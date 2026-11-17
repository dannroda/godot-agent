extends "test_case.gd"
## Scope Compass integrado (m7-56): detección, el MCP scompass, sus permisos y la regla del prompt.

const ScopeCompass := preload("res://addons/godot_agent/mcp/scope_compass.gd")
const PermissionPolicy := preload("res://addons/godot_agent/session/permission_policy.gd")
const ExternalMcpServers := preload("res://addons/godot_agent/mcp/external_mcp_servers.gd")
const SessionModel := preload("res://addons/godot_agent/session/session_model.gd")
const SessionController := preload("res://addons/godot_agent/session/session_controller.gd")
const AgentLog := preload("res://addons/godot_agent/core/agent_log.gd")
const BoardTask := preload("res://addons/godot_agent/oneshot/board_task.gd")
const OneShotRun := preload("res://addons/godot_agent/oneshot/oneshot_run.gd")
const AgentProfile := preload("res://addons/godot_agent/core/agent_profile.gd")
const AgentMainScreen := preload("res://addons/godot_agent/ui/main_screen/agent_main_screen.gd")

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


## `@` del composer: tareas abiertas, hitos, documentos y al final las terminadas.
func test_mention_options() -> void:
	var dir := _project("sc_mentions", true, true)
	var board := dir.path_join(ScopeCompass.BOARD_DIR)
	for sub: String in ["tasks", "milestones"]:
		DirAccess.make_dir_recursive_absolute(board.path_join(sub))
	var files := {
		"tasks/m1-01.json": {"milestone": "m01", "title": "Hecha", "status": "done"},
		"tasks/m1-02.json": {"milestone": "m01", "title": "Mover al jugador", "status": "doing"},
		"milestones/m01.json": {"code": "M1", "title": "Prototipo"},
		"config.json": {"project": "x", "docs": [{"alias": "spec", "path": "SPEC.md"}, {"alias": "notas", "path": "docs/**/*.md"}]},
	}
	for path: String in files:
		var file := FileAccess.open(board.path_join(path), FileAccess.WRITE)
		file.store_string(JSON.stringify(files[path]))
		file.close()
	var inserts := ScopeCompass.mention_options(dir).map(func(option: Dictionary) -> String: return option.insert)
	assert_eq(inserts, ["compass://task/m1-02", "compass://milestone/m01", "compass://doc/spec", "compass://task/m1-01"], "abiertas, hitos, documentos (sin patrones) y terminadas")
	assert_true(str(ScopeCompass.mention_options(dir)[0].label).begins_with("m1-02 · Mover al jugador"), "el id y el título")
	assert_eq(ScopeCompass.mention_options(_project("sc_mentions_off", false, true)), [] as Array[Dictionary], "sin el plugin, nada")
	for path: String in files:
		DirAccess.remove_absolute(board.path_join(path))


## One-shot desde el tablero: el objetivo y las líneas del prompt inicial y del traspaso.
func test_oneshot_from_board() -> void:
	var task := {"id": "m1-02", "kind": "task", "title": "Mover al jugador", "description": "Con WASD."}
	assert_eq(BoardTask.goal_text(task), "Task m1-02: Mover al jugador\n\nCon WASD.", "título y descripción")
	assert_eq(BoardTask.goal_text({"id": "m01", "kind": "milestone", "title": "Prototipo"}), "Milestone m01: Prototipo", "un hito sin descripción")
	assert_eq(BoardTask.prompt_lines("", "task", "x"), PackedStringArray(), "sin tarea, nada")
	var lines := "\n".join(BoardTask.prompt_lines("m1-02", "task", ".godot_agent/oneshot/1/spec.md"))
	for text: String in ["task m1-02", "show_task", "add_step", "check_step", "add_file", ".godot_agent/oneshot/1/spec.md", "move it to review"]:
		assert_true(lines.contains(text), text)
	assert_true("\n".join(BoardTask.prompt_lines("m01", "milestone", "s")).contains("show_milestone"), "un hito se lee con show_milestone")
	var run := OneShotRun.new()
	run.board_item = "m1-02"
	run.goal = "x"
	assert_true(run.initial_prompt().contains("This run works on task m1-02"), "el prompt inicial lleva la tarea")
	assert_true(BoardTask.handoff_line("m1-02", "task").contains("show_task"), "el traspaso al retomar")
	run.free()


