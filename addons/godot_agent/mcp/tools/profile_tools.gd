@tool
extends RefCounted
## godot.profile_run (m13-27): corre una escena con el profiler de scripts prendido y devuelve las
## funciones de GDScript más calientes.
##
## El editor no le pasa los frames del profiler a los plugins: `servers:profile_frame` tiene handler
## propio en ScriptEditorDebugger y nunca llega a EditorDebuggerPlugin._capture. Pero ese nodo interno
## emite `debug_data(msg, data)` con cada mensaje antes de manejarlo: de ahí se leen. Es una API
## interna del editor; si un Godot la cambia, la tool contesta un error que lo explica y el resto del
## plugin sigue igual. Si EditorDebuggerSession llega a tener `debug_data` (propuesta upstream en
## tests/upstream/), se usa esa. El profiler se prende con la API pública (toggle_profiler).
##
## Usa el run_scene de RunTools (mismo arranque, inputs e informe) y su máquina GameRunState: no
## arranca si hay un run_scene en curso, prende el profiler solo en el juego que lanzó y lo apaga
## siempre al final, también si el run falla; un timer de seguridad lo apaga si la corrutina se corta.

const McpTool := preload("../mcp_tool.gd")
const PermissionPolicy := preload("../../session/permission_policy.gd")
const PlaytestDebugger := preload("../../playtest/playtest_debugger.gd")
const ScriptProfile := preload("../../playtest/script_profile.gd")
const RunTools := preload("run_tools.gd")

const INTERNAL_CLASS := "ScriptEditorDebugger"
const DATA_SIGNAL := &"debug_data"
const PROFILER := "servers"
const DEFAULT_TOP := 20
const MAX_TOP := 100
const DEFAULT_MAX_FUNCTIONS := 128
const MIN_MAX_FUNCTIONS := 16
const MAX_MAX_FUNCTIONS := 512
## Margen del timer de seguridad sobre lo que puede durar un run_scene.
const SAFETY_MARGIN_S := 30.0
const UNAVAILABLE := "profile_run can't read the script profiler in this Godot version: the editor doesn't pass profiler data to plugins, and the harness reads it from an internal editor class (%s and its `debug_data` signal) that wasn't found. Profile by hand in Debugger → Profiler, or run the scene with run_scene." % INTERNAL_CLASS

var run_tools: RunTools
var debugger: PlaytestDebugger

var _profiling: bool = false
## Cuenta los profile_run: el timer de seguridad de uno viejo no apaga el de uno nuevo.
var _run_id: int = 0
var _profile: ScriptProfile
var _options: Array = []
## La sesión en la que se prendió el profiler (-1: todavía no) y los emisores conectados.
var _session_id: int = -1
var _sources: Array[Object] = []


func setup(tools: RunTools, playtest_debugger: PlaytestDebugger) -> void:
	run_tools = tools
	debugger = playtest_debugger


func tools() -> Array:
	var run_tool_schema: Dictionary = {}
	for tool: McpTool in run_tools.tools():
		if tool.name == "run_scene":
			run_tool_schema = tool.input_schema.get("properties", {})
	return [
		McpTool.create("profile_run", PermissionPolicy.GROUP_RUN,
			"Runs a scene like run_scene with Godot's script profiler on, and returns the hottest GDScript functions by self time: path:line, calls, self and total ms per frame, share of script time, and whether the function is typed. Use it before optimizing (which function to touch) and after (did it help). The profiler slows every call, so compare functions with each other rather than trusting absolute times. Reads the profiler through an internal editor API: in a Godot version that changes it, it returns an error saying so.",
			{
				"scene": run_tool_schema.get("scene", {"type": "string"}),
				"seconds": {"type": "number", "description": "Seconds to profile after the game starts (default 5, max. %d)" % int(RunTools.MAX_SECONDS)},
				"inputs": run_tool_schema.get("inputs", {"type": "array"}),
				"continue_on_error": run_tool_schema.get("continue_on_error", {"type": "boolean"}),
				"top": {"type": "integer", "description": "How many functions to list (default %d, max. %d)" % [DEFAULT_TOP, MAX_TOP]},
				"max_functions": {"type": "integer", "description": "Functions the game reports per frame (default %d, %d–%d)" % [DEFAULT_MAX_FUNCTIONS, MIN_MAX_FUNCTIONS, MAX_MAX_FUNCTIONS]},
			},
			[], _profile_run),
	]


## De dónde leer los mensajes del juego: "public" (EditorDebuggerSession.debug_data), "internal"
## (ScriptEditorDebugger) o "" si no hay manera.
static func data_source() -> String:
	if ClassDB.class_has_signal(&"EditorDebuggerSession", DATA_SIGNAL):
		return "public"
	for node: Node in _internal_debuggers():
		if node.has_signal(DATA_SIGNAL):
			return "internal"
	return ""


