extends "test_case.gd"
## Modos del proyecto (m11-39): el formato de los .json, los archivos que dejan escribir, la capa sobre
## la matriz (nunca más permisos que el base), la shell que pregunta siempre con archivos limitados
## (también en Auto), las escrituras del agente rechazadas sin tarjeta, las tools godot.* que declaran
## qué escriben (falla cerrada) y las instrucciones en el system prompt.

const ProjectModes := preload("res://addons/godot_agent/core/project_modes.gd")
const SessionModel := preload("res://addons/godot_agent/session/session_model.gd")
const SessionController := preload("res://addons/godot_agent/session/session_controller.gd")
const PermissionPolicy := preload("res://addons/godot_agent/session/permission_policy.gd")
const PermissionRequest := preload("res://addons/godot_agent/session/permission_request.gd")
const PermissionBroker := preload("res://addons/godot_agent/session/permission_broker.gd")
const AgentLog := preload("res://addons/godot_agent/core/agent_log.gd")
const ToolRegistry := preload("res://addons/godot_agent/mcp/tool_registry.gd")
const McpTool := preload("res://addons/godot_agent/mcp/mcp_tool.gd")
const RunTools := preload("res://addons/godot_agent/mcp/tools/run_tools.gd")
const RegressionsWorkflow := preload("res://addons/godot_agent/review/regressions_workflow.gd")

const M := SessionModel.HarnessMode
const PROJECT := "/tmp/project"
const OPTIONS := [
	{"optionId": "allow", "name": "Allow", "kind": "allow_once"},
	{"optionId": "always", "name": "Always", "kind": "allow_always"},
	{"optionId": "reject", "name": "Reject", "kind": "reject_once"},
]
## Las tools de grupos que escriben y no dicen dónde: en un modo con archivos limitados se rechazan.
const UNDECLARED: PackedStringArray = ["asset_install", "install_extension", "restart_editor"]
const TOOLS_DIR := "res://addons/godot_agent/mcp/tools"


func _levels(base: String = "build", extra: Dictionary = {}) -> Dictionary:
	var data := {"name": "Levels", "base": base, "editable": ["res://levels/**", "*.gdshader"], "instructions": "Reuse the props in res://props/."}
	data.merge(extra, true)
	var parsed := ProjectModes.from_data(data, "res://agent_modes/levels.json")
	assert_eq(parsed.errors, PackedStringArray(), "el modo de prueba es válido")
	return parsed.mode


func test_parse() -> void:
	var mode := _levels()
	assert_eq([mode.slug, mode.name, mode.base, mode.shell], ["levels", "Levels", "build", "ask"], "campos y shell por defecto")
	assert_eq(mode.editable, PackedStringArray(["res://levels/**", "*.gdshader"]), "globs")
	var cases := {
		"base inválida": [{"name": "X", "base": "oneshot"}, "«base»"],
		"sin nombre": [{"base": "build"}, "«name» is missing"],
		"campo desconocido": [{"name": "X", "base": "ask", "model": "opus"}, "Unknown field «model»"],
		"glob con ..": [{"name": "X", "base": "ask", "editable": ["res://../secret/**"]}, "«..»"],
		"glob absoluto": [{"name": "X", "base": "ask", "editable": ["/etc/**"]}, "res://"],
		"glob de otro esquema": [{"name": "X", "base": "ask", "editable": ["user://saves/**"]}, "res://"],
		"glob que no es texto": [{"name": "X", "base": "ask", "editable": [3]}, "must be text"],
		"editable no lista": [{"name": "X", "base": "ask", "editable": "res://a/**"}, "list"],
		"shell inválida": [{"name": "X", "base": "ask", "shell": "maybe"}, "«shell»"],
		"versión nueva": [{"name": "X", "base": "ask", "version": 9}, "newer version"],
		"instrucciones largas": [{"name": "X", "base": "ask", "instructions": "a".repeat(ProjectModes.MAX_INSTRUCTIONS_CHARS + 1)}, "too long"],
	}
	for label: String in cases:
		var parsed := ProjectModes.from_data(cases[label][0], "res://agent_modes/x.json")
		var errors := "\n".join(parsed.errors)
		assert_true(errors.contains(str(cases[label][1])), "%s · %s" % [label, errors])
	assert_eq(ProjectModes.from_data({"name": "X", "base": "nope"}).mode.base, "ask", "con base inválida queda el más restrictivo")
	assert_true(ProjectModes.parse("{not json").errors[0].contains("Not valid JSON"), "JSON roto")


