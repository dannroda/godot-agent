extends "test_case.gd"
## QuotaMonitor (spec §10.1, D22): fuentes, estados, umbrales, hora de reinicio y backoff.

const QuotaMonitor := preload("res://addons/godot_agent/core/quota_monitor.gd")
const AgentLog := preload("res://addons/godot_agent/core/agent_log.gd")

const NOW := 1792560000  # unix fijo para los tests

var _clock: Array[int] = [NOW]


func _monitor() -> QuotaMonitor:
	var monitor := QuotaMonitor.new()
	monitor.setup(AgentLog.new())
	monitor.now_provider = func() -> int: return _clock[0]
	return monitor


## usage_update como lo manda el agente falso (forma real de claude-agent-acp 0.94, D22).
func _update(five_hour: float, seven_day: float, status: String = "allowed", resets_in: int = 3600) -> Dictionary:
	return {"sessionUpdate": "usage_update", "used": 1000, "size": 200000, "_meta": {"_claude/rateLimit": {
		"status": status, "rateLimitType": "five_hour", "resetsAt": float(NOW + resets_in), "isUsingOverage": false,
		"unifiedWindows": {"five_hour": {"utilization": five_hour, "resetsAt": float(NOW + resets_in)}, "seven_day": {"utilization": seven_day, "resetsAt": float(NOW + 5 * 86400)}}}}}


func _quota_entries(monitor: QuotaMonitor) -> Array:
	return monitor.agent_log.entries().filter(func(entry: Dictionary) -> bool: return entry.channel == AgentLog.CH_QUOTA)


func test_patterns_file() -> void:
	var patterns := QuotaMonitor.load_patterns(QuotaMonitor.PATTERNS_PATH)
	assert_true(patterns.size() >= 8, "carga los patrones del archivo editable")


func test_usage_update_and_states() -> void:
	var monitor := _monitor()
	monitor.observe_update({"sessionUpdate": "usage_update", "used": 1200, "size": 200000})
	assert_eq(monitor.state, QuotaMonitor.State.UNKNOWN, "sin _meta: desconocido")
	assert_false(monitor.has_data(), "sin datos de cuota")
	monitor.observe_update(_update(0.63, 0.47))
	assert_eq(monitor.state, QuotaMonitor.State.NORMAL, "63 %: normal")
	assert_eq(monitor.utilization("five_hour"), 0.63, "ventana actual")
	assert_eq(monitor.resets_at("seven_day"), NOW + 5 * 86400, "reinicio semanal")
	assert_eq(monitor.describe_window("five_hour"), "Ventana 63 % · reinicia en 1 h", "texto de la ventana")
	var summary := str(_quota_entries(monitor)[1].message)
	assert_true(summary.contains("five_hour 63 % hasta") and summary.contains("seven_day 47 % hasta"), "log con las ventanas: " + summary)
	monitor.observe_update(_update(0.5, 0.8))
	assert_eq(monitor.state, QuotaMonitor.State.WARNING, "la semanal al 80 % avisa")
	monitor.observe_update(_update(0.91, 0.8, "allowed_warning"))
	assert_eq(monitor.state, QuotaMonitor.State.PAUSE_SCHEDULED, "91 %: pausa programada")
	assert_eq(monitor.pause_resets_at(), NOW + 3600, "la pausa espera el reinicio de la ventana más llena")
	assert_true(monitor.rule_text().contains("se pausa al terminar la tarea o el turno en curso"), "regla activa: " + monitor.rule_text())
	monitor.configure(0.75, 0.9, false)
	assert_eq(monitor.state, QuotaMonitor.State.WARNING, "pausa desactivada: solo aviso")
	monitor.configure(0.95, 0.99, true)
	assert_eq(monitor.state, QuotaMonitor.State.NORMAL, "umbrales configurables")
	var transitions := _quota_entries(monitor).filter(func(entry: Dictionary) -> bool: return str(entry.message).begins_with("estado de la cuota"))
	assert_true(transitions.size() >= 4, "cada cambio de estado se loguea (%d)" % transitions.size())


