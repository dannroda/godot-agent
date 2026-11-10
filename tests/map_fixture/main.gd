extends Node2D


func _on_player_died() -> void:
	GameState.add(0)
