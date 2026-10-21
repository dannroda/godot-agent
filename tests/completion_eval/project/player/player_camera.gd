class_name PlayerCamera
extends Camera2D

@export var decay: float = 8.0
@export var max_offset: Vector2 = Vector2(24.0, 16.0)

var _shake_strength: float = 0.0
var _shake_time: float = 0.0


func _ready() -> void:
	EventBus.screen_shake_requested.connect(shake)


func _process(delta: float) -> void:
	if _shake_time <= 0.0:
		_shake_strength = 0.0
		offset = offset.lerp(Vector2.ZERO, decay * delta)
		return
	_shake_time -= delta
	offset = Vector2(
		randf_range(-1.0, 1.0) * minf(_shake_strength, max_offset.x),
		randf_range(-1.0, 1.0) * minf(_shake_strength, max_offset.y)
	)


func shake(strength: float, duration: float) -> void:
	if not UserSettings.screen_shake:
		return
	_shake_strength = maxf(_shake_strength, strength)
	_shake_time = maxf(_shake_time, duration)


func set_limits(rect: Rect2) -> void:
	limit_left = int(rect.position.x)
	limit_top = int(rect.position.y)
	limit_right = int(rect.end.x)
	limit_bottom = int(rect.end.y)
	reset_smoothing()
