@tool
extends RefCounted
## Informe de un One-shot con datos medidos (D39): duración por tarea, tools usadas y fallidas,
## checks y cuántas veces fallaron, permisos, errores, pausas y loops. El run lo alimenta mientras
## corre; al terminar, `build` arma el informe que se muestra y se guarda en `<id>.report.json`
## para comparar corridas.

const VERSION := 1
const MAX_TURNS := 2000

## tarea (content) -> {status, started_ms, finished_ms}; ms desde el inicio del run, -1 = no se vio.
var tasks: Dictionary = {}
## orden en que aparecieron las tareas
var task_order: PackedStringArray = []
## tool -> {count, failed, ms}
var tools: Dictionary = {}
## Un registro por turno: {started_ms, ms, reason, tools} (m6-16).
var turns: Array[Dictionary] = []
## Tiempo sin trabajar, por motivo: quota (pausa o límite), paused (usuario), spec_review.
var waits: Dictionary = {}
## label -> fallas reportadas
var check_failures: Dictionary = {}
## evento -> cuenta: turns, turn_errors, permissions_asked, permissions_denied, quota_pauses,
## limited, loops, guidance
var events: Dictionary = {}


func reset() -> void:
	tasks.clear()
	task_order.clear()
	tools.clear()
	turns.clear()
	waits.clear()
	check_failures.clear()
	events.clear()


func count(event: String, amount: int = 1) -> void:
	events[event] = int(events.get(event, 0)) + amount


## Plan nuevo: marca cuándo empezó (in_progress) y terminó (completed) cada tarea.
func observe_plan(plan: Array, elapsed_ms: int) -> void:
	for entry: Variant in plan:
		if not entry is Dictionary:
			continue
		var content := str(entry.get("content", "")).strip_edges()
		if content.is_empty():
			continue
		if not tasks.has(content):
			tasks[content] = {"status": "pending", "started_ms": -1, "finished_ms": -1}
			task_order.append(content)
		var task: Dictionary = tasks[content]
		var status := str(entry.get("status", "pending"))
		task.status = status
		if status == "in_progress" and int(task.started_ms) < 0:
			task.started_ms = elapsed_ms
		elif status == "completed" and int(task.finished_ms) < 0:
			task.finished_ms = elapsed_ms


## Una tool call terminada; `name` es "godot.<tool>" para las del addon.
func observe_tool(name: String, failed: bool, duration_ms: int = 0) -> void:
	var stats: Dictionary = tools.get(name, {"count": 0, "failed": 0, "ms": 0})
	stats.count += 1
	stats.ms = int(stats.get("ms", 0)) + maxi(duration_ms, 0)
	if failed:
		stats.failed += 1
	tools[name] = stats


func observe_turn(started_ms: int, duration_ms: int, reason: String, tool_count: int) -> void:
	turns.append({"started_ms": started_ms, "ms": duration_ms, "reason": reason, "tools": tool_count})
	if turns.size() > MAX_TURNS:
		turns.remove_at(0)


func add_wait(kind: String, duration_ms: int) -> void:
	waits[kind] = int(waits.get(kind, 0)) + maxi(duration_ms, 0)


## Duración de una tarea del plan en ms (la que sigue en curso, hasta `now_ms`); -1 si no empezó.
func task_ms(content: String, now_ms: int) -> int:
	var task: Dictionary = tasks.get(content.strip_edges(), {})
	if task.is_empty() or int(task.started_ms) < 0:
		return -1
	var finished := int(task.finished_ms)
	return (finished if finished >= 0 else now_ms) - int(task.started_ms)


func observe_checks(checks: Array) -> void:
	for check: Variant in checks:
		if check is Dictionary and str(check.get("status", "")) == "fail":
			var label := str(check.get("label", ""))
			check_failures[label] = int(check_failures.get(label, 0)) + 1


## Nombre de la tool para el conteo: la del addon sin prefijo, la de Claude Code (toolName) o el título.
static func tool_label(title: String, godot_tool: String, tool_name: String, kind: String) -> String:
	if not godot_tool.is_empty():
		return "godot." + godot_tool
	if not tool_name.is_empty():
		return tool_name
	if title.begins_with("mcp__"):
		return title.trim_prefix("mcp__").replace("__", ".")
	return title.get_slice(" ", 0) if not title.is_empty() else kind


func to_dict() -> Dictionary:
	return {"tasks": tasks, "task_order": task_order, "tools": tools, "turns": turns, "waits": waits, "check_failures": check_failures, "events": events}


