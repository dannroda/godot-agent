@tool
extends RefCounted
## Las declaraciones de un GDScript con sus líneas (m11-83, m11-82), sin cargar el script: sirve
## para un archivo con errores y para el texto sin guardar del Script Editor.
##
## Una pasada por caracteres sabe qué líneas empiezan una sentencia: las que no están dentro de un
## string que sigue de la línea anterior (de triple comilla, o común con un salto de línea adentro), de paréntesis/corchetes/llaves abiertos ni después de una `\` final.
## Sobre esas, la indentación arma los bloques: una línea con menos o igual indentación que un
## `func` o `class` lo cierra. Lo que está dentro de un `func` (variables locales, lambdas) no es
## una declaración.
##
## Cada declaración: {kind, name, qualified, line, start, end, indent, static}. `kind` es func,
## class, class_name, signal, var, const o enum; `qualified` lleva las clases internas
## (`Inner.jump`); `line` es la línea de la declaración (desde 1), `start` incluye los comentarios
## `##` y las anotaciones de arriba, y `end` es la última línea de código del bloque (en un func o
## una class; en las demás, la última línea de la sentencia). Un `enum` sin nombre queda con name "".

const KIND_FUNC := "func"
const KIND_CLASS := "class"
const KIND_CLASS_NAME := "class_name"
const KIND_SIGNAL := "signal"
const KIND_VAR := "var"
const KIND_CONST := "const"
const KIND_ENUM := "enum"
## Un tab cuenta como esta cantidad de espacios al comparar indentaciones.
const TAB_WIDTH := 4

static var _re_annotations := RegEx.create_from_string("^(?:@\\w+(?:\\([^)]*\\))?\\s+)+")
static var _re_decl := RegEx.create_from_string("^(static\\s+)?(func|class_name|class|signal|var|const|enum)\\b\\s*(\\w*)")


## Estructura línea por línea de `text`: {lines, stmt_of, code} (arrays del largo de las líneas).
## `stmt_of[i]` es la línea (desde 0) donde empieza la sentencia de la línea i; `code[i]` dice si la
## línea tiene código (no es vacía, ni solo comentario, ni el medio de un string largo vacío).
static func scan(text: String) -> Dictionary:
	var lines := text.split("\n")
	var stmt_of := PackedInt32Array()
	stmt_of.resize(lines.size())
	var code := []
	code.resize(lines.size())
	var triple := ""
	var depth := 0
	var backslash := false
	var current_stmt := 0
	for i in lines.size():
		var line := lines[i].trim_suffix("\r")
		var continues := not triple.is_empty() or depth > 0 or backslash
		if not continues:
			current_stmt = i
		stmt_of[i] = current_stmt
		var stripped := line.strip_edges()
		code[i] = not triple.is_empty() or (not stripped.is_empty() and not stripped.begins_with("#"))
		backslash = false
		var j := 0
		var length := line.length()
		while j < length:
			var c := line[j]
			if not triple.is_empty():
				if line.substr(j, triple.length()) == triple:
					j += triple.length()
					triple = ""
					continue
				if c == "\\":
					j += 2
					continue
				j += 1
				continue
			if c == "#":
				break
			if c == "\"" or c == "'":
				if line.substr(j, 3) == c.repeat(3):
					triple = c.repeat(3)
					j += 3
					continue
				j = _skip_string(line, j + 1, c)
				if j < 0:
					# GDScript deja un salto de línea dentro de un string común: sigue abierto.
					triple = c
					break
				continue
			if c in "([{":
				depth += 1
			elif c in ")]}":
				depth = maxi(depth - 1, 0)
			elif c == "\\" and line.substr(j + 1).strip_edges().is_empty():
				backslash = true
			j += 1
	return {"lines": lines, "stmt_of": stmt_of, "code": code}


## El índice después de la comilla que cierra el string que empieza en `from`, o -1 si sigue
## abierto al final de la línea.
static func _skip_string(line: String, from: int, quote: String) -> int:
	var j := from
	while j < line.length():
		var c := line[j]
		if c == "\\":
			j += 2
			continue
		if c == quote:
			return j + 1
		j += 1
	return -1


static func indent_width(line: String) -> int:
	var width := 0
	for c in line:
		if c == "\t":
			width += TAB_WIDTH
		elif c == " ":
			width += 1
		else:
			break
	return width


