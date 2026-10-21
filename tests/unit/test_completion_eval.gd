extends "test_case.gd"
## Set de evaluación del completado (M8b, spec §16.9): los casos son válidos y el n-gram mejora la
## línea base de reglas + recuperación sin sumar sugerencias equivocadas. Los números completos se
## ven con tests/run_completion_eval.gd.

const Runner := preload("res://tests/completion_eval_runner.gd")

## Una sugerencia equivocada molesta más que ninguna: la precisión manda.
const MIN_PRECISION := 0.85


func test_eval_set() -> void:
	var runner := Runner.new()
	runner.load_cases()
	assert_eq(runner.errors, PackedStringArray(), "casos bien formados")
	assert_true(runner.cases.size() >= 30 and runner.cases.size() <= 50, "entre 30 y 50 casos (%d)" % runner.cases.size())
	var report := runner.run(Runner.parse_combos("rule+retrieval rule+retrieval+ngram ngram"))
	var base: Dictionary = report.combos[0].metrics
	var full: Dictionary = report.combos[1].metrics
	var ngram: Dictionary = report.combos[2].metrics
	print("completion_eval: base %d/%d correctas (%d FP), con n-gram %d/%d (%d FP), n-gram solo %d/%d (%d FP)" % [
		base.correct, base.shown, base.false_positives, full.correct, full.shown, full.false_positives,
		ngram.correct, ngram.shown, ngram.false_positives])
	assert_true(int(full.correct) > int(base.correct), "el n-gram suma sugerencias correctas")
	assert_true(int(full.false_positives) <= int(base.false_positives), "sin sumar equivocadas")
	assert_true(float(full.precision) >= MIN_PRECISION, "precisión %.2f" % full.precision)
	assert_true(float(ngram.precision) >= MIN_PRECISION, "precisión del n-gram solo %.2f" % ngram.precision)
	assert_true(float(full.p95_ms) < 10.0, "p95 %.2f ms" % full.p95_ms)
