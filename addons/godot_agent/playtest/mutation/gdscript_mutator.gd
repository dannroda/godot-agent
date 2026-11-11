@tool
extends RefCounted
## Mutantes de GDScript para medir las regresiones (m11-41): un cambio chico por mutante, solo dentro de
## funciones y nunca en comentarios ni strings. Trabaja sobre el texto; no lee ni escribe archivos.
## Un mutante es {path, line (desde 1), col (desde 0), before, after, op}: en esa línea y columna,
## `before` pasa a ser `after`.

const OP_RELATIONAL := "relational"
const OP_NEGATE := "negate_condition"
const OP_LOGICAL := "logical"
const OP_BOOLEAN := "boolean"
const OP_NUMBER := "number"
const OP_ARITHMETIC := "arithmetic"
const OP_DELETE := "delete_statement"

const RELATIONAL := {"<=": "<", ">=": ">", "==": "!=", "!=": "==", "<": "<=", ">": ">="}
const ARITHMETIC := {"+=": "-=", "-=": "+=", "*=": "/=", "/=": "*=", " + ": " - ", " - ": " + ", " * ": " / ", " / ": " * "}
## Sentencias que no se borran: abren un bloque, declaran algo o ya son control de flujo.
const KEEP_STATEMENTS: PackedStringArray = ["if ", "elif ", "else", "for ", "while ", "match ", "func ", "static ", "return",
	"var ", "const ", "pass", "break", "continue", "await ", "@", "class ", "signal ", "enum ", "extends", "class_name", "super("]


## Todos los mutantes de `source`, en orden de línea y columna.
static func mutants(source: String, path: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var lines := source.split("\n")
	var func_indent := -1
	var in_triple := false
	for index in lines.size():
		var line := lines[index]
		var stripped := line.strip_edges()
		if line.count("\"\"\"") % 2 == 1:
			in_triple = not in_triple
			continue
		if in_triple or stripped.is_empty() or stripped.begins_with("#"):
			continue
		var indent := _indent(line)
		if func_indent >= 0 and indent <= func_indent:
			func_indent = -1
		if stripped.begins_with("func ") or stripped.begins_with("static func "):
			func_indent = indent
			continue
		if line.ends_with("\\") or (index > 0 and lines[index - 1].ends_with("\\")):
			continue
		var code := _code_mask(line)
		var line_mutants: Array[Dictionary] = []
		if func_indent >= 0:
			line_mutants = _line_mutants(line, code, stripped)
		elif stripped.begins_with("const "):
			# Las constantes del script (velocidad, alturas…): solo sus números.
			line_mutants = _number_mutants(line, code)
		for mutant: Dictionary in line_mutants:
			mutant.path = path
			mutant.line = index + 1
			result.append(mutant)
	return result


## El texto con el mutante aplicado, o "" si la línea ya no tiene `before` en esa columna.
static func apply(source: String, mutant: Dictionary) -> String:
	var lines := source.split("\n")
	var index := int(mutant.get("line", 0)) - 1
	if index < 0 or index >= lines.size():
		return ""
	var line := lines[index]
	var col := int(mutant.get("col", -1))
	var before := str(mutant.get("before", ""))
	if col < 0 or line.substr(col, before.length()) != before:
		return ""
	lines[index] = line.substr(0, col) + str(mutant.get("after", "")) + line.substr(col + before.length())
	return "\n".join(lines)


## Hasta `count` mutantes repartidos: de cada script por turno y, dentro de cada uno, a lo largo del
## archivo. Determinista: la misma lista da la misma muestra.
static func sample(all: Array[Dictionary], count: int) -> Array[Dictionary]:
	if all.size() <= count:
		return all.duplicate()
	var by_path: Dictionary = {}
	for mutant: Dictionary in all:
		if not by_path.has(mutant.path):
			by_path[mutant.path] = []
		by_path[mutant.path].append(mutant)
	var paths := by_path.keys()
	paths.sort()
	var quota: Dictionary = {}
	var left := count
	while left > 0:
		var gave := false
		for path: String in paths:
			if left > 0 and int(quota.get(path, 0)) < (by_path[path] as Array).size():
				quota[path] = int(quota.get(path, 0)) + 1
				left -= 1
				gave = true
		if not gave:
			break
	var result: Array[Dictionary] = []
	for path: String in paths:
		var list: Array = by_path[path]
		var take := int(quota.get(path, 0))
		for i in take:
			result.append(list[int(float(i) * list.size() / take)])
	return result


## Cómo se ve el cambio para el usuario: «if x < 3: → if x <= 3:».
static func describe(source_line: String, mutant: Dictionary) -> String:
	var col := int(mutant.col)
	var after := source_line.substr(0, col) + str(mutant.after) + source_line.substr(col + str(mutant.before).length())
	return "%s → %s" % [source_line.strip_edges(), after.strip_edges()]


static func _line_mutants(line: String, code: PackedByteArray, stripped: String) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	var taken: Dictionary = {}
	# Comparaciones: primero las de dos caracteres, para no partir «<=» en «<».
	for op: String in ["<=", ">=", "==", "!=", "<", ">"]:
		var from := 0
		while true:
			var at := line.find(op, from)
			if at < 0:
				break
			from = at + 1
			if not _is_code(code, at, op.length()) or taken.has(at):
				continue
			if op.length() == 1:
				var prev := line[at - 1] if at > 0 else ""
				var next := line[at + 1] if at + 1 < line.length() else ""
				if next in ["=", op] or prev in [op, "-"]:  # <=, <<, >>, ->
					continue
			taken[at] = true
			if op.length() == 2:
				taken[at + 1] = true
			found.append({"col": at, "before": op, "after": RELATIONAL[op], "op": OP_RELATIONAL})
	for op: String in ARITHMETIC:
		var from := 0
		while true:
			var at := line.find(op, from)
			if at < 0:
				break
			from = at + 1
			var core := at + (1 if op.begins_with(" ") else 0)
			if _is_code(code, at, op.length()) and not taken.has(core):
				taken[core] = true
				found.append({"col": at, "before": op, "after": ARITHMETIC[op], "op": OP_ARITHMETIC})
	for pair: Array in [[" and ", " or "], [" or ", " and "], ["true", "false"], ["false", "true"]]:
		for at: int in _words(line, code, pair[0].strip_edges()):
			var col := at - (1 if pair[0].begins_with(" ") else 0)
			if pair[0].begins_with(" ") and (col < 0 or line.substr(col, pair[0].length()) != pair[0]):
				continue
			found.append({"col": col, "before": pair[0], "after": pair[1], "op": OP_LOGICAL if pair[0].begins_with(" ") else OP_BOOLEAN})
	found.append_array(_number_mutants(line, code))
	for keyword: String in ["if ", "elif ", "while "]:
		if stripped.begins_with(keyword) and stripped.ends_with(":") and _comment_at(line, code) < 0:
			var start := line.find(keyword) + keyword.length()
			var condition := line.substr(start, line.rfind(":") - start)
			found.append({"col": start, "before": condition + ":", "after": "not (%s):" % condition, "op": OP_NEGATE})
	if not Array(KEEP_STATEMENTS).any(func(prefix: String) -> bool: return stripped.begins_with(prefix)) and not stripped.ends_with(":") \
			and _comment_at(line, code) < 0 and not stripped.ends_with(",") and not stripped.ends_with("(") and not stripped.ends_with("["):
		found.append({"col": _indent_chars(line), "before": stripped, "after": "pass", "op": OP_DELETE})
	found.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.col) < int(b.col) or (int(a.col) == int(b.col) and str(a.op) < str(b.op)))
	return found


