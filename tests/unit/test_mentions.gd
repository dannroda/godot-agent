extends "test_case.gd"
## Menciones que traen contexto (m11-08): @errors, @output, @game y @docs:Clase.

const AgentDock := preload("res://addons/godot_agent/ui/dock/agent_dock.gd")
const ToolRegistry := preload("res://addons/godot_agent/mcp/tool_registry.gd")
const McpTool := preload("res://addons/godot_agent/mcp/mcp_tool.gd")


## m13-29: la línea de una máquina en el tooltip del encabezado.
func test_machine_line() -> void:
	assert_eq(AgentDock.machine_line("Game", "running", 12), "Game: running · 12 s", "máquina, estado y antigüedad")
	assert_eq(AgentDock.machine_line("Game", "no game launched", -1), "Game: no game launched", "sin antigüedad")


func test_special_mentions_in() -> void:
	var found := AgentDock.special_mentions_in("why @errors? see @game and @docs:CharacterBody2D, again @errors")
	assert_eq(found.map(func(m: Dictionary) -> String: return "%s|%s|%s" % [m.token, m.kind, m.arg]),
		["errors|errors|", "game|game|", "docs:CharacterBody2D|docs|CharacterBody2D"], "sin repetir, con la clase")
	assert_eq(AgentDock.special_mentions_in("mail me@errors.com, @Player/errors, @output_node"), [], "ni un mail ni un nodo que se llama parecido")
	assert_eq(AgentDock.special_mentions_in("@output").size(), 1, "al principio")
	assert_eq(AgentDock.special_mention_options().map(func(o: Dictionary) -> String: return o.insert), ["errors", "output", "game", "docs:"], "en el menú de @")


## Revisión m13-12-26 (#30): el prompt de «Fix with the agent» trae el error del juego tal cual; si el
## error dice «@game» no tiene que ir a buscar el árbol del juego como si lo hubiera pedido el usuario.
func test_harness_prompts_are_not_expanded() -> void:
	var run_error_watcher: GDScript = load("res://addons/godot_agent/editor/run_error_watcher.gd")
	var harness_prompts: GDScript = load("res://addons/godot_agent/session/harness_prompts.gd")
	var label: String = harness_prompts.RUN_ERROR
	var text: String = run_error_watcher.prompt({"breaked": true, "reason": "Invalid call on @game and @errors", "lines": PackedStringArray(["#1 [game/error] res://a.gd:3 — see @output"]), "count": 1})
	assert_true(text.contains("@game") and AgentDock.special_mentions_in(text).size() == 3, "el error trae las menciones · " + text)
	assert_eq(AgentDock.mentions_to_expand(text, label), [], "con la etiqueta del harness, ninguna se expande")
	assert_eq(AgentDock.mentions_to_expand("look at @game", "").size(), 1, "lo que escribió el usuario sí")
	var controller: Object = (load("res://addons/godot_agent/session/session_controller.gd") as GDScript).new()
	controller.label_prompt(text, label)
	assert_eq(AgentDock.mentions_to_expand(text, controller.prompt_label(text)), [], "la etiqueta sale del controller, como en _send_with_mentions")


func test_run_for_user() -> void:
	var registry := ToolRegistry.new()
	var tool := McpTool.create("probe", "diagnostics", "probe", {}, [], func(_args: Dictionary) -> String: return "3 errors")
	registry.register(tool)
	registry.authorizer = func(_group: String, _title: String, _description: String) -> bool: return false
	assert_eq(await registry.run_for_user("probe", {}), "3 errors", "sin pedir permiso")
	assert_eq(await registry.run_for_user("missing", {}), "", "una tool que no existe")
