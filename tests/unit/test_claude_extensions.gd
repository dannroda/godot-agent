extends "test_case.gd"
## Ventana Extensions (m7-37): parseo de las salidas del CLI de Claude Code.

const ClaudeExtensions := preload("res://addons/godot_agent/extensions/claude_extensions.gd")
const ClaudeCli := preload("res://addons/godot_agent/extensions/claude_cli.gd")
const ExtensionsWindow := preload("res://addons/godot_agent/ui/extensions/extensions_window.gd")
const InstructionsTab := preload("res://addons/godot_agent/ui/extensions/instructions_tab.gd")
const AgentDock := preload("res://addons/godot_agent/ui/dock/agent_dock.gd")

const MCP_LIST := """Checking MCP server health…

claude.ai Claude Docs: https://api.anthropic.com/v1/pages/mcp - ✔ Connected
plugin:design:slack: https://mcp.slack.com/mcp (HTTP) - ! Needs authentication
plugin:design:asana: https://mcp.asana.com/v2/mcp (HTTP) - ✘ Failed to connect — Incompatible auth server: does not support dynamic client registration
plugin:design:google calendar:  (HTTP) - - Not configured
blender: uvx --from git+https://projects.blender.org/lab/blender_mcp.git#subdirectory=mcp blender-mcp - ✔ Connected
shared: npx shared-mcp - ⏸ Pending approval
"""


func test_parse_mcp_list() -> void:
	var servers := ClaudeExtensions.parse_mcp_list(MCP_LIST)
	assert_eq(servers.map(func(server: Dictionary) -> String: return "%s|%s|%s" % [server.name, server.status, server.origin]), [
		"claude.ai Claude Docs|connected|claude.ai",
		"plugin:design:slack|needs_auth|plugin",
		"plugin:design:asana|failed|plugin",
		"plugin:design:google calendar|not_configured|plugin",
		"blender|connected|other",
		"shared|pending|other",
	], "nombre (con : y espacios), estado y origen")
	assert_eq(servers[2].detail, "Incompatible auth server: does not support dynamic client registration", "el motivo del fallo")
	assert_eq(servers[4].target, "uvx --from git+https://projects.blender.org/lab/blender_mcp.git#subdirectory=mcp blender-mcp", "destino")
	assert_eq(ClaudeExtensions.parse_mcp_list("No MCP servers configured."), [], "sin servers")


func test_config_scopes() -> void:
	var dir := ProjectSettings.globalize_path("user://test_claude_extensions")
	DirAccess.make_dir_recursive_absolute(dir.path_join("project"))
	var project := dir.path_join("project")
	_write(dir.path_join(".claude.json"), JSON.stringify({"mcpServers": {"blender": {}}, "projects": {project: {"mcpServers": {"mine": {}}}}}))
	_write(project.path_join(".mcp.json"), JSON.stringify({"mcpServers": {"team": {}}}))
	assert_eq(ClaudeExtensions.config_scopes(dir, project), {"team": "project", "blender": "user", "mine": "local"}, "user, local y project")
	assert_eq(ClaudeExtensions.config_scopes(dir.path_join("nada"), dir.path_join("nada")), {}, "sin archivos")


func test_parse_plugins_and_filter() -> void:
	var text := JSON.stringify({
		"installed": [{"id": "godot@market", "scope": "user", "enabled": true}],
		"available": [
			{"pluginId": "godot@market", "name": "godot", "description": "Godot skills", "marketplaceName": "market", "installCount": 900},
			{"pluginId": "few@market", "name": "few", "description": "Rare one", "marketplaceName": "market", "installCount": 3},
			{"pluginId": "many@other", "name": "many", "description": "Popular godot helper", "marketplaceName": "other", "installCount": 5000},
			{"pluginId": "none@other", "name": "none", "description": "No count", "marketplaceName": "other"},
		],
	})
	var data := ClaudeExtensions.parse_plugins(text)
	assert_eq(data.error, "", "sin error")
	assert_eq(data.installed.size(), 1, "instalados")
	var all := ClaudeExtensions.filter_available(data.available, data.installed, "", 2)
	assert_eq(all.total, 3, "sin el instalado")
	assert_eq(all.items.map(func(plugin: Dictionary) -> String: return plugin.name), ["many", "few"], "por instalaciones y con límite")
	var search := ClaudeExtensions.filter_available(data.available, data.installed, "GODOT", 10)
	assert_eq(search.items.map(func(plugin: Dictionary) -> String: return plugin.name), ["many"], "busca en la descripción, sin mayúsculas")
	assert_eq(ClaudeExtensions.parse_plugins("[]").installed, [], "lista vacía (sin --available)")
	assert_false(ClaudeExtensions.parse_plugins("no json").error.is_empty(), "salida rara")


