@tool
extends RefCounted
## Los tests del proyecto para godot.run_tests (m16-26): qué runner usar, con qué argumentos y cómo
## leer lo que dejó. Corren en otro proceso headless con el binario del editor, como el panel de GUT:
## un test toca autoloads, el árbol y estado global, y un crash adentro se llevaría el editor.
##
## El runner sale de un check del proyecto marcado `tests` (TurnChecks) o, si no hay, de GUT o gdUnit4
## instalados en addons/. GUT y gdUnit4 dejan un XML JUnit, que da cada falla con archivo y línea; un
## runner propio da el código de salida y su salida (lo de stderr primero, que es donde van las fallas).

const TurnChecks := preload("turn_checks.gd")

const GUT := "GUT"
const GDUNIT := "gdUnit4"
const COMMAND := "command"
const GUT_SCRIPT := "res://addons/gut/gut_cmdln.gd"
const GUT_CONFIG := "res://.gutconfig.json"
const GDUNIT_SCRIPT := "res://addons/gdUnit4/bin/GdUnitCmdTool.gd"
## Carpetas de tests de siempre, para GUT sin .gutconfig.json y para gdUnit4 sin `paths`.
const DEFAULT_DIRS: PackedStringArray = ["res://test", "res://tests"]
## En el comando de un runner propio: los `paths` tal cual (res://, separados por comas), solo los
## nombres de archivo, y el nombre del test. Un argumento con uno de estos sin valor no se pasa.
const PATHS_PLACEHOLDER := "{paths}"
const FILES_PLACEHOLDER := "{files}"
const TEST_PLACEHOLDER := "{test}"
## Fallas que se listan; las demás se cuentan.
const MAX_FAILURES := 20
const MESSAGE_CHARS := 400
## De un runner propio: líneas de stderr y las últimas de stdout.
const ERROR_LINES := 30
const TAIL_LINES := 12
const TAIL_LINES_PASSED := 4
const OUTPUT_CHARS := 4000


## El runner del proyecto: `{framework, command, check_name, needs_approval}`, o `{error}` si no hay.
## `checks` son los turn_checks de project_config.tres y `exists(path) -> bool` mira res://.
static func detect(checks: Array, exists: Callable) -> Dictionary:
	for check: Dictionary in TurnChecks.normalize_list(checks):
		if check.kind != TurnChecks.KIND_COMMAND or not check.get("tests", false) or str(check.command).is_empty():
			continue
		var command := str(check.command)
		var framework := COMMAND
		if command.contains(GUT_SCRIPT.trim_prefix("res://")):
			framework = GUT
		elif command.contains(GDUNIT_SCRIPT.trim_prefix("res://")):
			framework = GDUNIT
		return {"framework": framework, "command": command, "check_name": str(check.name), "needs_approval": true}
	if exists.call(GUT_SCRIPT):
		return {"framework": GUT, "command": "{godot} --headless --path {project} -s %s -gexit" % GUT_SCRIPT, "check_name": "", "needs_approval": false}
	if exists.call(GDUNIT_SCRIPT):
		return {"framework": GDUNIT, "command": "{godot} --headless --path {project} -s %s --ignoreHeadlessMode" % GDUNIT_SCRIPT, "check_name": "", "needs_approval": false}
	return {"error": "This project has no test runner the harness knows: neither GUT (%s) nor gdUnit4 (%s) is installed, and no project check is marked for godot.run_tests. The user can add one in Settings → MCP servers → Advanced → Project checks after each turn (a command with {godot}, {project} and, to run only some tests, {paths}, {files} or {test}) and tick «godot.run_tests»." % [GUT_SCRIPT.get_base_dir(), GDUNIT_SCRIPT.get_base_dir().get_base_dir()]}


## `{program, args, error, notes}` para correr `runner` con `paths` (res://) y `test` (parte del nombre
## de un test). `report` es la ruta absoluta del XML (GUT) o de su carpeta (gdUnit4). `notes`: lo que
## el pedido no pudo usar, para el resultado.
static func invocation(runner: Dictionary, paths: PackedStringArray, test: String, godot_path: String, project_dir: String, report: String, exists: Callable) -> Dictionary:
	var parsed := TurnChecks.parse_command(str(runner.command))
	if not str(parsed.error).is_empty():
		return {"program": "", "args": PackedStringArray(), "error": "The test command «%s»: %s" % [runner.command, parsed.error], "notes": PackedStringArray()}
	var args := TurnChecks.expand(parsed.args, godot_path, project_dir)
	var notes := PackedStringArray()
	match str(runner.framework):
		GUT:
			args = _gut_args(args, paths, test, report, exists)
		GDUNIT:
			args = _gdunit_args(args, paths, report, exists)
			if not test.is_empty():
				notes.append("gdUnit4 can't pick tests by name from the command line, so `test` was ignored: it ran the whole files.")
		_:
			var used := {"paths": false, "test": false}
			args = _custom_args(args, paths, test, used)
			if not paths.is_empty() and not used.paths:
				notes.append("The project's test command has no {paths} or {files}, so `paths` was ignored: it ran every test.")
			if not test.is_empty() and not used.test:
				notes.append("The project's test command has no {test}, so `test` was ignored.")
	return {"program": args[0], "args": args.slice(1), "error": "", "notes": notes}


