extends SceneTree
## Runner mínimo de tests unitarios (spec §13).
## Uso: godot --headless --path <repo> --script tests/run_all.gd [-- <filtro>]
## Corre cada método test_* de tests/unit/test_*.gd. Sale con 1 si algo falla.
## Un error de script (índice fuera de rango, llamada inválida…) corta el test sin que el test lo
## note: el logger lo cuenta y el test falla (m13-02).

const UNIT_DIR := "res://tests/unit"
const BASE_SCRIPT := "test_case.gd"


## Junta los errores de script; los de push_error y del motor no cuentan (los tests los provocan a
## propósito). Puede llamarse desde otros hilos.
class ScriptErrors extends Logger:
	var _mutex := Mutex.new()
	var _messages: PackedStringArray = []

	func _log_error(function: String, file: String, line: int, code: String, rationale: String, _editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		if error_type != ERROR_TYPE_SCRIPT:
			return
		_mutex.lock()
		_messages.append("%s (%s:%d %s)" % [rationale if not rationale.is_empty() else code, file.get_file(), line, function])
		_mutex.unlock()

	func take() -> PackedStringArray:
		_mutex.lock()
		var result := _messages
		_messages = []
		_mutex.unlock()
		return result


func _initialize() -> void:
	var filter: String = OS.get_cmdline_user_args()[0] if not OS.get_cmdline_user_args().is_empty() else ""
	var total_tests: int = 0
	var total_checks: int = 0
	var failures: PackedStringArray = []
	var script_errors := ScriptErrors.new()
	OS.add_logger(script_errors)

	for file: String in DirAccess.get_files_at(UNIT_DIR):
		if not file.begins_with("test_") or not file.ends_with(".gd") or file == BASE_SCRIPT:
			continue
		var script: GDScript = load(UNIT_DIR + "/" + file)
		for method: Dictionary in script.get_script_method_list():
			var name: String = method.name
			if not name.begins_with("test_") or (filter != "" and not ("%s.%s" % [file, name]).contains(filter)):
				continue
			var suite: RefCounted = script.new()
			var test_name := "%s.%s" % [file.get_basename(), name]
			script_errors.take()
			suite.call(&"begin", test_name)
			await suite.call(name)
			total_tests += 1
			total_checks += int(suite.get(&"checks"))
			failures.append_array(suite.get(&"failures"))
			for message: String in script_errors.take():
				failures.append("%s › error de script: %s" % [test_name, message])

	for failure: String in failures:
		printerr("FAIL " + failure)
	OS.remove_logger(script_errors)
	print("run_all: %d tests, %d checks, %d fallos (%s)" % [total_tests, total_checks, failures.size(), Engine.get_version_info().string])
	quit(1 if not failures.is_empty() or total_tests == 0 else 0)
