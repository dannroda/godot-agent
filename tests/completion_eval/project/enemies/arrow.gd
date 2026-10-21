class_name Arrow
extends Hitbox

@export var lifetime: float = 3.0

var velocity: Vector2 = Vector2.ZERO


func _ready() -> void:
	rotation = velocity.angle()
	body_entered.connect(_on_body_entered)
	area_entered.connect(_on_area_entered)
	get_tree().create_timer(lifetime).timeout.connect(queue_free)


func _physics_process(delta: float) -> void:
	position += velocity * delta


func _on_body_entered(_body: Node2D) -> void:
	queue_free()


func _on_area_entered(area: Area2D) -> void:
	if area is Hurtbox:
		queue_free.call_deferred()
