extends Enemy

const ARROW_SCENE: PackedScene = preload("res://tests/completion_eval/project/enemies/arrow.tscn")

@export var fire_rate: float = 1.5
@export var arrow_speed: float = 260.0

@onready var shoot_timer: Timer = $ShootTimer
@onready var muzzle: Marker2D = $Muzzle


func _ready() -> void:
	super()
	shoot_timer.wait_time = fire_rate
	shoot_timer.timeout.connect(_on_shoot_timer_timeout)
	sprite.play("idle")


func _update_behavior(delta: float) -> void:
	velocity.x = move_toward(velocity.x, 0.0, 500.0 * delta)
	if can_see_target():
		flip_towards(1 if target.global_position.x > global_position.x else -1)
		if shoot_timer.is_stopped():
			shoot_timer.start()
	else:
		shoot_timer.stop()


func flip_towards(new_direction: int) -> void:
	super(new_direction)
	muzzle.position.x = absf(muzzle.position.x) * direction


func _on_shoot_timer_timeout() -> void:
	if not can_see_target():
		return
	sprite.play("shoot")
	var arrow: Arrow = ARROW_SCENE.instantiate()
	arrow.global_position = muzzle.global_position
	arrow.velocity = direction_to_target() * arrow_speed
	get_tree().current_scene.add_child(arrow)
	AudioService.play_sfx(&"bow")
	await sprite.animation_finished
	sprite.play("idle")
