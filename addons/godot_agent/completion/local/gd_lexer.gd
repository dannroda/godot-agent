@tool
extends RefCounted
## Lexer GDScript simple para el modelo n-gram (spec §16.2c): identificadores (las keywords
## incluidas), operadores, strings, números y tokens de salto de línea, indent y dedent. Los
## comentarios no cuentan.
## Un token precedido de espacios lleva un espacio adelante (`" ="` y `"="` son tokens distintos),
## así el texto se rearma desde los tokens con el espaciado del proyecto.

const NEWLINE := "\n"
const INDENT := "<indent>"
const DEDENT := "<dedent>"
## Un tab o tantos espacios = un nivel.
const SPACES_PER_LEVEL := 4

const _TOKEN := "([ \\t]*)(\"\"\"|'''|[&^]?\"(?:[^\"\\\\]|\\\\.)*\"?|'(?:[^'\\\\]|\\\\.)*'?|#.*|0[xX][0-9A-Fa-f_]+|0[bB][01_]+|\\d[\\d_]*(?:\\.[\\d_]*)?(?:[eE][+-]?\\d+)?|\\.\\d[\\d_]*|[A-Za-z_]\\w*|\\*\\*=|<<=|>>=|->|:=|==|!=|<=|>=|\\*\\*|<<|>>|&&|\\|\\||[-+*/%&|^]=|\\.\\.|\\S)"

## Se compila al cargar el script (en el hilo principal): el worker y el editor lo comparten, y la
## búsqueda sobre un RegEx ya compilado no tiene estado.
static var _re: RegEx = _compile()


## Tokens de una línea, sin indentación ni salto de línea. Un string sin cerrar al final (a medio
## escribir) queda como un token.
static func tokenize_line(line: String) -> PackedStringArray:
	var out := PackedStringArray()
	var text := line.strip_edges(true, false)
	for found: RegExMatch in _re.search_all(text):
		var groups := found.strings
		var token := groups[2]
		if token.begins_with("#"):
			break
		if token == "\"\"\"" or token == "'''":
			return _tokenize_with_triple_quotes(text)
		out.append(token if groups[1].is_empty() else " " + token)
	return out


## Como `tokenize_line`, de a un token: un string de triple comilla cerrado en la misma línea va
## entero (y lo que tiene adentro no son tokens).
static func _tokenize_with_triple_quotes(text: String) -> PackedStringArray:
	var out := PackedStringArray()
	var position := 0
	while position < text.length():
		var found := _re.search(text, position)
		if found == null:
			break
		var token := found.get_string(2)
		if token.begins_with("#"):
			break
		if token == "\"\"\"" or token == "'''":
			var close := text.find(token, found.get_end(2))
			token = text.substr(found.get_start(2), (close + 3 if close >= 0 else text.length()) - found.get_start(2))
			position = found.get_start(2) + token.length()
		else:
			position = found.get_end()
		out.append(" " + token if found.get_start(2) > found.get_start() else token)
	return out


## Tokens de un archivo entero: por línea, el cambio de indentación (INDENT o DEDENT), los tokens y
## NEWLINE. Las líneas vacías, los comentarios y el interior de los strings multilínea no cuentan.
## `skip_line` (0-based) queda afuera: en un buffer, la línea del caret está a medio escribir.
static func tokenize(text: String, skip_line: int = -1) -> PackedStringArray:
	var out := PackedStringArray()
	var levels: Array[int] = [0]
	var in_string := ""
	var lines := text.split("\n")
	for i in lines.size():
		var line := lines[i].replace("\r", "")
		if not in_string.is_empty():
			if line.contains(in_string):
				in_string = ""
			continue
		if i == skip_line:
			continue
		var stripped := line.strip_edges()
		if stripped.is_empty() or stripped.begins_with("#"):
			continue
		var tokens := tokenize_line(line)
		if tokens.is_empty():
			continue
		var last := tokens[tokens.size() - 1].strip_edges(true, false)
		if (last.begins_with("\"\"\"") or last.begins_with("'''")) and (last.length() < 6 or not last.ends_with(last.left(3))):
			in_string = last.left(3)
		# Pila de anchos: sirve con cualquier unidad (tabs, 2 o 4 espacios).
		var level := indent_level(line, 1)
		if level > levels.back():
			levels.append(level)
			out.append(INDENT)
		else:
			while level < levels.back() and levels.size() > 1:
				levels.pop_back()
				out.append(DEDENT)
		out.append_array(tokens)
		out.append(NEWLINE)
	return out


## Nivel de indentación: tabs, o espacios de a `spaces_per_level` (el del archivo o el del editor;
## con 1 da el ancho, que sirve para comparar).
static func indent_level(line: String, spaces_per_level: int = SPACES_PER_LEVEL) -> int:
	var tabs := 0
	var spaces := 0
	for c in line:
		if c == "\t":
			tabs += 1
		elif c == " ":
			spaces += 1
		else:
			break
	return tabs + spaces / maxi(1, spaces_per_level)


## Espacios por nivel de un archivo indentado con espacios: la sangría más chica que aparece
## (SPACES_PER_LEVEL si usa tabs o no tiene sangría).
static func spaces_unit(lines: PackedStringArray) -> int:
	var unit := 0
	for line: String in lines:
		if not line.begins_with(" "):
			continue
		var spaces := 0
		while spaces < line.length() and line[spaces] == " ":
			spaces += 1
		if spaces < line.length() and line[spaces] != "#" and (unit == 0 or spaces < unit):
			unit = spaces
	return unit if unit > 0 else SPACES_PER_LEVEL


## Un token que se puede seguir escribiendo (identificador, número o string sin cerrar).
static func is_open_token(token: String) -> bool:
	var text := token.strip_edges(true, false)
	if text.is_empty():
		return false
	var body := text.trim_prefix("&").trim_prefix("^")
	if body.begins_with("\"") or body.begins_with("'"):
		var quote := body[0]
		return body.length() == 1 or not body.ends_with(quote) or body.ends_with("\\" + quote)
	var last := text.unicode_at(text.length() - 1)
	return last == 95 or (last >= 48 and last <= 57) or (last >= 65 and last <= 90) or (last >= 97 and last <= 122)


static func _compile() -> RegEx:
	var re := RegEx.new()
	re.compile(_TOKEN)
	return re
