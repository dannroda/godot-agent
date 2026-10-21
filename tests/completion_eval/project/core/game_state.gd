extends Node

signal coins_changed(coins: int)
signal lives_changed(lives: int)
signal score_changed(score: int)

const MAX_LIVES: int = 5
const STARTING_LIVES: int = 3
const LEVELS: Array[String] = [
	"res://tests/completion_eval/project/levels/level_01.tscn",
	"res://tests/completion_eval/project/levels/level_02.tscn",
]

var coins: int = 0:
	set(value):
		coins = maxi(value, 0)
		coins_changed.emit(coins)
var lives: int = STARTING_LIVES:
	set(value):
		lives = clampi(value, 0, MAX_LIVES)
		lives_changed.emit(lives)
var score: int = 0:
	set(value):
		score = value
		score_changed.emit(score)
var current_level: int = 0
var last_checkpoint: Vector2 = Vector2.ZERO
var has_checkpoint: bool = false
var unlocked_upgrades: Array[StringName] = []
var best_times: Dictionary[String, float] = {}


func _ready() -> void:
	EventBus.coin_collected.connect(_on_coin_collected)
	EventBus.enemy_killed.connect(_on_enemy_killed)
	EventBus.checkpoint_reached.connect(_on_checkpoint_reached)
	EventBus.level_completed.connect(_on_level_completed)


func reset() -> void:
	coins = 0
	lives = STARTING_LIVES
	score = 0
	current_level = 0
	has_checkpoint = false
	unlocked_upgrades.clear()


func has_upgrade(upgrade_id: StringName) -> bool:
	return upgrade_id in unlocked_upgrades


func unlock_upgrade(upgrade_id: StringName, cost: int) -> bool:
	if coins < cost or has_upgrade(upgrade_id):
		return false
	coins -= cost
	unlocked_upgrades.append(upgrade_id)
	EventBus.upgrade_purchased.emit(upgrade_id)
	return true


func get_level_path(index: int) -> String:
	return LEVELS[clampi(index, 0, LEVELS.size() - 1)]


func is_last_level() -> bool:
	return current_level >= LEVELS.size() - 1


func to_dict() -> Dictionary:
	var upgrade_names: Array[String] = []
	for upgrade_id in unlocked_upgrades:
		upgrade_names.append(String(upgrade_id))
	return {
		"coins": coins,
		"lives": lives,
		"score": score,
		"current_level": current_level,
		"unlocked_upgrades": upgrade_names,
		"best_times": best_times,
	}


func from_dict(data: Dictionary) -> void:
	coins = int(data.get("coins", 0))
	lives = int(data.get("lives", STARTING_LIVES))
	score = int(data.get("score", 0))
	current_level = int(data.get("current_level", 0))
	unlocked_upgrades.clear()
	for upgrade_name: String in data.get("unlocked_upgrades", []):
		unlocked_upgrades.append(StringName(upgrade_name))
	best_times.clear()
	var saved_times: Dictionary = data.get("best_times", {})
	for level_id: String in saved_times:
		best_times[level_id] = float(saved_times[level_id])


func _on_coin_collected(amount: int) -> void:
	coins += amount


func _on_enemy_killed(_enemy: Node2D, points: int) -> void:
	score += points


func _on_checkpoint_reached(checkpoint_position: Vector2) -> void:
	last_checkpoint = checkpoint_position
	has_checkpoint = true


func _on_level_completed(_level_id: String) -> void:
	has_checkpoint = false
	current_level += 1
