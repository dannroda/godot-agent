@tool
extends RefCounted
## Piezas de UI de la ventana Extensions y sus pestañas: tarjetas, secciones y textos.

const AgentTheme := preload("../agent_theme.gd")


static func card() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override(&"panel", AgentTheme.panel(Color(1, 1, 1, 0.04), Color(1, 1, 1, 0.1), 6, 8))
	return panel


static func section(text: String) -> Label:
	var label := Label.new()
	label.text = text.to_upper()
	label.add_theme_font_size_override(&"font_size", AgentTheme.px(11))
	label.add_theme_color_override(&"font_color", AgentTheme.MUTED)
	return label


static func muted(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override(&"font_size", AgentTheme.px(12))
	label.add_theme_color_override(&"font_color", AgentTheme.MUTED)
	return label


static func error_label(text: String) -> Label:
	var label := muted(text)
	label.add_theme_color_override(&"font_color", AgentTheme.ERROR)
	return label


static func icon_button(icon_name: StringName, tooltip: String, action: Callable) -> Button:
	var button := Button.new()
	button.flat = true
	button.icon = AgentTheme.icon(icon_name)
	if button.icon == null:
		button.text = tooltip
	button.tooltip_text = tooltip
	button.pressed.connect(action)
	return button


static func tab_page(tab_name: String) -> VBoxContainer:
	var margin := MarginContainer.new()
	margin.name = tab_name
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, AgentTheme.px(6))
	var page := VBoxContainer.new()
	page.add_theme_constant_override(&"separation", AgentTheme.px(6))
	margin.add_child(page)
	return page


static func scroll_list(page: VBoxContainer) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.add_child(scroll)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override(&"separation", AgentTheme.px(6))
	scroll.add_child(box)
	return box


## Con wrap_controls = false, un AcceptDialog acomoda su contenido solo al cambiar de tamaño: un
## texto con autowrap se mide primero con ancho ~0, deja el contenido altísimo y queda debajo de los
## botones (m12-01). Un frame después de abrirlo, el aviso de tema lo vuelve a acomodar.
static func refit_dialog(dialog: AcceptDialog) -> void:
	await dialog.get_tree().process_frame
	if is_instance_valid(dialog) and dialog.visible:
		dialog.notification(Window.NOTIFICATION_THEME_CHANGED)


static func clear(box: Container) -> void:
	for child: Node in box.get_children():
		box.remove_child(child)
		child.queue_free()
