extends "test_case.gd"
## MCP servers de terceros (m7-34) y su grupo de permisos (m7-35).

const ExternalMcpServers := preload("res://addons/godot_agent/mcp/external_mcp_servers.gd")
const PermissionPolicy := preload("res://addons/godot_agent/session/permission_policy.gd")
const SessionModel := preload("res://addons/godot_agent/session/session_model.gd")
const McpServersPage := preload("res://addons/godot_agent/ui/settings/mcp_servers_page.gd")

const M := SessionModel.HarnessMode


func test_to_acp_stdio_and_http() -> void:
	OS.set_environment("GODOT_AGENT_TEST_TOKEN", "s3cr3t-value")
	var stdio := ExternalMcpServers.normalize({"name": "blender", "command": "uvx", "args": ["blender-mcp", "--port=${GODOT_AGENT_TEST_PORT}"], "env": {"API_KEY": "$GODOT_AGENT_TEST_TOKEN", "MODE": "fast"}})
	OS.set_environment("GODOT_AGENT_TEST_PORT", "9876")
	assert_eq(ExternalMcpServers.to_acp(stdio, true), {
		"name": "blender", "command": "uvx", "args": ["blender-mcp", "--port=9876"],
		"env": [{"name": "API_KEY", "value": "s3cr3t-value"}, {"name": "MODE", "value": "fast"}],
	}, "stdio: $VAR y ${VAR} se resuelven, env como pares de ACP")
	var http := ExternalMcpServers.normalize({"name": "sentry", "transport": "http", "url": "https://mcp.example.com/mcp", "headers": {"Authorization": "Bearer $GODOT_AGENT_TEST_TOKEN"}})
	assert_eq(ExternalMcpServers.to_acp(http, true), {
		"type": "http", "name": "sentry", "url": "https://mcp.example.com/mcp",
		"headers": [{"name": "Authorization", "value": "Bearer s3cr3t-value"}],
	}, "http con el header resuelto")
	assert_eq(ExternalMcpServers.to_acp(http, false), {}, "http no va si el agente no lo soporta")
	stdio.enabled = false
	assert_eq(ExternalMcpServers.to_acp(stdio, true), {}, "apagado no va")
	assert_eq(ExternalMcpServers.secret_values(http), PackedStringArray(["s3cr3t-value"]), "el log tapa lo que salió de una variable")
	assert_eq(ExternalMcpServers.expand("a $GODOT_AGENT_TEST_NONE b"), "a  b", "variable que no está → vacío")


func test_validate() -> void:
	var ok := ExternalMcpServers.make("blender")
	ok.command = "uvx"
	assert_eq(ExternalMcpServers.validate([ok]), "", "válido")
	var cases := {
		"sin nombre": ExternalMcpServers.make(""),
		"nombre con espacios": ExternalMcpServers.make("mi server"),
		"godot reservado": ExternalMcpServers.make("godot"),
		"stdio sin comando": ExternalMcpServers.make("x"),
		"http sin URL": ExternalMcpServers.make("x", ExternalMcpServers.TRANSPORT_HTTP),
	}
	for label: String in cases:
		var entry: Dictionary = cases[label]
		if entry.transport == ExternalMcpServers.TRANSPORT_STDIO and label != "stdio sin comando":
			entry.command = "uvx"
		assert_false(ExternalMcpServers.validate([entry]).is_empty(), label)
	assert_false(ExternalMcpServers.validate([ok, ok.duplicate()]).is_empty(), "nombre repetido")
	var secret := ok.duplicate(true)
	secret.env = {"API_KEY": "sk-123"}
	assert_false(ExternalMcpServers.validate([secret]).is_empty(), "clave escrita a mano")
	secret.env = {"API_KEY": "$MY_KEY"}
	assert_eq(ExternalMcpServers.validate([secret]), "", "clave por variable")


func test_merge_project_wins() -> void:
	var user := ExternalMcpServers.make("blender")
	user.command = "user-cmd"
	var other := ExternalMcpServers.make("db")
	var project := ExternalMcpServers.make("blender")
	project.command = "project-cmd"
	var merged := ExternalMcpServers.merge([user, other], [project])
	assert_eq(merged.size(), 2, "un server por nombre")
	assert_eq(merged.filter(func(entry: Dictionary) -> bool: return entry.name == "blender")[0].command, "project-cmd", "gana el del proyecto")


