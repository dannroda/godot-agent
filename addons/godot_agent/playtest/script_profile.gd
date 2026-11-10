@tool
extends RefCounted
## m13-27: junta los frames del profiler de scripts del juego (mensajes `servers:function_signature`
## y `servers:profile_frame` del debugger) y arma las funciones más calientes para godot.profile_run.
## Parte pura: no sabe de dónde vienen los mensajes (ver profile_tools.gd).
##
## Se agrega solo desde los frames, nunca desde `servers:profile_total`: el primer frame después de
## prender el profiler es basura en Godot 4.7/4.8 (las llamadas en curso, que entraron con el profiler
## apagado, se miden desde 0: cientos de ms) y ese total lo arrastra. Por eso se descarta el primer
## frame y cualquiera donde una función diga durar más que el frame entero.

## Overhead medido con tests/run_in_xvfb.sh … --godot-agent-profile-test sobre una función mínima.
const OVERHEAD_NOTE := "The profiler slows every GDScript call (about 80–100 ns per call, ×1.7–1.9 on tiny functions), so small, often-called functions look more expensive than they are: compare functions with each other, and measure before and after a change with this same tool."
## Margen sobre frame_time para dar por imposible lo que dice una función (s).
const FRAME_SLACK_S := 0.01
## Hasta cuántas líneas antes de la de la firma se busca el `func` (cabeceras de varias líneas).
const DECLARATION_SEARCH := 12

## id → "res://ruta.gd::línea::función" (scripts built-in: 4 partes).
var signatures: Dictionary = {}
## Frames agregados y descartados.
var frames: int = 0
var discarded: int = 0
var _skip_next: bool = true
## id → {calls, self, total, internal, frames}; tiempos en segundos, sumados.
var _functions: Dictionary = {}
var _frame_time: float = 0.0
var _script_time: float = 0.0


## El próximo frame no se cuenta: el juego estuvo parado en el debugger y la llamada en curso se
## lleva el tiempo de la pausa (continue_on_error).
func skip_next_frame() -> void:
	_skip_next = true


func add_signature(data: Array) -> void:
	if data.size() >= 2:
		signatures[int(data[1])] = str(data[0])


func add_frame(data: Array) -> void:
	if _skip_next:
		_skip_next = false
		discarded += 1
		return
	var frame := parse_frame(data)
	if frame.is_empty():
		discarded += 1
		return
	# Con el tiempo propio: el total de una función recursiva cuenta lo anidado una vez por nivel y
	# puede pasar legítimamente al frame (revisión de m13-27).
	for function: Dictionary in frame.functions.values():
		if function.self > frame.frame_time + FRAME_SLACK_S:
			discarded += 1
			return
	frames += 1
	_frame_time += frame.frame_time
	_script_time += frame.script_time
	for id: int in frame.functions:
		var function: Dictionary = frame.functions[id]
		var sum: Dictionary = _functions.get_or_add(id, {"calls": 0, "self": 0.0, "total": 0.0, "internal": 0.0, "frames": 0})
		sum.calls += function.calls
		sum.self += function.self
		sum.total += function.total
		sum.internal += function.internal
		sum.frames += 1


## Un ServersProfilerFrame serializado (servers/debugger/servers_debugger.cpp):
## [frame, frame_time, process_time, physics_time, physics_frame_time, script_time, n_servers,
##  (nombre, 2*n, (función, tiempo)…)…, 5*n_funcs, (sig_id, calls, self, total, internal)…], en segundos.
## {} si no tiene esa forma.
static func parse_frame(data: Array) -> Dictionary:
	if data.size() < 8:
		return {}
	var idx := 7
	var servers := int(data[6])
	if servers < 0 or 7 + servers * 2 > data.size():
		return {}
	for i in servers:
		if idx + 1 >= data.size():
			return {}
		var pairs := int(data[idx + 1])
		if pairs < 0:
			return {}
		idx += 2 + pairs
	if idx >= data.size():
		return {}
	var size := int(data[idx])
	idx += 1
	if size < 0 or idx + size > data.size():
		return {}
	var functions := {}
	for i in size / 5:
		functions[int(data[idx])] = {"calls": int(data[idx + 1]), "self": float(data[idx + 2]), "total": float(data[idx + 3]), "internal": float(data[idx + 4])}
		idx += 5
	return {"frame_time": float(data[1]), "script_time": float(data[5]), "functions": functions}


