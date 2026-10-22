@tool
extends "entry_view.gd"
## Burbuja del usuario, a la derecha (mockup: fondo #33405a).

const MAX_WIDTH_RATIO := 0.85

var _row: HBoxContainer
var _bubble: PanelContainer
var _label: Label
var _attachments: Label


func _build() -> void:
	_row = HBoxContainer.new()
	add_child(_row)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_row.add_child(spacer)
	_bubble = PanelContainer.new()
	_bubble.add_theme_stylebox_override(&"panel", AgentTheme.panel(AgentTheme.USER_BUBBLE, Color.TRANSPARENT, 8, 8))
	_row.add_child(_bubble)
	var column := VBoxContainer.new()
	_bubble.add_child(column)
	_label = Label.new()
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_label)
	_attachments = Label.new()
	_attachments.add_theme_color_override(&"font_color", AgentTheme.MUTED)
	_attachments.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_attachments)
	resized.connect(_fit_width)


func refresh() -> void:
	_label.text = entry.text
	var names: PackedStringArray = []
	for block: Dictionary in entry.attachments:
		names.append(_attachment_name(block))
	_attachments.text = "📎 " + " · ".join(names) if not names.is_empty() else ""
	_attachments.visible = not names.is_empty()
	_fit_width()


## La burbuja se ajusta al texto hasta el 85% del ancho del dock.
func _fit_width() -> void:
	if _label == null or size.x <= 0.0:
		return
	var font := _label.get_theme_font(&"font")
	var font_size := _label.get_theme_font_size(&"font_size")
	var widest := 0.0
	for line: String in (entry.text + "\n" + _attachments.text).split("\n"):
		widest = maxf(widest, font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x)
	var max_width := size.x * MAX_WIDTH_RATIO - AgentTheme.px(16)
	_label.custom_minimum_size.x = minf(widest + 2.0, max_width)


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
