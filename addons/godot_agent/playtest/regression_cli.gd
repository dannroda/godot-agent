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

const SETTLE_S := 0.5
const SCRIPT_TIMEOUT_S := 30.0


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
	var options := {"paths": PackedStringArray(), "repeat": 1, "fail_on_flaky": false, "error": ""}
	for arg: String in args:
		if arg.begins_with("--repeat="):
			var value := arg.trim_prefix("--repeat=")
			if not value.is_valid_int() or int(value) < 1 or int(value) > PlaytestRegressions.MAX_REPEAT:
				options.error = "--repeat needs a whole number from 1 to %d, not «%s»" % [PlaytestRegressions.MAX_REPEAT, value]
				return options
			options.repeat = int(value)
		elif arg == "--fail-on-flaky":
			options.fail_on_flaky = true
		elif arg.begins_with("--"):
			options.error = "unknown option %s (use --repeat=N and --fail-on-flaky)" % arg
			return options
		else:
			options.paths.append(arg)
	return options


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
	var played: Dictionary = await probe.call(&"_run_script", {"code": str(entry.get("code", "")), "timeout": SCRIPT_TIMEOUT_S})
	result.output = str(played.get("error", played.get("text", "")))
	result.passed = not played.has("error") and PlaytestRegressions.passed(result.output)
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
