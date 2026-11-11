extends "test_case.gd"
## Invariantes por frame y presupuestos de las regresiones (m11-44).

const RegressionChecks := preload("res://addons/godot_agent/playtest/runtime/regression_checks.gd")
const PlaytestRegressions := preload("res://addons/godot_agent/review/playtest_regressions.gd")
const MutationTesting := preload("res://addons/godot_agent/playtest/mutation/mutation_testing.gd")


func test_invariant_breaks_once_with_frame_and_value() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var checks := RegressionChecks.new(tree)
	var state := {"calls": 0, "y": 0}
	checks.invariant("stays up", func() -> bool:
		state.calls += 1
		return state.y > -50, func() -> int: return state.y)
	checks.invariant("never null", func() -> Variant: return null)
	checks.invariant("fine", func() -> bool: return true)
	await tree.physics_frame
	await tree.physics_frame
	var calls_before: int = state.calls
	state.y = -80
	var expected_frame := Engine.get_physics_frames() + 1
	await tree.physics_frame
	state.y = -90
	await tree.physics_frame
	await tree.physics_frame
	var result := checks.finish()
	assert_eq(state.calls, calls_before + 1, "un invariante roto deja de evaluarse")
	var broken: Array = result.violations
	assert_eq(broken.size(), 2, "el roto y el que da null")
	assert_eq(broken[0].name, "stays up", "nombre")
	assert_eq(int(broken[0].frame), expected_frame, "el frame en que se rompió")
	assert_eq(broken[0].value, "-80", "el valor de ese frame, no el de después")
	assert_true(str(broken[1].value).begins_with("null"), "un chequeo que no da bool cuenta como roto")
	var text := "\n".join(result.lines)
	assert_true(text.contains(RegressionChecks.BROKEN + " «stays up» at physics frame %d" % expected_frame), text)
	assert_true(text.contains("Invariants: 1 of 3 held"), "resumen")
	state.y = -100
	await tree.physics_frame
	assert_eq(state.calls, calls_before + 1, "finish() desconecta")


func test_judge() -> void:
	var fixed := RegressionChecks.judge("frame_ms_p95", 18.2, 16.0, null)
	assert_true(fixed.failed and fixed.line.begins_with(RegressionChecks.OVER), "un límite escrito hace fallar: %s" % fixed.line)
	assert_false(RegressionChecks.judge("frame_ms_p95", 12.0, 16.0, null).failed, "bajo el límite pasa")
	var mutant := RegressionChecks.judge("frame_ms_p95", 18.2, 16.0, null, true)
	assert_true(not mutant.failed and mutant.line.begins_with(RegressionChecks.WARNING), "bajo un mutante el tiempo solo avisa")
	assert_true(RegressionChecks.judge("nodes_max", 90, 50, null, true).failed, "un conteo con límite falla también bajo un mutante")
	var slower := RegressionChecks.judge("frame_ms_p95", 19.1, null, 9.1)
	assert_false(slower.failed, "un tiempo contra la base no hace fallar")
	assert_true(slower.line.begins_with(RegressionChecks.WARNING) and slower.line.contains("2.1× this machine's baseline"), slower.line)
	assert_false(RegressionChecks.judge("frame_ms_p95", 12.0, null, 9.1).line.begins_with(RegressionChecks.WARNING), "dentro de la tolerancia no avisa")
	var nodes := RegressionChecks.judge("nodes_max", 70, null, 50)
	assert_true(nodes.failed and nodes.line.begins_with(RegressionChecks.OVER), "un conteo sobre la base falla: %s" % nodes.line)
	assert_true(nodes.line.contains("1.4× the baseline") and not nodes.line.contains("machine"), "la de conteo es compartida: %s" % nodes.line)
	assert_false(RegressionChecks.judge("nodes_max", 62, null, 50).failed, "dentro del 25 %")
	assert_true(RegressionChecks.judge("orphans_end", 1, null, 0).failed, "con base 0, un huérfano ya falla")
	var first := RegressionChecks.judge("nodes_max", 70, null, null)
	assert_true(not first.failed and first.line.contains("no baseline"), "sin base todavía pasa y lo dice")
	var headless := RegressionChecks.judge("draw_calls_max", null, 100, null)
	assert_true(not headless.failed and headless.line.contains("not measured"), "sin render no pasa en falso: lo dice")


