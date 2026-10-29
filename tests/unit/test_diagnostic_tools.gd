extends "test_case.gd"
## Salida del validador de scripts y ubicaciones de errores (spec §6).

const DiagnosticTools := preload("res://addons/godot_agent/mcp/tools/diagnostic_tools.gd")
const ErrorCollector := preload("res://addons/godot_agent/editor/error_collector.gd")
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
