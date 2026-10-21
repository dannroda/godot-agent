extends Pickup

@export var value: int = 1
@export var magnet_speed: float = 220.0

var _magnet_target: Node2D

@onready var magnet_area: Area2D = $MagnetArea


func _ready() -> void:
	super()
	if GameState.has_upgrade(&"magnet"):
		magnet_area.body_entered.connect(_on_magnet_area_body_entered)
	else:
		magnet_area.monitoring = false


func _physics_process(delta: float) -> void:
	if _magnet_target and not _collected:
		global_position = global_position.move_toward(_magnet_target.global_position, magnet_speed * delta)


func _apply(_body: Node2D) -> void:
	EventBus.coin_collected.emit(value)


func _on_magnet_area_body_entered(body: Node2D) -> void:
	if body.is_in_group("player"):
		_magnet_target = body
