extends "test_case.gd"
## Salida del validador de scripts y ubicaciones de errores (spec §6).

const DiagnosticTools := preload("res://addons/godot_agent/mcp/tools/diagnostic_tools.gd")
const ErrorCollector := preload("res://addons/godot_agent/core/error_collector.gd")


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
	assert_eq(results["res://bad.gd"].errors, ["línea 4: Parse Error: Identifier \"x\" not declared in the current scope."], "error con línea, sin el genérico ni ANSI")
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
