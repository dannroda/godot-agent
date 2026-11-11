extends "test_case.gd"
## Revisión next2 #28: los textos que mandan a un lugar de Settings nombran uno que existe. «Editor
## tools» es el título de una parte de MCP servers → Advanced, no una sección; «MCP server» (singular)
## tampoco existe.

const SCANNED: PackedStringArray = ["res://addons/godot_agent", "res://addons/godot_agent_dev", "res://CHANGELOG.md", "res://docs/wiki"]


func test_settings_paths_exist() -> void:
	var dialog := FileAccess.get_file_as_string("res://addons/godot_agent/ui/settings/settings_dialog.gd")
	assert_true(dialog.contains("\"MCP servers\",  # i18n"), "la sección MCP servers existe")
	assert_true(dialog.contains("I18n.t(\"Advanced: the editor's MCP server"), "y su parte Advanced")
	var stale := RegEx.create_from_string("Settings → (Editor tools|MCP server(?!s)|Servidor MCP(?!s))|Ajustes → Herramientas del editor")
	var found: PackedStringArray = []
	for root: String in SCANNED:
		for path: String in _files(root):
			var text := FileAccess.get_file_as_string(path)
			for match: RegExMatch in stale.search_all(text):
				found.append("%s: %s" % [path, match.get_string()])
	assert_eq(found, PackedStringArray(), "ningún texto manda a una sección que no existe")


static func _files(root: String) -> PackedStringArray:
	if FileAccess.file_exists(root):
		return PackedStringArray([root])
	var out: PackedStringArray = []
	var dir := DirAccess.open(root)
	if dir == null:
		return out
	for file: String in dir.get_files():
		if file.get_extension() in ["gd", "po", "md"]:
			out.append(root.path_join(file))
	for sub: String in dir.get_directories():
		out.append_array(_files(root.path_join(sub)))
	return out
