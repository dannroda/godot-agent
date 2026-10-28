@tool
extends "entry_view.gd"
## Tarjeta de formulario o enlace del agente (m11-17, ACP `elicitation/create`).
## Renderiza campos `string`, `enum`/`oneOf`, `boolean`, `number`/`integer` y `array` (multi-select),
## o un botón para abrir el enlace en modo `url`.

const ElicitationRequest := preload("../../../session/elicitation_request.gd")

var _panel: PanelContainer
var _title: Label
var _message: Label
var _description: Label
var _fields_box: VBoxContainer
var _error_label: Label
var _buttons: HFlowContainer
var _result: Label
var _field_readers: Dictionary = {}  # prop_name -> Callable() -> Variant


func _build() -> void:
	_panel = PanelContainer.new()
	add_child(_panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override(&"separation", AgentTheme.px(6))
	_panel.add_child(column)
	var header := HBoxContainer.new()
	column.add_child(header)
	var icon_rect := TextureRect.new()
	icon_rect.texture = AgentTheme.icon(&"Help")
	icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	icon_rect.modulate = accent
	header.add_child(icon_rect)
	_title = Label.new()
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title.add_theme_color_override(&"font_color", accent)
	header.add_child(_title)
	_message = Label.new()
	_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_message)
	_description = Label.new()
	_description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_description.add_theme_color_override(&"font_color", AgentTheme.MUTED)
	column.add_child(_description)
	_fields_box = VBoxContainer.new()
	_fields_box.add_theme_constant_override(&"separation", AgentTheme.px(6))
	column.add_child(_fields_box)
	_error_label = Label.new()
	_error_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_error_label.add_theme_color_override(&"font_color", AgentTheme.ERROR)
	_error_label.visible = false
	column.add_child(_error_label)
	_buttons = HFlowContainer.new()
	column.add_child(_buttons)
	_result = Label.new()
	_result.add_theme_color_override(&"font_color", AgentTheme.MUTED)
	_result.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_result)
	_build_fields()


func _build_fields() -> void:
	_field_readers.clear()
	for child: Node in _fields_box.get_children():
		child.queue_free()
	var request: ElicitationRequest = entry.elicitation
	if request == null or request.mode != ElicitationRequest.MODE_FORM:
		return
	var props := request.properties()
	var defaults := request.default_values()
	for key: Variant in props:
		var name := str(key)
		var prop: Dictionary = props[key] if props[key] is Dictionary else {}
		var row := VBoxContainer.new()
		row.add_theme_constant_override(&"separation", AgentTheme.px(2))
		_fields_box.add_child(row)
		var prop_type := str(prop.get("type", "string"))
		var label_text := str(prop.get("title", name)) if prop.get("title") is String and not str(prop.title).is_empty() else name
		if request.is_required(name):
			label_text += " *"
		var desc_text := str(prop.get("description", "")) if prop.get("description") is String else ""
		# Un opcional sin default que el usuario no tocó no se manda: un CheckBox o un SpinBox no
		# tienen "vacío" y el agente recibiría un false o un 0 que nadie eligió.
		var touched := [request.is_required(name) or prop.get("default") != null]
		if prop_type == "boolean":
			var check := CheckBox.new()
			check.text = label_text
			check.button_pressed = defaults.get(name) == true
			check.tooltip_text = desc_text
			check.toggled.connect(func(_on: bool) -> void: touched[0] = true)
			row.add_child(check)
			_field_readers[name] = func() -> Variant: return check.button_pressed if touched[0] else null
			continue
		var label := Label.new()
		label.text = label_text
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		row.add_child(label)
		if not desc_text.is_empty():
			var hint := Label.new()
			hint.text = desc_text
			hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			hint.add_theme_color_override(&"font_color", AgentTheme.MUTED)
			hint.add_theme_font_size_override(&"font_size", AgentTheme.px(11))
			row.add_child(hint)
		match prop_type:
			"integer", "number":
				var spin := SpinBox.new()
				# step 0: sin redondear los number (las flechas siguen de a 1).
				spin.step = 1.0 if prop_type == "integer" else 0.0
				spin.custom_arrow_step = 1.0
				var minimum: Variant = prop.get("minimum")
				var maximum: Variant = prop.get("maximum")
				spin.allow_lesser = not (minimum is int or minimum is float)
				spin.allow_greater = not (maximum is int or maximum is float)
				if not spin.allow_lesser:
					spin.min_value = ceilf(float(minimum)) if prop_type == "integer" else float(minimum)
				if not spin.allow_greater:
					spin.max_value = floorf(float(maximum)) if prop_type == "integer" else float(maximum)
				var initial_value: Variant = defaults.get(name, 0)
				spin.value = float(initial_value) if (initial_value is int or initial_value is float) else spin.min_value if not spin.allow_lesser else 0.0
				spin.value_changed.connect(func(_value: float) -> void: touched[0] = true)
				row.add_child(spin)
				var is_int := prop_type == "integer"
				_field_readers[name] = func() -> Variant:
					if not touched[0]:
						return null
					return roundi(spin.value) if is_int else spin.value
			"array":
				var choices := ElicitationRequest.enum_choices(prop)
				var checks_box := VBoxContainer.new()
				row.add_child(checks_box)
				var initial: Array = defaults.get(name, []) if defaults.get(name) is Array else []
				var check_items: Array[Dictionary] = []
				for choice: Dictionary in choices:
					var item_check := CheckBox.new()
					item_check.text = str(choice.label)
					item_check.tooltip_text = str(choice.description)
					item_check.button_pressed = choice.value in initial
					checks_box.add_child(item_check)
					check_items.append({"value": str(choice.value), "control": item_check})
				_field_readers[name] = func() -> Variant:
					var selected: Array = []
					for item: Dictionary in check_items:
						if (item.control as CheckBox).button_pressed:
							selected.append(item.value)
					return selected
			_:
				var choices := ElicitationRequest.enum_choices(prop)
				if not choices.is_empty():
					var option_btn := OptionButton.new()
					option_btn.clip_text = true
					option_btn.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
					var values_list: PackedStringArray = []
					if not request.is_required(name):
						option_btn.add_item("—")
						values_list.append("")
					var def_val := str(defaults.get(name, ""))
					var selected_idx := 0
					for choice: Dictionary in choices:
						var idx := option_btn.item_count
						option_btn.add_item(str(choice.label))
						if not str(choice.description).is_empty():
							option_btn.set_item_tooltip(idx, str(choice.description))
						values_list.append(str(choice.value))
						if str(choice.value) == def_val:
							selected_idx = idx
					option_btn.select(selected_idx)
					row.add_child(option_btn)
					_field_readers[name] = func() -> Variant:
						var idx := option_btn.selected
						return values_list[idx] if idx >= 0 and idx < values_list.size() else ""
				else:
					var edit := LineEdit.new()
					edit.text = str(defaults.get(name, ""))
					edit.placeholder_text = desc_text
					row.add_child(edit)
					_field_readers[name] = func() -> Variant: return edit.text


