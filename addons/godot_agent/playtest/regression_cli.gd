extends SceneTree
## Repite las regresiones guardadas sin el editor (m16-09), para CI. Cada una abre su escena, espera
## lo mismo que el botón del panel y corre su game_script con el probe en modo standalone. Los errores
## del juego no lo frenan (sin debugger no hay pausa), como continue_on_error en el editor.
## Uso: godot --headless --path <proyecto> --script res://addons/godot_agent/playtest/regression_cli.gd [-- [--repeat=N] [--fail-on-flaky] <archivo.json o carpeta>...]
## Sin rutas, las de res://.godot_agent/playtests/regressions. Una regresión con `sabotage` corre otra
## vez con el sabotaje puesto y tiene que fallar. `--repeat=N` corre cada una N veces (m11-42): pasa si
## pasaron todas; si pasó algunas es inestable (FLAKY, con cuántas de N). Sin --repeat, una que la
## última repetición en el editor marcó inestable y falla se reintenta hasta 3 veces: inestable si
## pasa alguna, falla si no. Una inestable no hace fallar la corrida salvo con `--fail-on-flaky`. Sale con 0 si pasan todas, 1 si falla alguna y 2 si
## no hay ninguna (o una opción está mal).

const PlaytestRegressions := preload("res://addons/godot_agent/review/playtest_regressions.gd")
const PlaytestProbe := preload("res://addons/godot_agent/playtest/runtime/playtest_probe.gd")
const RealGamepads := preload("res://addons/godot_agent/playtest/real_gamepads.gd")
const GDScriptMutator := preload("res://addons/godot_agent/playtest/mutation/gdscript_mutator.gd")
const SaveGuard := preload("res://addons/godot_agent/playtest/mutation/save_guard.gd")
## Con --mutant (m11-41): 0 si todas pasan con el mutante (sobrevivió), 1 si una lo detecta, 3 si el
## mutante no compila o ya no se aplica; 4 si algo intentó guardar un recurso (SaveGuard).
const MUTANT_INVALID := 3
const MutationTesting := preload("res://addons/godot_agent/playtest/mutation/mutation_testing.gd")

const SETTLE_S := 0.5
const SCRIPT_TIMEOUT_S := 30.0


## Guardar la base de los presupuestos en el primer run que pasa (m11-44). No bajo un mutante ni con
## --no-baselines (la medición de mutación corre sin tocar los JSON).
var record_baselines := true
## Bajo un mutante los presupuestos de tiempo no hacen fallar: entre procesos hay ruido.
var under_mutant := false


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	# Un gamepad real con el stick corrido juega por su cuenta (m16-11).
	var relaunched: int = await RealGamepads.relaunch_without(self, get_script().resource_path)
	if relaunched >= 0:
		quit(relaunched)
		return
	var options := parse_args(OS.get_cmdline_user_args())
	if not str(options.error).is_empty():
		print("regressions: " + options.error)
		quit(2)
		return
	var entries := _entries(options.paths)
	if entries.is_empty():
		print("regressions: none found")
		quit(2)
		return
	record_baselines = not options.no_baselines
	if not (options.mutant as Dictionary).is_empty():
		record_baselines = false
		under_mutant = true
		quit(await _run_mutant(options.mutant, entries, str(options.mutant_result)))
		return
	if int(options.mutate) > 0:
		quit(await _measure(entries, int(options.mutate), int(options.min_score)))
		return
	var results: Array = []
	for entry: Dictionary in entries:
		var runs: Array = []
		for i in int(options.repeat):
			runs.append(await run_one(entry))
		while PlaytestRegressions.retry_marked(entry, runs, int(options.repeat)):
			runs.append(await run_one(entry))
		var result := PlaytestRegressions.tally(entry, runs)
		# El sabotaje se prueba una vez, con una que pasó alguna corrida: si pasa también con él, no detecta nada.
		if int(result.passes) > 0 and entry.get("sabotage") is String:
			var sabotaged := await run_one(entry, entry.sabotage)
			if not PlaytestRegressions.detects(sabotaged.output):
				result.passed = false
				result.flaky = false
				result.output = "It does not detect the bug: it also passes with its sabotage.\n" + sabotaged.output
		var count := PlaytestRegressions.count_text(result)
		print("regressions: %s %s%s" % ["FLAKY" if result.flaky else ("PASS" if result.passed else "FAIL"), result.goal, " (%s)" % count if not count.is_empty() else ""])
		if not result.passed:
			print("  " + str(result.output).strip_edges().replace("\n", "\n  "))
		results.append(result)
	var summary := PlaytestRegressions.summary(results, bool(options.fail_on_flaky))
	var flaky := "" if summary.flaky == 0 else " · %d flaky%s" % [summary.flaky, " (--fail-on-flaky: they count as failures)" if options.fail_on_flaky else " (not counted as failures; --fail-on-flaky counts them)"]
	if summary.failed > 0:
		print("regressions: %d of %d fail%s" % [summary.failed, results.size(), flaky])
	elif summary.flaky > 0:
		print("regressions: none of %d fail%s" % [results.size(), flaky])
	else:
		print("regressions: all %d pass" % results.size())
	quit(0 if summary.ok else 1)


