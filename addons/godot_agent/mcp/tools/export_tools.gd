@tool
extends RefCounted
## godot.export_project (m11-53): exporta el proyecto con un preset de export_presets.cfg, en un proceso
## aparte (`<binario del editor> --headless --path <proyecto> --export-debug|--export-release|--export-pack
## <preset> <archivo>`), y devuelve errores, duración y tamaño. El editor sigue andando mientras tanto.
## - El agente elige solo el preset, el modo y el nombre del archivo: el binario es el del editor
##   (OS.get_executable_path()) y no hay argumentos extra.
## - export_presets.cfg solo se lee (ConfigFile); nunca se escribe.
## - El archivo va a la carpeta de exports del harness (en la caché del editor, fuera del proyecto) o, si
##   se pide, a la ruta de export del preset, la que configuró el usuario. Nunca a una ruta elegida por
##   el agente: un export escribe un binario, y no tiene que poder pisar archivos de la máquina.
## - debug y release necesitan las plantillas de export de esta versión: si faltan, error claro antes de
##   lanzar. pack (.pck) no las necesita.

const McpTool := preload("../mcp_tool.gd")
const PermissionPolicy := preload("../../session/permission_policy.gd")
const AgentProcess := preload("../../transport/agent_process.gd")

const MODE_DEBUG := "debug"
const MODE_RELEASE := "release"
const MODE_PACK := "pack"
const MODES: PackedStringArray = [MODE_DEBUG, MODE_RELEASE, MODE_PACK]
const OUTPUT_PRESET := "preset"
const PRESETS_FILE := "export_presets.cfg"
const TIMEOUT_DEFAULT_S := 600
const TIMEOUT_MAX_S := 1800
## Líneas de error/aviso de la salida que entran en el informe.
const PROBLEM_LINES := 30
const LINE_CHARS := 300
## Extensión por plataforma, para el nombre del archivo cuando el preset no tiene ruta de export.
const EXTENSIONS := {"Linux": "x86_64", "Windows Desktop": "exe", "macOS": "zip", "Web": "html", "Android": "apk", "iOS": "ipa"}
const TEMPLATES_MISSING := "No export template found"

## Hooks de test: la carpeta del proyecto, la de plantillas y la de exports.
var project_dir := ""
var templates_dir := ""
var exports_dir := ""

var _running := false


func tools() -> Array:
	return [
		McpTool.create("export_project", PermissionPolicy.GROUP_PROJECT,
			"Export the project with one of its export presets (export_presets.cfg) in a separate headless Godot, the editor's own binary, and report errors, time and the size of what it wrote. `debug` and `release` need this Godot version's export templates (Editor → Manage Export Templates); `pack` writes only the .pck and needs none, a quick \"does it export?\" check. The file goes to the harness's exports folder outside the project (named after the preset's export path), or with output=\"preset\" to the preset's own export path. export_presets.cfg is never changed.",
			{
				"preset": {"type": "string", "description": "Name of the export preset, as in Project → Export"},
				"mode": {"type": "string", "enum": Array(MODES), "description": "debug (default), release, or pack (.pck only, no templates needed)"},
				"output": {"type": "string", "description": "File name inside the harness's exports folder (default: the file name of the preset's export path), or \"preset\" to write to the preset's export path"},
				"timeout_s": {"type": "integer", "description": "Stop the export after this many seconds (default %d, at most %d)" % [TIMEOUT_DEFAULT_S, TIMEOUT_MAX_S]},
			}, ["preset"], _export_project),
	]


func _export_project(args: Dictionary) -> Dictionary:
	if _running:
		return McpTool.error("An export is already running: wait for it to finish.")
	var plan := prepare(args)
	if plan.has("error"):
		return McpTool.error(plan.error)
	_running = true
	var ran: Dictionary = await _run(plan)
	_running = false
	return McpTool.error(ran.text) if ran.failed else McpTool.text(ran.text)


## Lo que se va a correr: `{program, args, output, preset, mode, timeout_s}` o `{error}`.
func prepare(args: Dictionary) -> Dictionary:
	var name := McpTool.str_arg(args, "preset").strip_edges()
	var mode := McpTool.str_arg(args, "mode", MODE_DEBUG)
	if not mode in MODES:
		return {"error": "`mode` must be one of: %s." % ", ".join(MODES)}
	var project := _project_dir()
	var presets := read_presets(project.path_join(PRESETS_FILE))
	if presets.is_empty():
		return {"error": "The project has no export presets (%s). Add one in Project → Export." % PRESETS_FILE}
	var preset := {}
	for item: Dictionary in presets:
		if item.name == name:
			preset = item
	if preset.is_empty():
		return {"error": "There is no export preset «%s». The presets are: %s." % [name, ", ".join(presets.map(func(item: Dictionary) -> String: return "«%s»" % item.name))]}
	if mode != MODE_PACK:
		var missing := missing_templates(_templates_dir())
		if not missing.is_empty():
			return {"error": missing}
	var output := output_path(preset, mode, McpTool.str_arg(args, "output").strip_edges(), project, _exports_dir())
	if output.has("error"):
		return output
	var timeout_s := clampi(McpTool.int_arg(args, "timeout_s", TIMEOUT_DEFAULT_S), 10, TIMEOUT_MAX_S)
	return {"program": OS.get_executable_path(), "args": process_args(project, mode, name, str(output.path)),
		"output": output.path, "preset": preset, "mode": mode, "timeout_s": timeout_s}