func apply(data: Dictionary) -> void:
	reset()
	if data.get("tasks") is Dictionary:
		tasks = data.tasks
	if data.get("task_order") is Array:
		task_order = PackedStringArray(data.task_order)
	if data.get("tools") is Dictionary:
		tools = data.tools
	if data.get("turns") is Array:
		turns.assign((data.turns as Array).filter(func(turn: Variant) -> bool: return turn is Dictionary))
	if data.get("waits") is Dictionary:
		waits = data.waits
	if data.get("check_failures") is Dictionary:
		check_failures = data.check_failures
	if data.get("events") is Dictionary:
		events = data.events


## `run`: lo que el run sabe al terminar (id, goal, finish_reason, duration_ms, budgets, used,
## checks, checkpoints, changes).
func build(run: Dictionary) -> Dictionary:
	var duration_ms := int(run.get("duration_ms", 0))
	var task_rows: Array[Dictionary] = []
	for content: String in task_order:
		var task: Dictionary = tasks[content]
		var started := int(task.started_ms)
		var finished := int(task.finished_ms)
		var seconds := -1
		if started >= 0:
			seconds = roundi(((finished if finished >= 0 else duration_ms) - started) / 1000.0)
		task_rows.append({"task": content, "status": task.status, "duration_s": seconds})
	var tool_rows: Array[Dictionary] = []
	for name: String in tools:
		tool_rows.append({"tool": name, "count": int(tools[name].count), "failed": int(tools[name].failed), "seconds": roundi(int(tools[name].get("ms", 0)) / 1000.0)})
	tool_rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.count > b.count or (a.count == b.count and a.tool < b.tool))
	var check_rows: Array[Dictionary] = []
	for check: Variant in run.get("checks", []):
		if check is Dictionary:
			var label := str(check.get("label", ""))
			check_rows.append({"label": label, "status": str(check.get("status", "")), "failures": int(check_failures.get(label, 0))})
	var turn_ms: Array = turns.map(func(turn: Dictionary) -> int: return int(turn.get("ms", 0)))
	var turn_total := 0
	for ms: int in turn_ms:
		turn_total += ms
	var timing := {
		"working_s": roundi(turn_total / 1000.0),
		"turns": turns.size(),
		"turn_avg_s": roundi(turn_total / 1000.0 / turns.size()) if not turns.is_empty() else 0,
		"turn_max_s": roundi(turn_ms.max() / 1000.0) if not turns.is_empty() else 0,
		"waiting_quota_s": roundi(int(waits.get("quota", 0)) / 1000.0),
		"paused_s": roundi(int(waits.get("paused", 0)) / 1000.0),
		"spec_review_s": roundi(int(waits.get("spec_review", 0)) / 1000.0),
	}
	return {
		"version": VERSION,
		"timing": timing,
		"id": str(run.get("id", "")),
		"goal": str(run.get("goal", "")),
		"finish_reason": str(run.get("finish_reason", "")),
		"finished_at": Time.get_datetime_string_from_system(false, true),
		"duration_s": roundi(duration_ms / 1000.0),
		"budgets": run.get("budgets", {}),
		"used": run.get("used", {}),
		"tasks": task_rows,
		"tools": tool_rows,
		"checks": check_rows,
		"checkpoints": run.get("checkpoints", []),
		"events": events.duplicate(),
		"changes": run.get("changes", {}),
		"files_dir": str(run.get("files_dir", "")),
	}


