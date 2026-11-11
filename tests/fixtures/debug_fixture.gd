extends Node2D
## m11-56: escena para game_breakpoint, game_stack y game_debug. Cada frame `_process` llama a
## `_tick`, que llama a `_add`; el check pone un breakpoint en `_add` (las líneas que usa están
## anotadas: si se mueven, actualizar debug_check.gd).

var score: int = 0
var label_text: String = "debug fixture"
var history: Array = [1, 2, 3]


func _process(_delta: float) -> void:
	_tick(Engine.get_process_frames())


func _tick(frame: int) -> void:
	var doubled := frame * 2
	score = _add(score, doubled)


func _add(a: int, b: int) -> int:
	var total := a + b  # línea 21: BREAK_LINE
	return total  # línea 22: después de un next


## Un breakpoint que llega con el run ya andando, cuando run_scene ya muestrea sus monitores.
func _physics_process(_delta: float) -> void:
	if Engine.get_physics_frames() == 150:
		score += 0  # línea 28: LATE_LINE, unos 2,5 s después de arrancar
