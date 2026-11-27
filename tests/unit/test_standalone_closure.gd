extends "test_case.gd"
## m20-07: nada que cargue la app aparte nombra una clase del editor. Una plantilla de exportación no
## las tiene y ese script no parsea: al editor se llega por AgentTheme.editor() y AgentTheme.file_dialog().
## Sigue los preload/load y los ext_resource desde standalone/main.tscn.

const START := "res://addons/godot_agent/standalone/main.tscn"
const REFERENCE := "(?:preload|load)\\(\\s*\"([^\"]+)\"\\s*\\)|\\[ext_resource[^\\]]*path=\"([^\"]+)\""


func test_nothing_the_app_loads_names_editor_classes() -> void:
	var names: PackedStringArray = []
	for name: String in ClassDB.get_class_list():
		if ClassDB.class_get_api_type(name) == ClassDB.API_EDITOR:
			names.append(name)
	assert_true(names.has("EditorInterface"), "el binario de los tests tiene las clases del editor")
	var editor_class := RegEx.create_from_string("\\b(%s)\\b" % "|".join(names))
	var reference := RegEx.create_from_string(REFERENCE)
	var seen: Dictionary = {}
	var pending: Array[String] = [START]
	var uses: PackedStringArray = []
	while not pending.is_empty():
		var path: String = pending.pop_back()
		if seen.has(path) or not path.get_extension() in ["gd", "tscn", "tres"] or not FileAccess.file_exists(path):
			continue
		seen[path] = true
		var text := FileAccess.get_file_as_string(path)
		for found: RegExMatch in reference.search_all(text):
			var target := found.get_string(1) if not found.get_string(1).is_empty() else found.get_string(2)
			pending.append(target if target.begins_with("res://") else path.get_base_dir().path_join(target).simplify_path())
		if path.get_extension() != "gd":
			continue
		var lines := text.split("\n")
		for i in lines.size():
			var code := lines[i].get_slice("#", 0)
			for found: RegExMatch in editor_class.search_all(code):
				if not code.contains("\"" + found.get_string(1)):  # Engine.has_singleton(&"EditorInterface")
					uses.append("%s:%d: %s" % [path, i + 1, lines[i].strip_edges()])
	assert_true(seen.size() > 100, "recorrió lo que carga la app (%d archivos)" % seen.size())
	assert_eq(uses, PackedStringArray(), "clases del editor en lo que carga la app")
