@tool
extends RefCounted
## Tools de diagnóstico (spec §6): get_errors, validate_scripts, capture_editor_viewport y
## build_extension, test_extension, install_extension y restart_editor. Los .cs se validan compilando el proyecto con dotnet (m14-07); la GDExtension se
## compila con build_extension (m19-01), se prueba en un Godot aparte con test_extension (m19-02) y
## se lleva al juego con install_extension (m19-05), que la deja preparada para el próximo reinicio.

const McpTool := preload("../mcp_tool.gd")
const UntrustedText := preload("../untrusted_text.gd")
const ErrorCollector := preload("../../editor/error_collector.gd")
const AgentProcess := preload("../../transport/agent_process.gd")
const EditorContext := preload("../../ui/editor_context.gd")
const PermissionPolicy := preload("../../session/permission_policy.gd")
const CsharpBuild := preload("../../core/csharp_build.gd")
const NativeBuild := preload("../../core/native_build.gd")
const NativeTest := preload("../../core/native_test.gd")
const SupervisorClient := preload("../../supervisor/supervisor_client.gd")
const NativeInstall := preload("../../core/native_install.gd")
const ExtensionSnapshot := preload("../../supervisor/extension_snapshot.gd")

const CHECKER_SCRIPT := "res://addons/godot_agent/mcp/tools/script_checker.gd"
const MAX_SCRIPTS := 400
const CHECK_TIMEOUT_S := 60.0
## Margen para que lleguen las últimas líneas de stderr después del exit.
const STDERR_GRACE_S := 0.3
const ERROR_LIMIT := 200
const HARNESS_ADDON := "res://addons/godot_agent"
## Plataformas sin compilar que nombra install_extension (godot-cpp-template trae 20).
const NOT_BUILT_SHOWN := 6

var errors: ErrorCollector
## Callable(supervise: bool) -> String: reinicia el editor un momento después (lo pone el plugin).
var restarter: Callable
var project_path: String = ""
## `(test_dir, options) -> Dictionary` con el reporte de NativeTest.run (los tests lo reemplazan).
var extension_tester: Callable = NativeTest.run


func setup(collector: ErrorCollector, project_dir: String) -> void:
	errors = collector
	project_path = project_dir


