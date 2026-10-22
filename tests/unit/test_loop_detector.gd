extends "test_case.gd"
## Detector de loops del One-shot (D38): checks que fallan igual, tool calls que fallan con los
## mismos argumentos y cambios repetidos.

const LoopDetector := preload("res://addons/godot_agent/oneshot/loop_detector.gd")


func _failing(label: String, detail: String) -> Array:
	return [{"label": label, "status": "fail", "detail": detail}]


func test_same_failing_check() -> void:
	var loops := LoopDetector.new()
	assert_eq(loops.observe_checks(_failing("salta", "no se mueve")), {}, "1")
	assert_eq(loops.observe_checks(_failing("salta", "no se mueve")), {}, "2")
	var finding := loops.observe_checks(_failing("salta", "no se mueve"))
	assert_false(finding.is_empty(), "3 iguales = loop")
	assert_false(finding.repeated, "primera vez")
	assert_true(str(finding.text).contains("salta"), "nombra el check")
	loops.observe_checks(_failing("salta", "no se mueve"))
	loops.observe_checks(_failing("salta", "no se mueve"))
	assert_true(loops.observe_checks(_failing("salta", "no se mueve")).repeated, "la misma huella otra vez")


func test_check_streak_breaks() -> void:
	var loops := LoopDetector.new()
	loops.observe_checks(_failing("salta", "no se mueve"))
	loops.observe_checks(_failing("salta", "no se mueve"))
	loops.observe_checks([{"label": "salta", "status": "pass"}])
	assert_eq(loops.observe_checks(_failing("salta", "no se mueve")), {}, "pasar corta la racha")
	loops.observe_checks(_failing("salta", "no se mueve"))
	assert_eq(loops.observe_checks(_failing("salta", "salta poco")), {}, "otro detalle = avance")
	loops.observe_checks([])
	loops.observe_checks(_failing("salta", "salta poco"))
	assert_false(loops.observe_checks(_failing("salta", "salta poco")).is_empty(), "un reporte sin checks no corta")


func test_same_failing_call() -> void:
	var loops := LoopDetector.new()
	var input := {"path": "res://player.gd", "old": "a", "new": "b"}
	assert_eq(loops.observe_call("Edit", "edit", "", input, true), {}, "1")
	assert_eq(loops.observe_call("Read", "read", "", {"path": "res://player.gd"}, false), {}, "leer en el medio")
	assert_eq(loops.observe_call("Edit", "edit", "", {"path": "res://player.gd", "new": "b", "old": "a"}, true), {}, "2 (otro orden de claves)")
	assert_false(loops.observe_call("Edit", "edit", "", input, true).is_empty(), "3 fallas iguales")
	assert_eq(loops.observe_call("Edit", "edit", "", input, true), {}, "la cuenta vuelve a 0")


func test_verification_after_change_is_not_a_loop() -> void:
	var loops := LoopDetector.new()
	var run := {"scene": "res://main.tscn"}
	for i in 4:
		assert_eq(loops.observe_call("godot.run_scene", "other", "run_scene", run, true), {}, "falla %d, se edita" % (i + 1))
		loops.observe_call("Edit", "edit", "", {"i": i}, false)
	assert_eq(loops.observe_call("godot.run_scene", "other", "run_scene", run, true), {}, "cada cambio reinicia la cuenta")
	assert_eq(loops.observe_call("godot.run_scene", "other", "run_scene", run, true), {}, "2 sin cambios")
	assert_false(loops.observe_call("godot.run_scene", "other", "run_scene", run, true).is_empty(), "3 sin cambios = loop")


func test_same_change_repeated() -> void:
	var loops := LoopDetector.new()
	var input := {"node": "Player", "properties": {"speed": 200}}
	for i in 3:
		assert_eq(loops.observe_call("godot.set_properties", "edit", "set_properties", input, false), {}, "cambio %d" % (i + 1))
		loops.observe_call("godot.run_scene", "other", "run_scene", {}, false)
	var finding := loops.observe_call("godot.set_properties", "edit", "set_properties", input, false)
	assert_false(finding.is_empty(), "4 cambios iguales")
	assert_true(str(finding.text).contains("4 times"), finding.text)


func test_reads_and_verifications_repeat_freely() -> void:
	var loops := LoopDetector.new()
	for i in 10:
		assert_eq(loops.observe_call("Read player.gd", "read", "", {"path": "a"}, false), {}, "lectura")
		assert_eq(loops.observe_call("godot.capture_game_frame", "other", "capture_game_frame", {}, false), {}, "captura")
		assert_eq(loops.observe_call("godot.save_scene", "edit", "save_scene", {}, false), {}, "guardar")


func test_window() -> void:
	var loops := LoopDetector.new()
	for i in 3:
		loops.observe_call("Edit", "edit", "", {"x": 1}, false)
	for i in LoopDetector.WINDOW:
		loops.observe_call("Edit", "edit", "", {"x": 100 + i}, false)
	assert_eq(loops.observe_call("Edit", "edit", "", {"x": 1}, false), {}, "las viejas salieron de la ventana")


func test_repeats_setting() -> void:
	var loops := LoopDetector.new()
	loops.repeats = 2
	loops.observe_checks(_failing("a", ""))
	assert_false(loops.observe_checks(_failing("a", "")).is_empty(), "umbral 2")
	loops.reset()
	assert_eq(loops.observe_checks(_failing("a", "")), {}, "reset")
