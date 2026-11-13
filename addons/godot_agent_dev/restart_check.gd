@tool
extends RefCounted
## Reiniciar el editor y retomar las sesiones (m12-54) con el agente falso. Dos pestañas con sesión:
## la primera en Review y en pleno turno, la segunda («Restart tab», en Build) llama a
## godot.restart_editor con un motivo. La tarjeta muestra el motivo y avisa del turno de la otra; al
## permitir, el reinicio pasa por restart_override y quedan guardadas las pestañas. Deshabilitar y
## habilitar el plugin hace de reinicio: vuelven las dos pestañas con su sesión, su modo y su nombre, y
## solo la segunda recibe «The editor restarted (<motivo>). Continue.». Al final, «Restart and resume»
## del menú ⋯ pasa por el mismo camino, sin pestaña que lo pida.

const RestartResume := preload("res://addons/godot_agent/session/restart_resume.gd")
const SupervisorClient := preload("res://addons/godot_agent/supervisor/supervisor_client.gd")
const AgentProfile := preload("res://addons/godot_agent/core/agent_profile.gd")
const SessionModel := preload("res://addons/godot_agent/session/session_model.gd")
const PLUGIN_SCRIPT := "res://addons/godot_agent/agent_plugin.gd"
const TARGET_PLUGIN := "godot_agent"
const REASON := "the check enabled a plugin"
const LABEL := "Restart tab"
const WAIT_S := 15.0

var failures: PackedStringArray = []
var _tree: SceneTree


func run(tree: SceneTree) -> PackedStringArray:
	_tree = tree
	var state := SupervisorClient.state_dir()
	RestartResume.discard(state)
	await _run()
	RestartResume.discard(state)
	return failures


func _run() -> void:
	var plugin := _plugin()
	if plugin == null:
		failures.append("no se encontró el plugin")
		return
	var tabs: Object = plugin.get(&"_tabs")
	var primary: Control = tabs.call(&"dock", "s1")
	var profile := AgentProfile.from_dict({
		"id": "fake", "display_name": "Agente falso", "command": OS.get_executable_path(),
		"args": ["--headless", "--no-header", "--path", ProjectSettings.globalize_path("res://"),
			"--script", "res://tests/fake_agent.gd", "--", "--scenario=res://tests/scripts/restart.json"],
	})
	var settings: Object = primary.get(&"_settings")
	var saved_profiles: Array = settings.call(&"profiles")
	var with_fake: Array[AgentProfile] = [profile]
	settings.call(&"save_profiles", with_fake)
	await _two_tabs(plugin, tabs, primary, profile)
	if failures.is_empty():
		await _reopened()
	if failures.is_empty():
		await _user_restart()
	var current := _plugin()
	if current:
		var current_tabs: Object = current.get(&"_tabs")
		for id: String in current_tabs.call(&"ids"):
			if id != "s1":
				current.call(&"_close_session_tab", id, false)
		var first: Control = current_tabs.call(&"dock", "s1")
		(first.get(&"_controller") as Object).call(&"stop")
		(first.get(&"_settings") as Object).call(&"save_profiles", saved_profiles)


func _two_tabs(plugin: Node, tabs: Object, primary: Control, profile: AgentProfile) -> void:
	var first_model: Object = primary.get(&"_model")
	var first_controller: Object = primary.get(&"_controller")
	if not await first_controller.call(&"start", profile):
		failures.append("no arrancó la primera sesión: %s" % first_model.get(&"failure_message"))
		return
	first_model.call(&"set_harness_mode", SessionModel.HarnessMode.REVIEW)
	await first_controller.call(&"send_prompt", "hola")
	plugin.call(&"_open_session_tab")
	var ids: PackedStringArray = tabs.call(&"ids")
	var second_id := ids[ids.size() - 1]
	var second: Control = tabs.call(&"dock", second_id)
	var second_model: Object = second.get(&"_model")
	var second_controller: Object = second.get(&"_controller")
	plugin.call(&"_rename_session", second_id, LABEL)
	if not await second_controller.call(&"start", profile):
		failures.append("no arrancó la segunda sesión: %s" % second_model.get(&"failure_message"))
		return
	await second_controller.call(&"send_prompt", "hola")
	# La primera queda en pleno turno (el segundo del guion tarda un minuto).
	first_controller.call(&"send_prompt", "seguí")
	await _until(func() -> bool: return first_model.call(&"is_busy"))
	var restarts: Array = []
	plugin.set(&"restart_override", func(supervise: bool, reason: String) -> String:
		restarts.append([supervise, reason])
		return "")
	var registry: Object = plugin.get(&"_registry")
	var results: Array = []
	(func() -> void: results.append(await registry.call(&"call_tool", "restart_editor", {"reason": REASON}, second_id))).call()
	await _until(func() -> bool: return not (second_model.get(&"pending_permissions") as Array).is_empty())
	var pending: Array = second_model.get(&"pending_permissions")
	if pending.is_empty():
		failures.append("restart_editor no pidió permiso en Build")
		plugin.set(&"restart_override", Callable())
		return
	var request: Object = pending[0]
	var description := str(request.get(&"description"))
	_expect(description.contains(REASON), "la tarjeta muestra el motivo · " + description)
	_expect(description.contains(str(tabs.call(&"label", "s1"))) and description.contains("⚠"), "y avisa que la otra pestaña está en pleno turno · " + description)
	request.call(&"select", request.call(&"option_id_for", PackedStringArray(["allow_once"])))
	await _until(func() -> bool: return not results.is_empty())
	plugin.set(&"restart_override", Callable())
	_expect(not results.is_empty() and not bool(results[0].get("isError", true)), "la tool sale bien · %s" % [results])
	_expect(restarts == [[false, REASON]], "reinicia con el motivo y sin supervisor (no hay GDExtension) · %s" % [restarts])
	var saved := FileAccess.get_file_as_string(SupervisorClient.state_dir().path_join(RestartResume.FILE))
	_expect(saved.contains(str(first_model.get(&"session_id"))) and saved.contains(str(second_model.get(&"session_id"))), "guarda las dos sesiones")
	set_meta(&"first_session", str(first_model.get(&"session_id")))
	set_meta(&"second_session", str(second_model.get(&"session_id")))


