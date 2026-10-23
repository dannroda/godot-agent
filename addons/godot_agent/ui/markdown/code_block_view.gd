@tool
extends PanelContainer
## Bloque de código del chat: caja a todo el ancho con el lenguaje, botón para copiar y el código
## en monoespaciada con resaltado (CodeBBCode). Se puede seleccionar parte del texto.

const AgentTheme := preload("../agent_theme.gd")
const I18n := preload("../../core/i18n.gd")
const MarkdownBBCode := preload("markdown_bbcode.gd")

var _language: Label
var _copy: Button
var _label: RichTextLabel
var _code: String = ""
var _shown_language: String = ""


func _init() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_theme_stylebox_override(&"panel", AgentTheme.panel(Color(0, 0, 0, 0.28), Color(1, 1, 1, 0.07), 6, 0))
	var column := VBoxContainer.new()
	column.add_theme_constant_override(&"separation", 0)
	add_child(column)

	var header := HBoxContainer.new()
	var header_margin := MarginContainer.new()
	header_margin.add_theme_constant_override(&"margin_left", AgentTheme.px(8))
	header_margin.add_theme_constant_override(&"margin_right", AgentTheme.px(2))
	header_margin.add_child(header)
	column.add_child(header_margin)
	_language = Label.new()
	_language.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_language.add_theme_color_override(&"font_color", AgentTheme.MUTED)
	_language.add_theme_font_size_override(&"font_size", AgentTheme.px(11))
	header.add_child(_language)
	_copy = Button.new()
	_copy.flat = true
	_copy.icon = AgentTheme.icon(&"ActionCopy")
	_copy.text = "" if _copy.icon else I18n.t("Copy")
	_copy.tooltip_text = I18n.t("Copy code")
	_copy.focus_mode = Control.FOCUS_NONE
	_copy.pressed.connect(_on_copy)
	header.add_child(_copy)

	var body := MarginContainer.new()
	for side: String in ["left", "right"]:
		body.add_theme_constant_override("margin_" + side, AgentTheme.px(10))
	body.add_theme_constant_override(&"margin_bottom", AgentTheme.px(8))
	column.add_child(body)
	_label = RichTextLabel.new()
	_label.bbcode_enabled = true
	_label.fit_content = true
	_label.scroll_active = false
	_label.selection_enabled = true
	_label.context_menu_enabled = true
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_label.add_theme_font_override(&"normal_font", AgentTheme.mono_font())
	_label.add_theme_font_size_override(&"normal_font_size", AgentTheme.mono_font_size())
	body.add_child(_label)


## Cambia el contenido solo si cambió (el streaming lo llama una vez por frame).
func set_code(code: String, language: String, markdown: MarkdownBBCode) -> void:
	if code == _code and language == _shown_language and not _label.text.is_empty():
		return
	_code = code
	_shown_language = language
	_language.text = language if not language.is_empty() else I18n.t("code")
	_label.text = markdown.highlighter.highlight(code, language)


func _on_copy() -> void:
	DisplayServer.clipboard_set(_code)
	_copy.tooltip_text = I18n.t("Copied")
	_copy.modulate = Color(0.6, 1.0, 0.6)
	get_tree().create_timer(1.2).timeout.connect(func() -> void:
		if is_instance_valid(_copy):
			_copy.tooltip_text = I18n.t("Copy code")
			_copy.modulate = Color.WHITE
	)
