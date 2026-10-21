extends Area2D

@export var heal_on_activate: bool = true

var is_active: bool = false

@onready var flag: AnimatedSprite2D = $Flag
@onready var particles: GPUParticles2D = $Particles


func _ready() -> void:
	add_to_group("checkpoints")
	body_entered.connect(_on_body_entered)
	flag.play("down")
	if GameState.has_checkpoint and GameState.last_checkpoint.is_equal_approx(global_position):
		is_active = true
		flag.play("up")


func activate() -> void:
	if is_active:
		return
	is_active = true
	get_tree().call_group("checkpoints", "deactivate_unless", self)
	flag.play("raise")
	particles.restart()
	AudioService.play_sfx(&"checkpoint")
	EventBus.checkpoint_reached.emit(global_position)


func deactivate_unless(active_checkpoint: Node) -> void:
	if active_checkpoint != self and is_active:
		is_active = false
		flag.play("down")


func _on_body_entered(body: Node2D) -> void:
	if not body.is_in_group("player"):
		return
	activate()
	if heal_on_activate:
		var health: HealthComponent = body.get_node("HealthComponent")
		health.heal(health.max_health)
