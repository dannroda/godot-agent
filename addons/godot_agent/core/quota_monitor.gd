@tool
extends RefCounted
## Cuota del plan del usuario (spec §10.1). Por ahora solo observa (M1):
## - loguea en el canal `quota` cada `usage_update` y cada aviso o error de límite;
## - guarda lo último crudo, para mapear campos y estados después (M6).
## Nunca estima la cuota a partir de tokens, no consulta endpoints y no lee archivos del agente.

const AgentLog := preload("agent_log.gd")

const PATTERNS_PATH := "res://addons/godot_agent/config/quota_patterns.txt"
## Clave de `_meta` donde claude-agent-acp manda el SDKRateLimitInfo en los usage_update (D22).
const CLAUDE_RATE_LIMIT_KEY := "_claude/rateLimit"

var agent_log: AgentLog
var last_usage_update: Dictionary = {}
## Último SDKRateLimitInfo: {status, resetsAt, rateLimitType, utilization, surpassedThreshold,
## unifiedWindows: {five_hour: {utilization 0–1, resetsAt}, seven_day: {…}}, …} (D22).
var last_rate_limit: Dictionary = {}
## Último aviso o error de límite: {source: "texto"|"error", text, at (unix)}.
var last_limit_event: Dictionary = {}

var _patterns: Array[RegEx] = []


func setup(log_sink: AgentLog, patterns_path: String = PATTERNS_PATH) -> void:
	agent_log = log_sink
	_patterns = load_patterns(patterns_path)


## Una regex por línea (sin mayúsculas/minúsculas); `#` comenta. Las inválidas se saltean.
static func load_patterns(path: String) -> Array[RegEx]:
	var patterns: Array[RegEx] = []
	for line: String in FileAccess.get_file_as_string(path).split("\n"):
		var source := line.strip_edges()
		if source.is_empty() or source.begins_with("#"):
			continue
		var regex := RegEx.create_from_string("(?i)" + source, false)
		if regex and regex.is_valid():
			patterns.append(regex)
	return patterns


func observe_update(update: Dictionary) -> void:
	last_usage_update = update.duplicate(true)
	var raw := JSON.stringify(update)
	var info := rate_limit_info(update)
	if info.is_empty():
		_log("usage_update: %s/%s tokens de contexto, sin datos de cuota" % [update.get("used", "?"), update.get("size", "?")], raw)
		return
	last_rate_limit = info
	_log("cuota del plan: %s" % describe_rate_limit(info), raw)


## Texto del agente en un turno: si coincide con un patrón de límite, se registra.
func observe_agent_text(text: String) -> bool:
	var match_text := matching_line(text)
	if match_text.is_empty():
		return false
	last_limit_event = {"source": "texto", "text": match_text, "at": int(Time.get_unix_time_from_system())}
	_log("aviso de límite en el texto del agente: %s" % match_text, JSON.stringify({"text": text.left(2000)}))
	return true


## Error de session/prompt. Se loguean todos (para ver la forma real); devuelve si parece de límite.
func observe_prompt_error(error: Dictionary) -> bool:
	var data: Variant = error.get("data")
	var kind := str(data.get("errorKind", "")) if data is Dictionary else ""
	var text := "%s %s" % [error.get("message", ""), JSON.stringify(data) if data != null else ""]
	var is_limit := kind in ["rate_limit", "billing_error"] or not matching_line(text).is_empty()
	if is_limit:
		last_limit_event = {"source": "error", "text": str(error.get("message", "")), "at": int(Time.get_unix_time_from_system())}
	_log("error de session/prompt%s: %s" % [" (límite)" if is_limit else "", str(error.get("message", "")).left(300)], JSON.stringify(error))
	return is_limit


func matching_line(text: String) -> String:
	for line: String in text.split("\n"):
		var trimmed := line.strip_edges()
		for regex: RegEx in _patterns:
			if regex.search(trimmed):
				return trimmed
	return ""


static func rate_limit_info(update: Dictionary) -> Dictionary:
	var meta: Variant = update.get("_meta")
	if meta is Dictionary and meta.get(CLAUDE_RATE_LIMIT_KEY) is Dictionary:
		return meta[CLAUDE_RATE_LIMIT_KEY]
	return {}


## "allowed · five_hour · reinicio 2026-10-21 05:40:00 · five_hour 63 % hasta … · seven_day 47 % hasta …".
static func describe_rate_limit(info: Dictionary) -> String:
	var parts: PackedStringArray = [str(info.get("status", "?"))]
	if info.has("rateLimitType"):
		parts.append(str(info.rateLimitType))
	if info.get("utilization") is float or info.get("utilization") is int:
		parts.append(_percent(info.utilization))
	if info.get("surpassedThreshold") is float or info.get("surpassedThreshold") is int:
		parts.append("umbral " + _percent(info.surpassedThreshold))
	if info.get("resetsAt") is float or info.get("resetsAt") is int:
		parts.append("reinicio " + Time.get_datetime_string_from_unix_time(int(info.resetsAt) + _utc_offset_s(), true))
	if info.get("isUsingOverage") == true:
		parts.append("usando créditos extra")
	var windows: Variant = info.get("unifiedWindows")
	if windows is Dictionary:
		for window_name: String in windows:
			var window: Variant = windows[window_name]
			if window is Dictionary and (window.get("utilization") is float or window.get("utilization") is int):
				var reset := ""
				if window.get("resetsAt") is float or window.get("resetsAt") is int:
					reset = " hasta " + Time.get_datetime_string_from_unix_time(int(window.resetsAt) + _utc_offset_s(), true)
				parts.append("%s %s%s" % [window_name, _percent(window.utilization), reset])
	return " · ".join(parts)


## Claude Code manda fracciones 0–1 (D22); >1 se toma como porcentaje ya.
static func _percent(value: float) -> String:
	return "%d %%" % roundi(value * 100.0 if value <= 1.0 else value)


static func _utc_offset_s() -> int:
	return int(Time.get_time_zone_from_system().get("bias", 0)) * 60


func _log(message: String, raw: String) -> void:
	if agent_log:
		agent_log.add(AgentLog.CH_QUOTA, message, raw)