## Deshabilitar y habilitar el plugin hace de reinicio.
func _reopened() -> void:
	EditorInterface.set_plugin_enabled(TARGET_PLUGIN, false)
	await _tree.create_timer(1.0).timeout
	EditorInterface.set_plugin_enabled(TARGET_PLUGIN, true)
	await _until(func() -> bool: return _tab_count() == 2)
	var plugin := _plugin()
	var tabs: Object = plugin.get(&"_tabs") if plugin else null
	if tabs == null or (tabs.call(&"ids") as PackedStringArray).size() != 2:
		failures.append("al volver no hay dos pestañas · %s" % [tabs.call(&"ids") if tabs else "sin pestañas"])
		return
	var ids: PackedStringArray = tabs.call(&"ids")
	var first_model: Object = (tabs.call(&"dock", ids[0]) as Control).get(&"_model")
	var second_model: Object = (tabs.call(&"dock", ids[1]) as Control).get(&"_model")
	await _until(func() -> bool: return int(first_model.get(&"state")) == SessionModel.SessionState.READY and int(second_model.get(&"state")) == SessionModel.SessionState.READY and _user_text(second_model).contains("The editor restarted"))
	_expect(str(first_model.get(&"session_id")) == str(get_meta(&"first_session")), "la primera retoma su sesión · %s" % first_model.get(&"session_id"))
	_expect(str(second_model.get(&"session_id")) == str(get_meta(&"second_session")), "la segunda retoma la suya · %s" % second_model.get(&"session_id"))
	_expect(int(first_model.get(&"harness_mode")) == SessionModel.HarnessMode.REVIEW, "con su modo (Review)")
	_expect(int(second_model.get(&"harness_mode")) == SessionModel.HarnessMode.BUILD, "y la otra con el suyo (Build)")
	_expect(str(tabs.call(&"custom_label", ids[1])) == LABEL, "y su nombre")
	_expect(_user_text(second_model).contains("The editor restarted (%s). Continue." % REASON), "la que pidió el reinicio sigue con el motivo · " + _user_text(second_model).right(200))
	_expect(not _user_text(first_model).contains("The editor restarted"), "la otra vuelve sin mensaje")
	_expect(_notices(first_model).contains(REASON), "el aviso del dock dice por qué se reinició")
	_expect(not FileAccess.file_exists(SupervisorClient.state_dir().path_join(RestartResume.FILE)), "lo guardado se usa una vez")


## «Restart and resume» del menú ⋯: mismo camino, sin pestaña que lo pida.
func _user_restart() -> void:
	var plugin := _plugin()
	var tabs: Object = plugin.get(&"_tabs")
	var first: Control = tabs.call(&"dock", "s1")
	var restarts: Array = []
	plugin.set(&"restart_override", func(supervise: bool, reason: String) -> String:
		restarts.append(reason)
		return "")
	var popup: PopupMenu = (first.get(&"_more_button") as MenuButton).get_popup()
	first.call(&"_fill_more_menu")
	var index := -1
	for i: int in popup.item_count:
		if popup.get_item_id(i) == int(first.get(&"MORE_RESTART")):
			index = i
	_expect(index >= 0, "el menú ⋯ tiene «Restart and resume»")
	popup.id_pressed.emit(first.get(&"MORE_RESTART"))
	await _tree.process_frame
	plugin.set(&"restart_override", Callable())
	_expect(restarts.size() == 1, "reinicia sin preguntar cuando nada está en pleno turno · %s" % [restarts])
	var saved := RestartResume.take(SupervisorClient.state_dir())
	var tabs_saved: Array = saved.get("tabs", [])
	_expect(tabs_saved.size() == 2 and not tabs_saved.any(func(tab: Dictionary) -> bool: return bool(tab.get("requester", false))), "guarda las pestañas, ninguna como la que lo pidió · %s" % [tabs_saved])


func _tab_count() -> int:
	var plugin := _plugin()
	var tabs: Object = plugin.get(&"_tabs") if plugin else null
	return (tabs.call(&"ids") as PackedStringArray).size() if tabs else 0


func _user_text(model: Object) -> String:
	var lines: PackedStringArray = []
	for entry: Object in model.call(&"entries"):
		if int(entry.get(&"kind")) == 0:  # USER
			lines.append(str(entry.get(&"text")))
	return "\n".join(lines)


func _notices(model: Object) -> String:
	var lines: PackedStringArray = []
	for entry: Object in model.call(&"entries"):
		if int(entry.get(&"kind")) == 7:  # NOTICE
			lines.append(str(entry.get(&"text")))
	return "\n".join(lines)


func _until(condition: Callable) -> void:
	var deadline := Time.get_ticks_msec() + int(WAIT_S * 1000)
	while not condition.call() and Time.get_ticks_msec() < deadline:
		await _tree.create_timer(0.1).timeout


func _plugin() -> Node:
	for node: Node in _tree.root.find_children("*", "Node", true, false):
		if node.get_script() and (node.get_script() as Script).resource_path == PLUGIN_SCRIPT and node.is_inside_tree():
			return node
	return null


func _expect(condition: bool, what: String) -> void:
	if not condition:
		failures.append(what)
