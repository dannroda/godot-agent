extends "test_case.gd"
## Salida del validador de scripts y ubicaciones de errores (spec §6).

const DiagnosticTools := preload("res://addons/godot_agent/mcp/tools/diagnostic_tools.gd")
const ErrorCollector := preload("res://addons/godot_agent/editor/error_collector.gd")
const EditorLogger := preload("res://addons/godot_agent/core/editor_logger.gd")
const SessionController := preload("res://addons/godot_agent/session/session_controller.gd")
const SessionModel := preload("res://addons/godot_agent/session/session_model.gd")
const AgentLog := preload("res://addons/godot_agent/core/agent_log.gd")


func test_parse_checker_output() -> void:
	var lines: PackedStringArray = [
		"@@BEGIN res://bad.gd",
		"\u001b[1;31mSCRIPT ERROR:\u001b[0m Parse Error: Identifier \"x\" not declared in the current scope.",
		"          at: GDScript::reload (res://bad.gd:4)",
		"          GDScript backtrace (most recent call first):",
		"ERROR: Failed to load script \"res://bad.gd\" with error \"Parse error\".",
		"   at: load (modules/gdscript/gdscript_resource_format.cpp:50)",
		"@@END ok res://bad.gd",
		"@@BEGIN res://uses_bad.gd",
		"SCRIPT ERROR: Parse Error: Could not preload resource script \"res://dep.gd\".",
		"   at: GDScript::reload (res://uses_bad.gd:2)",
		"@@END ok res://uses_bad.gd",
		"@@BEGIN res://good.gd",
		"@@END ok res://good.gd",
	]
	var results := DiagnosticTools.parse_checker_output(lines)
	assert_eq(results["res://bad.gd"].errors, ["line 4: Parse Error: Identifier \"x\" not declared in the current scope."], "error con línea, sin el genérico ni ANSI")
	assert_eq(results["res://uses_bad.gd"].errors.size(), 1, "error de dependencia")
	assert_true(results["res://good.gd"].ok and results["res://good.gd"].errors.is_empty(), "script sano")


func test_parse_location() -> void:
	assert_eq(ErrorCollector._parse_location("   at: GDScript::reload (res://a/b.gd:12)"), ["res://a/b.gd", 12], "archivo y línea")
	assert_eq(ErrorCollector._parse_location("at: algo"), ["", 0], "sin paréntesis")


func test_collector_marks() -> void:
	var collector := ErrorCollector.new()
	collector.add("error", "uno", "res://a.gd", 1)
	var mark := collector.mark()
	collector.add("warning", "dos")
	assert_eq(mark, 1, "marca")
	var entry: Dictionary = {"seq": 2, "kind": "warning", "message": "dos", "file": "", "line": 0, "source": "editor"}
	assert_eq(ErrorCollector.format_entry(entry), "#2 [editor/warning] — dos", "formato")


func test_scripts_modified_since() -> void:
	var root := ProjectSettings.globalize_path("user://unit_tests/verify_turn")
	for path: String in ["a.gd", "sub/b.gd", "sub/c.txt", ".hidden/d.gd", "ignored/e.gd", "ignored/.gdignore"]:
		DirAccess.make_dir_recursive_absolute(root.path_join(path).get_base_dir())
		var file := FileAccess.open(root.path_join(path), FileAccess.WRITE)
		file.store_string("extends Node\n")
		file.close()
	var found := Array(DiagnosticTools.scripts_modified_since(root, 0)).map(func(path: String) -> String: return path.trim_prefix(root + "/"))
	found.sort()
	assert_eq(found, ["a.gd", "sub/b.gd"], "solo .gd, sin carpetas ocultas ni con .gdignore")
	assert_eq(DiagnosticTools.scripts_modified_since(root, int(Time.get_unix_time_from_system()) + 60).size(), 0, "nada modificado después")
	var report := {"results": {"res://a.gd": {"ok": true, "errors": []}, "res://b.gd": {"ok": false, "errors": ["line 3: Expected end of statement"]}}}
	assert_eq(Array(DiagnosticTools.failure_lines(PackedStringArray(["res://a.gd", "res://b.gd"]), report)), ["✗ res://b.gd", "  line 3: Expected end of statement"], "solo los que fallan, con sus errores")


func test_turn_check_sends_fix_or_notice() -> void:
	var controller := SessionController.new()
	controller.setup(SessionModel.new(), AgentLog.new(), "/tmp/project")
	var model := controller.model
	model.session_id = "s"
	model.set_state(SessionModel.SessionState.READY)
	model.set_harness_mode(SessionModel.HarnessMode.BUILD)
	var calls := []
	controller.turn_verifier = func(since: int) -> String:
		calls.append(since)
		return "✗ res://a.gd\n  line 1: error"
	var texts := func() -> Array: return model.entries().map(func(e: Variant) -> String: return e.text)
	await controller.call(&"_verify_turn", 123)
	assert_eq(calls, [123], "verifica desde el inicio del turno")
	assert_true(texts.call().any(func(text: String) -> bool: return text.begins_with("[Automatic check after your turn]")), "le devuelve los errores al agente: %s" % [texts.call()])
	model.set_state(SessionModel.SessionState.READY)
	controller.set(&"_fix_turns", SessionController.MAX_FIX_TURNS)
	await controller.call(&"_verify_turn", 456)
	assert_true(str(texts.call()[-1]).contains("✗ res://a.gd"), "con el tope, queda como aviso")
	model.set_harness_mode(SessionModel.HarnessMode.ASK)
	await controller.call(&"_verify_turn", 789)
	assert_eq(calls.size(), 2, "en Preguntar no verifica")


