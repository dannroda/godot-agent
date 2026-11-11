extends "test_case.gd"
## Tools propias del proyecto (m11-46): qué se aprueba, que una sin aprobar no se carga, los errores de
## una tool mal armada, lo que devuelve _run y cómo entran al registro (godot.methods / godot.run).

const ProjectToolLoader := preload("res://addons/godot_agent/mcp/project_tool_loader.gd")
const ToolRegistry := preload("res://addons/godot_agent/mcp/tool_registry.gd")
const McpTool := preload("res://addons/godot_agent/mcp/mcp_tool.gd")
const PermissionPolicy := preload("res://addons/godot_agent/session/permission_policy.gd")
const SessionModel := preload("res://addons/godot_agent/session/session_model.gd")
const AgentTool := preload("res://addons/godot_agent/api/agent_tool.gd")

const PROJECT := "/p/game"
const HEADER := "@tool\nextends \"res://addons/godot_agent/api/agent_tool.gd\"\n"

var _approved: Dictionary = {}


func _tool_source(description: String, run_body: String, parameters := "{\"properties\": {\"text\": {\"type\": \"string\"}}, \"required\": [\"text\"]}") -> String:
	return HEADER + "\nfunc _description() -> String:\n\treturn \"%s\"\n\nfunc _parameters() -> Dictionary:\n\treturn %s\n\nfunc _run(args: Dictionary, ctx: RefCounted) -> Variant:\n%s\n" % [description, parameters, run_body]


func _write(path: String, text: String) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()


func _loader(dir: String) -> ProjectToolLoader:
	_approved.clear()
	var loader := ProjectToolLoader.new()
	loader.dir = dir
	loader.project_dir = PROJECT
	loader.is_approved = func(key: String) -> bool: return _approved.has(key)
	loader.reserved = func(tool_name: String) -> bool: return tool_name == "get_errors"
	return loader


func _approve_all(loader: ProjectToolLoader) -> void:
	for item: Dictionary in loader.held():
		_approved[item.key] = true
	loader.refresh()


func _by_name(loader: ProjectToolLoader) -> Dictionary:
	var result := {}
	for entry: Dictionary in loader.entries():
		result[entry.name] = entry
	return result


func _clean(dir: String) -> String:
	var path := temp_dir(dir)
	for sub: String in DirAccess.get_directories_at(path):
		for file: String in DirAccess.get_files_at(path.path_join(sub)):
			DirAccess.remove_absolute(path.path_join(sub).path_join(file))
		DirAccess.remove_absolute(path.path_join(sub))
	return path


func test_resolve_dir() -> void:
	assert_eq(ProjectToolLoader.resolve_dir(""), "res://agent_tools", "vacío: la de siempre")
	assert_eq(ProjectToolLoader.resolve_dir("tools/agent/"), "res://tools/agent", "relativa a res://")
	assert_eq(ProjectToolLoader.resolve_dir("res://addons/godot_agent/x"), "res://agent_tools", "nunca adentro del addon")
	assert_eq(ProjectToolLoader.resolve_dir("res://"), "res://agent_tools", "nunca la raíz")
	assert_eq(ProjectToolLoader.normalize_dir("res://../outside"), "", "fuera del proyecto, no")
	assert_eq(ProjectToolLoader.normalize_dir(".godot/x"), "", "carpetas con punto, no")
	assert_eq(ProjectToolLoader.normalize_dir("res://agent_tools/"), "res://agent_tools", "la de siempre, escrita entera")
	assert_eq(ProjectToolLoader.export_filter("res://tools/agent"), "tools/agent/*", "el filtro del preset")


func test_unapproved_never_loads() -> void:
	var dir := _clean("project_tools_held")
	var marker := ProjectSettings.globalize_path(dir.path_join("loaded.txt"))
	# Si el script se cargara, el static var escribiría la marca.
	var source := HEADER + "\nstatic var _side_effect := FileAccess.open(\"%s\", FileAccess.WRITE)\n\nfunc _description() -> String:\n\treturn \"Echo.\"\n\nfunc _run(args: Dictionary, ctx: RefCounted) -> Variant:\n\treturn \"ok\"\n" % marker
	_write(dir.path_join("sneaky.gd"), source)
	var loader := _loader(dir)
	assert_true(loader.refresh(), "aparece una tool")
	assert_eq(_by_name(loader).sneaky.state, ProjectToolLoader.STATE_HELD, "sin aprobar, frenada")
	assert_false(FileAccess.file_exists(marker), "y nunca se cargó: el static no corrió")
	assert_eq(loader.tools().size(), 0, "no hay tools listas")
	var held: Array = loader.held()
	assert_eq(held.size(), 1, "«Aprobar…» la ofrece")
	assert_true(str(held[0].command).begins_with(dir.path_join("sneaky.gd")) and str(held[0].command).contains("static var"), "el diálogo muestra la ruta y el código")
	assert_false(loader.refresh(), "sin cambios, refresh no cambia nada")


