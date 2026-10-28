@tool
extends AcceptDialog
## Diálogo con un diff completo por líneas (conflictos, "Revisar cambios").

const AgentTheme := preload("agent_theme.gd")
const LineDiff := preload("../core/line_diff.gd")
const MarkdownBBCode := preload("markdown/markdown_bbcode.gd")

var _label: RichTextLabel


func _ready() -> void:
	min_size = Vector2i(AgentTheme.px(720), AgentTheme.px(480))
	_label = RichTextLabel.new()
	_label.bbcode_enabled = true
	_label.selection_enabled = true
	_label.add_theme_font_override(&"normal_font", AgentTheme.mono_font())
	_label.add_theme_font_size_override(&"normal_font_size", AgentTheme.mono_font_size())
	add_child(_label)


func show_diff(dialog_title: String, old_label: String, old_text: String, new_label: String, new_text: String) -> void:
	title = dialog_title
	_label.text = diff_bbcode(old_label, old_text, new_label, new_text)
	popup_centered_ratio(0.6)


## El diff por líneas en BBCode, con un encabezado de qué es cada lado y cuántas líneas cambian.
static func diff_bbcode(old_label: String, old_text: String, new_label: String, new_text: String) -> String:
	var ops := LineDiff.diff(old_text, new_text)
	var counts := LineDiff.count(ops)
	var lines: PackedStringArray = [
		"[color=%s]− %s[/color]   [color=%s]+ %s[/color]   (+%d −%d)\n" % [
			AgentTheme.color_hex(AgentTheme.REMOVED), old_label, AgentTheme.color_hex(AgentTheme.ADDED), new_label, counts.added, counts.removed
		]
	]
	for op: Dictionary in ops:
		var text := MarkdownBBCode.escape(str(op.text))
		match int(op.kind):
			LineDiff.ADD:
				lines.append("[bgcolor=#%s]+ %s[/bgcolor]" % [AgentTheme.ADDED_BG.to_html(true), text])
			LineDiff.REMOVE:
				lines.append("[bgcolor=#%s]− %s[/bgcolor]" % [AgentTheme.REMOVED_BG.to_html(true), text])
			_:
				lines.append("[color=#8a8f98]  %s[/color]" % text)
	return "\n".join(lines)
