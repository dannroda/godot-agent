@tool
extends RefCounted
## Verificación del modo Auto (D57) en el editor, todo por la UI: el botón Auto del dock, un turno
## del agente falso (tests/scripts/auto_shell.json) con las tarjetas resueltas con sus botones
## («Permitir siempre» con el patrón editado), la regla nueva guardada en project_config.tres, el
## log de permisos, y la sección «Modo Auto» de Settings → Permisos (ver la regla, borrarla y guardar).
## Deja project_config.tres como estaba.

const AgentProfile := preload("res://addons/godot_agent/core/agent_profile.gd")
const AgentLog := preload("res://addons/godot_agent/core/agent_log.gd")
const I18n := preload("res://addons/godot_agent/core/i18n.gd")
const SessionModel := preload("res://addons/godot_agent/session/session_model.gd")
const ShellRules := preload("res://addons/godot_agent/session/shell_rules.gd")
const ProjectConfig := preload("res://addons/godot_agent/config/project_config.gd")
const DOCK_SCRIPT := "res://addons/godot_agent/ui/dock/agent_dock.gd"
const PERMISSION_VIEW_SCRIPT := "res://addons/godot_agent/ui/dock/entries/permission_view.gd"
const AUTO_RULES_SCRIPT := "res://addons/godot_agent/ui/settings/auto_rules_page.gd"
const TURN_TIMEOUT_S := 40.0
const CARD_RULE := "npm test *"

var failures: PackedStringArray = []
var _tree: SceneTree
var _dock: Control
var _model: Object
var _controller: Object


func run_auto(tree: SceneTree, shot_prefix: String = "") -> PackedStringArray:
	_tree = tree
	var config_path := ProjectSettings.globalize_path(ProjectConfig.PATH)
	var had_config := FileAccess.file_exists(config_path)
	var config_before := FileAccess.get_file_as_bytes(config_path) if had_config else PackedByteArray()
	await _run(shot_prefix)
	if _controller:
		_controller.call(&"stop")
	if had_config:
		var file := FileAccess.open(config_path, FileAccess.WRITE)
		file.store_buffer(config_before)
		file.close()
	else:
		DirAccess.remove_absolute(config_path)
	return failures


func _run(shot_prefix: String) -> void:
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

	# El modo se elige en el selector del composer (m7-32), entre Construir y One-shot.
	var composer: Object = _dock.get(&"_composer")
	var mode_button: OptionButton = composer.get(&"_mode_button")
	var auto_index := mode_button.get_item_index(SessionModel.HarnessMode.AUTO)
	if auto_index < 0:
		failures.append("el selector de modo no tiene Auto")
		return
	if auto_index != mode_button.get_item_index(SessionModel.HarnessMode.BUILD) + 1:
		failures.append("Auto no está después de Construir")
	if mode_button.get_item_tooltip(auto_index).is_empty():
		failures.append("Auto no tiene tooltip en el selector")
	composer.call(&"choose_mode", SessionModel.HarnessMode.AUTO)
	if _model.get(&"harness_mode") != SessionModel.HarnessMode.AUTO:
		failures.append("el botón no pasó a modo Auto")
		return

	var profile := AgentProfile.from_dict({
		"id": "fake", "display_name": "Agente falso", "command": OS.get_executable_path(),
		"args": ["--headless", "--no-header", "--path", ProjectSettings.globalize_path("res://"),
			"--script", "res://tests/fake_agent.gd", "--", "--scenario=res://tests/scripts/auto_shell.json"],
	})
	if not await _controller.call(&"start", profile):
		failures.append("no arrancó la sesión: %s" % _model.get(&"failure_message"))
		return
	_dock.call(&"_on_submitted", "auto")
	var cards := await _answer_cards(shot_prefix)
	if cards != ["rm -rf /tmp/godot_agent_auto", "npm test", "echo hola > /tmp/godot_agent_auto.txt"]:
		failures.append("tarjetas: %s" % str(cards))

	var rules: Array = _controller.get(&"shell_rules")
	var added: Array = rules.filter(func(rule: Dictionary) -> bool: return rule.origin == ShellRules.ORIGIN_CARD)
	if added.size() != 1 or added[0].pattern != CARD_RULE:
		failures.append("regla agregada desde la tarjeta: %s" % str(added))
	var saved := FileAccess.get_file_as_string(ProjectConfig.PATH)
	if not saved.contains(CARD_RULE):
		failures.append("la regla no quedó guardada en %s" % ProjectConfig.PATH)
	var log: AgentLog = _controller.get(&"agent_log")
	var perm := "\n".join(log.entries().filter(func(entry: Dictionary) -> bool: return entry.channel == AgentLog.CH_PERM).map(func(entry: Dictionary) -> String: return str(entry.message)))
	for expected: String in ["allowed by Auto mode, on the allowlist (ls *, git status *)", "Auto mode asks, «rm -rf /tmp/godot_agent_auto» is on the ask list (rm *)", "rule added to the Auto allow list: npm test *", "allowed by Auto mode, on the allowlist (npm test *)"]:
		if not perm.contains(expected):
			failures.append("falta en el log de permisos: %s" % expected)

	await _check_settings(shot_prefix)