## {paths, repeat, fail_on_flaky, error}: las opciones van antes o entre las rutas.
static func parse_args(args: PackedStringArray) -> Dictionary:
	var options := {"paths": PackedStringArray(), "repeat": 1, "fail_on_flaky": false, "error": "", "mutant": {}, "mutant_result": "", "mutate": 0, "min_score": -1, "no_baselines": false}
	for arg: String in args:
		if arg.begins_with("--mutant="):
			var parsed: Variant = JSON.parse_string(Marshalls.base64_to_utf8(arg.trim_prefix("--mutant=")))
			if not parsed is Dictionary or not str(parsed.get("path", "")).begins_with("res://"):
				options.error = "--mutant needs the mutant as base64 JSON"
				return options
			options.mutant = parsed
		elif arg == "--mutate" or arg.begins_with("--mutate="):
			var count := arg.trim_prefix("--mutate").trim_prefix("=")
			if count.is_empty():
				count = str(MutationTesting.DEFAULT_COUNT)
			if not count.is_valid_int() or int(count) < 1:
				options.error = "--mutate needs a number of mutants, not «%s»" % count
				return options
			options.mutate = int(count)
		elif arg.begins_with("--min-score="):
			var value := arg.trim_prefix("--min-score=")
			if not value.is_valid_int() or int(value) < 0 or int(value) > 100:
				options.error = "--min-score needs a percentage from 0 to 100, not «%s»" % value
				return options
			options.min_score = int(value)
		elif arg.begins_with("--mutant-result="):
			options.mutant_result = arg.trim_prefix("--mutant-result=")
		elif arg.begins_with("--repeat="):
			var value := arg.trim_prefix("--repeat=")
			if not value.is_valid_int() or int(value) < 1 or int(value) > PlaytestRegressions.MAX_REPEAT:
				options.error = "--repeat needs a whole number from 1 to %d, not «%s»" % [PlaytestRegressions.MAX_REPEAT, value]
				return options
			options.repeat = int(value)
		elif arg == "--fail-on-flaky":
			options.fail_on_flaky = true
		elif arg == "--no-baselines":
			options.no_baselines = true
		elif arg.begins_with("--"):
			options.error = "unknown option %s (use --repeat=N, --fail-on-flaky, --no-baselines, --mutate[=N] and --min-score=P)" % arg
			return options
		else:
			options.paths.append(arg)
	return options


## --mutate=N (m11-41): mide las regresiones con N mutantes, cada uno en otro proceso. Imprime el
## puntaje y los que sobrevivieron; sale con 0 salvo que el puntaje quede bajo --min-score (1) o no
## se pueda medir (2).
func _measure(entries: Array[Dictionary], count: int, min_score: int) -> int:
	var testing := MutationTesting.new()
	testing.on_progress = func(done: int, total: int, mutant: Dictionary) -> void:
		print("regressions: mutant %d/%d %s:%d %s" % [done, total, mutant.path, int(mutant.line), mutant.status])
	var result := await testing.run(entries, count)
	if not result.ok:
		print("regressions: " + str(result.error))
		return 2
	print("regressions: mutation score %d/%d (%d %%)%s" % [result.detected, result.measured, result.percent,
		" · %d invalid" % result.invalid if int(result.invalid) > 0 else ""])
	for mutant: Dictionary in result.mutants:
		if mutant.status == MutationTesting.STATUS_SURVIVED:
			print("  survived %s:%d %s" % [mutant.path, int(mutant.line), mutant.change])
		elif mutant.status == MutationTesting.STATUS_ERROR:
			print("  error %s:%d %s" % [mutant.path, int(mutant.line), mutant.get("output", "")])
	if min_score >= 0 and int(result.percent) < min_score:
		print("regressions: the mutation score is under --min-score=%d" % min_score)
		return 1
	return 0


