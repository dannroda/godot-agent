@tool
extends RefCounted
## Informe de diagnóstico para pegar en un issue (m11-80). Solo valores de listas cerradas, números
## acotados y versiones con forma de versión: nada de rutas, texto de la conversación, nombres de
## archivos, comandos, email ni cuenta. `build` normaliza cualquier dato crudo: lo que no está en su
## lista sale como "unknown" (o "other" para un nombre de agente o de cliente que no conocemos), así
## un valor inesperado nunca se cuela en el informe. Sirve para los fallos que no podemos reproducir
## (Windows, macOS, Antigravity).
## La idea y la forma (schema_version, listas cerradas, _bounded_version) son de
## support_diagnostic_report.gd de Orca (MIT).

const SessionModel := preload("../session/session_model.gd")
const QuotaMonitor := preload("quota_monitor.gd")

const SCHEMA_VERSION := 1

const GODOT_STATUSES: PackedStringArray = ["stable", "beta", "alpha", "rc", "dev", "custom_build"]
const OS_NAMES: PackedStringArray = ["Windows", "macOS", "Linux", "FreeBSD", "NetBSD", "OpenBSD", "BSD", "Android", "iOS", "Web"]
const ARCHITECTURES: PackedStringArray = ["x86_64", "x86_32", "arm64", "arm32", "rv64", "ppc64", "ppc32", "wasm32", "loongarch64"]
## Los `kind` de los adaptadores (ClaudeExtensions.AGENT_*).
const AGENT_KINDS: PackedStringArray = ["claude", "codex", "antigravity", "copilot", "cursor", "opencode", "other"]
## `agentInfo.name` de los adaptadores ACP que conocemos; otro nombre sale como "other".
const AGENT_NAMES: PackedStringArray = ["@agentclientprotocol/claude-agent-acp", "claude-agent-acp", "@zed-industries/claude-code-acp", "claude-code-acp", "codex-acp", "@zed-industries/codex-acp", "antigravity-acp", "cursor-agent", "cursor-acp", "gemini", "opencode", "copilot", "fake-agent"]
## SessionModel.SessionState, en minúsculas.
const SESSION_STATES: PackedStringArray = ["disconnected", "starting", "ready", "prompting", "cancelling", "failed", "login_required"]
## Dónde estaba la conexión con el agente.
const ACP_PHASES: PackedStringArray = ["none", "launching", "initializing", "opening_session", "idle", "prompting", "cancelling", "failed", "login_required"]
## SessionModel.HarnessMode, en minúsculas.
const HARNESS_MODES: PackedStringArray = ["ask", "review", "build", "oneshot", "auto", "plan"]
## Por qué falló la sesión o el último turno (SessionModel.failure_kind).
const FAILURE_KINDS: PackedStringArray = ["none", "launch_failed", "no_initialize", "session_open_failed", "login_required", "process_exited", "turn_error", "turn_limit", "turn_auth"]
const STOP_REASONS: PackedStringArray = ["none", "end_turn", "max_tokens", "max_turn_requests", "refusal", "cancelled", "error"]
## Códigos JSON-RPC que conocemos (AcpClient.ERR_* y los de ACP); otro sale como 0.
const ERROR_CODES: Array[int] = [-32700, -32600, -32601, -32602, -32603, -32800, -32000, -32001, -32002]
## QuotaMonitor.QuotaState, en minúsculas.
const QUOTA_STATES: PackedStringArray = ["unknown", "normal", "warning", "pause_scheduled", "limited"]
## `clientInfo.name` de los clientes MCP que conocemos.
const MCP_CLIENTS: PackedStringArray = ["claude-code", "codex-mcp-client", "antigravity", "gemini-cli-mcp-client", "cursor", "opencode", "other"]
## OneShotRun.RunPhase, en minúsculas.
const ONESHOT_PHASES: PackedStringArray = ["idle", "preparing", "running", "paused", "paused_quota", "limited", "waiting_confirm", "closing", "finished", "spec_review", "evaluating"]
const VERSION_PATTERN := "^\\d{1,4}(\\.\\d{1,4}){0,3}([-+][0-9A-Za-z]{1,12}(\\.[0-9A-Za-z]{1,12}){0,2})?$"
const COUNT_MAX := 999


