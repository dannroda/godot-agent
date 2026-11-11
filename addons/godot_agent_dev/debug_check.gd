@tool
extends "mcp_check.gd"
## m11-56: game_breakpoint, game_stack y game_debug por HTTP real, sobre
## tests/fixtures/debug_fixture.tscn (`_process` → `_tick` → `_add`, breakpoint en `_add`):
## - sin juego: game_stack dice que no hay probe; el breakpoint puesto antes llega al arrancar;
## - run_scene para en el breakpoint y lo dice como breakpoint, no como error;
## - game_stack: la pila del juego (sin frames del addon), locales y miembros, otro frame;
## - game_debug next para en la línea siguiente; continue vuelve a parar en el breakpoint;
## - sacar el breakpoint y continue: el juego vuelve a correr (GameRunState en PROBE_READY);
## - si la sesión que lo puso se cierra con el juego parado ahí, el breakpoint se va y el juego sigue.

const SessionModel := preload("res://addons/godot_agent/session/session_model.gd")
const DOCK_SCRIPT := "res://addons/godot_agent/ui/dock/agent_dock.gd"
const MAIN_PLUGIN := "res://addons/godot_agent/plugin.gd"
const SCENE := "res://tests/fixtures/debug_fixture.tscn"
const SCRIPT := "res://tests/fixtures/debug_fixture.gd"
const BREAK_LINE := 21
const LATE_LINE := 28
const RUN_ARGS_ENV := "GODOT_AGENT_TEST_RUN_ARGS"
const RUN_ARGS_SETTING := "editor/run/main_run_args"

var report: Dictionary = {}
var _plugin: Node
var _debugger: Object


func run_debug(tree: SceneTree) -> PackedStringArray:
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
			_plugin = node
			plugin_config = node.get(&"_project_config")
			_debugger = node.get(&"_playtest_debugger")
	if _server == null or model == null or _plugin == null or _plugin.get(&"_debug_tools") == null:
		failures.append("no se encontró el server, el modelo o DebugTools")
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
	print("[debug-check] ", JSON.stringify(report))
	return failures


