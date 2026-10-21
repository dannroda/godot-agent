extends Enemy

@export var hover_amplitude: float = 12.0
@export var hover_frequency: float = 2.0
@export var chase_speed: float = 90.0

var is_awake: bool = false

var _time: float = 0.0
var _home_position: Vector2

@onready var wake_area: Area2D = $WakeArea


func _ready() -> void:
	super()
	_home_position = global_position
	sprite.play("sleep")
	wake_area.body_entered.connect(_on_wake_area_body_entered)
	wake_area.body_exited.connect(_on_wake_area_body_exited)


func _physics_process(delta: float) -> void:
	if health.is_dead():
		return
	_time += delta
	if is_awake and can_see_target():
		velocity = velocity.move_toward(direction_to_target() * chase_speed, 200.0 * delta)
	else:
		var hover_target := _home_position + Vector2(0.0, sin(_time * hover_frequency) * hover_amplitude)
		velocity = (hover_target - global_position) * 2.0
	if absf(velocity.x) > 1.0:
		flip_towards(1 if velocity.x > 0.0 else -1)
	move_and_slide()


func _on_wake_area_body_entered(body: Node2D) -> void:
	if not body.is_in_group("player"):
		return
	is_awake = true
	target = body
	sprite.play("fly")
	AudioService.play_sfx(&"bat_screech")


func _on_wake_area_body_exited(body: Node2D) -> void:
	if body == target:
		is_awake = false
		sprite.play("sleep")
