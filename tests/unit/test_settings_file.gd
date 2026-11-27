extends "test_case.gd"
## m20-02: fuera del editor, HarnessSettings guarda en un ConfigFile y lo vuelve a leer.

const HarnessSettings := preload("res://addons/godot_agent/core/harness_settings.gd")

const PATH := "user://test_settings_file/settings.cfg"


func test_round_trip() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(PATH.get_base_dir()))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))
	var settings := HarnessSettings.new(null, PATH)
	assert_eq(settings.get_value(HarnessSettings.KEY_ACCOUNTS, {}), {}, "sin archivo arranca vacío")
	var accounts := {"claude-code": ["/c/a", "/c/b"], "antigravity": ["/g/a", "/g/b"]}
	settings.set_value(HarnessSettings.KEY_ACCOUNTS, accounts)
	settings.set_value(HarnessSettings.KEY_ACCENT, Color.RED)
	var again := HarnessSettings.new(null, PATH)
	assert_eq(again.get_value(HarnessSettings.KEY_ACCOUNTS, {}), accounts, "las cuentas vuelven al reabrir")
	assert_eq(again.accent_color(), Color.RED, "y el color, con su tipo")
	assert_false(FileAccess.file_exists(PATH + ".tmp"), "no queda el temporal de la escritura atómica")


func test_broken_file_is_kept_aside() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(PATH.get_base_dir()))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH + ".broken"))
	var file := FileAccess.open(PATH, FileAccess.WRITE)
	file.store_string("[godot_agent\nesto no es un ConfigFile = = =")
	file.close()
	var settings := HarnessSettings.new(null, PATH)
	assert_eq(settings.get_value(HarnessSettings.KEY_ACCOUNTS, {}), {}, "un archivo roto arranca vacío")
	assert_true(FileAccess.file_exists(PATH + ".broken"), "y queda apartado para no perderlo")


func test_memory_mode_writes_nothing() -> void:
	var settings := HarnessSettings.new()
	settings.set_value(HarnessSettings.KEY_ACCENT, Color.BLUE)
	assert_eq(settings.accent_color(), Color.BLUE, "sin archivo sigue en memoria, como en los tests")