## Responde las tarjetas con sus botones: «Permitir siempre» con el patrón editado para npm test y
## Denegar para las demás. Devuelve los títulos en orden.
func _answer_cards(shot_prefix: String) -> Array[String]:
	var titles: Array[String] = []
	var answered := {}
	var deadline := Time.get_ticks_msec() + int(TURN_TIMEOUT_S * 1000)
	while Time.get_ticks_msec() < deadline:
		await _tree.create_timer(0.1).timeout
		for view: Node in _dock.find_children("*", "", true, false):
			if not view.get_script() or (view.get_script() as Script).resource_path != PERMISSION_VIEW_SCRIPT:
				continue
			var request: Object = view.get(&"entry").get(&"permission")
			if not request.call(&"is_pending") or answered.has(request.get_instance_id()):
				continue
			# La tarjeta arma sus botones en el refresh que le sigue: se espera a que estén.
			if not _find_button(view.get(&"_buttons"), I18n.t("Deny")):
				continue
			answered[request.get_instance_id()] = true
			var title := str(request.get(&"title"))
			titles.append(title)
			var rule_row: Control = view.get(&"_rule_row")
			if title == "npm test":
				if not rule_row.visible:
					failures.append("la tarjeta de npm test no muestra «Permitir siempre»")
					continue
				var edit: LineEdit = view.get(&"_rule_edit")
				if edit.text != "npm test":
					failures.append("patrón propuesto: %s" % edit.text)
				edit.text = CARD_RULE
				if not shot_prefix.is_empty():
					await _tree.create_timer(0.3).timeout
					_shot(shot_prefix + "card.png")
				_press(rule_row, I18n.t("Always allow"))
			else:
				if rule_row.visible:
					failures.append("«%s» no debería ofrecer «Permitir siempre»" % title)
				_press(view.get(&"_buttons"), I18n.t("Deny"))
			var session_always := (view.get(&"_buttons") as Node).get_children().any(func(button: Node) -> bool: return button is Button and (button as Button).text == I18n.t("Always allow in this session"))
			if session_always:
				failures.append("«%s» ofrece «siempre en esta sesión» en Auto" % title)
		if not _model.call(&"is_busy") and titles.size() >= 3:
			break
	if _model.call(&"is_busy"):
		failures.append("el turno no terminó en %d s" % TURN_TIMEOUT_S)
	await _tree.create_timer(0.2).timeout
	for view: Node in _dock.find_children("*", "", true, false):
		if view.get_script() and (view.get_script() as Script).resource_path == PERMISSION_VIEW_SCRIPT and str(view.get(&"entry").get(&"permission").get(&"title")) == "npm test":
			var result: Label = view.get(&"_result")
			if not result.text.contains(CARD_RULE):
				failures.append("la tarjeta resuelta no dice qué regla se agregó: %s" % result.text)
	return titles


