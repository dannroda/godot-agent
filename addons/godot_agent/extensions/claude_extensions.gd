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

var cli: ClaudeCli


func _init(project_dir: String = "", env: Dictionary = {}) -> void:
	cli = ClaudeCli.new(project_dir, env)


## El perfil lanza Claude Code (claude-agent-acp o el CLI de claude).
static func is_claude_profile(command: String, args: PackedStringArray) -> bool:
	var line := " ".join(PackedStringArray([command]) + args).to_lower()
	return line.contains("claude-agent-acp") or line.contains("claude-code-acp") or command.get_file().get_basename() == "claude"


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
