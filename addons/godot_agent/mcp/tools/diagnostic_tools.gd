@tool
extends RefCounted
## Tools de diagnóstico (spec §6): get_errors, validate_scripts y capture_editor_viewport. Los .cs
## se validan compilando el proyecto con dotnet (m14-07).

const McpTool := preload("../mcp_tool.gd")
const ErrorCollector := preload("../../editor/error_collector.gd")
const AgentProcess := preload("../../transport/agent_process.gd")
const EditorContext := preload("../../ui/editor_context.gd")
const PermissionPolicy := preload("../../session/permission_policy.gd")
const CsharpBuild := preload("../../core/csharp_build.gd")

const CHECKER_SCRIPT := "res://addons/godot_agent/mcp/tools/script_checker.gd"
const MAX_SCRIPTS := 400
const CHECK_TIMEOUT_S := 60.0
## Margen para que lleguen las últimas líneas de stderr después del exit.
const STDERR_GRACE_S := 0.3
const ERROR_LIMIT := 200
const HARNESS_ADDON := "res://addons/godot_agent"

var errors: ErrorCollector
var project_path: String = ""


func setup(collector: ErrorCollector, project_dir: String) -> void:
	errors = collector
	project_path = project_dir


func tools() -> Array:
	var diagnostics := PermissionPolicy.GROUP_DIAGNOSTICS
	return [
		McpTool.create("get_errors", diagnostics,
			"Errors and warnings from the editor (scripts, Output) and from the game (Debugger) since a mark. Returns the current mark: pass it as `since` next time to see only what is new.",
			{"since": {"type": "integer", "description": "Mark returned by a previous call (default 0: everything stored)"}},
			[], _get_errors),
		McpTool.create("validate_scripts", diagnostics,
			"Parses GDScript scripts in a separate process and compiles C# with dotnet build, and returns the errors by file and line. Without `paths`, all the project's .gd files (and its C#, if it has a .csproj).",
			{"paths": {"type": "array", "items": {"type": "string"}, "description": "res://…gd or res://…cs paths"}},
			[], _validate_scripts),
		McpTool.create("capture_editor_viewport", diagnostics,
			"Captures the editor's 2D or 3D viewport as a PNG.",
			{"which": {"type": "string", "enum": ["2d", "3d"], "description": "Viewport to capture"}},
			["which"], _capture_editor_viewport),
	]


func _get_errors(args: Dictionary) -> String:
	var since := McpTool.int_arg(args, "since", 0)
	var entries := errors.entries_since(since)
	var lines: PackedStringArray = []
	var shown := entries.slice(maxi(entries.size() - ERROR_LIMIT, 0))
	for entry: Dictionary in shown:
		lines.append(ErrorCollector.format_entry(entry))
	var header := "mark: %d · %d new since %d" % [errors.mark(), entries.size(), since]
	if shown.size() < entries.size():
		header += " (showing the last %d)" % shown.size()
	if entries.is_empty():
		return header + "\nNo new errors or warnings."
	return header + "\n" + "\n".join(lines)


