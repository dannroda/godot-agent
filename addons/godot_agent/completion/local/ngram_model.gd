@tool
extends RefCounted
## NGramModel del completado (spec §16.2c): 4-gramas de tokens GDScript con stupid backoff y
## generación greedy hasta el fin de la línea o hasta que la confianza baja.
## Se entrena en el worker del índice y queda inmutable al publicarse. El build siguiente copia las
## tablas (copia superficial) y solo rehace las de los contextos que tocan los archivos cambiados:
## nunca modifica un diccionario que el hilo principal pueda estar leyendo.

const GdLexer := preload("gd_lexer.gd")

const ORDER := 4
## Peso de cada paso de backoff a un contexto más corto (stupid backoff). Con STEP_MIN 0,5 un paso
## que viene de un contexto más corto nunca alcanza: genera solo el contexto completo (3 tokens).
## Probado medir el umbral sin este factor: el set de evaluación no cambió (D27).
const BACKOFF := 0.4
## Ids de tokens (20 bits por posición en la clave del contexto).
const MAX_VOCAB := (1 << 20) - 1
## Más de esta fracción de archivos cambiados: se reentrena entero.
const FULL_RETRAIN_SHARE := 0.3
## Un paso que no supera esta confianza corta la generación (un empate entre dos continuaciones
## también: ante la duda, se para ahí).
const STEP_MIN := 0.5
## La confianza acumulada (producto de los pasos) tampoco baja de esto.
const CUMULATIVE_MIN := 0.3
## Contextos vistos menos veces no cuentan.
const MIN_SUPPORT := 2
const MAX_TOKENS := 24
const NUMBER := "<num>"
## De una línea de arriba más larga que esto se tokeniza solo el final (el contexto usa 3 tokens).
const LONG_CONTEXT_LINE := 256

## token -> id (el 0 es NEWLINE: el comienzo de un archivo cuenta como un salto de línea).
var vocab: Dictionary = {GdLexer.NEWLINE: 0}
var words: PackedStringArray = [GdLexer.NEWLINE]
## id -> id con el que cuenta en un contexto: el mismo, salvo los números, que cuentan como su
## clase (`create_timer(0.3).` y `create_timer(2).` son el mismo contexto).
var context_ids: PackedInt32Array = [0]
## clave de contexto -> {id siguiente: cuenta}
var counts: Dictionary = {}
## clave de contexto -> total
var totals: Dictionary = {}
## ruta -> tokens con los que se entrenó (para restarlos cuando cambia)
var sources: Dictionary = {}
var token_count: int = 0
## Cachés de consulta por clave de contexto (solo el hilo principal las toca): (id más visto,
## total) entre todos y entre los que llevan espacio, y las continuaciones ordenadas.
var _stats: Dictionary = {}
var _spaced_stats: Dictionary = {}
var _sorted: Dictionary = {}


## `files`: ruta -> PackedStringArray de tokens (GdLexer.tokenize). `previous`: el modelo anterior
## o null; si cambió poco, se actualiza por archivo.
static func build(files: Dictionary, previous: RefCounted = null) -> RefCounted:
	var model := new()
	var changed: Array[String] = []
	var removed: Array[String] = []
	if previous:
		for path: String in files:
			if not previous.sources.has(path) or previous.sources[path] != files[path]:
				changed.append(path)
		for path: String in previous.sources:
			if not files.has(path):
				removed.append(path)
	if previous == null or changed.size() + removed.size() > maxf(1.0, files.size() * FULL_RETRAIN_SHARE):
		for path: String in files:
			model._count(files[path])
		model._sum_totals()
		model.sources = files.duplicate()
		return model
	if changed.is_empty() and removed.is_empty():
		return previous
	model.vocab = previous.vocab.duplicate()
	# Copias: los Packed*Array asignados se comparten, y `_id` les agrega tokens nuevos mientras el
	# hilo principal lee los del modelo publicado.
	model.words = previous.words.duplicate()
	model.context_ids = previous.context_ids.duplicate()
	model.counts = previous.counts.duplicate()
	model.totals = previous.totals.duplicate()
	model.sources = previous.sources.duplicate()
	model.token_count = previous.token_count
	var owned: Dictionary = {}
	for path: String in removed + changed:
		if previous.sources.has(path):
			model._update(previous.sources[path], -1, owned)
		model.sources.erase(path)
	for path: String in changed:
		model._update(files[path], 1, owned)
		model.sources[path] = files[path]
	return model


## Ids de una secuencia, con el NEWLINE inicial (el comienzo del archivo).
func _ids(tokens: PackedStringArray) -> PackedInt32Array:
	var ids := PackedInt32Array()
	ids.resize(tokens.size() + 1)
	ids[0] = 0
	for i in tokens.size():
		ids[i + 1] = _id(tokens[i])
	return ids