static func _gut_args(args: PackedStringArray, paths: PackedStringArray, test: String, report: String, exists: Callable) -> PackedStringArray:
	var result := PackedStringArray()
	for arg: String in args:
		# Lo que pide la llamada pisa lo que traiga el comando del proyecto.
		if arg.begins_with("-gjunit_xml_file=") or (not paths.is_empty() and (arg.begins_with("-gtest=") or arg.begins_with("-gdir=") or arg.begins_with("-gselect="))) \
				or (not test.is_empty() and arg.begins_with("-gunit_test_name=")):
			continue
		result.append(arg)
	if not result.has("-gexit"):
		result.append("-gexit")
	var scripts := PackedStringArray()
	var dirs := PackedStringArray()
	for path: String in paths:
		if path.ends_with(".gd"):
			scripts.append(path)
		else:
			dirs.append(path.trim_suffix("/"))
	if not scripts.is_empty():
		result.append("-gtest=" + ",".join(scripts))
	if not dirs.is_empty():
		result.append("-gdir=" + ",".join(dirs))
		result.append("-ginclude_subdirs")
	if paths.is_empty() and not exists.call(GUT_CONFIG) and not _has_prefix(result, "-gdir=") and not _has_prefix(result, "-gtest="):
		# Sin .gutconfig.json, GUT no sabe dónde buscar: las carpetas de siempre.
		var found := PackedStringArray(Array(DEFAULT_DIRS).filter(func(dir: String) -> bool: return exists.call(dir)))
		if not found.is_empty():
			result.append("-gdir=" + ",".join(found))
			result.append("-ginclude_subdirs")
	if not test.is_empty():
		result.append("-gunit_test_name=" + test)
	result.append("-gjunit_xml_file=" + report)
	return result


static func _gdunit_args(args: PackedStringArray, paths: PackedStringArray, report: String, exists: Callable) -> PackedStringArray:
	var result := PackedStringArray()
	var skip_next := false
	var has_add := false
	for arg: String in args:
		if skip_next:
			skip_next = false
			continue
		if arg in ["-rd", "--report-directory"] or (not paths.is_empty() and arg in ["-a", "--add"]):
			skip_next = true
			continue
		has_add = has_add or arg in ["-a", "--add"]
		result.append(arg)
	for path: String in paths:
		result.append_array(["-a", path])
	if paths.is_empty() and not has_add:
		var found := Array(DEFAULT_DIRS).filter(func(dir: String) -> bool: return exists.call(dir))
		result.append_array(["-a", str(found[0]) if not found.is_empty() else "res://"])
	# Sin -c, gdUnit4 corta en la primera falla.
	if not result.has("-c") and not result.has("--continue"):
		result.append("-c")
	result.append_array(["-rd", report])
	return result


static func _custom_args(args: PackedStringArray, paths: PackedStringArray, test: String, used: Dictionary) -> PackedStringArray:
	var files := PackedStringArray(Array(paths).map(func(path: String) -> String: return path.get_file()))
	var values := {PATHS_PLACEHOLDER: ",".join(paths), FILES_PLACEHOLDER: ",".join(files), TEST_PLACEHOLDER: test}
	var result := PackedStringArray()
	for arg: String in args:
		var keep := true
		var expanded := arg
		for placeholder: String in values:
			if not arg.contains(placeholder):
				continue
			if placeholder == TEST_PLACEHOLDER:
				used.test = true
			else:
				used.paths = true
			if str(values[placeholder]).is_empty():
				keep = false
			expanded = expanded.replace(placeholder, values[placeholder])
		if keep:
			result.append(expanded)
	return result


static func _has_prefix(args: PackedStringArray, prefix: String) -> bool:
	for arg: String in args:
		if arg.begins_with(prefix):
			return true
	return false


