@tool
extends RefCounted
## El debugger de scripts como tools (m11-56): breakpoints del agente, la pila y las variables del
## juego parado, y continue/step.
##
## - Los breakpoints del agente van aparte de los del usuario (los del editor de scripts, que el
##   editor manda al juego al arrancarlo): cada línea lleva las sesiones que la pusieron, y en el
##   juego se apaga cuando no la quiere ninguna ni el usuario. El agente no puede sacar uno del usuario.
## - Solo van a los juegos que lanza el harness (run_scene, regresiones…), no a los que el usuario
##   corre con F5/F6: ahí pararían en líneas sin marca en el margen (revisión de next2 #14b).
## - La pila la arma el probe dentro del bucle del debugger (DebugStack), así que necesita un juego
##   con el probe (run_scene). game_debug no: alcanza con un juego parado.
## - Si la sesión que puso los breakpoints se cierra, `release_session` los saca y, si el juego quedó
##   parado por uno que se apagó o por un paso de esa sesión (aunque el paso aterrice después), lo
##   deja seguir.

const McpTool := preload("../mcp_tool.gd")
const PermissionPolicy := preload("../../session/permission_policy.gd")
const PlaytestDebugger := preload("../../playtest/playtest_debugger.gd")
const UntrustedText := preload("../untrusted_text.gd")
const RunTools := preload("run_tools.gd")

const STACK_TIMEOUT_S := 3.0
## Cuánto espera game_debug a que el juego vuelva a parar (un step) antes de decir que sigue.
const REBREAK_WAIT_S := 1.5
## Cuántos frames espera release_session a que el panel del debugger diga por qué paró.
const REASON_WAIT_FRAMES := 30
const ACTIONS: PackedStringArray = ["continue", "step", "next", "out"]
## game_stack con un juego parado sin el probe (no lo tiene, o paró antes de que cargue: es el último
## autoload) o parado en otra instancia que la del probe.
const NO_PROBE_STACK := "The game is stopped in the debugger, but not one with the playtest probe connected (a manual run without it, or it stopped before the probe loaded: the probe is the last autoload). game_stack needs the probe; game_debug can still continue or step it."
const NO_FRAMES := "No game frames on the stack."
const OTHER_THREAD := "If it stopped in a Thread or a WorkerThreadPool task, it can't be seen or stepped from here: the user can pick the thread in the Debugger panel."
const NOT_STOPPED := "The game is not stopped in the debugger (state: %s). It stops at a breakpoint (game_breakpoint) or at an error."

## RunTools: estado del juego y pedidos al probe.
var run_tools: RefCounted
## PlaytestDebugger (sin tipo: los tests usan uno falso, EditorDebuggerPlugin no se crea sin editor).
var debugger: RefCounted
## Callable() -> String: la sesión que llama (registry.current_caller).
var caller: Callable = func() -> String: return ""
## Callable() -> PackedStringArray: los breakpoints del usuario, «res://a.gd:12» (ScriptEditor).
var user_breakpoints: Callable = func() -> PackedStringArray: return PackedStringArray()
## Callable() -> String: motivo y lugar de la pausa (PlaytestDebugger.break_reason).
var break_reason: Callable = PlaytestDebugger.break_reason

## «res://a.gd:12» -> PackedStringArray de las sesiones que lo pusieron.
var breakpoints: Dictionary = {}
## Las sesiones del debugger de juegos que lanzó el harness: id -> true.
var _harness_sessions: Dictionary = {}
## La sesión que dejó al juego en una pausa con un paso (step/next/out); "" = ninguna.
var _stepped_by: String = ""
var _has_stepper: bool = false
## Un paso mandado que todavía no paró el juego (puede quedar armado hasta la próxima línea de
## GDScript que corra): la sesión que lo pidió se vuelve dueña de esa pausa cuando llega.
var _pending_step_by: String = ""
var _has_pending_step: bool = false
## La sesión del paso pendiente se cerró: la pausa en que aterrice se continúa.
var _release_next_break: bool = false
## Pausas vistas (señal breaked): un step sale y vuelve a parar, a veces en el mismo frame del editor.
var _break_count: int = 0


func setup(tools: RefCounted, playtest_debugger: RefCounted) -> void:
	run_tools = tools
	debugger = playtest_debugger
	debugger.session_started_id.connect(_on_session_started)
	debugger.session_continued.connect(_on_continued)
	debugger.session_breaked.connect(_on_breaked)
	debugger.session_stopped_id.connect(_on_session_stopped)


