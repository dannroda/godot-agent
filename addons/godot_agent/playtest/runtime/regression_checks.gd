extends RefCounted
## Invariantes por frame y presupuestos de rendimiento de un game_script (m11-44): game.invariant() y
## game.budget(). Un invariante se evalúa en cada physics frame mientras corre el script; el primero
## que se rompe guarda el frame y el valor y deja de evaluarse. Los presupuestos usan los monitores
## (m11-43) desde que se declaran hasta que el script termina. Ideas de Beckett v1.9 (perf asserts y
## baselines) y v1.16 (invariantes en cada physics frame).
##
## Qué hace fallar: un invariante roto, un presupuesto con límite escrito, o uno de conteo por encima
## de su base. Las bases de conteo son deterministas: una sola, compartida, en el JSON de la regresión.
## Las de tiempo son de cada máquina y viven fuera del repo (PlaytestRegressions.TIME_BASELINES); un
## presupuesto de tiempo sin límite solo avisa, porque la regresión corre en otras máquinas (CI, otra PC).

const Monitors := preload("monitors.gd")

## Las líneas que hacen fallar la regresión (PlaytestRegressions.passed las busca).
const BROKEN := "Invariant broken:"
const OVER := "Over budget:"
const WARNING := "Budget warning:"
## La línea con lo medido, que el runner guarda como base en el primer run verde: «MEASURED (máquina): {json}».
const MEASURED := "Budgets measured"

const TIME_METRICS: PackedStringArray = ["frame_ms_p95", "physics_ms_p95"]
const COUNT_METRICS: PackedStringArray = ["draw_calls_max", "nodes_max", "orphans_end"]
const TIME_TOLERANCE := 1.5
const COUNT_TOLERANCE := 1.25
## Por encima de esto, los invariantes son caros y el reporte lo dice.
const SLOW_CHECKS_MS := 1.0

## Bases de conteo, {métrica: valor} (el campo `baselines` del JSON de la regresión).
var baselines: Dictionary = {}
## Bases de tiempo de esta máquina, {runner: {métrica: valor}}: la probe se queda con la de su runner.
var time_baselines: Dictionary = {}
## Bajo un mutante (m11-41) un presupuesto de tiempo no hace fallar: entre procesos hay ruido.
var time_budgets_warn := false

var _tree: SceneTree
var _invariants: Array[Dictionary] = []
var _frames := 0
var _usec := 0
var _pending_usec := 0
var _budgets: Array[Dictionary] = []
var _monitors: Monitors
var _nodes_max := 0.0
var _orphans_start := 0.0


func _init(tree: SceneTree) -> void:
	_tree = tree


## Con o sin ventana: headless no dibuja y corre a otro ritmo, así que sus tiempos tienen otra base.
static func runner() -> String:
	return "headless" if DisplayServer.get_name() == "headless" else "window"


func invariant(name: String, check: Callable, value: Callable = Callable()) -> void:
	_invariants.append({"name": name, "check": check, "value": value, "broken": {}})
	if not _tree.physics_frame.is_connected(_check_invariants):
		_tree.physics_frame.connect(_check_invariants)


## "" si se declaró, o por qué no.
func budget(metric: String, limit: Variant = null) -> String:
	if not metric in TIME_METRICS and not metric in COUNT_METRICS:
		return "unknown budget «%s»: use one of %s" % [metric, ", ".join(TIME_METRICS + COUNT_METRICS)]
	if limit != null and not (limit is float or limit is int):
		return "the limit of «%s» has to be a number" % metric
	_budgets.append({"metric": metric, "limit": limit})
	if _monitors == null:
		_monitors = Monitors.new()
		_monitors.start()
		_orphans_start = Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)
		_nodes_max = Performance.get_monitor(Performance.OBJECT_NODE_COUNT)
		_tree.process_frame.connect(_tick_budgets)
	return ""


func _check_invariants() -> void:
	var start := Time.get_ticks_usec()
	_frames += 1
	for check: Dictionary in _invariants:
		if not (check.broken as Dictionary).is_empty():
			continue
		var held: Variant = check.check.call()
		if held is bool and held:
			continue
		var shown: Variant = held
		if held is bool:
			shown = check.value.call() if check.value.is_valid() else false
		check.broken = {"frame": Engine.get_physics_frames(), "time": Time.get_ticks_msec() / 1000.0,
			"value": "null (an error in the check?)" if shown == null else str(shown)}
	var spent := Time.get_ticks_usec() - start
	_usec += spent
	_pending_usec += spent


func _tick_budgets() -> void:
	_monitors.tick(_pending_usec / 1000.0)
	_pending_usec = 0
	_nodes_max = maxf(_nodes_max, Performance.get_monitor(Performance.OBJECT_NODE_COUNT))


## Lo medido para los presupuestos; null en lo que no se pudo medir.
func measure() -> Dictionary:
	if _monitors == null:
		return {}
	var measured := _monitors.measure()
	measured["nodes_max"] = _nodes_max
	measured["orphans_end"] = maxf(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT) - _orphans_start, 0.0)
	return measured


