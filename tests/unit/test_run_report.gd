extends "test_case.gd"
## Informe de métricas del One-shot (D39): tareas con duración, tools, checks, eventos y Markdown.

const RunReport := preload("res://addons/godot_agent/oneshot/run_report.gd")


func _plan(statuses: Array) -> Array:
	var plan := []
	for i in statuses.size():
		plan.append({"content": "Tarea %d" % (i + 1), "status": statuses[i]})
	return plan


func _sample() -> RunReport:
	var report := RunReport.new()
	report.observe_plan(_plan(["in_progress", "pending"]), 1000)
	report.observe_plan(_plan(["completed", "in_progress"]), 61000)
	report.observe_tool("godot.run_scene", false)
	report.observe_tool("godot.run_scene", true)
	report.observe_tool("Edit", false)
	report.observe_checks([{"label": "Salto", "status": "fail"}, {"label": "Puntaje", "status": "pass"}])
	report.observe_checks([{"label": "Salto", "status": "fail"}])
	report.count("turns", 4)
	report.count("permissions_asked")
	report.count("loops")
	return report


func test_build() -> void:
	var built := _sample().build({
		"id": "20261022-120000", "goal": "Pong", "finish_reason": "Terminado.", "duration_ms": 125000,
		"budgets": {"time": 45, "tokens": 0, "playtests": 8}, "used": {"time": 125.0, "tokens": 3000, "playtests": 2},
		"checks": [{"label": "Salto", "status": "fail"}, {"label": "Puntaje", "status": "pass"}],
		"checkpoints": [{"name": "cp1", "label": "Estado inicial"}],
	})
	assert_eq(built.duration_s, 125, "duración")
	assert_eq(built.tasks, [{"task": "Tarea 1", "status": "completed", "duration_s": 60}, {"task": "Tarea 2", "status": "in_progress", "duration_s": 64}], "tareas: la abierta dura hasta el final")
	assert_eq(built.tools[0], {"tool": "godot.run_scene", "count": 2, "failed": 1}, "tools ordenadas por uso")
	assert_eq(built.checks, [{"label": "Salto", "status": "fail", "failures": 2}, {"label": "Puntaje", "status": "pass", "failures": 0}], "checks con fallas")
	assert_eq(built.events.turns, 4, "eventos")


func test_markdown() -> void:
	var built := _sample().build({"goal": "Pong", "finish_reason": "Terminado.", "duration_ms": 3725000, "used": {"time": 3725.0}, "budgets": {"time": 0}, "checks": [{"label": "Salto", "status": "fail"}], "changes": {"files": [{"path": "main.gd", "added": 10, "removed": 2}], "added": 10, "removed": 2}})
	var text := RunReport.to_markdown(built)
	for expected: String in ["**Objetivo**: Pong", "1 h 02 min", "Tiempo: 1 h 02 min (sin límite)", "- [x] Tarea 1 · 1 min 00 s", "| `godot.run_scene` | 2 | 1 |", "| Salto |", "Loops detectados: 1", "### Archivos (1 · +10 −2)", "`main.gd` +10 −2"]:
		assert_true(text.contains(expected), "markdown: %s" % expected)


func test_persist_and_labels() -> void:
	var copy := RunReport.new()
	copy.apply(JSON.parse_string(JSON.stringify(_sample().to_dict())))
	var built := copy.build({"duration_ms": 61000})
	assert_eq(built.tasks.size(), 2, "tareas tras guardar y cargar")
	assert_eq(built.tools.size(), 2, "tools tras guardar y cargar")
	assert_eq(RunReport.tool_label("mcp__godot__run_scene", "run_scene", "", "other"), "godot.run_scene", "tool del addon")
	assert_eq(RunReport.tool_label("Edit player.gd", "", "Edit", "edit"), "Edit", "toolName de Claude Code")
	assert_eq(RunReport.tool_label("mcp__other__thing", "", "", "other"), "other.thing", "otra tool MCP")
	assert_eq(RunReport.tool_label("Read main.gd", "", "", "read"), "Read", "sin toolName")
	assert_eq(RunReport.format_duration(59), "59 s", "segundos")
