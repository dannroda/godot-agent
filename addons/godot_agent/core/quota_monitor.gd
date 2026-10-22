@tool
extends RefCounted
## Cuota del plan del usuario (spec §10.1).
## Fuentes, en orden:
## 1. los `usage_update` con `_meta["_claude/rateLimit"]` (D22);
## 2. avisos y errores de límite en el texto del agente o en session/prompt, con los patrones de
##    config/quota_patterns.txt;
## 3. sin datos, el estado queda "desconocido".
## Nunca estima la cuota a partir de tokens, no consulta endpoints y no lee archivos del agente.
## Cada cambio de estado se loguea en el canal `quota`.

signal changed

const AgentLog := preload("agent_log.gd")

enum State { UNKNOWN, NORMAL, WARNING, PAUSE_SCHEDULED, LIMITED }

const STATE_LABELS: Dictionary = {
	State.UNKNOWN: "desconocido",
	State.NORMAL: "normal",
	State.WARNING: "aviso",
	State.PAUSE_SCHEDULED: "pausa programada",
	State.LIMITED: "limitado",
}
const PATTERNS_PATH := "res://addons/godot_agent/config/quota_patterns.txt"
## Clave de `_meta` donde claude-agent-acp manda el SDKRateLimitInfo en los usage_update (D22).
const CLAUDE_RATE_LIMIT_KEY := "_claude/rateLimit"
## Ventanas que se muestran, en orden: la actual y la semanal (D22).
const WINDOW_CURRENT := "five_hour"
const WINDOW_WEEKLY := "seven_day"
const WINDOW_LABELS: Dictionary = {WINDOW_CURRENT: "Ventana", WINDOW_WEEKLY: "Semana"}
## Reintentos sin hora de reinicio (minutos): 5, 10, 20 y después cada 60.
const BACKOFF_MINUTES: Array[int] = [5, 10, 20, 60]
const DEFAULT_WARN := 0.75
const DEFAULT_PAUSE := 0.9

var agent_log: AgentLog
## Umbrales (fracción 0–1). `pause_enabled` false = el One-shot nunca pausa por cuota.
var warn_threshold: float = DEFAULT_WARN
var pause_threshold: float = DEFAULT_PAUSE
var pause_enabled: bool = true
## () -> int, unix en segundos. Reemplazable en los tests.
var now_provider: Callable = func() -> int: return int(Time.get_unix_time_from_system())

var state: State = State.UNKNOWN
## {nombre: {utilization: 0–1, resets_at: unix (0 = desconocida)}}
var windows: Dictionary = {}
var last_usage_update: Dictionary = {}
## Último SDKRateLimitInfo: {status, resetsAt, rateLimitType, utilization, surpassedThreshold,
## unifiedWindows: {five_hour: {utilization 0–1, resetsAt}, seven_day: {…}}, …} (D22).
var last_rate_limit: Dictionary = {}
## Último aviso o error de límite: {source: "texto"|"error"|"cuota", text, at (unix)}.
var last_limit_event: Dictionary = {}
## En "limitado": desde cuándo, hasta cuándo (0 = sin hora) y cuándo toca el próximo intento.
var limited_since: int = 0
var limited_until: int = 0
var next_retry_at: int = 0

var _patterns: Array[RegEx] = []
var _retries: int = 0
var _limited: bool = false


func setup(log_sink: AgentLog, patterns_path: String = PATTERNS_PATH) -> void:
	agent_log = log_sink
	_patterns = load_patterns(patterns_path)


func configure(warn: float, pause: float, pause_on: bool) -> void:
	warn_threshold = clampf(warn, 0.0, 1.0)
	pause_threshold = clampf(pause, 0.0, 1.0)
	pause_enabled = pause_on
	_recompute()


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


# --- fuentes ---------------------------------------------------------------------------------------

func observe_update(update: Dictionary) -> void:
	last_usage_update = update.duplicate(true)
	var raw := JSON.stringify(update)
	var info := rate_limit_info(update)
	if info.is_empty():
		_log("usage_update: %s/%s tokens de contexto, sin datos de cuota" % [update.get("used", "?"), update.get("size", "?")], raw)
		return
	last_rate_limit = info
	_log("cuota del plan: %s" % describe_rate_limit(info), raw)
	_read_windows(info)
	if str(info.get("status", "")) == "rejected":
		_enter_limited("cuota", "status rejected", _number(info.get("resetsAt")))
	elif _limited and str(info.get("status", "")).begins_with("allowed"):
		_leave_limited("el agente vuelve a informar cuota disponible")
	_recompute()


## Texto del agente en un turno: si coincide con un patrón de límite, se pasa a "limitado".
func observe_agent_text(text: String) -> bool:
	var match_text := matching_line(text)
	if match_text.is_empty():
		return false
	_log("aviso de límite en el texto del agente: %s" % match_text, JSON.stringify({"text": text.left(2000)}))
	_enter_limited("texto", match_text, parse_reset_time(match_text, _now()))
	_recompute()
	return true


