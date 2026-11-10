@tool
extends RefCounted
## El debugger de scripts como tools (m11-56): breakpoints del agente, la pila y las variables del
## juego parado, y continue/step.
##
## - Los breakpoints del agente van aparte de los del usuario (los del editor de scripts, que el
##   editor manda al juego al arrancarlo): se marcan con la sesión que los puso, se mandan a cada
##   juego que arranca y el agente no puede sacar uno del usuario. Si el usuario tiene uno en la
##   misma línea, sacar el del agente no lo apaga en el juego.
## - La pila la arma el probe dentro del bucle del debugger (DebugStack), así que necesita un juego
##   con el probe (run_scene).
## - Si la sesión que puso los breakpoints se cierra, `release_session` los saca y, si el juego quedó
##   parado por uno de ellos o por un paso de esa sesión, lo deja seguir.

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

## «res://a.gd:12» -> sesión que lo puso.
var breakpoints: Dictionary = {}
## La sesión que dejó al juego en una pausa con un paso (step/next/out); "" = ninguna.
var _stepped_by: String = ""
var _has_stepper: bool = false
## Pausas vistas (señal breaked): un step sale y vuelve a parar, a veces en el mismo frame del editor.
var _break_count: int = 0


func setup(tools: RefCounted, playtest_debugger: RefCounted) -> void:
	run_tools = tools
	debugger = playtest_debugger
	debugger.session_started_id.connect(_on_session_started)
	debugger.session_continued.connect(_on_continued)
	debugger.session_breaked.connect(_on_breaked)


func tools() -> Array:
	var run := PermissionPolicy.GROUP_RUN
	var read := PermissionPolicy.GROUP_READ
	return [
		McpTool.create("game_breakpoint", run,
			"Sets, clears or lists your breakpoints in the game's GDScript. When the running game reaches one it stops in the debugger: then game_stack shows where and the variables, and game_debug continues or steps. They stay for the next runs of this session; ones set before the game starts reach it a moment after launch, so code in its first frame may run before them. The user's breakpoints from the script editor also stop the game; you can't clear those.",
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
			"Resumes the game stopped in the debugger: continue (until the next breakpoint or error), step (into calls), next (over calls) or out (until the current function returns). If it stops again it says where.",
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
				_remove(key)
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
		breakpoints[key] = who
		debugger.set_breakpoint(file, line, true)
		var running := "" if debugger.has_probe() else " It will be sent to the game when it starts."
		return McpTool.text("Breakpoint set at %s.%s" % [key, running])
	if breakpoints.get(key) != who:
		if not breakpoints.has(key) and key in _user_set():
			return McpTool.error("The breakpoint at %s is the user's (from the script editor): only they can clear it." % key)
		return McpTool.error("There is no breakpoint of yours at %s. %s" % [key, _list(who)])
	_remove(key)
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
		if breakpoints[key] == who:
			keys.append(key)
	keys.sort()
	return keys


func _user_set() -> PackedStringArray:
	return user_breakpoints.call() as PackedStringArray


## Saca uno del agente; en el juego solo si el usuario no tiene uno en la misma línea.
func _remove(key: String) -> void:
	breakpoints.erase(key)
	if key in _user_set():
		return
	var colon := key.rfind(":")
	debugger.set_breakpoint(key.left(colon), int(key.substr(colon + 1)), false)


## Un juego que arranca recibe los breakpoints del agente (los del usuario ya los manda el editor).
func _on_session_started(session_id: int) -> void:
	for key: String in breakpoints:
		var colon := key.rfind(":")
		debugger.set_session_breakpoint(session_id, key.left(colon), int(key.substr(colon + 1)))


# --- pila y pasos ------------------------------------------------------------------------------

## "" si el juego del probe está parado en el debugger; si no, el error para el agente.
func _not_stopped() -> String:
	if not debugger.has_probe():
		return RunTools.NO_PROBE
	if not debugger.is_breaked():
		return NOT_STOPPED % run_tools.call(&"describe_run_state")
	return ""


func _stack(args: Dictionary) -> Dictionary:
	if not _not_stopped().is_empty():
		return McpTool.error(_not_stopped())
	var reply: Dictionary = await run_tools.call(&"request", "stack", {"frame": McpTool.int_arg(args, "frame", 0), "variables": args.get("variables", true) != false}, STACK_TIMEOUT_S, true)
	if reply.has("error"):
		return McpTool.error(UntrustedText.wrap(str(reply.error)))
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
	if not debugger.debug_command(action):
		return McpTool.error(_not_stopped())
	var tree := Engine.get_main_loop() as SceneTree
	var deadline := Time.get_ticks_msec() + int(REBREAK_WAIT_S * 1000.0)
	while Time.get_ticks_msec() < deadline and _break_count == breaks_before and debugger.has_probe():
		await tree.process_frame
	if _break_count > breaks_before and debugger.is_breaked():
		if stepping:
			_stepped_by = who
			_has_stepper = true
		var where: Dictionary = await run_tools.call(&"request", "stack", {"variables": false}, STACK_TIMEOUT_S, true)
		var top := str(where.get("text", "")).get_slice("\n", 1)
		return McpTool.text("Stopped again (%s): %s. game_stack shows the variables." % [action, UntrustedText.wrap(top)])
	if not debugger.has_probe():
		return McpTool.text("The game ended.")
	return McpTool.text("The game is running again (%s)." % action)


func _on_breaked() -> void:
	_break_count += 1


func _on_continued() -> void:
	_has_stepper = false
	_stepped_by = ""


# --- sesiones que se cierran -------------------------------------------------------------------

## La sesión `who` se cerró (el plugin escucha su `disconnected`): saca sus breakpoints y, si el
## juego quedó parado por uno de ellos o por un paso suyo, lo deja seguir. Devuelve los que sacó.
func release_session(who: String) -> PackedStringArray:
	var released := _owned_by(who)
	for key: String in released:
		_remove(key)
	var stepped := _has_stepper and _stepped_by == who
	# El panel del debugger escribe el motivo unos frames después de la pausa.
	var reason := str(break_reason.call())
	var tree := Engine.get_main_loop() as SceneTree
	for frame in REASON_WAIT_FRAMES:
		if not reason.is_empty() or stepped or released.is_empty() or not debugger.is_breaked():
			break
		await tree.process_frame
		reason = str(break_reason.call())
	if debugger.is_breaked() and (stepped or stopped_at_any(reason, released)):
		_has_stepper = false
		_stepped_by = ""
		debugger.debug_command("continue")
	return released


## Si el motivo de la pausa («Breakpoint (res://a.gd:12 in f)») es uno de `keys`.
static func stopped_at_any(reason: String, keys: PackedStringArray) -> bool:
	var found := RegEx.create_from_string("(res://[^\\s:()]+\\.gd):(\\d+)").search(reason)
	return found != null and ("%s:%s" % [found.get_string(1), found.get_string(2)]) in keys
