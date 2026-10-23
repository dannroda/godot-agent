extends Polygon2D
## Ship of the docs demo (tests/docs_demo): the screenshots of the guide show it.

@export var speed: float = 260.0
@export var turn_speed: float = 3.5

var velocity := Vector2.ZERO


func _physics_process(delta: float) -> void:
	rotation += Input.get_axis(&"ui_left", &"ui_right") * turn_speed * delta
	if Input.is_action_pressed(&"ui_up"):
		velocity = Vector2.UP.rotated(rotation) * speed
	position += velocity
	position = Vector2(fposmod(position.x, 1152.0), fposmod(position.y, 648.0))
