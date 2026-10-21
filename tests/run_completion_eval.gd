extends SceneTree
## Corre el set de evaluación del completado (tests/completion_eval) y muestra la tabla por
## combinación de fuentes.
##   godot --headless --path . --script tests/run_completion_eval.gd
##   ... -- rule+retrieval ngram          (combinaciones propias, separadas por espacio)
##   ... -- --cases                       (además, el detalle por caso de cada combinación)

const Runner := preload("completion_eval_runner.gd")


func _initialize() -> void:
	var runner := Runner.new()
	runner.load_cases()
	for error: String in runner.errors:
		printerr("caso inválido: " + error)
	var combos: Array[PackedStringArray] = []
	var detail := false
	for arg: String in OS.get_cmdline_user_args():
		if arg == "--cases":
			detail = true
		else:
			combos.append(arg.split("+"))
	var report := runner.run(combos if not combos.is_empty() else Runner.parse_combos(Runner.DEFAULT_COMBOS))
	print("completion_eval: %d casos (%s)" % [runner.cases.size(), Engine.get_version_info().string])
	print(Runner.format(report))
	if detail:
		for entry: Dictionary in report.combos:
			print("\n== %s" % "+".join(entry.sources))
			print(Runner.format_cases(entry))
	quit(1 if not runner.errors.is_empty() else 0)