func _check_settings(shot_prefix: String) -> void:
	(_dock.get(&"_settings_button") as Button).pressed.emit()
	await _tree.create_timer(0.5).timeout
	var dialog: ConfirmationDialog = null
	for node: Node in EditorInterface.get_base_control().get_children():
		if node is ConfirmationDialog and node.has_method(&"matrix_overrides"):
			dialog = node
	if dialog == null:
		failures.append("el botón de Settings no abrió el diálogo")
		return
	var nav: ItemList = dialog.get(&"_nav")
	nav.select(1)
	nav.item_selected.emit(1)
	await _tree.create_timer(0.3).timeout
	var matrix: Dictionary = dialog.get(&"_matrix")
	if not (matrix.get("shell", {}) as Dictionary).has(SessionModel.HarnessMode.AUTO):
		failures.append("la matriz de Settings no tiene la columna Auto")
	var page: Node = null
	for node: Node in dialog.find_children("*", "", true, false):
		if node.get_script() and (node.get_script() as Script).resource_path == AUTO_RULES_SCRIPT:
			page = node
	if page == null:
		failures.append("Settings → Permisos no tiene la sección del modo Auto")
		dialog.hide()
		return
	var tree: Tree = page.get(&"_tree")
	var row: TreeItem = null
	for item: TreeItem in tree.get_root().get_children():
		if item.get_text(0) == CARD_RULE:
			row = item
	if row == null:
		failures.append("la regla de la tarjeta no aparece en Settings")
		dialog.hide()
		return
	if row.get_text(2) != I18n.t("From a permission card") or row.get_text(3).is_empty():
		failures.append("origen y fecha de la regla: %s · %s" % [row.get_text(2), row.get_text(3)])
	# Probar un comando (m2-10): con la regla de la tarjeta, «npm test --watch» corre sin preguntar y
	# la fila de esa regla queda resaltada; «git push» pregunta.
	var test_edit: LineEdit = page.get(&"_test_edit")
	var test_result: Label = page.get(&"_test_result")
	test_edit.text = "ls && npm test --watch"
	test_edit.text_changed.emit(test_edit.text)
	var expected := I18n.t("Runs without asking: every part is on the allowlist (%s).") % ("ls *, " + CARD_RULE)
	if not test_result.visible or test_result.text != expected:
		failures.append("prueba de comando: «%s»" % test_result.text)
	var highlighted := false
	for item: TreeItem in tree.get_root().get_children():
		if item.get_text(0) == CARD_RULE and item.get_custom_bg_color(0).a > 0.0:
			highlighted = true
	if not highlighted:
		failures.append("la regla que decidió no se resalta en la tabla")
	test_edit.text = "git push origin main"
	test_edit.text_changed.emit(test_edit.text)
	if not test_result.text.begins_with(I18n.t("Asks: «%s» is on the «Always ask» list (%s).").get_slice("«", 0)):
		failures.append("prueba de git push: «%s»" % test_result.text)
	test_edit.text = "ls && npm test --watch"
	test_edit.text_changed.emit(test_edit.text)
	# Filtro «agregadas por vos o desde tarjetas»: solo esa.
	var filter: OptionButton = page.get(&"_filter")
	filter.select(3)
	filter.item_selected.emit(3)
	var shown := tree.get_root().get_child_count()
	if shown != 1:
		failures.append("el filtro de reglas agregadas muestra %d" % shown)
	if not shot_prefix.is_empty():
		var scroll := page.get_parent().get_parent() as ScrollContainer
		if scroll:
			scroll.ensure_control_visible.call_deferred(page)
		await _tree.create_timer(0.3).timeout
		dialog.get_texture().get_image().save_png(shot_prefix + "settings.png")
	tree.get_root().get_child(0).select(0)
	_press(page, I18n.t("Remove selected"))
	dialog.call(&"_on_save")
	await _tree.create_timer(0.3).timeout
	if dialog.visible:
		failures.append("Settings no se guardó: %s" % (dialog.get(&"_error_label") as Label).text)
		dialog.hide()
	var rules: Array = _controller.get(&"shell_rules")
	if rules.any(func(rule: Dictionary) -> bool: return rule.pattern == CARD_RULE):
		failures.append("la regla borrada en Settings sigue en el controller")
	if FileAccess.get_file_as_string(ProjectConfig.PATH).contains(CARD_RULE):
		failures.append("la regla borrada sigue en %s" % ProjectConfig.PATH)


func _press(root: Node, text: String) -> void:
	var button := _find_button(root, text)
	if button:
		button.pressed.emit()
	else:
		failures.append("no se encontró el botón «%s»" % text)


func _find_button(root: Node, text: String) -> Button:
	for button: Node in root.find_children("*", "Button", true, false):
		if (button as Button).text == text and not button.is_queued_for_deletion() and (button as Button).is_visible_in_tree():
			return button
	return null


func _shot(path: String) -> void:
	EditorInterface.get_base_control().get_viewport().get_texture().get_image().save_png(path)
