extends RefCounted
## Evaluación del completado (spec §16.9) sobre tests/completion_eval: para cada caso, el archivo
## cortado en el caret (lo de después no existe todavía) entra al índice como buffer sin guardar, y
## cada combinación de fuentes del proveedor local sugiere el resto de la línea.
## Métricas por combinación: exact match de la primera línea, sugerencias correctas (prefijo de lo
## esperado), similitud por tokens, cobertura, falsos positivos y latencia; y qué fuente ganó.

const ProjectContext := preload("res://addons/godot_agent/completion/project_context.gd")
const LocalProvider := preload("res://addons/godot_agent/completion/local/local_provider.gd")
const CompletionRequest := preload("res://addons/godot_agent/completion/completion_request.gd")
const CompletionResult := preload("res://addons/godot_agent/completion/completion_result.gd")
const GdLexer := preload("res://addons/godot_agent/completion/local/gd_lexer.gd")

const EVAL_DIR := "res://tests/completion_eval"
const PROJECT := EVAL_DIR + "/project"
const CASES := EVAL_DIR + "/cases.txt"
const END_MARK := "⏎"
## Combinaciones por defecto. El historial de la sesión arranca vacío en cada caso, así que no
## cambia nada acá: se prueba en los tests unitarios.
const DEFAULT_COMBOS := "rule retrieval ngram rule+retrieval rule+retrieval+ngram"

var cases: Array[Dictionary] = []
var errors: PackedStringArray = []


## Lee cases.txt: {file, path, line (0-based), cut, typed, expected, buffer, category}.
func load_cases() -> void:
	var category := ""
	for raw: String in FileAccess.get_file_as_string(CASES).split("\n"):
		var line := raw.strip_edges()
		if line.begins_with("# ---"):
			category = line.trim_prefix("# ---").get_slice("(", 0).strip_edges()
			continue
		if line.is_empty() or line.begins_with("#"):
			continue
		var parts := raw.split("|")
		if parts.size() != 3:
			errors.append("línea mal formada: %s" % raw)
			continue
		var file := parts[0].strip_edges()
		var cut := parts[2].strip_edges().trim_suffix(END_MARK)
		var path := PROJECT.path_join(file)
		var source := FileAccess.get_file_as_string(path).split("\n")
		var index := parts[1].strip_edges().to_int() - 1
		if index < 0 or index >= source.size():
			errors.append("%s:%d no existe" % [file, index + 1])
			continue
		var target := source[index]
		var stripped := target.strip_edges(true, false)
		if not stripped.begins_with(cut) or stripped.length() == cut.length():
			errors.append("%s:%d no empieza con «%s»" % [file, index + 1, cut])
			continue
		var typed := target.left(target.length() - stripped.length()) + cut
		var before := "\n".join(source.slice(0, index))
		cases.append({
			"file": file, "path": path, "line": index, "cut": cut, "typed": typed, "category": category,
			"expected": stripped.substr(cut.length()).strip_edges(false, true),
			"buffer": (before + "\n" if index > 0 else "") + typed,
		})


## Corre las combinaciones sobre todos los casos. Devuelve {combos: [{sources, metrics, by_source,
## outcomes}]} con un outcome por caso: {file, line, cut, expected, got, source, exact, correct}.
## `configure`: se llama con cada proveedor antes de correr (para probar umbrales).
## `age_days`: edad de todos los archivos del proyecto, contada desde el más nuevo (la recencia baja con
## la edad); -1 usa la hora real, y entonces el resultado depende de cuándo se copió el repo.
func run(combos: Array[PackedStringArray] = parse_combos(DEFAULT_COMBOS), configure: Callable = Callable(), age_days: float = -1.0) -> Dictionary:
	var context := ProjectContext.new()
	context.root = PROJECT
	context.settings_file = PROJECT + "/project_settings.cfg"
	if age_days >= 0.0:
		context.fixed_now = newest_mtime(PROJECT) + age_days * 86400.0
	context.build_now()
	var providers: Array[LocalProvider] = []
	var results: Array[Dictionary] = []
	for combo: PackedStringArray in combos:
		var provider := LocalProvider.new(context)
		for source: String in provider.sources.keys():
			provider.sources[source] = combo.has(source)
		if configure.is_valid():
			configure.call(provider)
		providers.append(provider)
		results.append({"sources": combo, "outcomes": [], "latencies": PackedFloat64Array()})
	var previous_path := ""
	for case: Dictionary in cases:
		if not previous_path.is_empty():
			context.drop_buffer(previous_path)
		context.update_buffer(case.path, case.buffer, case.line)
		context.build_now()
		previous_path = case.path
		var request: CompletionRequest = CompletionRequest.make(case.path, case.buffer, case.line, str(case.typed).length())
		for i in providers.size():
			var started := Time.get_ticks_usec()
			var result := providers[i].complete(request)
			var latencies: PackedFloat64Array = results[i].latencies
			latencies.append((Time.get_ticks_usec() - started) / 1000.0)
			results[i].latencies = latencies
			(results[i].outcomes as Array).append(_outcome(case, result))
	for entry: Dictionary in results:
		entry.metrics = _metrics(entry.outcomes, entry.latencies)
		entry.by_source = _by_source(entry.outcomes)
	return {"combos": results}


