class_name HealthComponent
extends Node

signal changed(current: int, maximum: int)
signal damaged(amount: int)
signal healed(amount: int)
signal died

@export var max_health: int = 3
@export var invulnerability_time: float = 0.0

var current_health: int
var is_invulnerable: bool = false


func _ready() -> void:
	current_health = max_health


func take_damage(amount: int) -> void:
	if is_invulnerable or is_dead():
		return
	current_health = maxi(current_health - amount, 0)
	damaged.emit(amount)
	changed.emit(current_health, max_health)
	if current_health == 0:
		died.emit()
	elif invulnerability_time > 0.0:
		_start_invulnerability()


func heal(amount: int) -> void:
	if is_dead():
		return
	var previous := current_health
	current_health = mini(current_health + amount, max_health)
	if current_health != previous:
		healed.emit(current_health - previous)
		changed.emit(current_health, max_health)


func set_max_health(value: int, refill: bool = true) -> void:
	max_health = maxi(value, 1)
	if refill:
		current_health = max_health
	else:
		current_health = mini(current_health, max_health)
	changed.emit(current_health, max_health)


func is_dead() -> bool:
	return current_health <= 0


func get_ratio() -> float:
	return float(current_health) / float(max_health)


func _start_invulnerability() -> void:
	is_invulnerable = true
	await get_tree().create_timer(invulnerability_time).timeout
	is_invulnerable = false