func _validate_scripts(args: Dictionary) -> Dictionary:
	var paths: PackedStringArray = []
	var requested: Variant = args.get("paths")
	if requested is Array and not requested.is_empty():
		for path: Variant in requested:
			var text := str(path)
			if not text.begins_with("res://") or not (text.ends_with(".gd") or text.ends_with(".cs")):
				return McpTool.error("'%s' is not a res://…gd or res://…cs path." % text)
			if not FileAccess.file_exists(text):
				return McpTool.error("%s does not exist." % text)
			paths.append(text)
	else:
		_collect_scripts(EditorInterface.get_resource_filesystem().get_filesystem(), paths)
	var csharp := Array(paths).filter(func(path: String) -> bool: return path.ends_with(".cs"))
	paths = PackedStringArray(Array(paths).filter(func(path: String) -> bool: return path.ends_with(".gd")))
	var csproj := CsharpBuild.find_project(project_path)
	var explicit: bool = requested is Array and not requested.is_empty()
	var whole_csharp: bool = not explicit and not csproj.is_empty()
	var notes: PackedStringArray = []
	if not explicit and csproj.is_empty() and not csharp.is_empty():
		notes.append("C# not checked: the project has no .csproj (Project → Tools → C# → Create C# solution).")
		csharp = []
	if paths.is_empty() and csharp.is_empty() and not whole_csharp:
		return McpTool.text("There are no .gd scripts to validate.")
	var truncated := paths.size() > MAX_SCRIPTS
	if truncated:
		paths = paths.slice(0, MAX_SCRIPTS)
	var report: Dictionary = await check_scripts(paths) if not paths.is_empty() else {"error": "", "results": {}}
	if not report.error.is_empty():
		return McpTool.error(report.error)
	var lines := failure_lines(paths, report)
	if not csharp.is_empty() or whole_csharp:
		if csproj.is_empty():
			return McpTool.error("This project has no .csproj, so its C# can't be compiled: create it in the editor with Project → Tools → C# → Create C# solution.")
		var build: Dictionary = await CsharpBuild.build(csproj)
		if not build.error.is_empty():
			return McpTool.error(build.error)
		# dotnet solo nombra los archivos con errores, a veces otros que los pedidos.
		var compiled := PackedStringArray(csharp)
		for path: String in build.results:
			if not path in compiled:
				compiled.append(path)
		for path: String in compiled:
			if not build.results.has(path):
				build.results[path] = {"ok": true, "errors": []}
		lines.append_array(failure_lines(compiled, build))
		paths.append_array(compiled)
	var failed: int = Array(lines).filter(func(line: String) -> bool: return line.begins_with("✗ ")).size()
	lines.append_array(notes)
	var header := "%d scripts validated · %d with errors" % [paths.size(), failed]
	if truncated:
		header += " (validated the first %d; pass `paths` for the rest)" % MAX_SCRIPTS
	if failed == 0:
		return McpTool.text("\n".join(PackedStringArray([header, "Everything parses fine."]) + notes))
	return McpTool.text(header + "\n" + "\n".join(lines))


## Verificación al terminar un turno (m11-04): valida los .gd del proyecto modificados desde
## `since_unix`, y si cambió algún .cs, compila el C# (m14-07). "" si no cambió ninguno, todos
## están bien o el validador no pudo correr; si no, los errores por archivo.
func verify_changed_scripts(since_unix: int) -> String:
	var changed := scripts_modified_since("res://", since_unix)
	var paths := PackedStringArray(Array(changed).filter(func(path: String) -> bool: return path.ends_with(".gd")))
	var csharp := PackedStringArray(Array(changed).filter(func(path: String) -> bool: return path.ends_with(".cs")))
	var lines: PackedStringArray = []
	if not paths.is_empty():
		var report: Dictionary = await check_scripts(paths.slice(0, MAX_SCRIPTS))
		if report.error.is_empty():
			lines.append_array(failure_lines(paths.slice(0, MAX_SCRIPTS), report))
	var csproj := CsharpBuild.find_project(project_path)
	if not csharp.is_empty() and not csproj.is_empty():
		var build: Dictionary = await CsharpBuild.build(csproj)
		if build.error.is_empty():
			# Todos los errores del build: un .cs cambiado puede romper a otro que no se tocó.
			lines.append_array(failure_lines(PackedStringArray(build.results.keys()), build))
	return "\n".join(lines)


## Los `.gd` y `.cs` bajo `root` modificados desde `since_unix`. Recorre el disco y no el EditorFileSystem:
## un script que el agente creó desde la shell todavía puede no estar escaneado. Saltea carpetas
## ocultas (.godot, .git) y las que tienen .gdignore.
static func scripts_modified_since(root: String, since_unix: int) -> PackedStringArray:
	var result: PackedStringArray = []
	if FileAccess.file_exists(root.path_join(".gdignore")):
		return result
	for file: String in DirAccess.get_files_at(root):
		var path := root.path_join(file)
		if (file.ends_with(".gd") or file.ends_with(".cs")) and FileAccess.get_modified_time(path) >= since_unix:
			result.append(path)
	for dir: String in DirAccess.get_directories_at(root):
		if not dir.begins_with("."):
			result.append_array(scripts_modified_since(root.path_join(dir), since_unix))
	return result


