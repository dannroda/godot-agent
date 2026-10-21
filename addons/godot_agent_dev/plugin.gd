@tool
extends EditorPlugin
## Herramientas de test que necesitan el editor. No hace nada salvo que se lance con:
## - `-- --godot-agent-cycle-test`: alterna el plugin godot_agent N veces y sale.
##   Código de salida: 0 bien, 1 si quedan nodos huérfanos u objetos que crecen ciclo a ciclo.
## - `-- --godot-agent-screenshot=<ruta.png>`: abre la main screen "Agent", guarda una captura
##   del editor y sale (necesita ventana, no headless).
## - `-- --godot-agent-ui-test=<guion> --godot-agent-ui-shot=<ruta.png>`: conecta el dock al agente
##   falso con tests/scripts/<guion>.json, manda "hola", espera el fin del turno, captura y sale.

const CYCLE_ARG := "--godot-agent-cycle-test"
const SCREENSHOT_ARG := "--godot-agent-screenshot="
const UI_TEST_ARG := "--godot-agent-ui-test="
const UI_SHOT_ARG := "--godot-agent-ui-shot="
const AgentProfile := preload("res://addons/godot_agent/core/agent_profile.gd")
const DOCK_SCRIPT := "res://addons/godot_agent/ui/dock/agent_dock.gd"
const MAIN_SCREEN_NAME := "Agent"
const TARGET_PLUGIN := "godot_agent"
const CYCLES := 5
const SETTLE_FRAMES := 5
const SAFETY_TIMEOUT_S := 120.0
## Margen de objetos que se toleran entre el primer y el último ciclo (cachés del editor, tooltips…).
const OBJECT_GROWTH_TOLERANCE := 50


func _enter_tree() -> void:
	var args := OS.get_cmdline_user_args()
	if CYCLE_ARG in args:
		_run_cycle_test.call_deferred()
	for arg: String in args:
		if arg.begins_with(SCREENSHOT_ARG):
			_take_screenshot.call_deferred(arg.trim_prefix(SCREENSHOT_ARG))
		if arg.begins_with(UI_TEST_ARG):
			_run_ui_test.call_deferred(arg.trim_prefix(UI_TEST_ARG), _arg_value(UI_SHOT_ARG))


func _arg_value(prefix: String) -> String:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with(prefix):
			return arg.trim_prefix(prefix)
	return ""


func _run_ui_test(scenario: String, shot_path: String) -> void:
	get_tree().create_timer(SAFETY_TIMEOUT_S).timeout.connect(_on_safety_timeout)
	await get_tree().create_timer(2.0).timeout
	var dock: Control = null
	for node: Node in EditorInterface.get_base_control().find_children("*", "VBoxContainer", true, false):
		if node.get_script() and (node.get_script() as Script).resource_path == DOCK_SCRIPT:
			dock = node
	if dock == null:
		_finish(1, "no se encontró el dock")
		return
	var holder := dock.get_parent()
	if holder.has_method(&"make_visible"):
		holder.call(&"make_visible")
	elif holder is TabContainer:
		(holder as TabContainer).current_tab = dock.get_index()
	var controller: Object = dock.get(&"_controller")
	var model: Object = dock.get(&"_model")
	var profile := AgentProfile.from_dict({
		"id": "fake", "display_name": "Agente falso", "command": OS.get_executable_path(),
		"args": ["--headless", "--no-header", "--path", ProjectSettings.globalize_path("res://"),
			"--script", "res://tests/fake_agent.gd", "--", "--scenario=res://tests/scripts/%s.json" % scenario],
	})
	var ok: bool = await controller.call(&"start", profile)
	if not ok:
		_finish(1, "no arrancó la sesión: %s" % model.get(&"failure_message"))
		return
	dock.call(&"_on_submitted", "hola, ¿qué hay que hacer con las oleadas?")
	while int(model.get(&"state")) != 2:  # READY
		await get_tree().process_frame
	await get_tree().create_timer(0.5).timeout
	dock.emit_signal(&"show_log_requested")
	await get_tree().create_timer(0.5).timeout
	var entries: Array = model.call(&"entries")
	print("[ui-test] %d entradas, título '%s'" % [entries.size(), model.get(&"title")])
	if not shot_path.is_empty():
		var image := EditorInterface.get_base_control().get_viewport().get_texture().get_image()
		image.save_png(shot_path)
	controller.call(&"stop")
	_finish(0, "ui-test %s" % scenario)


