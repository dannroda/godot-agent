@tool
extends RefCounted
## Índice de líneas del proyecto para LineRetrieval (spec §16.2b). Se arma en un worker a partir de
## las líneas normalizadas de cada archivo y queda inmutable: el hilo principal solo consulta.
## - Las líneas únicas van ordenadas, así que las que empiezan con un prefijo son un rango contiguo
##   que se encuentra con búsqueda binaria.
## - La secuencia de cada archivo (con su indentación) da la línea siguiente y los bloques cortos.
## - Las rotaciones (lo de antes y lo de después de cada identificador) encuentran las líneas que
##   difieren de lo escrito en un solo identificador, para adaptarlas.

## Líneas más cortas o más largas no se indexan.
const MIN_LINE := 4
const MAX_LINE := 240
const DAY_SECONDS := 86400.0
## Semivida (en días) del peso por recencia de modificación del archivo fuente.
const RECENCY_DAYS := 7.0
## Identificadores rotados por línea, y solo los que empiezan antes de esta columna.
const MAX_ROTATIONS := 4
const ROTATE_WITHIN := 48
## Lo escrito después del identificador cambiado (sin espacios) tiene que tener al menos esto.
const MIN_ADAPT_AFTER := 2
const KEYWORDS: PackedStringArray = [
	"var", "const", "func", "static", "if", "elif", "else", "for", "while", "match", "return", "pass",
	"break", "continue", "in", "is", "as", "and", "or", "not", "self", "super", "true", "false", "null",
	"await", "signal", "class", "extends", "enum", "void", "when",
]
const GdLexer := preload("gd_lexer.gd")

const _IDENT_PATTERN := "\"(?:[^\"\\\\]|\\\\.)*\"|'(?:[^'\\\\]|\\\\.)*'|([A-Za-z_]\\w*)"

## Líneas únicas normalizadas, ordenadas.
var keys: PackedStringArray = []
## Paralelo a `keys`: pares [id de archivo, posición en su secuencia, ...].
var positions: Array[PackedInt32Array] = []
var files: PackedStringArray = []
## Por archivo: líneas normalizadas ("" = línea vacía o la del caret, que corta los bloques) y su
## nivel de indentación.
var seq_text: Array[PackedStringArray] = []
var seq_indent: Array[PackedInt32Array] = []
## "antes\u0001después\u0002índice de la línea\u0002inicio\u0002largo", ordenadas.
var rotations: PackedStringArray = []
var _dirs: PackedStringArray = []
var _recency: PackedFloat32Array = []
var _file_ids: Dictionary = {}
var _ident_re: RegEx


func _init() -> void:
	_ident_re = RegEx.create_from_string(_IDENT_PATTERN)


## `file_lines`: ruta -> {lines: PackedStringArray, indents: PackedInt32Array} (de `lines_of`);
## `mtimes`: ruta -> unix time.
static func build(file_lines: Dictionary, mtimes: Dictionary, now_unix: float) -> RefCounted:
	var index := new()
	var where: Dictionary = {}  # línea -> [id de archivo, posición, ...]
	for path: String in file_lines:
		var file_id := index.files.size()
		index.files.append(path)
		index._dirs.append(path.get_base_dir())
		var age_days := maxf(0.0, now_unix - float(mtimes.get(path, now_unix))) / DAY_SECONDS
		index._recency.append(0.5 + 0.5 * exp(-age_days / RECENCY_DAYS))
		index._file_ids[path] = file_id
		var sequence: Dictionary = file_lines[path]
		var lines: PackedStringArray = sequence.lines
		index.seq_text.append(lines)
		index.seq_indent.append(sequence.indents)
		for position in lines.size():
			var line := lines[position]
			if line.length() >= MIN_LINE and line.length() <= MAX_LINE:
				var found: Array = where.get_or_add(line, [])
				found.append(file_id)
				found.append(position)
	index.keys = PackedStringArray(where.keys())
	index.keys.sort()
	index.positions.resize(index.keys.size())
	for i in index.keys.size():
		index.positions[i] = PackedInt32Array(where[index.keys[i]])
	index._rotate()
	return index


func _rotate() -> void:
	for i in keys.size():
		var key := keys[i]
		var count := 0
		for found: RegExMatch in _ident_re.search_all(key):
			var ident := found.get_string(1)
			if ident.is_empty() or ident in KEYWORDS:
				continue
			var start := found.get_start(1)
			if start > ROTATE_WITHIN:
				break
			rotations.append("%s\u0001%s\u0002%d\u0002%d\u0002%d" % [key.left(start), key.substr(found.get_end(1)), i, start, ident.length()])
			count += 1
			if count >= MAX_ROTATIONS:
				break
	rotations.sort()


