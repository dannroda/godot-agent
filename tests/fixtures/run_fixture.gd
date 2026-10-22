extends Node2D
## Escena de prueba de run_scene y de las tools game_*: imprime al arrancar y con los inputs,
## pinta todo de rojo y tiene estado para leer, cambiar y esperar.

signal scored(total: int)

var score: int = 0
var speed: float = 1.5
var target := Vector2(3, 4)


func _ready() -> void:
	print("run_fixture listo")


func add_score(points: int) -> int:
	score += points
	scored.emit(score)
	return score


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_accept"):
		print("ui_accept recibido")
	elif event.is_action_released("ui_accept"):
		print("ui_accept soltado")
	elif event is InputEventKey and event.pressed and event.physical_keycode == KEY_S and event.ctrl_pressed:
		print("ctrl+s recibido")
	elif event is InputEventMouseButton and event.pressed:
		print("click %d en %s" % [event.button_index, event.position])