func tools() -> Array:
	var diagnostics := PermissionPolicy.GROUP_DIAGNOSTICS
	return [
		McpTool.enveloped(McpTool.create("get_errors", diagnostics,
			"Errors and warnings from the editor (scripts, Output) and from the game (Debugger) since a mark. Returns the current mark: pass it as `since` next time to see only what is new.",
			{"since": {"type": "integer", "description": "Mark returned by a previous call (default 0: everything stored)"}},
			[], _get_errors), McpTool.ENVELOPE_PARTS),
		McpTool.create("validate_scripts", diagnostics,
			"Parses GDScript scripts in a separate process and compiles C# with dotnet build, and returns the errors by file and line. Without `paths`, all the project's .gd files (and its C#, if it has a .csproj).",
			{"paths": {"type": "array", "items": {"type": "string"}, "description": "res://…gd or res://…cs paths"}},
			[], _validate_scripts),
		McpTool.create("capture_editor_viewport", diagnostics,
			"Captures the editor's 2D or 3D viewport as a PNG.",
			{"which": {"type": "string", "enum": ["2d", "3d"], "description": "Viewport to capture"}},
			["which"], _capture_editor_viewport),
		_build_extension_tool(),
		McpTool.create("test_extension", PermissionPolicy.GROUP_RUN,
			"Tests the project's GDExtension in a separate headless Godot, never in this editor: a crash there kills only the test process. Runs the test_*.gd files of `tests` (methods test_*(t) that call t.check(condition, \"what\"), the format of the gdextension-cpp skill) and checks that `classes` are registered. Returns the failed checks, the load errors and, after a crash, the backtrace with the extension's frames turned into functions and lines when the build has debug symbols. The test project is found like build_extension's build system: project/ or demo/ next to the SConstruct, godot/ next to rust/, or this project.",
			{
				"project": {"type": "string", "description": "Folder of the Godot project to test with (absolute or res://), when it isn't found by itself"},
				"tests": {"type": "string", "description": "res:// folder of the test project with the test_*.gd files (default res://tests). Without it, only checks that the extension and `classes` load."},
				"classes": {"type": "array", "items": {"type": "string"}, "description": "Classes the extension must register"},
				"timeout_s": {"type": "integer", "description": "Default %d, at most %d" % [NativeTest.DEFAULT_TIMEOUT_S, NativeTest.MAX_TIMEOUT_S]},
			},
			[], _test_extension),
		McpTool.create("install_extension", PermissionPolicy.GROUP_PROJECT,
			"Brings the tested GDExtension from its test project into this game as an addon (res://addons/<name>/ by default, or where the game already has a .gdextension with that name). Runs the same tests as test_extension first and installs only if they pass, rewrites the res:// paths of the .gdextension to the new folder and checks it against the libraries (entry_symbol, compatibility_minimum, a debug library this editor can load, missing files). Nothing changes in the open editor: the files are staged and enter the game when the editor restarts, so call restart_editor next.",
			{
				"project": {"type": "string", "description": "Folder of the test project (absolute or res://), when it isn't found by itself"},
				"gdextension": {"type": "string", "description": "res:// path of the .gdextension in the test project, when it has more than one"},
				"target": {"type": "string", "description": "res:// folder of this game to install into (default res://addons/<name>/, or the folder that already has it)"},
				"tests": {"type": "string", "description": "Like test_extension's `tests` (default res://tests)"},
				"classes": {"type": "array", "items": {"type": "string"}, "description": "Classes the extension must register"},
				"timeout_s": {"type": "integer", "description": "Default %d, at most %d" % [NativeTest.DEFAULT_TIMEOUT_S, NativeTest.MAX_TIMEOUT_S]},
			},
			[], _install_extension),
		McpTool.create("restart_editor", PermissionPolicy.GROUP_PROJECT,
			"Saves the scenes and restarts the editor, so it loads the GDExtension libraries that are on disk now and the ones install_extension staged. Run test_extension first: a build that crashes takes the editor down with it. Under the crash supervisor (`supervise`, default true), a build that crashes the editor while starting is rolled back to the last one that started fine (or disabled, when it has none), the editor reopens and this session continues with a message that says what happened, with the backtrace. Without it, a crashing build leaves the editor down until the user fixes it. Your session ends with the restart and comes back by itself.",
			{"supervise": {"type": "boolean", "description": "Restart under the crash supervisor (default true). Ignored when the editor already runs under it."}},
			[], _restart_editor),
	]


## Asks like a shell command: SConstruct is Python and build.rs is Rust, so a build runs code.
func _build_extension_tool() -> McpTool:
	var tool := McpTool.create("build_extension", PermissionPolicy.GROUP_SHELL,
		"Builds the project's GDExtension with SCons or CMake (godot-cpp) or Cargo (gdext) and returns the compiler errors by file and line. Looks for SConstruct, CMakeLists.txt or Cargo.toml in the project folder, the folder above it (godot-cpp-template opens `project/`) and a `rust/` folder in either. The first godot-cpp build takes minutes; later ones, seconds. It doesn't load the build: this editor keeps the library it started with, and a crash in a new build would take the editor down with it. Test a new build in a separate headless Godot and tell the user when to restart the editor.",
		{
			"target": {"type": "string", "enum": Array(NativeBuild.TARGETS), "description": "godot-cpp target (default template_debug, which the editor and debug exports load). With Cargo, template_release builds with --release."},
			"args": {"type": "array", "items": {"type": "string"}, "description": "Extra arguments for scons, the CMake configure step or cargo build (for example `platform=windows`, `use_mingw=yes`, `debug_symbols=yes`)"},
			"root": {"type": "string", "description": "Folder with the SConstruct, CMakeLists.txt or Cargo.toml, absolute or res://, when it isn't found by itself"},
		},
		[], _build_extension)
	tool.describer = func(args: Dictionary) -> String:
		var project := _native_project(args)
		if project.is_empty():
			return "Build the GDExtension (no build system found)"
		var lines: PackedStringArray = []
		for step: PackedStringArray in NativeBuild.commands(project, _native_target(args), _native_args(args)):
			lines.append(" ".join(step))
		return "\n".join(lines)
	return tool