func test_limit_with_reset() -> void:
	var monitor := _monitor()
	monitor.observe_update(_update(0.9, 0.4))
	# El agente falso manda primero la cuota "rejected" y después el texto y el error.
	monitor.observe_update(_update(1.0, 0.5, "rejected", 120))
	assert_eq(monitor.state, QuotaMonitor.State.LIMITED, "status rejected: limitado")
	assert_eq(monitor.limited_until, NOW + 120, "hasta el resetsAt de la cuota")
	assert_true(monitor.observe_agent_text("You've hit your limit · resets 3pm (America/Argentina/Buenos_Aires)"), "prefijo del SDK")
	assert_eq(monitor.limited_until, NOW + 120, "el resetsAt exacto le gana a la hora redondeada del texto")
	assert_true(monitor.observe_prompt_error({"code": -32603, "message": "Internal error: You've hit your limit", "data": {"errorKind": "rate_limit"}}), "error del prompt")
	assert_eq(monitor.seconds_until_retry(), 120, "cuenta regresiva")
	assert_false(monitor.retry_due(), "todavía no")
	_clock[0] = NOW + 121
	assert_true(monitor.retry_due(), "llegó la hora")
	monitor.observe_turn_ok()
	assert_eq(monitor.state, QuotaMonitor.State.PAUSE_SCHEDULED, "al volver, recalcula con lo último informado")
	_clock[0] = NOW


func test_limit_without_reset_backoff() -> void:
	var monitor := _monitor()
	assert_true(monitor.observe_prompt_error({"code": -32603, "message": "Internal error", "data": {"errorKind": "rate_limit"}}), "errorKind rate_limit")
	assert_eq(monitor.state, QuotaMonitor.State.LIMITED, "limitado")
	assert_eq(monitor.limited_until, 0, "sin hora de reinicio")
	assert_eq(monitor.seconds_until_retry(), 5 * 60, "primer intento a los 5 min")
	var expected: Array[int] = [10, 20, 60, 60]
	for minutes: int in expected:
		monitor.note_retry()
		monitor.observe_prompt_error({"code": -32603, "message": "Internal error", "data": {"errorKind": "rate_limit"}})
		assert_eq(monitor.seconds_until_retry(), minutes * 60, "backoff de %d min" % minutes)
	monitor.observe_turn_ok()
	assert_eq(monitor.state, QuotaMonitor.State.UNKNOWN, "sin datos de ventanas: desconocido")
	monitor.observe_prompt_error({"code": -32603, "message": "Internal error", "data": {"errorKind": "rate_limit"}})
	assert_eq(monitor.seconds_until_retry(), 5 * 60, "el backoff vuelve a empezar")
	assert_false(monitor.observe_prompt_error({"code": -32603, "message": "Internal error: boom"}), "otro error no es límite")
	assert_true(str(_quota_entries(monitor)[0].message).contains("(límite)"), "marca el de límite")


func test_limit_text() -> void:
	var monitor := _monitor()
	assert_false(monitor.observe_agent_text("Listo, agregué el nodo."), "texto normal")
	assert_false(monitor.observe_agent_text("Agregué rate limiting al cliente de red: ya no llega al usage limit."), "no confunde prosa")
	assert_true(monitor.observe_agent_text("Texto previo\nClaude AI usage limit reached|1792600000"), "formato viejo, en cualquier línea")
	assert_eq(monitor.limited_until, 1792600000, "hora del formato viejo")


func test_parse_reset_time() -> void:
	var offset := int(Time.get_time_zone_from_system().get("bias", 0)) * 60
	var local_midnight := NOW + offset - posmod(NOW + offset, 86400) - offset
	var local_hour := posmod(NOW + offset, 86400) / 3600
	var later := posmod(local_hour + 2, 24)
	var expected := local_midnight + later * 3600 + (86400 if later < local_hour + 2 else 0)
	assert_eq(QuotaMonitor.parse_reset_time("You've hit your limit · resets %02d:00" % later, NOW), expected, "HH:MM, dentro de 2 h")
	var hour12 := later % 12
	var text12 := "resets %d%s (UTC)" % [12 if hour12 == 0 else hour12, "pm" if later >= 12 else "am"]
	assert_eq(QuotaMonitor.parse_reset_time(text12, NOW), expected, "formato am/pm: " + text12)
	var earlier := posmod(local_hour - 1, 24)
	var tomorrow := QuotaMonitor.parse_reset_time("reinicia a las %d:30" % earlier, NOW)
	assert_true(tomorrow > NOW and tomorrow - NOW <= 86400, "una hora que ya pasó es mañana")
	assert_eq(QuotaMonitor.parse_reset_time("Claude AI usage limit reached|1792600000", NOW), 1792600000, "unix")
	assert_eq(QuotaMonitor.parse_reset_time("You've hit your limit", NOW), 0, "sin hora")


func test_format_duration() -> void:
	assert_eq(QuotaMonitor.format_duration(35), "35 s", "segundos")
	assert_eq(QuotaMonitor.format_duration(4 * 60 + 10), "4 min", "minutos")
	assert_eq(QuotaMonitor.format_duration(2 * 3600 + 10 * 60), "2 h 10 min", "horas")
	assert_eq(QuotaMonitor.format_duration(3 * 86400), "3 días", "días")