static func _internal_debuggers() -> Array[Node]:
	return EditorInterface.get_base_control().find_children("*", INTERNAL_CLASS, true, false)


func _profile_run(args: Dictionary) -> Dictionary:
	if _profiling:
		return McpTool.error("A profile_run is already in progress: wait for it to finish.")
	if run_tools.is_busy():
		return McpTool.error("A run_scene is in progress (%s): wait for it to finish, then profile." % run_tools.describe_run_state())
	if data_source().is_empty():
		return McpTool.error(UNAVAILABLE)
	var top := clampi(McpTool.int_arg(args, "top", DEFAULT_TOP), 1, MAX_TOP)
	var max_functions := clampi(McpTool.int_arg(args, "max_functions", DEFAULT_MAX_FUNCTIONS), MIN_MAX_FUNCTIONS, MAX_MAX_FUNCTIONS)
	var run_args := {"seconds": args.get("seconds", 5.0)}
	for key: String in ["scene", "inputs", "continue_on_error"]:
		if args.has(key):
			run_args[key] = args[key]

	_profiling = true
	_run_id += 1
	_profile = ScriptProfile.new()
	_options = [max_functions, false]
	_session_id = -1
	debugger.session_started.connect(_on_session_started)
	var seconds := clampf(float(args.get("seconds", 5.0)), 0.1, RunTools.MAX_SECONDS)
	var safety := (Engine.get_main_loop() as SceneTree).create_timer(seconds + RunTools.STARTUP_TIMEOUT_S + RunTools.STOP_TIMEOUT_S + SAFETY_MARGIN_S)
	safety.timeout.connect(_on_safety_timeout.bind(_run_id))
	var ran: Dictionary = await run_tools.run_scene(run_args)
	var profile := _profile
	var armed := _session_id >= 0
	_finish_profiling()

	var run_text := "\n".join((ran.get("content", []) as Array).map(func(block: Dictionary) -> String: return str(block.get("text", ""))))
	if ran.get("isError", false):
		return McpTool.error(run_text)
	if not armed or profile == null:
		return McpTool.error("The profiler could not be started: the game's debugger session did not show up.\n\nRun:\n" + run_text)
	return McpTool.text(profile.report(top) + "\n\nRun:\n" + run_text)


## El juego que lanzó run_scene abrió su sesión: se escuchan sus mensajes y se prende el profiler.
## Un juego que arranca sin que run_scene lo haya lanzado (un run manual) no se toca.
func _on_session_started() -> void:
	if not _profiling or _session_id >= 0 or run_tools.run_state != RunTools.GameRunState.STARTED or not run_tools.is_busy():
		return
	var session_id := debugger.active_session_id()
	if session_id < 0:
		return
	var session := debugger.get_session(session_id)
	if session.has_signal(DATA_SIGNAL):
		_listen(session)
	else:
		var internal := _internal_debuggers().filter(func(node: Node) -> bool: return node.has_signal(DATA_SIGNAL))
		# El nodo de la sesión es la pestaña con su índice en el panel Debugger; con una sola, esa.
		for node: Node in internal:
			if node.get_index() == session_id or internal.size() == 1:
				_listen(node)
				break
	if _sources.is_empty():
		return
	_session_id = session_id
	session.toggle_profiler(PROFILER, true, _options)


func _listen(source: Object) -> void:
	source.connect(DATA_SIGNAL, _on_debug_data)
	_sources.append(source)


func _on_debug_data(message: String, data: Array) -> void:
	if _profile == null:
		return
	match message:
		"servers:function_signature":
			_profile.add_signature(data)
		"servers:profile_frame":
			_profile.add_frame(data)


func _on_safety_timeout(run_id: int) -> void:
	if run_id == _run_id:
		_finish_profiling()


## Apaga el profiler si el juego sigue vivo y suelta todo. Se puede llamar varias veces (fin normal,
## timer de seguridad, plugin que se deshabilita).
func _finish_profiling() -> void:
	if not _profiling:
		return
	_profiling = false
	if debugger and debugger.session_started.is_connected(_on_session_started):
		debugger.session_started.disconnect(_on_session_started)
	if _session_id >= 0 and debugger:
		var session := debugger.get_session(_session_id)
		if session and session.is_active():
			session.toggle_profiler(PROFILER, false, [])
	for source: Object in _sources:
		if is_instance_valid(source) and source.is_connected(DATA_SIGNAL, _on_debug_data):
			source.disconnect(DATA_SIGNAL, _on_debug_data)
	_sources = []
	_session_id = -1
	_profile = null


## Para el plugin al deshabilitarse.
func shutdown() -> void:
	_finish_profiling()