func _native_project(args: Dictionary) -> Dictionary:
	var root := str(args.get("root", "")).strip_edges()
	if root.is_empty():
		return NativeBuild.find_project(project_path)
	return NativeBuild.detect(ProjectSettings.globalize_path(root).simplify_path())


## El proyecto de prueba: `project` o el que se encuentra solo. `{dir}` o `{error}`.
func _test_project(args: Dictionary) -> Dictionary:
	var requested := str(args.get("project", "")).strip_edges()
	if requested.is_empty():
		var found := NativeTest.find_test_project(NativeBuild.find_project(project_path), project_path)
		return {"dir": found} if not found.is_empty() else {"error": "No Godot project to test with. Pass `project`."}
	var dir := ProjectSettings.globalize_path(requested).simplify_path()
	if not FileAccess.file_exists(dir.path_join("project.godot")):
		return {"error": "%s has no project.godot." % requested}
	return {"dir": dir}


func _test_options(args: Dictionary, test_dir: String) -> Dictionary:
	var classes: PackedStringArray = []
	if args.get("classes") is Array:
		for value: Variant in args.classes:
			classes.append(str(value))
	return {
		"tests": McpTool.str_arg(args, "tests") if not McpTool.str_arg(args, "tests").is_empty() else "res://tests",
		"classes": classes,
		"timeout_s": McpTool.int_arg(args, "timeout_s", NativeTest.DEFAULT_TIMEOUT_S),
		# El import escribe .godot/: nunca en el proyecto que tiene abierto el editor.
		"import": not NativeTest.same_dir(test_dir, project_path),
	}


func _summary_dirs(test_dir: String) -> PackedStringArray:
	var dirs := PackedStringArray([test_dir])
	var native := NativeBuild.find_project(project_path)
	if not native.is_empty():
		dirs.append(native.root)
	return dirs


func _test_extension(args: Dictionary) -> Dictionary:
	var found := _test_project(args)
	if found.has("error"):
		return McpTool.error(found.error)
	var test_dir: String = found.dir
	var is_open := NativeTest.same_dir(test_dir, project_path)
	var report: Dictionary = await extension_tester.call(test_dir, _test_options(args, test_dir))
	if not report.error.is_empty():
		return McpTool.error(report.error)
	var text := NativeTest.summarize(report, test_dir, _summary_dirs(test_dir))
	if is_open and not (report.unregistered as PackedStringArray).is_empty():
		text += "\nThis is the project open in the editor: the editor registers a new .gdextension, and loads it, when it scans the files. Test new extensions in their own test project."
	if report.code == 0 and not report.crashed:
		return McpTool.text(text)
	return {"content": [{"type": "text", "text": text}], "isError": true}