func test_from_mcp_json() -> void:
	var text := JSON.stringify({"mcpServers": {
		"blender": {"command": "uvx", "args": ["blender-mcp"]},
		"remote": {"type": "http", "url": "https://x.example/mcp", "headers": {"X-Key": "$K"}},
		"old": {"url": "https://y.example/sse"},
		"bad": "no",
	}})
	var servers := ExternalMcpServers.from_mcp_json(text)
	var by_name: Dictionary = {}
	for entry: Dictionary in servers:
		by_name[entry.name] = entry
	assert_eq(by_name.size(), 3, "el que no es un objeto se salta")
	assert_eq([by_name.blender.transport, by_name.remote.transport, by_name.old.transport], ["stdio", "http", "http"], "stdio, http y url sola")
	assert_eq(by_name.blender.args, ["blender-mcp"], "args")
	assert_eq(by_name.remote.headers, {"X-Key": "$K"}, "headers")
	assert_eq(ExternalMcpServers.from_mcp_json("{}"), [], "sin mcpServers")


func test_tool_names() -> void:
	assert_eq(ExternalMcpServers.server_of_tool("mcp__blender__get_objects_summary"), "blender", "server")
	assert_eq(ExternalMcpServers.server_of_tool("mcp__godot__add_node"), "", "el del addon no es de terceros")
	assert_eq(ExternalMcpServers.server_of_tool("Bash"), "", "no MCP")
	assert_eq(ExternalMcpServers.server_of_tool("mcp__broken"), "", "sin tool")
	assert_eq(ExternalMcpServers.short_tool_name("mcp__blender__get_objects_summary"), "blender.get_objects_summary", "nombre corto")
	assert_eq(ExternalMcpServers.short_tool_name("mcp__godot__add_node"), "godot.add_node", "también el del addon")
	assert_eq(ExternalMcpServers.short_tool_name("Read"), "Read", "otro queda igual")


func test_policy_groups_per_server() -> void:
	var call := {"title": "mcp__blender__get_objects_summary", "kind": "other"}
	assert_eq(PermissionPolicy.group_for_tool_call(call), "mcp:blender", "grupo por título")
	var by_meta := {"title": "Get objects", "kind": "other", "_meta": {"claudeCode": {"toolName": "mcp__db__query"}}}
	assert_eq(PermissionPolicy.group_for_tool_call(by_meta), "mcp:db", "grupo por el toolName de Claude Code")
	assert_eq(PermissionPolicy.group_for_tool_call({"title": "mcp__godot__add_node", "kind": "other"}), "other", "godot no cambia")
	assert_eq(PermissionPolicy.group_label("mcp:blender"), "MCP · blender", "etiqueta")
	var policy := PermissionPolicy.new({"mcp:blender": {"oneshot": "allow"}, "bogus": {"oneshot": "allow"}})
	assert_eq(policy.decide("mcp:blender", M.ONESHOT), "allow", "override por server")
	assert_eq(policy.decide("mcp:blender", M.BUILD), "ask", "sin override: ask")
	assert_eq(policy.decide("mcp:db", M.ONESHOT), "ask", "otro server: ask")
	assert_eq(policy.decide("bogus", M.ONESHOT), "ask", "grupo desconocido sigue en ask aunque tenga override")
	policy.grant_for_session("mcp:db")
	assert_eq(policy.decide("mcp:db", M.BUILD), "allow", "«siempre en esta sesión» vale solo para ese server")
	assert_eq(policy.decide("mcp:other", M.BUILD), "ask", "y no para los demás")


func test_settings_page_round_trip() -> void:
	var page := McpServersPage.new()
	var project := ExternalMcpServers.make("blender")
	project.command = "uvx"
	var user := ExternalMcpServers.make("db", ExternalMcpServers.TRANSPORT_HTTP)
	user.url = "https://db.example/mcp"
	page.load_from([user], [project])
	assert_eq(page.project_servers(), [project], "proyecto")
	assert_eq(page.user_servers(), [user], "usuario")
	assert_eq(page.server_names(), PackedStringArray(["blender", "db"]), "nombres")
	assert_eq(page.validate(), "", "válido")
	var added := page.import_mcp_json(JSON.stringify({"mcpServers": {"blender": {"command": "x"}, "godot": {"command": "x"}, "fs": {"command": "npx", "args": ["fs-mcp"]}}}))
	assert_eq(added, 1, "importa solo los que faltan, sin godot")
	assert_eq(page.project_servers().size(), 2, "el importado va al proyecto")
	page.free()
