extends "test_case.gd"
## m20-03: fuera del editor, la carpeta del proyecto es la elegida y las menciones con @ la recorren.

const EditorContext := preload("res://addons/godot_agent/ui/editor_context.gd")

const DIR := "user://test_editor_context_root"


func test_project_root_override() -> void:
	var root := ProjectSettings.globalize_path(DIR)
	for sub: String in ["scripts", ".git", ".godot", "addons/godot_agent", "art"]:
		DirAccess.make_dir_recursive_absolute(root.path_join(sub))
	for file: String in ["main.tscn", "scripts/player.gd", ".git/config.md", ".godot/cache.cfg", "addons/godot_agent/x.gd", "art/hero.png"]:
		FileAccess.open(root.path_join(file), FileAccess.WRITE).store_string("x")
	assert_eq(EditorContext.project_path(), ProjectSettings.globalize_path("res://").trim_suffix("/"), "sin carpeta elegida, la del proyecto abierto")
	EditorContext.project_root = root + "/"
	assert_eq(EditorContext.project_path(), root, "con carpeta elegida, esa, sin la barra final")
	var inserts: PackedStringArray = []
	for option: Dictionary in EditorContext.mention_options():
		inserts.append(str(option.insert))
	EditorContext.project_root = ""
	inserts.sort()
	assert_eq(inserts, PackedStringArray(["main.tscn", "scripts/player.gd"]), "archivos de texto relativos a la carpeta, sin ocultas, sin el addon ni imágenes")
