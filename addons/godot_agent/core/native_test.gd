@tool
extends RefCounted
## Probar la GDExtension en un Godot headless aparte (m19-02): un segfault en código nativo mata al
## proceso que cargó la biblioteca, así que la prueba nunca corre en el editor. Corre el runner
## native/extension_tests.gd sobre el proyecto de prueba y devuelve los tests que fallaron, los
## errores de carga y, si crasheó, el backtrace con las líneas de la extensión resueltas.

const AgentProcess := preload("../transport/agent_process.gd")
const CommandResolver := preload("../transport/command_resolver.gd")

const RUNNER := "res://addons/godot_agent/native/extension_tests.gd"
const DEFAULT_TIMEOUT_S := 120
const MAX_TIMEOUT_S := 600
const IMPORT_TIMEOUT_S := 300.0
const OUTPUT_GRACE_S := 0.3
const CRASH_MARKER := "handle_crash:"
const LOAD_ERROR_HINTS: PackedStringArray = [
	"GDExtension", "Can't open dynamic library", "cannot open shared object file", "entry point",
	"Getter method", "Setter method", "runtime class",
]
const TAIL_LINES := 30
## Frames de una biblioteca en el backtrace: `... - /ruta/libx.so(+0x8463c) [0x...]`.
const _FRAME_PATTERN := "- (\\S+\\.(?:so|dylib|dll))(?:\\.[0-9.]+)?\\(\\+0x([0-9a-fA-F]+)\\)"


## El proyecto de prueba de la extensión: `project/` o `demo/` (godot-cpp-template), `godot/` al lado
## de `rust/` (gdext), la raíz misma, o si no el proyecto abierto. Ruta absoluta, o "".
static func find_test_project(native: Dictionary, open_dir: String) -> String:
	var candidates: PackedStringArray = []
	if not native.is_empty():
		var root: String = native.root
		candidates.append_array([root.path_join("project"), root.path_join("demo"), root.path_join("godot"), root, root.get_base_dir().path_join("godot")])
	candidates.append(open_dir)
	for dir: String in candidates:
		var clean := _strip_slash(dir.simplify_path())
		if FileAccess.file_exists(clean.path_join("project.godot")):
			return clean
	return ""


static func same_dir(a: String, b: String) -> bool:
	return _strip_slash(a.simplify_path()) == _strip_slash(b.simplify_path())


## Los `.gdextension` de `dir`, como res:// relativos a `dir`. Saltea carpetas ocultas y las que
## tienen .gdignore, como el EditorFileSystem.
static func gdextension_files(dir: String, prefix: String = "res://") -> PackedStringArray:
	var result: PackedStringArray = []
	if FileAccess.file_exists(dir.path_join(".gdignore")):
		return result
	for file: String in DirAccess.get_files_at(dir):
		if file.get_extension() == "gdextension":
			result.append(prefix + file)
	for sub: String in DirAccess.get_directories_at(dir):
		if not sub.begins_with("."):
			result.append_array(gdextension_files(dir.path_join(sub), prefix + sub + "/"))
	return result


## Los `.gdextension` que Godot carga al arrancar (`.godot/extension_list.cfg`, lo escribe el import).
static func registered_extensions(dir: String) -> PackedStringArray:
	var path := dir.path_join(".godot/extension_list.cfg")
	if not FileAccess.file_exists(path):
		return PackedStringArray()
	var result: PackedStringArray = []
	for line: String in FileAccess.get_file_as_string(path).split("\n", false):
		if not line.strip_edges().is_empty():
			result.append(line.strip_edges())
	return result


## Los `.gdextension` de `dir` con `reloadable = true`: el editor que tenga abierto ese proyecto
## recarga su biblioteca cuando cambia, y un crash en la recarga lo tira abajo.
static func reloadable_extensions(dir: String) -> PackedStringArray:
	var result: PackedStringArray = []
	for res_path: String in gdextension_files(dir):
		var config := ConfigFile.new()
		if config.load(dir.path_join(res_path.trim_prefix("res://"))) == OK and bool(config.get_value("configuration", "reloadable", false)):
			result.append(res_path)
	return result