func test_budget_declaration() -> void:
	var checks := RegressionChecks.new(Engine.get_main_loop() as SceneTree)
	assert_true(checks.budget("fps").contains("unknown budget"), "métrica desconocida")
	assert_true(checks.budget("nodes_max", "a lot").contains("number"), "límite que no es número")
	assert_eq(checks.budget("nodes_max", 100000), "", "declarado")
	checks.budget("frame_ms_p95")
	await (Engine.get_main_loop() as SceneTree).process_frame
	await (Engine.get_main_loop() as SceneTree).process_frame
	var result := checks.finish()
	assert_true((result.violations as Array).is_empty(), "nada roto: %s" % "\n".join(result.lines))
	var measured := RegressionChecks.measured_in("\n".join(result.lines))
	assert_eq(measured.get("runner"), "headless", "la línea de lo medido dice el runner, no la máquina")
	assert_true((measured.values as Dictionary).has("frame_ms_p95"), "con las que van contra la base")
	assert_false((measured.values as Dictionary).has("nodes_max"), "no las que tienen límite escrito")


func test_passed_and_baselines() -> void:
	var ok := "run() returned: true"
	assert_true(PlaytestRegressions.passed(ok), "pasa")
	assert_false(PlaytestRegressions.passed(RegressionChecks.BROKEN + " «x» at physics frame 3\n" + ok), "un invariante roto la hace fallar")
	assert_false(PlaytestRegressions.passed(RegressionChecks.OVER + " nodes_max 9 > 5.\n" + ok), "un presupuesto pasado la hace fallar")
	assert_true(PlaytestRegressions.passed(RegressionChecks.WARNING + " frame_ms_p95 19 ms\n" + ok), "un aviso no")
	var dir := temp_dir("baselines")
	var path := dir.path_join("r.json")
	var times_file := dir.path_join("times.json")
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify({"goal": "g", "scene": "res://x.tscn", "code": "func run(game):\n\treturn true"}))
	file.close()
	var output := "%s (headless): {\"nodes_max\": 40, \"frame_ms_p95\": 2.5}\n%s" % [RegressionChecks.MEASURED, ok]
	assert_true(PlaytestRegressions.record_baselines(path, output, times_file), "el primer run verde guarda las bases")
	var saved: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	assert_eq(saved.baselines, {"nodes_max": 40.0}, "en el JSON versionado, solo los conteos y sin máquina")
	assert_eq(saved.code, "func run(game):\n\treturn true", "el resto queda igual")
	var times: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(times_file))
	assert_eq(times, {path + "|headless": {"frame_ms_p95": 2.5}}, "los tiempos fuera del repo, por regresión y runner")
	var later := "%s (headless): {\"nodes_max\": 60, \"frame_ms_p95\": 9}" % RegressionChecks.MEASURED
	assert_false(PlaytestRegressions.record_baselines(path, later, times_file), "una base guardada no se pisa")
	var window := "%s (window): {\"nodes_max\": 45, \"frame_ms_p95\": 7}" % RegressionChecks.MEASURED
	assert_true(PlaytestRegressions.record_baselines(path, window, times_file), "otro runner suma su tiempo")
	saved = JSON.parse_string(FileAccess.get_file_as_string(path))
	assert_eq(saved.baselines, {"nodes_max": 40.0}, "el conteo sigue siendo uno")
	var entry := saved.duplicate()
	entry.file = path
	var given := PlaytestRegressions.baselines_for(entry, times_file)
	assert_eq(given.counts, {"nodes_max": 40.0}, "a la probe: los conteos")
	assert_eq(given.times, {"headless": {"frame_ms_p95": 2.5}, "window": {"frame_ms_p95": 7.0}}, "y los tiempos de esta máquina por runner")


func test_mutation_counts_kills_by_checks() -> void:
	assert_eq(MutationTesting.kill_reason(RegressionChecks.BROKEN + " «x»"), MutationTesting.KILLED_BY_INVARIANT, "invariante")
	assert_eq(MutationTesting.kill_reason(RegressionChecks.OVER + " nodes_max"), MutationTesting.KILLED_BY_BUDGET, "presupuesto")
	assert_eq(MutationTesting.kill_reason("run() returned: false"), MutationTesting.KILLED_BY_SCRIPT, "script")
	var mutants := [
		{"status": "killed", "regressions": ["a"], "killed_by": ["a"], "killed_how": {"a": "invariant"}},
		{"status": "killed", "regressions": ["a"], "killed_by": ["a"], "killed_how": {"a": "script"}},
		{"status": "survived", "regressions": ["a"]},
	]
	var result := MutationTesting.score(mutants)
	assert_eq(int(result.by_regression.a), 2, "atrapó 2")
	assert_eq(int(result.by_checks.a), 1, "1 por invariantes")
	var notice := MutationTesting.notice(result, {"a": "goal"}, func(text: String) -> String: return text)
	var by: String = notice.sections.back().text
	assert_true(by.contains("caught 2 (1 by invariants or budgets)"), by)