## Entrenamiento desde cero: solo cuentas (los totales se suman al final, `_sum_totals`).
func _count(tokens: PackedStringArray) -> void:
	var ids := _ids(tokens)
	token_count += tokens.size()
	for i in range(1, ids.size()):
		var target := ids[i]
		if target < 0:
			continue
		var context := 0
		for k in range(1, ORDER):
			if i - k < 0 or ids[i - k] < 0:
				break
			context |= context_ids[ids[i - k]] << (20 * (k - 1))
			var inner: Dictionary = counts.get_or_add((k << 60) | context, {})
			inner[target] = int(inner.get(target, 0)) + 1


func _sum_totals() -> void:
	for key: int in counts:
		var total := 0
		for count: int in (counts[key] as Dictionary).values():
			total += count
		totals[key] = total


## Suma (`delta` 1) o resta (-1) los n-gramas de una secuencia sobre tablas copiadas del modelo
## anterior. `owned`: contextos cuyo diccionario ya es propio de este modelo (los demás se copian
## antes de tocarlos: el anterior lo puede estar leyendo el hilo principal).
func _update(tokens: PackedStringArray, delta: int, owned: Dictionary) -> void:
	var ids := _ids(tokens)
	token_count += delta * tokens.size()
	for i in range(1, ids.size()):
		var target := ids[i]
		if target < 0:
			continue
		var context := 0
		for k in range(1, ORDER):
			if i - k < 0 or ids[i - k] < 0:
				break
			context |= context_ids[ids[i - k]] << (20 * (k - 1))
			var key := (k << 60) | context
			var inner: Dictionary
			if owned.has(key):
				inner = counts.get_or_add(key, {})
			elif counts.has(key):
				inner = (counts[key] as Dictionary).duplicate()
				counts[key] = inner
			elif delta > 0:
				inner = {}
				counts[key] = inner
			else:
				continue
			owned[key] = true
			var count := int(inner.get(target, 0)) + delta
			if count > 0:
				inner[target] = count
			else:
				inner.erase(target)
			var total := int(totals.get(key, 0)) + delta
			if total > 0:
				totals[key] = total
			else:
				totals.erase(key)
				counts.erase(key)


## Id de un token, o -1 si el vocabulario está lleno.
func _id(token: String) -> int:
	var id: int = vocab.get(token, -1)
	if id < 0 and words.size() < MAX_VOCAB - 1:
		var context_id := _id(" " + NUMBER if token.begins_with(" ") else NUMBER) if _is_number(token) else -1
		id = words.size()
		vocab[token] = id
		words.append(token)
		context_ids.append(context_id if context_id >= 0 else id)
	return id


static func _is_number(token: String) -> bool:
	var text := token.strip_edges(true, false)
	if text.is_empty():
		return false
	var first := text.unicode_at(0)
	return (first >= 48 and first <= 57) or (first == 46 and text.length() > 1 and text.unicode_at(1) >= 48 and text.unicode_at(1) <= 57)


## Clave de los últimos `length` ids de `ids`: el largo en los bits altos y 20 bits por id, el más
## cercano abajo. -1 si alguno es desconocido.
static func _key(ids: PackedInt32Array, length: int) -> int:
	var context := 0
	for k in range(1, length + 1):
		var id := ids[ids.size() - k]
		if id < 0:
			return -1
		context |= id << (20 * (k - 1))
	return (length << 60) | context


## Contexto para `generate` desde lo que rodea al caret: las líneas de arriba (cada una con su
## NEWLINE), el cambio de sangría de la línea actual y sus tokens. Un identificador, número o string
## a medio escribir al final queda aparte como `partial`. Devuelve {context, partial, after_space}.
static func context_for(previous_lines: PackedStringArray, prefix: String, spaces_per_level: int = GdLexer.SPACES_PER_LEVEL) -> Dictionary:
	var context := PackedStringArray()
	var previous := ""
	for line: String in previous_lines:
		var stripped := line.strip_edges()
		if stripped.is_empty() or stripped.begins_with("#"):
			continue
		# Entre líneas, los cambios de sangría como al entrenar (`<indent>` antes de la línea).
		if not previous.is_empty():
			_append_level_change(context, GdLexer.indent_level(previous, spaces_per_level), GdLexer.indent_level(line, spaces_per_level))
		# Solo cuentan los últimos tokens: de una línea muy larga alcanza con el final.
		context.append_array(GdLexer.tokenize_line(line if line.length() <= LONG_CONTEXT_LINE else line.right(LONG_CONTEXT_LINE)))
		context.append(GdLexer.NEWLINE)
		previous = line
	var level := GdLexer.indent_level(prefix, spaces_per_level)
	_append_level_change(context, GdLexer.indent_level(previous, spaces_per_level) if not previous.is_empty() else level, level)
	if context.is_empty():
		context.append(GdLexer.NEWLINE)  # el comienzo de la línea, como al entrenar
	var tokens := GdLexer.tokenize_line(prefix)
	var typed := not prefix.strip_edges().is_empty()
	var after_space := typed and (prefix.ends_with(" ") or prefix.ends_with("\t"))
	var partial := ""
	if typed and not after_space and not tokens.is_empty() and GdLexer.is_open_token(tokens[tokens.size() - 1]):
		partial = tokens[tokens.size() - 1]
		tokens.remove_at(tokens.size() - 1)
	context.append_array(tokens)
	return {"context": context, "partial": partial, "after_space": after_space}


