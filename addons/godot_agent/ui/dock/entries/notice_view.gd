@tool
extends "entry_view.gd"
## Aviso del harness (cancelación, errores de transporte…) con acciones concretas (spec §15).
## Una acción `primary` va con el color de acento; las que traen `more` (el texto del menú) van
## juntas en ese menú, después de los botones (p. ej. «Otras formas de entrar», m12-11).

var _panel: PanelContainer
var _title: Label
var _label: Label
## Las últimas líneas del log (m12-13), con «Copiar».
var _details: PanelContainer
var _details_text: Label
var _actions: HFlowContainer


func _build() -> void:
	_panel = PanelContainer.new()
	add_child(_panel)
	var column := VBoxContainer.new()
	_panel.add_child(column)
	_title = Label.new()
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var theme := AgentTheme.editor_theme()
	if theme.has_font(&"bold", &"EditorFonts"):
		_title.add_theme_font_override(&"font", theme.get_font(&"bold", &"EditorFonts"))
	_title.add_theme_font_size_override(&"font_size", AgentTheme.px(15))
	column.add_child(_title)
	_label = Label.new()
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_label)
	_details = PanelContainer.new()
	_details.add_theme_stylebox_override(&"panel", AgentTheme.panel(Color(0, 0, 0, 0.25), Color.TRANSPARENT, 4, 6))
	column.add_child(_details)
	var details_column := VBoxContainer.new()
	_details.add_child(details_column)
	var details_header := HBoxContainer.new()
	details_column.add_child(details_header)
	var details_title := Label.new()
	details_title.text = I18n.t("Last lines of the log")
	details_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	details_title.add_theme_color_override(&"font_color", AgentTheme.MUTED)
	details_header.add_child(details_title)
	var copy := Button.new()
	copy.flat = true
	copy.text = I18n.t("Copy")
	copy.pressed.connect(func() -> void: DisplayServer.clipboard_set(entry.details))
	details_header.add_child(copy)
	_details_text = Label.new()
	_details_text.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	_details_text.add_theme_font_override(&"font", AgentTheme.mono_font())
	_details_text.add_theme_font_size_override(&"font_size", AgentTheme.mono_font_size())
	_details_text.add_theme_color_override(&"font_color", AgentTheme.MUTED)
	details_column.add_child(_details_text)
	_actions = HFlowContainer.new()
	_actions.alignment = FlowContainer.ALIGNMENT_END
	column.add_child(_actions)


func refresh() -> void:
	var color := AgentTheme.MUTED
	match entry.level:
		ChatEntry.NoticeLevel.WARNING:
			color = AgentTheme.WARNING
		ChatEntry.NoticeLevel.ERROR:
			color = AgentTheme.ERROR
	# Un aviso que pide algo (tiene acción principal) va en una tarjeta neutra, alineado a la izquierda.
	var asks := entry.level == ChatEntry.NoticeLevel.INFO and entry.actions.any(func(action: Dictionary) -> bool: return bool(action.get("primary", false)))
	var bg := Color(color, 0.08) if entry.level != ChatEntry.NoticeLevel.INFO else (Color(1, 1, 1, 0.04) if asks else Color.TRANSPARENT)
	var border := Color(color, 0.5) if entry.level != ChatEntry.NoticeLevel.INFO else (Color(1, 1, 1, 0.12) if asks else Color.TRANSPARENT)
	_panel.add_theme_stylebox_override(&"panel", AgentTheme.panel(bg, border, 6, 8 if asks else 6))
	if entry.footer:
		# Pie del turno (m12-20): una línea arriba, el texto a la izquierda y las acciones como enlaces.
		var footer_box := AgentTheme.panel(Color.TRANSPARENT, Color.TRANSPARENT, 0, 4)
		footer_box.border_width_top = 1
		footer_box.border_color = Color(1, 1, 1, 0.1)
		_panel.add_theme_stylebox_override(&"panel", footer_box)
	_title.text = entry.title
	_title.visible = not entry.title.is_empty()
	_title.add_theme_color_override(&"font_color", color)
	_details_text.text = entry.details
	_details.visible = not entry.details.is_empty()
	_label.text = entry.text
	if asks or not entry.title.is_empty():
		_label.remove_theme_color_override(&"font_color")
	else:
		_label.add_theme_color_override(&"font_color", color if entry.level != ChatEntry.NoticeLevel.INFO else AgentTheme.MUTED)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER if entry.level == ChatEntry.NoticeLevel.INFO and not asks and not entry.footer else HORIZONTAL_ALIGNMENT_LEFT
	_actions.alignment = FlowContainer.ALIGNMENT_BEGIN if asks or entry.footer else FlowContainer.ALIGNMENT_END
	for child: Node in _actions.get_children():
		child.queue_free()
	var menus: Dictionary = {}  # texto del menú -> MenuButton
	for action: Dictionary in entry.actions:
		var emit := func() -> void: action_requested.emit(str(action.id), action.get("data", entry))
		var label := str(action.get("label", action.get("id", "")))
		var more := str(action.get("more", ""))
		if not more.is_empty():
			var menu: MenuButton = menus.get(more)
			if menu == null:
				menu = MenuButton.new()
				menu.text = more + " ▾"
				menu.flat = false
				menu.get_popup().id_pressed.connect(func(index: int) -> void: (menu.get_meta(&"actions") as Array)[index].call())
				menu.set_meta(&"actions", [])
				menus[more] = menu
			menu.get_popup().add_item(label, menu.get_popup().item_count)
			(menu.get_meta(&"actions") as Array).append(emit)
			continue
		var button := Button.new()
		button.text = label
		button.tooltip_text = str(action.get("tooltip", ""))
		if bool(action.get("primary", false)):
			AgentTheme.style_accent_button(button, accent, 4, 6)
		elif entry.footer:
			button.flat = true
			button.add_theme_color_override(&"font_color", accent)
		button.pressed.connect(emit)
		_actions.add_child(button)
	for more: String in menus:
		_actions.add_child(menus[more])
	_actions.visible = not entry.actions.is_empty()