## El ruido de 4.7 (@implicit_new) no sale en get_errors: el One-shot lo citó como error del harness (m17-07).
func test_get_errors_hides_engine_noise() -> void:
	var collector := OfflineCollector.new()
	collector.add("error", "Cannot get path of node as it is not in a scene tree. @implicit_new: absolute paths from outside the active scene tree are relative", "", 0, "game")
	collector.add("error", "de verdad", "res://a.gd", 3, "game")
	var tools := DiagnosticTools.new()
	tools.setup(collector, "")
	var text: String = tools._get_errors({})
	assert_false(text.contains("@implicit_new"), "sin el ruido del motor")
	assert_true(text.contains("de verdad"), "el resto sigue")
	assert_true(text.contains("1 new"), "el conteo no cuenta el ruido")


## m11-72: get_output lee lo impreso con marcas, las últimas líneas y un filtro.
func test_get_output() -> void:
	var collector := OfflineCollector.new()
	collector.add_output("Bake PVS: 10%\nBake PVS: 50%\n")
	collector.add_output("otra cosa")
	collector.add_output("falló el bake", true)
	var tools := DiagnosticTools.new()
	tools.setup(collector, "")
	var text: String = tools._get_output({})
	assert_true(text.begins_with("mark: 4 · 4 new lines since 0"), text)
	assert_true(text.contains("Bake PVS: 50%\notra cosa\n[stderr] falló el bake"), "en orden, una por línea, stderr marcado")
	text = tools._get_output({"since": 2})
	assert_false(text.contains("50%"), "desde la marca")
	assert_true(text.contains("2 new lines since 2"), text)
	text = tools._get_output({"contains": "bake pvs", "lines": 1})
	assert_true(text.contains("2 new lines since 0 containing \"bake pvs\" (showing the last 1)"), text)
	assert_true(text.contains("50%") and not text.contains("10%"), "la última")
	assert_true(tools._get_output({"since": 4}).ends_with("Nothing printed."), "nada nuevo")
	for i: int in ErrorCollector.MAX_OUTPUT_LINES + 5:
		collector.add_output("línea %d" % i)
	assert_eq(collector.output_since(0).size(), ErrorCollector.MAX_OUTPUT_LINES, "tope de líneas")


## m11-84: editor_wait en lugar de `until stat …; do sleep 5; done` en la shell.
func test_editor_wait() -> void:
	var collector := OfflineCollector.new()
	var tools := DiagnosticTools.new()
	tools.setup(collector, "")
	var tree := Engine.get_main_loop() as SceneTree
	var path := "res://tests/tmp/editor_wait_probe.txt"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://tests/tmp"))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	assert_true((await tools._editor_wait({})).isError, "sin condición, error")
	assert_true((await tools._editor_wait({"file": "/tmp/x"})).isError, "solo res:// o user://")
	# El archivo aparece a mitad de la espera.
	tree.create_timer(0.4).timeout.connect(func() -> void: FileAccess.open(path, FileAccess.WRITE).store_string("baked"))
	var started := Time.get_ticks_msec()
	var written: Dictionary = await tools._editor_wait({"file": path, "seconds": 5})
	assert_true(str(written.content[0].text).begins_with(path + " was written"), str(written.content[0].text))
	assert_true(Time.get_ticks_msec() - started < 3000, "vuelve apenas se cumple")
	# Ya escrito antes de la llamada: con `after` cuenta; sin `after`, espera un cambio nuevo.
	var before := int(FileAccess.get_modified_time(path))
	var done: Dictionary = await tools._editor_wait({"file": path, "after": before, "seconds": 1})
	assert_true(str(done.content[0].text).contains("was written"), "con after: ya estaba")
	var still: Dictionary = await tools._editor_wait({"file": path, "seconds": 0.5})
	assert_true(str(still.content[0].text).begins_with("Still waiting after") and str(still.content[0].text).contains("was not written"), str(still.content[0].text))
	# Una línea del Output, desde la marca de ahora (lo impreso antes no cuenta).
	collector.add_output("Bake PVS: done")
	tree.create_timer(0.3).timeout.connect(func() -> void: collector.add_output("PVS bake: DONE in 3 s"))
	var printed: Dictionary = await tools._editor_wait({"output": "done in", "seconds": 5})
	assert_true(str(printed.content[0].text).contains("PVS bake: DONE in 3 s"), str(printed.content[0].text))
	var old: Dictionary = await tools._editor_wait({"output": "bake pvs", "since": 0, "seconds": 1})
	assert_true(str(old.content[0].text).contains("Bake PVS: done"), "con since, lo de antes también")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


## El logger guarda lo impreso para el colector (en el hilo que sea).
func test_logger_keeps_messages() -> void:
	var logger := EditorLogger.new()
	logger._log_message("hola\n", false)
	logger._log_message("error\n", true)
	assert_eq(logger.drain_messages(), [["hola\n", false], ["error\n", true]], "en orden")
	assert_eq(logger.drain_messages(), [], "y se vacía")


## Sin editor (tests por --script) no hay debugger que leer.
class OfflineCollector extends ErrorCollector:
	func collect() -> void:
		pass