func test_parse_action() -> void:
	var ok := ClaudeExtensions.parse_action({"code": 0, "stdout": "{\"command\":\"enable\",\"outcome\":\"ok\",\"message\":\"Successfully enabled plugin: x (scope: user)\"}", "stderr": ""})
	assert_eq(ok, {"ok": true, "message": "Successfully enabled plugin: x (scope: user)"}, "ok")
	var already := ClaudeExtensions.parse_action({"code": 1, "stdout": "{\"outcome\":\"failed\",\"message\":\"Plugin \\\"x\\\" is already enabled\",\"alreadyInGoalState\":true}\n✘ Failed", "stderr": ""})
	assert_true(already.ok, "ya estaba así no es un error")
	var failed := ClaudeExtensions.parse_action({"code": 1, "stdout": "{\"outcome\":\"failed\",\"message\":\"Plugin \\\"x\\\" not found in marketplace \\\"y\\\".\",\"failureCode\":\"not_found\"}", "stderr": ""})
	assert_eq(failed, {"ok": false, "message": "Plugin \"x\" not found in marketplace \"y\"."}, "falla con el mensaje del CLI")
	var command := ClaudeExtensions.parse_action({"code": 2, "stdout": "{\"outcome\":\"needs_confirmation\",\"message\":\"Runs a command\",\"shownCommand\":{\"sha256\":\"abc\",\"command\":\"npm i x\"}}", "stderr": ""})
	assert_eq(command.get("accept_command"), {"sha256": "abc", "command": "npm i x"}, "pide aceptar el comando del marketplace")
	var plain := ClaudeExtensions.parse_action({"code": 0, "stdout": "✔ Successfully updated marketplace: m", "stderr": ""})
	assert_eq(plain, {"ok": true, "message": "✔ Successfully updated marketplace: m"}, "sin --json: el texto")
	var timeout := ClaudeExtensions.parse_action({"code": -1, "stdout": "", "stderr": "", "timed_out": true})
	assert_false(timeout.ok, "timeout")


func test_claude_profile_detection() -> void:
	assert_true(ClaudeExtensions.is_claude_profile("npx", PackedStringArray(["-y", "@agentclientprotocol/claude-agent-acp"])), "el adaptador por npx")
	assert_true(ClaudeExtensions.is_claude_profile("/usr/local/bin/claude", PackedStringArray([])), "el CLI")
	assert_false(ClaudeExtensions.is_claude_profile("gemini", PackedStringArray(["--experimental-acp"])), "Gemini")
	assert_eq(ClaudeExtensions.agent_kind("npx", PackedStringArray(["-y", "@zed-industries/codex-acp"])), "codex", "Codex")
	assert_eq(ClaudeExtensions.agent_kind("agy", PackedStringArray(["acp"])), "antigravity", "Antigravity")
	assert_eq(ClaudeExtensions.agent_kind("npx", PackedStringArray(["copilot-acp"])), "copilot", "Copilot")
	assert_eq(ClaudeExtensions.agent_kind("cursor-agent", PackedStringArray(["acp"])), "cursor", "Cursor")
	assert_eq(ClaudeExtensions.agent_kind("opencode", PackedStringArray(["acp"])), "opencode", "OpenCode")