func tools() -> Array:
	var run := PermissionPolicy.GROUP_RUN
	var read := PermissionPolicy.GROUP_READ
	return [
		McpTool.create("game_breakpoint", run,
			"Sets, clears or lists your breakpoints in the game's GDScript. When a game you launched (run_scene) reaches one it stops in the debugger: then game_stack shows where and the variables, and game_debug continues or steps. They stay for the next runs of this session, but not for games the user runs with F5; ones set before the game starts reach it a moment after launch, so code in its first frame may run before them. The user's breakpoints from the script editor also stop the game; you can't clear those. Only the main thread: code in a Thread or a WorkerThreadPool task that stops can't be seen or stepped from here.",
			{
				"action": {"type": "string", "enum": ["set", "clear", "clear_all", "list"]},
				"file": {"type": "string", "description": "res://…gd"},
				"line": {"type": "integer", "description": "Line number, from 1 as in the script editor"},
			}, ["action"], _breakpoint),
		McpTool.enveloped(McpTool.create("game_stack", read,
			"While the running game is stopped in the debugger (a breakpoint or an error): the call stack (file, line, function; #0 is where it stopped) and the local and member variables of one frame. Values are shortened: nodes with their path, collections with their size and first items.",
			{
				"frame": {"type": "integer", "description": "Which frame's variables (default 0)"},
				"variables": {"type": "boolean", "description": "false: only the stack (default true)"},
			}, [], _stack), McpTool.ENVELOPE_PARTS),
		McpTool.enveloped(McpTool.create("game_debug", run,
			"Resumes the game stopped in the debugger (also one without the playtest probe): continue (until the next breakpoint or error), step (into calls), next (over calls) or out (until the current function returns). If it stops again it says where.",
			{"action": {"type": "string", "enum": Array(ACTIONS)}}, ["action"], _debug), McpTool.ENVELOPE_PARTS),
	]


# --- breakpoints -------------------------------------------------------------------------------

func _breakpoint(args: Dictionary) -> Dictionary:
	var action := McpTool.str_arg(args, "action")
	var who := str(caller.call())
	match action:
		"list":
			return McpTool.text(_list(who))
		"clear_all":
			var mine := _owned_by(who)
			for key: String in mine:
				_remove(key, who)
			return McpTool.text("Cleared %d breakpoint%s." % [mine.size(), "" if mine.size() == 1 else "s"])
	var file := McpTool.str_arg(args, "file")
	var line := McpTool.int_arg(args, "line", 0)
	if not file.begins_with("res://") or not file.ends_with(".gd"):
		return McpTool.error("`file` must be a res://…gd script.")
	if not FileAccess.file_exists(file):
		return McpTool.error("%s does not exist." % file)
	var line_count := FileAccess.get_file_as_string(file).count("\n") + 1
	if line < 1 or line > line_count:
		return McpTool.error("`line` must be between 1 and %d in %s." % [line_count, file])
	var key := "%s:%d" % [file, line]
	if action == "set":
		var owners: PackedStringArray = breakpoints.get_or_add(key, PackedStringArray())
		if not who in owners:
			owners.append(who)
			breakpoints[key] = owners
		var sent := _send(key, true)
		var where := "the running game has it now" if sent > 0 else "no game you launched is running: it reaches the next one run_scene launches"
		return McpTool.text("Breakpoint set at %s (%s; games the user runs with F5 don't get it)." % [key, where])
	if not who in _owners(key):
		if key in _user_set():
			return McpTool.error("The breakpoint at %s is the user's (from the script editor): only they can clear it." % key)
		return McpTool.error("There is no breakpoint of yours at %s. %s" % [key, _list(who)])
	_remove(key, who)
	return McpTool.text("Cleared the breakpoint at %s." % key)


func _list(who: String) -> String:
	var lines: PackedStringArray = []
	var mine := _owned_by(who)
	lines.append("Your breakpoints: %s" % (", ".join(mine) if not mine.is_empty() else "none"))
	var users := _user_set()
	if not users.is_empty():
		lines.append("The user's (script editor, they also stop the game): %s" % ", ".join(users))
	return "\n".join(lines)


func _owned_by(who: String) -> PackedStringArray:
	var keys := PackedStringArray()
	for key: String in breakpoints:
		if who in _owners(key):
			keys.append(key)
	keys.sort()
	return keys