## Las `count` funciones con más tiempo propio, por frame agregado:
## [{signature, path, line, name, calls, self_ms, total_ms, share, typed}]. `share`: fracción del
## tiempo de script de los frames; `typed`: "yes", "partial", "no" o "" (no se pudo leer).
func top(count: int) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	if frames == 0:
		return rows
	for id: int in _functions:
		var sum: Dictionary = _functions[id]
		var signature := str(signatures.get(id, "?::0::?"))
		var where := split_signature(signature)
		rows.append({
			"signature": signature, "path": where.path, "line": where.line, "name": where.name,
			"calls": float(sum.calls) / frames,
			"self_ms": sum.self * 1000.0 / frames, "total_ms": sum.total * 1000.0 / frames,
			"internal_ms": sum.internal * 1000.0 / frames,
			"share": sum.self / _script_time if _script_time > 0.0 else 0.0,
		})
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.self_ms > b.self_ms)
	rows = rows.slice(0, count)
	var sources := {}  # ruta → texto: cada script se lee una vez por informe
	for row: Dictionary in rows:
		var found := typed_in_file(row.path, row.line, row.name, sources)
		row["typed"] = found.typed
		if found.line > 0:
			row["line"] = found.line
	return rows


func average_frame_ms() -> float:
	return _frame_time * 1000.0 / frames if frames > 0 else 0.0


func average_script_ms() -> float:
	return _script_time * 1000.0 / frames if frames > 0 else 0.0


## "res://a.gd::12::_process" → {path, line, name}. Un script built-in trae una parte más
## ("res://s.tscn::GDScript_x::12::f"): la ruta queda con el sub-recurso.
static func split_signature(signature: String) -> Dictionary:
	var parts := signature.split("::")
	if parts.size() < 3:
		return {"path": signature, "line": 0, "name": ""}
	return {"path": "::".join(parts.slice(0, parts.size() - 2)), "line": int(parts[-2]), "name": parts[-1]}


## Si la función de `path` tiene tipos: {typed, line}. `typed`: "yes" (todos los parámetros y el
## retorno), "partial", "no" o "" si no se puede leer (built-in, archivo que no está); `line`: la del
## `func` (0 si no se encontró).
static func typed_in_file(path: String, line: int, function_name: String, sources: Dictionary = {}) -> Dictionary:
	if not path.begins_with("res://") or path.contains("::") or not FileAccess.file_exists(path):
		return {"typed": "", "line": 0}
	if not sources.has(path):
		sources[path] = FileAccess.get_file_as_string(path)
	return typed_in_source(sources[path], line, function_name)