## Un XML JUnit (GUT, gdUnit4): `{ok, total, failed, skipped, failures: [{test, suite, file, line,
## message}]}`. `ok` false si no se pudo leer.
static func parse_junit(xml: String) -> Dictionary:
	var result := {"ok": false, "total": 0, "failed": 0, "skipped": 0, "failures": []}
	if xml.strip_edges().is_empty():
		return result
	var parser := XMLParser.new()
	if parser.open_buffer(xml.to_utf8_buffer()) != OK:
		return result
	var suite := ""
	var testcase := {}
	var failure := {}
	while parser.read() == OK:
		match parser.get_node_type():
			XMLParser.NODE_ELEMENT:
				var tag := parser.get_node_name()
				if tag == "testsuite":
					suite = _attr(parser, "package") if not _attr(parser, "package").is_empty() else _attr(parser, "name")
				elif tag == "testcase":
					result.total += 1
					testcase = {"test": _attr(parser, "name"), "suite": suite, "classname": _attr(parser, "classname"), "failed": false}
					if parser.is_empty():
						testcase = {}
				elif tag in ["failure", "error"] and not testcase.is_empty():
					if not testcase.failed:
						testcase.failed = true
						result.failed += 1
						failure = {"test": testcase.test, "suite": testcase.suite, "classname": testcase.classname, "attr": _attr(parser, "message"), "text": ""}
						(result.failures as Array).append(failure)
					if parser.is_empty():
						failure = {}
				elif tag == "skipped" and not testcase.is_empty():
					result.skipped += 1
			XMLParser.NODE_TEXT:
				if not failure.is_empty():
					failure.text += parser.get_node_data()
			XMLParser.NODE_CDATA:
				# El contenido de un CDATA viene en el nombre del nodo.
				if not failure.is_empty():
					failure.text += parser.get_node_name()
			XMLParser.NODE_ELEMENT_END:
				var tag := parser.get_node_name()
				if tag in ["failure", "error"]:
					failure = {}
				elif tag == "testcase":
					testcase = {}
	result.ok = true
	var failures: Array = []
	for item: Dictionary in result.failures:
		failures.append(_located(item))
	result.failures = failures
	return result


static func _attr(parser: XMLParser, name: String) -> String:
	return parser.get_named_attribute_value_safe(name)


## Archivo, línea y mensaje de una falla del XML. gdUnit4 los da en el atributo («FAILED:
## res://x.gd:12»); GUT da la ruta sin res:// en classname y la línea en el texto («at line 12»).
static func _located(item: Dictionary) -> Dictionary:
	var text := strip_ansi(str(item.text)).strip_edges()
	var file := ""
	var line := 0
	var found := RegEx.create_from_string("(res://[^\\s:\"'<>]+\\.(?:gd|cs)):(\\d+)").search(str(item.attr) + "\n" + text)
	if found:
		file = found.get_string(1)
		line = found.get_string(2).to_int()
	if file.is_empty():
		for candidate: String in [str(item.classname), str(item.suite)]:
			if candidate.ends_with(".gd") or candidate.ends_with(".cs"):
				file = candidate if candidate.begins_with("res://") else "res://" + candidate
				break
	if line == 0:
		var at_line := RegEx.create_from_string("at line (\\d+)").search(text)
		if at_line:
			line = at_line.get_string(1).to_int()
	var message := text if not text.is_empty() else str(item.attr)
	message = RegEx.create_from_string("\\s*at line \\d+\\s*").sub(message, " ", true).strip_edges()
	if message.length() > MESSAGE_CHARS:
		message = message.left(MESSAGE_CHARS) + "…"
	return {"test": str(item.test), "suite": str(item.suite), "file": file, "line": line, "message": message}


static func strip_ansi(text: String) -> String:
	return RegEx.create_from_string("\\x1b\\[[0-9;]*[A-Za-z]").sub(text, "", true)


