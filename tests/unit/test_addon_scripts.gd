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


## Ningún guardado del addon pasa por la vista previa (m17-01, D60): ni save_scene(), ni
## save_scene_as(path) sin `false`, ni save_all_scenes() fuera de plugin._save_all_scenes, que antes
## guarda la escena activa sin vista previa.
func test_no_save_with_preview() -> void:
	var paths: PackedStringArray = []
	_collect("res://addons/godot_agent", paths)
	var offenders: PackedStringArray = []
	var allowed_save_all := 0
	for path: String in paths:
		var function := ""
		var number := 0
		for line: String in FileAccess.get_file_as_string(path).split("\n"):
			number += 1
			if line.begins_with("func ") or line.begins_with("static func "):
				function = line.get_slice("func ", 1).get_slice("(", 0)
			var code := line.get_slice("#", 0)
			var bad := code.contains(".save_scene()") or (code.contains("save_scene_as(") and not code.contains(", false)"))
			if code.contains("EditorInterface.save_all_scenes()"):
				if path.ends_with("/godot_agent/agent_plugin.gd") and function == "_save_all_scenes":
					allowed_save_all += 1
				else:
					bad = true
			if bad:
				offenders.append("%s:%d" % [path, number])
	assert_eq(offenders, PackedStringArray(), "guardados con vista previa")
	assert_eq(allowed_save_all, 1, "plugin._save_all_scenes sigue siendo el único save_all_scenes")
	var tools := FileAccess.get_file_as_string("res://addons/godot_agent/mcp/tools/scene_edit_tools.gd")
	assert_true(tools.contains("EditorInterface.save_scene_as(scene_path, false)"), "la tool save_scene guarda sin vista previa")


func _collect(dir_path: String, out: PackedStringArray) -> void:
	for file: String in DirAccess.get_files_at(dir_path):
		if file.ends_with(".gd"):
			out.append(dir_path.path_join(file))
	for sub: String in DirAccess.get_directories_at(dir_path):
		_collect(dir_path.path_join(sub), out)