## Corre los tests. `options`: `tests` (res://, por defecto res://tests), `classes`
## (PackedStringArray), `timeout_s`, `import` (bool: importar antes si falta registrar una extensión;
## nunca sobre el proyecto que tiene abierto el editor). Devuelve
## `{error, code, crashed, timed_out, imported, unregistered, parsed, lines}`.
static func run(test_dir: String, options: Dictionary = {}) -> Dictionary:
	var report := {"error": "", "code": -1, "crashed": false, "timed_out": false, "imported": false, "unregistered": PackedStringArray(), "parsed": {}, "lines": PackedStringArray()}
	var godot := OS.get_executable_path()
	var registered := registered_extensions(test_dir)
	var missing: PackedStringArray = []
	for path: String in gdextension_files(test_dir):
		if not path in registered:
			missing.append(path)
	if not missing.is_empty() and bool(options.get("import", false)):
		var imported: Dictionary = await _run_process(godot, PackedStringArray(["--headless", "--no-header", "--path", test_dir, "--import"]), IMPORT_TIMEOUT_S)
		report.imported = true
		if not imported.error.is_empty():
			report.error = "The import before the test failed: %s" % imported.error
			return report
		registered = registered_extensions(test_dir)
		missing = PackedStringArray(Array(missing).filter(func(path: String) -> bool: return not path in registered))
	report.unregistered = missing
	var args := PackedStringArray(["--headless", "--no-header", "--path", test_dir, "--script", ProjectSettings.globalize_path(RUNNER), "--", "--dir=" + str(options.get("tests", "res://tests"))])
	var classes: PackedStringArray = options.get("classes", PackedStringArray())
	if not classes.is_empty():
		args.append("--class=" + ",".join(classes))
	var timeout := clampi(int(options.get("timeout_s", DEFAULT_TIMEOUT_S)), 5, MAX_TIMEOUT_S)
	var result: Dictionary = await _run_process(godot, args, float(timeout))
	report.lines = result.lines
	report.code = result.code
	report.timed_out = result.timed_out
	if not result.error.is_empty() and not result.timed_out:
		report.error = result.error
		return report
	report.parsed = parse_output(result.lines)
	report.crashed = not (report.parsed.crash as PackedStringArray).is_empty()
	return report


## La salida del runner → `{passed, failed, load_errors, crash, gdscript_backtrace, done, loaded}`.
static func parse_output(lines: PackedStringArray) -> Dictionary:
	var ansi := RegEx.create_from_string("\\x1b\\[[0-9;]*m")
	var parsed := {"passed": 0, "failed": PackedStringArray(), "load_errors": PackedStringArray(), "crash": PackedStringArray(), "done": "", "loaded": ""}
	var in_crash := false
	for raw: String in lines:
		var line := ansi.sub(raw, "", true).strip_edges()
		if line.contains(CRASH_MARKER):
			in_crash = true
		# stdout y stderr llegan intercalados: las líneas del runner pueden caer dentro del crash.
		if in_crash and not (line.begins_with("PASS ") or line.begins_with("FAIL ") or line.begins_with("LOADED ")):
			if not line.is_empty() and not line.begins_with("=====") and not line.begins_with("Dumping the backtrace") and not line.begins_with("Load address"):
				parsed.crash.append(line)
			continue
		if line.begins_with("PASS "):
			parsed.passed += 1
		elif line.begins_with("FAIL "):
			parsed.failed.append(line.trim_prefix("FAIL "))
		elif line.begins_with("DONE "):
			parsed.done = line.trim_prefix("DONE ")
		elif line.begins_with("LOADED "):
			parsed.loaded = line.trim_prefix("LOADED ")
		elif line.begins_with("ERROR"):
			var message := line.trim_prefix("ERROR:").trim_prefix("ERROR").strip_edges()
			for hint: String in LOAD_ERROR_HINTS + PackedStringArray(["no GDExtension loaded", "isn't registered"]):
				if message.contains(hint) and not message in parsed.load_errors:
					parsed.load_errors.append(message)
					break
	return parsed


## Resuelve con addr2line los frames del backtrace que caen en una biblioteca bajo `dirs` (la de la
## extensión), con la clave como aparece en el frame:
## `{"/ruta/libx.so(+0x8463c)": "MyNode::_process(double) at src/my_node.cpp:12"}`.
## Sin addr2line, o sin símbolos (godot-cpp compila sin debug_symbols), {}.
static func symbolize(crash: PackedStringArray, dirs: PackedStringArray) -> Dictionary:
	var addr2line := CommandResolver.resolve("addr2line")
	if addr2line.is_empty():
		return {}
	var pattern := RegEx.create_from_string(_FRAME_PATTERN)
	var by_library: Dictionary = {}  # biblioteca -> [offsets]
	for line: String in crash:
		var found := pattern.search(line)
		if found == null:
			continue
		var library := found.get_string(1)
		if not Array(dirs).any(func(dir: String) -> bool: return library.begins_with(_strip_slash(dir) + "/")):
			continue
		if not by_library.has(library):
			by_library[library] = PackedStringArray()
		var offset := "0x" + found.get_string(2)
		if not offset in by_library[library]:
			by_library[library].append(offset)
	var result: Dictionary = {}
	for library: String in by_library:
		var output: Array = []
		var offsets: PackedStringArray = by_library[library]
		if OS.execute(addr2line, PackedStringArray(["-f", "-C", "-e", library]) + offsets, output, true) != 0 or output.is_empty():
			continue
		var answer: PackedStringArray = str(output[0]).strip_edges().split("\n")
		for i: int in offsets.size():
			if i * 2 + 1 >= answer.size():
				break
			var function := answer[i * 2].strip_edges()
			var place := answer[i * 2 + 1].strip_edges()
			if function == "??" and place.begins_with("??"):
				continue
			result["%s(+%s)" % [library, offsets[i]]] = "%s at %s" % [function, place]
	return result


