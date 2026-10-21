extends Area2D

@export var requires_all_enemies: bool = false
@export var open_shop: bool = true

var _triggered: bool = false

@onready var door_sprite: AnimatedSprite2D = $DoorSprite
@onready var label: Label = $Label


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	EventBus.enemy_killed.connect(_on_enemy_killed)
	_update_lock()


func is_locked() -> bool:
	return requires_all_enemies and get_tree().get_nodes_in_group("enemies").size() > 0


func _update_lock() -> void:
	if is_locked():
		door_sprite.play("locked")
		label.text = "Defeat all enemies"
	else:
		door_sprite.play("open")
		label.text = ""


func _on_enemy_killed(_enemy: Node2D, _score: int) -> void:
	_update_lock()


func _on_body_entered(body: Node2D) -> void:
	if _triggered or is_locked() or not body.is_in_group("player"):
		return
	_triggered = true
	var level := owner as Level
	var was_last_level := GameState.is_last_level()
	EventBus.level_completed.emit(level.level_id if level else "")
	AudioService.play_sfx(&"level_complete")
	SaveService.save_game()
	if was_last_level:
		SceneRouter.go_to_main_menu()
	elif open_shop:
		SceneRouter.go_to_shop()
	else:
		SceneRouter.start_level(GameState.current_level)