## Error de session/prompt. Se loguean todos (para ver la forma real); devuelve si parece de límite.
func observe_prompt_error(error: Dictionary) -> bool:
	var data: Variant = error.get("data")
	var kind := str(data.get("errorKind", "")) if data is Dictionary else ""
	var text := "%s %s" % [error.get("message", ""), JSON.stringify(data) if data != null else ""]
	var line := matching_line(str(error.get("message", "")))
	var is_limit := kind in ["rate_limit", "billing_error"] or not matching_line(text).is_empty()
	_log("error de session/prompt%s: %s" % [" (límite)" if is_limit else "", str(error.get("message", "")).left(300)], JSON.stringify(error))
	if is_limit:
		_enter_limited("error", str(error.get("message", "")), parse_reset_time(line if not line.is_empty() else text, _now()))
		_recompute()
	return is_limit


## Un turno terminó bien: si estaba "limitado", la cuota volvió.
func observe_turn_ok() -> void:
	if _limited:
		_leave_limited("un turno terminó bien")
		_recompute()


# --- consultas -------------------------------------------------------------------------------------

func has_data() -> bool:
	return not windows.is_empty()


func utilization(window: String) -> float:
	return float(windows.get(window, {}).get("utilization", -1.0))


func resets_at(window: String) -> int:
	return int(windows.get(window, {}).get("resets_at", 0))


## La mayor utilización informada (cualquiera de las ventanas puede cortar), o -1 sin datos.
func max_utilization() -> float:
	var best := -1.0
	for window: String in windows:
		best = maxf(best, utilization(window))
	return best


## Cuándo se libera la cuota que motivó la pausa: el reinicio de la ventana más llena.
func pause_resets_at() -> int:
	var best_window := ""
	for window: String in windows:
		if best_window.is_empty() or utilization(window) > utilization(best_window):
			best_window = window
	return resets_at(best_window) if not best_window.is_empty() else 0


func is_limited() -> bool:
	return state == State.LIMITED


## Segundos hasta el próximo intento en "limitado" (0 si ya toca).
func seconds_until_retry() -> int:
	return maxi(next_retry_at - _now(), 0) if state == State.LIMITED else 0


func retry_due() -> bool:
	return state == State.LIMITED and _now() >= next_retry_at


## Se mandó un intento de reanudación: si vuelve a fallar, el próximo espera más.
func note_retry() -> void:
	_retries += 1
	_log("intento de reanudación %d" % _retries, "")


## "se pausa al 90 %, al terminar la tarea o el turno", para la barra del One-shot.
func rule_text() -> String:
	if state == State.LIMITED:
		return "Limitado: se retoma %s" % ("al reiniciarse la ventana" if limited_until > 0 else "con reintentos (5, 10, 20 y cada 60 min)")
	if not pause_enabled:
		return "Sin pausa por cuota · aviso al %d %%" % roundi(warn_threshold * 100.0)
	if state == State.PAUSE_SCHEDULED:
		return "Cuota al %d %%: se pausa al terminar la tarea o el turno en curso" % roundi(max_utilization() * 100.0)
	return "Se pausa al %d %%, al terminar la tarea o el turno en curso" % roundi(pause_threshold * 100.0)


## "Ventana 63 % · reinicia en 2 h 10 min".
func describe_window(window: String) -> String:
	var parts: PackedStringArray = ["%s %d %%" % [WINDOW_LABELS.get(window, window), roundi(utilization(window) * 100.0)]]
	if resets_at(window) > 0:
		parts.append("reinicia en " + format_duration(resets_at(window) - _now()))
	return " · ".join(parts)


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


## Hora de reinicio en un aviso de límite, como unix (0 si no tiene). Acepta el formato viejo
## "…|<unix>" y "resets 3pm", "resets 3:30 pm", "resets 15:00", "reinicia a las 15:00" (hora local:
## la próxima vez que llegue esa hora).
static func parse_reset_time(text: String, now: int) -> int:
	var unix := RegEx.create_from_string("\\|\\s*(\\d{9,11})\\b").search(text)
	if unix:
		return int(unix.get_string(1))
	var clock := RegEx.create_from_string("(?i)(?:resets?|reinicia|se reinicia)\\s+(?:at\\s+|a las\\s+|el\\s+)?(\\d{1,2})(?::(\\d{2}))?\\s*(am|pm)?").search(text)
	if clock == null:
		return 0
	var hour := int(clock.get_string(1))
	var minute := int(clock.get_string(2)) if not clock.get_string(2).is_empty() else 0
	var meridiem := clock.get_string(3).to_lower()
	if meridiem == "pm" and hour < 12:
		hour += 12
	elif meridiem == "am" and hour == 12:
		hour = 0
	if hour > 23 or minute > 59:
		return 0
	var offset := _utc_offset_s()
	var local_now := now + offset
	var local_midnight := local_now - posmod(local_now, 86400)
	var candidate := local_midnight + hour * 3600 + minute * 60
	if candidate <= local_now:
		candidate += 86400
	return candidate - offset