## El informe a partir de los datos crudos que junta `collect` (o un test). Todo pasa por su lista.
static func build(raw: Dictionary) -> Dictionary:
	var godot: Dictionary = raw.get("godot", {}) if raw.get("godot") is Dictionary else {}
	var agent: Dictionary = raw.get("agent", {}) if raw.get("agent") is Dictionary else {}
	var session: Dictionary = raw.get("session", {}) if raw.get("session") is Dictionary else {}
	var mcp: Dictionary = raw.get("mcp", {}) if raw.get("mcp") is Dictionary else {}
	var oneshot: Dictionary = raw.get("oneshot", {}) if raw.get("oneshot") is Dictionary else {}
	return {
		"schema_version": SCHEMA_VERSION,
		"addon_version": bounded_version(raw.get("addon_version")),
		"godot": {
			"major": _count(godot.get("major")),
			"minor": _count(godot.get("minor")),
			"patch": _count(godot.get("patch")),
			"status": _enum(godot.get("status"), GODOT_STATUSES),
		},
		"os": _enum(raw.get("os"), OS_NAMES),
		"architecture": _enum(raw.get("architecture"), ARCHITECTURES),
		"agent": {
			"kind": _enum(agent.get("kind"), AGENT_KINDS),
			"name": _known_name(agent.get("name"), AGENT_NAMES),
			"version": bounded_version(agent.get("version")),
			"protocol_version": _count(agent.get("protocol_version")),
		},
		"session": {
			"state": _enum(session.get("state"), SESSION_STATES),
			"acp_phase": _enum(session.get("acp_phase"), ACP_PHASES),
			"harness_mode": _enum(session.get("harness_mode"), HARNESS_MODES),
			"failure_kind": _enum(session.get("failure_kind", "none"), FAILURE_KINDS),
			"error_code": _error_code(session.get("error_code")),
			"last_stop_reason": _enum(session.get("last_stop_reason", "none"), STOP_REASONS),
			"quota_state": _enum(session.get("quota_state"), QUOTA_STATES),
			"open_tabs": _count(session.get("open_tabs")),
		},
		"mcp": {
			"server_listening": _bool(mcp.get("server_listening")),
			"agent_connected": _bool(mcp.get("agent_connected")),
			"client": _known_name(mcp.get("client"), MCP_CLIENTS) if _bool(mcp.get("agent_connected")) else "none",
			"tool_calls": _count(mcp.get("tool_calls")),
			"tool_errors": _count(mcp.get("tool_errors")),
		},
		"oneshot": {
			"active": _bool(oneshot.get("active")),
			"phase": _enum(oneshot.get("phase", "idle"), ONESHOT_PHASES),
		},
	}


## Los datos crudos de una sesión: el estado de su modelo, su controlador y su MCP (`mcp`, de
## McpServer.diagnostics_of). `oneshot` es {active, phase} con la fase en minúsculas.
static func collect(addon_version: String, model: SessionModel, adapter_kind: String, quota: QuotaMonitor, mcp: Dictionary, oneshot: Dictionary, open_tabs: int) -> Dictionary:
	var info := Engine.get_version_info()
	var raw := {"addon_version": addon_version, "os": OS.get_name(), "architecture": Engine.get_architecture_name(),
		"godot": {"major": info.get("major"), "minor": info.get("minor"), "patch": info.get("patch"), "status": info.get("status")},
		"mcp": mcp, "oneshot": oneshot}
	if model == null:
		return raw
	var state := SessionModel.state_name(model.state).to_lower()
	raw.agent = {"kind": adapter_kind, "name": model.agent_info.get("name", ""), "version": model.agent_info.get("version", ""),
		"protocol_version": model.protocol_version}
	raw.session = {"state": state, "acp_phase": acp_phase(state, not model.agent_info.is_empty()),
		"harness_mode": str(SessionModel.HarnessMode.find_key(model.harness_mode)).to_lower(),
		"failure_kind": model.failure_kind, "error_code": model.failure_code,
		"last_stop_reason": model.last_stop_reason if not model.last_stop_reason.is_empty() else "none",
		"quota_state": str(QuotaMonitor.QuotaState.find_key(quota.state)).to_lower() if quota else "", "open_tabs": open_tabs}
	return raw


## Dónde está la conexión con el agente: STARTING se parte en antes y después de initialize.
static func acp_phase(state: String, initialized: bool) -> String:
	match state:
		"disconnected":
			return "none"
		"starting":
			return "opening_session" if initialized else "initializing"
		"ready":
			return "idle"
		"failed", "login_required", "prompting", "cancelling":
			return state
	return "unknown"


## JSON con sangría, para copiar. Cabe en un bloque de código de un issue.
static func serialize(report: Dictionary) -> String:
	return JSON.stringify(report, "  ", false)


## Lo que va en el portapapeles: el JSON en un bloque de código, con una línea que dice qué es.
static func clipboard_text(report: Dictionary) -> String:
	return "Godot Agent Harness diagnostic report (no paths, conversation text, file names or account data):\n\n```json\n%s\n```\n" % serialize(report)


## Una versión con forma de versión (1.2.3, 0.2.1-beta3, 4.7.2+abc); cualquier otra cosa es "unknown".
static func bounded_version(value: Variant) -> String:
	if not (value is String or value is StringName):
		return "unknown"
	var text := str(value).strip_edges().trim_prefix("v")
	if text.length() > 40 or RegEx.create_from_string(VERSION_PATTERN).search(text) == null:
		return "unknown"
	return text


static func _enum(value: Variant, allowed: PackedStringArray) -> String:
	if not (value is String or value is StringName):
		return "unknown"
	var text := str(value)
	return text if text in allowed else "unknown"


static func _known_name(value: Variant, allowed: PackedStringArray) -> String:
	if not (value is String or value is StringName) or str(value).is_empty():
		return "unknown"
	return str(value) if str(value) in allowed else "other"


static func _count(value: Variant) -> int:
	if not (value is int or value is float):
		return 0
	return clampi(int(value), 0, COUNT_MAX)


static func _bool(value: Variant) -> bool:
	return value if value is bool else false


static func _error_code(value: Variant) -> int:
	if not (value is int or value is float):
		return 0
	return int(value) if int(value) in ERROR_CODES else 0