func _take_screenshot(path: String) -> void:
	get_tree().create_timer(SAFETY_TIMEOUT_S).timeout.connect(_on_safety_timeout)
	await get_tree().create_timer(3.0).timeout
	for dock: Node in EditorInterface.get_base_control().find_children("*", "EditorDock", true, false):
		print("[dbg] dock title=%s parent=%s inside=%s visible=%s slot=%s child=%s" % [dock.get(&"title"), dock.get_parent().get_path() if dock.get_parent() else "-", dock.is_inside_tree(), (dock as Control).visible, dock.get(&"default_slot"), dock.get_child(0).name if dock.get_child_count() > 0 else "-"])
	EditorInterface.set_main_screen_editor(MAIN_SCREEN_NAME)
	await get_tree().create_timer(1.0).timeout
	var image := EditorInterface.get_base_control().get_viewport().get_texture().get_image()
	var err := image.save_png(path)
	_finish(0 if err == OK else 1, "captura en %s (%s)" % [path, error_string(err)])


func _run_cycle_test() -> void:
	get_tree().create_timer(SAFETY_TIMEOUT_S).timeout.connect(_on_safety_timeout)
	await _settle()
	if not EditorInterface.is_plugin_enabled(TARGET_PLUGIN):
		EditorInterface.set_plugin_enabled(TARGET_PLUGIN, true)
		await _settle()

	var orphans_before: int = _orphans()
	var orphan_ids_before: Array = _orphan_ids()
	var objects_after_first: int = -1
	for i: int in CYCLES:
		EditorInterface.set_plugin_enabled(TARGET_PLUGIN, false)
		await _settle()
		if EditorInterface.is_plugin_enabled(TARGET_PLUGIN):
			_finish(1, "cycle %d: el plugin no se deshabilitó" % (i + 1))
			return
		EditorInterface.set_plugin_enabled(TARGET_PLUGIN, true)
		await _settle()
		if not EditorInterface.is_plugin_enabled(TARGET_PLUGIN):
			_finish(1, "cycle %d: el plugin no se habilitó" % (i + 1))
			return
		var objects: int = _objects()
		if i == 0:
			objects_after_first = objects
		print("[cycle-test] cycle %d ok · objects=%d orphan_nodes=%d" % [i + 1, objects, _orphans()])

	var orphans_after: int = _orphans()
	var growth: int = _objects() - objects_after_first
	if orphans_after > orphans_before:
		_print_new_orphans(orphan_ids_before)
		_finish(1, "quedaron %d nodos huérfanos nuevos" % (orphans_after - orphans_before))
	elif growth > OBJECT_GROWTH_TOLERANCE:
		_finish(1, "los objetos crecieron %d entre el ciclo 1 y el %d" % [growth, CYCLES])
	else:
		_finish(0, "%d ciclos sin huérfanos (crecimiento de objetos: %d)" % [CYCLES, growth])


func _settle() -> void:
	for i: int in SETTLE_FRAMES:
		await get_tree().process_frame


func _objects() -> int:
	return int(Performance.get_monitor(Performance.OBJECT_COUNT))


func _orphans() -> int:
	return int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))


## Node.get_orphan_node_ids() no existe en 4.4: se llama por reflexión para que el script parsee igual.
func _orphan_ids() -> Array:
	if not ClassDB.class_has_method(&"Node", &"get_orphan_node_ids"):
		return []
	return ClassDB.call(&"class_call_static", &"Node", &"get_orphan_node_ids")


func _print_new_orphans(before: Array) -> void:
	for id: int in _orphan_ids():
		if id in before:
			continue
		var node := instance_from_id(id) as Node
		if node:
			print("[cycle-test] huérfano nuevo: '%s' (%s) title=%s children=%s" % [node.name, node.get_class(), node.get(&"title"), node.get_children()])


func _on_safety_timeout() -> void:
	_finish(1, "timeout")


func _finish(code: int, message: String) -> void:
	print("[cycle-test] %s: %s" % ["PASS" if code == 0 else "FAIL", message])
	get_tree().quit(code)
