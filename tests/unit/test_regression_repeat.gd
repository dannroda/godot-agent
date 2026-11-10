extends "test_case.gd"
## m11-42: repetir las regresiones N veces, pass^k, marcar las inestables y que una inestable no
## rompa el CI salvo que se pida.

const PlaytestRegressions := preload("res://addons/godot_agent/review/playtest_regressions.gd")
const RegressionsWorkflow := preload("res://addons/godot_agent/review/regressions_workflow.gd")
const RegressionCli := preload("res://addons/godot_agent/playtest/regression_cli.gd")
const I18n := preload("res://addons/godot_agent/core/i18n.gd")

const DIR := "user://test_regression_repeat"


func _run(passed: bool, output: String = "") -> Dictionary:
	return {"goal": "g", "passed": passed, "output": output if not output.is_empty() else ("run() returned: true" if passed else "run() returned: false")}


func test_tally_is_pass_to_the_k() -> void:
	var entry := {"goal": "Salta", "file": "res://x.json"}
	var all := PlaytestRegressions.tally(entry, [_run(true), _run(true), _run(true)])
	assert_true(all.passed and not all.flaky and all.passes == 3 and all.runs == 3, "pasa si pasaron todas")
	var some := PlaytestRegressions.tally(entry, [_run(true), _run(false, "falló la 2"), _run(true)])
	assert_false(some.passed, "una que falla alguna no pasa")
	assert_true(some.flaky and some.passes == 2, "y es inestable, con cuántas pasaron")
	assert_eq(some.output, "falló la 2", "con el texto de la que falló")
	var none := PlaytestRegressions.tally(entry, [_run(false), _run(false)])
	assert_true(not none.passed and not none.flaky, "falla todas: falla, no inestable")
	var once := PlaytestRegressions.tally(entry, [_run(false)])
	assert_false(once.flaky, "una corrida que falla, sin marca, falla")


func test_marked_flaky_single_failure() -> void:
	var entry := {"goal": "Salta", "runs": {"passed": 2, "total": 3, "at": 0}}
	assert_true(PlaytestRegressions.is_flaky(entry), "marcada")
	var once := PlaytestRegressions.tally(entry, [_run(false)])
	assert_true(once.flaky and once.output.begins_with("Marked flaky: it passed 2 of 3"), "falla una vez pero la marca dice que es inestable")
	assert_false(PlaytestRegressions.is_flaky({"runs": {"passed": 3, "total": 3}}), "pasó todas: estable")
	assert_false(PlaytestRegressions.is_flaky({"runs": {"passed": 0, "total": 3}}), "falló todas: no es inestable")


func test_summary_counts_flaky_apart() -> void:
	var flaky := PlaytestRegressions.tally({"goal": "Salta"}, [_run(true), _run(false)])
	var failing := PlaytestRegressions.tally({"goal": "Dispara"}, [_run(false), _run(false)])
	var passing := PlaytestRegressions.tally({"goal": "Corre"}, [_run(true), _run(true)])
	var only_flaky := PlaytestRegressions.summary([passing, flaky])
	assert_true(only_flaky.ok and only_flaky.failed == 0 and only_flaky.flaky == 1, "una inestable no hace fallar")
	assert_true(only_flaky.details.contains("• Salta (flaky: passed 1 of 2)"), "dice cuántas pasaron (%s)" % only_flaky.details)
	assert_false(PlaytestRegressions.summary([passing, flaky], true).ok, "con fail_on_flaky, sí")
	var mixed := PlaytestRegressions.summary([failing, flaky])
	assert_true(not mixed.ok and mixed.failed == 1 and mixed.flaky == 1, "la que falla todas cuenta como falla")
	assert_true(mixed.details.contains("• Dispara (passed 0 of 2)"), "con el conteo")
	# Sin repetir, como antes (m16-06).
	var old := PlaytestRegressions.summary([{"goal": "A", "passed": false, "output": "x"}])
	assert_true(not old.ok and old.failed == 1 and old.details == "• A\n  x", "una corrida, sin conteo")
	I18n.set_locale("es")
	var translated := PlaytestRegressions.summary([flaky], false, Callable(I18n, &"t"))
	assert_true(translated.details.contains("(inestable: pasó 1 de 2)"), "traducido para el panel (%s)" % translated.details)
	I18n.set_locale("en")


