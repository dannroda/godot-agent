@tool
extends RefCounted
## Sugerencia elegida (spec §16.1): el texto a insertar en el caret, su puntaje y de qué fuente salió.

const SOURCE_RULE := "rule"
const SOURCE_RETRIEVAL := "retrieval"
const SOURCE_NGRAM := "ngram"
const SOURCE_HISTORY := "history"
const SOURCE_LLM := "llm"

var text: String = ""
var score: float = 0.0
var source: String = ""
## Tiempo de la consulta en el proveedor.
var latency_usec: int = 0
var seq: int = 0


static func make(p_text: String, p_score: float, p_source: String) -> RefCounted:
	var result := new()
	result.text = p_text
	result.score = p_score
	result.source = p_source
	return result
