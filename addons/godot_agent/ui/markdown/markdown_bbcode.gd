@tool
extends RefCounted
## Conversor Markdown → BBCode de RichTextLabel, propio (spec §9.1): párrafos, títulos, negrita,
## itálica, tachado, `code`, bloques de código (con resaltado), listas anidadas con sangría
## colgante, tareas, citas, tablas, reglas, links, URLs sueltas e imágenes (como link).
## Tolerante: lo que no reconoce queda como texto escapado; nunca deja tags sin cerrar.
## `blocks()` separa el texto de los bloques de código, que el chat muestra en su propia caja.

const CodeBBCode := preload("code_bbcode.gd")

const FENCES: PackedStringArray = ["```", "~~~"]
## Caracteres de uso privado: `\X` se guarda como ESCAPE_BASE + X y cada code span como
## SPAN_BASE + índice hasta el final del formato en línea.
const _ESCAPE_BASE := 0xE000
const _SPAN_BASE := 0xE100
const _MAX_SPANS := 0x700
## Tamaño (% del de la fuente) de la línea vacía que separa dos bloques separados por una línea en
## blanco: un respiro más chico que una línea entera.
const _GAP_SIZE := 45
const HEADING_SIZES: Array[int] = [0, 140, 122, 108, 100, 100, 100]
const IMAGE_MARK := "🖼"

var code_color: String = "#f0a85a"
var muted_color: String = "#9aa0a6"
var code_bg_color: String = "#00000040"
var table_border_color: String = "#ffffff26"
var table_header_bg: String = "#ffffff12"
var highlighter := CodeBBCode.new()

var _re_escape := RegEx.create_from_string("\\\\([!-/:-@\\[-`{-~])")
var _re_code_span := RegEx.create_from_string("(?<!`)(`+)(?!`)(.+?)(?<!`)\\1(?!`)")
var _re_link := RegEx.create_from_string("!?\\[([^\\]\\n]*)\\]\\(((?:[^()\\s]|\\([^()\\s]*\\))+)(?:\\s+\"[^\"]*\")?\\)")
var _re_autolink := RegEx.create_from_string("<(https?://[^>\\s]+)>")
## URL suelta: sin la puntuación final ni un `)` que no abrió adentro.
var _re_bare_url := RegEx.create_from_string("(?<![\\w/=\"'<])https?://(?:[^\\s<>\\[\\]()]|\\([^\\s<>\\[\\]()]*\\))*(?:[^\\s<>\\[\\]().,;:!?'\"*~]|\\([^\\s<>\\[\\]()]*\\))")
var _re_bold_italic := RegEx.create_from_string("\\*\\*\\*(?=\\S)(.+?)(?<=\\S)\\*\\*\\*|___(?=\\S)(.+?)(?<=\\S)___")
var _re_bold := RegEx.create_from_string("\\*\\*(?=\\S)(.+?)(?<=\\S)\\*\\*|__(?=\\S)(.+?)(?<=\\S)__")
var _re_italic := RegEx.create_from_string("(?<![\\*\\w])\\*(?=\\S)(.+?)(?<=\\S)\\*(?!\\*)|(?<![_\\w])_(?=\\S)(.+?)(?<=\\S)_(?![_\\w])")
var _re_strike := RegEx.create_from_string("~~(?=\\S)(.+?)(?<=\\S)~~")
var _re_heading := RegEx.create_from_string("^(#{1,6})\\s+(.*?)(?:\\s+#+)?\\s*$")
var _re_bullet := RegEx.create_from_string("^(\\s*)[-*+]\\s+(.*)$")
var _re_ordered := RegEx.create_from_string("^(\\s*)(\\d{1,9})[.)]\\s+(.*)$")
var _re_task := RegEx.create_from_string("^\\[([ xX])\\]\\s+(.*)$")
var _re_rule := RegEx.create_from_string("^\\s*([-*_])(\\s*\\1){2,}\\s*$")
var _re_fence := RegEx.create_from_string("^(\\s*)(`{3,}|~{3,})\\s*([^`\\s]*)")
var _re_table_separator := RegEx.create_from_string("^\\s*\\|?\\s*:?-+:?\\s*(\\|\\s*:?-+:?\\s*)*\\|?\\s*$")
var _re_emphasis_tag := RegEx.create_from_string("\\[(/?)(b|i|s)\\]")


## Todo en un solo BBCode: los bloques de código van en una caja (tabla de una celda).
func convert(markdown: String) -> String:
	var parts: PackedStringArray = []
	for block: Dictionary in blocks(markdown):
		parts.append(block.bbcode if block.has("bbcode") else code_block_bbcode(block.code, block.language))
	return "\n".join(parts)