func test_record_runs_marks_and_clears() -> void:
	var store := PlaytestRegressions.new(DIR)
	var path := store.save("Salta", "res://x.tscn", "func run(game):\n\treturn true")
	var entry: Dictionary = store.list()[0]
	PlaytestRegressions.record_runs(PlaytestRegressions.tally(entry, [_run(true)]))
	assert_false(store.list()[0].has("runs"), "con una corrida no marca nada")
	PlaytestRegressions.record_runs(PlaytestRegressions.tally(entry, [_run(true), _run(false), _run(true)]))
	var marked: Dictionary = store.list()[0]
	assert_eq([int(marked.runs.passed), int(marked.runs.total)], [2, 3], "guarda cuántas pasaron")
	assert_eq(PlaytestRegressions.flaky_count(store.list()), 1, "cuenta como inestable")
	assert_eq(marked.code, "func run(game):\n\treturn true", "el resto queda igual")
	PlaytestRegressions.record_runs(PlaytestRegressions.tally(marked, [_run(true), _run(true), _run(true)]))
	assert_eq(PlaytestRegressions.flaky_count(store.list()), 0, "pasar todas la desmarca")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(DIR))


func test_cli_options() -> void:
	var parsed := RegressionCli.parse_args(PackedStringArray(["--repeat=5", "res://a.json", "--fail-on-flaky", "res://b"]))
	assert_eq([parsed.repeat, parsed.fail_on_flaky, parsed.paths, parsed.error], [5, true, PackedStringArray(["res://a.json", "res://b"]), ""], "opciones entre las rutas")
	assert_eq(RegressionCli.parse_args(PackedStringArray()).repeat, 1, "por defecto, una vez")
	assert_true(str(RegressionCli.parse_args(PackedStringArray(["--repeat=0"])).error).contains("1 to 20"), "fuera de rango")
	assert_true(str(RegressionCli.parse_args(PackedStringArray(["--repeat=x"])).error).contains("«x»"), "no es un número")
	assert_true(str(RegressionCli.parse_args(PackedStringArray(["--retry"])).error).contains("unknown option --retry"), "opción desconocida")


func test_workflow_passes_the_options() -> void:
	assert_eq(RegressionsWorkflow.cli_options(1, false), PackedStringArray(), "por defecto, nada")
	var text := RegressionsWorkflow.workflow_text("4.7.2-stable", false, "", false, 3, true)
	assert_true(text.contains("--script res://addons/godot_agent/playtest/regression_cli.gd -- --repeat=3 --fail-on-flaky 2>&1 | tee"), "headless con las opciones")
	var render := RegressionsWorkflow.workflow_text("4.7.2-stable", true, "", false, 4)
	assert_true(render.contains("regression_cli.gd -- --repeat=4 2>&1"), "bajo Xvfb también")
	assert_false(RegressionsWorkflow.workflow_text("4.7.2-stable", false).contains("--repeat"), "sin repetir, como antes")


## El panel de hallazgos: «Correr regresiones (N · K inestables)», cuáles en el tooltip, y el ×N
## de corridas sale con el pedido.
func test_panel_counts_flaky_and_sends_repeat() -> void:
	var ReviewPanel: GDScript = load("res://addons/godot_agent/ui/dock/review_panel.gd")
	var ReviewStore: GDScript = load("res://addons/godot_agent/review/review_store.gd")
	var store := PlaytestRegressions.new()
	var saved: Array[String] = []
	if store.list().is_empty():  # no se tocan las que haya de quien corre los tests
		saved.append(store.save("m11-42 salta", "res://x.tscn", "func run(game):\n\treturn true"))
		saved.append(store.save("m11-42 dispara", "res://x.tscn", "func run(game):\n\treturn true"))
		var jump: Dictionary = store.list().filter(func(entry: Dictionary) -> bool: return entry.goal == "m11-42 salta")[0]
		PlaytestRegressions.record_runs(PlaytestRegressions.tally(jump, [_run(true), _run(false), _run(true)]))
	else:
		return
	var tree := Engine.get_main_loop() as SceneTree
	var panel: Control = ReviewPanel.new()
	panel.call(&"setup", ReviewStore.new(), Color.ORANGE)
	tree.root.add_child(panel)
	await tree.process_frame
	panel.call(&"refresh")
	var button: Button = panel.get(&"_regressions_button")
	assert_eq(button.text, "Run regressions (2 · 1 flaky)", "cuenta las inestables")
	assert_true(button.tooltip_text.contains("«m11-42 salta» (passed 2 of 3)") and not button.tooltip_text.contains("dispara"), "dice cuáles (%s)" % button.tooltip_text)
	var asked: Array = []
	panel.connect(&"regressions_requested", func(repeat: int) -> void: asked.append(repeat))
	(panel.get(&"_repeat") as SpinBox).value = 3
	button.pressed.emit()
	assert_eq(asked, [3], "sale con las corridas pedidas")
	panel.queue_free()
	for path: String in saved:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
