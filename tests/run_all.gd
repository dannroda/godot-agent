extends SceneTree
## Runner mínimo de tests unitarios (spec §13).
## Uso: godot --headless --path <repo> --script tests/run_all.gd [-- <filtro>]
## Corre cada método test_* de tests/unit/test_*.gd. Sale con 1 si algo falla.

const UNIT_DIR := "res://tests/unit"
const BASE_SCRIPT := "test_case.gd"


func _initialize() -> void:
	var filter: String = OS.get_cmdline_user_args()[0] if not OS.get_cmdline_user_args().is_empty() else ""
	var total_tests: int = 0
	var total_checks: int = 0
	var failures: PackedStringArray = []

	for file: String in DirAccess.get_files_at(UNIT_DIR):
		if not file.begins_with("test_") or not file.ends_with(".gd") or file == BASE_SCRIPT:
			continue
		var script: GDScript = load(UNIT_DIR + "/" + file)
		for method: Dictionary in script.get_script_method_list():
			var name: String = method.name
			if not name.begins_with("test_") or (filter != "" and not ("%s.%s" % [file, name]).contains(filter)):
				continue
			var suite: RefCounted = script.new()
			suite.call(&"begin", "%s.%s" % [file.get_basename(), name])
			await suite.call(name)
			total_tests += 1
			total_checks += int(suite.get(&"checks"))
			failures.append_array(suite.get(&"failures"))

	for failure: String in failures:
		printerr("FAIL " + failure)
	print("run_all: %d tests, %d checks, %d fallos (%s)" % [total_tests, total_checks, failures.size(), Engine.get_version_info().string])
	quit(1 if not failures.is_empty() or total_tests == 0 else 0)