func test_approval_follows_the_code() -> void:
	var dir := _clean("project_tools_key")
	_write(dir.path_join("echo.gd"), _tool_source("Echoes the text.", "\treturn args.text"))
	var loader := _loader(dir)
	loader.refresh()
	var key: String = loader.held()[0].key
	_approve_all(loader)
	assert_eq(_by_name(loader).echo.state, ProjectToolLoader.STATE_READY, "aprobada, se carga")
	_write(dir.path_join("echo.gd"), _tool_source("Echoes the text.", "\treturn args.text + \"!\""))
	assert_true(loader.refresh(), "editar la tool cambia algo")
	assert_eq(_by_name(loader).echo.state, ProjectToolLoader.STATE_HELD, "editada, frenada de nuevo")
	assert_true(_by_name(loader).echo.key != key, "otra clave")
	_approve_all(loader)
	_write(dir.path_join("_helpers/util.gd"), "extends RefCounted\n")
	loader.refresh()
	assert_eq(_by_name(loader).echo.state, ProjectToolLoader.STATE_HELD, "un helper nuevo en la carpeta también la frena")
	assert_false(_by_name(loader).has("util") or _by_name(loader).has("_helpers"), "los helpers no son tools")
	var source := FileAccess.get_file_as_string(dir.path_join("echo.gd"))
	assert_true(ProjectToolLoader.approval_key("/p/other", dir.path_join("echo.gd"), source, "") != ProjectToolLoader.approval_key(PROJECT, dir.path_join("echo.gd"), source, ""), "otro proyecto, otra clave")
	DirAccess.remove_absolute(dir.path_join("echo.gd"))
	loader.refresh()
	assert_false(_by_name(loader).has("echo"), "borrada, desaparece")


func test_broken_tools() -> void:
	var dir := _clean("project_tools_broken")
	_write(dir.path_join("BadName.gd"), _tool_source("x.", "\treturn \"\""))
	_write(dir.path_join("get_errors.gd"), _tool_source("x.", "\treturn \"\""))
	_write(dir.path_join("no_tool.gd"), _tool_source("x.", "\treturn \"\"").trim_prefix("@tool\n"))
	_write(dir.path_join("global.gd"), HEADER.replace("extends", "class_name ProjectToolsTestGlobal\nextends") + "\nfunc _description() -> String:\n\treturn \"x.\"\n")
	_write(dir.path_join("plain.gd"), "@tool\nextends RefCounted\n")
	_write(dir.path_join("silent.gd"), HEADER)
	_write(dir.path_join("bad_schema.gd"), _tool_source("x.", "\treturn \"\"", "{\"properties\": {\"a\": {}}, \"required\": [\"b\"]}"))
	var loader := _loader(dir)
	loader.refresh()
	var entries := _by_name(loader)
	assert_true(str(entries.BadName.error).contains("lowercase"), "nombre inválido: %s" % entries.BadName.error)
	assert_true(str(entries.get_errors.error).contains("already exists"), "choca con el addon")
	_approve_all(loader)
	entries = _by_name(loader)
	assert_true(str(entries.no_tool.error).contains("@tool"), "sin @tool: %s" % entries.no_tool.error)
	assert_true(str(entries.global.error).contains("class_name"), "con class_name: %s" % entries.global.error)
	assert_true(str(entries.plain.error).contains("agent_tool.gd"), "sin la base: %s" % entries.plain.error)
	assert_true(str(entries.silent.error).contains("_description"), "sin descripción: %s" % entries.silent.error)
	assert_true(str(entries.bad_schema.error).contains("required"), "required que no está: %s" % entries.bad_schema.error)
	assert_eq(loader.tools().size(), 0, "ninguna queda lista")


func test_run_results() -> void:
	assert_eq(ProjectToolLoader.result_of("x"), "x", "texto")
	assert_eq(ProjectToolLoader.result_of({"count": 2}), JSON.stringify({"count": 2}, "  "), "un Dictionary va como JSON")
	assert_eq(ProjectToolLoader.result_of(3), "3", "un número, como texto")
	assert_eq(ProjectToolLoader.result_of(null), null, "null queda null: el registro lo da como error")
	var error := AgentTool.error("bad")
	assert_eq(ProjectToolLoader.result_of(error), error, "un resultado MCP pasa tal cual")


