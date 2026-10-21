@tool
extends RefCounted
## Índice de líneas del proyecto para LineRetrieval (spec §16.2b). Se arma en un worker a partir de
## las líneas normalizadas de cada archivo y queda inmutable: el hilo principal solo consulta.
## Las líneas únicas van ordenadas, así que las que empiezan con un prefijo son un rango contiguo
## que se encuentra con búsqueda binaria.

## Líneas más cortas o más largas no se indexan.
const MIN_LINE := 4
const MAX_LINE := 240
const DAY_SECONDS := 86400.0
## Semivida (en días) del peso por recencia de modificación del archivo fuente.
const RECENCY_DAYS := 7.0

## Líneas únicas normalizadas, ordenadas.
var keys: PackedStringArray = []
## Paralelo a `keys`: pares [id de archivo, ocurrencias, ...].
var occurrences: Array[PackedInt32Array] = []
var files: PackedStringArray = []
var _dirs: PackedStringArray = []
var _recency: PackedFloat32Array = []
var _file_ids: Dictionary = {}


## `file_lines`: ruta -> PackedStringArray de líneas ya normalizadas; `mtimes`: ruta -> unix time.
static func build(file_lines: Dictionary, mtimes: Dictionary, now_unix: float) -> RefCounted:
	var index := new()
	var counts: Dictionary = {}  # línea -> {id de archivo: ocurrencias}
	for path: String in file_lines:
		var file_id := index.files.size()
		index.files.append(path)
		index._dirs.append(path.get_base_dir())
		var age_days := maxf(0.0, now_unix - float(mtimes.get(path, now_unix))) / DAY_SECONDS
		index._recency.append(0.5 + 0.5 * exp(-age_days / RECENCY_DAYS))
		index._file_ids[path] = file_id
		for line: String in file_lines[path]:
			var per_file: Dictionary = counts.get_or_add(line, {})
			per_file[file_id] = int(per_file.get(file_id, 0)) + 1
	index.keys = PackedStringArray(counts.keys())
	index.keys.sort()
	index.occurrences.resize(index.keys.size())
	for i in index.keys.size():
		var per_file: Dictionary = counts[index.keys[i]]
		var pairs := PackedInt32Array()
		for file_id: int in per_file:
			pairs.append(file_id)
			pairs.append(per_file[file_id])
		index.occurrences[i] = pairs
	return index


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


## Líneas normalizadas indexables de un texto. `skip_line` (0-based) queda afuera: es la del caret,
## que en el buffer está a medio escribir.
static func lines_of(text: String, skip_line: int = -1) -> PackedStringArray:
	var out := PackedStringArray()
	var lines := text.split("\n")
	for i in lines.size():
		if i == skip_line:
			continue
		var line := normalize(lines[i]).strip_edges(false, true)
		if line.length() >= MIN_LINE and line.length() <= MAX_LINE:
			out.append(line)
	return out


func size() -> int:
	return keys.size()


## Candidatos que continúan `prefix` (ya normalizado): [{rest, raw}] con `raw` = Σ ocurrencias ×
## cercanía (mismo archivo 3, misma carpeta 2, resto 1) × recencia. Si el rango tiene más de
## `max_scan` líneas, el prefijo es demasiado ambiguo y no devuelve nada.
func query(prefix: String, path: String, max_scan: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var start := keys.bsearch(prefix)
	var end := start
	var count := keys.size()
	while end < count and keys[end].begins_with(prefix):
		end += 1
		if end - start > max_scan:
			return out
	var current_id: int = _file_ids.get(path, -1)
	var current_dir := path.get_base_dir()
	var prefix_length := prefix.length()
	for i in range(start, end):
		var key := keys[i]
		if key.length() == prefix_length:
			continue
		var raw := 0.0
		var pairs := occurrences[i]
		for j in range(0, pairs.size(), 2):
			var file_id := pairs[j]
			var closeness := 3.0 if file_id == current_id else (2.0 if _dirs[file_id] == current_dir else 1.0)
			raw += pairs[j + 1] * closeness * _recency[file_id]
		out.append({"rest": key.substr(prefix_length), "raw": raw})
	return out
