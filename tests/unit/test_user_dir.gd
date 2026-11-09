extends "test_case.gd"
## user:// propio de cada checkout (m13-17): run_all ya llamó a TestUserDir.apply(), así que acá se
## verifica el resultado: la carpeta, que todo user:// cae adentro, que repetirlo no cambia nada y
## que el override no termina en project.godot si algo guarda los ajustes.

const TestUserDir := preload("res://tests/test_user_dir.gd")


func test_user_dir_is_the_checkouts_one() -> void:
	var dir := OS.get_user_data_dir()
	var suffix := "/%s/%s" % [TestUserDir.SUBDIR, TestUserDir.checkout_tag()]
	assert_true(dir.ends_with(suffix), "user:// termina en %s (%s)" % [suffix, dir])
	assert_true(dir.trim_suffix(suffix).ends_with(str(ProjectSettings.get_setting("application/config/name"))), "cuelga de la carpeta por defecto del proyecto (%s)" % dir)
	assert_true(ProjectSettings.globalize_path("user://unit_tests/x").begins_with(dir + "/"), "globalize_path(user://) cae adentro")
	var path := temp_dir("user_dir_probe").path_join("probe.txt")
	var file := FileAccess.open(path, FileAccess.WRITE)
	assert_true(file != null, "se puede escribir en user:// (%s)" % error_string(FileAccess.get_open_error()))
	if file:
		file.store_string("x")
		file.close()
	assert_true(FileAccess.file_exists(dir.path_join("unit_tests/user_dir_probe/probe.txt")), "lo que se escribe en user:// está en la carpeta del checkout")


func test_apply_is_idempotent() -> void:
	var before := OS.get_user_data_dir()
	assert_eq(TestUserDir.apply(), before, "una segunda llamada devuelve la misma carpeta")
	assert_eq(OS.get_user_data_dir(), before, "y no la cambia")


func test_tag_is_stable_and_version_aware() -> void:
	var tag := TestUserDir.checkout_tag()
	assert_eq(tag, TestUserDir.checkout_tag(), "el mismo checkout da el mismo nombre")
	var version: Dictionary = Engine.get_version_info()
	assert_true(tag.ends_with("-%d.%d" % [int(version.major), int(version.minor)]), "lleva la versión de Godot (%s)" % tag)
	assert_eq(tag.length(), 8 + 1 + ("%d.%d" % [int(version.major), int(version.minor)]).length(), "md5 corto + versión (%s)" % tag)


func test_override_is_not_saved_to_project_godot() -> void:
	var out := temp_dir("user_dir_save").path_join("project.godot")
	assert_eq(ProjectSettings.save_custom(out), OK, "save_custom")
	var text := FileAccess.get_file_as_string(out)
	assert_false(text.contains("custom_user_dir"), "project.godot guardado sin el override")
	assert_true(bool(ProjectSettings.get_setting(TestUserDir.SETTING_ENABLED)), "y la redirección sigue activa")
