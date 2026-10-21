extends "test_case.gd"
## QuotaMonitor en modo observación (spec §10.1, D22): usage_update con cuota, avisos y errores de límite.

const QuotaMonitor := preload("res://addons/godot_agent/core/quota_monitor.gd")
const AgentLog := preload("res://addons/godot_agent/core/agent_log.gd")


func _monitor() -> QuotaMonitor:
	var monitor := QuotaMonitor.new()
	monitor.setup(AgentLog.new())
	return monitor


func _quota_entries(monitor: QuotaMonitor) -> Array:
	return monitor.agent_log.entries().filter(func(entry: Dictionary) -> bool: return entry.channel == AgentLog.CH_QUOTA)


func test_patterns_file() -> void:
	var patterns := QuotaMonitor.load_patterns(QuotaMonitor.PATTERNS_PATH)
	assert_true(patterns.size() >= 8, "carga los patrones del archivo editable")


func test_usage_update() -> void:
	var monitor := _monitor()
	monitor.observe_update({"sessionUpdate": "usage_update", "used": 1200, "size": 200000})
	assert_true(monitor.last_rate_limit.is_empty(), "sin _meta no hay cuota")
	var info := {"status": "allowed_warning", "rateLimitType": "five_hour", "utilization": 0.82, "surpassedThreshold": 0.75, "resetsAt": 1792600000}
	monitor.observe_update({"sessionUpdate": "usage_update", "used": 1500, "size": 200000, "_meta": {"_claude/rateLimit": info}})
	assert_eq(monitor.last_rate_limit, info, "guarda el SDKRateLimitInfo crudo")
	var entries := _quota_entries(monitor)
	assert_eq(entries.size(), 2, "una entrada por usage_update")
	assert_true(str(entries[1].message).contains("allowed_warning · five_hour · 82 % · umbral 75 % · reinicio"), "resumen legible")
	assert_true(str(entries[1].raw).contains("_claude/rateLimit"), "raw completo")
	# Forma real de claude-agent-acp 0.94 (D22): ventanas unificadas con fracciones 0–1.
	monitor.observe_update({"sessionUpdate": "usage_update", "used": 26939, "size": 400000, "_meta": {"_claude/rateLimit": {
		"status": "allowed", "rateLimitType": "five_hour", "resetsAt": 1792572000.0, "isUsingOverage": false,
		"unifiedWindows": {"five_hour": {"resetsAt": 1792572000.0, "utilization": 0.63}, "seven_day": {"resetsAt": 1793062800.0, "utilization": 0.47}}}}})
	var summary := str(_quota_entries(monitor).back().message)
	assert_true(summary.contains("five_hour 63 % hasta") and summary.contains("seven_day 47 % hasta"), "ventanas: " + summary)


func test_limit_text() -> void:
	var monitor := _monitor()
	assert_false(monitor.observe_agent_text("Listo, agregué el nodo."), "texto normal")
	assert_true(monitor.observe_agent_text("You've hit your limit · resets 3pm (America/Argentina/Buenos_Aires)"), "prefijo del SDK")
	assert_eq(monitor.last_limit_event.source, "texto", "evento de límite por texto")
	assert_false(monitor.observe_agent_text("Agregué rate limiting al cliente de red: ya no llega al usage limit."), "no confunde prosa")
	assert_true(monitor.observe_agent_text("Texto previo\nClaude AI usage limit reached|1792600000"), "formato viejo, en cualquier línea")


func test_prompt_errors() -> void:
	var monitor := _monitor()
	assert_true(monitor.observe_prompt_error({"code": -32603, "message": "Internal error", "data": {"errorKind": "rate_limit"}}), "errorKind rate_limit")
	assert_false(monitor.observe_prompt_error({"code": -32603, "message": "Internal error: boom"}), "otro error")
	assert_eq(_quota_entries(monitor).size(), 2, "loguea todos los errores de prompt")
	assert_true(str(_quota_entries(monitor)[0].message).contains("(límite)"), "marca el de límite")