## "2 h 10 min", "4 min", "35 s".
static func format_duration(seconds: int) -> String:
	seconds = maxi(seconds, 0)
	if seconds < 60:
		return "%d s" % seconds
	var minutes := seconds / 60
	if minutes < 60:
		return "%d min" % minutes
	if minutes < 48 * 60:
		return "%d h %d min" % [minutes / 60, minutes % 60] if minutes % 60 else "%d h" % (minutes / 60)
	return "%d días" % (minutes / 1440)


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
	var unified: Variant = info.get("unifiedWindows")
	if unified is Dictionary:
		for window_name: String in unified:
			var window: Variant = unified[window_name]
			if window is Dictionary and (window.get("utilization") is float or window.get("utilization") is int):
				var reset := ""
				if window.get("resetsAt") is float or window.get("resetsAt") is int:
					reset = " hasta " + Time.get_datetime_string_from_unix_time(int(window.resetsAt) + _utc_offset_s(), true)
				parts.append("%s %s%s" % [window_name, _percent(window.utilization), reset])
	return " · ".join(parts)


# --- estado ----------------------------------------------------------------------------------------

func _read_windows(info: Dictionary) -> void:
	var unified: Variant = info.get("unifiedWindows")
	if unified is Dictionary:
		for window_name: String in unified:
			var window: Variant = unified[window_name]
			if window is Dictionary and _number(window.get("utilization"), -1) >= 0:
				windows[window_name] = {"utilization": _fraction(window.utilization), "resets_at": _number(window.get("resetsAt"))}
	elif _number(info.get("utilization"), -1) >= 0:
		windows[str(info.get("rateLimitType", WINDOW_CURRENT))] = {"utilization": _fraction(info.utilization), "resets_at": _number(info.get("resetsAt"))}


func _enter_limited(source: String, text: String, reset_at: int) -> void:
	var now := _now()
	# El resetsAt de una cuota "rejected" es exacto; el del texto viene redondeado a la hora.
	if _number(last_rate_limit.get("resetsAt")) > now and str(last_rate_limit.get("status", "")) == "rejected":
		reset_at = _number(last_rate_limit.resetsAt)
	last_limit_event = {"source": source, "text": text, "at": now}
	if not _limited:
		limited_since = now
	limited_until = reset_at if reset_at > now else (limited_until if limited_until > now else 0)
	var backoff_min: int = BACKOFF_MINUTES[mini(_retries, BACKOFF_MINUTES.size() - 1)]
	next_retry_at = limited_until if limited_until > 0 else now + backoff_min * 60
	_limited = true


func _leave_limited(reason: String) -> void:
	_log("fin de \"limitado\": %s" % reason, "")
	_limited = false
	limited_until = 0
	next_retry_at = 0
	_retries = 0


func _recompute() -> void:
	var previous := state
	if _limited:
		state = State.LIMITED
	else:
		var used := max_utilization()
		if used < 0.0:
			state = State.UNKNOWN
		elif pause_enabled and used >= pause_threshold:
			state = State.PAUSE_SCHEDULED
		elif used >= warn_threshold:
			state = State.WARNING
		else:
			state = State.NORMAL
	if state != previous:
		var detail := ""
		if state == State.LIMITED:
			detail = " hasta " + Time.get_datetime_string_from_unix_time(limited_until + _utc_offset_s(), true) if limited_until > 0 else " sin hora de reinicio: próximo intento en %s" % format_duration(next_retry_at - _now())
		elif max_utilization() >= 0.0:
			detail = " (%d %%)" % roundi(max_utilization() * 100.0)
		_log("estado de la cuota: %s → %s%s" % [STATE_LABELS[previous], STATE_LABELS[state], detail], "")
	changed.emit()


func _now() -> int:
	return int(now_provider.call())


static func _number(value: Variant, fallback: int = 0) -> int:
	return int(value) if value is float or value is int else fallback


## Claude Code manda fracciones 0–1 (D22); >1 se toma como porcentaje.
static func _fraction(value: Variant) -> float:
	var number := float(value)
	return number / 100.0 if number > 1.0 else number


static func _percent(value: float) -> String:
	return "%d %%" % roundi(value * 100.0 if value <= 1.0 else value)


static func _utc_offset_s() -> int:
	return int(Time.get_time_zone_from_system().get("bias", 0)) * 60


func _log(message: String, raw: String) -> void:
	if agent_log:
		agent_log.add(AgentLog.CH_QUOTA, message, raw)
