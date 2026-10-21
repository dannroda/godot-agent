extends Node

signal settings_changed

const SETTINGS_PATH: String = "user://settings.cfg"

var master_volume: float = 1.0
var music_volume: float = 0.8
var sfx_volume: float = 1.0
var fullscreen: bool = false
var screen_shake: bool = true


func _ready() -> void:
	load_settings()
	apply()


func apply() -> void:
	_set_bus_volume("Master", master_volume)
	_set_bus_volume("Music", music_volume)
	_set_bus_volume("SFX", sfx_volume)
	if fullscreen:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	settings_changed.emit()


func save_settings() -> void:
	var config := ConfigFile.new()
	config.set_value("audio", "master_volume", master_volume)
	config.set_value("audio", "music_volume", music_volume)
	config.set_value("audio", "sfx_volume", sfx_volume)
	config.set_value("video", "fullscreen", fullscreen)
	config.set_value("gameplay", "screen_shake", screen_shake)
	var err := config.save(SETTINGS_PATH)
	if err != OK:
		push_error("Could not save settings: %s" % error_string(err))


func load_settings() -> void:
	var config := ConfigFile.new()
	if config.load(SETTINGS_PATH) != OK:
		return
	master_volume = config.get_value("audio", "master_volume", master_volume)
	music_volume = config.get_value("audio", "music_volume", music_volume)
	sfx_volume = config.get_value("audio", "sfx_volume", sfx_volume)
	fullscreen = config.get_value("video", "fullscreen", fullscreen)
	screen_shake = config.get_value("gameplay", "screen_shake", screen_shake)


func _set_bus_volume(bus_name: String, linear: float) -> void:
	var bus_index := AudioServer.get_bus_index(bus_name)
	if bus_index == -1:
		return
	AudioServer.set_bus_volume_db(bus_index, linear_to_db(linear))
	AudioServer.set_bus_mute(bus_index, linear <= 0.001)
