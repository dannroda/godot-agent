class_name Enemy
extends CharacterBody2D

signal defeated(enemy: Enemy)

const COIN_SCENE: PackedScene = preload("res://tests/completion_eval/project/pickups/coin.tscn")

@export var speed: float = 60.0
@export var contact_damage: int = 1
@export var score_value: int = 10
@export var coin_drop: int = 1
@export var detection_range: float = 160.0

var gravity: float = ProjectSettings.get_setting("physics/2d/default_gravity")
var direction: int = -1
var target: Node2D

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var collision_shape: CollisionShape2D = $CollisionShape2D
@onready var health: HealthComponent = $HealthComponent
@onready var hurtbox: Hurtbox = $Hurtbox
@onready var contact_hitbox: Hitbox = $Hitbox


func _ready() -> void:
	add_to_group("enemies")
	contact_hitbox.damage = contact_damage
	health.died.connect(_on_health_died)
	health.damaged.connect(_on_health_damaged)
	hurtbox.hit_received.connect(_on_hurtbox_hit_received)
	target = get_tree().get_first_node_in_group("player") as Node2D


func _physics_process(delta: float) -> void:
	if health.is_dead():
		return
	if not is_on_floor():
		velocity.y += gravity * delta
	_update_behavior(delta)
	move_and_slide()


func _update_behavior(_delta: float) -> void:
	pass


func can_see_target() -> bool:
	if not is_instance_valid(target):
		return false
	return global_position.distance_to(target.global_position) <= detection_range


func direction_to_target() -> Vector2:
	if not is_instance_valid(target):
		return Vector2.ZERO
	return global_position.direction_to(target.global_position)


func flip_towards(new_direction: int) -> void:
	direction = new_direction
	sprite.flip_h = direction > 0


func _on_hurtbox_hit_received(hitbox: Hitbox) -> void:
	velocity = hitbox.get_knockback_from(global_position)
	velocity.y = minf(velocity.y, -80.0)
	EventBus.screen_shake_requested.emit(2.0, 0.1)


func _on_health_damaged(_amount: int) -> void:
	AudioService.play_sfx(&"enemy_hit")
	var tween := create_tween()
	tween.tween_property(sprite, "modulate", Color(1.0, 0.3, 0.3), 0.05)
	tween.tween_property(sprite, "modulate", Color.WHITE, 0.15)


func _on_health_died() -> void:
	set_physics_process(false)
	remove_from_group("enemies")
	collision_shape.set_deferred("disabled", true)
	hurtbox.set_deferred("monitoring", false)
	contact_hitbox.set_deferred("monitorable", false)
	EventBus.enemy_killed.emit(self, score_value)
	defeated.emit(self)
	_drop_coins()
	sprite.play("death")
	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 0.0, 0.4)
	tween.tween_callback(queue_free)


func _drop_coins() -> void:
	for i in coin_drop:
		var coin: Node2D = COIN_SCENE.instantiate()
		coin.position = position + Vector2(randf_range(-12.0, 12.0), -8.0)
		get_parent().add_child.call_deferred(coin)