## El informe en Markdown: para mostrarlo y para copiarlo.
static func to_markdown(report: Dictionary) -> String:
	var used: Dictionary = report.get("used", {})
	var budgets: Dictionary = report.get("budgets", {})
	var events: Dictionary = report.get("events", {})
	var lines: PackedStringArray = [
		"## Informe del One-shot",
		"",
		"**Objetivo**: %s" % str(report.get("goal", "")),
		"**Cierre**: %s" % str(report.get("finish_reason", "")),
		"**Duración**: %s · **turnos**: %d" % [format_duration(int(report.get("duration_s", 0))), int(events.get("turns", 0))],
		"",
		"### Presupuestos",
		"- Tiempo: %s%s" % [format_duration(roundi(float(used.get("time", 0)))), _limit(budgets.get("time", 0), " min")],
		"- Tokens: %d%s" % [int(used.get("tokens", 0)), _limit(budgets.get("tokens", 0), "")],
		"- Playtests: %d%s" % [int(used.get("playtests", 0)), _limit(budgets.get("playtests", 0), "")],
	]
	var tasks: Array = report.get("tasks", [])
	if not tasks.is_empty():
		lines.append_array(["", "### Plan"])
		for task: Dictionary in tasks:
			var seconds := int(task.duration_s)
			lines.append("- [%s] %s%s" % ["x" if task.status == "completed" else " ", task.task, (" · %s" % format_duration(seconds)) if seconds >= 0 else ""])
	var timing: Dictionary = report.get("timing", {})
	if not timing.is_empty():
		lines.append_array(["", "### Tiempos"])
		lines.append("- Trabajando: %s en %d turnos (promedio %s, el más largo %s)" % [format_duration(int(timing.get("working_s", 0))), int(timing.get("turns", 0)),
			format_duration(int(timing.get("turn_avg_s", 0))), format_duration(int(timing.get("turn_max_s", 0)))])
		var waits: PackedStringArray = []
		for pair: Array in [["waiting_quota_s", "esperando la cuota"], ["paused_s", "en pausa"], ["spec_review_s", "revisando el spec"]]:
			if int(timing.get(pair[0], 0)) > 0:
				waits.append("%s %s" % [pair[1], format_duration(int(timing[pair[0]]))])
		if not waits.is_empty():
			lines.append("- Sin trabajar: " + ", ".join(waits))
	var tools: Array = report.get("tools", [])
	if not tools.is_empty():
		lines.append_array(["", "### Tools", "| Tool | Usos | Fallas | Tiempo |", "|---|---|---|---|"])
		for row: Dictionary in tools:
			lines.append("| `%s` | %d | %d | %s |" % [row.tool, row.count, row.failed, format_duration(int(row.get("seconds", 0)))])
	var checks: Array = report.get("checks", [])
	if not checks.is_empty():
		lines.append_array(["", "### Checks", "| Check | Estado | Veces que falló |", "|---|---|---|"])
		for row: Dictionary in checks:
			lines.append("| %s | %s | %d |" % [str(row.label).replace("|", "/"), row.status, row.failures])
	lines.append_array(["", "### Eventos"])
	lines.append("- Permisos pedidos: %d · denegados: %d" % [int(events.get("permissions_asked", 0)), int(events.get("permissions_denied", 0))])
	lines.append("- Turnos con error: %d · pausas por cuota: %d · límites del plan: %d" % [int(events.get("turn_errors", 0)), int(events.get("quota_pauses", 0)), int(events.get("limited", 0))])
	lines.append("- Loops detectados: %d · guías del usuario: %d · cambios de presupuesto: %d" % [int(events.get("loops", 0)), int(events.get("guidance", 0)), int(events.get("budget_changes", 0))])
	if not str(report.get("files_dir", "")).is_empty():
		lines.append("- Spec, progreso y QA: `%s/`" % report.files_dir)
	var checkpoints: Array = report.get("checkpoints", [])
	if not checkpoints.is_empty():
		lines.append("- Checkpoints: " + ", ".join(checkpoints.map(func(cp: Variant) -> String: return "%s %s" % [cp.get("name", ""), cp.get("label", "")] if cp is Dictionary else str(cp))))
	var changes: Dictionary = report.get("changes", {})
	if not changes.is_empty():
		var files: Array = changes.get("files", [])
		lines.append_array(["", "### Archivos (%d · +%d −%d)" % [files.size(), int(changes.get("added", 0)), int(changes.get("removed", 0))]])
		for file: Variant in files:
			if file is Dictionary:
				lines.append("- `%s` +%d −%d" % [file.get("path", ""), int(file.get("added", 0)), int(file.get("removed", 0))])
	return "\n".join(lines) + "\n"


## Para duraciones cortas (tools): "850 ms", "5,5 s"; desde un minuto, como format_duration.
static func format_ms(msec: int) -> String:
	if msec < 1000:
		return "%d ms" % maxi(msec, 0)
	if msec < 60000:
		return ("%.1f s" % (msec / 1000.0)).replace(".", ",")
	return format_duration(roundi(msec / 1000.0))


static func format_duration(seconds: int) -> String:
	if seconds < 60:
		return "%d s" % seconds
	if seconds < 3600:
		return "%d min %02d s" % [seconds / 60, seconds % 60]
	return "%d h %02d min" % [seconds / 3600, (seconds % 3600) / 60]


static func _limit(value: Variant, suffix: String) -> String:
	return " de %d%s" % [int(value), suffix] if int(value) > 0 else " (sin límite)"
