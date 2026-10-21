class_name FixtureHealth
extends Node

signal changed(current: int, maximum: int)
signal depleted
signal healed(
	amount: int
)

@export var maximum: int = 10
var current: int = 10


func damage(amount: int) -> void:
	current = maxi(0, current - amount)
	changed.emit(current, maximum)
	if current == 0:
		depleted.emit()
