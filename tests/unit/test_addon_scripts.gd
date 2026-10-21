extends "test_case.gd"
## Todos los scripts del addon compilan (atrapa errores de parseo sin abrir el editor).

const ROOTS: PackedStringArray = ["res://addons/godot_agent", "res://addons/godot_agent_dev"]


func test_all_scripts_compile() -> void:
	var paths: PackedStringArray = []
	for root: String in ROOTS:
		_collect(root, paths)
	assert_true(paths.size() > 10, "encontró scripts (%d)" % paths.size())
	for path: String in paths:
		var script: GDScript = ResourceLoader.load(path, "GDScript", ResourceLoader.CACHE_MODE_IGNORE)
		assert_true(script != null and script.can_instantiate(), "compila: %s" % path)


func _collect(dir_path: String, out: PackedStringArray) -> void:
	for file: String in DirAccess.get_files_at(dir_path):
		if file.ends_with(".gd"):
			out.append(dir_path.path_join(file))
	for sub: String in DirAccess.get_directories_at(dir_path):
		_collect(dir_path.path_join(sub), out)
