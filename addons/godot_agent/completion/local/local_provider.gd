@tool
extends "../completion_provider.gd"
## Proveedor local sin IA (spec §16.2): reglas de contexto, recuperación de líneas del proyecto e
## historial de la sesión, unidos por el Ranker. Resuelve en el mismo frame; nada de esto sale del
## editor. Presupuesto: menos de 5 ms por consulta en el hilo principal.

const ProjectContext := preload("../project_context.gd")
const ContextRules := preload("context_rules.gd")
const LineIndex := preload("line_index.gd")
const TypedHistory := preload("typed_history.gd")
const Ranker := preload("ranker.gd")
const PostProcessor := preload("../post_processor.gd")

const SOURCE_RULES := CompletionResult.SOURCE_RULE
const SOURCE_RETRIEVAL := CompletionResult.SOURCE_RETRIEVAL
const SOURCE_HISTORY := CompletionResult.SOURCE_HISTORY
## Mínimo de caracteres escritos (sin indentación) para recuperación e historial.
const MIN_PREFIX := 3
## Más líneas que esto con el mismo comienzo = prefijo ambiguo.
const MAX_SCAN := 400
## Cuánta evidencia hace falta: con raw = 1 (una línea, otro archivo) el soporte es ~0.49.
const SUPPORT_SCALE := 1.5

var context: ProjectContext
var rules: ContextRules = ContextRules.new()
var history: TypedHistory = TypedHistory.new()
var threshold: float = Ranker.DEFAULT_THRESHOLD
var margin: float = Ranker.DEFAULT_MARGIN
## Fuentes activas (spec §16.10).
var sources: Dictionary = {SOURCE_RULES: true, SOURCE_RETRIEVAL: true, SOURCE_HISTORY: true}


func _init(p_context: ProjectContext = null) -> void:
	context = p_context if p_context else ProjectContext.new()


func describe() -> Dictionary:
	return {"name": "local", "remote": false, "ai": false}


func complete(request: CompletionRequest) -> CompletionResult:
	var started := Time.get_ticks_usec()
	var chosen := Ranker.pick(gather(request), threshold, margin)
	if chosen.is_empty():
		return null
	var result := CompletionResult.make(str(chosen.text), float(chosen.score), str(chosen.source))
	result.latency_usec = Time.get_ticks_usec() - started
	result.seq = request.seq
	return result


## Todos los candidatos ya post-procesados (para el ranker, los tests y la evaluación).
func gather(request: CompletionRequest) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var raw: Array[Dictionary] = []
	if sources.get(SOURCE_RULES, true):
		raw.append_array(rules.candidates(request, context))
	var has_rule := not raw.is_empty()
	var prefix := LineIndex.normalize(request.line_prefix)
	if not has_rule and prefix.length() >= MIN_PREFIX:
		if sources.get(SOURCE_RETRIEVAL, true):
			raw.append_array(retrieval(prefix, request.path))
		if sources.get(SOURCE_HISTORY, true):
			raw.append_array(history.query(prefix))
	for candidate: Dictionary in raw:
		var text := PostProcessor.process(str(candidate.text), request.line_prefix, request.line_suffix, request.next_line)
		if not text.is_empty():
			candidate.text = text
			out.append(candidate)
	return out


## Candidatos de LineRetrieval con puntaje normalizado: su parte del total × soporte (la evidencia
## absoluta: pocas apariciones lejanas no alcanzan aunque sean la única opción).
func retrieval(prefix: String, path: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var found := context.lines().query(prefix, path, MAX_SCAN)
	var total := 0.0
	for entry: Dictionary in found:
		total += float(entry.raw)
	if total <= 0.0:
		return out
	for entry: Dictionary in found:
		var raw := float(entry.raw)
		var support := 1.0 - exp(-raw / SUPPORT_SCALE)
		out.append({"text": entry.rest, "score": raw / total * support, "source": SOURCE_RETRIEVAL})
	return out
