@tool
extends RefCounted
## Conversor Markdown → BBCode de RichTextLabel, propio y mínimo (spec §9.1): párrafos, títulos,
## negrita, itálica, `code`, bloques de código, listas, citas, links y tablas (en mono).
## Tolerante: lo que no reconoce queda como texto escapado; nunca deja tags sin cerrar.

const FENCE := "```"
## Devuelto por _block_line para una línea que no se muestra (separador de tabla).
const _SKIP_LINE := "\u0002"

var code_color: String = "#f0a85a"
var muted_color: String = "#9aa0a6"
var code_bg_color: String = "#00000040"

var _re_code_span := RegEx.create_from_string("`([^`\\n]+)`")
var _re_link := RegEx.create_from_string("\\[([^\\]\\n]+)\\]\\(([^)\\s]+)\\)")
var _re_autolink := RegEx.create_from_string("<(https?://[^>\\s]+)>")
var _re_bold := RegEx.create_from_string("\\*\\*(?=\\S)(.+?)(?<=\\S)\\*\\*|__(?=\\S)(.+?)(?<=\\S)__")
var _re_italic := RegEx.create_from_string("(?<![\\*\\w])\\*(?=\\S)(.+?)(?<=\\S)\\*(?!\\*)|(?<![_\\w])_(?=\\S)(.+?)(?<=\\S)_(?![_\\w])")
var _re_strike := RegEx.create_from_string("~~(?=\\S)(.+?)(?<=\\S)~~")
var _re_heading := RegEx.create_from_string("^(#{1,6})\\s+(.*?)\\s*#*\\s*$")
var _re_bullet := RegEx.create_from_string("^(\\s*)[-*+]\\s+(.*)$")
var _re_ordered := RegEx.create_from_string("^(\\s*)(\\d+)[.)]\\s+(.*)$")
var _re_task := RegEx.create_from_string("^\\[([ xX])\\]\\s+(.*)$")
var _re_rule := RegEx.create_from_string("^\\s*([-*_])(\\s*\\1){2,}\\s*$")


func convert(markdown: String) -> String:
	var out: PackedStringArray = []
	var lines := markdown.replace("\r\n", "\n").split("\n")
	var in_code := false
	var code_lines: PackedStringArray = []
	var paragraph: PackedStringArray = []

	for raw_line: String in lines:
		var stripped := raw_line.strip_edges()
		if in_code:
			if stripped.begins_with(FENCE):
				out.append(_code_block(code_lines))
				code_lines.clear()
				in_code = false
			else:
				code_lines.append(raw_line)
			continue
		if stripped.begins_with(FENCE):
			_flush_paragraph(paragraph, out)
			in_code = true
			continue
		if stripped.is_empty():
			_flush_paragraph(paragraph, out)
			continue
		var block := _block_line(raw_line, stripped)
		if block == _SKIP_LINE:
			continue
		if block.is_empty():
			paragraph.append(inline(stripped))
		else:
			_flush_paragraph(paragraph, out)
			out.append(block)

	if in_code:
		out.append(_code_block(code_lines))
	_flush_paragraph(paragraph, out)
	return "\n".join(out)


