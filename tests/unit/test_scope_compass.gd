extends "test_case.gd"
## Scope Compass integrado (m7-56): detección, el MCP scompass, sus permisos y la regla del prompt.

const ScopeCompass := preload("res://addons/godot_agent/mcp/scope_compass.gd")
const PermissionPolicy := preload("res://addons/godot_agent/session/permission_policy.gd")
const ExternalMcpServers := preload("res://addons/godot_agent/mcp/external_mcp_servers.gd")
const SessionModel := preload("res://addons/godot_agent/session/session_model.gd")
const SessionController := preload("res://addons/godot_agent/session/session_controller.gd")
const AgentLog := preload("res://addons/godot_agent/core/agent_log.gd")

const M := SessionModel.HarnessMode
const PROGRAM := ["/usr/bin/scompass", []]


## Un proyecto en una carpeta temporal: con o sin el plugin activado y con o sin compass/.
func _project(name: String, plugin: bool, board: bool) -> String:
	var dir := ProjectSettings.globalize_path(temp_dir(name))
	DirAccess.remove_absolute(dir.path_join(ScopeCompass.BOARD_DIR))
	var plugins := ["res://addons/godot_agent/plugin.cfg"]
	if plugin:
		plugins.append(ScopeCompass.PLUGIN_CFG)
	var config := ConfigFile.new()
	config.set_value("editor_plugins", "enabled", PackedStringArray(plugins))
	config.save(dir.path_join("project.godot"))
	if board:
		DirAccess.make_dir_absolute(dir.path_join(ScopeCompass.BOARD_DIR))
	return dir


func test_detect_needs_plugin_and_board() -> void:
	assert_true(ScopeCompass.detect(_project("sc_both", true, true)), "plugin activado y compass/")
	assert_false(ScopeCompass.detect(_project("sc_no_plugin", false, true)), "compass/ sin el plugin")
	assert_false(ScopeCompass.detect(_project("sc_no_board", true, false)), "el plugin sin tablero")
	assert_false(ScopeCompass.detect(ProjectSettings.globalize_path(temp_dir("sc_empty"))), "sin project.godot")


func test_server_entry() -> void:
	var dir := _project("sc_entry", true, true)
	var entry := ScopeCompass.server_entry(dir, ["node", ["/opt/sc/scompass.js"]])
	assert_eq(ExternalMcpServers.to_acp(entry, true), {
		"name": "scompass", "command": "node", "args": ["/opt/sc/scompass.js", "--dir", dir, "mcp"], "env": [],
	}, "stdio con --dir del proyecto")
	assert_eq(ExternalMcpServers.validate([ExternalMcpServers.normalize(entry)]), "", "válido como server de terceros")
	assert_eq(ScopeCompass.server_entry(dir, []), {}, "sin scompass en la máquina, nada")
	assert_eq(ScopeCompass.server_entry(_project("sc_entry_off", false, true), PROGRAM), {}, "sin el plugin, nada")


## scompass sale del registro del usuario y no de una carpeta del proyecto.
func test_recorded_command() -> void:
	var data := ProjectSettings.globalize_path(temp_dir("sc_data"))
	var previous := OS.get_environment("SCOMPASS_DATA")
	OS.set_environment("SCOMPASS_DATA", data)
	var program := data.path_join("scompass")
	var file := FileAccess.open(program, FileAccess.WRITE)
	file.store_string("#!/bin/sh\n")
	file.close()
	assert_eq(ScopeCompass.recorded_command(), [], "sin scompass.json")
	file = FileAccess.open(data.path_join("scompass.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"command": program, "args": []}))
	file.close()
	assert_eq(ScopeCompass.recorded_command(), [program, []], "el que anotó scompass")
	assert_eq(ScopeCompass.command("/no/existe"), [program, []], "el registro gana")
	file = FileAccess.open(data.path_join("scompass.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"command": data.path_join("borrado"), "args": []}))
	file.close()
	assert_eq(ScopeCompass.recorded_command(), [], "un programa que ya no está no vale")
	OS.set_environment("SCOMPASS_DATA", previous)


## Las lecturas del tablero van a Read; las escrituras, a mcp:scompass, que no pregunta desde Construir.
func test_permission_groups() -> void:
	var read := {"title": "mcp__scompass__show_task", "kind": "other", "_meta": {"claudeCode": {"toolName": "mcp__scompass__show_task"}}}
	var write := {"title": "mcp__scompass__move_task", "kind": "other", "_meta": {"claudeCode": {"toolName": "mcp__scompass__move_task"}}}
	var agy := {"title": "scompass_list_tasks", "kind": "other", "_meta": {"mcp": {"tool": "list_tasks", "server": "scompass"}}}
	assert_eq(PermissionPolicy.group_for_tool_call(read), PermissionPolicy.GROUP_READ, "show_task lee")
	assert_eq(PermissionPolicy.group_for_tool_call(agy), PermissionPolicy.GROUP_READ, "Antigravity: list_tasks lee")
	var group := PermissionPolicy.group_for_tool_call(write)
	assert_eq(group, "mcp:scompass", "move_task escribe")
	var policy := PermissionPolicy.new({})
	assert_eq(policy.matrix_value(group, M.ASK), PermissionPolicy.ASK, "Preguntar pregunta")
	assert_eq(policy.matrix_value(group, M.REVIEW), PermissionPolicy.ASK, "Revisar pregunta")
	for mode: M in [M.BUILD, M.ONESHOT, M.AUTO]:
		assert_eq(policy.matrix_value(group, mode), PermissionPolicy.ALLOW, "escribe solo en %d" % mode)
	var custom := PermissionPolicy.new({group: {"build": PermissionPolicy.DENY}})
	assert_eq(custom.matrix_value(group, M.BUILD), PermissionPolicy.DENY, "la matriz del proyecto gana")
	var blender := {"title": "mcp__blender__list_tasks", "kind": "other"}
	assert_eq(PermissionPolicy.group_for_tool_call(blender), "mcp:blender", "otro server con el mismo nombre de tool no es Read")


func test_prompt_rules_only_with_board() -> void:
	var dir := _project("sc_prompt", true, false)
	var controller := SessionController.new()
	controller.setup(SessionModel.new(), AgentLog.new(), dir)
	assert_false(controller.system_prompt().contains("Scope Compass in this project"), "sin tablero, sin reglas")
	DirAccess.make_dir_absolute(dir.path_join(ScopeCompass.BOARD_DIR))
	var prompt := controller.system_prompt()
	assert_true(prompt.contains("Scope Compass in this project") and prompt.contains("compass/AGENTS.md"), "con el tablero, las reglas")
	assert_false(RegEx.create_from_string("\\{[a-z_]+\\}").search(prompt) != null, "sin variables sin reemplazar")
	DirAccess.remove_absolute(dir.path_join(ScopeCompass.BOARD_DIR))
