extends Enemy

@export var charge_speed: float = 150.0
@export var charge_duration: float = 1.2

var is_charging: bool = false

@onready var sensors: Node2D = $Sensors
@onready var floor_ray: RayCast2D = $Sensors/FloorRay
@onready var wall_ray: RayCast2D = $Sensors/WallRay
@onready var charge_cooldown: Timer = $ChargeCooldown


func _ready() -> void:
	super()
	sprite.play("walk")


func _update_behavior(delta: float) -> void:
	if wall_ray.is_colliding() or not floor_ray.is_colliding():
		flip_towards(-direction)
		is_charging = false
	if not is_charging and can_see_target() and charge_cooldown.is_stopped():
		var to_target := direction_to_target()
		if absf(to_target.y) < 0.4:
			_start_charge(1 if to_target.x > 0.0 else -1)
	var current_speed := charge_speed if is_charging else speed
	velocity.x = move_toward(velocity.x, direction * current_speed, 600.0 * delta)


func flip_towards(new_direction: int) -> void:
	super(new_direction)
	sensors.scale.x = direction


func _start_charge(charge_direction: int) -> void:
	flip_towards(charge_direction)
	is_charging = true
	sprite.play("charge")
	AudioService.play_sfx(&"beetle_charge")
	await get_tree().create_timer(charge_duration).timeout
	is_charging = false
	sprite.play("walk")
	charge_cooldown.start()
