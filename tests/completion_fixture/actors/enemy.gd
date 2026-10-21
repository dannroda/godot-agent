class_name FixtureEnemy
extends Area2D

@export var health: FixtureHealth


func _ready() -> void:
	add_to_group("enemies")
	health.changed.connect(_on_health_changed)
	body_entered.connect(_on_body_entered)


func _process(delta: float) -> void:
	position.x += 10.0 * delta


func _on_health_changed(current: int, maximum: int) -> void:
	modulate.a = float(current) / maximum