func test_load_dir() -> void:
	var dir := "user://test_project_modes"
	DirAccess.make_dir_recursive_absolute(dir)
	var files := {"a.json": {"name": "Levels", "base": "build"}, "b.json": {"name": "levels", "base": "ask"}, "c.json": {"name": "Broken", "base": "x"}, "note.txt": {}}
	for file: String in files:
		var f := FileAccess.open(dir.path_join(file), FileAccess.WRITE)
		f.store_string(JSON.stringify(files[file]))
		f.close()
	var loaded := ProjectModes.load_dir(dir)
	assert_eq(loaded.size(), 3, "solo los .json")
	var with_errors := loaded.filter(func(item: Dictionary) -> bool: return not (item.errors as PackedStringArray).is_empty())
	assert_eq(with_errors.size(), 2, "el nombre repetido y la base rota")
	var usable := ProjectModes.usable(loaded)
	assert_eq(usable.size(), 1, "se elige solo el válido")
	assert_eq(ProjectModes.find(usable, "LEVELS").slug, "a", "por nombre sin mayúsculas")
	assert_eq(ProjectModes.find(usable, "a").name, "Levels", "por slug")
	for file: String in files:
		DirAccess.remove_absolute(dir.path_join(file))
	DirAccess.remove_absolute(dir)
	assert_eq(ProjectModes.load_dir("user://no_such_dir").size(), 0, "sin carpeta, sin modos")


func test_allows_write() -> void:
	var mode := _levels()
	var cases := {
		"res://levels/one.tscn": true,
		"res://levels/deep/two/three.tres": true,
		PROJECT + "/levels/abs.tscn": true,
		"file://" + PROJECT + "/levels/f.tscn": true,
		"res://shaders/water.gdshader": true,  # glob sin «/»: en cualquier carpeta
		"res://player.gd": false,
		"res://levels_old/a.tscn": false,
		"res://agent_modes/levels.json": false,
		"res://agent_modes/other.json": false,
		"/tmp/elsewhere/levels/a.tscn": false,
		PROJECT + "/../project/levels/escape.tscn": true,  # simplifica a la misma carpeta
		PROJECT + "/../other/levels/a.tscn": false,
		"res://../levels/a.tscn": false,
	}
	for path: String in cases:
		assert_eq(ProjectModes.allows_write(mode, path, PROJECT), cases[path], path)
	var everything := _levels("build", {"editable": ["res://**"]})
	assert_false(ProjectModes.allows_write(everything, "res://agent_modes/levels.json", PROJECT), "la carpeta del modo nunca, ni con res://**")
	assert_true(ProjectModes.allows_write(everything, "res://anything.gd", PROJECT), "el resto sí")
	var unlimited: Dictionary = ProjectModes.from_data({"name": "Free", "base": "build"}).mode
	assert_false(ProjectModes.limits_files(unlimited), "sin editable no limita")
	assert_true(ProjectModes.allows_write(unlimited, "/anywhere/x", PROJECT), "y deja todo (lo decide el base)")
	assert_eq(ProjectModes.first_refused(mode, PackedStringArray(["res://levels/a.tscn", "res://main.tscn"]), PROJECT), "res://main.tscn", "la primera rechazada")


func _controller(mode: Dictionary, base: int = -1) -> SessionController:
	var controller := SessionController.new()
	controller.setup(SessionModel.new(), AgentLog.new(), PROJECT)
	if not mode.is_empty():
		controller.model.set_project_mode(mode)
	if base >= 0:
		controller.model.set_harness_mode(base)
	return controller


func test_session_model_layer() -> void:
	var model := SessionModel.new()
	var changes: Array = []
	model.project_mode_changed.connect(func(mode: Dictionary) -> void: changes.append(mode.get("name", "")))
	model.set_harness_mode(M.ASK)
	model.set_project_mode(_levels("auto"))
	assert_eq(model.harness_mode, M.AUTO, "pasa al base")
	assert_eq(changes, ["Levels"], "avisa")
	assert_eq(model.mode_display(), "Levels (Auto)", "nombre y base")
	model.set_harness_mode(M.BUILD)  # aprobar un plan, una receta
	assert_eq(model.project_mode.get("name"), "Levels", "la capa sigue si el harness cambia el base")
	assert_eq(model.mode_display(), "Levels (Build)", "con el base nuevo")
	model.set_project_mode({})
	assert_true(model.project_mode.is_empty(), "el usuario la saca")
	assert_eq(model.harness_mode, M.BUILD, "y el base queda")
	assert_eq(changes, ["Levels", ""], "avisa al sacarla")


