extends Enemy

@export var jump_interval: float = 1.6
@export var jump_velocity: Vector2 = Vector2(90.0, -220.0)

var _jump_timer: float = 0.0

@onready var floor_ray: RayCast2D = $FloorRay
@onready var wall_ray: RayCast2D = $WallRay


func _ready() -> void:
	super()
	_jump_timer = jump_interval
	sprite.play("idle")


func _update_behavior(delta: float) -> void:
	if not is_on_floor():
		return
	velocity.x = move_toward(velocity.x, 0.0, 400.0 * delta)
	if can_see_target():
		flip_towards(1 if target.global_position.x > global_position.x else -1)
	elif wall_ray.is_colliding() or not floor_ray.is_colliding():
		flip_towards(-direction)
	_jump_timer -= delta
	if _jump_timer <= 0.0:
		_jump_timer = jump_interval
		velocity = Vector2(jump_velocity.x * direction, jump_velocity.y)
		sprite.play("jump")
		AudioService.play_sfx(&"slime_jump")
	elif sprite.animation == &"jump":
		sprite.play("idle")


func flip_towards(new_direction: int) -> void:
	super(new_direction)
	wall_ray.target_position.x = absf(wall_ray.target_position.x) * direction
	floor_ray.position.x = absf(floor_ray.position.x) * direction
