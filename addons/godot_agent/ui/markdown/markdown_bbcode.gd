@tool
extends RefCounted
## Conversor Markdown → BBCode de RichTextLabel, propio y mínimo (spec §9.1): párrafos, títulos,
## negrita, itálica, `code`, bloques de código, listas (anidadas), citas, links y tablas (en mono).
## Tolerante: lo que no reconoce queda como texto escapado; nunca deja tags sin cerrar.

const FENCES: PackedStringArray = ["```", "~~~"]
## Devuelto por _block_line para una línea que no se muestra (separador de tabla).
const _SKIP_LINE := "\u0002"
## Caracteres de uso privado: `\X` se guarda como ESCAPE_BASE + X y cada code span como
## SPAN_BASE + índice hasta el final del formato en línea.
const _ESCAPE_BASE := 0xE000
const _SPAN_BASE := 0xE100
const _MAX_SPANS := 0x700

var code_color: String = "#f0a85a"
var muted_color: String = "#9aa0a6"
var code_bg_color: String = "#00000040"

var _re_escape := RegEx.create_from_string("\\\\([!-/:-@\\[-`{-~])")
var _re_code_span := RegEx.create_from_string("(?<!`)(`+)(?!`)(.+?)(?<!`)\\1(?!`)")
var _re_link := RegEx.create_from_string("\\[([^\\]\\n]+)\\]\\(((?:[^()\\s]|\\([^()\\s]*\\))+)\\)")
var _re_autolink := RegEx.create_from_string("<(https?://[^>\\s]+)>")
var _re_bold_italic := RegEx.create_from_string("\\*\\*\\*(?=\\S)(.+?)(?<=\\S)\\*\\*\\*|___(?=\\S)(.+?)(?<=\\S)___")
var _re_bold := RegEx.create_from_string("\\*\\*(?=\\S)(.+?)(?<=\\S)\\*\\*|__(?=\\S)(.+?)(?<=\\S)__")
var _re_italic := RegEx.create_from_string("(?<![\\*\\w])\\*(?=\\S)(.+?)(?<=\\S)\\*(?!\\*)|(?<![_\\w])_(?=\\S)(.+?)(?<=\\S)_(?![_\\w])")
var _re_strike := RegEx.create_from_string("~~(?=\\S)(.+?)(?<=\\S)~~")
var _re_heading := RegEx.create_from_string("^(#{1,6})\\s+(.*?)\\s*#*\\s*$")
var _re_bullet := RegEx.create_from_string("^(\\s*)[-*+]\\s+(.*)$")
var _re_ordered := RegEx.create_from_string("^(\\s*)(\\d+)[.)]\\s+(.*)$")
var _re_task := RegEx.create_from_string("^\\[([ xX])\\]\\s+(.*)$")
var _re_rule := RegEx.create_from_string("^\\s*([-*_])(\\s*\\1){2,}\\s*$")
var _re_fence := RegEx.create_from_string("^\\s*(`{3,}|~{3,})")
var _re_emphasis_tag := RegEx.create_from_string("\\[(/?)(b|i|s)\\]")


func convert(markdown: String) -> String:
	var out: PackedStringArray = []
	var lines := markdown.replace("\r\n", "\n").split("\n")
	var fence := ""  # la del bloque de código abierto, o ""
	var code_lines: PackedStringArray = []
	var paragraph: PackedStringArray = []
	## La última línea de `out` es un ítem de lista que puede seguir en la línea siguiente.
	var in_list_item := false

	for raw_line: String in lines:
		var stripped := raw_line.strip_edges()
		var fence_match := _re_fence.search(raw_line)
		if not fence.is_empty():
			if fence_match and fence_match.get_string(1)[0] == fence[0] and fence_match.get_string(1).length() >= fence.length() and stripped.length() == fence_match.get_string(1).length():
				out.append(_code_block(code_lines))
				code_lines.clear()
				fence = ""
			else:
				code_lines.append(raw_line)
			continue
		if fence_match:
			_flush_paragraph(paragraph, out)
			in_list_item = false
			fence = fence_match.get_string(1)
			continue
		if stripped.is_empty():
			_flush_paragraph(paragraph, out)
			in_list_item = false
			continue
		var block := _block_line(raw_line, stripped)
		if block == _SKIP_LINE:
			continue
		if block.is_empty():
			if in_list_item and raw_line.begins_with(" ") or in_list_item and raw_line.begins_with("\t"):
				out[out.size() - 1] += " " + inline(stripped)  # continuación del ítem
			else:
				paragraph.append(_paragraph_line(raw_line))
			continue
		_flush_paragraph(paragraph, out)
		out.append(block)
		in_list_item = _re_bullet.search(raw_line) != null or _re_ordered.search(raw_line) != null

	if not fence.is_empty():
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
		var marker := "•" if indent == 0 else "◦"
		if task:
			marker = "☑" if task.get_string(1).to_lower() == "x" else "☐"
			text = task.get_string(2)
		return "%s%s %s" % ["    ".repeat(indent + 1).left(-2), marker, inline(text)]
	found = _re_ordered.search(raw_line)
	if found:
		var indent := _indent_level(found.get_string(1))
		return "%s%s. %s" % ["    ".repeat(indent + 1).left(-2), found.get_string(2), inline(found.get_string(3))]
	if stripped.begins_with(">"):
		var depth := 0
		var rest := stripped
		while rest.begins_with(">"):
			depth += 1
			rest = rest.substr(1).strip_edges(true, false)
		var inner := _block_line(rest, rest.strip_edges()) if not rest.strip_edges().is_empty() else ""
		if inner == _SKIP_LINE:
			inner = ""
		return "[color=%s]%s [i]%s[/i][/color]" % [muted_color, "▎".repeat(depth), inner if not inner.is_empty() else inline(rest.strip_edges())]
	if stripped.begins_with("|") and stripped.ends_with("|"):
		if stripped.replace("|", "").replace("-", "").replace(":", "").strip_edges().is_empty():
			return _SKIP_LINE
		return "[code]%s[/code]" % escape(stripped)
	return ""


