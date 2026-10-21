extends FixtureEnemy

const BulletScene := preload("res://tests/completion_fixture/actors/player.tscn")


func _ready() -> void:
	add_to_group("enemies")
	health.changed.connect(_on_health_changed)
	if Input.is_action_just_pressed("shoot"):
		get_tree().call_group("enemies", "alert")