## La capa nunca da más permisos que el base, en ningún grupo ni base (y con cualquier `shell`).
func test_layer_never_grants_more() -> void:
	var rank := {PermissionPolicy.DENY: 0, PermissionPolicy.ASK: 1, PermissionPolicy.ALLOW: 2}
	var groups := Array(PermissionPolicy.GROUPS) + [PermissionPolicy.mcp_group("filesystem")]
	for shell: String in ProjectModes.SHELLS:
		for editable: Array in [[], ["res://levels/**"]]:
			for base: String in ProjectModes.BASES:
				var controller := _controller(_levels(base, {"shell": shell, "editable": editable}))
				var broker := controller.permissions
				for group: String in groups:
					var plain := broker.policy.decide(group, controller.model.harness_mode)
					var layered := broker.decide(group)
					assert_true(rank[layered] <= rank[plain], "%s/%s/%s/%s: %s → %s" % [base, shell, editable, group, plain, layered])


func test_shell_layer() -> void:
	var broker := _controller(_levels("auto")).permissions
	assert_eq(broker.decide(PermissionPolicy.GROUP_SHELL), PermissionPolicy.ASK, "Auto con archivos limitados: la shell pregunta")
	assert_eq(broker.decide(PermissionPolicy.GROUP_PROJECT_TOOLS), PermissionPolicy.ASK, "las tools del proyecto también")
	assert_eq(broker.decide(PermissionPolicy.mcp_group("filesystem")), PermissionPolicy.ASK, "y los MCP de terceros")
	assert_eq(broker.decide(PermissionPolicy.GROUP_EDIT_FILES), PermissionPolicy.ALLOW, "editar sigue al base (las rutas las revisa aparte)")
	assert_eq(broker.decide(PermissionPolicy.GROUP_RUN), PermissionPolicy.ALLOW, "correr el juego sigue al base")
	assert_eq(_controller(_levels("auto", {"shell": "deny"})).permissions.decide(PermissionPolicy.GROUP_SHELL), PermissionPolicy.DENY, "shell: deny")
	assert_eq(_controller(_levels("auto", {"shell": "base"})).permissions.decide(PermissionPolicy.GROUP_SHELL), PermissionPolicy.ASK, "shell: base, la matriz de Auto (pregunta y las reglas deciden)")
	assert_false(_controller(_levels("auto", {"shell": "base"})).permissions.mode_forces_ask(PermissionPolicy.GROUP_SHELL), "con base, las reglas de Auto valen")
	var unlimited: Dictionary = ProjectModes.from_data({"name": "Free", "base": "auto"}).mode
	assert_false(_controller(unlimited).permissions.mode_forces_ask(PermissionPolicy.GROUP_SHELL), "sin archivos limitados, la shell sigue al base")
	assert_eq(_controller(_levels("ask")).permissions.decide(PermissionPolicy.GROUP_SHELL), PermissionPolicy.DENY, "lo que el base niega sigue negado")


func _wait() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	for i in 3:
		await tree.process_frame


func _request(controller: SessionController, id: String, kind: String, raw: Dictionary) -> Variant:
	return await controller.permissions.call(&"on_request_permission", {"sessionId": "s", "toolCall": {"toolCallId": id, "kind": kind, "title": "Edit", "rawInput": raw}, "options": OPTIONS})