static func _number_mutants(line: String, code: PackedByteArray) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	var numbers := RegEx.create_from_string("(?<![\\w.])\\d+(?:\\.\\d+)?(?![\\w.])")
	for match_: RegExMatch in numbers.search_all(line):
		var at := match_.get_start()
		if not _is_code(code, at, match_.get_string().length()) or (at > 0 and line[at - 1] in ["$", "/", "%"]):
			continue
		var text := match_.get_string()
		var zero := text.to_float() == 0.0
		var after := ("1.0" if text.contains(".") else "1") if zero else ("0.0" if text.contains(".") else "0")
		found.append({"col": at, "before": text, "after": after, "op": OP_NUMBER})
	return found


## Posiciones de `word` como palabra entera en el código.
static func _words(line: String, code: PackedByteArray, word: String) -> Array[int]:
	var result: Array[int] = []
	var from := 0
	while true:
		var at := line.find(word, from)
		if at < 0:
			break
		from = at + 1
		var before_ok := at == 0 or not _is_word_char(line[at - 1])
		var after_ok := at + word.length() >= line.length() or not _is_word_char(line[at + word.length()])
		if before_ok and after_ok and _is_code(code, at, word.length()):
			result.append(at)
	return result


static func _is_word_char(c: String) -> bool:
	return c == "_" or (c >= "a" and c <= "z") or (c >= "A" and c <= "Z") or (c >= "0" and c <= "9")


## 1 donde hay código, 0 en strings (con sus comillas) y desde un # que no está en un string.
static func _code_mask(line: String) -> PackedByteArray:
	var mask := PackedByteArray()
	mask.resize(line.length())
	mask.fill(1)
	var quote := ""
	var i := 0
	while i < line.length():
		var c := line[i]
		if quote.is_empty():
			if c == "#":
				for j in range(i, line.length()):
					mask[j] = 0
				break
			if c == "\"" or c == "'":
				quote = c
				mask[i] = 0
		else:
			mask[i] = 0
			if c == "\\":
				if i + 1 < line.length():
					mask[i + 1] = 0
				i += 1
			elif c == quote:
				quote = ""
		i += 1
	return mask


static func _is_code(mask: PackedByteArray, at: int, length: int) -> bool:
	for i in range(at, mini(at + length, mask.size())):
		if mask[i] == 0:
			return false
	return true


## Columna del # de un comentario al final de la línea (-1 si no hay).
static func _comment_at(line: String, mask: PackedByteArray) -> int:
	for i in mask.size():
		if mask[i] == 0 and line[i] == "#" and (i == 0 or mask[i - 1] == 1 or line[i - 1] == " "):
			var in_string := false
			for j in range(0, i):
				if line[j] in ["\"", "'"]:
					in_string = not in_string
			if not in_string:
				return i
	return -1


static func _indent(line: String) -> int:
	var count := 0
	for c in line:
		if c == "\t":
			count += 4
		elif c == " ":
			count += 1
		else:
			break
	return count


static func _indent_chars(line: String) -> int:
	return line.length() - line.strip_edges(true, false).length()
