extends "test_case.gd"
## Los enums y clases internas del addon tienen nombres compuestos (D47). Si un juego declara
## `class_name Level` y el addon tiene `enum Level` con `var level: Level`, Godot resuelve el tipo a
## la clase global al compilar otro script que lo usa, y el addon no carga (pasó en great-boy-one).

const ADDON_DIRS: PackedStringArray = ["res://addons/godot_agent", "res://addons/godot_agent_dev"]


func test_inner_types_have_compound_names() -> void:
	var single_word := RegEx.create_from_string("^(?:enum|class) ([A-Z][a-z0-9]*)\\b")
	var found: PackedStringArray = []
	for dir: String in ADDON_DIRS:
		for path: String in _scripts(dir):
			var lines := FileAccess.get_file_as_string(path).split("\n")
			for i in lines.size():
				var match := single_word.search(lines[i])
				if match:
					found.append("%s:%d %s" % [path.get_file(), i + 1, match.get_string(1)])
	assert_eq(found, PackedStringArray(), "enum o clase interna con nombre de una palabra")


func _scripts(dir: String) -> PackedStringArray:
	var result: PackedStringArray = []
	for file: String in DirAccess.get_files_at(dir):
		if file.ends_with(".gd"):
			result.append(dir.path_join(file))
	for sub: String in DirAccess.get_directories_at(dir):
		result.append_array(_scripts(dir.path_join(sub)))
	return result
