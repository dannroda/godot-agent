extends Node2D

enum Mode { IDLE, CHASE }


func chase(target: Player) -> void:
	pass


static func spawn_count() -> int:
	return get_tree().get_nodes_in_group("players").size()
