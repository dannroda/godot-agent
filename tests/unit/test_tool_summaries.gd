extends "test_case.gd"
## m12-46: cada tool registrada en mcp/tools/ tiene una línea corta para las personas (traducida),
## y no sobran líneas de tools que ya no existen.

const ToolSummaries := preload("res://addons/godot_agent/mcp/tool_summaries.gd")
const I18n := preload("res://addons/godot_agent/core/i18n.gd")
const TOOLS_DIR := "res://addons/godot_agent/mcp/tools"


func test_every_registered_tool_has_a_summary() -> void:
	var registered := _registered_tools()
	assert_true(registered.size() >= 70, "encuentra las tools en los proveedores (%d)" % registered.size())
	var missing: PackedStringArray = []
	for tool_name: String in registered:
		if not ToolSummaries.SUMMARIES.has(tool_name):
			missing.append(tool_name)
	assert_eq(missing, PackedStringArray(), "tools sin línea corta")
	var stale: PackedStringArray = []
	for tool_name: String in ToolSummaries.SUMMARIES:
		if not tool_name in registered:
			stale.append(tool_name)
	assert_eq(stale, PackedStringArray(), "líneas de tools que ya no existen")
	for tool_name: String in ToolSummaries.SUMMARIES:
		var line := str(ToolSummaries.SUMMARIES[tool_name])
		assert_true(line.length() <= 90 and not line.ends_with("."), "corta y sin punto final: %s" % tool_name)
	I18n.set_locale("es")
	assert_eq(ToolSummaries.summary("run_scene"), "Corre una escena y devuelve los errores y el Output del juego", "traducida")
	assert_eq(ToolSummaries.summary("nope"), "", "desconocida: vacío")
	I18n.set_locale("en")


## Los nombres de `McpTool.create("nombre", …)` en los proveedores.
static func _registered_tools() -> PackedStringArray:
	var names: PackedStringArray = []
	var pattern := RegEx.create_from_string("McpTool\\.create\\(\\s*\"([a-z_0-9]+)\"")
	for file: String in DirAccess.get_files_at(TOOLS_DIR):
		if not file.ends_with(".gd"):
			continue
		for found: RegExMatch in pattern.search_all(FileAccess.get_file_as_string(TOOLS_DIR.path_join(file))):
			if not found.get_string(1) in names:
				names.append(found.get_string(1))
	return names
