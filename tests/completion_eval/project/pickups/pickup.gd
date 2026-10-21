class_name Pickup
extends Area2D

signal collected

@export var bob_height: float = 4.0
@export var bob_speed: float = 3.0
@export var pickup_sound: StringName = &"coin"

var _collected: bool = false
var _base_y: float
var _time: float = 0.0

@onready var sprite: Sprite2D = $Sprite2D


func _ready() -> void:
	add_to_group("pickups")
	_base_y = sprite.position.y
	_time = randf() * TAU
	body_entered.connect(_on_body_entered)


func _process(delta: float) -> void:
	if _collected:
		return
	_time += delta * bob_speed
	sprite.position.y = _base_y + sin(_time) * bob_height


func _on_body_entered(body: Node2D) -> void:
	if _collected or not body.is_in_group("player"):
		return
	if not _can_collect(body):
		return
	_collected = true
	_apply(body)
	AudioService.play_sfx(pickup_sound)
	collected.emit()
	_play_collect_animation()


func _can_collect(_body: Node2D) -> bool:
	return true


func _apply(_body: Node2D) -> void:
	pass


func _play_collect_animation() -> void:
	set_deferred("monitoring", false)
	var tween := create_tween().set_parallel()
	tween.tween_property(sprite, "position:y", sprite.position.y - 16.0, 0.25).set_ease(Tween.EASE_OUT)
	tween.tween_property(sprite, "modulate:a", 0.0, 0.25)
	tween.chain().tween_callback(queue_free)