func test_other_agents_mcp_and_instructions() -> void:
	var root := ProjectSettings.globalize_path("user://test_other_agents_extensions")
	var home := root.path_join("home")
	var project := root.path_join("project")
	DirAccess.make_dir_recursive_absolute(home.path_join(".codex"))
	DirAccess.make_dir_recursive_absolute(project.path_join(".agents/rules"))
	DirAccess.make_dir_recursive_absolute(project.path_join(".agents/workflows"))
	DirAccess.make_dir_recursive_absolute(project.path_join(".cursor/rules"))
	_write(home.path_join(".codex/config.toml"), "[mcp_servers.github]\ncommand = \"npx\"\nargs = [\"-y\", \"@modelcontextprotocol/server-github\"]\n\n[mcp_servers.disabled_srv]\nurl = \"https://example.com/mcp\"\nenabled = false\n")
	var codex_mcp := ClaudeExtensions.agent_mcp_servers("codex", project, {"CODEX_HOME": home.path_join(".codex")}, home)
	assert_eq(codex_mcp.size(), 2, "dos servers de Codex en config.toml")
	assert_eq([codex_mcp[0].name, codex_mcp[0].target, codex_mcp[0].origin], ["github", "npx -y @modelcontextprotocol/server-github", "user"], "stdio server en TOML")
	assert_eq([codex_mcp[1].name, codex_mcp[1].status], ["disabled_srv", ClaudeExtensions.MCP_DISABLED], "server deshabilitado en TOML")

	DirAccess.make_dir_recursive_absolute(home.path_join(".gemini/config"))
	_write(home.path_join(".gemini/config/mcp_config.json"), JSON.stringify({"mcpServers": {"firebase": {"command": "npx", "args": ["firebase-mcp"]}}}))
	var agy_mcp := ClaudeExtensions.agent_mcp_servers("antigravity", project, {}, home)
	assert_eq(agy_mcp.size(), 1, "server de Antigravity en mcp_config.json")
	assert_eq([agy_mcp[0].name, agy_mcp[0].origin], ["firebase", "user"], "origen user")

	_write(project.path_join(".agents/rules/gdscript.md"), "# GDScript rules")
	_write(project.path_join(".agents/workflows/release.md"), "# Release workflow")
	_write(project.path_join(".cursor/rules/style.mdc"), "# Cursor rule")
	var extras := InstructionsTab.discover_extra_files(project)
	assert_eq(extras, PackedStringArray([".agents/rules/gdscript.md", ".agents/workflows/release.md", ".cursor/rules/style.mdc"]), "reglas y workflows descubiertos")
	assert_eq(InstructionsTab.default_file_for("codex", project), "AGENTS.md", "Codex prefiere AGENTS.md")
	assert_eq(InstructionsTab.default_file_for("antigravity", project), "GEMINI.md", "Antigravity prefiere GEMINI.md")
	assert_eq(InstructionsTab.default_file_for("copilot", project), ".github/copilot-instructions.md", "Copilot prefiere .github/copilot-instructions.md")


func test_parse_auth_status() -> void:
	var account := ClaudeCli.parse_auth_status('{"loggedIn": true, "authMethod": "claude.ai", "email": "a@b.c", "orgName": "Org", "subscriptionType": "pro"}')
	assert_eq(account, {"email": "a@b.c", "org": "Org", "plan": "pro", "method": "claude.ai"}, "cuenta de claude.ai")
	assert_eq(ClaudeCli.parse_auth_status('{"loggedIn": true, "authMethod": "api_key", "email": null}').email, "", "con API key no hay email")
	assert_eq(ClaudeCli.parse_auth_status('{"loggedIn": false}'), {}, "sin sesión")
	assert_eq(ClaudeCli.parse_auth_status("Not logged in"), {}, "salida que no es JSON")
	assert_eq(AgentDock.account_summary({"email": "a@b.c", "org": "", "plan": "max"}), "Account: a@b.c\nPlan: Max", "tooltip sin organización")
	assert_eq(AgentDock.account_summary({}), "", "sin cuenta, sin tooltip")


func test_cli_wraps_cwd() -> void:
	var cli := ClaudeCli.new("/tmp/proyecto")
	cli.path = "/usr/bin/claude"
	var launch: Array = cli.call(&"_launch_command", PackedStringArray(["mcp", "list"]))
	if OS.get_name() != "Windows":
		assert_eq(launch[0], "/bin/sh", "por sh")
		assert_eq(launch[1], PackedStringArray(["-c", "cd \"$1\" && shift && exec \"$@\"", "sh", "/tmp/proyecto", "/usr/bin/claude", "mcp", "list"]), "cwd y argumentos sin pasar por el shell")


func test_window_builds_offline() -> void:
	var window := ExtensionsWindow.new()
	window.call(&"_build")
	window.set(&"_installed", [{"id": "design@dir", "scope": "user", "enabled": true, "mcpServers": {"slack": {}}}])
	window.set(&"_mcp", ClaudeExtensions.parse_mcp_list(MCP_LIST))
	window.addon_servers_provider = func() -> Array: return [{"name": "db", "enabled": true}]
	window.call(&"_rebuild_all")
	var tabs: TabContainer = window.get(&"_tabs")
	assert_eq(tabs.get_tab_count(), 6, "seis pestañas (con Instructions)")
	assert_eq(tabs.get_tab_title(3), "Skills", "la de skills")
	assert_eq(tabs.get_tab_title(4), "Godot addons", "la de addons de Godot")
	assert_eq(tabs.get_tab_title(0), "Plugins (1)", "cuenta en el título")
	var mcp_box: VBoxContainer = window.get(&"_mcp_box")
	var sections := mcp_box.get_children().filter(func(child: Node) -> bool: return child is Label).map(func(label: Label) -> String: return label.text)
	assert_eq(sections, ["THIS ADDON (SETTINGS → MCP SERVERS) (1)", "CLAUDE.AI (1)", "FROM PLUGINS (3)", "OTHER (2)"], "grupos de MCP en orden")
	assert_eq(window.call(&"_plugin_server_status", "design@dir", "slack"), "needs_auth", "el chip del plugin toma el estado de su server")
	window.free()


func _write(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()
