@tool
extends RefCounted
## godot.run_tests (m16-26): corre los tests del proyecto (GUT, gdUnit4 o el comando de un check
## marcado `tests`) en otro proceso headless con el binario del editor, sin shell, y devuelve el total
## y cada falla con archivo y línea en vez de la salida entera. Ver core/test_runner.gd.
##
## Con el editor abierto: espera a que termine un escaneo del filesystem (el proceso de los tests
## importaría lo mismo a la vez) y corre una tanda a la vez, también entre sesiones.

const McpTool := preload("../mcp_tool.gd")
const UntrustedText := preload("../untrusted_text.gd")
const PermissionPolicy := preload("../../session/permission_policy.gd")
const TestRunner := preload("../../core/test_runner.gd")
const TurnChecks := preload("../../core/turn_checks.gd")
const AgentProcess := preload("../../transport/agent_process.gd")

const DEFAULT_TIMEOUT_S := 300
const MAX_TIMEOUT_S := 3600
## Lo que se espera a que el editor termine de escanear antes de lanzar.
const SCAN_WAIT_S := 30
const OUTPUT_GRACE_S := 0.2
## Líneas de salida que se guardan de cada canal mientras corre.
const KEEP_LINES := 400
const RESULTS_DIR := "res://.godot_agent/test_results"

## `() -> Array`: los turn_checks de project_config.tres.
var checks: Callable
## `(key) -> bool`: la tienda de aprobaciones de esta máquina.
var is_approved: Callable
## La carpeta del proyecto principal (la clave de aprobación, como los checks).
var project_dir: String = ""
## `(text)`: una línea en el log del harness.
var log_line: Callable

var _process: AgentProcess


func tools() -> Array:
	return [
		McpTool.enveloped(McpTool.create("run_tests", PermissionPolicy.GROUP_RUN,
			"Runs the project's tests in a separate headless Godot process, with this editor's binary, and returns how many passed and each failure with its file:line and message. Use it instead of running Godot from the shell to test. It uses GUT or gdUnit4 if the project has them, or the check the project marked for it in its settings. Run only the tests you're working on with `paths` (and `test`), and the whole suite before finishing.",
			{
				"paths": {"type": "array", "items": {"type": "string"}, "description": "Test scripts or folders to run (res://…; default: all the tests)"},
				"test": {"type": "string", "description": "Run only the tests whose name contains this text (GUT and project commands with {test})"},
				"timeout_s": {"type": "integer", "description": "Stop the run after this many seconds (default %d, max. %d)" % [DEFAULT_TIMEOUT_S, MAX_TIMEOUT_S]},
			}, [], _run_tests), McpTool.ENVELOPE_PARTS),
	]


## Para la tanda en curso (el plugin se cierra).
func stop() -> void:
	if _process:
		_process.stop()
		_process = null


