@tool
extends RefCounted
## Plugins, marketplaces y MCP servers de Claude Code para la ventana Extensions (m7-37). Lee y
## cambia todo por el CLI (ClaudeCli); el parseo es estático para los tests. Los cambios de plugins
## valen desde la próxima sesión del agente.

const ClaudeCli := preload("claude_cli.gd")

## Estados de un MCP server según `claude mcp list`.
const MCP_CONNECTED := "connected"
const MCP_NEEDS_AUTH := "needs_auth"
const MCP_FAILED := "failed"
const MCP_PENDING := "pending"
const MCP_DISABLED := "disabled"
const MCP_NOT_CONFIGURED := "not_configured"
const MCP_UNKNOWN := "unknown"
## Origen de un MCP server, para agruparlos.
const ORIGIN_USER := "user"
const ORIGIN_PROJECT := "project"
const ORIGIN_LOCAL := "local"
const ORIGIN_CLAUDE_AI := "claude.ai"
const ORIGIN_PLUGIN := "plugin"
const ORIGIN_OTHER := "other"
const SCOPES: PackedStringArray = ["user", "project", "local"]

## Familias de agentes para extensiones por archivos (m11-19).
const AGENT_CLAUDE := "claude"
const AGENT_CODEX := "codex"
const AGENT_ANTIGRAVITY := "antigravity"
const AGENT_COPILOT := "copilot"
const AGENT_CURSOR := "cursor"
const AGENT_OPENCODE := "opencode"
const AGENT_OTHER := "other"

var cli: ClaudeCli


func _init(project_dir: String = "", env: Dictionary = {}) -> void:
	cli = ClaudeCli.new(project_dir, env)


## El perfil lanza Claude Code (claude-agent-acp o el CLI de claude).
static func is_claude_profile(command: String, args: PackedStringArray) -> bool:
	var line := " ".join(PackedStringArray([command]) + args).to_lower()
	return line.contains("claude-agent-acp") or line.contains("claude-code-acp") or command.get_file().get_basename() == "claude"


## Qué agente lanza un perfil (`claude`, `codex`, `antigravity`, `copilot`, `cursor`, `opencode`, `other`).
static func agent_kind(command: String, args: PackedStringArray, profile_id: String = "") -> String:
	if is_claude_profile(command, args):
		return AGENT_CLAUDE
	var line := (" ".join(PackedStringArray([profile_id, command]) + args)).to_lower()
	var bin := command.get_file().get_basename().to_lower()
	if line.contains("codex-acp") or line.contains("@zed-industries/codex") or bin == "codex" or profile_id.to_lower().begins_with("codex"):
		return AGENT_CODEX
	if line.contains("antigravity") or bin == "agy" or bin == "antigravity":
		return AGENT_ANTIGRAVITY
	if line.contains("copilot") or bin == "copilot":
		return AGENT_COPILOT
	if line.contains("cursor-acp") or line.contains("cursor-agent") or bin == "cursor" or bin == "cursor-agent" or profile_id.to_lower().begins_with("cursor"):
		return AGENT_CURSOR
	if line.contains("opencode") or bin == "opencode":
		return AGENT_OPENCODE
	return AGENT_OTHER


## `{installed: [], available: [], error}`. `available` solo si se pide (es grande: miles).
func plugins(include_available: bool) -> Dictionary:
	var args: PackedStringArray = ["plugin", "list", "--json"]
	if include_available:
		args.append("--available")
	var result: Dictionary = await cli.run(args)
	if result.code != 0:
		return {"installed": [], "available": [], "error": describe_failure(result)}
	return parse_plugins(result.stdout)


func marketplaces() -> Dictionary:
	var result: Dictionary = await cli.run(["plugin", "marketplace", "list", "--json"])
	if result.code != 0:
		return {"marketplaces": [], "error": describe_failure(result)}
	var data: Variant = _parse_json(result.stdout)
	return {"marketplaces": data if data is Array else [], "error": "" if data is Array else "Unexpected output from claude plugin marketplace list."}