static func newest_mtime(dir: String) -> float:
	var newest := 0.0
	for name: String in DirAccess.get_files_at(dir):
		if name.get_extension() == "gd":
			newest = maxf(newest, FileAccess.get_modified_time(dir.path_join(name)))
	for sub: String in DirAccess.get_directories_at(dir):
		newest = maxf(newest, newest_mtime(dir.path_join(sub)))
	return newest


## "a+b c" -> [["a", "b"], ["c"]]
static func parse_combos(text: String) -> Array[PackedStringArray]:
	var out: Array[PackedStringArray] = []
	for combo: String in text.split(" ", false):
		out.append(combo.split("+"))
	return out


static func _outcome(case: Dictionary, result: CompletionResult) -> Dictionary:
	var got := result.text.get_slice("\n", 0) if result else ""
	var expected: String = case.expected
	return {
		"file": case.file, "line": int(case.line) + 1, "cut": case.cut, "category": case.category,
		"expected": expected, "got": got, "full": result.text if result else "",
		"source": result.source if result else "", "shown": result != null,
		"exact": result != null and got.strip_edges(false, true) == expected,
		# Correcta: lo mostrado es el comienzo de lo esperado (más corta pero sin errores).
		"correct": result != null and not got.strip_edges().is_empty() and expected.begins_with(got.strip_edges(false, true)),
		"similarity": token_similarity(got, expected) if result else 0.0,
	}


static func _metrics(outcomes: Array, latencies: PackedFloat64Array) -> Dictionary:
	var shown := 0
	var exact := 0
	var correct := 0
	var similarity := 0.0
	for outcome: Dictionary in outcomes:
		if outcome.shown:
			shown += 1
			similarity += float(outcome.similarity)
		exact += int(outcome.exact)
		correct += int(outcome.correct)
	var sorted := latencies.duplicate()
	sorted.sort()
	return {
		"cases": outcomes.size(), "shown": shown, "exact": exact, "correct": correct,
		"false_positives": shown - correct,
		"coverage": float(shown) / maxf(1.0, outcomes.size()),
		"precision": float(correct) / maxf(1.0, shown),
		"similarity": similarity / maxf(1.0, shown),
		"p50_ms": sorted[sorted.size() / 2] if not sorted.is_empty() else 0.0,
		"p95_ms": sorted[int(sorted.size() * 0.95)] if not sorted.is_empty() else 0.0,
	}


## Por fuente ganadora: {fuente: {shown, exact, correct}}.
static func _by_source(outcomes: Array) -> Dictionary:
	var out := {}
	for outcome: Dictionary in outcomes:
		if not outcome.shown:
			continue
		var entry: Dictionary = out.get_or_add(outcome.source, {"shown": 0, "exact": 0, "correct": 0})
		entry.shown = int(entry.shown) + 1
		entry.exact = int(entry.exact) + int(outcome.exact)
		entry.correct = int(entry.correct) + int(outcome.correct)
	return out


## Similitud por tokens: 2 × LCS / (tokens de a + tokens de b), sin los espacios.
static func token_similarity(a: String, b: String) -> float:
	var left := _plain_tokens(a)
	var right := _plain_tokens(b)
	if left.is_empty() and right.is_empty():
		return 1.0
	if left.is_empty() or right.is_empty():
		return 0.0
	var previous := PackedInt32Array()
	previous.resize(right.size() + 1)
	for i in left.size():
		var current := PackedInt32Array()
		current.resize(right.size() + 1)
		for j in right.size():
			current[j + 1] = previous[j] + 1 if left[i] == right[j] else maxi(previous[j + 1], current[j])
		previous = current
	return 2.0 * previous[right.size()] / (left.size() + right.size())


static func _plain_tokens(text: String) -> PackedStringArray:
	var out := PackedStringArray()
	for token: String in GdLexer.tokenize_line(text):
		out.append(token.strip_edges())
	return out


## Tabla de texto con una fila por combinación y el detalle por fuente.
static func format(report: Dictionary) -> String:
	var lines := PackedStringArray()
	lines.append("%-28s %5s %9s %8s %10s %4s %10s %7s %7s" % ["fuentes", "casos", "mostradas", "exactas", "correctas", "FP", "similitud", "p50 ms", "p95 ms"])
	for entry: Dictionary in report.combos:
		var m: Dictionary = entry.metrics
		lines.append("%-28s %5d %4d (%2.0f%%) %8d %10d %4d %10.2f %7.2f %7.2f" % [
			"+".join(entry.sources), m.cases, m.shown, float(m.coverage) * 100.0, m.exact, m.correct,
			m.false_positives, m.similarity, m.p50_ms, m.p95_ms])
		var parts := PackedStringArray()
		for source: String in entry.by_source:
			var s: Dictionary = entry.by_source[source]
			parts.append("%s %d/%d exactas, %d correctas" % [source, s.exact, s.shown, s.correct])
		if not parts.is_empty():
			lines.append("    " + "; ".join(parts))
	return "\n".join(lines)


## Detalle de una combinación: un renglón por caso.
static func format_cases(entry: Dictionary) -> String:
	var lines := PackedStringArray()
	for outcome: Dictionary in entry.outcomes:
		var mark := "=" if outcome.exact else ("~" if outcome.correct else ("✗" if outcome.shown else " "))
		lines.append("%s %s:%d «%s» → «%s» (esperado «%s»)%s" % [mark, outcome.file, outcome.line, outcome.cut, outcome.got, outcome.expected, " [%s]" % outcome.source if outcome.shown else ""])
	return "\n".join(lines)