func test_read_item_and_picker() -> void:
	var dir := _project("sc_picker", true, true)
	var board := dir.path_join(ScopeCompass.BOARD_DIR)
	for sub: String in ["tasks", "milestones"]:
		DirAccess.make_dir_recursive_absolute(board.path_join(sub))
	var files := {
		"tasks/m1-01.json": {"milestone": "m01", "title": "Hecha", "status": "done"},
		"tasks/m1-02.json": {"milestone": "m01", "title": "Pendiente", "status": "todo"},
		"tasks/m1-03.json": {"milestone": "m01", "title": "En curso", "status": "doing"},
		"milestones/m01.json": {"code": "M1", "title": "Prototipo"},
	}
	for path: String in files:
		var file := FileAccess.open(board.path_join(path), FileAccess.WRITE)
		file.store_string(JSON.stringify(files[path]))
		file.close()
	assert_eq(ScopeCompass.read_item(dir, "m1-02").get("kind"), "task", "una tarea")
	assert_eq(ScopeCompass.read_item(dir, "m01").get("kind"), "milestone", "un hito")
	assert_eq(ScopeCompass.read_item(dir, "../config"), {}, "un id con / no sale del tablero")
	var ids := AgentMainScreen.board_picker_options(dir).map(func(option: Dictionary) -> String: return option.id)
	assert_eq(ids, ["m1-03", "m1-02", "m01"], "en curso, pendientes, hitos; sin las terminadas")
	for path: String in files:
		DirAccess.remove_absolute(board.path_join(path))


## m7-57: el assignee o la etiqueta agent:<x> de la tarea elige el agente del run.
func test_agent_from_task() -> void:
	assert_eq(BoardTask.agent_hint({"assignee": "Claude"}), "Claude", "el assignee")
	assert_eq(BoardTask.agent_hint({"assignee": "Claude", "tags": ["ui", "agente:codex trabajo"]}), "codex trabajo", "la etiqueta gana")
	assert_eq(BoardTask.agent_hint({"tags": ["Agent:Gemini"]}), "Gemini", "agent: sin importar mayúsculas")
	assert_eq(BoardTask.agent_hint({"tags": ["agent:"]}), "", "vacía no cuenta")
	var claude := AgentProfile.new()
	claude.id = "claude"
	claude.display_name = "Claude Code"
	claude.command = "claude-agent-acp"
	var codex := AgentProfile.new()
	codex.id = "codex-1"
	codex.display_name = "Codex"
	codex.command = "codex-acp"
	var choices: Array[Dictionary] = [
		{"profile": "claude", "account": "", "label": "Claude Code"},
		{"profile": "claude", "account": "/home/u/.claude-profiles/trabajo", "label": "Claude Code · trabajo · ana@x.com"},
		{"profile": "codex-1", "account": "", "label": "Codex"},
		{"profile": "borrado", "account": "", "label": "Viejo"},
	]
	var candidates := AgentMainScreen.board_agent_candidates([claude, codex], choices)
	assert_eq(candidates.size(), 3, "sin el perfil que ya no está")
	assert_eq(BoardTask.best_match("Claude", candidates), 0, "por nombre: la primera cuenta")
	assert_eq(BoardTask.best_match("claude trabajo", candidates), 1, "nombre y cuenta")
	assert_eq(BoardTask.best_match("ana@x.com", candidates), 1, "por email")
	assert_eq(BoardTask.best_match("Codex", candidates), 2, "otro agente")
	assert_eq(BoardTask.best_match("gemini", candidates), -1, "ninguno")
	assert_eq(BoardTask.best_match("", candidates), -1, "sin hint")