## Una línea «✗ ruta» por script que no parsea, con sus errores debajo.
static func failure_lines(paths: PackedStringArray, report: Dictionary) -> PackedStringArray:
	var lines: PackedStringArray = []
	for path: String in paths:
		var result: Dictionary = report.results.get(path, {"ok": false, "errors": []})
		if result.ok and result.errors.is_empty():
			continue
		lines.append("✗ %s" % path)
		for error: String in result.errors:
			lines.append("  " + error)
		if result.errors.is_empty():
			lines.append("  could not be loaded (no details)")
	return lines


## Corre el checker en un proceso aparte. Devuelve `{error, results: {path: {ok, errors[]}}}`.
func check_scripts(paths: PackedStringArray) -> Dictionary:
	var process := AgentProcess.new()
	var stderr_lines: PackedStringArray = []
	var state := {"exited": false}
	process.stderr_received.connect(func(line: String) -> void: stderr_lines.append(line))
	process.line_received.connect(func(line: String) -> void: stderr_lines.append(line))
	process.exited.connect(func(_code: int) -> void: state.exited = true)
	var args: PackedStringArray = ["--headless", "--no-header", "--path", project_path, "--script", CHECKER_SCRIPT, "--"]
	args.append_array(paths)
	if not process.start(OS.get_executable_path(), args):
		return {"error": "Could not launch the validator: %s" % process.last_error(), "results": {}}
	var tree := Engine.get_main_loop() as SceneTree
	var deadline := Time.get_ticks_msec() + int(CHECK_TIMEOUT_S * 1000.0)
	while not state.exited and Time.get_ticks_msec() < deadline:
		await tree.process_frame
	var timed_out: bool = not state.exited
	if not timed_out:
		await tree.create_timer(STDERR_GRACE_S).timeout
	process.stop()
	if timed_out:
		return {"error": "The validator did not finish within %d s." % int(CHECK_TIMEOUT_S), "results": {}}
	return {"error": "", "results": parse_checker_output(stderr_lines)}


## Salida del checker → `{path: {ok, errors: ["línea N: mensaje"]}}`.
static func parse_checker_output(lines: PackedStringArray) -> Dictionary:
	var ansi := RegEx.create_from_string("\\x1b\\[[0-9;]*m")
	var results: Dictionary = {}
	var current := ""
	var pending_message := ""
	for raw: String in lines:
		var line := ansi.sub(raw, "", true).strip_edges()
		if line.begins_with("@@BEGIN "):
			current = line.trim_prefix("@@BEGIN ")
			results[current] = {"ok": false, "errors": []}
			continue
		if line.begins_with("@@END "):
			var parts := line.split(" ", false, 2)
			if parts.size() == 3 and results.has(parts[2]):
				results[parts[2]].ok = parts[1] == "ok"
			current = ""
			pending_message = ""
			continue
		for prefix: String in ["SCRIPT ERROR:", "ERROR:"]:
			if line.begins_with(prefix):
				pending_message = line.trim_prefix(prefix).strip_edges()
				break
		if line.begins_with("at:") and not pending_message.is_empty():
			var location := ErrorCollector._parse_location(line)
			var file: String = location[0]
			if file.begins_with("res://") and not pending_message.begins_with("Failed to load script"):
				if not results.has(file):
					results[file] = {"ok": false, "errors": []}
				var entry := "line %d: %s" % [location[1], pending_message] if int(location[1]) > 0 else pending_message
				if not entry in results[file].errors:
					results[file].errors.append(entry)
			pending_message = ""
	return results


## Los scripts del proyecto, sin los del harness: no son del juego y son cientos (validarlos todos no
## entraba en el tiempo del validador).
func _collect_scripts(dir: EditorFileSystemDirectory, out: PackedStringArray) -> void:
	if dir == null or dir.get_path().begins_with(HARNESS_ADDON):
		return
	for i in dir.get_file_count():
		var path := dir.get_file_path(i)
		if path.ends_with(".gd") or path.ends_with(".cs"):
			out.append(path)
	for i in dir.get_subdir_count():
		_collect_scripts(dir.get_subdir(i), out)


func _capture_editor_viewport(args: Dictionary) -> Dictionary:
	var which := McpTool.str_arg(args, "which", "2d")
	var image := EditorContext.capture_viewport(which == "3d")
	if image == null:
		return McpTool.error("Could not capture the %s viewport (is the editor minimized, or was the tab never opened?)." % which.to_upper())
	return McpTool.image(image, "Editor %s viewport (%dx%d)" % [which.to_upper(), image.get_width(), image.get_height()])