func _check(model: Object) -> void:
	await _rpc("initialize", {"protocolVersion": "2025-06-18", "capabilities": {}, "clientInfo": {"name": "debug-check", "version": "1"}})
	model.call(&"set_harness_mode", SessionModel.HarnessMode.ONESHOT)
	var methods := await _call_text("methods", {"query": "breakpoint"})
	_expect(methods.contains("game_breakpoint"), "godot.methods lista game_breakpoint · " + methods.left(300))

	var idle: Dictionary = await _call("game_stack", {})
	_expect(idle.get("isError", false) and _text(idle).begins_with("No game is running."), "sin juego: lo dice · " + _text(idle).left(200))
	var set := await _call_text("game_breakpoint", {"action": "set", "file": SCRIPT, "line": BREAK_LINE})
	_expect(set.contains("reaches the next one run_scene launches"), "antes del juego: llega al próximo run_scene · " + set)
	_expect(_plugin.call(&"_editor_debugger_node") != null, "el EditorDebuggerNode tiene breakpoint_toggled (los del usuario que el agente también tiene, revisión de next2 #19)")

	var ran := await _call_text("run_scene", {"scene": SCENE, "seconds": 3})
	report.run = ran.left(400)
	_expect(ran.contains("stopped at a breakpoint") and ran.contains("%s:%d" % [SCRIPT, BREAK_LINE]), "run_scene para en el breakpoint y lo dice · " + ran.left(400))
	_expect(_run_state().contains("stopped in the debugger"), "BREAKED · " + _run_state())
	# Revisión de next2 #21: otra tool del juego con la pausa en un breakpoint lo dice así, no como error.
	var blocked: Dictionary = await _call("game_tree", {})
	_expect(blocked.get("isError", false) and _text(blocked).contains("stopped at a breakpoint") and _text(blocked).contains("game_debug"), "parado en un breakpoint: las tools del juego lo dicen · " + _text(blocked).left(300))

	var stack := await _call_text("game_stack", {})
	report.stack = stack.left(900)
	_expect(stack.contains("Stopped: <untrusted") and stack.contains("<untrusted nonce="), "en sobre · " + stack.left(200))
	_expect(stack.contains("#0 %s:%d in _add()" % [SCRIPT, BREAK_LINE]), "#0 es el breakpoint · " + stack.left(600))
	_expect(stack.contains("#1 %s:17 in _tick()" % SCRIPT) and stack.contains("#2 %s:12 in _process()" % SCRIPT), "los que lo llamaron · " + stack.left(600))
	_expect(not stack.contains("res://addons/godot_agent/"), "sin frames del addon")
	_expect(stack.contains("Locals (") and RegEx.create_from_string("\\n  a = \\d+").search(stack) != null and RegEx.create_from_string("\\n  b = \\d+").search(stack) != null, "locales de _add · " + stack)
	_expect(stack.contains("label_text = \"debug fixture\"") and stack.contains("history = Array(3) [1, 2, 3]"), "miembros · " + stack)
	var frame1 := await _call_text("game_stack", {"frame": 1})
	_expect(frame1.contains("Frame #1, _tick()") and RegEx.create_from_string("\\n  frame = \\d+").search(frame1) != null and frame1.contains("doubled = "), "locales de otro frame · " + frame1.right(500))

	var next := await _call_text("game_debug", {"action": "next"})
	report.next = next
	_expect(next.contains("Stopped again (next)") and next.contains("%s:%d in _add()" % [SCRIPT, BREAK_LINE + 1]), "next para en la línea siguiente · " + next)
	var again := await _call_text("game_debug", {"action": "continue"})
	_expect(again.contains("Stopped again (continue)") and again.contains("%s:%d" % [SCRIPT, BREAK_LINE]), "continue vuelve a parar en el breakpoint · " + again)

	var cleared := await _call_text("game_breakpoint", {"action": "clear", "file": SCRIPT, "line": BREAK_LINE})
	_expect(cleared.begins_with("Cleared the breakpoint"), "lo saca · " + cleared)
	var go := await _call_text("game_debug", {"action": "continue"})
	report.go = go
	_expect(go.contains("running again"), "sin breakpoint, sigue · " + go)
	_expect(_run_state().contains("running") and EditorInterface.is_playing_scene(), "PROBE_READY · " + _run_state())
	var running: Dictionary = await _call("game_debug", {"action": "step"})
	_expect(running.get("isError", false) and _text(running).contains("not stopped"), "corriendo: game_debug lo dice · " + _text(running))

	# La sesión que puso el breakpoint se cierra con el juego parado ahí: no queda parado.
	await _call_text("game_breakpoint", {"action": "set", "file": SCRIPT, "line": BREAK_LINE})
	_expect(await _until_breaked(true), "con el juego corriendo, el breakpoint nuevo llega y para")
	await _plugin.call(&"_on_agent_disconnected", "s1")
	_expect(await _until_breaked(false), "al cerrarse la sesión, el juego sigue")
	_expect((_plugin.get(&"_debug_tools").get(&"breakpoints") as Dictionary).is_empty(), "y su breakpoint se fue")
	await _tree.create_timer(0.5).timeout
	_expect(not bool(_debugger.call(&"is_breaked")), "no vuelve a parar")
	await _call_text("stop_scene", {})

	# Revisión de next2 #14b: un juego que corre el usuario (F5/F6) no recibe los breakpoints del agente.
	await _call_text("game_breakpoint", {"action": "set", "file": SCRIPT, "line": BREAK_LINE})
	EditorInterface.play_custom_scene(SCENE)
	var launched := Time.get_ticks_msec()
	while not EditorInterface.is_playing_scene() and Time.get_ticks_msec() - launched < 10000:
		await _tree.process_frame
	await _tree.create_timer(2.0).timeout
	_expect(EditorInterface.is_playing_scene() and not bool(_debugger.call(&"any_breaked")), "un run manual no para en el breakpoint del agente")
	EditorInterface.stop_playing_scene()
	await _tree.create_timer(0.5).timeout
	await _call_text("game_breakpoint", {"action": "clear_all"})

	# Revisión de next2 #10: run_scene con monitors que termina parado en un breakpoint igual los lee
	# (el probe contesta desde el bucle del debugger) y los apaga.
	await _call_text("game_breakpoint", {"action": "set", "file": SCRIPT, "line": LATE_LINE})
	var late := await _call_text("run_scene", {"scene": SCENE, "seconds": 5, "monitors": true})
	report.late = late.left(300)
	_expect(late.contains("stopped at a breakpoint") and late.contains("%s:%d" % [SCRIPT, LATE_LINE]), "para en el breakpoint de más tarde · " + late.left(400))
	_expect(late.contains("Performance during the run:\nSampled "), "parado ahí, igual lee los monitores · " + late.right(600))
	await _call_text("game_breakpoint", {"action": "clear", "file": SCRIPT, "line": LATE_LINE})
	await _call_text("stop_scene", {})


func _run_state() -> String:
	return str(_plugin.get(&"_run_tools").call(&"describe_run_state"))


func _until_breaked(breaked: bool) -> bool:
	var deadline := Time.get_ticks_msec() + 3000
	while Time.get_ticks_msec() < deadline:
		if bool(_debugger.call(&"is_breaked")) == breaked:
			return true
		await _tree.process_frame
	return false