func test_agent_writes() -> void:
	var controller := _controller(_levels("auto"))
	var model := controller.model
	var result: Variant = await _request(controller, "e1", "edit", {"file_path": PROJECT + "/player.gd"})
	assert_eq(str(result.outcome.get("optionId", "")), "reject", "fuera de los archivos del modo: rechazada")
	assert_true(model.pending_permissions.is_empty(), "sin tarjeta")
	var notice: String = model.entries().back().text
	assert_true(notice.contains("«Levels»") and notice.contains("res://levels/**") and notice.contains("player.gd"), "el aviso dice el modo, lo que edita y el archivo · %s" % notice)
	result = await _request(controller, "e2", "edit", {"file_path": PROJECT + "/levels/one.gd"})
	assert_eq(str(result.outcome.get("optionId", "")), "allow", "dentro, Auto lo deja")
	result = await _request(controller, "e3", "delete", {"path": PROJECT + "/levels/../main.gd"})
	assert_eq(str(result.outcome.get("optionId", "")), "reject", "con .. hacia afuera, rechazada")
	result = await _request(controller, "e4", "edit", {"content": "x"})
	assert_eq(str(result.outcome.get("optionId", "")), "reject", "sin ruta no se puede revisar: rechazada")
	result = await _request(controller, "e5", "edit", {"file_path": PROJECT + "/agent_modes/levels.json"})
	assert_eq(str(result.outcome.get("optionId", "")), "reject", "su propio .json, nunca")
	# Construir: dentro pregunta como siempre. (Las .tscn a mano las rechaza el guard de D48 en todo modo.)
	model.set_harness_mode(M.BUILD)
	var answers: Array = []
	var ask := func() -> void: answers.append(await _request(controller, "e6", "edit", {"file_path": PROJECT + "/levels/two.gd"}))
	ask.call()
	assert_eq(model.pending_permissions.size(), 1, "en Construir, dentro pregunta")
	model.pending_permissions[0].select("allow")
	await _wait()
	assert_eq(str(answers[0].outcome.get("optionId", "")), "allow", "permitido")
	# fs/write_text_file
	assert_false(await controller.permissions.authorize_fs_write(PROJECT + "/main.gd", "", "x"), "fs/write fuera: false")
	assert_true(model.pending_permissions.is_empty(), "sin tarjeta")
	model.set_harness_mode(M.AUTO)
	assert_true(await controller.permissions.authorize_fs_write(PROJECT + "/levels/a.gd", "", "x"), "fs/write dentro, en Auto: true")
	# Sin modo del proyecto, como antes.
	model.set_project_mode({})
	result = await _request(controller, "e7", "edit", {"file_path": PROJECT + "/player.gd"})
	assert_eq(str(result.outcome.get("optionId", "")), "allow", "sin capa, Auto edita todo")


func test_shell_asks_in_auto() -> void:
	var controller := _controller(_levels("auto"))
	var model := controller.model
	var answers: Array = []
	var ask := func() -> void: answers.append(await _request(controller, "s1", "execute", {"command": "cat a.tres"}))
	ask.call()
	assert_eq(model.pending_permissions.size(), 1, "cat está en la allowlist de Auto, pero el modo pregunta")
	var request: PermissionRequest = model.pending_permissions[0]
	assert_eq(request.rule_pattern, "", "sin regla de Auto propuesta")
	assert_true(request.option_id_for([PermissionRequest.KIND_ALLOW_ALWAYS]).is_empty(), "sin «siempre»")
	request.select("allow")
	await _wait()
	assert_eq(str(answers[0].outcome.get("optionId", "")), "allow", "el usuario la deja")
	# terminal/create
	var pending: Array = []
	var run := func() -> void: pending.append(await controller.permissions.authorize_terminal_command("ls", PROJECT))
	run.call()
	assert_eq(model.pending_permissions.size(), 1, "terminal/create también pregunta")
	request = model.pending_permissions[0]
	assert_eq(request.rule_pattern, "", "sin regla")
	request.select(request.option_id_for([PermissionRequest.KIND_REJECT_ONCE]))
	await _wait()
	assert_true(str(pending[0]).contains("denied"), "rechazado · %s" % pending[0])
	# godot.* del grupo shell (build_extension) por authorize
	var authorized: Array = []
	var godot_shell := func() -> void: authorized.append(await controller.permissions.authorize(PermissionPolicy.GROUP_SHELL, "godot.build_extension", "scons"))
	godot_shell.call()
	assert_eq(model.pending_permissions.size(), 1, "authorize de una godot.* de shell pregunta")
	assert_true(model.pending_permissions[0].option_id_for([PermissionRequest.KIND_ALLOW_ALWAYS]).is_empty(), "sin «siempre»")
	model.pending_permissions[0].select(model.pending_permissions[0].option_id_for([PermissionRequest.KIND_ALLOW_ONCE]))
	await _wait()
	assert_eq(authorized, [true], "permitido una vez")
	var denied := _controller(_levels("auto", {"shell": "deny"}))
	assert_true(str(await denied.permissions.authorize_terminal_command("ls", PROJECT)).contains("denied"), "shell: deny, sin tarjeta")
	assert_true(denied.model.pending_permissions.is_empty(), "sin tarjeta")
	assert_true(denied.model.entries().back().text.contains("Levels (Auto)"), "el aviso nombra el modo del proyecto · %s" % denied.model.entries().back().text)


var _providers: Array = []


