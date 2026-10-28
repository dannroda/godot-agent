extends "test_case.gd"
## Menciones que traen contexto (m11-08): @errors, @output, @game y @docs:Clase.

const AgentDock := preload("res://addons/godot_agent/ui/dock/agent_dock.gd")
const ToolRegistry := preload("res://addons/godot_agent/mcp/tool_registry.gd")
const McpTool := preload("res://addons/godot_agent/mcp/mcp_tool.gd")


func test_special_mentions_in() -> void:
	var found := AgentDock.special_mentions_in("why @errors? see @game and @docs:CharacterBody2D, again @errors")
	assert_eq(found.map(func(m: Dictionary) -> String: return "%s|%s|%s" % [m.token, m.kind, m.arg]),
		["errors|errors|", "game|game|", "docs:CharacterBody2D|docs|CharacterBody2D"], "sin repetir, con la clase")
	assert_eq(AgentDock.special_mentions_in("mail me@errors.com, @Player/errors, @output_node"), [], "ni un mail ni un nodo que se llama parecido")
	assert_eq(AgentDock.special_mentions_in("@output").size(), 1, "al principio")
	assert_eq(AgentDock.special_mention_options().map(func(o: Dictionary) -> String: return o.insert), ["errors", "output", "game", "docs:"], "en el menú de @")


func test_run_for_user() -> void:
	var registry := ToolRegistry.new()
	var tool := McpTool.create("probe", "diagnostics", "probe", {}, [], func(_args: Dictionary) -> String: return "3 errors")
	registry.register(tool)
	registry.authorizer = func(_group: String, _title: String, _description: String) -> bool: return false
	assert_eq(await registry.run_for_user("probe", {}), "3 errors", "sin pedir permiso")
	assert_eq(await registry.run_for_user("missing", {}), "", "una tool que no existe")
