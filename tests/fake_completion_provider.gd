extends "res://addons/godot_agent/completion/completion_provider.gd"
## Proveedor falso para probar el controller y la UI sin modelo (spec §16.9): respuestas por línea
## escrita (sin indentación) y latencia configurable.

## línea antes del caret (sin indentación) -> texto sugerido
var responses: Dictionary = {}
## > 0: responde después de esta cantidad de ms (con un timer del árbol).
var latency_ms: int = 0
## Fuente de los resultados (como LLM para probar el modo híbrido).
var source: String = CompletionResult.SOURCE_RULE
var calls: Array[CompletionRequest] = []
var cancelled: int = 0


func complete(request: CompletionRequest) -> CompletionResult:
	calls.append(request)
	if latency_ms > 0:
		await (Engine.get_main_loop() as SceneTree).create_timer(latency_ms / 1000.0).timeout
	var key := request.line_prefix.strip_edges(true, false)
	if not responses.has(key):
		return null
	var result := CompletionResult.make(str(responses[key]), 0.9, source)
	result.seq = request.seq
	return result


func cancel() -> void:
	cancelled += 1


func describe() -> Dictionary:
	return {"name": "fake", "remote": false, "ai": false}
