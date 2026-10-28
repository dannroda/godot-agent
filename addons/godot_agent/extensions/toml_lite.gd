@tool
extends RefCounted
## Lector de TOML acotado a lo que traen los config.toml de agentes (Codex): tablas `[a.b]` con
## claves citadas, claves con puntos, strings básicos y literales, números, booleanos, arrays (también
## de varias líneas) y tablas en línea, con comentarios al final. Los arrays de tablas (`[[x]]`) se
## saltean. Lo que no entiende lo ignora: es para mostrar, no para validar.


## Diccionario con las tablas anidadas de `text`.
static func parse(text: String) -> Dictionary:
	var root: Dictionary = {}
	var current: Variant = root  # null dentro de un [[array de tablas]]
	for statement: String in _statements(text):
		if statement.begins_with("[["):
			current = null
		elif statement.begins_with("["):
			var close := statement.rfind("]")
			current = _table_at(root, _key_path(statement.substr(1, close - 1))) if close > 0 else null
		elif current is Dictionary:
			var eq := _find_outside_strings(statement, "=")
			if eq <= 0:
				continue
			var path := _key_path(statement.substr(0, eq))
			if path.is_empty():
				continue
			var state := [0]
			var value: Variant = _value(statement.substr(eq + 1).strip_edges(), state)
			var table: Variant = _table_at(current, path.slice(0, path.size() - 1))
			if table is Dictionary and value != null:
				table[path[path.size() - 1]] = value
	return root


## Sentencias completas: sin comentarios y con los arrays o tablas en línea de varias líneas unidos.
static func _statements(text: String) -> PackedStringArray:
	var result: PackedStringArray = []
	var pending := ""
	var depth := 0
	for raw: String in text.replace("\r\n", "\n").split("\n"):
		var line := _strip_comment(raw).strip_edges()
		if line.is_empty():
			continue
		pending = line if pending.is_empty() else pending + " " + line
		depth = _bracket_depth(pending)
		if depth <= 0 or pending.begins_with("["):
			result.append(pending)
			pending = ""
	if not pending.is_empty():
		result.append(pending)
	return result


static func _strip_comment(line: String) -> String:
	var hash := _find_outside_strings(line, "#")
	return line if hash < 0 else line.substr(0, hash)


## Posición de `needle` fuera de strings, o -1.
static func _find_outside_strings(text: String, needle: String) -> int:
	var quote := ""
	var i := 0
	while i < text.length():
		var c := text[i]
		if quote.is_empty():
			if c == "\"" or c == "'":
				quote = c
			elif c == needle:
				return i
		elif c == "\\" and quote == "\"":
			i += 1
		elif c == quote:
			quote = ""
		i += 1
	return -1


static func _bracket_depth(text: String) -> int:
	var depth := 0
	var eq := _find_outside_strings(text, "=")
	if eq < 0:
		return 0
	var quote := ""
	var i := eq + 1
	while i < text.length():
		var c := text[i]
		if quote.is_empty():
			if c == "\"" or c == "'":
				quote = c
			elif c == "[" or c == "{":
				depth += 1
			elif c == "]" or c == "}":
				depth -= 1
		elif c == "\\" and quote == "\"":
			i += 1
		elif c == quote:
			quote = ""
		i += 1
	return depth


## `a."b.c".d` → ["a", "b.c", "d"].
static func _key_path(text: String) -> PackedStringArray:
	var path: PackedStringArray = []
	var part := ""
	var quote := ""
	for c: String in text.strip_edges():
		if quote.is_empty():
			if c == "\"" or c == "'":
				quote = c
			elif c == ".":
				path.append(part.strip_edges())
				part = ""
			else:
				part += c
		elif c == quote:
			quote = ""
		else:
			part += c
	path.append(part.strip_edges())
	return path if not "" in path else PackedStringArray()


static func _table_at(root: Dictionary, path: PackedStringArray) -> Variant:
	var table: Dictionary = root
	for key: String in path:
		if not table.has(key):
			table[key] = {}
		if not table[key] is Dictionary:
			return null
		table = table[key]
	return table


## Valor que empieza en `state[0]`; deja `state[0]` después de él. null si no lo entiende.
static func _value(text: String, state: Array) -> Variant:
	_skip_spaces(text, state)
	var i: int = state[0]
	if i >= text.length():
		return null
	var c := text[i]
	if c == "\"" or c == "'":
		return _string(text, state)
	if c == "[":
		state[0] = i + 1
		var items: Array = []
		while true:
			_skip_spaces(text, state)
			if state[0] >= text.length():
				return items
			if text[state[0]] == "]":
				state[0] += 1
				return items
			var item: Variant = _value(text, state)
			if item == null:
				return items
			items.append(item)
			_skip_spaces(text, state)
			if state[0] < text.length() and text[state[0]] == ",":
				state[0] += 1
	if c == "{":
		state[0] = i + 1
		var table: Dictionary = {}
		while true:
			_skip_spaces(text, state)
			if state[0] >= text.length():
				return table
			if text[state[0]] == "}":
				state[0] += 1
				return table
			var rest := text.substr(state[0])
			var eq := _find_outside_strings(rest, "=")
			if eq <= 0:
				return table
			var path := _key_path(rest.substr(0, eq))
			state[0] += eq + 1
			var value: Variant = _value(text, state)
			var target: Variant = _table_at(table, path.slice(0, path.size() - 1)) if not path.is_empty() else null
			if target is Dictionary and value != null:
				target[path[path.size() - 1]] = value
			_skip_spaces(text, state)
			if state[0] < text.length() and text[state[0]] == ",":
				state[0] += 1
	var end := i
	while end < text.length() and not text[end] in [",", "]", "}", " ", "\t"]:
		end += 1
	var word := text.substr(i, end - i)
	state[0] = end
	if word == "true" or word == "false":
		return word == "true"
	if word.replace("_", "").is_valid_int():
		return word.replace("_", "").to_int()
	if word.replace("_", "").is_valid_float():
		return word.replace("_", "").to_float()
	return null


static func _string(text: String, state: Array) -> String:
	var i: int = state[0]
	var quote := text[i]
	var result := ""
	i += 1
	while i < text.length() and text[i] != quote:
		if quote == "\"" and text[i] == "\\" and i + 1 < text.length():
			i += 1
			match text[i]:
				"n": result += "\n"
				"t": result += "\t"
				_: result += text[i]
		else:
			result += text[i]
		i += 1
	state[0] = i + 1
	return result


static func _skip_spaces(text: String, state: Array) -> void:
	while state[0] < text.length() and text[state[0]] in [" ", "\t"]:
		state[0] += 1
