@tool
extends "entry_view.gd"
## Burbuja del usuario, a la derecha (mockup: fondo #33405a). Un prompt que armó el harness (One-shot,
## el chequeo después del turno, Revisar…, ver HarnessPrompts) sale atenuado y plegado: una línea con
## su etiqueta en el idioma de la interfaz y «Ver prompt» para leer lo que recibió el agente (m12-44).

const MAX_WIDTH_RATIO := 0.85

var _row: HBoxContainer
var _spacer: Control
var _bubble: PanelContainer
var _label: Label
var _attachments: Label
var _header: HBoxContainer
var _caption: Label
var _toggle: Button
var _expanded: bool = false


func _build() -> void:
	_row = HBoxContainer.new()
	add_child(_row)
	_spacer = Control.new()
	_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_row.add_child(_spacer)
	_bubble = PanelContainer.new()
	_bubble.add_theme_stylebox_override(&"panel", AgentTheme.panel(AgentTheme.USER_BUBBLE, Color.TRANSPARENT, 8, 8))
	_row.add_child(_bubble)
	var column := VBoxContainer.new()
	_bubble.add_child(column)
	_header = HBoxContainer.new()
	column.add_child(_header)
	_caption = Label.new()
	_caption.name = "HarnessCaption"
	_caption.add_theme_color_override(&"font_color", AgentTheme.MUTED)
	# Una línea: si el dock es angosto, se corta con «…» y la etiqueta entera va en el tooltip.
	_caption.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_caption.mouse_filter = Control.MOUSE_FILTER_PASS
	_caption.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_header.add_child(_caption)
	_toggle = Button.new()
	_toggle.name = "HarnessToggle"
	_toggle.flat = true
	_toggle.focus_mode = Control.FOCUS_NONE
	_toggle.add_theme_color_override(&"font_color", AgentTheme.MUTED)
	_toggle.pressed.connect(_on_toggle)
	_header.add_child(_toggle)
	_label = Label.new()
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_label)
	_attachments = Label.new()
	_attachments.add_theme_color_override(&"font_color", AgentTheme.MUTED)
	_attachments.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_attachments)
	resized.connect(_fit_width)


func is_harness() -> bool:
	return entry != null and not entry.harness_label.is_empty()


func is_expanded() -> bool:
	return _expanded


func refresh() -> void:
	var harness := is_harness()
	_header.visible = harness
	if harness:
		_caption.text = "⚙ " + I18n.t(entry.harness_label)
		_caption.tooltip_text = I18n.t(entry.harness_label)
		_toggle.text = I18n.t("Hide prompt") if _expanded else I18n.t("Show prompt")
		_toggle.tooltip_text = I18n.t("What the harness sent to the agent, as the agent got it")
	_bubble.add_theme_stylebox_override(&"panel", AgentTheme.panel(Color(AgentTheme.USER_BUBBLE, 0.3), Color(AgentTheme.USER_BUBBLE, 0.9), 8, 6)
		if harness else AgentTheme.panel(AgentTheme.USER_BUBBLE, Color.TRANSPARENT, 8, 8))
	if harness:
		_label.add_theme_color_override(&"font_color", AgentTheme.MUTED)
	else:
		_label.remove_theme_color_override(&"font_color")
	_label.text = entry.text
	_label.visible = not harness or _expanded
	# Del harness, a todo el ancho del chat: no es una burbuja del usuario.
	_spacer.visible = not harness
	_bubble.size_flags_horizontal = Control.SIZE_EXPAND_FILL if harness else Control.SIZE_FILL
	var names: PackedStringArray = []
	for block: Dictionary in entry.attachments:
		names.append(_attachment_name(block))
	_attachments.text = "📎 " + " · ".join(names) if not names.is_empty() else ""
	_attachments.visible = not names.is_empty()
	_fit_width()


func _on_toggle() -> void:
	_expanded = not _expanded
	refresh()


## La burbuja se ajusta al texto hasta el 85% del ancho del dock. Al ancho del texto se suman los
## márgenes del estilo `normal` del Label (en el tema del editor, 6 px por lado): sin ellos, el
## texto tenía menos lugar que su ancho y se partía letra por letra (m13-21).
func _fit_width() -> void:
	if _label == null or size.x <= 0.0:
		return
	if is_harness():  # a todo el ancho: el texto desplegado se parte en el ancho del chat
		_label.custom_minimum_size.x = 0.0
		return
	var font := _label.get_theme_font(&"font")
	var font_size := _label.get_theme_font_size(&"font_size")
	var widest := 0.0
	for line: String in (entry.text + "\n" + _attachments.text).split("\n"):
		widest = maxf(widest, font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x)
	var style := _label.get_theme_stylebox(&"normal")
	var margins := style.get_minimum_size().x if style else 0.0
	var max_width := size.x * MAX_WIDTH_RATIO - AgentTheme.px(16)
	_label.custom_minimum_size.x = minf(ceilf(widest) + margins + 2.0, max_width)


static func _attachment_name(block: Dictionary) -> String:
	match str(block.get("type", "")):
		"image":
			return I18n.t("screenshot")
		"resource_link":
			return str(block.get("name", block.get("uri", "")))
		"resource":
			var resource: Variant = block.get("resource")
			return str(resource.get("uri", I18n.t("resource"))).get_file() if resource is Dictionary else I18n.t("resource")
	return str(block.get("type", "?"))
