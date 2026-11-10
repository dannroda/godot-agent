@tool
extends "mcp_check.gd"
## m11-55 dentro del editor: un run manual (play_custom_scene, no run_scene) de un script roto deja
## en el dock un aviso con el error y la pila y «Arreglar con el agente», una vez por run; el botón
## manda el prompt a la sesión activa con la etiqueta del harness; un run del agente (run_scene) no
## avisa; apagado en Ajustes tampoco. Necesita ventana (tests/run_in_xvfb.sh).

const SessionModel := preload("res://addons/godot_agent/session/session_model.gd")
const ChatEntry := preload("res://addons/godot_agent/session/chat_entry.gd")
const HarnessPrompts := preload("res://addons/godot_agent/session/harness_prompts.gd")
const HarnessSettings := preload("res://addons/godot_agent/core/harness_settings.gd")
const AgentProfile := preload("res://addons/godot_agent/core/agent_profile.gd")
const I18n := preload("res://addons/godot_agent/core/i18n.gd")
const DOCK_SCRIPT := "res://addons/godot_agent/ui/dock/agent_dock.gd"
const MAIN_PLUGIN_SCRIPT := "res://addons/godot_agent/plugin.gd"
const BROKEN_SCENE := "res://tests/fixtures/run_broken.tscn"
const RUN_ARGS_ENV := "GODOT_AGENT_TEST_RUN_ARGS"
const RUN_ARGS_SETTING := "editor/run/main_run_args"
const NOTICE_TIMEOUT_S := 25.0
const TURN_TIMEOUT_S := 30.0

var _dock: Node
var _model: Object
var _controller: Object
var _settings: Object
var _plugin_config: Object
var _shot_path: String = ""


## Con `shot_path` guarda el dock con el aviso a la vista.
func run_run_error(tree: SceneTree, shot_path: String = "") -> PackedStringArray:
	_tree = tree
	_shot_path = shot_path
	for node: Node in tree.root.find_children("*", "Node", true, false):
		var script := node.get_script() as Script
		if script and script.resource_path == SERVER_SCRIPT:
			_server = node
		elif script and script.resource_path == DOCK_SCRIPT:
			_dock = node
			_model = node.get(&"_model")
			_controller = node.get(&"_controller")
		elif script and script.resource_path == MAIN_PLUGIN_SCRIPT:
			_settings = node.get(&"_settings")
			_plugin_config = node.get(&"_project_config")
	if _server == null or _dock == null or _settings == null:
		failures.append("no se encontró el server, el dock o los ajustes")
		return failures
	var previous_args: Variant = ProjectSettings.get_setting(RUN_ARGS_SETTING, "")
	if not OS.get_environment(RUN_ARGS_ENV).is_empty():
		ProjectSettings.set_setting(RUN_ARGS_SETTING, OS.get_environment(RUN_ARGS_ENV))
	var manual_runs: bool = _plugin_config.get(&"playtest_on_manual_runs") if _plugin_config else false
	if _plugin_config:
		_plugin_config.set(&"playtest_on_manual_runs", false)
	var offered: bool = _settings.call(&"offer_fix_on_run_error")
	_settings.call(&"set_value", HarnessSettings.KEY_RUN_ERROR_FIX, true)
	await _check(tree)
	_settings.call(&"set_value", HarnessSettings.KEY_RUN_ERROR_FIX, offered)
	if _plugin_config:
		_plugin_config.set(&"playtest_on_manual_runs", manual_runs)
	ProjectSettings.set_setting(RUN_ARGS_SETTING, previous_args)
	ProjectSettings.save()
	return failures


