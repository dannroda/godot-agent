extends Node

signal score_changed(value: int)

var score := 0


func add(points: int) -> void:
	score += points
	score_changed.emit(score)