## El texto partido en bloques, en orden: `{bbcode}` para el texto y `{code, language}` para cada
## bloque de código (el código tal cual, sin escapar).
func blocks(markdown: String) -> Array[Dictionary]:
	var state := _State.new()
	var lines := markdown.replace("\r\n", "\n").split("\n")
	var fence := ""  # la del bloque de código abierto, o ""
	var fence_indent := 0
	var language := ""
	var code_lines: PackedStringArray = []
	var i := 0
	while i < lines.size():
		var raw_line: String = lines[i]
		i += 1
		var stripped := raw_line.strip_edges()
		var fence_match := _re_fence.search(raw_line)
		if not fence.is_empty():
			var closer := fence_match.get_string(2) if fence_match else ""
			if not closer.is_empty() and closer[0] == fence[0] and closer.length() >= fence.length() and stripped.length() == closer.length():
				state.result.append({"code": "\n".join(code_lines), "language": language})
				code_lines.clear()
				fence = ""
			else:
				code_lines.append(_dedent(raw_line, fence_indent))
			continue
		if fence_match:
			_end_text(state)
			fence = fence_match.get_string(2)
			fence_indent = fence_match.get_string(1).replace("\t", "    ").length()
			language = fence_match.get_string(3)
			continue
		if stripped.is_empty():
			_flush_paragraph(state)
			state.blank = true
			continue

		var item := _list_item(raw_line)
		var heading := _re_heading.search(stripped) != null
		if not state.lists.is_empty() and item.is_empty():
			var indent := _leading_spaces(raw_line)
			var lazy := not state.blank and not heading and not stripped.begins_with(">") and _re_rule.search(stripped) == null
			if indent >= 2 or lazy:
				# El texto sigue el ítem abierto: en la misma línea o, tras una línea en blanco, abajo.
				state.out[state.out.size() - 1] += ("[br]" if state.blank else " ") + inline(stripped)
				state.blank = false
				continue
			_close_lists(state, -1)
		if not item.is_empty():
			_flush_paragraph(state)
			if state.lists.is_empty():
				_gap(state)
			_close_lists(state, item.indent)
			state.out.append("[ul bullet=%s]%s" % [_marker(item, state.lists.size()), inline(item.text)])
			state.lists.append(item.indent)
			state.blank = false
			continue

		if stripped.contains("|") and i < lines.size() and lines[i].contains("|") and _re_table_separator.search(lines[i]):
			_flush_paragraph(state)
			_gap(state)
			var aligns := _table_aligns(lines[i])
			var rows: Array[PackedStringArray] = [_split_row(stripped)]
			i += 1
			while i < lines.size() and lines[i].contains("|") and not lines[i].strip_edges().is_empty():
				rows.append(_split_row(lines[i].strip_edges()))
				i += 1
			state.out.append(_table(rows, aligns))
			state.blank = false
			continue

		var block := _block_line(stripped)
		if block.is_empty():
			if state.paragraph.is_empty():
				_gap(state)
			state.paragraph.append(_paragraph_line(raw_line))
		else:
			_flush_paragraph(state)
			_gap(state)
			state.out.append(block)
		state.blank = false

	if not fence.is_empty():
		state.result.append({"code": "\n".join(code_lines), "language": language})
	_end_text(state)
	return state.result


## Caja de un bloque de código para un RichTextLabel (el chat usa su propio control).
func code_block_bbcode(code: String, language: String) -> String:
	return "[table=1][cell bg=%s padding=%s][code]%s[/code][/cell][/table]" % [code_bg_color, _padding(8, 6), highlighter.highlight(code, language)]


## Estado de blocks(): las líneas del bloque de texto en curso y lo que hay abierto.
class _State:
	var result: Array[Dictionary] = []
	var out: PackedStringArray = []
	var paragraph: PackedStringArray = []
	## Sangría (en espacios) de cada ítem de lista abierto, del de afuera al de adentro.
	var lists: Array[int] = []
	## Hubo una línea en blanco desde el último bloque.
	var blank: bool = false


func _end_text(state: _State) -> void:
	_flush_paragraph(state)
	_close_lists(state, -1)
	if not state.out.is_empty():
		state.result.append({"bbcode": "\n".join(state.out)})
		state.out.clear()
	state.blank = false


## Cierra los ítems con sangría >= `indent` (todos con -1).
func _close_lists(state: _State, indent: int) -> void:
	while not state.lists.is_empty() and (indent < 0 or state.lists.back() >= indent):
		state.lists.pop_back()
		state.out[state.out.size() - 1] += "[/ul]"


## Una línea en blanco entre dos bloques deja un respiro (no al principio de un bloque de texto).
func _gap(state: _State) -> void:
	if state.blank and not state.out.is_empty():
		state.out.append("[font_size=%d] [/font_size]" % _scaled_size(_GAP_SIZE))
	state.blank = false


