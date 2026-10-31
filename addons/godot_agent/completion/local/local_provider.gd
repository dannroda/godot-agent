@tool
extends "../completion_provider.gd"
## Proveedor local sin IA (spec §16.2): reglas de contexto, recuperación de líneas del proyecto,
## n-gram e historial de la sesión, unidos por el Ranker. Resuelve en el mismo frame; nada de esto
## sale del editor. Presupuesto: menos de 5 ms por consulta en el hilo principal.
## - Con algo escrito en la línea: las líneas del proyecto que empiezan igual (o, si no hay
##   ninguna, las que difieren en un identificador, adaptadas), el historial y el n-gram.
## - En una línea vacía: la línea que sigue a la de arriba en el proyecto, y el n-gram.
## - La recuperación que gana se extiende a un bloque corto si el corpus sigue coincidiendo.

const ProjectContext := preload("../project_context.gd")
const ContextRules := preload("context_rules.gd")
const LineIndex := preload("line_index.gd")
const NGramModel := preload("ngram_model.gd")
const GdLexer := preload("gd_lexer.gd")
const TypedHistory := preload("typed_history.gd")
const Ranker := preload("ranker.gd")
const PostProcessor := preload("../post_processor.gd")

const SOURCE_RULES := CompletionResult.SOURCE_RULE
const SOURCE_RETRIEVAL := CompletionResult.SOURCE_RETRIEVAL
const SOURCE_NGRAM := CompletionResult.SOURCE_NGRAM
const SOURCE_HISTORY := CompletionResult.SOURCE_HISTORY
## Mínimo de caracteres escritos (sin indentación) para recuperación, historial y n-gram.
const MIN_PREFIX := 3
## Más líneas que esto con el mismo comienzo = prefijo ambiguo.
const MAX_SCAN := 400
## Cuánta evidencia hace falta: con raw = 1 (una línea en otra carpeta) el soporte es ~0.63. Con
## 1.5 una sola aparición lejana no llegaba al umbral; el set de evaluación mostró que esas líneas
## casi siempre aciertan (D27).
const SUPPORT_SCALE := 1.0
## Una línea adaptada (un identificador cambiado) vale un poco menos que una que coincide tal cual.
const ADAPT_WEIGHT := 0.9
const NEXT_LINE_WEIGHT := 1.0
const NGRAM_WEIGHT := 1.0
## Más caracteres que esto en la línea (con su indentación) = ninguna línea del índice coincide.
const LONG_LINE := LineIndex.MAX_LINE * 2
## Un bloque se extiende solo si al menos tantas apariciones siguen igual.
const MIN_BLOCK_SUPPORT := 2

static var _WORD: RegEx = RegEx.create_from_string("[A-Za-z0-9_\"']")

var context: ProjectContext
var rules: ContextRules = ContextRules.new()
var history: TypedHistory = TypedHistory.new()
var threshold: float = Ranker.DEFAULT_THRESHOLD
var margin: float = Ranker.DEFAULT_MARGIN
## Máximo de líneas por sugerencia (1 = sin bloques).
var max_lines: int = PostProcessor.DEFAULT_MAX_LINES
## Ajustes de las fuentes (los defaults salen del set de evaluación, D27).
var support_scale: float = SUPPORT_SCALE
var ngram_step_min: float = NGramModel.STEP_MIN
var ngram_cumulative_min: float = NGramModel.CUMULATIVE_MIN
var ngram_min_support: int = NGramModel.MIN_SUPPORT
## Fuentes activas (spec §16.10).
var sources: Dictionary = {SOURCE_RULES: true, SOURCE_RETRIEVAL: true, SOURCE_NGRAM: true, SOURCE_HISTORY: true}


func _init(p_context: ProjectContext = null) -> void:
	context = p_context if p_context else ProjectContext.new()


func describe() -> Dictionary:
	return {"name": "local", "remote": false, "ai": false}


func cache_generation() -> int:
	return context.generation * 100003 + history.revision


func complete(request: CompletionRequest) -> CompletionResult:
	var started := Time.get_ticks_usec()
	var chosen := Ranker.pick(gather(request), threshold, margin)
	if chosen.is_empty():
		return null
	var text := str(chosen.text)
	if chosen.has("positions") and max_lines > 1:
		text = _with_block(text, chosen, request)
	var result := CompletionResult.make(text, float(chosen.score), str(chosen.source))
	result.latency_usec = Time.get_ticks_usec() - started
	result.seq = request.seq
	return result