func test_registry() -> void:
	var dir := _clean("project_tools_registry")
	_write(dir.path_join("echo.gd"), _tool_source("Echoes the text. Second sentence.", "\tawait Engine.get_main_loop().process_frame\n\treturn \"echo: \" + args.text"))
	_write(dir.path_join("nothing.gd"), HEADER + "\nfunc _description() -> String:\n\treturn \"Returns nothing.\"\n\nfunc _run(args: Dictionary, ctx: RefCounted) -> Variant:\n\treturn null\n")
	var loader := _loader(dir)
	var registry := ToolRegistry.new()
	registry.register(McpTool.create("get_errors", "read", "Errors.", {}, [], func(_a: Dictionary) -> String: return ""))
	loader.reserved = registry.is_builtin
	registry.project_tools = loader
	var asked: Array = []
	registry.authorizer = func(group: String, title: String, description: String) -> bool:
		asked.append([group, title, description])
		return true
	var held: Dictionary = await registry.call_tool("run", {"method": "echo", "params": {"text": "hi"}})
	assert_true(held.isError and str(held.content[0].text).contains("no method"), "sin aprobar, godot.run no la conoce: %s" % held.content[0].text)
	assert_true(asked.is_empty(), "y no pide permiso")
	_approve_all(loader)
	var listed: Dictionary = await registry.call_tool("methods", {"query": "project"})
	assert_true(str(listed.content[0].text).contains("echo(text) [project tool]: Echoes the text."), "godot.methods la lista: %s" % listed.content[0].text)
	var names := PackedStringArray(registry.list().map(func(entry: Dictionary) -> String: return entry.name))
	assert_true("methods" in names and "run" in names and not "echo" in names, "tools/list no la trae, pero sí methods y run aunque no sea compacta: %s" % names)
	var result: Dictionary = await registry.call_tool("run", {"method": "echo", "params": {"text": "hi"}})
	assert_false(result.isError, "corre: %s" % result.content)
	assert_true(str(result.content[0].text).contains("echo: hi"), "con await y el resultado: %s" % result.content[0].text)
	assert_eq(asked[0][0], PermissionPolicy.GROUP_PROJECT_TOOLS, "pide el permiso del grupo project_tools")
	assert_true(str(asked[0][2]).contains(dir.path_join("echo.gd")) and str(asked[0][2]).contains("text: hi"), "la tarjeta dice qué archivo y con qué: %s" % asked[0][2])
	var invalid: Dictionary = await registry.call_tool("run", {"method": "echo", "params": {}})
	assert_true(invalid.isError and str(invalid.content[0].text).contains("text"), "el schema se valida")
	var empty: Dictionary = await registry.call_tool("run", {"method": "nothing", "params": {}})
	assert_true(empty.isError, "un _run sin return es un error para el agente")
	var catalog := registry.catalog().filter(func(entry: Dictionary) -> bool: return entry.name == "echo")
	assert_eq([catalog[0].category, catalog[0].group, catalog[0].extended], [ToolRegistry.PROJECT_CATEGORY, PermissionPolicy.GROUP_PROJECT_TOOLS, true], "en el catálogo, con su categoría")
	_write(dir.path_join("echo.gd"), _tool_source("Echoes louder.", "\treturn \"ECHO\""))
	var after_edit: Dictionary = await registry.call_tool("run", {"method": "echo", "params": {"text": "hi"}})
	assert_true(after_edit.isError, "editada, deja de correr hasta aprobarla (ni la vieja ni la nueva)")
	_approve_all(loader)
	var reloaded: Dictionary = await registry.call_tool("run", {"method": "echo", "params": {"text": "hi"}})
	assert_true(str(reloaded.content[0].text).contains("ECHO"), "aprobada de nuevo, corre la versión nueva: %s" % reloaded.content[0].text)


func test_permission_group() -> void:
	var policy := PermissionPolicy.new()
	var modes := [SessionModel.HarnessMode.ASK, SessionModel.HarnessMode.REVIEW, SessionModel.HarnessMode.BUILD, SessionModel.HarnessMode.ONESHOT, SessionModel.HarnessMode.AUTO]
	var values := modes.map(func(mode: SessionModel.HarnessMode) -> String: return policy.decide(PermissionPolicy.GROUP_PROJECT_TOOLS, mode))
	assert_eq(values, [PermissionPolicy.DENY, PermissionPolicy.DENY, PermissionPolicy.ASK, PermissionPolicy.ASK, PermissionPolicy.ASK], "pregunta en Construir, One-shot y Auto")
	assert_true(PermissionPolicy.GROUP_PROJECT_TOOLS in PermissionPolicy.GROUPS, "está en la matriz")