## Ítem de lista: {indent, number ("" si es viñeta), task (" ", "x" o ""), text}, o {} si no es.
func _list_item(raw_line: String) -> Dictionary:
	var found := _re_bullet.search(raw_line)
	if found and _re_rule.search(raw_line) == null:
		var text := found.get_string(2)
		var task := _re_task.search(text)
		return {
			"indent": _leading_spaces(found.get_string(1)), "number": "",
			"task": task.get_string(1).to_lower() if task else "", "text": task.get_string(2) if task else text,
		}
	found = _re_ordered.search(raw_line)
	if found:
		return {"indent": _leading_spaces(found.get_string(1)), "number": str(found.get_string(2).to_int()), "task": "", "text": found.get_string(3)}
	return {}


## Cada ítem es un [ul] propio con su marca: así el número es el del texto (una lista cortada por
## un bloque de código sigue en 3, no vuelve a 1) y las líneas largas quedan alineadas.
static func _marker(item: Dictionary, depth: int) -> String:
	if not str(item.number).is_empty():
		return item.number + "."
	match str(item.task):
		"x":
			return "▣"
		" ":
			return "□"
	return "•" if depth == 0 else "◦"


## Línea de bloque (título, regla, cita) o "" si es texto de párrafo.
func _block_line(stripped: String) -> String:
	var found := _re_heading.search(stripped)
	if found:
		var level := found.get_string(1).length()
		var title := inline(found.get_string(2))
		if HEADING_SIZES[level] > 100:
			return "[font_size=%d][b]%s[/b][/font_size]" % [_scaled_size(HEADING_SIZES[level]), title]
		return "[b]%s[/b]" % title
	if _re_rule.search(stripped):
		return "[hr color=%s height=1 width=100%%]" % muted_color
	if stripped.begins_with(">"):
		var depth := 0
		var rest := stripped
		while rest.begins_with(">"):
			depth += 1
			rest = rest.substr(1).strip_edges(true, false)
		rest = rest.strip_edges()
		var inner := ""
		var item := _list_item(rest)
		if not item.is_empty():
			inner = "%s %s" % [_marker(item, 0), inline(item.text)]
		elif not rest.is_empty():
			inner = _block_line(rest)
			if inner.begins_with("[hr"):
				inner = ""
		return "[color=%s]%s [i]%s[/i][/color]" % [muted_color, "▎".repeat(depth), inner if not inner.is_empty() else inline(rest)]
	return ""


## Línea de párrafo ya formateada. Dos espacios o `\` al final = salto de línea forzado.
func _paragraph_line(raw_line: String) -> String:
	var text := raw_line.strip_edges()
	var backslash := text.ends_with("\\") and not text.ends_with("\\\\")
	var hard := raw_line.ends_with("  ") or backslash
	if backslash:
		text = text.left(-1).strip_edges(false, true)
	return inline(text) + ("\n" if hard else "")


func _flush_paragraph(state: _State) -> void:
	if state.paragraph.is_empty():
		return
	var text := ""
	for line: String in state.paragraph:
		text += line if text.is_empty() or text.ends_with("\n") else " " + line
	state.out.append(text.trim_suffix("\n"))
	state.paragraph.clear()


## Tabla con encabezado en negrita sobre fondo, bordes y la alineación de cada columna.
func _table(rows: Array[PackedStringArray], aligns: PackedStringArray) -> String:
	var columns := rows[0].size()
	var cell_open := "[cell border=%s padding=%s]" % [table_border_color, _padding(6, 3)]
	var header_open := "[cell bg=%s border=%s padding=%s]" % [table_header_bg, table_border_color, _padding(6, 3)]
	var result := "[table=%d]" % columns
	for r in rows.size():
		for c in columns:
			var text := inline(rows[r][c]) if c < rows[r].size() else ""
			if r == 0:
				text = "[b]%s[/b]" % text if not text.is_empty() else text
			var align := aligns[c] if c < aligns.size() else ""
			if not align.is_empty() and not text.is_empty():
				text = "[%s]%s[/%s]" % [align, text, align]
			result += (header_open if r == 0 else cell_open) + text + "[/cell]"
	return result + "[/table]"


## "left"/"" → "", ":-:" → "center", "-:" → "right".
func _table_aligns(separator: String) -> PackedStringArray:
	var aligns: PackedStringArray = []
	for cell: String in _split_row(separator.strip_edges()):
		var spec := cell.strip_edges()
		if spec.ends_with(":"):
			aligns.append("center" if spec.begins_with(":") else "right")
		else:
			aligns.append("")
	return aligns