func _all_tools() -> Array:
	var result: Array = []
	for file: String in DirAccess.get_files_at(TOOLS_DIR):
		if not file.ends_with("_tools.gd"):
			continue
		var provider: Object = (load(TOOLS_DIR.path_join(file)) as Script).new()
		if &"run_tools" in provider:  # profile_tools copia el esquema de run_scene
			provider.set(&"run_tools", RunTools.new())
		if provider.has_method(&"tools"):
			_providers.append(provider)  # como el registro: un Callable a un método no retiene al provider
			result.append_array(provider.call(&"tools"))
	return result


## Falla cerrada: cada tool de un grupo que escribe declara dónde escribe, salvo las de UNDECLARED, que
## en un modo con archivos limitados se rechazan.
func test_writing_tools_declare_targets() -> void:
	var registry := ToolRegistry.new()
	var tools := _all_tools()
	assert_true(tools.size() > 60, "se cargaron las tools (%d)" % tools.size())
	for tool: McpTool in tools:
		registry.register(tool)
		if not tool.group in ToolRegistry.WRITE_GROUPS:
			continue
		if tool.name in UNDECLARED:
			assert_false(tool.write_targets.is_valid(), "%s no dice dónde escribe" % tool.name)
			assert_false(registry.write_targets(tool.name, {}).declared, "%s: sin declarar, el modo la rechaza" % tool.name)
		else:
			assert_true(tool.write_targets.is_valid(), "%s (%s) declara qué escribe" % [tool.name, tool.group])
	assert_true(registry.write_targets("list_files", {}).declared, "una de lectura no escribe nada")
	var cases := {
		["create_scene", {"path": "res://levels/a.tscn", "root_type": "Node2D", "script_path": "res://a.gd"}]: ["res://levels/a.tscn", "res://a.gd"],
		["copy_file", {"from": "res://x.png", "to": "res://levels/x.png"}]: ["res://levels/x.png"],
		["move_file", {"from": "res://x.png", "to": "res://levels/x.png"}]: ["res://x.png", "res://levels/x.png"],
		["delete_file", {"path": "res://y.gd"}]: ["res://y.gd"],
		["create_resource", {"path": "res://levels/r.tres", "type": "Resource"}]: ["res://levels/r.tres"],
		["set_resource_properties", {"path": "res://levels/r.tres", "properties": {}}]: ["res://levels/r.tres"],
		["set_project_setting", {"name": "a", "value": 1}]: ["res://project.godot"],
		["set_autoload", {"name": "A", "path": "res://levels/a.gd"}]: ["res://project.godot"],
		["plugin_enable", {"plugin": "x"}]: ["res://project.godot"],
		["write_regressions_workflow", {}]: [RegressionsWorkflow.PATH],
		["save_scene", {"path": "res://levels/b.tscn"}]: ["res://levels/b.tscn"],
		["add_node", {"parent": ".", "type": "Node", "scene": "res://levels/c.tscn"}]: ["res://levels/c.tscn"],
		["attach_script", {"node_path": ".", "script_path": "res://levels/c.gd", "scene": "res://levels/c.tscn"}]: ["res://levels/c.tscn", "res://levels/c.gd"],
		["open_scene", {"path": "res://main.tscn"}]: [],
		["export_project", {"preset": "Linux"}]: [],
	}
	for key: Array in cases:
		var targets: Dictionary = registry.write_targets(key[0], key[1])
		assert_true(targets.declared, "%s declarada" % key[0])
		assert_eq(Array(targets.paths), cases[key], key[0])


func test_system_prompt() -> void:
	var controller := _controller(_levels("build"))
	var prompt := controller.system_prompt()
	assert_true(prompt.contains("Levels (a project mode based on Build)"), "el nombre del modo")
	assert_true(prompt.contains("you may only write files matching res://levels/**, *.gdshader"), "los archivos")
	assert_true(prompt.contains("shell commands always ask the user"), "la shell")
	assert_true(prompt.contains("Project mode instructions («Levels»") and prompt.contains("Reuse the props in res://props/."), "las instrucciones")
	assert_true(prompt.contains(SessionController.MODE_RULES[M.BUILD]), "y las reglas del base")
	controller.model.set_project_mode({})
	assert_false(controller.system_prompt().contains("Project mode"), "sin modo, nada")


func test_prompt_resent_on_project_mode_change() -> void:
	var controller := _controller({})
	controller.model.set_harness_mode(M.BUILD)
	controller.set(&"_system_prompt_sent", true)
	controller.model.set_project_mode(_levels("build"))
	assert_false(controller.get(&"_system_prompt_sent"), "mismo base: el system prompt vuelve igual")