func _check(tree: SceneTree) -> void:
	# Una sesión con el agente falso: el botón manda el prompt enseguida.
	if not await _controller.call(&"start", _profile("ui_harness_prompt")):
		failures.append("no arrancó la sesión: %s" % _model.get(&"failure_message"))
		return
	await _wait_ready()

	# Run manual roto: aviso con el error, la pila y el botón.
	var before := _notices().size()
	EditorInterface.play_custom_scene(BROKEN_SCENE)
	var notice: Object = await _wait_notice(before)
	_expect(notice != null, "run manual roto: aviso en el dock (%d s)" % int(NOTICE_TIMEOUT_S))
	var action: Dictionary = {}
	if notice:
		_expect(notice.get(&"level") == ChatEntry.NoticeLevel.WARNING, "nivel: advertencia")
		_expect(str(notice.get(&"text")).contains("run_broken.gd") or str(notice.get(&"text")).contains("Nil"), "cuerpo con el error: " + str(notice.get(&"text")))
		_expect(str(notice.get(&"details")).contains("run_broken.gd"), "detalles con el archivo: " + str(notice.get(&"details")).left(300))
		_expect(notice.get(&"details_title") == I18n.t("Errors and stack"), "título de los detalles: " + str(notice.get(&"details_title")))
		for candidate: Dictionary in notice.get(&"actions"):
			if str(candidate.id) == "fix_run_error":
				action = candidate
		_expect(not action.is_empty() and str(action.get("label", "")) == I18n.t("Fix with the agent") and bool(action.get("primary", false)), "acción «Fix with the agent» principal (%s)" % [notice.get(&"actions")])
	if notice and not _shot_path.is_empty():
		await tree.create_timer(0.5).timeout
		var image := EditorInterface.get_base_control().get_viewport().get_texture().get_image()
		image.get_region(Rect2i((_dock.get_parent() as Control).get_global_rect())).save_png(_shot_path)
	EditorInterface.stop_playing_scene()
	await tree.create_timer(2.0).timeout
	_expect(_notices().size() == before + 1, "una vez por run (%d avisos)" % (_notices().size() - before))

	# El botón: el prompt va a la sesión activa con la etiqueta del harness.
	if not action.is_empty():
		var users_before := _user_entries().size()
		_dock.call(&"_on_action_requested", str(action.id), action.get("data"))
		await _wait_ready()
		var users := _user_entries()
		_expect(users.size() == users_before + 1, "el botón mandó un prompt (%d → %d)" % [users_before, users.size()])
		if users.size() > users_before:
			var sent: Object = users[-1]
			_expect(sent.get(&"harness_label") == HarnessPrompts.RUN_ERROR, "con la etiqueta del harness (%s)" % sent.get(&"harness_label"))
			_expect(str(sent.get(&"text")).begins_with("The user ran the game from the editor by hand") and str(sent.get(&"text")).contains("run_broken.gd"), "prompt en inglés con el error: " + str(sent.get(&"text")).left(200))

	# Un run del agente (run_scene) no avisa: el agente ya ve el error en el resultado.
	await _rpc("initialize", {"protocolVersion": "2025-06-18", "capabilities": {}, "clientInfo": {"name": "run-error-check", "version": "1"}})
	var mode: int = _model.get(&"harness_mode")
	_model.call(&"set_harness_mode", SessionModel.HarnessMode.ONESHOT)
	var count := _notices().size()
	var result := await _call_text("run_scene", {"scene": BROKEN_SCENE, "seconds": 3})
	_expect(result.contains("run_broken.gd"), "run_scene ve el error: " + result.left(200))
	var deadline := Time.get_ticks_msec() + 10000
	while EditorInterface.is_playing_scene() and Time.get_ticks_msec() < deadline:
		await tree.process_frame
	EditorInterface.stop_playing_scene()
	await tree.create_timer(2.0).timeout
	_expect(_notices().size() == count, "un run del agente no avisa (%d avisos nuevos)" % (_notices().size() - count))
	_model.call(&"set_harness_mode", mode)

	# Apagado en Ajustes: nada.
	_settings.call(&"set_value", HarnessSettings.KEY_RUN_ERROR_FIX, false)
	count = _notices().size()
	EditorInterface.play_custom_scene(BROKEN_SCENE)
	await tree.create_timer(8.0).timeout
	EditorInterface.stop_playing_scene()
	await tree.create_timer(2.0).timeout
	_expect(_notices().size() == count, "apagado en Ajustes no avisa (%d avisos nuevos)" % (_notices().size() - count))
	_controller.call(&"stop")


## El aviso nuevo del run (título de m11-55), o null si no llega a tiempo.
func _wait_notice(before: int) -> Object:
	var deadline := Time.get_ticks_msec() + int(NOTICE_TIMEOUT_S * 1000)
	while Time.get_ticks_msec() < deadline:
		var notices := _notices()
		if notices.size() > before:
			return notices[-1]
		await _tree.process_frame
	return null


func _notices() -> Array:
	var titles: PackedStringArray = [I18n.t("The game stopped in the debugger with an error"), I18n.t("The game ended with errors")]
	return (_model.call(&"entries") as Array).filter(func(entry: Object) -> bool: return entry.get(&"kind") == ChatEntry.EntryKind.NOTICE and str(entry.get(&"title")) in titles)


func _user_entries() -> Array:
	return (_model.call(&"entries") as Array).filter(func(entry: Object) -> bool: return entry.get(&"kind") == ChatEntry.EntryKind.USER)


func _wait_ready() -> void:
	var deadline := Time.get_ticks_msec() + int(TURN_TIMEOUT_S * 1000)
	await _tree.process_frame
	await _tree.process_frame
	while int(_model.get(&"state")) != SessionModel.SessionState.READY and Time.get_ticks_msec() < deadline:
		await _tree.process_frame
	if int(_model.get(&"state")) != SessionModel.SessionState.READY:
		failures.append("el turno no terminó (estado %d)" % int(_model.get(&"state")))


func _profile(scenario: String) -> AgentProfile:
	return AgentProfile.from_dict({
		"id": "claude", "display_name": "Claude Code", "command": OS.get_executable_path(),
		"args": ["--headless", "--no-header", "--path", ProjectSettings.globalize_path("res://"),
			"--script", "res://tests/fake_agent.gd", "--", "--scenario=res://tests/scripts/%s.json" % scenario],
	})
