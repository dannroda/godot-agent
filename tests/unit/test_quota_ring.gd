extends "test_case.gd"
## Indicador de cuota de la fila del composer: tooltip sin datos, con las dos ventanas y con el
## límite; color por umbral.

const QuotaMonitor := preload("res://addons/godot_agent/core/quota_monitor.gd")
const QuotaRing := preload("res://addons/godot_agent/ui/dock/quota_ring.gd")
const AgentLog := preload("res://addons/godot_agent/core/agent_log.gd")
const AgentTheme := preload("res://addons/godot_agent/ui/agent_theme.gd")

const NOW := 1792560000


func _update(five_hour: float, seven_day: float) -> Dictionary:
	return {"sessionUpdate": "usage_update", "used": 1000, "size": 200000, "_meta": {"_claude/rateLimit": {
		"status": "allowed", "rateLimitType": "five_hour", "resetsAt": float(NOW + 3600), "isUsingOverage": false,
		"unifiedWindows": {"five_hour": {"utilization": five_hour, "resetsAt": float(NOW + 3600)}, "seven_day": {"utilization": seven_day, "resetsAt": float(NOW + 5 * 86400)}}}}}


func test_tooltip_and_colors() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var monitor := QuotaMonitor.new()
	monitor.setup(AgentLog.new())
	monitor.now_provider = func() -> int: return NOW
	var ring := QuotaRing.new()
	ring.setup(monitor, Color.ORANGE)
	tree.root.add_child(ring)
	await tree.process_frame
	assert_true(ring.hint_text.contains("first message of each session"), "sin datos explica por qué: " + ring.hint_text)
	assert_true(ring.custom_minimum_size.x > 0.0, "tiene tamaño aunque no haya datos")
	monitor.observe_update(_update(0.36, 0.84))
	assert_eq(ring.hint_text, "Plan quota\nOuter ring: Window 36 % · resets in 1 h\nInner ring: Week 84 % · resets in 5 days", "las dos ventanas")
	assert_eq(ring.color_for(0.36), Color.ORANGE, "debajo del aviso: acento")
	assert_eq(ring.color_for(0.84), AgentTheme.WARNING, "sobre el aviso: amarillo")
	assert_eq(ring.color_for(1.0), AgentTheme.ERROR, "lleno: rojo")
	monitor.observe_prompt_error({"code": -32603, "message": "rate limited", "data": {"errorKind": "rate_limit"}})
	assert_true(ring.hint_text.contains("Plan limit reached"), "con el límite: " + ring.hint_text)
	ring.queue_free()


func test_hint_rows_are_bars() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var monitor := QuotaMonitor.new()
	monitor.setup(AgentLog.new())
	monitor.now_provider = func() -> int: return NOW
	var ring := QuotaRing.new()
	ring.setup(monitor, Color.ORANGE)
	tree.root.add_child(ring)
	await tree.process_frame
	ring.set_context(50000, 200000)
	monitor.observe_update(_update(0.36, 0.84))
	var rows: Array[Dictionary] = ring.hint_rows()
	var bars := rows.filter(func(row: Dictionary) -> bool: return row.kind == "bar")
	assert_eq(bars.size(), 3, "contexto y las dos ventanas: %s" % [rows])
	assert_eq(bars[0].label, "Context", "el contexto primero")
	assert_eq(bars[0].value, 0.25, "contexto 50k de 200k")
	assert_eq(bars[0].detail, "50k / 200k · 25 %", "detalle del contexto")
	assert_eq(bars[1].label, "Window · outer ring", "dice qué anillo es")
	assert_eq(bars[1].value, 0.36, "valor de la ventana")
	assert_eq(bars[1].detail, "36 % · resets in 1 h", "porcentaje y reinicio")
	assert_eq(bars[1].color, Color.ORANGE, "color del anillo")
	assert_eq(bars[2].color, AgentTheme.WARNING, "semana sobre el aviso: amarillo")
	ring.call(&"_show_hint")
	assert_true(ring.is_hint_visible(), "el panel se abre")
	var panel: Control = ring.get(&"_hint_panel")
	assert_eq(panel.find_children("Bar", "ProgressBar", true, false).size(), 3, "una barra por fila")
	ring.queue_free()