## `{servers: [{name, target, status, detail, origin}], error}`. Chequea la conexión de cada
## server, así que tarda unos segundos.
func mcp_servers() -> Dictionary:
	var result: Dictionary = await cli.run(["mcp", "list"], 90000)
	if result.code != 0 and result.stdout.strip_edges().is_empty():
		return {"servers": [], "error": describe_failure(result)}
	var servers := parse_mcp_list(result.stdout)
	var scopes := config_scopes(cli.env.get("CLAUDE_CONFIG_DIR", OS.get_environment("CLAUDE_CONFIG_DIR")), cli.cwd)
	for server: Dictionary in servers:
		if server.origin == ORIGIN_OTHER and scopes.has(server.name):
			server.origin = scopes[server.name]
	return {"servers": servers, "error": ""}


## Acción del CLI que cambia algo. `{ok, message, accept_command: {sha256, command}?}`. Si un plugin
## declara un comando para instalarse, la primera vez no lo corre: devuelve el comando para que la
## persona lo acepte y se repite con `accept_sha`.
func set_plugin_enabled(id: String, enabled: bool, scope: String) -> Dictionary:
	return await _action(["plugin", "enable" if enabled else "disable", id, "--scope", scope, "--json"])


func install_plugin(id: String, scope: String, accept_sha: String = "") -> Dictionary:
	var args: PackedStringArray = ["plugin", "install", id, "--scope", scope, "--json"]
	if not accept_sha.is_empty():
		args.append_array(["--accept-command", accept_sha])
	return await _action(args)


func update_plugin(id: String, scope: String, accept_sha: String = "") -> Dictionary:
	var args: PackedStringArray = ["plugin", "update", id, "--scope", scope, "--json"]
	if not accept_sha.is_empty():
		args.append_array(["--accept-command", accept_sha])
	return await _action(args)


func uninstall_plugin(id: String, scope: String) -> Dictionary:
	return await _action(["plugin", "uninstall", id, "--scope", scope, "--json"])


func add_marketplace(source: String) -> Dictionary:
	return await _action(["plugin", "marketplace", "add", source, "--json"])


func update_marketplace(name: String) -> Dictionary:
	return await _action(["plugin", "marketplace", "update", name])


func remove_marketplace(name: String) -> Dictionary:
	return await _action(["plugin", "marketplace", "remove", name])


## Autenticación OAuth de un MCP server: Claude Code abre el navegador y espera la vuelta.
func mcp_login(name: String) -> Dictionary:
	return await _action(["mcp", "login", name], 300000)


func _action(args: PackedStringArray, timeout_ms: int = ClaudeCli.DEFAULT_TIMEOUT_MS) -> Dictionary:
	var result: Dictionary = await cli.run(args, timeout_ms)
	return parse_action(result)


# --- parseo --------------------------------------------------------------------------------------

static func parse_plugins(text: String) -> Dictionary:
	var data: Variant = _parse_json(text)
	if data is Array:
		return {"installed": data, "available": [], "error": ""}
	if data is Dictionary:
		var installed: Variant = data.get("installed", [])
		var available: Variant = data.get("available", [])
		return {"installed": installed if installed is Array else [], "available": available if available is Array else [], "error": ""}
	return {"installed": [], "available": [], "error": "Unexpected output from claude plugin list."}


## Disponibles que no están instalados, que contienen `query` (nombre, descripción o marketplace) y
## ordenados por instalaciones; `limit` como máximo. `{items, total}`.
static func filter_available(available: Array, installed: Array, query: String, limit: int) -> Dictionary:
	var installed_ids: Dictionary = {}
	for plugin: Variant in installed:
		if plugin is Dictionary:
			installed_ids[str(plugin.get("id", ""))] = true
	var needle := query.strip_edges().to_lower()
	var matches: Array = []
	for plugin: Variant in available:
		if not plugin is Dictionary or installed_ids.has(str(plugin.get("pluginId", ""))):
			continue
		if not needle.is_empty():
			var haystack := ("%s %s %s" % [plugin.get("name", ""), plugin.get("description", ""), plugin.get("marketplaceName", "")]).to_lower()
			if not haystack.contains(needle):
				continue
		matches.append(plugin)
	matches.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var count_a := int(a.get("installCount", 0))
		var count_b := int(b.get("installCount", 0))
		return count_a > count_b if count_a != count_b else str(a.get("name", "")) < str(b.get("name", "")))
	return {"items": matches.slice(0, limit), "total": matches.size()}


