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
const LayoutCheck := preload("layout_check.gd")
const PERMISSION_VIEW_SCRIPT := "res://addons/godot_agent/ui/dock/entries/permission_view.gd"
const NOTICE_VIEW_SCRIPT := "res://addons/godot_agent/ui/dock/entries/notice_view.gd"
const EDITED_FILE := "res://tests/tmp/remote_activity_edit.gd"
const CREATED_FILE := "res://tests/tmp/remote_activity_new.gd"
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
	for path: String in [EDITED_FILE, CREATED_FILE]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
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
	_write(EDITED_FILE, "extends Node\n")
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
	await _check_remote_files()
	await _tree.create_timer(0.3).timeout
	# Con la franja, la tarjeta y el aviso a la vista, el dock entra en su panel (m7-23).
	failures.append_array(LayoutCheck.dock_fits(_dock))
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


## «El celular» modifica un archivo y crea otro: aparece un aviso con los dos, el diff los muestra
## y «Deshacer» los deja como estaban.
func _check_remote_files() -> void:
	await _tree.create_timer(0.5).timeout
	_write(EDITED_FILE, "extends Node2D\n")
	_write(CREATED_FILE, "extends Node\n")
	var notice: Array = [null]
	var found := await _until(func() -> bool:
		for view: Node in _dock.find_children("*", "", true, false):
			if view.get_script() and (view.get_script() as Script).resource_path == NOTICE_VIEW_SCRIPT:
				var text := str(view.get(&"entry").get(&"text"))
				if text.contains(I18n.t("From Remote Control: %s") % ""):
					notice[0] = view
					return true
		return false)
	if not found:
		failures.append("no apareció el aviso de los archivos cambiados desde el celular")
		return
	var view: Control = notice[0]
	var text := str(view.get(&"entry").get(&"text"))
	if not (text.contains(EDITED_FILE.trim_prefix("res://")) and text.contains(CREATED_FILE.trim_prefix("res://"))):
		failures.append("el aviso no nombra los dos archivos: %s" % text)
	_press(view, I18n.t("View diff"))
	await _tree.create_timer(0.3).timeout
	var dialog: Window = null
	for node: Node in EditorInterface.get_base_control().get_children():
		if node is Window and node.has_method(&"show_diff") and (node as Window).visible:
			dialog = node
	if dialog == null:
		failures.append("«%s» no abrió el diff" % I18n.t("View diff"))
	else:
		dialog.hide()
	await _until(func() -> bool: return view.is_queued_for_deletion() or _find_button(view, I18n.t("Undo")) != null)
	_press(view, I18n.t("Undo"))
	await _tree.create_timer(0.3).timeout
	if FileAccess.get_file_as_string(EDITED_FILE) != "extends Node\n" or FileAccess.file_exists(CREATED_FILE):
		failures.append("«%s» no dejó los archivos como estaban" % I18n.t("Undo"))
	if not str(view.get(&"entry").get(&"text")).contains(I18n.t("Undone.")):
		failures.append("el aviso no dice que se deshizo")
	# Deshacer no cuenta como otro cambio del celular.
	await _tree.create_timer(4.5).timeout
	var notices := _dock.find_children("*", "", true, false).filter(func(node: Node) -> bool: return node.get_script() and (node.get_script() as Script).resource_path == NOTICE_VIEW_SCRIPT and str(node.get(&"entry").get(&"text")).contains(I18n.t("From Remote Control: %s") % ""))
	if notices.size() != 1:
		failures.append("después de deshacer hay %d avisos de Remote Control" % notices.size())


func _write(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()


func _find_button(root: Node, text: String) -> Button:
	for button: Node in root.find_children("*", "Button", true, false):
		if (button as Button).text == text and (button as Button).is_visible_in_tree() and not button.is_queued_for_deletion():
			return button
	return null


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