## Texto para el agente a partir del reporte de `run`.
static func summarize(report: Dictionary, test_dir: String, extension_dirs: PackedStringArray) -> String:
	var lines: PackedStringArray = []
	var parsed: Dictionary = report.parsed
	if report.timed_out:
		lines.append("Timed out: the test process was stopped. A test may be waiting forever, or a script that fails to parse left the game running.")
	elif report.crashed:
		lines.append("CRASHED in %s (exit code %d). The editor was not affected." % [test_dir, report.code])
	elif report.code == 0:
		lines.append("Passed in %s · %s" % [test_dir, parsed.get("done", "")])
	elif report.code == 2:
		lines.append("The extension or a class did not load in %s." % test_dir)
	else:
		lines.append("Failed in %s (exit code %d) · %s" % [test_dir, report.code, parsed.get("done", "")])
	if report.imported:
		lines.append("Ran `godot --headless --import` first, to register the .gdextension files.")
	if not (report.unregistered as PackedStringArray).is_empty():
		lines.append("Not registered in .godot/extension_list.cfg, so not loaded: %s. Godot adds them when it imports the project." % ", ".join(report.unregistered))
	if not str(parsed.get("loaded", "")).is_empty():
		lines.append("Loaded: " + parsed.loaded)
	for message: String in parsed.get("load_errors", PackedStringArray()):
		lines.append("✗ " + message)
	for failure: String in parsed.get("failed", PackedStringArray()):
		lines.append("✗ " + failure)
	var crash: PackedStringArray = parsed.get("crash", PackedStringArray())
	if not crash.is_empty():
		var symbols := symbolize(crash, extension_dirs)
		var frame := RegEx.create_from_string("^\\[\\d+\\] ")
		var hidden := 0
		lines.append("")
		for line: String in crash:
			# De los frames C++ quedan los de la extensión: los del motor y libc no le sirven al agente.
			var is_frame := frame.search(line) != null and line.contains(" - ")
			if is_frame and not Array(extension_dirs).any(func(dir: String) -> bool: return line.contains(_strip_slash(dir) + "/")):
				hidden += 1
				continue
			if line.begins_with("-- END OF C++") and hidden > 0:
				lines.append("(%d frames in Godot or system libraries not shown)" % hidden)
				hidden = 0
			lines.append(line)
			for key: String in symbols:
				if line.contains(key):
					lines.append("    → " + symbols[key])
		if symbols.is_empty():
			lines.append("Frames inside the extension show only as offsets: rebuild with `debug_symbols=yes` (and keep the same build) to get functions and lines.")
	if report.timed_out or (report.code not in [0, 1, 2] and not report.crashed):
		lines.append("")
		lines.append_array((report.lines as PackedStringArray).slice(-TAIL_LINES))
	return "\n".join(lines)


static func _run_process(executable: String, args: PackedStringArray, timeout_s: float) -> Dictionary:
	var process := AgentProcess.new()
	var lines: PackedStringArray = []
	var state := {"exited": false, "code": 0}
	process.line_received.connect(func(line: String) -> void: lines.append(line))
	process.stderr_received.connect(func(line: String) -> void: lines.append(line))
	process.exited.connect(func(code: int) -> void:
		state.exited = true
		state.code = code)
	if not process.start(executable, args):
		return {"error": "Could not launch Godot: %s" % process.last_error(), "lines": lines, "code": -1, "timed_out": false}
	var tree := Engine.get_main_loop() as SceneTree
	var deadline := Time.get_ticks_msec() + int(timeout_s * 1000.0)
	while not state.exited and Time.get_ticks_msec() < deadline:
		await tree.process_frame
	if not state.exited:
		process.stop()
		return {"error": "Did not finish within %d s." % int(timeout_s), "lines": lines, "code": -1, "timed_out": true}
	await tree.create_timer(OUTPUT_GRACE_S).timeout
	process.stop()
	return {"error": "", "lines": lines, "code": int(state.code), "timed_out": false}


static func _strip_slash(path: String) -> String:
	return path.left(-1) if path.ends_with("/") and path.length() > 1 else path
