extends Node

const SFX_POOL_SIZE: int = 8
const SOUND_DIR: String = "res://tests/completion_eval/project/sounds/"
const SILENT_DB: float = -40.0

var _sfx_players: Array[AudioStreamPlayer] = []
var _next_player: int = 0
var _music_player: AudioStreamPlayer
var _cache: Dictionary[StringName, AudioStream] = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i in SFX_POOL_SIZE:
		var player := AudioStreamPlayer.new()
		player.bus = &"SFX"
		add_child(player)
		_sfx_players.append(player)
	_music_player = AudioStreamPlayer.new()
	_music_player.bus = &"Music"
	add_child(_music_player)


func play_sfx(sound_name: StringName, pitch_variation: float = 0.1) -> void:
	var stream := _get_stream(sound_name)
	if stream == null:
		return
	var player := _sfx_players[_next_player]
	_next_player = (_next_player + 1) % _sfx_players.size()
	player.stream = stream
	player.pitch_scale = 1.0 + randf_range(-pitch_variation, pitch_variation)
	player.play()


func play_music(stream: AudioStream, fade_time: float = 1.0) -> void:
	if _music_player.stream == stream and _music_player.playing:
		return
	if _music_player.playing:
		var fade_out := create_tween()
		fade_out.tween_property(_music_player, "volume_db", SILENT_DB, fade_time * 0.5)
		await fade_out.finished
	_music_player.stream = stream
	_music_player.volume_db = SILENT_DB
	_music_player.play()
	var fade_in := create_tween()
	fade_in.tween_property(_music_player, "volume_db", 0.0, fade_time * 0.5)


func stop_music(fade_time: float = 0.5) -> void:
	var tween := create_tween()
	tween.tween_property(_music_player, "volume_db", SILENT_DB, fade_time)
	tween.tween_callback(_music_player.stop)


func _get_stream(sound_name: StringName) -> AudioStream:
	if _cache.has(sound_name):
		return _cache[sound_name]
	var path := SOUND_DIR + String(sound_name) + ".wav"
	if not ResourceLoader.exists(path):
		push_warning("Missing sound: %s" % path)
		return null
	var stream: AudioStream = load(path)
	_cache[sound_name] = stream
	return stream
