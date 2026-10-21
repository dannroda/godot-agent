extends Pickup

@export var heal_amount: int = 1


func _can_collect(body: Node2D) -> bool:
	var health: HealthComponent = body.get_node_or_null("HealthComponent")
	return health != null and health.current_health < health.max_health


func _apply(body: Node2D) -> void:
	var health: HealthComponent = body.get_node("HealthComponent")
	health.heal(heal_amount)