## Normaliza una línea para el índice y las consultas: sin indentación y con los espacios colapsados
## fuera de los strings (adentro se respetan: `"a  b"` sigue igual).
static func normalize(line: String) -> String:
	var out := line.strip_edges(true, false)
	if not out.contains("\"") and not out.contains("'"):
		out = out.replace("\t", " ")
		while out.contains("  "):
			out = out.replace("  ", " ")
		return out
	var result := ""
	var quote := ""
	var previous_space := false
	var i := 0
	while i < out.length():
		var c := out[i]
		if not quote.is_empty():
			result += c
			if c == "\\" and i + 1 < out.length():
				i += 1
				result += out[i]
			elif c == quote:
				quote = ""
			i += 1
			continue
		if c == " " or c == "\t":
			if not previous_space:
				result += " "
			previous_space = true
		else:
			if c == "\"" or c == "'":
				quote = c
			result += c
			previous_space = false
		i += 1
	return result


## Secuencia de un texto: {lines, indents}. Los comentarios (`comment`: "#" en GDScript, "//" en C#)
## no cuentan; las líneas vacías y `skip_line` (0-based, la del caret en un buffer, a medio
## escribir) quedan como "" y cortan los bloques.
static func lines_of(text: String, skip_line: int = -1, comment: String = "#") -> Dictionary:
	var lines := PackedStringArray()
	var indents := PackedInt32Array()
	var source := text.split("\n")
	var unit := GdLexer.spaces_unit(source)
	for i in source.size():
		var raw := source[i]
		var line := normalize(raw).strip_edges(false, true)
		if line.begins_with(comment):
			continue
		if i == skip_line:
			line = ""
		lines.append(line)
		indents.append(GdLexer.indent_level(raw, unit) if not line.is_empty() else -1)
	return {"lines": lines, "indents": indents}


func size() -> int:
	return keys.size()


## Alguna línea del corpus empieza con `prefix` (aunque sea la línea entera o haya demasiadas).
func has_prefix(prefix: String) -> bool:
	var i := keys.bsearch(prefix)
	return i < keys.size() and keys[i].begins_with(prefix)