func _install_extension(args: Dictionary) -> Dictionary:
	var found := _test_project(args)
	if found.has("error"):
		return McpTool.error(found.error)
	var test_dir: String = found.dir
	if NativeTest.same_dir(test_dir, project_path):
		return McpTool.error("The test project is this project, so the extension is already here: there is nothing to install. Pass `project` with the extension's own test project (project/ or demo/ next to the SConstruct).")
	var gdextension := McpTool.str_arg(args, "gdextension")
	if gdextension.is_empty():
		var picked := NativeInstall.pick_gdextension(test_dir)
		if not str(picked.error).is_empty():
			return McpTool.error(picked.error)
		gdextension = picked.path
	var planned := NativeInstall.plan(test_dir, gdextension, project_path, McpTool.str_arg(args, "target"))
	if not str(planned.error).is_empty():
		return McpTool.error(planned.error)
	var report: Dictionary = await extension_tester.call(test_dir, _test_options(args, test_dir))
	if not report.error.is_empty():
		return McpTool.error("Not installed: the tests could not run. %s" % report.error)
	var summary := NativeTest.summarize(report, test_dir, _summary_dirs(test_dir))
	if report.code != 0 or report.crashed or report.timed_out:
		return {"content": [{"type": "text", "text": "Not installed: the tests didn't pass.\n" + summary}], "isError": true}
	var state_dir := SupervisorClient.State.state_dir(project_path)
	var previous := NativeInstall.pending_info(state_dir)
	var staged := NativeInstall.stage(planned, state_dir)
	if not staged.is_empty():
		return McpTool.error("Not installed: %s" % staged)
	var checked := NativeInstall.check_staged(planned, state_dir)
	var lines: PackedStringArray = [summary, ""]
	if not (checked.problems as PackedStringArray).is_empty():
		NativeInstall.discard_pending(state_dir)
		lines.append("Not installed: the .gdextension as it would be in %s has problems:" % planned.target)
		for problem: String in checked.problems:
			lines.append("✗ " + problem)
		return {"content": [{"type": "text", "text": "\n".join(lines)}], "isError": true}
	lines.append("Staged %d files from %s (test project) for %s:" % [planned.files.size(), planned.source, planned.target])
	if not previous.is_empty():
		lines.append("(This replaces the install staged before, of %s: only one is staged at a time.)" % NativeInstall.pending_names(previous))
	for file: Dictionary in planned.files:
		lines.append("  res://" + str(file.to))
	if not (checked.warnings as PackedStringArray).is_empty():
		lines.append("To fix before shipping (the editor loads it anyway):")
		for warning: String in checked.warnings:
			lines.append("  ! " + warning)
	if not (checked.not_built as PackedStringArray).is_empty():
		var not_built: PackedStringArray = checked.not_built
		var listed := ", ".join(not_built.slice(0, NOT_BUILT_SHOWN)) + (" and %d more" % (not_built.size() - NOT_BUILT_SHOWN) if not_built.size() > NOT_BUILT_SHOWN else "")
		lines.append("Not built yet (no library for any of their keys, so they don't load there): %s." % listed)
	if planned.new_extension:
		lines.append("The game doesn't have this extension yet: after the restart the editor registers and loads it.")
	else:
		lines.append("It replaces the copy the game has at %s." % planned.replaces)
	lines.append("Nothing changed in the open editor. The files enter the game when the editor restarts: call restart_editor. " + _crash_note(planned, state_dir))
	return McpTool.text("\n".join(lines))


## Qué pasa si la build instalada crashea el editor al arrancar, según lo que el supervisor tiene
## guardado (good/): no promete volver atrás si no hay a qué.
func _crash_note(planned: Dictionary, state_dir: String) -> String:
	var unsupervised := "Without it, a crash while starting leaves the editor down until the user fixes it."
	if planned.new_extension:
		return "If it crashes the editor while starting under the crash supervisor, the supervisor disables it (renames its .gdextension to .gdextension.disabled) and reopens the editor. " + unsupervised
	match ExtensionSnapshot.restorable(project_path, state_dir, str(planned.replaces).trim_prefix("res://")):
		"full":
			return "If it crashes the editor while starting under the crash supervisor, the supervisor goes back to the .gdextension and libraries that last started fine. " + unsupervised
		"libraries":
			return "If it crashes the editor while starting under the crash supervisor, the supervisor puts back the libraries that last started fine, but not the .gdextension (it has no copy of it yet: it saves one each time the editor starts fine under it). " + unsupervised
	return "The crash supervisor has no copy of the build the game has now (it saves one each time the editor starts fine under it), so if this one crashes the editor while starting it can't go back: it disables the extension (renames its .gdextension to .gdextension.disabled) and reopens the editor. " + unsupervised


