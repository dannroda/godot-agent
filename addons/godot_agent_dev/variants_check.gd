@tool
extends RefCounted
## Variantes en paralelo (m11-90) con el agente falso, de punta a punta. La primera pestaña llama a
## godot.propose_variants con tres variantes; el check confirma el diálogo con las dos primeras
## tildadas. Se abren dos pestañas «V1 · …» y «V2 · …», cada una en su copia (git worktree), con su
## prompt; al terminar su turno, las regresiones de prueba (copiadas a la carpeta de regresiones del
## proyecto, que git ignora) las juzgan en un Godot headless aparte y la primera pestaña muestra la
## comparación con «Jugar» y «Aplicar» por cada una. Después, un reinicio (guardar las pestañas,
## deshabilitar y habilitar el plugin): las variantes vuelven con su juicio y la comparación. Al final
## borra las copias y sus ramas.

const RestartResume := preload("res://addons/godot_agent/session/restart_resume.gd")
const SupervisorClient := preload("res://addons/godot_agent/supervisor/supervisor_client.gd")
const AgentProfile := preload("res://addons/godot_agent/core/agent_profile.gd")
const SessionModel := preload("res://addons/godot_agent/session/session_model.gd")
const PlaytestRegressions := preload("res://addons/godot_agent/review/playtest_regressions.gd")
const PLUGIN_SCRIPT := "res://addons/godot_agent/agent_plugin.gd"
const TARGET_PLUGIN := "godot_agent"
const FIXTURES := "res://tests/fixtures/regressions/pass"
const GOAL := "A better jump"
const VARIANTS := ["Coyote time and a jump buffer", "Stronger gravity when falling", "Variable jump height"]
## El juez importa una copia entera del repo: tarda.
const JUDGE_WAIT_S := 300.0
const WAIT_S := 20.0

var failures: PackedStringArray = []
var _tree: SceneTree
var _added_regressions: PackedStringArray = []


func run(tree: SceneTree) -> PackedStringArray:
	_tree = tree
	RestartResume.discard(SupervisorClient.state_dir())
	if not _add_regressions():
		return failures
	await _run()
	for path: String in _added_regressions:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	RestartResume.discard(SupervisorClient.state_dir())
	return failures


## Las regresiones de prueba en la carpeta del proyecto, sin pisar ninguna que ya esté.
func _add_regressions() -> bool:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(PlaytestRegressions.DIR))
	for name: String in DirAccess.get_files_at(FIXTURES):
		var target := PlaytestRegressions.DIR.path_join(name)
		if FileAccess.file_exists(target):
			failures.append("ya hay una regresión %s en el proyecto: el check no la pisa" % target)
			return false
		DirAccess.copy_absolute(ProjectSettings.globalize_path(FIXTURES.path_join(name)), ProjectSettings.globalize_path(target))
		_added_regressions.append(target)
	return true


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
			"--script", "res://tests/fake_agent.gd", "--", "--scenario=res://tests/scripts/variants.json"],
	})
	var settings: Object = primary.get(&"_settings")
	var saved_profiles: Array = settings.call(&"profiles")
	var with_fake: Array[AgentProfile] = [profile]
	settings.call(&"save_profiles", with_fake)
	var first_model: Object = primary.get(&"_model")
	var first_controller: Object = primary.get(&"_controller")
	first_model.call(&"set_harness_mode", SessionModel.HarnessMode.ASK)
	if await first_controller.call(&"start", profile):
		await _propose(plugin, tabs, first_model)
		if failures.is_empty():
			await _restart()
	else:
		failures.append("no arrancó la primera sesión: %s" % first_model.get(&"failure_message"))
	await _cleanup(saved_profiles)