## Todos los candidatos de una línea, ya post-procesados (para el ranker, los tests y la evaluación).
func gather(request: CompletionRequest) -> Array[Dictionary]:
	var raw: Array[Dictionary] = []
	# En C# (m14-08) solo cuentan las líneas de los .cs y lo tecleado: las reglas de contexto y el
	# n-gram están hechos para GDScript.
	var csharp := request.path.get_extension() == "cs"
	if _on(SOURCE_RULES) and not csharp:
		raw.append_array(rules.candidates(request, context))
		# La regla reconoce el contexto pero no puede elegir: nadie adivina.
		if ContextRules.is_veto(raw):
			return []
	# Ninguna línea del índice pasa de MAX_LINE: con una más larga no hay nada que buscar, y
	# normalizarla costaría más que el presupuesto por tecla.
	if raw.is_empty() and request.line_prefix.length() <= LONG_LINE:
		var prefix := LineIndex.normalize(request.line_prefix)
		if prefix.is_empty():
			if not request.previous_lines.is_empty() and not request.previous_lines[request.previous_lines.size() - 1].strip_edges().is_empty():
				if _on(SOURCE_RETRIEVAL):
					raw.append_array(next_line(request))
				if _on(SOURCE_NGRAM) and not csharp:
					raw.append_array(ngram(request))
		elif prefix.length() >= MIN_PREFIX:
			if _on(SOURCE_RETRIEVAL):
				raw.append_array(retrieval(prefix, request))
			if _on(SOURCE_HISTORY):
				raw.append_array(history.query(prefix))
			if _on(SOURCE_NGRAM) and not csharp:
				raw.append_array(ngram(request))
	var out: Array[Dictionary] = []
	for candidate: Dictionary in raw:
		var text := PostProcessor.process(str(candidate.text), request, 1)
		if not text.is_empty():
			candidate.text = text
			out.append(candidate)
	return out


func _on(source: String) -> bool:
	return sources.get(source, true)


## LineRetrieval: el resto de las líneas que empiezan con `prefix` (normalizado). Si no hay ninguna,
## las que difieren en un identificador ya escrito, con la misma sustitución en el resto. El puntaje
## es su parte del total × soporte (la evidencia absoluta: pocas apariciones lejanas no alcanzan
## aunque sean la única opción).
func retrieval(prefix: String, request: CompletionRequest) -> Array[Dictionary]:
	var lines := context.lines_for(request.path)
	# Se adapta solo si ninguna línea empieza así: una línea ya completa o un prefijo ambiguo
	# (más de MAX_SCAN) no se reemplazan con la de un pariente.
	var adapted := not lines.has_prefix(prefix)
	var found := lines.adapt(prefix, request.path, MAX_SCAN) if adapted else lines.query(prefix, request.path, MAX_SCAN)
	var level := GdLexer.indent_level(request.line_prefix, request.indent_size)
	var out := _scored(found, ADAPT_WEIGHT if adapted else 1.0)
	for i in out.size():
		out[i].text = found[i].rest
		# Una línea adaptada no se extiende: el bloque traería el identificador viejo.
		if not adapted:
			out[i].positions = found[i].positions
			out[i].level = level
	return out


## Predicción de la línea siguiente: en una línea vacía, lo que sigue en el proyecto a la línea de
## arriba, con su sangría relativa.
func next_line(request: CompletionRequest) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var above := request.previous_lines[request.previous_lines.size() - 1]
	if above.length() > LONG_LINE:
		return out
	var previous := LineIndex.normalize(above).strip_edges(false, true)
	if previous.length() < LineIndex.MIN_LINE:
		return out
	var found := context.lines_for(request.path).next_lines(previous, request.path, MAX_SCAN)
	var scored := _scored(found, NEXT_LINE_WEIGHT)
	var previous_level := GdLexer.indent_level(above, request.indent_size)
	var current_level := GdLexer.indent_level(request.line_prefix, request.indent_size)
	for i in found.size():
		var level := previous_level + int(found[i].delta)
		# Una sangría menor que la ya escrita no se puede sugerir (habría que borrar).
		if level < current_level:
			continue
		var candidate := scored[i]
		candidate.text = request.indent_unit().repeat(level - current_level) + str(found[i].text)
		candidate.positions = found[i].positions
		candidate.level = level
		out.append(candidate)
	return out


func _scored(found: Array[Dictionary], weight: float) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var total := 0.0
	for entry: Dictionary in found:
		total += float(entry.raw)
	for entry: Dictionary in found:
		var raw := float(entry.raw)
		# La recencia reparte entre candidatos; cuánta evidencia hay no depende de la edad de los
		# archivos: si no, una línea que aparece una vez dejaba de sugerirse a la semana (m16-07).
		var support := 1.0 - exp(-float(entry.get("evidence", raw)) / support_scale)
		out.append({"text": "", "score": raw / total * support * weight if total > 0.0 else 0.0, "source": SOURCE_RETRIEVAL})
	return out


## NGramModel: el resto de la línea generado token a token desde el contexto del caret.
func ngram(request: CompletionRequest) -> Array[Dictionary]:
	var model := context.ngram()
	if model.token_count == 0:
		return []
	var input := NGramModel.context_for(request.previous_lines, request.line_prefix, request.indent_size)
	var generated := model.generate(input.context, input.partial, input.after_space, ngram_step_min, ngram_cumulative_min, ngram_min_support)
	# Solo signos (`%`, `(`) no ayudan: hace falta al menos un nombre, número o string.
	if generated.is_empty() or _WORD.search(str(generated.text)) == null:
		return []
	return [{"text": generated.text, "score": float(generated.score) * NGRAM_WEIGHT, "source": SOURCE_NGRAM}]


## La línea elegida más las que la siguen en el corpus mientras todas sus apariciones coinciden.
func _with_block(text: String, chosen: Dictionary, request: CompletionRequest) -> String:
	var more := context.lines_for(request.path).extend(chosen.positions, max_lines - 1, MIN_BLOCK_SUPPORT)
	if more.is_empty():
		return text
	var block := text
	for line: Dictionary in more:
		block += "\n" + request.indent_unit().repeat(int(chosen.level) + int(line.delta)) + str(line.text)
	var processed := PostProcessor.process(block, request, max_lines)
	return processed if not processed.is_empty() else text
