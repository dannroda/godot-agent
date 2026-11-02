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


## Archivos de referencia del usuario (GDD, arte…): los del proyecto quedan donde están, los de
## afuera se copian a refs/ sin pisarse, y los que no existen o pasan el tope se informan.
func test_add_references() -> void:
	var root := ProjectSettings.globalize_path("user://test_oneshot_refs/project")
	var outside := ProjectSettings.globalize_path("user://test_oneshot_refs/outside")
	OS.execute("rm", ["-rf", root.get_base_dir()])
	DirAccess.make_dir_recursive_absolute(root.path_join("docs"))
	DirAccess.make_dir_recursive_absolute(outside.path_join("otra"))
	for path: String in [root.path_join("docs/gdd.md"), outside.path_join("gdd.md"), outside.path_join("otra/gdd.md"), outside.path_join("arte.png")]:
		var file := FileAccess.open(path, FileAccess.WRITE)
		file.store_string("contenido de " + path.get_file())
		file.close()
	var files := OneShotFiles.new()
	files.project_root = root
	files.run_id = "20261102-120000"
	files.prepare()
	var added := files.add_references(PackedStringArray([root.path_join("docs/gdd.md"), outside.path_join("gdd.md"), outside.path_join("otra/gdd.md"), outside.path_join("arte.png"), outside.path_join("no-existe.md")]))
	var refs := files.refs_dir()
	assert_eq(added.paths, PackedStringArray([root.path_join("docs/gdd.md"), refs.path_join("gdd.md"), refs.path_join("gdd-2.md"), refs.path_join("arte.png")]), "el del proyecto en su lugar; los de afuera copiados, sin pisarse")
	assert_eq(added.skipped, PackedStringArray(["no-existe.md"]), "el que no existe se informa")
	assert_eq(FileAccess.get_file_as_string(refs.path_join("gdd-2.md")), "contenido de gdd.md", "la copia tiene el contenido")
	assert_true(refs.begins_with(root), "las copias quedan adentro del proyecto, donde lee el agente")
	OS.execute("rm", ["-rf", root.get_base_dir()])