## Líneas `nombre: destino - ✔ Connected` de `claude mcp list`. El nombre puede tener `:`
## (`plugin:design:slack`); termina en el primer `: `. El estado va después del último ` - `.
static func parse_mcp_list(text: String) -> Array:
	var servers: Array = []
	for raw_line: String in text.split("\n"):
		var line := raw_line.strip_edges()
		var name_end := line.find(": ")
		var status_at := line.rfind(" - ")
		if line.is_empty() or name_end <= 0 or status_at <= name_end:
			continue
		var name := line.left(name_end)
		var status_text := line.substr(status_at + 3).strip_edges()
		var parsed := _status_of(status_text)
		servers.append({
			"name": name,
			"target": line.substr(name_end + 2, status_at - name_end - 2).strip_edges(),
			"status": parsed[0],
			"detail": parsed[1],
			"origin": _origin_of(name),
		})
	return servers


## {nombre: scope} de los servers de la configuración de Claude Code: `mcpServers` de `.claude.json`
## (user), de su entrada de este proyecto (local) y del `.mcp.json` del proyecto (project).
static func config_scopes(config_dir: String, project_dir: String) -> Dictionary:
	var scopes: Dictionary = {}
	var claude_json := (config_dir if not config_dir.is_empty() else OS.get_environment("HOME")).path_join(".claude.json")
	var data: Variant = _parse_json(FileAccess.get_file_as_string(claude_json)) if FileAccess.file_exists(claude_json) else null
	if not project_dir.is_empty() and FileAccess.file_exists(project_dir.path_join(".mcp.json")):
		var mcp_json: Variant = _parse_json(FileAccess.get_file_as_string(project_dir.path_join(".mcp.json")))
		if mcp_json is Dictionary and mcp_json.get("mcpServers") is Dictionary:
			for name: Variant in mcp_json.mcpServers:
				scopes[str(name)] = ORIGIN_PROJECT
	if data is Dictionary:
		if data.get("mcpServers") is Dictionary:
			for name: Variant in data.mcpServers:
				scopes[str(name)] = ORIGIN_USER
		var projects: Variant = data.get("projects")
		var key := project_dir.trim_suffix("/")
		if projects is Dictionary and projects.get(key) is Dictionary and projects[key].get("mcpServers") is Dictionary:
			for name: Variant in projects[key].mcpServers:
				scopes[str(name)] = ORIGIN_LOCAL
	return scopes


## MCP servers configurados en los archivos del agente (m11-19) para agentes que no son Claude Code:
## Codex (`config.toml`), Antigravity (`mcp_config.json`), Cursor (`.cursor/mcp.json`), Copilot
## (`.vscode/mcp.json`) y OpenCode (`opencode.json`).
static func agent_mcp_servers(kind: String, project_dir: String, env: Dictionary = {}, home_dir: String = "") -> Array:
	var home := home_dir if not home_dir.is_empty() else OS.get_environment("HOME")
	var servers: Array = []
	var seen: Dictionary = {}
	var add_entries := func(entries: Array) -> void:
		for item: Dictionary in entries:
			var key := "%s|%s" % [item.origin, item.name]
			if not seen.has(key):
				seen[key] = true
				servers.append(item)
	match kind:
		AGENT_CODEX:
			var codex_home := str(env.get("CODEX_HOME", OS.get_environment("CODEX_HOME")))
			if codex_home.is_empty():
				codex_home = home.path_join(".codex")
			if not project_dir.is_empty() and FileAccess.file_exists(project_dir.path_join(".codex/config.toml")):
				add_entries.call(parse_codex_mcp_toml(FileAccess.get_file_as_string(project_dir.path_join(".codex/config.toml")), ORIGIN_PROJECT))
			if FileAccess.file_exists(codex_home.path_join("config.toml")):
				add_entries.call(parse_codex_mcp_toml(FileAccess.get_file_as_string(codex_home.path_join("config.toml")), ORIGIN_USER))
		AGENT_ANTIGRAVITY:
			for rel: String in [".agents/mcp_config.json", ".agent/mcp_config.json"]:
				if not project_dir.is_empty() and FileAccess.file_exists(project_dir.path_join(rel)):
					add_entries.call(parse_mcp_json(FileAccess.get_file_as_string(project_dir.path_join(rel)), ORIGIN_PROJECT))
			for rel: String in [".gemini/config/mcp_config.json", ".gemini/antigravity/mcp_config.json"]:
				if not home.is_empty() and FileAccess.file_exists(home.path_join(rel)):
					add_entries.call(parse_mcp_json(FileAccess.get_file_as_string(home.path_join(rel)), ORIGIN_USER))
		AGENT_CURSOR:
			if not project_dir.is_empty() and FileAccess.file_exists(project_dir.path_join(".cursor/mcp.json")):
				add_entries.call(parse_mcp_json(FileAccess.get_file_as_string(project_dir.path_join(".cursor/mcp.json")), ORIGIN_PROJECT))
			if not home.is_empty() and FileAccess.file_exists(home.path_join(".cursor/mcp.json")):
				add_entries.call(parse_mcp_json(FileAccess.get_file_as_string(home.path_join(".cursor/mcp.json")), ORIGIN_USER))
		AGENT_COPILOT:
			if not project_dir.is_empty() and FileAccess.file_exists(project_dir.path_join(".vscode/mcp.json")):
				add_entries.call(parse_mcp_json(FileAccess.get_file_as_string(project_dir.path_join(".vscode/mcp.json")), ORIGIN_PROJECT))
			if not home.is_empty() and FileAccess.file_exists(home.path_join(".copilot/mcp-config.json")):
				add_entries.call(parse_mcp_json(FileAccess.get_file_as_string(home.path_join(".copilot/mcp-config.json")), ORIGIN_USER))
		AGENT_OPENCODE:
			for rel: String in ["opencode.json", ".opencode/opencode.json"]:
				if not project_dir.is_empty() and FileAccess.file_exists(project_dir.path_join(rel)):
					add_entries.call(parse_mcp_json(FileAccess.get_file_as_string(project_dir.path_join(rel)), ORIGIN_PROJECT))
			if not home.is_empty() and FileAccess.file_exists(home.path_join(".config/opencode/opencode.json")):
				add_entries.call(parse_mcp_json(FileAccess.get_file_as_string(home.path_join(".config/opencode/opencode.json")), ORIGIN_USER))
	if not project_dir.is_empty() and FileAccess.file_exists(project_dir.path_join(".mcp.json")):
		add_entries.call(parse_mcp_json(FileAccess.get_file_as_string(project_dir.path_join(".mcp.json")), ORIGIN_PROJECT))
	return servers


