@tool
extends RefCounted
## Compilar el C# del proyecto con `dotnet build` (m14-07): lo que para GDScript hace el checker de
## scripts. Los errores salen como `ruta(línea,col): error CS0103: mensaje [proyecto.csproj]`.

const AgentProcess := preload("../transport/agent_process.gd")
const CommandResolver := preload("../transport/command_resolver.gd")

const BUILD_TIMEOUT_S := 180.0
## Margen para que lleguen las últimas líneas después del exit.
const OUTPUT_GRACE_S := 0.3


## El `.csproj` de la raíz del proyecto (el que crea «Crear solución de C#»), o "".
static func find_project(project_dir: String) -> String:
	for file: String in DirAccess.get_files_at(project_dir):
		if file.get_extension() == "csproj":
			return project_dir.path_join(file)
	return ""


## Compila `csproj` y devuelve `{error, results: {res_path: {ok, errors: ["line N: CSxxxx mensaje"]}}}`
## (solo los archivos con problemas; los warnings no cuentan como error).
static func build(csproj: String) -> Dictionary:
	var dotnet := CommandResolver.resolve("dotnet")
	if dotnet.is_empty():
		return {"error": "The .NET SDK (dotnet) is not installed or not on the PATH: C# scripts can't be checked.", "results": {}}
	var process := AgentProcess.new()
	var lines: PackedStringArray = []
	var state := {"exited": false, "code": 0}
	process.line_received.connect(func(line: String) -> void: lines.append(line))
	process.stderr_received.connect(func(line: String) -> void: lines.append(line))
	process.exited.connect(func(code: int) -> void:
		state.exited = true
		state.code = code)
	# En inglés: el agente lee los mensajes del compilador.
	var env := {"DOTNET_CLI_UI_LANGUAGE": "en", "DOTNET_NOLOGO": "1", "DOTNET_CLI_TELEMETRY_OPTOUT": "1"}
	if not process.start(dotnet, PackedStringArray(["build", csproj, "-nologo", "-v", "q", "-clp:NoSummary"]), env):
		return {"error": "Could not run dotnet: %s" % process.last_error(), "results": {}}
	var tree := Engine.get_main_loop() as SceneTree
	var deadline := Time.get_ticks_msec() + int(BUILD_TIMEOUT_S * 1000.0)
	while not state.exited and Time.get_ticks_msec() < deadline:
		await tree.process_frame
	if not state.exited:
		process.stop()
		return {"error": "dotnet build did not finish within %d s." % int(BUILD_TIMEOUT_S), "results": {}}
	await tree.create_timer(OUTPUT_GRACE_S).timeout
	process.stop()
	var results := parse_build_output(lines)
	if int(state.code) != 0 and results.is_empty():
		return {"error": "dotnet build failed without file errors:\n%s" % "\n".join(lines.slice(-10)), "results": {}}
	return {"error": "", "results": results}


## Las líneas de error de MSBuild → `{res_path: {ok: false, errors: [...]}}`. Las rutas fuera del
## proyecto quedan absolutas.
static func parse_build_output(lines: PackedStringArray) -> Dictionary:
	var pattern := RegEx.create_from_string("^(.+?)\\((\\d+),(\\d+)\\): error (\\w+): (.*?)(?: \\[[^\\]]*\\])?$")
	var results: Dictionary = {}
	for raw: String in lines:
		var found := pattern.search(raw.strip_edges())
		if found == null:
			continue
		var path := ProjectSettings.localize_path(found.get_string(1))
		if not results.has(path):
			results[path] = {"ok": false, "errors": []}
		var entry := "line %s: %s %s" % [found.get_string(2), found.get_string(4), found.get_string(5)]
		if not entry in results[path].errors:
			results[path].errors.append(entry)
	return results
