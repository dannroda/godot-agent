class_name Hitbox
extends Area2D

@export var damage: int = 1
@export var knockback_force: float = 250.0


func get_knockback_from(target_position: Vector2) -> Vector2:
	return global_position.direction_to(target_position) * knockback_force