func _owners(key: String) -> PackedStringArray:
	return breakpoints.get(key, PackedStringArray()) as PackedStringArray


func _user_set() -> PackedStringArray:
	return user_breakpoints.call() as PackedStringArray


## Saca el de `who`. En el juego se apaga solo si no lo quiere otra sesión ni el usuario: devuelve
## si se apagó.
func _remove(key: String, who: String) -> bool:
	var owners := _owners(key)
	var at := owners.find(who)
	if at >= 0:
		owners.remove_at(at)
	if not owners.is_empty():
		breakpoints[key] = owners
		return false
	breakpoints.erase(key)
	if key in _user_set():
		return false
	_send(key, false)
	return true


## Prende o apaga `key` en los juegos del harness que corren. Devuelve a cuántos se mandó.
func _send(key: String, enabled: bool) -> int:
	var colon := key.rfind(":")
	for session_id: int in _harness_sessions:
		debugger.set_session_breakpoint(session_id, key.left(colon), int(key.substr(colon + 1)), enabled)
	return _harness_sessions.size()


## Un juego que lanzó el harness recibe los breakpoints del agente (los del usuario ya los manda el
## editor); uno que el usuario corre con F5/F6, no (revisión de next2 #14b).
func _on_session_started(session_id: int) -> void:
	if not _harness_launch():
		return
	_harness_sessions[session_id] = true
	for key: String in breakpoints:
		var colon := key.rfind(":")
		debugger.set_session_breakpoint(session_id, key.left(colon), int(key.substr(colon + 1)), true)


## La sesión que arranca es de un juego del harness. RunTools puede atender el `started` antes o
## después que acá: LAUNCHING (todavía no) o harness_run con el juego corriendo (ya; también la
## segunda instancia de «Run Multiple Instances»).
func _harness_launch() -> bool:
	var state: int = run_tools.get(&"run_state")
	if state == RunTools.GameRunState.LAUNCHING:
		return true
	return bool(run_tools.get(&"harness_run")) and state in [RunTools.GameRunState.STARTED, RunTools.GameRunState.PROBE_READY, RunTools.GameRunState.BREAKED]


func _on_session_stopped(session_id: int) -> void:
	_harness_sessions.erase(session_id)
	if not debugger.has_game():
		_clear_step()


## El usuario sacó del margen una línea que el agente también tiene: el editor la apagó en todos los
## juegos; en los del harness se vuelve a prender (lo conecta el plugin a breakpoint_toggled del
## EditorDebuggerNode, que se emite después de mandarla). `line` desde 1.
func on_user_breakpoint_toggled(path: String, line: int, enabled: bool) -> void:
	var key := "%s:%d" % [path, line]
	if not enabled and not _owners(key).is_empty():
		_send(key, true)


# --- pila y pasos ------------------------------------------------------------------------------

## "" si algún juego está parado en el debugger; si no, el error para el agente.
func _not_stopped() -> String:
	if not debugger.any_breaked():
		if not debugger.has_game():
			return "No game is running. " + NOT_STOPPED.get_slice(". ", 1)
		return NOT_STOPPED % run_tools.call(&"describe_run_state")
	return ""


func _stack(args: Dictionary) -> Dictionary:
	if not _not_stopped().is_empty():
		return McpTool.error(_not_stopped())
	if not debugger.is_breaked():
		return McpTool.error(NO_PROBE_STACK)
	var reply: Dictionary = await run_tools.call(&"request", "stack", {"frame": McpTool.int_arg(args, "frame", 0), "variables": args.get("variables", true) != false}, STACK_TIMEOUT_S, true)
	if reply.has("error"):
		var error := UntrustedText.wrap(str(reply.error))
		if str(reply.error) == NO_FRAMES:
			error += " " + OTHER_THREAD
		return McpTool.error(error)
	var lines: PackedStringArray = []
	var reason := str(break_reason.call())
	if not reason.is_empty():
		lines.append("Stopped: " + UntrustedText.wrap(reason))
	lines.append(UntrustedText.wrap(str(reply.get("text", ""))))
	return McpTool.text("\n".join(lines))


