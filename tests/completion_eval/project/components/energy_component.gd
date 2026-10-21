class_name EnergyComponent
extends Node

signal changed(current: float, maximum: float)
signal depleted

@export var max_energy: float = 100.0
@export var regen_per_second: float = 25.0
@export var regen_delay: float = 0.8

var current_energy: float
var _regen_cooldown: float = 0.0


func _ready() -> void:
	current_energy = max_energy


func _process(delta: float) -> void:
	if _regen_cooldown > 0.0:
		_regen_cooldown -= delta
		return
	if current_energy < max_energy:
		current_energy = minf(current_energy + regen_per_second * delta, max_energy)
		changed.emit(current_energy, max_energy)


func can_spend(amount: float) -> bool:
	return current_energy >= amount


func spend(amount: float) -> bool:
	if not can_spend(amount):
		return false
	current_energy -= amount
	_regen_cooldown = regen_delay
	changed.emit(current_energy, max_energy)
	if current_energy <= 0.0:
		depleted.emit()
	return true


func refill() -> void:
	current_energy = max_energy
	changed.emit(current_energy, max_energy)


func get_ratio() -> float:
	return current_energy / max_energy
