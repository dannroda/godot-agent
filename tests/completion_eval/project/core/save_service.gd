extends Node

signal game_saved
signal game_loaded

const SAVE_PATH: String = "user://savegame.json"
const SAVE_VERSION: int = 2


func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)


func save_game() -> void:
	var data: Dictionary = {
		"version": SAVE_VERSION,
		"timestamp": Time.get_unix_time_from_system(),
		"game_state": GameState.to_dict(),
	}
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_error("Could not open save file: %s" % error_string(FileAccess.get_open_error()))
		return
	file.store_string(JSON.stringify(data, "\t"))
	file.close()
	game_saved.emit()


func load_game() -> bool:
	if not has_save():
		return false
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		push_error("Could not read save file: %s" % error_string(FileAccess.get_open_error()))
		return false
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if not parsed is Dictionary:
		push_warning("Save file is corrupted, ignoring it")
		return false
	var data: Dictionary = _migrate(parsed)
	GameState.from_dict(data.get("game_state", {}))
	game_loaded.emit()
	return true


func delete_save() -> void:
	if has_save():
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))


func get_save_timestamp() -> int:
	if not has_save():
		return 0
	return FileAccess.get_modified_time(SAVE_PATH)


func _migrate(data: Dictionary) -> Dictionary:
	var version: int = int(data.get("version", 1))
	if version < 2:
		data["game_state"] = {
			"coins": data.get("coins", 0),
			"lives": data.get("lives", 3),
			"current_level": data.get("level", 0),
		}
	data["version"] = SAVE_VERSION
	return data
