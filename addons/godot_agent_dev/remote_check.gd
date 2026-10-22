@tool
extends RefCounted
## Verificación de Remote Control (m7-21) en el editor, por la UI y con el agente falso
## (tests/scripts/remote_control.json): el botón «Remoto» del encabezado prende Remote Control, la
## franja muestra el link, el permiso pedido «desde el celular» y contestado allá queda cerrado en
## su tarjeta, «Apagar» lo apaga y en One-shot el botón no aparece.

const AgentProfile := preload("res://addons/godot_agent/core/agent_profile.gd")
const I18n := preload("res://addons/godot_agent/core/i18n.gd")
const SessionModel := preload("res://addons/godot_agent/session/session_model.gd")
const DOCK_SCRIPT := "res://addons/godot_agent/ui/dock/agent_dock.gd"
const PERMISSION_VIEW_SCRIPT := "res://addons/godot_agent/ui/dock/entries/permission_view.gd"
const FAKE_URL := "https://claude.ai/code/session_01FakeRemoteSession"
const WAIT_S := 15.0

var failures: PackedStringArray = []
var _tree: SceneTree
var _dock: Control
var _model: Object
var _controller: Object


func run_remote(tree: SceneTree, shot_path: String = "") -> PackedStringArray:
	_tree = tree
	await _run(shot_path)
	if _controller:
		_controller.call(&"stop")
	if _model:
		_model.set(&"harness_mode", SessionModel.HarnessMode.BUILD)
	return failures


func _run(shot_path: String) -> void:
	for node: Node in EditorInterface.get_base_control().find_children("*", "VBoxContainer", true, false):
		if node.get_script() and (node.get_script() as Script).resource_path == DOCK_SCRIPT:
			_dock = node
			var guard := node.get_parent()  # MinSizeGuard
			var holder := guard.get_parent()
			if holder.has_method(&"make_visible"):
				holder.call(&"make_visible")
			elif holder is TabContainer:
				(holder as TabContainer).current_tab = guard.get_index()
	if _dock == null:
		failures.append("no se encontró el dock")
		return
	_model = _dock.get(&"_model")
	_controller = _dock.get(&"_controller")
	var button: Button = _dock.get(&"_remote_button")
	var banner: Control = _dock.get(&"_remote_banner")
	var profile := AgentProfile.from_dict({
		"id": "fake", "display_name": "Agente falso", "command": OS.get_executable_path(),
		"args": ["--headless", "--no-header", "--path", ProjectSettings.globalize_path("res://"),
			"--script", "res://tests/fake_agent.gd", "--", "--scenario=res://tests/scripts/remote_control.json"],
	})
	if not await _controller.call(&"start", profile):
		failures.append("no arrancó la sesión: %s" % _model.get(&"failure_message"))
		return
	if not await _until(func() -> bool: return button.is_visible_in_tree() and not button.disabled):
		failures.append("el botón «%s» no aparece con un agente que publica /remote-control" % button.text)
		return
	if banner.visible:
		failures.append("la franja de Remote Control se ve antes de prenderlo")
	button.pressed.emit()
	if not await _until(func() -> bool: return banner.is_visible_in_tree()):
		failures.append("la franja no aparece al prenderlo")
		return
	var link: Button = _dock.get(&"_remote_link")
	if link.text != FAKE_URL:
		failures.append("link de la franja: %s" % link.text)
	if button.visible:
		failures.append("el botón sigue a la vista con Remote Control prendido")
	# El permiso remoto aparece como tarjeta y se cierra al contestarlo «desde el celular».
	var withdrawn := func() -> bool:
		for view: Node in _dock.find_children("*", "", true, false):
			if view.get_script() and (view.get_script() as Script).resource_path == PERMISSION_VIEW_SCRIPT:
				var result: Label = view.get(&"_result")
				if result.is_visible_in_tree() and result.text.contains(I18n.t("Answered elsewhere: from Remote Control, or no longer needed")):
					return true
		return false
	if not await _until(withdrawn):
		failures.append("la tarjeta del permiso contestado desde el celular no quedó cerrada")
	await _tree.create_timer(0.3).timeout
	# Ni la franja ni la tarjeta ensanchan el dock más allá de su mínimo de diseño.
	if _dock.get_combined_minimum_size().x > _dock.custom_minimum_size.x + 1.0:
		failures.append("el dock pide %d px (mínimo de diseño %d)" % [_dock.get_combined_minimum_size().x, _dock.custom_minimum_size.x])
	if not shot_path.is_empty():
		EditorInterface.get_base_control().get_viewport().get_texture().get_image().save_png(shot_path)
	_press(banner, I18n.t("Turn off"))
	if not await _until(func() -> bool: return not banner.visible and button.is_visible_in_tree()):
		failures.append("«%s» no lo apagó" % I18n.t("Turn off"))
	await _until(func() -> bool: return not _model.call(&"is_busy"))
	var buttons: Dictionary = _dock.get(&"_mode_buttons")
	(buttons[SessionModel.HarnessMode.ONESHOT] as Button).pressed.emit()
	await _tree.process_frame
	if button.visible:
		failures.append("en One-shot el botón de Remote Control sigue a la vista")


func _until(condition: Callable) -> bool:
	var deadline := Time.get_ticks_msec() + int(WAIT_S * 1000)
	while Time.get_ticks_msec() < deadline:
		if condition.call():
			return true
		await _tree.create_timer(0.1).timeout
	return condition.call()


func _press(root: Node, text: String) -> void:
	for button: Node in root.find_children("*", "Button", true, false):
		if (button as Button).text == text and (button as Button).is_visible_in_tree():
			(button as Button).pressed.emit()
			return
	failures.append("no se encontró el botón «%s»" % text)
