@tool
extends PanelContainer
## Tarjeta de diff: ruta, +N/−M, "Abrir en Script" y las primeras líneas cambiadas.

signal open_requested(path: String, line: int)

const AgentTheme := preload("../../agent_theme.gd")
const LineDiff := preload("../../../core/line_diff.gd")
const MarkdownBBCode := preload("../../markdown/markdown_bbcode.gd")

const PREVIEW_LINES := 8

var _path: String = ""
var _old_text: String = ""
var _new_text: String = ""
var _accent: Color


func setup_diff(block: Dictionary, accent: Color) -> void:
	_path = str(block.get("path", ""))
	_old_text = str(block.get("oldText")) if block.get("oldText") != null else ""
	_new_text = str(block.get("newText", ""))
	_accent = accent


func _ready() -> void:
	add_theme_stylebox_override(&"panel", AgentTheme.panel(AgentTheme.dark_color(), Color(1, 1, 1, 0.1), 6, 6))
	var column := VBoxContainer.new()
	add_child(column)
	var ops := LineDiff.diff(_old_text, _new_text)
	var counts := LineDiff.count(ops)

	var header := HBoxContainer.new()
	column.add_child(header)
	var path_label := Label.new()
	path_label.text = _path.get_file()
	path_label.tooltip_text = _path
	path_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	path_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	path_label.clip_text = true
	header.add_child(path_label)
	var added := Label.new()
	added.text = "+%d" % counts.added
	added.add_theme_color_override(&"font_color", AgentTheme.ADDED)
	header.add_child(added)
	var removed := Label.new()
	removed.text = "−%d" % counts.removed
	removed.add_theme_color_override(&"font_color", AgentTheme.REMOVED)
	header.add_child(removed)
	var open := Button.new()
	open.text = "Abrir en Script"
	open.flat = true
	open.add_theme_color_override(&"font_color", _accent)
	open.pressed.connect(func() -> void: open_requested.emit(_path, LineDiff.first_changed_line(ops)))
	header.add_child(open)

	var preview := RichTextLabel.new()
	preview.bbcode_enabled = true
	preview.fit_content = true
	preview.scroll_active = false
	preview.selection_enabled = true
	preview.autowrap_mode = TextServer.AUTOWRAP_OFF
	preview.clip_contents = true
	preview.add_theme_font_override(&"normal_font", AgentTheme.mono_font())
	preview.add_theme_font_size_override(&"normal_font_size", AgentTheme.mono_font_size())
	column.add_child(preview)
	var lines: PackedStringArray = []
	var shown := 0
	var changed_total: int = counts.added + counts.removed
	for op: Dictionary in ops:
		if op.kind == LineDiff.EQUAL:
			continue
		if shown >= PREVIEW_LINES:
			break
		var is_add: bool = op.kind == LineDiff.ADD
		var bg := AgentTheme.ADDED_BG if is_add else AgentTheme.REMOVED_BG
		lines.append("[bgcolor=%s]%s %s[/bgcolor]" % [
			"#" + bg.to_html(true), "+" if is_add else "−", MarkdownBBCode.escape(str(op.text))
		])
		shown += 1
	if changed_total > shown:
		lines.append("[color=#8a8f98]⋯ %d líneas más[/color]" % (changed_total - shown))
	preview.text = "\n".join(lines)