## Deja de evaluar y devuelve {lines, violations: [{kind, name, frame, time, value, limit}]}.
func finish() -> Dictionary:
	if _tree.physics_frame.is_connected(_check_invariants):
		_tree.physics_frame.disconnect(_check_invariants)
	if _tree.process_frame.is_connected(_tick_budgets):
		_tree.process_frame.disconnect(_tick_budgets)
	var lines: PackedStringArray = []
	var violations: Array[Dictionary] = []
	for check: Dictionary in _invariants:
		var broken: Dictionary = check.broken
		if broken.is_empty():
			continue
		lines.append("%s «%s» at physics frame %d (game time %.2f s): %s" % [BROKEN, check.name, broken.frame, broken.time, broken.value])
		violations.append({"kind": "invariant", "name": check.name, "frame": broken.frame, "time": broken.time, "value": broken.value})
	if not _invariants.is_empty():
		var per_frame := _usec / 1000.0 / maxi(_frames, 1)
		lines.append("Invariants: %d of %d held over %d physics frames (%.3f ms per frame%s)." % [_invariants.size() - violations.size(), _invariants.size(), _frames, per_frame,
			", slow: keep the checks cheap; this time is not counted in frame_ms" if per_frame > SLOW_CHECKS_MS else ""])
	var measured := measure()
	var times: Dictionary = time_baselines.get(runner(), {}) if time_baselines.get(runner()) is Dictionary else {}
	for declared: Dictionary in _budgets:
		var base: Variant = times.get(declared.metric) if declared.metric in TIME_METRICS else baselines.get(declared.metric)
		var verdict := judge(declared.metric, measured.get(declared.metric), declared.limit, base, time_budgets_warn)
		lines.append(verdict.line)
		if verdict.failed:
			violations.append({"kind": "budget", "name": declared.metric, "value": measured.get(declared.metric), "limit": verdict.limit})
	# Solo lo que se compara con la base: un presupuesto con límite escrito no guarda nada en el JSON.
	var shown := {}
	for declared: Dictionary in _budgets:
		if declared.limit == null and measured.get(declared.metric) != null:
			shown[declared.metric] = snappedf(float(measured[declared.metric]), 0.01)
	if not shown.is_empty():
		lines.append("%s (%s): %s" % [MEASURED, runner(), JSON.stringify(shown)])
	return {"lines": lines, "violations": violations}


## Un presupuesto: {line, failed, limit}. `base`: la compartida (conteos) o la de esta máquina (tiempos), o null.
static func judge(metric: String, value: Variant, limit: Variant, base: Variant, time_warn: bool = false) -> Dictionary:
	var timed := metric in TIME_METRICS
	var unit := " ms" if timed else ""
	if value == null:
		return {"line": "Budget %s: not measured without rendering (headless)." % metric, "failed": false, "limit": limit}
	var got := float(value)
	if limit != null:
		if got <= float(limit):
			return {"line": "Budget %s: %s%s (limit %s)." % [metric, _number(got), unit, _number(float(limit))], "failed": false, "limit": limit}
		if timed and time_warn:
			return {"line": "%s %s %s%s > %s (time budgets do not fail under a mutant)." % [WARNING, metric, _number(got), unit, _number(float(limit))], "failed": false, "limit": limit}
		return {"line": "%s %s %s%s > %s." % [OVER, metric, _number(got), unit, _number(float(limit))], "failed": true, "limit": limit}
	if base == null:
		return {"line": "Budget %s: %s%s (no baseline%s yet: a passing run records it)." % [metric, _number(got), unit, " on this machine" if timed else ""], "failed": false, "limit": null}
	var base_value := float(base)
	var allowed := base_value * TIME_TOLERANCE if timed else float(ceili(base_value * COUNT_TOLERANCE))
	var whose := "this machine's baseline" if timed else "the baseline"
	var ratio := "%.1f× %s (%s%s)" % [got / base_value, whose, _number(base_value), unit] if base_value > 0.0 else "%s is %s" % [whose, _number(base_value)]
	if got <= allowed:
		return {"line": "Budget %s: %s%s, %s." % [metric, _number(got), unit, ratio], "failed": false, "limit": allowed}
	if timed:
		return {"line": "%s %s %s%s, %s." % [WARNING, metric, _number(got), unit, ratio], "failed": false, "limit": allowed}
	return {"line": "%s %s %s, %s." % [OVER, metric, _number(got), ratio], "failed": true, "limit": allowed}


## Lo medido para las bases en una salida: {runner, values: {métrica: valor}}, o {}.
static func measured_in(output: String) -> Dictionary:
	var found := RegEx.create_from_string("(?m)^%s \\((.+)\\): (\\{.*\\})$" % MEASURED).search(output)
	if not found:
		return {}
	var parsed: Variant = JSON.parse_string(found.get_string(2))
	return {"runner": found.get_string(1), "values": parsed} if parsed is Dictionary else {}


static func _number(value: float) -> String:
	return str(int(value)) if is_equal_approx(value, roundf(value)) else "%.1f" % value
