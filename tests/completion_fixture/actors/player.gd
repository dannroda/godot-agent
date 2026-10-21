class_name FixturePlayer
extends CharacterBody2D

signal hit(damage: int)

const SPEED := 220.0
const FRICTION := 900.0

@onready var sprite_2d: Sprite2D = $Sprite2D


func _ready() -> void:
	add_to_group("players")
	$CooldownTimer.timeout.connect(_on_cooldown_timer_timeout)


func _physics_process(delta: float) -> void:
	var direction := Input.get_axis("move_left", "move_right")
	velocity.x = direction * SPEED
	velocity = velocity.move_toward(Vector2.ZERO, FRICTION * delta)
	move_and_slide()


func _on_cooldown_timer_timeout() -> void:
	pass