static func _append_level_change(context: PackedStringArray, from_level: int, to_level: int) -> void:
	if to_level > from_level:
		context.append(GdLexer.INDENT)
	for i in maxi(0, from_level - to_level):
		context.append(GdLexer.DEDENT)


## Continúa `context` (tokens ya completos, el último más cercano al caret). `partial`: el token a
## medio escribir ("" si no hay): el primero generado tiene que empezar con él. `after_space`: lo
## escrito termina en espacio, así que el primer token tiene que llevarlo.
## Devuelve {text, score, complete} o {} si no hay nada con confianza.
func generate(context: PackedStringArray, partial: String = "", after_space: bool = false, step_min: float = STEP_MIN, cumulative_min: float = CUMULATIVE_MIN, min_support: int = MIN_SUPPORT) -> Dictionary:
	var ids := PackedInt32Array()
	for token: String in context.slice(maxi(0, context.size() - (ORDER - 1))):
		var id: int = vocab.get(token, -1)
		ids.append(context_ids[id] if id >= 0 else -1)
	var text := ""
	var score := 1.0
	var steps := 0
	var complete := false
	while steps < MAX_TOKENS:
		var best := _best_next(ids, partial if steps == 0 else "", after_space and steps == 0, min_support)
		if best.is_empty() or float(best.score) <= step_min or score * float(best.score) < cumulative_min:
			break
		var token: String = words[int(best.id)]
		if token == GdLexer.NEWLINE:
			complete = true
			break
		if token == GdLexer.INDENT or token == GdLexer.DEDENT:
			break
		if steps == 0:
			token = token.substr(partial.length()) if not partial.is_empty() else (token.substr(1) if after_space else token)
		text += token
		score *= float(best.score)
		steps += 1
		ids.append(context_ids[int(best.id)])
		if ids.size() > ORDER - 1:
			ids = ids.slice(ids.size() - (ORDER - 1))
	if text.is_empty() and not complete:
		return {}
	return {"text": text, "score": score, "complete": complete, "steps": steps}


## El siguiente token más probable con stupid backoff: el contexto más largo que lo vio manda; un
## contexto más corto vale BACKOFF por cada nivel que baja. Se compara el más probable de cada
## contexto; con algo a medio escribir (o después de un espacio), entre los tokens compatibles.
func _best_next(ids: PackedInt32Array, partial: String, needs_space: bool, min_support: int = MIN_SUPPORT) -> Dictionary:
	var best := {}
	var higher: Array[Dictionary] = []
	var weight := 1.0
	for k in range(mini(ids.size(), ORDER - 1), 0, -1):
		var key := _key(ids, k)
		if key >= 0 and counts.has(key):
			var inner: Dictionary = counts[key]
			var stats := _range_stats(key, partial) if not partial.is_empty() else _cached_stats(key, needs_space)
			var top := stats.x
			# Un token que ya vio un contexto más largo se puntuó ahí.
			if top >= 0 and stats.y >= min_support and not higher.any(func(table: Dictionary) -> bool: return table.has(top)):
				best = _better(best, top, weight * inner[top] / float(stats.y))
			higher.append(inner)
		weight *= BACKOFF
	return best


static func _better(best: Dictionary, id: int, score: float) -> Dictionary:
	return {"id": id, "score": score} if best.is_empty() or score > float(best.score) else best


## (id más visto, total) de un contexto, entre todos o solo entre los tokens con espacio adelante.
## Se calcula la primera vez que se pide (en el hilo principal: el modelo publicado ya no cambia).
func _cached_stats(key: int, spaced: bool) -> Vector2i:
	var cache := _spaced_stats if spaced else _stats
	if cache.has(key):
		return cache[key]
	var inner: Dictionary = counts[key]
	var top := -1
	var top_count := 0
	var total := 0
	for id: int in inner:
		if spaced and not words[id].begins_with(" "):
			continue
		var count: int = inner[id]
		total += count
		if count > top_count:
			top = id
			top_count = count
	cache[key] = Vector2i(top, total)
	return cache[key]


## (id más visto, total) entre los tokens que empiezan con `partial`: un rango de la lista ordenada
## de continuaciones del contexto (armada una vez por contexto).
func _range_stats(key: int, partial: String) -> Vector2i:
	var sorted: PackedStringArray = _sorted.get(key, PackedStringArray())
	if sorted.is_empty():
		for id: int in counts[key]:
			sorted.append(words[id] + "\u0001" + str(id))
		sorted.sort()
		_sorted[key] = sorted
	var inner: Dictionary = counts[key]
	var top := -1
	var top_count := 0
	var total := 0
	var i := sorted.bsearch(partial)
	while i < sorted.size() and sorted[i].begins_with(partial):
		var id := sorted[i].get_slice("\u0001", 1).to_int()
		var count: int = inner[id]
		total += count
		if count > top_count:
			top = id
			top_count = count
		i += 1
	return Vector2i(top, total)
