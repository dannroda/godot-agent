class_name Level
extends Node2D

@export var level_id: String = "level_01"
@export var music: AudioStream
@export var respawn_delay: float = 1.5

var elapsed_time: float = 0.0
var is_finished: bool = false

@onready var tile_map: TileMapLayer = $TileMapLayer
@onready var player: Player = $Player
@onready var enemies: Node2D = $Enemies
@onready var pickups: Node2D = $Pickups
@onready var level_exit: Area2D = $LevelExit


func _ready() -> void:
	player.died.connect(_on_player_died)
	EventBus.level_completed.connect(_on_level_completed)
	_configure_camera()
	if music:
		AudioService.play_music(music)


func _process(delta: float) -> void:
	if not is_finished:
		elapsed_time += delta


func get_enemy_count() -> int:
	return get_tree().get_nodes_in_group("enemies").size()


func get_coin_count() -> int:
	return pickups.get_child_count()


func _configure_camera() -> void:
	var used := tile_map.get_used_rect()
	var cell_size := tile_map.tile_set.tile_size
	var rect := Rect2(Vector2(used.position * cell_size), Vector2(used.size * cell_size))
	player.camera.set_limits(rect)


func _on_player_died() -> void:
	GameState.lives -= 1
	await get_tree().create_timer(respawn_delay).timeout
	if GameState.lives <= 0:
		GameState.reset()
		SaveService.delete_save()
		SceneRouter.go_to_main_menu()
	else:
		SceneRouter.restart_level()


func _on_secret_area_body_entered(body: Node2D) -> void:
	if not body is Player:
		return
	$Props/SecretArea.set_deferred("monitoring", false)
	AudioService.play_sfx(&"secret")
	var tween := create_tween()
	tween.tween_property($Props/SecretWall, "modulate:a", 0.0, 0.5)
	tween.tween_callback($Props/SecretWall.queue_free)


func _on_level_completed(completed_id: String) -> void:
	if completed_id != level_id:
		return
	is_finished = true
	var best: float = GameState.best_times.get(level_id, INF)
	if elapsed_time < best:
		GameState.best_times[level_id] = elapsed_time
