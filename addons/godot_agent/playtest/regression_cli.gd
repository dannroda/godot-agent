extends SceneTree
## Repite las regresiones guardadas sin el editor (m16-09), para CI. Cada una abre su escena, espera
## lo mismo que el botón del panel y corre su game_script con el probe en modo standalone. Los errores
## del juego no lo frenan (sin debugger no hay pausa), como continue_on_error en el editor.
## Uso: godot --headless --path <proyecto> --script res://addons/godot_agent/playtest/regression_cli.gd [-- <archivo.json o carpeta>...]
## Sin rutas, las de res://.godot_agent/playtests/regressions. Una regresión con `sabotage` corre otra
## vez con el sabotaje puesto y tiene que fallar. Sale con 0 si pasan todas, 1 si falla alguna y 2 si no
## hay ninguna.

const PlaytestRegressions := preload("res://addons/godot_agent/review/playtest_regressions.gd")
const PlaytestProbe := preload("res://addons/godot_agent/playtest/runtime/playtest_probe.gd")

const SETTLE_S := 0.5
const SCRIPT_TIMEOUT_S := 30.0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var entries := _entries(OS.get_cmdline_user_args())
	if entries.is_empty():
		print("regressions: none found")
		quit(2)
		return
	var results: Array = []
	for entry: Dictionary in entries:
		var result := await run_one(entry)
		if result.passed and entry.get("sabotage") is String:
			var sabotaged := await run_one(entry, entry.sabotage)
			if not PlaytestRegressions.detects(sabotaged.output):
				result.passed = false
				result.output = "It does not detect the bug: it also passes with its sabotage.\n" + sabotaged.output
		print("regressions: %s %s" % ["PASS" if result.passed else "FAIL", result.goal])
		if not result.passed:
			print("  " + str(result.output).strip_edges().replace("\n", "\n  "))
		results.append(result)
	var summary := PlaytestRegressions.summary(results)
	print("regressions: %d of %d fail" % [summary.failed, results.size()] if not summary.ok else "regressions: all %d pass" % results.size())
	quit(0 if summary.ok else 1)


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