## Celdas de una fila: separa en los `|` que no están escapados ni dentro de un code span.
static func _split_row(row: String) -> PackedStringArray:
	if row.begins_with("|"):
		row = row.substr(1)
	if row.ends_with("|") and not row.ends_with("\\|"):
		row = row.left(-1)
	var cells: PackedStringArray = []
	var cell := ""
	var in_code := false
	var i := 0
	while i < row.length():
		var c := row[i]
		if c == "\\" and i + 1 < row.length() and row[i + 1] == "|":
			cell += "|"
			i += 2
			continue
		if c == "`":
			in_code = not in_code
		elif c == "|" and not in_code:
			cells.append(cell.strip_edges())
			cell = ""
			i += 1
			continue
		cell += c
		i += 1
	cells.append(cell.strip_edges())
	return cells


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
## Una imagen `![alt](ruta)` queda como link con 🖼: el chat la abre en el visor.
func _inline_text(text: String) -> String:
	var result := ""
	var position := 0
	var matches: Array[RegExMatch] = []
	matches.append_array(_re_link.search_all(text))
	matches.append_array(_re_autolink.search_all(text))
	matches.append_array(_re_bare_url.search_all(text))
	matches.sort_custom(func(a: RegExMatch, b: RegExMatch) -> bool: return a.get_start() < b.get_start())
	for found: RegExMatch in matches:
		if found.get_start() < position:
			continue
		result += _emphasis(escape(text.substr(position, found.get_start() - position)))
		var whole := found.get_string()
		var url := found.get_string(2) if found.get_group_count() >= 2 else found.get_string(1) if found.get_group_count() == 1 else whole
		var label := ""
		if found.get_group_count() == 0:
			label = escape(whole)  # URL suelta: sin énfasis (los _ son parte de la URL)
		elif whole.begins_with("!"):
			var alt := found.get_string(1)
			label = "%s %s" % [IMAGE_MARK, _emphasis(escape(alt if not alt.is_empty() else url.get_file()))]
		else:
			label = _emphasis(escape(found.get_string(1)))
		result += "[url=%s]%s[/url]" % [_restore_escapes(url, true).replace("\\", "").replace("]", "%5D"), label]
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


## Destino de un link que no es web: `{path, line}`. Acepta `file://`, `ruta#L42`, `ruta#L42-L50`
## y `ruta:42` (o `ruta:42:7`); sin línea, 0.
static func link_target(url: String) -> Dictionary:
	var path := url.trim_prefix("file://").uri_decode()
	var line := 0
	var anchor := path.rfind("#L")
	if anchor >= 0 and path.substr(anchor + 2).get_slice("-", 0).is_valid_int():
		line = path.substr(anchor + 2).get_slice("-", 0).to_int()
		path = path.left(anchor)
	else:
		var parts := path.rsplit(":", true, 2)
		# "a.gd:42:7" → ["a.gd", "42", "7"]; "C:/x" o "res://x" no tienen número al final.
		if parts.size() >= 2 and parts[parts.size() - 1].is_valid_int():
			var numbers := 2 if parts.size() == 3 and parts[1].is_valid_int() else 1
			line = parts[parts.size() - numbers].to_int()
			path = ":".join(parts.slice(0, parts.size() - numbers))
	return {"path": path, "line": maxi(line, 0)}


static func escape(text: String) -> String:
	return text.replace("[", "\u0001").replace("]", "[rb]").replace("\u0001", "[lb]")


static func _leading_spaces(text: String) -> int:
	var spaces := 0
	for c in text:
		if c == " ":
			spaces += 1
		elif c == "\t":
			spaces += 4
		else:
			break
	return spaces


## Saca hasta `indent` espacios del principio (la sangría del fence dentro de una lista).
static func _dedent(line: String, indent: int) -> String:
	var removed := 0
	while removed < indent and removed < line.length() and line[removed] == " ":
		removed += 1
	return line.substr(removed)


static func _padding(horizontal: int, vertical: int) -> String:
	var h := _px(horizontal)
	var v := _px(vertical)
	return "%d,%d,%d,%d" % [h, v, h, v]


static func _px(value: float) -> int:
	if Engine.is_editor_hint() and Engine.has_singleton(&"EditorInterface"):
		return int(round(value * EditorInterface.get_editor_scale()))
	return int(value)


static func _scaled_size(percent: int) -> int:
	var base := 14
	if Engine.is_editor_hint() and Engine.has_singleton(&"EditorInterface"):
		var theme := EditorInterface.get_editor_theme()
		if theme.has_font_size(&"main_size", &"EditorFonts"):
			base = theme.get_font_size(&"main_size", &"EditorFonts")
	return int(base * percent / 100.0)