func _debug(args: Dictionary) -> Dictionary:
	var action := McpTool.str_arg(args, "action")
	if not _not_stopped().is_empty():
		return McpTool.error(_not_stopped())
	var who := str(caller.call())
	var stepping := action != "continue"
	var breaks_before := _break_count
	# El paso se anota antes de mandarlo (revisión de next2 #14d): si la sesión se cierra mientras
	# espera, release_session lo ve; y si no aterriza en REBREAK_WAIT_S (queda armado), la pausa en
	# que aterrice después sigue siendo de esta sesión.
	_has_pending_step = stepping
	_pending_step_by = who if stepping else ""
	if not debugger.debug_command(action):
		_has_pending_step = false
		_pending_step_by = ""
		return McpTool.error(_not_stopped())
	var tree := Engine.get_main_loop() as SceneTree
	var deadline := Time.get_ticks_msec() + int(REBREAK_WAIT_S * 1000.0)
	while Time.get_ticks_msec() < deadline and _break_count == breaks_before and debugger.has_game():
		await tree.process_frame
	if _break_count > breaks_before and debugger.any_breaked():
		if not debugger.is_breaked():
			return McpTool.text("Stopped again (%s). game_stack needs the playtest probe, which this game doesn't have connected." % action)
		var where: Dictionary = await run_tools.call(&"request", "stack", {"variables": false}, STACK_TIMEOUT_S, true)
		var top := str(where.get("text", "")).get_slice("\n", 1)
		return McpTool.text("Stopped again (%s): %s. game_stack shows the variables." % [action, UntrustedText.wrap(top)])
	if not debugger.has_game():
		return McpTool.text("The game ended.")
	if stepping:
		return McpTool.text("The game is running again (%s): the step stops it at the next line of GDScript that runs, maybe later." % action)
	return McpTool.text("The game is running again (%s)." % action)


func _on_breaked() -> void:
	_break_count += 1
	if _release_next_break:
		# Aterrizó el paso de una sesión que ya se cerró: el juego sigue.
		_release_next_break = false
		_has_pending_step = false
		_pending_step_by = ""
		debugger.debug_command("continue")
		return
	if _has_pending_step:
		_stepped_by = _pending_step_by
		_has_stepper = true
		_has_pending_step = false
		_pending_step_by = ""


func _on_continued() -> void:
	_has_stepper = false
	_stepped_by = ""


func _clear_step() -> void:
	_has_stepper = false
	_stepped_by = ""
	_has_pending_step = false
	_pending_step_by = ""
	_release_next_break = false


# --- sesiones que se cierran -------------------------------------------------------------------

## La sesión `who` se cerró (el plugin escucha su `disconnected`): saca sus breakpoints y, si el
## juego quedó parado por uno de ellos o por un paso suyo, lo deja seguir. Devuelve los que sacó.
func release_session(who: String) -> PackedStringArray:
	var released := _owned_by(who)
	# Solo cuentan las que se apagaron en el juego: si otra sesión o el usuario tiene la misma línea,
	# la pausa es también suya (revisión de next2 #14a, #19).
	var turned_off := PackedStringArray()
	for key: String in released:
		if _remove(key, who):
			turned_off.append(key)
	if _has_pending_step and _pending_step_by == who:
		_has_pending_step = false
		_pending_step_by = ""
		_release_next_break = true
	var stepped := _has_stepper and _stepped_by == who
	# El panel del debugger escribe el motivo unos frames después de la pausa.
	var reason := str(break_reason.call())
	var tree := Engine.get_main_loop() as SceneTree
	for frame in REASON_WAIT_FRAMES:
		if not reason.is_empty() or stepped or turned_off.is_empty() or not debugger.any_breaked():
			break
		await tree.process_frame
		reason = str(break_reason.call())
	if debugger.any_breaked() and (stepped or stopped_at_any(reason, turned_off)):
		_has_stepper = false
		_stepped_by = ""
		debugger.debug_command("continue")
	return released


## Si el motivo de la pausa («Breakpoint (0 - res://a.gd:12 - at function: f)») es uno de `keys`. El
## lugar es la última ruta del texto (la pila va al final, después del mensaje); la ruta puede tener
## espacios o paréntesis (revisión de next2 #19).
static func stopped_at_any(reason: String, keys: PackedStringArray) -> bool:
	var found := RegEx.create_from_string("(res://.+?\\.gd):(\\d+)").search_all(reason)
	if found.is_empty():
		return false
	var last: RegExMatch = found.back()
	return ("%s:%s" % [last.get_string(1), last.get_string(2)]) in keys
