@tool
extends "mcp_check.gd"
## m13-27: godot.profile_run por HTTP real, sobre tests/fixtures/profile_fixture.tscn (`_hot` llama
## 2000 veces por frame a `_step`). Corre después de profile_check.gd con el mismo flag:
## - el informe trae frames y descartados, `_step` y `_hot` con ruta:línea del func, llamadas por
##   frame, tipado leído del script, la nota del overhead y el informe del run;
## - al terminar, el juego sigue corriendo pero el profiler quedó apagado (no llegan más frames);
## - no arranca con un run_scene en curso (GameRunState);
## - con un juego que se frena en el debugger, contesta y no queda perfilando.

const SessionModel := preload("res://addons/godot_agent/session/session_model.gd")
const ScriptProfile := preload("res://addons/godot_agent/playtest/script_profile.gd")
const DOCK_SCRIPT := "res://addons/godot_agent/ui/dock/agent_dock.gd"
const MAIN_PLUGIN := "res://addons/godot_agent/plugin.gd"
const SCENE := "res://tests/fixtures/profile_fixture.tscn"
const FIXTURE_SCRIPT := "res://tests/fixtures/profile_fixture.gd"
const BROKEN_SCENE := "res://tests/fixtures/run_broken.tscn"
const RUN_SCENE := "res://tests/fixtures/run_fixture.tscn"
const RUN_ARGS_ENV := "GODOT_AGENT_TEST_RUN_ARGS"
const RUN_ARGS_SETTING := "editor/run/main_run_args"

var report: Dictionary = {}
var _profile_tools: Object
var _late_frames: int = 0
var _background_done: bool = false


func run_profile_tool(tree: SceneTree) -> PackedStringArray:
	_tree = tree
	var model: Object
	var plugin_config: Object
	for node: Node in tree.root.find_children("*", "Node", true, false):
		var script := node.get_script() as Script
		if script and script.resource_path == SERVER_SCRIPT:
			_server = node
		elif script and script.resource_path == DOCK_SCRIPT:
			model = node.get(&"_model")
		elif script and script.resource_path == MAIN_PLUGIN:
			plugin_config = node.get(&"_project_config")
			_profile_tools = node.get(&"_profile_tools")
	if _server == null or model == null or _profile_tools == null:
		failures.append("no se encontró el server, el modelo o ProfileTools")
		return failures
	var previous_args: Variant = ProjectSettings.get_setting(RUN_ARGS_SETTING, "")
	if not OS.get_environment(RUN_ARGS_ENV).is_empty():
		ProjectSettings.set_setting(RUN_ARGS_SETTING, OS.get_environment(RUN_ARGS_ENV))
	var manual_runs: bool = plugin_config.get(&"playtest_on_manual_runs") if plugin_config else false
	if plugin_config:
		plugin_config.set(&"playtest_on_manual_runs", false)
	await _check(model)
	if EditorInterface.is_playing_scene():
		EditorInterface.stop_playing_scene()
	if plugin_config:
		plugin_config.set(&"playtest_on_manual_runs", manual_runs)
	ProjectSettings.set_setting(RUN_ARGS_SETTING, previous_args)
	ProjectSettings.save()
	print("[profile-tool-check] ", JSON.stringify(report))
	return failures


func _check(model: Object) -> void:
	await _rpc("initialize", {"protocolVersion": "2025-06-18", "capabilities": {}, "clientInfo": {"name": "profile-check", "version": "1"}})
	model.call(&"set_harness_mode", SessionModel.HarnessMode.ONESHOT)
	# Es extendida: con tools/list compacto se descubre por godot.methods.
	var methods := await _call_text("methods", {"query": "profile"})
	_expect(methods.contains("profile_run"), "godot.methods lista profile_run · " + methods.left(300))

	var text := await _call_text("profile_run", {"scene": SCENE, "seconds": 2, "top": 5})
	report.first_lines = text.split("\n").slice(0, 4)
	report.run_part = text.substr(text.find("\n\nRun:\n")).left(600)
	var counts := RegEx.create_from_string("Script profile: (\\d+) frames \\((\\d+) discarded").search(text)
	_expect(counts != null and int(counts.get_string(1)) >= 30 and int(counts.get_string(2)) >= 1, "frames agregados y el primero descartado · " + text.left(300))
	_expect(text.contains("%s:32 _step — 2000.0 calls" % FIXTURE_SCRIPT), "_step con la línea del func y 2000 llamadas por frame · " + text.left(900))
	_expect(text.contains("%s:27 _hot — 1.0 calls" % FIXTURE_SCRIPT), "_hot con una llamada por frame")
	_expect(RegEx.create_from_string("_step — [^\\n]*typed: yes").search(text) != null, "tipado leído del script")
	_expect(text.contains(ScriptProfile.OVERHEAD_NOTE), "la nota del overhead")
	_expect(text.contains("\n\nRun:\n%s: ran for 2.0 s" % SCENE), "el informe del run")
	_expect(not bool(_profile_tools.get(&"_profiling")), "terminó de perfilar")

	# El juego sigue (como con run_scene) pero el profiler quedó apagado.
	_expect(EditorInterface.is_playing_scene(), "el juego sigue corriendo")
	# Los frames que ya venían en camino cuando se apagó siguen llegando un momento.
	await _tree.create_timer(0.5).timeout
	var debuggers := EditorInterface.get_base_control().find_children("*", "ScriptEditorDebugger", true, false)
	for dbg: Node in debuggers:
		dbg.connect(&"debug_data", _on_debug_data)
	await _tree.create_timer(1.0).timeout
	for dbg: Node in debuggers:
		dbg.disconnect(&"debug_data", _on_debug_data)
	report.frames_after = _late_frames
	_expect(_late_frames == 0, "con el profiler apagado no llegan frames (%d)" % _late_frames)
	await _call_text("stop_scene", {})

	# Con un run_scene en curso, no arranca (y no lo interrumpe).
	_background_run_scene()
	await _tree.create_timer(0.3).timeout
	var busy: Dictionary = await _call("profile_run", {"scene": SCENE, "seconds": 1})
	_expect(busy.get("isError", false) and _text(busy).contains("A run_scene is in progress (game:"), "rechaza con un run_scene en curso · " + _text(busy).left(200))
	var deadline := Time.get_ticks_msec() + 30000
	while not _background_done and Time.get_ticks_msec() < deadline:
		await _tree.process_frame
	_expect(_background_done, "el run_scene de fondo terminó")
	await _call_text("stop_scene", {})

	# Un juego que se frena en el debugger antes del primer frame: contesta y suelta el profiler.
	var broken := await _call_text("profile_run", {"scene": BROKEN_SCENE, "seconds": 2})
	_expect(broken.contains("No usable profiler frames") and broken.contains("stopped in the debugger"), "juego frenado: lo dice · " + broken.left(400))
	_expect(not bool(_profile_tools.get(&"_profiling")), "y no queda perfilando")
	await _call_text("stop_scene", {})


## Un run_scene que corre mientras el check sigue (se llama sin await).
func _background_run_scene() -> void:
	await _call("run_scene", {"scene": RUN_SCENE, "seconds": 2})
	_background_done = true


func _on_debug_data(message: String, _data: Array) -> void:
	if message == "servers:profile_frame":
		_late_frames += 1
