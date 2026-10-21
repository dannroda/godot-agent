class_name Hurtbox
extends Area2D

signal hit_received(hitbox: Hitbox)

@export var health: HealthComponent


func _ready() -> void:
	area_entered.connect(_on_area_entered)


func _on_area_entered(area: Area2D) -> void:
	if not area is Hitbox:
		return
	var hitbox := area as Hitbox
	if hitbox.owner == owner:
		return
	if health:
		health.take_damage(hitbox.damage)
	hit_received.emit(hitbox)