## Línea de bloque (título, lista, cita, tabla, regla), "" si es texto de párrafo o _SKIP_LINE.
func _block_line(raw_line: String, stripped: String) -> String:
	var found := _re_heading.search(stripped)
	if found:
		var level := found.get_string(1).length()
		var size: int = [0, 130, 115, 100, 100, 100, 100][level]
		var title := inline(found.get_string(2))
		if size > 100:
			return "[font_size=%d][b]%s[/b][/font_size]" % [_scaled_size(size), title]
		return "[b]%s[/b]" % title
	if _re_rule.search(stripped):
		return "[color=%s]────────[/color]" % muted_color
	found = _re_bullet.search(raw_line)
	if found:
		var indent := _indent_level(found.get_string(1))
		var text := found.get_string(2)
		var task := _re_task.search(text)
		var marker := "•"
		if task:
			marker = "☑" if task.get_string(1).to_lower() == "x" else "☐"
			text = task.get_string(2)
		return "%s%s %s" % ["    ".repeat(indent + 1).left(-2), marker, inline(text)]
	found = _re_ordered.search(raw_line)
	if found:
		var indent := _indent_level(found.get_string(1))
		return "%s%s. %s" % ["    ".repeat(indent + 1).left(-2), found.get_string(2), inline(found.get_string(3))]
	if stripped.begins_with(">"):
		return "[color=%s]▎ [i]%s[/i][/color]" % [muted_color, inline(stripped.trim_prefix(">").strip_edges())]
	if stripped.begins_with("|") and stripped.ends_with("|"):
		if stripped.replace("|", "").replace("-", "").replace(":", "").strip_edges().is_empty():
			return _SKIP_LINE
		return "[code]%s[/code]" % escape(stripped)
	return ""


func _flush_paragraph(paragraph: PackedStringArray, out: PackedStringArray) -> void:
	if paragraph.is_empty():
		return
	out.append(" ".join(paragraph))
	paragraph.clear()


func _code_block(code_lines: PackedStringArray) -> String:
	return "[bgcolor=%s][code]%s[/code][/bgcolor]" % [code_bg_color, escape("\n".join(code_lines))]


## Formato en línea: `code`, links, negrita, itálica y tachado. El texto se escapa.
func inline(text: String) -> String:
	var result := ""
	var position := 0
	for found: RegExMatch in _re_code_span.search_all(text):
		result += _inline_text(text.substr(position, found.get_start() - position))
		result += "[code][color=%s]%s[/color][/code]" % [code_color, escape(found.get_string(1))]
		position = found.get_end()
	result += _inline_text(text.substr(position))
	return result


## Texto sin code spans: links primero (necesitan los corchetes sin escapar), después énfasis.
func _inline_text(text: String) -> String:
	var result := ""
	var position := 0
	var matches: Array[RegExMatch] = []
	matches.append_array(_re_link.search_all(text))
	matches.append_array(_re_autolink.search_all(text))
	matches.sort_custom(func(a: RegExMatch, b: RegExMatch) -> bool: return a.get_start() < b.get_start())
	for found: RegExMatch in matches:
		if found.get_start() < position:
			continue
		result += _emphasis(escape(text.substr(position, found.get_start() - position)))
		var url := found.get_string(2) if found.get_group_count() >= 2 else found.get_string(1)
		var label := found.get_string(1)
		result += "[url=%s]%s[/url]" % [url.replace("]", "%5D"), _emphasis(escape(label))]
		position = found.get_end()
	result += _emphasis(escape(text.substr(position)))
	return result


func _emphasis(text: String) -> String:
	text = _replace_pairs(_re_bold, text, "b")
	text = _replace_pairs(_re_strike, text, "s")
	text = _replace_pairs(_re_italic, text, "i")
	return text


func _replace_pairs(regex: RegEx, text: String, tag: String) -> String:
	var result := ""
	var position := 0
	for found: RegExMatch in regex.search_all(text):
		var inner := found.get_string(1)
		if inner.is_empty() and found.get_group_count() >= 2:
			inner = found.get_string(2)
		result += text.substr(position, found.get_start() - position)
		result += "[%s]%s[/%s]" % [tag, inner, tag]
		position = found.get_end()
	return result + text.substr(position)


static func escape(text: String) -> String:
	return text.replace("[", "\u0001").replace("]", "[rb]").replace("\u0001", "[lb]")


static func _indent_level(spaces: String) -> int:
	return spaces.replace("\t", "    ").length() / 2


static func _scaled_size(percent: int) -> int:
	var base := 14
	if Engine.is_editor_hint() and Engine.has_singleton(&"EditorInterface"):
		var theme := EditorInterface.get_editor_theme()
		if theme.has_font_size(&"main_size", &"EditorFonts"):
			base = theme.get_font_size(&"main_size", &"EditorFonts")
	return int(base * percent / 100.0)
