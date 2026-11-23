extends "test_case.gd"
## Revisión next2 #28: los textos que mandan a un lugar de Settings nombran uno que existe. «Editor
## tools» es el título de una parte de Advanced, no una sección; «MCP server» (singular) tampoco existe.
## m12-57 reordenó las secciones: «MCP servers → Advanced», «Interface», «Plan quota», «Completion» y
## «Export» ya no existen. El CHANGELOG no se revisa: sus versiones viejas nombran lo que había entonces.

const SCANNED: PackedStringArray = ["res://addons/godot_agent", "res://addons/godot_agent_dev", "res://docs/wiki", "res://README.md", "res://README.es.md", "res://PRIVACY.md"]


func test_settings_paths_exist() -> void:
	var dialog := FileAccess.get_file_as_string("res://addons/godot_agent/ui/settings/settings_dialog.gd")
	assert_false(dialog.contains("\"MCP servers\",  # i18n"), "los servidores MCP se editan en Extensions (m12-58)")
	for label: String in ["General", "After each turn", "Code completion", "Advanced"]:
		assert_true(dialog.contains("\"%s\",  # i18n" % label), "la sección %s existe" % label)
	var stale := RegEx.create_from_string("(?<!Editor )(Settings|Ajustes) → (Editor tools|MCP server(?!s)|Servidor MCP(?!s)|Herramientas del editor|Interface|Interfaz|Plan quota|Cuota del plan|Completion|Completado|Export)|(MCP servers|Servidores MCP) → (Advanced|Avanzado)|(Settings|Ajustes) → (MCP servers|Servidores MCP)|Project folders\\*\\*|Carpetas del proyecto\\*\\*")
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
