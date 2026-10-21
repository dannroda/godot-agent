extends Node2D

@onready var player: FixturePlayer = $Player


func _ready() -> void:
	Events.score_changed.connect(_on_score_changed)
	velocity_check()


func velocity_check() -> void:
	var direction := Input.get_axis("move_left", "move_right")
	print(direction)
