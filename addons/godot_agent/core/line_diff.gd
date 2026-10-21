@tool
extends RefCounted
## Diff por líneas (LCS) para las tarjetas de diff y los conflictos. Recorta prefijo y sufijo
## comunes; si lo que queda es muy grande, lo marca entero como quitado y agregado.

const EQUAL := 0
const ADD := 1
const REMOVE := 2

## Tope de celdas de la tabla LCS (filas × columnas) antes de rendirse.
const MAX_CELLS := 400000


## `[{kind, text, new_line}]`. `new_line` es la línea (1-based) en el texto nuevo, o la posición
## donde estaría para las líneas quitadas.
static func diff(old_text: String, new_text: String) -> Array[Dictionary]:
	var a := _lines(old_text)
	var b := _lines(new_text)
	var ops: Array[Dictionary] = []
	var prefix := 0
	while prefix < a.size() and prefix < b.size() and a[prefix] == b[prefix]:
		prefix += 1
	var suffix := 0
	while suffix < a.size() - prefix and suffix < b.size() - prefix and a[a.size() - 1 - suffix] == b[b.size() - 1 - suffix]:
		suffix += 1
	for i in prefix:
		ops.append({"kind": EQUAL, "text": a[i], "new_line": i + 1})
	var mid_a := a.slice(prefix, a.size() - suffix)
	var mid_b := b.slice(prefix, b.size() - suffix)
	ops.append_array(_middle(mid_a, mid_b, prefix))
	for i in suffix:
		var index := b.size() - suffix + i
		ops.append({"kind": EQUAL, "text": b[index], "new_line": index + 1})
	return ops


static func count(ops: Array[Dictionary]) -> Dictionary:
	var added := 0
	var removed := 0
	for op: Dictionary in ops:
		if op.kind == ADD:
			added += 1
		elif op.kind == REMOVE:
			removed += 1
	return {"added": added, "removed": removed}


static func first_changed_line(ops: Array[Dictionary]) -> int:
	for op: Dictionary in ops:
		if op.kind != EQUAL:
			return int(op.new_line)
	return 1


static func _middle(a: PackedStringArray, b: PackedStringArray, offset: int) -> Array[Dictionary]:
	var ops: Array[Dictionary] = []
	if a.size() * b.size() > MAX_CELLS or a.is_empty() or b.is_empty():
		for line: String in a:
			ops.append({"kind": REMOVE, "text": line, "new_line": offset + 1})
		for i in b.size():
			ops.append({"kind": ADD, "text": b[i], "new_line": offset + i + 1})
		return ops
	# Tabla LCS de sufijos: lcs[i][j] = LCS de a[i:] y b[j:].
	var width := b.size() + 1
	var lcs := PackedInt32Array()
	lcs.resize((a.size() + 1) * width)
	for i in range(a.size() - 1, -1, -1):
		for j in range(b.size() - 1, -1, -1):
			if a[i] == b[j]:
				lcs[i * width + j] = lcs[(i + 1) * width + j + 1] + 1
			else:
				lcs[i * width + j] = maxi(lcs[(i + 1) * width + j], lcs[i * width + j + 1])
	var i := 0
	var j := 0
	while i < a.size() and j < b.size():
		if a[i] == b[j]:
			ops.append({"kind": EQUAL, "text": b[j], "new_line": offset + j + 1})
			i += 1
			j += 1
		elif lcs[(i + 1) * width + j] >= lcs[i * width + j + 1]:
			ops.append({"kind": REMOVE, "text": a[i], "new_line": offset + j + 1})
			i += 1
		else:
			ops.append({"kind": ADD, "text": b[j], "new_line": offset + j + 1})
			j += 1
	while i < a.size():
		ops.append({"kind": REMOVE, "text": a[i], "new_line": offset + j + 1})
		i += 1
	while j < b.size():
		ops.append({"kind": ADD, "text": b[j], "new_line": offset + j + 1})
		j += 1
	return ops


static func _lines(text: String) -> PackedStringArray:
	if text.is_empty():
		return PackedStringArray()
	var lines := text.replace("\r\n", "\n").split("\n")
	if text.ends_with("\n"):
		lines.resize(lines.size() - 1)
	return lines