## Un mutante (m11-41): el script se cambia solo en memoria (source_code + reload del recurso del
## caché, que es el que usa la escena) y ningún recurso se puede guardar mientras tanto. Corre todas
## las regresiones. Deja {status, killed_by (las que lo detectaron), output} en
## `result_path` (un archivo del usuario, no del proyecto) y devuelve el código de salida.
func _run_mutant(mutant: Dictionary, entries: Array[Dictionary], result_path: String) -> int:
	var guard := SaveGuard.new()
	ResourceSaver.add_resource_format_saver(guard, true)
	var report := {"status": "invalid", "killed_by": "", "output": ""}
	var code := MUTANT_INVALID
	var script := load(str(mutant.path)) as GDScript
	var mutated := GDScriptMutator.apply(script.source_code, mutant) if script else ""
	if mutated.is_empty():
		report.output = "The mutant does not apply to %s any more." % mutant.path
	else:
		script.source_code = mutated
		if script.reload(true) != OK:
			report.output = "The mutant does not compile."
		else:
			report.status = "survived"
			report.killed_by = []
			report.killed_how = {}
			code = 0
			# Todas, no solo hasta la primera: el puntaje por regresión dice cuáles lo detectan de verdad.
			for entry: Dictionary in entries:
				var result := await run_one(entry)
				if not result.passed:
					report.status = "killed"
					var file := str(entry.get("file", entry.get("goal", "")))
					(report.killed_by as Array).append(file)
					report.killed_how[file] = MutationTesting.kill_reason(str(result.output))
					if str(report.output).is_empty():
						report.output = str(result.output).left(500)
					code = 1
	if not guard.attempts.is_empty():
		report.status = "save_attempted"
		report.output = "Tried to save: %s" % ", ".join(guard.attempts)
		code = SaveGuard.EXIT_CODE
	ResourceSaver.remove_resource_format_saver(guard)
	print("regressions: mutant %s:%d %s" % [mutant.path, int(mutant.line), report.status])
	if not result_path.is_empty():
		var file := FileAccess.open(result_path, FileAccess.WRITE)
		if file:
			file.store_string(JSON.stringify(report))
			file.close()
	return code


## {goal, passed, output}, como RunTools.run_regression. `setup`: código que corre antes, en el mismo juego.
func run_one(entry: Dictionary, setup: String = "") -> Dictionary:
	var result := {"goal": str(entry.get("goal", "")), "passed": false, "output": ""}
	var blocked := PlaytestRegressions.blocked_api(str(entry.get("code", "")) + "\n" + setup)
	if not blocked.is_empty():
		result.output = "It can't use %s: it may not touch files or start processes." % blocked
		return result
	var scene := str(entry.get("scene", ""))
	if not ResourceLoader.exists(scene) or change_scene_to_file(scene) != OK:
		result.output = "The scene %s could not be opened." % scene
		return result
	paused = false
	await process_frame
	await process_frame
	await create_timer(SETTLE_S).timeout
	var probe: Node = PlaytestProbe.new()
	probe.standalone = true
	root.add_child(probe)
	if not setup.is_empty():
		await probe.call(&"_run_script", {"code": setup, "timeout": SCRIPT_TIMEOUT_S})
	var played: Dictionary = await probe.call(&"_run_script", {"code": str(entry.get("code", "")), "timeout": SCRIPT_TIMEOUT_S,
		"baselines": entry.get("baselines", {}), "time_budgets_warn": under_mutant})
	result.output = str(played.get("error", played.get("text", "")))
	result.passed = not played.has("error") and PlaytestRegressions.passed(result.output)
	result.violations = played.get("violations", [])
	if result.passed and record_baselines and setup.is_empty():
		PlaytestRegressions.record_baselines(str(entry.get("file", "")), result.output)
	probe.queue_free()
	unload_current_scene()
	await process_frame
	return result


## Archivos .json sueltos o carpetas con regresiones; sin rutas, la carpeta de siempre.
static func _entries(paths: PackedStringArray) -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	if paths.is_empty():
		paths = [PlaytestRegressions.DIR]
	for path: String in paths:
		if path.get_extension() == "json":
			var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
			if parsed is Dictionary and parsed.get("scene") is String and parsed.get("code") is String:
				parsed["file"] = path
				entries.append(parsed)
		else:
			entries.append_array(PlaytestRegressions.new(path).list())
	return entries
