@tool
extends RefCounted
## Tools de diagnóstico (spec §6): get_errors, validate_scripts y capture_editor_viewport.

const McpTool := preload("../mcp_tool.gd")
const ErrorCollector := preload("../../core/error_collector.gd")
const AgentProcess := preload("../../transport/agent_process.gd")
const EditorContext := preload("../../ui/editor_context.gd")
const PermissionPolicy := preload("../../session/permission_policy.gd")

const CHECKER_SCRIPT := "res://addons/godot_agent/mcp/tools/script_checker.gd"
const MAX_SCRIPTS := 400
const CHECK_TIMEOUT_S := 60.0
## Margen para que lleguen las últimas líneas de stderr después del exit.
const STDERR_GRACE_S := 0.3
const ERROR_LIMIT := 200

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
			"Parses GDScript scripts in a separate process and returns the errors by file and line. Without `paths`, all the project's .gd files.",
			{"paths": {"type": "array", "items": {"type": "string"}, "description": "res://…gd paths"}},
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
			if not text.begins_with("res://") or not text.ends_with(".gd"):
				return McpTool.error("'%s' is not a res://…gd path." % text)
			if not FileAccess.file_exists(text):
				return McpTool.error("%s does not exist." % text)
			paths.append(text)
	else:
		_collect_scripts(EditorInterface.get_resource_filesystem().get_filesystem(), paths)
	if paths.is_empty():
		return McpTool.text("There are no .gd scripts to validate.")
	var truncated := paths.size() > MAX_SCRIPTS
	if truncated:
		paths = paths.slice(0, MAX_SCRIPTS)
	var report: Dictionary = await check_scripts(paths)
	if not report.error.is_empty():
		return McpTool.error(report.error)
	var lines: PackedStringArray = []
	var failed := 0
	for path: String in paths:
		var result: Dictionary = report.results.get(path, {"ok": false, "errors": []})
		if result.ok and result.errors.is_empty():
			continue
		failed += 1
		lines.append("✗ %s" % path)
		for error: String in result.errors:
			lines.append("  " + error)
		if result.errors.is_empty():
			lines.append("  could not be loaded (no details)")
	var header := "%d scripts validated · %d with errors" % [paths.size(), failed]
	if truncated:
		header += " (validated the first %d; pass `paths` for the rest)" % MAX_SCRIPTS
	if failed == 0:
		return McpTool.text(header + "\nEverything parses fine.")
	return McpTool.text(header + "\n" + "\n".join(lines))


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


func _collect_scripts(dir: EditorFileSystemDirectory, out: PackedStringArray) -> void:
	if dir == null:
		return
	for i in dir.get_file_count():
		var path := dir.get_file_path(i)
		if path.ends_with(".gd"):
			out.append(path)
	for i in dir.get_subdir_count():
		_collect_scripts(dir.get_subdir(i), out)


func _capture_editor_viewport(args: Dictionary) -> Dictionary:
	var which := McpTool.str_arg(args, "which", "2d")
	var image := EditorContext.capture_viewport(which == "3d")
	if image == null:
		return McpTool.error("Could not capture the %s viewport (is the editor minimized, or was the tab never opened?)." % which.to_upper())
	return McpTool.image(image, "Editor %s viewport (%dx%d)" % [which.to_upper(), image.get_width(), image.get_height()])
