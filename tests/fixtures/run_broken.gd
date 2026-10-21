extends Node
## Escena de prueba de run_scene: falla en _ready (el debugger del editor la pausa).


func _ready() -> void:
	print("run_broken antes del error")
	var missing: Node = get_node_or_null("NoExiste")
	missing.queue_free()