## Las declaraciones de `text`, en orden.
static func parse(text: String) -> Array[Dictionary]:
	var scanned := scan(text)
	var lines: PackedStringArray = scanned.lines
	var stmt_of: PackedInt32Array = scanned.stmt_of
	var code: Array = scanned.code
	var result: Array[Dictionary] = []
	## Bloques abiertos (func o class): las declaraciones de result, con su indentación.
	var open: Array[Dictionary] = []
	## La indentación de los miembros de cada bloque abierto (-1: todavía ninguno).
	var bodies: Array[int] = []
	for i in lines.size():
		if not code[i]:
			continue
		if stmt_of[i] != i:
			# Sigue una sentencia de antes: alarga los bloques abiertos y la sentencia misma.
			for block: Dictionary in open:
				block.end = i + 1
			if not result.is_empty() and result[-1].line - 1 == stmt_of[i] and result[-1].kind not in [KIND_FUNC, KIND_CLASS]:
				result[-1].end = i + 1
			continue
		var line := lines[i].trim_suffix("\r")
		var indent := indent_width(line)
		while not open.is_empty() and open[-1].indent >= indent:
			open.pop_back()
			bodies.pop_back()
		for block: Dictionary in open:
			block.end = i + 1
		if not open.is_empty() and open[-1].kind == KIND_FUNC:
			continue
		# Más adentro que los miembros de la clase: el cuerpo de una lambda de un var, no un miembro.
		var level := 0
		if not open.is_empty():
			if bodies[-1] < 0:
				bodies[-1] = indent
			level = bodies[-1]
		if indent > level:
			continue
		var body := line.strip_edges()
		var annotations := _re_annotations.search(body)
		if annotations:
			body = body.substr(annotations.get_end())
		var found := _re_decl.search(body)
		if found == null:
			continue
		var kind := found.get_string(2)
		var decl_name := found.get_string(3)
		if decl_name.is_empty() and kind != KIND_ENUM:
			continue
		var owner := ""
		if not open.is_empty():
			owner = open[-1].qualified
		var decl := {
			"kind": kind,
			"name": decl_name,
			"qualified": decl_name if owner.is_empty() else "%s.%s" % [owner, decl_name],
			"line": i + 1,
			"start": _doc_start(lines, stmt_of, code, i) + 1,
			"end": i + 1,
			"indent": indent,
			"static": not found.get_string(1).is_empty(),
		}
		result.append(decl)
		if kind == KIND_FUNC or kind == KIND_CLASS:
			open.append(decl)
			bodies.append(-1)
	return result


## La primera línea de los comentarios `##` y las anotaciones que están justo arriba de la línea
## `index` (sin una línea vacía en el medio).
static func _doc_start(lines: PackedStringArray, stmt_of: PackedInt32Array, code: Array, index: int) -> int:
	var start := index
	var i := index - 1
	while i >= 0:
		var stripped := lines[i].strip_edges()
		if stripped.begins_with("##"):
			start = i
			i -= 1
			continue
		if not code[i]:
			break
		var first := stmt_of[i]
		if lines[first].strip_edges().begins_with("@") and _re_decl.search(_strip_annotations(lines[first].strip_edges())) == null:
			start = first
			i = first - 1
			continue
		break
	return start


static func _strip_annotations(body: String) -> String:
	var annotations := _re_annotations.search(body)
	return body.substr(annotations.get_end()) if annotations else body


## Las funciones de `declarations` que se llaman `wanted`: por nombre calificado exacto
## (`Inner.jump`); si no hay, las que terminan así (`Deeper.jump` → `Inner.Deeper.jump`); si
## tampoco, por el nombre solo.
static func find_functions(declarations: Array[Dictionary], wanted: String) -> Array[Dictionary]:
	var exact: Array[Dictionary] = []
	var suffix: Array[Dictionary] = []
	var by_name: Array[Dictionary] = []
	for decl: Dictionary in declarations:
		if decl.kind != KIND_FUNC:
			continue
		if decl.qualified == wanted:
			exact.append(decl)
		elif str(decl.qualified).ends_with("." + wanted):
			suffix.append(decl)
		elif decl.name == wanted:
			by_name.append(decl)
	if not exact.is_empty():
		return exact
	return suffix if not suffix.is_empty() else by_name


## La función más interna que contiene la línea `line` (desde 1), o {}.
static func function_at(declarations: Array[Dictionary], line: int) -> Dictionary:
	var best := {}
	for decl: Dictionary in declarations:
		if decl.kind == KIND_FUNC and decl.start <= line and line <= decl.end:
			if best.is_empty() or decl.line >= best.line:
				best = decl
	return best
