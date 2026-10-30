extends CharacterBody3D
## Jugador del juego de prueba: se mueve, salta y mira con el mouse sin capturarlo.

const SPEED := 5.0
const JUMP_VELOCITY := 4.5
const SENSITIVITY := 0.1

@onready var _camera: Camera3D = $Camera3D


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity += get_gravity() * delta
	elif Input.is_action_just_pressed("ui_accept"):
		velocity.y = JUMP_VELOCITY
	var direction := Input.get_axis("ui_left", "ui_right")
	velocity.x = direction * SPEED
	move_and_slide()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		rotate_y(deg_to_rad(-event.relative.x * SENSITIVITY))
		_camera.rotate_x(deg_to_rad(-event.relative.y * SENSITIVITY))
		_camera.rotation.x = clampf(_camera.rotation.x, deg_to_rad(-80.0), deg_to_rad(80.0))
