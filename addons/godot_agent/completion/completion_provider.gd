@tool
extends RefCounted
## Interfaz de los proveedores de sugerencias (spec §16.1). El local resuelve en el mismo frame;
## uno remoto puede hacer `await` y debe respetar `cancel()`.

const CompletionRequest := preload("completion_request.gd")
const CompletionResult := preload("completion_result.gd")


## La mejor sugerencia para el pedido, o null si no hay ninguna lo bastante segura.
func complete(_request: CompletionRequest) -> CompletionResult:
	return null


func cancel() -> void:
	pass


## {name, remote: bool, ai: bool}
func describe() -> Dictionary:
	return {"name": "", "remote": false, "ai": false}
