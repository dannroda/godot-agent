extends Node
## Autoload de playtest: corre dentro del juego lanzado por el harness.
## Aislado a propósito: sin preload, sin class_name y sin referencias a scripts @tool del addon,
## para que cargarlo no arrastre código de editor (spec §6, punto 5).
## M0: solo el guard. Captura de frames e inputs simulados llegan en M4.


func _ready() -> void:
	if not OS.has_feature("editor_runtime") or not EngineDebugger.is_active():
		queue_free()
		return
