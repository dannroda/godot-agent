@tool
extends RefCounted
## m11-49 en el editor: un agente falso que juega de verdad por el server MCP del harness y entra en
## loop (la misma tecla cinco veces, el juego igual). A la tercera, el resultado de la tool se lo
## avisa; a la cuarta, la tool no responde el juego, el harness cancela el turno y el veredicto queda
## «could not test» con lo que repetía y la evidencia. El «pass» que el agente iba a dar no cuenta.

const AgentProfile := preload("res://addons/godot_agent/core/agent_profile.gd")
const SessionModel := preload("res://addons/godot_agent/session/session_model.gd")
const ChatEntry := preload("res://addons/godot_agent/session/chat_entry.gd")
const ToolCall := preload("res://addons/godot_agent/session/tool_call.gd")
const SCENARIO := "res://tests/scripts/playtest_loop.json"
const WAIT_MS := 60000

var failures: PackedStringArray = []
var _tree: SceneTree
var _model: SessionModel


func run(tree: SceneTree, dock: Control) -> PackedStringArray:
	_tree = tree
	var controller: Object = dock.get(&"_controller")
	var model: SessionModel = dock.get(&"_model")
	_model = model
	var profile := AgentProfile.from_dict({"id": "fake", "display_name": "Agente falso", "command": OS.get_executable_path(),
		"args": ["--headless", "--no-header", "--path", ProjectSettings.globalize_path("res://"),
			"--script", "res://tests/fake_agent.gd", "--", "--scenario=" + SCENARIO]})
	if not await controller.call(&"start", profile):
		failures.append("la sesión no arrancó")
		return failures
	model.set_harness_mode(SessionModel.HarnessMode.REVIEW)
	dock.call(&"_on_submitted", "Playtest: pressing Space opens the menu")
	await _until(func() -> bool: return model.is_busy())
	await _until(func() -> bool: return not model.is_busy())
	var outputs: Array[String] = []
	for entry: ChatEntry in model.entries():
		for id: String in entry.tool_call_ids:
			var call: ToolCall = model.tool_call(id)
			if call and call.title.ends_with("game_input"):
				outputs.append(str(call.raw_output))
	_expect(outputs.size() == 4, "el agente llegó a 4 game_input y no al quinto: %d" % outputs.size())
	if outputs.size() >= 4:
		_expect(not outputs[1].contains("same call"), "la segunda vuelta todavía no avisa")
		_expect(outputs[2].contains("same call") and outputs[2].contains("3 times"), "a la tercera el resultado avisa: %s" % outputs[2].right(300))
		_expect(outputs[3].begins_with("Stopped:"), "a la cuarta la tool corta: %s" % outputs[3].left(200))
	var verdicts := model.entries().filter(func(entry: ChatEntry) -> bool: return entry.title.begins_with("Playtest:"))
	_expect(verdicts.size() == 1, "un solo veredicto: %s" % [verdicts.map(func(entry: ChatEntry) -> String: return entry.title)])
	if verdicts.size() == 1:
		var verdict: ChatEntry = verdicts[0]
		_expect(verdict.title.begins_with("Playtest: could not test") and verdict.title.contains("game_input"), "could not test, con lo que repetía: %s" % verdict.title)
		var evidence := verdict.sections.filter(func(section: Dictionary) -> bool: return str(section.get("title", "")).begins_with("Evidence"))
		_expect(not evidence.is_empty() and str(evidence[0].get("text", "")).contains("Space") and str(evidence[0].get("text", "")).contains("×4"), "la evidencia muestra la llamada repetida: %s" % [evidence])
	EditorInterface.stop_playing_scene()
	return failures


## Espera `condition` aprobando las tarjetas de permiso que salgan (Revisar pide correr el juego).
func _until(condition: Callable) -> void:
	var deadline := Time.get_ticks_msec() + WAIT_MS
	while not condition.call() and Time.get_ticks_msec() < deadline:
		for entry: ChatEntry in _model.entries():
			if entry.kind == ChatEntry.EntryKind.PERMISSION and entry.permission and entry.permission.call(&"is_pending"):
				entry.permission.call(&"select", entry.permission.call(&"option_id_for", PackedStringArray(["allow_once"])))
		await _tree.process_frame


func _expect(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