func collect_values() -> Dictionary:
	var result: Dictionary = {}
	for name: String in _field_readers:
		var reader: Callable = _field_readers[name]
		var val: Variant = reader.call()
		if val == null:
			continue
		if val is String and str(val).is_empty():
			var request: ElicitationRequest = entry.elicitation
			if request and not request.is_required(name):
				continue
		result[name] = val
	return result


func refresh() -> void:
	var request: ElicitationRequest = entry.elicitation
	if request == null:
		return
	var pending := request.is_pending()
	_panel.add_theme_stylebox_override(&"panel", AgentTheme.panel(
		Color(accent, 0.10 if pending else 0.03), Color(accent, 0.8 if pending else 0.25), 6, 8
	))
	var schema_title := request.schema_title()
	if not schema_title.is_empty():
		_title.text = schema_title
	elif request.mode == ElicitationRequest.MODE_URL:
		_title.text = I18n.t("Confirmation link")
	else:
		_title.text = I18n.t("Agent question")
	_message.text = request.message
	if request.mode == ElicitationRequest.MODE_URL:  # el destino a la vista antes de abrirlo
		_message.text = (request.message + "\n" if not request.message.is_empty() else "") + request.url
	_message.visible = not _message.text.is_empty()
	var desc := request.schema_description()
	_description.text = desc
	_description.visible = not desc.is_empty() and desc != request.message
	_fields_box.visible = pending and request.mode == ElicitationRequest.MODE_FORM
	for child: Node in _buttons.get_children():
		child.queue_free()
	_buttons.visible = pending
	_result.visible = not pending
	if not pending:
		_error_label.visible = false
		_result.text = _result_text(request)
		return
	if request.mode == ElicitationRequest.MODE_URL:
		var open_btn := _primary_button(I18n.t("Open link"))
		open_btn.tooltip_text = request.url
		open_btn.pressed.connect(func() -> void:
			# Directo al navegador y solo http(s): «open_link» del chat también abre archivos locales.
			if ElicitationRequest.is_web_url(request.url):
				OS.shell_open(request.url.strip_edges())
			request.accept()
		)
		_buttons.add_child(open_btn)
	else:
		var submit_btn := _primary_button(I18n.t("Submit"))
		submit_btn.pressed.connect(_on_submit)
		_buttons.add_child(submit_btn)
	var decline_btn := Button.new()
	decline_btn.text = I18n.t("Decline")
	decline_btn.pressed.connect(func() -> void: request.decline())
	_buttons.add_child(decline_btn)
	var cancel_btn := Button.new()
	cancel_btn.flat = true
	cancel_btn.text = I18n.t("Cancel")
	cancel_btn.add_theme_color_override(&"font_color", AgentTheme.ERROR)
	cancel_btn.pressed.connect(func() -> void: request.cancel())
	_buttons.add_child(cancel_btn)


func _primary_button(label_text: String) -> Button:
	var button := Button.new()
	button.text = label_text
	button.add_theme_stylebox_override(&"normal", AgentTheme.panel(accent, Color.TRANSPARENT, 4, 5))
	button.add_theme_stylebox_override(&"hover", AgentTheme.panel(accent.lightened(0.15), Color.TRANSPARENT, 4, 5))
	button.add_theme_color_override(&"font_color", Color("#1d1d1d"))
	button.add_theme_color_override(&"font_hover_color", Color("#1d1d1d"))
	return button


func _on_submit() -> void:
	var request: ElicitationRequest = entry.elicitation
	if request == null or not request.is_pending():
		return
	var values := collect_values()
	var missing := request.validate(values)
	if not missing.is_empty():
		_error_label.text = I18n.t("Complete the required field: %s") % missing
		_error_label.visible = true
		return
	_error_label.visible = false
	request.accept(values)


static func _result_text(request: ElicitationRequest) -> String:
	if request.withdrawn:
		return "⇄ " + I18n.t("Answered elsewhere: from Remote Control, or no longer needed")
	if request.completed_by_agent:
		return "✓ " + I18n.t("Completed")
	match str(request.response.get("action", "")):
		ElicitationRequest.ACTION_ACCEPT:
			return "✓ " + I18n.t("Submitted")
		ElicitationRequest.ACTION_DECLINE:
			return "⊘ " + I18n.t("Declined")
	return "⊘ " + I18n.t("Cancelled")