## La línea de la firma del profiler no es la del `func`: es la primera del cuerpo (4.7/4.8). Se busca
## la declaración hacia atrás desde ahí, hasta DECLARATION_SEARCH líneas.
static func typed_in_source(source: String, line: int, function_name: String) -> Dictionary:
	var none := {"typed": "", "line": 0}
	var lines := source.split("\n")
	if line < 1 or line > lines.size():
		return none
	var declaration := RegEx.create_from_string("^\\s*(static\\s+)?func\\s+" + function_name + "\\s*\\(")
	var any_declaration := RegEx.create_from_string("^\\s*(static\\s+)?func\\s")
	var start := -1
	for i in range(line - 1, maxi(line - 1 - DECLARATION_SEARCH, -1), -1):
		if declaration.search(lines[i]):
			start = i
			break
		if any_declaration.search(lines[i]):
			break  # otra función: la firma no es de esta
	if start < 0:
		return none
	# La declaración puede ocupar varias líneas (parámetros largos).
	var header := " ".join(lines.slice(start, mini(start + 10, lines.size())))
	var at := RegEx.create_from_string("\\bfunc\\s+" + function_name + "\\s*\\(").search(header)
	if at == null:
		return none
	var open := at.get_end() - 1
	var close := _matching_paren(header, open)
	if close < 0:
		return none
	var params := _split_params(header.substr(open + 1, close - open - 1))
	var typed := 0
	for param: String in params:
		if _param_typed(param):
			typed += 1
	var returns := header.substr(close + 1).strip_edges().begins_with("->")
	var count := typed + (1 if returns else 0)
	var typed_text := "yes" if count == params.size() + 1 else ("no" if count == 0 else "partial")
	return {"typed": typed_text, "line": start + 1}


## El índice del `)` que cierra el `(` de `open`, o -1. Saltea strings (`a: String = ")"`).
static func _matching_paren(text: String, open: int) -> int:
	var depth := 0
	var quote := ""
	var i := open
	while i < text.length():
		var character := text[i]
		if not quote.is_empty():
			if character == "\\":
				i += 1
			elif character == quote:
				quote = ""
		elif character == "\"" or character == "'":
			quote = character
		elif character == "(":
			depth += 1
		elif character == ")":
			depth -= 1
			if depth == 0:
				return i
		i += 1
	return -1


## Parámetros separados por comas de primer nivel y fuera de strings (un default puede llevar
## `Vector2(1, 2)`, `{"a": 1}` o `"x,y"`).
static func _split_params(text: String) -> PackedStringArray:
	var params: PackedStringArray = []
	var depth := 0
	var quote := ""
	var current := ""
	var i := 0
	while i < text.length():
		var character := text[i]
		if not quote.is_empty():
			if character == "\\" and i + 1 < text.length():
				current += character
				i += 1
				character = text[i]
			elif character == quote:
				quote = ""
		elif character == "\"" or character == "'":
			quote = character
		elif character in ["(", "[", "{"]:
			depth += 1
		elif character in [")", "]", "}"]:
			depth -= 1
		if character == "," and depth == 0 and quote.is_empty():
			params.append(current.strip_edges())
			current = ""
		else:
			current += character
		i += 1
	if not current.strip_edges().is_empty():
		params.append(current.strip_edges())
	return params


## Si un parámetro tiene tipo: un `:` antes del `=` del default (`a: int`, `a: int = 1`, `a := 1`).
## Un `:` dentro del default (`a = {"k": 1}`, `a = "x:y"`) no cuenta.
static func _param_typed(param: String) -> bool:
	for character: String in param:
		if character == ":":
			return true
		if character == "=":
			return false
	return false


## El texto para el agente.
func report(count: int) -> String:
	var lines: PackedStringArray = []
	if frames == 0:
		return "No usable profiler frames arrived (%d discarded): the game may have ended or stopped in the debugger before a full frame." % discarded
	lines.append("Script profile: %d frames (%d discarded: the first one after the profiler starts is always wrong). Average frame %.2f ms, GDScript %.2f ms." % [frames, discarded, average_frame_ms(), average_script_ms()])
	lines.append("Hottest GDScript functions by self time (per frame: calls, self ms, total ms with what they call, share of script time, typed):")
	for row: Dictionary in top(count):
		var typed: String = row.typed if not row.typed.is_empty() else "?"
		lines.append("  %s:%d %s — %.1f calls, self %.3f ms, total %.3f ms, %.0f%%, typed: %s" % [row.path, row.line, row.name, row.calls, row.self_ms, row.total_ms, row.share * 100.0, typed])
	lines.append(OVERHEAD_NOTE)
	return "\n".join(lines)
