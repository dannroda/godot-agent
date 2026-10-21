extends AnimatableBody2D

@export var travel: Vector2 = Vector2(0.0, -64.0)
@export var duration: float = 2.0
@export var pause_time: float = 0.5

var _start_position: Vector2


func _ready() -> void:
	_start_position = position
	var tween := create_tween().set_loops()
	tween.set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	tween.tween_property(self, "position", _start_position + travel, duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_interval(pause_time)
	tween.tween_property(self, "position", _start_position, duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_interval(pause_time)