func _run_tests(args: Dictionary) -> Dictionary:
	if _process != null:
		return McpTool.error("Tests are already running (from this or another agent session): wait for them to finish and try again.")
	var exists := func(path: String) -> bool: return FileAccess.file_exists(path) or DirAccess.dir_exists_absolute(path)
	var runner := TestRunner.detect(checks.call() if checks.is_valid() else [], exists)
	if runner.has("error"):
		return McpTool.error(str(runner.error))
	if runner.needs_approval:
		var key := TurnChecks.approval_key(project_dir, str(runner.command))
		if not (is_approved.is_valid() and is_approved.call(key)):
			return McpTool.error("The project's test command («%s», from the check «%s») isn't approved on this machine, so it can't run. Ask the user to allow it in Settings → After each turn → Project checks after each turn (it came with the project; they should check it before allowing it). Don't run it from the shell instead." % [runner.command, runner.check_name])
	var paths := PackedStringArray()
	var raw: Variant = args.get("paths", [])
	if raw is String:
		raw = [raw]
	if raw is Array:
		for path: Variant in raw:
			var text := str(path).strip_edges()
			if text.is_empty():
				continue
			if not text.begins_with("res://"):
				text = "res://" + text.trim_prefix("/")
			if not exists.call(text):
				return McpTool.error("%s doesn't exist." % text)
			paths.append(text)
	var test := McpTool.str_arg(args, "test").strip_edges()
	var timeout_s := clampi(McpTool.int_arg(args, "timeout_s", DEFAULT_TIMEOUT_S), 1, MAX_TIMEOUT_S)
	var report_dir := ProjectSettings.globalize_path(RESULTS_DIR)
	_clear_results(report_dir)
	DirAccess.make_dir_recursive_absolute(report_dir)
	var report_path := report_dir.path_join("results.xml") if runner.framework == TestRunner.GUT else report_dir
	var how := TestRunner.invocation(runner, paths, test, OS.get_executable_path(), ProjectSettings.globalize_path("res://").trim_suffix("/"), report_path, exists)
	if not str(how.error).is_empty():
		return McpTool.error(str(how.error))
	await _wait_for_scan()
	var started := Time.get_ticks_msec()
	_log("run_tests: %s %s" % [how.program, " ".join(how.args)])
	var ran := await _run(how, timeout_s)
	var run := {"framework": runner.framework, "code": ran.code, "timed_out": ran.timed_out, "timeout_s": timeout_s, "seconds": (Time.get_ticks_msec() - started) / 1000.0,
		"stdout": ran.stdout, "stderr": ran.stderr, "notes": how.notes, "launched": ran.launched, "launch_error": ran.launch_error, "test": test, "junit": {}}
	if runner.framework != TestRunner.COMMAND and not ran.timed_out:
		var xml_path := report_path if runner.framework == TestRunner.GUT else TestRunner.newest_xml(report_dir)
		if not xml_path.is_empty() and FileAccess.file_exists(xml_path):
			run.junit = TestRunner.parse_junit(FileAccess.get_file_as_string(xml_path))
	var result := TestRunner.report(run, func(text: String) -> String: return UntrustedText.wrap(text))
	_log("run_tests: %s (code %d, %.0f s)" % ["passed" if result.passed else "failed", int(ran.code), float(run.seconds)])
	return McpTool.text(result.text) if result.passed else McpTool.error(result.text)


func _run(how: Dictionary, timeout_s: int) -> Dictionary:
	var result := {"launched": false, "launch_error": "", "code": -1, "timed_out": false, "stdout": PackedStringArray(), "stderr": PackedStringArray()}
	# Array y no PackedStringArray: las lambdas capturan una copia de un Packed.
	var process := AgentProcess.new()
	var state := {"exited": false, "code": 0}
	var stdout: Array[String] = []
	var stderr: Array[String] = []
	process.line_received.connect(func(line: String) -> void: _keep(stdout, line))
	process.stderr_received.connect(func(line: String) -> void: _keep(stderr, line))
	process.exited.connect(func(code: int) -> void:
		state.exited = true
		state.code = code)
	if not process.start(str(how.program), how.args):
		result.launch_error = "%s: %s" % [how.program, process.last_error()]
		return result
	result.launched = true
	_process = process
	var tree := Engine.get_main_loop() as SceneTree
	var deadline := Time.get_ticks_msec() + timeout_s * 1000
	while not state.exited and Time.get_ticks_msec() < deadline and _process == process:
		await tree.process_frame
	if not state.exited:
		process.stop()
		result.timed_out = _process == process
	else:
		await tree.create_timer(OUTPUT_GRACE_S).timeout
		process.stop()
		result.code = int(state.code)
	if _process == process:
		_process = null
	result.stdout = PackedStringArray(stdout)
	result.stderr = PackedStringArray(stderr)
	return result


## Las primeras líneas (el arranque, los errores de carga) y las últimas: en el medio no suele haber
## nada que el resultado use.
static func _keep(lines: Array[String], line: String) -> void:
	if lines.size() >= KEEP_LINES:
		lines.remove_at(KEEP_LINES / 2)
	lines.append(line)


func _wait_for_scan() -> void:
	var filesystem := EditorInterface.get_resource_filesystem() if Engine.is_editor_hint() else null
	if filesystem == null:
		return
	var tree := Engine.get_main_loop() as SceneTree
	var deadline := Time.get_ticks_msec() + SCAN_WAIT_S * 1000
	while filesystem.is_scanning() and Time.get_ticks_msec() < deadline:
		await tree.process_frame


## Borra los XML de la corrida anterior: uno viejo no puede pasar por el de esta.
static func _clear_results(dir: String) -> void:
	if not DirAccess.dir_exists_absolute(dir):
		return
	for sub: String in DirAccess.get_directories_at(dir):
		_clear_results(dir.path_join(sub))
		DirAccess.remove_absolute(dir.path_join(sub))
	for file: String in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(file))


func _log(text: String) -> void:
	if log_line.is_valid():
		log_line.call(text)
