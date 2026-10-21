extends CanvasLayer

@export var heart_full: Texture2D
@export var heart_empty: Texture2D

var _player: Player

@onready var hearts: HBoxContainer = %Hearts
@onready var energy_bar: ProgressBar = %EnergyBar
@onready var coin_label: Label = %CoinLabel
@onready var lives_label: Label = %LivesLabel
@onready var score_label: Label = %ScoreLabel
@onready var time_label: Label = %TimeLabel
@onready var level_label: Label = %LevelLabel
@onready var animation_player: AnimationPlayer = $AnimationPlayer


func _ready() -> void:
	GameState.coins_changed.connect(_on_coins_changed)
	GameState.lives_changed.connect(_on_lives_changed)
	GameState.score_changed.connect(_on_score_changed)
	EventBus.level_completed.connect(_on_level_completed)
	EventBus.game_paused.connect(_on_game_paused)
	coin_label.text = str(GameState.coins)
	lives_label.text = "x%d" % GameState.lives
	score_label.text = "%06d" % GameState.score
	level_label.text = "Level %d" % (GameState.current_level + 1)
	_bind_player.call_deferred()


func _process(_delta: float) -> void:
	var level := owner as Level
	if level:
		time_label.text = _format_time(level.elapsed_time)


func _bind_player() -> void:
	_player = get_tree().get_first_node_in_group("player") as Player
	if _player == null:
		return
	_player.health.changed.connect(_on_health_changed)
	_player.energy.changed.connect(_on_energy_changed)
	_on_health_changed(_player.health.current_health, _player.health.max_health)
	_on_energy_changed(_player.energy.current_energy, _player.energy.max_energy)


func _format_time(seconds: float) -> String:
	var minutes := floori(seconds / 60.0)
	return "%02d:%05.2f" % [minutes, fmod(seconds, 60.0)]


func _on_health_changed(current: int, maximum: int) -> void:
	for child in hearts.get_children():
		child.queue_free()
	for i in maximum:
		var heart := TextureRect.new()
		heart.texture = heart_full if i < current else heart_empty
		heart.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		hearts.add_child(heart)


func _on_energy_changed(current: float, maximum: float) -> void:
	energy_bar.max_value = maximum
	energy_bar.value = current


func _on_coins_changed(coins: int) -> void:
	coin_label.text = str(coins)
	animation_player.play("coin_bump")


func _on_lives_changed(lives: int) -> void:
	lives_label.text = "x%d" % lives


func _on_score_changed(score: int) -> void:
	score_label.text = "%06d" % score
	var tween := create_tween()
	tween.tween_property(score_label, "scale", Vector2(1.2, 1.2), 0.08)
	tween.tween_property(score_label, "scale", Vector2.ONE, 0.12)


func _on_level_completed(_level_id: String) -> void:
	animation_player.play("level_complete")


func _on_game_paused(is_paused: bool) -> void:
	visible = not is_paused
