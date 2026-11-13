extends "test_case.gd"
## Reiniciar el editor y retomar las sesiones (m12-54): lo que se guarda de las pestañas, el orden en
## que vuelven, el mensaje para la que pidió el reinicio y la tool restart_editor para cualquier
## proyecto, con `reason` en la tarjeta.

const RestartResume := preload("res://addons/godot_agent/session/restart_resume.gd")
const DiagnosticTools := preload("res://addons/godot_agent/mcp/tools/diagnostic_tools.gd")
const McpTool := preload("res://addons/godot_agent/mcp/mcp_tool.gd")


func test_save_and_take_once() -> void:
	var dir := _dir("restart_resume_save")
	var tabs := [
		RestartResume.tab_entry("s1", "abc", "", 2, "", {}, false, true),
		RestartResume.tab_entry("s2", "def", "Level", 0, "level-design", {"project": "/tmp/copy", "branch": "agent/copy-1"}, true, false),
	]
	RestartResume.save(dir, "plugin enabled", tabs, 1000)
	var data := RestartResume.take(dir, 1010)
	assert_eq(str(data.get("reason")), "plugin enabled", "el motivo")
	assert_eq((data.tabs as Array).size(), 2, "las dos pestañas")
	assert_eq(str(data.tabs[1].session_id), "def", "con su sesión")
	assert_eq(str(data.tabs[1].project_mode), "level-design", "y su modo del proyecto")
	assert_eq(str(data.tabs[1].copy.branch), "agent/copy-1", "y la copia aparte")
	assert_true(RestartResume.take(dir, 1010).is_empty(), "una sola vez")


func test_old_or_broken_files_are_ignored() -> void:
	var dir := _dir("restart_resume_old")
	RestartResume.save(dir, "x", [RestartResume.tab_entry("s1", "abc", "", 2, "", {}, true, true)], 1000)
	assert_true(RestartResume.take(dir, 1000 + RestartResume.MAX_AGE_S + 1).is_empty(), "un reinicio que no pasó no reabre pestañas días después")
	assert_false(FileAccess.file_exists(dir.path_join(RestartResume.FILE)), "y se borra")
	var file := FileAccess.open(dir.path_join(RestartResume.FILE), FileAccess.WRITE)
	file.store_string("{not json")
	file.close()
	assert_true(RestartResume.take(dir).is_empty(), "roto: nada")
	RestartResume.save(dir, "x", [])
	RestartResume.discard(dir)
	assert_false(FileAccess.file_exists(dir.path_join(RestartResume.FILE)), "discard lo borra")


func test_tab_without_session_is_skipped() -> void:
	assert_true(RestartResume.tab_entry("s3", "", "", 2, "", {}, false, false).is_empty(), "una pestaña que nunca arrancó no se guarda")


func test_requester_opens_first_and_primary_is_not_a_copy() -> void:
	var tabs := [
		{"tab": "s1", "copy": {"project": "/c"}},
		{"tab": "s2", "copy": {}},
		{"tab": "s3", "copy": {}, "requester": true},
	]
	assert_eq(RestartResume.open_order(tabs), [2, 0, 1] as Array[int], "la que pidió primero, las demás como estaban")
	assert_eq(RestartResume.primary_index(tabs), 1, "la primera pestaña del dock no puede ser una copia")
	assert_eq(RestartResume.primary_index([{"copy": {"project": "/c"}}]), -1, "todas copias: ninguna")


func test_agent_message() -> void:
	assert_eq(RestartResume.agent_message("the plugin X was enabled"), "The editor restarted (the plugin X was enabled). Continue.", "con el motivo")
	assert_eq(RestartResume.agent_message("r", PackedStringArray(["The editor crashed."])), "The editor restarted (r). Continue.\n\nThe editor crashed.", "lo del supervisor después")


func test_restart_tool_needs_a_reason() -> void:
	var tools := DiagnosticTools.new()
	tools.setup(null, _dir("restart_resume_tool"))
	var calls: Array = []
	tools.restarter = func(supervise: bool, reason: String) -> String:
		calls.append([supervise, reason])
		return ""
	var tool := _tool(tools, "restart_editor")
	assert_eq(tool.input_schema.get("required"), ["reason"], "reason es obligatorio")
	assert_true(tool.description.contains("plugin enabled or disabled") and tool.description.contains("GDExtension"), "la descripción es para cualquier proyecto · " + tool.description.left(200))
	var blank: Dictionary = tools._restart_editor({"reason": "  "})
	assert_true(blank.isError and calls.is_empty(), "un motivo vacío no reinicia")
	var result: Dictionary = tools._restart_editor({"reason": "the renderer changed"})
	assert_false(result.isError, str(result))
	assert_eq(calls, [[false, "the renderer changed"]], "sin GDExtension, sin supervisor por defecto, y con el motivo")
	assert_false(result.content[0].text.contains("stays down"), "sin GDExtension no avisa de una build que crashea")
	calls.clear()
	tools._restart_editor({"reason": "r", "supervise": true})
	assert_eq(calls, [[true, "r"]], "supervise lo pide")


func test_card_shows_the_reason_and_the_note() -> void:
	var tools := DiagnosticTools.new()
	tools.setup(null, _dir("restart_resume_card"))
	var tool := _tool(tools, "restart_editor")
	var text := tool.describe({"reason": "the plugin X was enabled"})
	assert_true(text.contains("the plugin X was enabled") and text.split("\n").size() == 1, "el motivo, en una línea · " + text)
	tools.restart_note = func() -> String: return "⚠ busy"
	text = tool.describe({"reason": "r"})
	assert_true(text.ends_with("\n⚠ busy"), "y lo que agrega el plugin · " + text)


func _tool(tools: Object, name: String) -> McpTool:
	for tool: McpTool in tools.tools():
		if tool.name == name:
			return tool
	return null


func _dir(name: String) -> String:
	var path := ProjectSettings.globalize_path("user://unit_tests/%s" % name)
	DirAccess.make_dir_recursive_absolute(path)
	return path