## Los presets de export_presets.cfg: `[{name, platform, export_path}]`, en el orden del archivo.
static func read_presets(path: String) -> Array[Dictionary]:
	var presets: Array[Dictionary] = []
	var config := ConfigFile.new()
	if not FileAccess.file_exists(path) or config.load(path) != OK:
		return presets
	for section: String in config.get_sections():
		if section.begins_with("preset.") and section.count(".") == 1:
			presets.append({"name": str(config.get_value(section, "name", "")), "platform": str(config.get_value(section, "platform", "")),
				"export_path": str(config.get_value(section, "export_path", ""))})
	return presets


## Los argumentos del proceso: nada que venga del agente salvo el nombre del preset, que va como un
## argumento solo (sin shell).
static func process_args(project: String, mode: String, preset: String, output: String) -> PackedStringArray:
	var flag: String = {MODE_DEBUG: "--export-debug", MODE_RELEASE: "--export-release", MODE_PACK: "--export-pack"}[mode]
	return PackedStringArray(["--headless", "--path", project, flag, preset, output])


## La carpeta de las plantillas de esta versión («4.7.2.stable», «4.8.beta2»; «.mono» con C#).
static func templates_version() -> String:
	var info := Engine.get_version_info()
	var version := "%d.%d" % [info.major, info.minor]
	if int(info.patch) > 0:
		version += ".%d" % info.patch
	version += ".%s" % info.status
	if ClassDB.class_exists(&"CSharpScript"):
		version += ".mono"
	return version


## "" si las plantillas de esta versión están; si no, el error para el agente.
static func missing_templates(dir: String) -> String:
	if DirAccess.dir_exists_absolute(dir) and not DirAccess.get_files_at(dir).is_empty():
		return ""
	return "The export templates for Godot %s are not installed (expected in %s). Install them from Editor → Manage Export Templates, or use mode=\"pack\", which exports only the .pck and needs no templates." % [templates_version(), dir]


## `{path}` o `{error}`. Sin `output`: el nombre del archivo de la ruta del preset, en la carpeta de
## exports. "preset": la ruta del preset (relativa al proyecto, como la guarda el editor).
static func output_path(preset: Dictionary, mode: String, output: String, project: String, exports: String) -> Dictionary:
	var preset_path := str(preset.export_path)
	if output == OUTPUT_PRESET:
		if preset_path.is_empty():
			return {"error": "The preset «%s» has no export path: set it in Project → Export, or leave `output` empty to use the harness's exports folder." % preset.name}
		var absolute := preset_path if preset_path.is_absolute_path() else project.path_join(preset_path)
		return {"path": _with_pack_extension(absolute.simplify_path(), mode)}
	var file := output
	if file.is_empty():
		file = preset_path.get_file()
		if file.is_empty():
			var extension := str(EXTENSIONS.get(preset.platform, "bin"))
			file = "%s.%s" % [_safe_name(str(preset.name)), extension]
	if file.is_absolute_path() or file.begins_with("res://") or file.begins_with("user://") or ".." in file.replace("\\", "/").split("/"):
		return {"error": "`output` is a file name inside the harness's exports folder (%s), or \"preset\" for the preset's export path; not a path of its own." % exports}
	var folder := exports.path_join(_safe_name(str(preset.name)))
	return {"path": _with_pack_extension(folder.path_join(file).simplify_path(), mode)}


static func _with_pack_extension(path: String, mode: String) -> String:
	if mode == MODE_PACK and not path.get_extension() in ["pck", "zip"]:
		return path.get_basename() + ".pck"
	return path


static func _safe_name(text: String) -> String:
	var safe := ""
	for character in text:
		safe += character if character.is_valid_identifier() or character.is_valid_int() or character in "-." else "_"
	return safe if not safe.is_empty() else "preset"


## Las líneas con ERROR o WARNING de la salida, hasta PROBLEM_LINES.
static func problems(lines: PackedStringArray) -> PackedStringArray:
	var found: PackedStringArray = []
	for line: String in lines:
		var clean := line.strip_edges()
		if clean.begins_with("ERROR") or clean.begins_with("WARNING") or clean.begins_with("SCRIPT ERROR") or clean.contains(TEMPLATES_MISSING):
			found.append(clean.left(LINE_CHARS))
			if found.size() >= PROBLEM_LINES:
				break
	return found