## Parsea archivos JSON de MCP (`mcpServers`, `servers` de VS Code/Copilot o `mcp` de OpenCode).
static func parse_mcp_json(text: String, origin: String) -> Array:
	var data: Variant = _parse_json(text)
	if not data is Dictionary:
		return []
	var dict: Dictionary = {}
	for key: String in ["mcpServers", "servers", "mcp"]:
		if data.get(key) is Dictionary:
			dict = data[key]
			break
	var result: Array = []
	for name: Variant in dict:
		var entry: Variant = dict[name]
		if not entry is Dictionary:
			continue
		var target := str(entry.get("url", entry.get("serverUrl", "")))
		if target.is_empty():
			var cmd: Variant = entry.get("command", "")
			if cmd is Array:
				target = " ".join(PackedStringArray(cmd))
			elif cmd is String and not str(cmd).is_empty():
				var args_arr: Array = entry.get("args", []) if entry.get("args") is Array else []
				var parts: PackedStringArray = [str(cmd)]
				for arg: Variant in args_arr:
					parts.append(str(arg))
				target = " ".join(parts)
		var disabled: bool = entry.get("enabled") == false or entry.get("disabled") == true
		result.append({
			"name": str(name),
			"target": target.strip_edges(),
			"status": MCP_DISABLED if disabled else MCP_UNKNOWN,
			"detail": "",
			"origin": origin,
		})
	return result


## Parsea `[mcp_servers.<nombre>]` en `config.toml` de Codex.
static func parse_codex_mcp_toml(text: String, origin: String) -> Array:
	var result: Array = []
	var header_re := RegEx.create_from_string("^\\[mcp_servers\\.(?:\"([^\"]+)\"|'([^']+)'|([A-Za-z0-9_-]+))\\]\\s*$")
	var current_name := ""
	var current: Dictionary = {}
	for raw_line: String in text.replace("\r\n", "\n").split("\n"):
		var line := raw_line.strip_edges()
		if line.is_empty() or line.begins_with("#"):
			continue
		if line.begins_with("["):
			_flush_codex_mcp_entry(result, current_name, current, origin)
			var m := header_re.search(line)
			if m:
				current_name = m.get_string(1) if not m.get_string(1).is_empty() else (m.get_string(2) if not m.get_string(2).is_empty() else m.get_string(3))
				current = {}
			else:
				current_name = ""
			continue
		if current_name.is_empty():
			continue
		var eq := line.find("=")
		if eq <= 0:
			continue
		var key := line.substr(0, eq).strip_edges()
		var val_text := line.substr(eq + 1).strip_edges()
		if key in ["command", "url"]:
			var parsed: Variant = _parse_json(val_text)
			current[key] = str(parsed) if parsed is String else val_text.trim_prefix("'").trim_suffix("'")
		elif key == "args":
			var parsed_args: Variant = _parse_json(val_text)
			if parsed_args is Array:
				current["args"] = parsed_args
		elif key == "enabled":
			current["enabled"] = val_text != "false"
	_flush_codex_mcp_entry(result, current_name, current, origin)
	return result