## El resultado para el agente. `run`: `{framework, code, timed_out, timeout_s, seconds, stdout,
## stderr, junit (parse_junit o {}), notes, launched, launch_error}`. `wrap(text) -> String` pone en
## sobre lo que viene de los tests. `{text, passed, locations: [{path, line}]}`.
static func report(run: Dictionary, wrap: Callable) -> Dictionary:
	var framework := str(run.framework)
	var label := framework if framework != COMMAND else "the project's test command"
	var lines := PackedStringArray()
	var locations: Array[Dictionary] = []
	var passed := false
	if not run.get("launched", true):
		return {"text": "Could not launch the tests: %s" % run.get("launch_error", ""), "passed": false, "locations": locations}
	var junit: Dictionary = run.get("junit", {})
	var seconds := "%d s" % int(run.get("seconds", 0))
	if run.get("timed_out", false):
		lines.append("STOPPED after %d s (the time limit) with %s. Pass a larger `timeout_s` or run fewer tests with `paths`." % [int(run.timeout_s), label])
	elif junit.get("ok", false) and int(junit.total) > 0:
		passed = int(junit.failed) == 0
		var counts := "%d passed%s" % [int(junit.total) - int(junit.failed) - int(junit.skipped), ", %d skipped" % int(junit.skipped) if int(junit.skipped) > 0 else ""]
		lines.append(("PASSED: %d tests (%s, %s, %s)." % [int(junit.total), counts, label, seconds]) if passed else ("FAILED: %d of %d tests (%s; %s, %s)." % [int(junit.failed), int(junit.total), counts, label, seconds]))
		var shown := 0
		for failure: Dictionary in junit.failures:
			if shown == MAX_FAILURES:
				lines.append("…and %d more failures." % (int(junit.failed) - shown))
				break
			shown += 1
			var where := "%s:%d" % [failure.file, failure.line] if failure.line > 0 else str(failure.file)
			lines.append("✗ %s — %s" % [failure.test, where if not where.is_empty() else failure.suite])
			if not str(failure.message).is_empty():
				lines.append("  " + str(wrap.call(str(failure.message))).replace("\n", "\n  "))
			if not str(failure.file).is_empty():
				locations.append({"path": failure.file, "line": failure.line})
		if not passed and int(run.code) != 0 and junit.failures.is_empty():
			lines.append("Exit code %d." % int(run.code))
	else:
		passed = int(run.code) == 0
		var none := " and wrote no test results" if framework != COMMAND else ""
		lines.append("%s with exit code %d (%s%s, %s)." % ["PASSED" if passed else "FAILED", int(run.code), label, none, seconds])
		if framework != COMMAND and passed:
			lines[0] = "No tests ran (%s found none%s, %s). Check `paths`, or where the project keeps its tests." % [label, " matching `test`" if not str(run.get("test", "")).is_empty() else "", seconds]
			passed = false
	if not passed or framework == COMMAND:
		var errors := PackedStringArray(Array(run.get("stderr", PackedStringArray())).map(func(line: String) -> String: return strip_ansi(line)).filter(func(line: String) -> bool: return not line.strip_edges().is_empty()))
		var tail := PackedStringArray(Array(run.get("stdout", PackedStringArray())).map(func(line: String) -> String: return strip_ansi(line)).filter(func(line: String) -> bool: return not line.strip_edges().is_empty()))
		var keep_tail := TAIL_LINES_PASSED if passed else TAIL_LINES
		if not junit.get("ok", false) or int(junit.get("total", 0)) == 0 or run.get("timed_out", false):
			if not errors.is_empty() and not passed:
				var shown_errors := errors.slice(0, ERROR_LINES)
				lines.append("Error output%s:\n%s" % [" (first %d lines)" % ERROR_LINES if errors.size() > ERROR_LINES else "", wrap.call(_clip("\n".join(shown_errors)))])
				locations.append_array(output_locations(shown_errors))
			if not tail.is_empty():
				var last := tail.slice(maxi(0, tail.size() - keep_tail))
				lines.append("Last lines of the output:\n%s" % wrap.call(_clip("\n".join(last))))
				if not passed:
					locations.append_array(output_locations(last))
	for note: String in run.get("notes", PackedStringArray()):
		lines.append("Note: " + note)
	return {"text": "\n".join(lines), "passed": passed, "locations": _unique(locations)}


## Los `res://archivo.gd:línea` de unas líneas de salida.
static func output_locations(lines: PackedStringArray) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var pattern := RegEx.create_from_string("(res://[^\\s:\"'<>()]+\\.(?:gd|cs|tscn)):(\\d+)")
	for line: String in lines:
		for found: RegExMatch in pattern.search_all(line):
			result.append({"path": found.get_string(1), "line": found.get_string(2).to_int()})
	return result


static func _unique(locations: Array[Dictionary]) -> Array[Dictionary]:
	var seen := {}
	var result: Array[Dictionary] = []
	for location: Dictionary in locations:
		var key := "%s:%d" % [location.path, location.line]
		if not seen.has(key):
			seen[key] = true
			result.append(location)
	return result


static func _clip(text: String) -> String:
	return text if text.length() <= OUTPUT_CHARS else "…" + text.right(OUTPUT_CHARS)


## El XML más nuevo de `dir` y sus subcarpetas (gdUnit4 deja report_N/results.xml), o "".
static func newest_xml(dir: String) -> String:
	var best := ""
	var best_time := -1
	var pending: Array[String] = [dir]
	while not pending.is_empty():
		var current: String = pending.pop_back()
		for sub: String in DirAccess.get_directories_at(current):
			pending.append(current.path_join(sub))
		for file: String in DirAccess.get_files_at(current):
			if file.ends_with(".xml"):
				var time := FileAccess.get_modified_time(current.path_join(file))
				if time > best_time:
					best_time = time
					best = current.path_join(file)
	return best