## Candidatos que continúan `prefix` (ya normalizado): [{rest, raw, positions}] con `raw` = Σ
## ocurrencias × cercanía (mismo archivo 3, misma carpeta 2, resto 1) × recencia. Si el rango tiene
## más de `max_scan` líneas, el prefijo es demasiado ambiguo y no devuelve nada.
func query(prefix: String, path: String, max_scan: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var start := keys.bsearch(prefix)
	var end := start
	var count := keys.size()
	while end < count and keys[end].begins_with(prefix):
		end += 1
		if end - start > max_scan:
			return out
	var prefix_length := prefix.length()
	for i in range(start, end):
		var key := keys[i]
		if key.length() == prefix_length:
			continue
		out.append({"rest": key.substr(prefix_length), "raw": weight(positions[i], path), "evidence": weight(positions[i], path, false), "positions": positions[i]})
	return out


## Lo que sigue a la línea `line` (normalizada, completa) en el corpus: [{text, delta, raw,
## positions}], con `delta` = indentación de la siguiente menos la de `line` y `positions` las de
## las líneas siguientes.
func next_lines(line: String, path: String, max_scan: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var i := keys.bsearch(line)
	if i >= keys.size() or keys[i] != line or positions[i].size() / 2 > max_scan:
		return out
	var groups: Dictionary = {}  # "delta\u0001texto" -> [pares]
	var pairs := positions[i]
	for j in range(0, pairs.size(), 2):
		var file_id := pairs[j]
		var next := pairs[j + 1] + 1
		if next >= seq_text[file_id].size() or seq_text[file_id][next].is_empty():
			continue
		var delta := seq_indent[file_id][next] - seq_indent[file_id][pairs[j + 1]]
		var group: Array = groups.get_or_add("%d\u0001%s" % [delta, seq_text[file_id][next]], [])
		group.append(file_id)
		group.append(next)
	for group_key: String in groups:
		var next_positions := PackedInt32Array(groups[group_key])
		out.append({"text": group_key.get_slice("\u0001", 1), "delta": group_key.get_slice("\u0001", 0).to_int(), "raw": weight(next_positions, path), "evidence": weight(next_positions, path, false), "positions": next_positions})
	return out


## Las líneas que siguen a `start_positions` mientras todas coinciden (texto y sangría relativa) y
## el bloque no termina (sangría menor que la primera o una línea vacía): [{text, delta}], con
## `delta` relativo a la primera. Con menos de `min_support` posiciones no extiende.
func extend(start_positions: PackedInt32Array, max_lines: int, min_support: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if start_positions.size() / 2 < min_support:
		return out
	for step in range(1, max_lines + 1):
		var text := ""
		var delta := 0
		for j in range(0, start_positions.size(), 2):
			var file_id := start_positions[j]
			var position := start_positions[j + 1]
			var lines := seq_text[file_id]
			if position + step >= lines.size() or lines[position + step].is_empty():
				return out
			var line_delta := seq_indent[file_id][position + step] - seq_indent[file_id][position]
			if j == 0:
				text = lines[position + step]
				delta = line_delta
			elif text != lines[position + step] or delta != line_delta:
				return out
		if delta < 0:
			return out
		out.append({"text": text, "delta": delta})
	return out


## Líneas que difieren de `prefix` (normalizado) en un solo identificador ya escrito, con la misma
## sustitución aplicada al resto (spec §16.2b): [{rest, raw, positions}].
func adapt(prefix: String, path: String, max_scan: int) -> Array[Dictionary]:
	var by_rest: Dictionary = {}
	for found: RegExMatch in _ident_re.search_all(prefix):
		var ident := found.get_string(1)
		if ident.is_empty() or ident in KEYWORDS or found.get_end(1) >= prefix.length():
			continue
		var after := prefix.substr(found.get_end(1))
		if after.strip_edges().length() < MIN_ADAPT_AFTER:
			continue
		var query_key := prefix.left(found.get_start(1)) + "\u0001" + after
		var start := rotations.bsearch(query_key)
		var end := start
		while end < rotations.size() and rotations[end].begins_with(query_key):
			end += 1
			if end - start > max_scan:
				break
		if end - start > max_scan:
			continue
		for r in range(start, end):
			var parts := rotations[r].split("\u0002")
			var key_index := parts[1].to_int()
			var old := keys[key_index].substr(parts[2].to_int(), parts[3].to_int())
			if old == ident:
				continue
			var rest := parts[0].get_slice("\u0001", 1).substr(after.length())
			if rest.strip_edges().is_empty():
				continue
			rest = substitute(rest, old, ident)
			var entry: Dictionary = by_rest.get_or_add(rest, {"rest": rest, "raw": 0.0, "evidence": 0.0, "positions": PackedInt32Array()})
			entry.raw = float(entry.raw) + weight(positions[key_index], path)
			entry.evidence = float(entry.evidence) + weight(positions[key_index], path, false)
			var merged: PackedInt32Array = entry.positions
			merged.append_array(positions[key_index])
			entry.positions = merged
	var out: Array[Dictionary] = []
	for rest: String in by_rest:
		out.append(by_rest[rest])
	return out


## Reemplaza `old` por `new` en `text` donde aparece como identificador o como parte de uno en
## snake_case (`_on_health_changed`), también en PascalCase y MAYÚSCULAS si los dos son snake_case.
static func substitute(text: String, old: String, new: String) -> String:
	var out := _replace_word(text, old, new, "a-z0-9")
	if old == old.to_lower() and new == new.to_lower():
		out = _replace_word(out, old.to_pascal_case(), new.to_pascal_case(), "A-Z0-9", "a-z0-9")
		out = _replace_word(out, old.to_upper(), new.to_upper(), "A-Z0-9")
	return out


static func _replace_word(text: String, old: String, new: String, before: String, after: String = "") -> String:
	if old.is_empty() or not text.contains(old):
		return text
	var re := RegEx.create_from_string("(?<![%s])%s(?![%s])" % [before, old, after if not after.is_empty() else before])
	return re.sub(text, new, true)


## Σ cercanía × recencia de las posiciones (pares [archivo, posición]) respecto de `path`. Sin
## `recent`, solo cercanía: la evidencia, que no baja porque el proyecto envejezca (m16-07).
func weight(pairs: PackedInt32Array, path: String, recent: bool = true) -> float:
	var current_id: int = _file_ids.get(path, -1)
	var current_dir := path.get_base_dir()
	var raw := 0.0
	for j in range(0, pairs.size(), 2):
		var file_id := pairs[j]
		var closeness := 3.0 if file_id == current_id else (2.0 if _dirs[file_id] == current_dir else 1.0)
		raw += closeness * (_recency[file_id] if recent else 1.0)
	return raw