## Línea de párrafo ya formateada. Dos espacios o `\` al final = salto de línea forzado.
func _paragraph_line(raw_line: String) -> String:
	var text := raw_line.strip_edges()
	var backslash := text.ends_with("\\") and not text.ends_with("\\\\")
	var hard := raw_line.ends_with("  ") or backslash
	if backslash:
		text = text.left(-1).strip_edges(false, true)
	return inline(text) + ("\n" if hard else "")


func _flush_paragraph(paragraph: PackedStringArray, out: PackedStringArray) -> void:
	if paragraph.is_empty():
		return
	var text := ""
	for line: String in paragraph:
		text += line if text.is_empty() or text.ends_with("\n") else " " + line
	out.append(text.trim_suffix("\n"))
	paragraph.clear()


func _code_block(code_lines: PackedStringArray) -> String:
	return "[bgcolor=%s][code]%s[/code][/bgcolor]" % [code_bg_color, escape("\n".join(code_lines))]


## Formato en línea: `code`, links, negrita, itálica y tachado. El texto se escapa.
## Orden: `\X` y code spans se apartan primero (adentro no hay formato), después links (su texto
## puede tener code spans y énfasis) y por último el énfasis.
func inline(text: String) -> String:
	text = _protect_escapes(text)
	var spans: PackedStringArray = []
	var protected := ""
	var position := 0
	for found: RegExMatch in _re_code_span.search_all(text):
		if spans.size() >= _MAX_SPANS:
			break
		protected += text.substr(position, found.get_start() - position)
		var code := _restore_escapes(found.get_string(2), true)
		if code.length() > 1 and code.begins_with(" ") and code.ends_with(" ") and not code.strip_edges().is_empty():
			code = code.substr(1, code.length() - 2)
		spans.append("[code][color=%s]%s[/color][/code]" % [code_color, escape(code)])
		protected += String.chr(_SPAN_BASE + spans.size() - 1)
		position = found.get_end()
	protected += text.substr(position)
	var result := _restore_escapes(_inline_text(protected), false)
	for i in spans.size():
		result = result.replace(String.chr(_SPAN_BASE + i), spans[i])
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
		result += "[url=%s]%s[/url]" % [_restore_escapes(url, true).replace("\\", "").replace("]", "%5D"), _emphasis(escape(label))]
		position = found.get_end()
	result += _emphasis(escape(text.substr(position)))
	return result


func _emphasis(text: String) -> String:
	text = _replace_pairs(_re_bold_italic, text, "b][i", "/i][/b")
	text = _replace_pairs(_re_bold, text, "b", "/b")
	text = _replace_pairs(_re_strike, text, "s", "/s")
	text = _replace_pairs(_re_italic, text, "i", "/i")
	return _balance(text)


## Marcas cruzadas (`**a *b** c*`) dan tags cruzados: al cerrar uno que no es el último abierto,
## se cierran los de adentro y se vuelven a abrir después.
func _balance(text: String) -> String:
	var result := ""
	var position := 0
	var open: Array[String] = []
	for found: RegExMatch in _re_emphasis_tag.search_all(text):
		result += text.substr(position, found.get_start() - position)
		position = found.get_end()
		var tag := found.get_string(2)
		if found.get_string(1).is_empty():
			open.append(tag)
			result += "[%s]" % tag
			continue
		var index := open.rfind(tag)
		if index < 0:
			continue  # cierre sin apertura: no pasa con _replace_pairs, pero no se emite
		var inner := open.slice(index + 1)
		for i in range(inner.size() - 1, -1, -1):
			result += "[/%s]" % inner[i]
		result += "[/%s]" % tag
		for inner_tag: String in inner:
			result += "[%s]" % inner_tag
		open.remove_at(index)
	return result + text.substr(position)


func _replace_pairs(regex: RegEx, text: String, open_tag: String, close_tag: String) -> String:
	var result := ""
	var position := 0
	for found: RegExMatch in regex.search_all(text):
		var inner := found.get_string(1)
		if inner.is_empty() and found.get_group_count() >= 2:
			inner = found.get_string(2)
		result += text.substr(position, found.get_start() - position)
		result += "[%s]%s[%s]" % [open_tag, inner, close_tag]
		position = found.get_end()
	return result + text.substr(position)


## `\*` → carácter privado, para que no cuente como marca de formato.
func _protect_escapes(text: String) -> String:
	var result := ""
	var position := 0
	for found: RegExMatch in _re_escape.search_all(text):
		result += text.substr(position, found.get_start() - position)
		result += String.chr(_ESCAPE_BASE + found.get_string(1).unicode_at(0))
		position = found.get_end()
	return result + text.substr(position)


## Devuelve los caracteres escapados: tal cual con su `\` (dentro de code) o como texto BBCode.
static func _restore_escapes(text: String, literal: bool) -> String:
	var result := ""
	for i in text.length():
		var code := text.unicode_at(i)
		if code >= _ESCAPE_BASE and code < _ESCAPE_BASE + 128:
			var original := String.chr(code - _ESCAPE_BASE)
			result += ("\\" + original) if literal else escape(original)
		else:
			result += text[i]
	return result


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