static func _flush_codex_mcp_entry(result: Array, current_name: String, current: Dictionary, origin: String) -> void:
	if current_name.is_empty():
		return
	var target := str(current.get("url", ""))
	if target.is_empty() and not str(current.get("command", "")).is_empty():
		var parts: PackedStringArray = [str(current.command)]
		if current.get("args") is Array:
			for arg: Variant in current.args:
				parts.append(str(arg))
		target = " ".join(parts)
	var disabled: bool = current.get("enabled") == false
	result.append({
		"name": current_name,
		"target": target.strip_edges(),
		"status": MCP_DISABLED if disabled else MCP_UNKNOWN,
		"detail": "",
		"origin": origin,
	})


## Resultado de una acción: con `--json`, la última línea de stdout es un objeto con el resultado.
static func parse_action(result: Dictionary) -> Dictionary:
	var parsed: Dictionary = {}
	for line: String in Array(str(result.get("stdout", "")).split("\n")).filter(func(text: String) -> bool: return not text.strip_edges().is_empty()):
		var data: Variant = _parse_json(line)
		if data is Dictionary:
			parsed = data
	var shown: Variant = parsed.get("shownCommand")
	if shown is Dictionary and shown.get("sha256") is String and int(result.get("code", 0)) != 0:
		return {"ok": false, "message": str(parsed.get("message", parsed.get("error", ""))), "accept_command": {"sha256": shown.sha256, "command": str(shown.get("command", shown.get("text", "")))}}
	# «Ya estaba así» (enable de uno habilitado) no es un error para la ventana.
	var ok := (int(result.get("code", -1)) == 0 and not bool(result.get("timed_out", false))) or bool(parsed.get("alreadyInGoalState", false))
	var message := str(parsed.get("message", parsed.get("error", "")))
	if message.is_empty():
		message = str(result.get("stdout", "")).strip_edges() if ok else describe_failure(result)
	return {"ok": ok, "message": message.left(600)}


static func describe_failure(result: Dictionary) -> String:
	if bool(result.get("timed_out", false)):
		return "The command took too long and was stopped."
	var text := str(result.get("stderr", "")).strip_edges()
	if text.is_empty():
		text = str(result.get("stdout", "")).strip_edges()
	return text.left(600) if not text.is_empty() else "The command failed (code %d)." % int(result.get("code", -1))


static func _status_of(text: String) -> Array:
	var lower := text.to_lower()
	if lower.contains("connected") and not lower.contains("failed"):
		return [MCP_CONNECTED, ""]
	if lower.contains("needs auth"):
		return [MCP_NEEDS_AUTH, ""]
	if lower.contains("pending"):
		return [MCP_PENDING, ""]
	if lower.contains("disabled"):
		return [MCP_DISABLED, ""]
	if lower.contains("not configured"):
		return [MCP_NOT_CONFIGURED, ""]
	if lower.contains("failed"):
		var dash := text.find("—")
		return [MCP_FAILED, text.substr(dash + 1).strip_edges() if dash >= 0 else ""]
	return [MCP_UNKNOWN, text]


static func _origin_of(name: String) -> String:
	if name.begins_with("plugin:"):
		return ORIGIN_PLUGIN
	if name.begins_with("claude.ai "):
		return ORIGIN_CLAUDE_AI
	return ORIGIN_OTHER


## JSON.parse_string sin el error en la consola: el CLI mezcla líneas de texto con el JSON.
static func _parse_json(text: String) -> Variant:
	var json := JSON.new()
	return json.data if json.parse(text) == OK else null