func _propose(plugin: Node, tabs: Object, first_model: Object) -> void:
	var registry: Object = plugin.get(&"_registry")
	var results: Array = []
	(func() -> void: results.append(await registry.call(&"call_tool", "propose_variants", {"goal": GOAL, "variants": VARIANTS}, "s1"))).call()
	await _until(func() -> bool: return plugin.get(&"_variants_dialog") != null and (plugin.get(&"_variants_dialog") as Window).visible, WAIT_S)
	var dialog: ConfirmationDialog = plugin.get(&"_variants_dialog")
	if dialog == null or not dialog.visible:
		failures.append("propose_variants no abrió el diálogo")
		return
	_expect(dialog.call(&"chosen") == PackedStringArray(VARIANTS), "las 3 propuestas vienen tildadas · %s" % [dialog.call(&"chosen")])
	var boxes := dialog.find_children("*", "CheckBox", true, false)
	(boxes[2] as CheckBox).button_pressed = false
	_expect(dialog.get_ok_button().text == "Open 2 copies" and not dialog.get_ok_button().disabled, "con 2 tildadas abre 2 · " + dialog.get_ok_button().text)
	dialog.hide()
	dialog.confirmed.emit()
	await _until(func() -> bool: return not results.is_empty(), WAIT_S)
	_expect(not results.is_empty() and not bool(results[0].get("isError", true)) and str(results[0]).contains("V1 · ") and str(results[0]).contains("V2 · "), "la tool dice qué pestañas abrió · %s" % [results])
	var ids := _variant_ids(plugin)
	if ids.size() != 2:
		failures.append("no hay dos pestañas de variantes · %s" % [tabs.call(&"ids")])
		return
	for i in ids.size():
		var session: Dictionary = (plugin.get(&"_extra_sessions") as Dictionary)[ids[i]]
		_expect(session.get("copy") != null, "V%d trabaja en una copia" % (i + 1))
		_expect(str(tabs.call(&"label", ids[i])).begins_with("V%d · " % (i + 1)), "la pestaña se llama V%d · … · %s" % [i + 1, tabs.call(&"label", ids[i])])
		var model: Object = (tabs.call(&"dock", ids[i]) as Control).get(&"_model")
		_expect(int(model.get(&"harness_mode")) == SessionModel.HarnessMode.BUILD, "V%d en Build aunque la que propuso estaba en Ask" % (i + 1))
	# Cada una recibe su prompt, termina el turno y la juzgan las regresiones.
	await _until(func() -> bool: return Array(ids).all(func(id: String) -> bool: return (plugin.get(&"_extra_sessions") as Dictionary)[id].variant.has("judged") and not (plugin.get(&"_extra_sessions") as Dictionary)[id].variant.get("judging", false)), JUDGE_WAIT_S)
	for i in ids.size():
		var model: Object = (tabs.call(&"dock", ids[i]) as Control).get(&"_model")
		_expect(_user_text(model).contains("variant V%d of 2" % (i + 1)) and _user_text(model).contains("Your variant: %s" % VARIANTS[i]), "V%d recibió su prompt · %s" % [i + 1, _user_text(model).left(200)])
		var judged: Dictionary = (plugin.get(&"_extra_sessions") as Dictionary)[ids[i]].variant.get("judged", {})
		_expect(judged.get("ok", false) and judged.report.get("ok", false) and (judged.report.regressions as Array).size() == 2, "V%d juzgada: pasan las 2 regresiones · %s" % [i + 1, str(judged).left(400)])
		_expect(_notices(model).contains("Variant judged: 2 of 2 regressions pass"), "V%d muestra su juicio · %s" % [i + 1, _notices(model).right(300)])
	var comparison := _comparison(first_model)
	_expect(comparison != null and str(comparison.get(&"text")).count("2 of 2 regressions pass") == 2, "la primera pestaña compara las dos · %s" % [comparison.get(&"text") if comparison else "sin aviso"])
	if comparison:
		var labels := (comparison.get(&"actions") as Array).map(func(action: Dictionary) -> String: return str(action.label))
		_expect(labels == ["Play V1", "Apply V1", "Play V2", "Apply V2"], "con Jugar y Aplicar por cada una · %s" % [labels])


## Guardar las pestañas como antes de reiniciar y deshabilitar y habilitar el plugin.
func _restart() -> void:
	var plugin := _plugin()
	RestartResume.save(SupervisorClient.state_dir(), "check", plugin.call(&"restart_tabs", ""))
	EditorInterface.set_plugin_enabled(TARGET_PLUGIN, false)
	await _tree.create_timer(1.0).timeout
	EditorInterface.set_plugin_enabled(TARGET_PLUGIN, true)
	await _until(func() -> bool: return _variant_ids(_plugin()).size() == 2, WAIT_S)
	plugin = _plugin()
	var ids := _variant_ids(plugin)
	_expect(ids.size() == 2, "vuelven las dos variantes · %s" % [ids])
	if ids.size() != 2:
		return
	for id: String in ids:
		var variant: Dictionary = (plugin.get(&"_extra_sessions") as Dictionary)[id].variant
		_expect(str(variant.from) == "s1" and variant.get("judged", {}).get("ok", false), "con su juicio y la pestaña que las propuso · %s" % str(variant).left(300))
	var tabs: Object = plugin.get(&"_tabs")
	var comparison := _comparison((tabs.call(&"dock", "s1") as Control).get(&"_model"))
	_expect(comparison != null and str(comparison.get(&"text")).count("2 of 2 regressions pass") == 2 and (comparison.get(&"actions") as Array).size() == 4, "la comparación vuelve a la primera pestaña · %s" % [comparison.get(&"text") if comparison else "sin aviso"])


func _cleanup(saved_profiles: Array) -> void:
	var plugin := _plugin()
	if plugin == null:
		return
	var sessions: Dictionary = plugin.get(&"_extra_sessions")
	for id: String in sessions.keys():
		var copy: Object = sessions[id].get("copy")
		(sessions[id].controller as Object).call(&"stop")
		if copy:
			await copy.call(&"remove", true)
		plugin.call(&"_close_session_tab", id, false)
	var first: Control = (plugin.get(&"_tabs") as Object).call(&"dock", "s1")
	(first.get(&"_controller") as Object).call(&"stop")
	(first.get(&"_settings") as Object).call(&"save_profiles", saved_profiles)


func _variant_ids(plugin: Node) -> PackedStringArray:
	var ids: PackedStringArray = []
	if plugin == null:
		return ids
	var sessions: Dictionary = plugin.get(&"_extra_sessions")
	for id: String in sessions:
		if sessions[id].has("variant"):
			ids.append(id)
	ids.sort()
	return ids


func _comparison(model: Object) -> Object:
	for entry: Object in model.call(&"entries"):
		if int(entry.get(&"kind")) == 7 and str(entry.get(&"title")).begins_with("Variants: "):
			return entry
	return null


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


func _until(condition: Callable, seconds: float) -> void:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000)
	while not condition.call() and Time.get_ticks_msec() < deadline:
		await _tree.create_timer(0.2).timeout


func _plugin() -> Node:
	for node: Node in _tree.root.find_children("*", "Node", true, false):
		if node.get_script() and (node.get_script() as Script).resource_path == PLUGIN_SCRIPT and node.is_inside_tree():
			return node
	return null


func _expect(condition: bool, what: String) -> void:
	if not condition:
		failures.append(what)
