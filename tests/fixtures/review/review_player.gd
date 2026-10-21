extends CharacterBody2D
## Jugador de la revisión de prueba (M5).

@export var speed: float = 220.0

var _facing: Vector2 = Vector2.RIGHT


func _physics_process(_delta: float) -> void:
	var direction := Input.get_vector(&"ui_left", &"ui_right", &"ui_up", &"ui_down")
	if direction != Vector2.ZERO:
		_facing = direction
	position += direction * speed