func _restart_editor(args: Dictionary) -> Dictionary:
	if not restarter.is_valid():
		return McpTool.error("The editor can't be restarted from here.")
	var supervise: bool = args.get("supervise", true)
	var supervised := SupervisorClient.is_supervised()
	if supervise and not supervised and SupervisorClient.State.supervisor_running(SupervisorClient.state_dir()):
		return McpTool.error("A supervisor is already running for this project, but this editor isn't its own. Ask the user to close this editor; the supervisor reopens it.")
	var error := str(restarter.call(supervise))
	if not error.is_empty():
		return McpTool.error(error)
	var staged: Array = NativeInstall.pending(SupervisorClient.State.state_dir(project_path)).get("files", [])
	if not staged.is_empty():
		var note := "The %d files staged by install_extension enter the game with this restart." % staged.size()
		var result: Dictionary = _restart_result(supervise, supervised)
		result.content[0].text += " " + note
		return result
	return _restart_result(supervise, supervised)


func _restart_result(supervise: bool, supervised: bool) -> Dictionary:
	if supervised:
		return McpTool.text("Restarting under the crash supervisor in a second. Your session ends now and resumes when the editor is back.")
	if supervise:
		return McpTool.text("Restarting under the crash supervisor in a second (from now on it watches this editor). Your session ends now and resumes when the editor is back.")
	return McpTool.text("Restarting in a second, without the crash supervisor: if the new build crashes the editor while starting, it stays down. Your session ends now and resumes when the editor is back.")


func _native_target(args: Dictionary) -> String:
	var target := str(args.get("target", "template_debug"))
	return target if target in NativeBuild.TARGETS else "template_debug"


func _native_args(args: Dictionary) -> PackedStringArray:
	var extra: PackedStringArray = []
	if args.get("args") is Array:
		for value: Variant in args.args:
			extra.append(str(value))
	return extra


func _build_extension(args: Dictionary) -> Dictionary:
	var target := str(args.get("target", "template_debug"))
	if not target in NativeBuild.TARGETS:
		return McpTool.error("Unknown target '%s': use %s." % [target, ", ".join(NativeBuild.TARGETS)])
	var project := _native_project(args)
	if project.is_empty():
		if not str(args.get("root", "")).strip_edges().is_empty():
			return McpTool.error("%s has no SConstruct, CMakeLists.txt or Cargo.toml." % args.root)
		return McpTool.error("No SConstruct, CMakeLists.txt or Cargo.toml in the project folder, the folder above it or a rust/ folder. Pass `root`.")
	var report: Dictionary = await NativeBuild.build(project, target, _native_args(args))
	var header := "%s in %s:\n%s" % [project.kind, project.root, "\n".join(report.commands)]
	if not report.error.is_empty() and report.results.is_empty():
		return McpTool.error("%s\n\n%s" % [header, report.error])
	if report.results.is_empty():
		var built := "%s\nBuilt in %.1f s. Not loaded in this editor: test it with test_extension." % [header, report.seconds]
		var reloadable := NativeTest.reloadable_extensions(project_path)
		if not reloadable.is_empty():
			built += "\nWarning: %s in this project has `reloadable = true`, so this editor reloads its library when it changes, and a crash then takes the editor down. Run test_extension before the user switches back to the editor." % ", ".join(reloadable)
		return McpTool.text(built)
	var paths := PackedStringArray(report.results.keys())
	var lines := failure_lines(paths, report)
	return McpTool.text("%s\nBuild failed · %d files with errors\n%s" % [header, paths.size(), "\n".join(lines)])


func _get_errors(args: Dictionary) -> String:
	var since := McpTool.int_arg(args, "since", 0)
	var entries := errors.entries_since(since).filter(func(entry: Dictionary) -> bool: return not ErrorCollector.is_engine_noise(entry))
	var lines: PackedStringArray = []
	var shown := entries.slice(maxi(entries.size() - ERROR_LIMIT, 0))
	for entry: Dictionary in shown:
		lines.append(ErrorCollector.format_entry(entry))
	var header := "mark: %d · %d new since %d" % [errors.mark(), entries.size(), since]
	if shown.size() < entries.size():
		header += " (showing the last %d)" % shown.size()
	if entries.is_empty():
		return header + "\nNo new errors or warnings."
	return header + "\n" + UntrustedText.wrap("\n".join(lines))


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