## Ruta → bytes de lo que escribió el export: el archivo y los que deja al lado con el mismo nombre
## (.pck, .wasm, .so…), o todo lo de adentro si es una carpeta.
static func written_files(output: String, since_unix: int) -> Dictionary:
	var sizes := {}
	if DirAccess.dir_exists_absolute(output):
		for file: String in DirAccess.get_files_at(output):
			sizes[output.path_join(file)] = _size(output.path_join(file))
		return sizes
	var dir := output.get_base_dir()
	var stem := output.get_file().get_basename()
	if not DirAccess.dir_exists_absolute(dir):
		return sizes
	for file: String in DirAccess.get_files_at(dir):
		var path := dir.path_join(file)
		if (file == output.get_file() or file.get_basename() == stem) and FileAccess.get_modified_time(path) >= since_unix:
			sizes[path] = _size(path)
	return sizes


static func _size(path: String) -> int:
	var file := FileAccess.open(path, FileAccess.READ)
	return file.get_length() if file else 0


static func format_size(bytes: int) -> String:
	if bytes >= 1024 * 1024:
		return "%.1f MB" % (bytes / 1048576.0)
	if bytes >= 1024:
		return "%.1f KB" % (bytes / 1024.0)
	return "%d B" % bytes


func _run(plan: Dictionary) -> Dictionary:
	var output := str(plan.output)
	DirAccess.make_dir_recursive_absolute(output.get_base_dir())
	var started_unix := int(Time.get_unix_time_from_system()) - 1
	var started := Time.get_ticks_msec()
	var process := AgentProcess.new()
	var lines: PackedStringArray = []
	var state := {"exited": false, "code": 0}
	process.line_received.connect(func(line: String) -> void: lines.append(line))
	process.stderr_received.connect(func(line: String) -> void: lines.append(line))
	process.exited.connect(func(code: int) -> void:
		state.exited = true
		state.code = code)
	if not process.start(str(plan.program), plan.args):
		return {"failed": true, "text": "Could not start the export: %s" % process.last_error()}
	var tree := Engine.get_main_loop() as SceneTree
	var deadline := started + int(plan.timeout_s) * 1000
	while not state.exited and Time.get_ticks_msec() < deadline:
		await tree.process_frame
	var timed_out: bool = not state.exited
	if not timed_out:
		await tree.create_timer(0.2).timeout  # lo último de los pipes
	process.stop()
	var seconds := (Time.get_ticks_msec() - started) / 1000.0
	var found := problems(lines)
	var header := "Export «%s» (%s) " % [plan.preset.name, plan.mode]
	if timed_out:
		return {"failed": true, "text": header + "stopped after %d s.%s" % [plan.timeout_s, _problems_text(found)]}
	if Array(found).any(func(line: String) -> bool: return line.contains(TEMPLATES_MISSING)):
		return {"failed": true, "text": header + "failed: " + missing_templates(_templates_dir()) + _problems_text(found)}
	var sizes := written_files(output, started_unix)
	if int(state.code) != 0 or sizes.is_empty():
		return {"failed": true, "text": header + "failed (exit code %d, %.1f s).%s" % [int(state.code), seconds, _problems_text(found if not found.is_empty() else lines.slice(maxi(0, lines.size() - 10)))]}
	var total := 0
	var listing: PackedStringArray = []
	for path: String in sizes:
		total += int(sizes[path])
		listing.append("- %s (%s)" % [path, format_size(int(sizes[path]))])
	return {"failed": false, "text": header + "done in %.1f s: %s in total.\n%s%s" % [seconds, format_size(total), "\n".join(listing), _problems_text(found)]}


static func _problems_text(found: PackedStringArray) -> String:
	if found.is_empty():
		return ""
	return "\nOutput:\n" + "\n".join(Array(found).map(func(line: String) -> String: return "  " + line.left(LINE_CHARS)))


func _project_dir() -> String:
	return project_dir if not project_dir.is_empty() else ProjectSettings.globalize_path("res://").trim_suffix("/")


func _templates_dir() -> String:
	if not templates_dir.is_empty():
		return templates_dir
	return EditorInterface.get_editor_paths().get_data_dir().path_join("export_templates").path_join(templates_version())


func _exports_dir() -> String:
	if not exports_dir.is_empty():
		return exports_dir
	var project := _project_dir()
	return EditorInterface.get_editor_paths().get_cache_dir().path_join("godot_agent_exports").path_join("%s-%s" % [_safe_name(project.get_file()), project.md5_text().left(8)])
