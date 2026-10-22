extends "test_case.gd"
## Archivos de traspaso del One-shot (D41): carpeta, .gdignore, rutas, lectura y escritura.

const OneShotFiles := preload("res://addons/godot_agent/oneshot/oneshot_files.gd")


func test_prepare_and_paths() -> void:
	var root := ProjectSettings.globalize_path("user://test_oneshot_files")
	OS.execute("rm", ["-rf", root])
	var files := OneShotFiles.new()
	assert_false(files.prepare(), "sin proyecto ni id no hace nada")
	files.project_root = root
	files.run_id = "20261022-101500"
	assert_false(files.has_spec(), "sin spec todavía")
	assert_true(files.prepare(), "prepara la carpeta")
	assert_true(DirAccess.dir_exists_absolute(root + "/.godot_agent/oneshot/20261022-101500"), "carpeta del run")
	assert_true(FileAccess.file_exists(root + "/.godot_agent/.gdignore"), ".gdignore: fuera del FileSystem y del export")
	assert_eq(files.relative_dir(), ".godot_agent/oneshot/20261022-101500", "ruta relativa")
	assert_eq(files.qa_path(2).get_file(), "qa-2.md", "qa por vuelta")
	assert_true(files.write(files.spec_path(), "# Pong\n"), "escribe")
	assert_true(files.has_spec(), "hay spec")
	assert_eq(files.read(files.spec_path()), "# Pong\n", "lee")
	assert_eq(files.read(files.progress_path()), "", "lo que no existe es vacío")
	assert_true(files.prepare(), "preparar de nuevo no rompe nada")
	OS.execute("rm", ["-rf", root])
