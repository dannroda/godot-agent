@tool
extends RefCounted
## Compilar la GDExtension del proyecto (m19-01): lo que csharp_build.gd hace para C#, con SCons o
## CMake (godot-cpp) o Cargo (gdext). Los errores salen por archivo y línea para que el agente se
## entere en la misma tool. Nunca carga la build: eso lo hace un Godot aparte (m19-02).

const AgentProcess := preload("../transport/agent_process.gd")
const CommandResolver := preload("../transport/command_resolver.gd")

const KIND_SCONS := "scons"
const KIND_CMAKE := "cmake"
const KIND_CARGO := "cargo"
## Archivo que identifica cada sistema, en orden de preferencia: un proyecto usa uno solo.
const MARKERS: Array = [["SConstruct", KIND_SCONS], ["CMakeLists.txt", KIND_CMAKE], ["Cargo.toml", KIND_CARGO]]
const TARGETS: PackedStringArray = ["template_debug", "template_release", "editor"]
## La primera build de godot-cpp genera y compila ~1100 archivos: 51 s con 32 hilos, varios minutos
## en una máquina chica. Las siguientes, segundos.
const BUILD_TIMEOUT_S := 1200.0
const OUTPUT_GRACE_S := 0.3
const TAIL_LINES := 20
const CMAKE_BUILD_DIR := "build"

## gcc, clang, rustc (--message-format=short): `ruta:línea[:col]: [fatal ]error[: o [E0425]:] mensaje`.
const _GNU_PATTERN := "^(.+?):(\\d+):(?:\\d+:)? (?:fatal )?error(?:\\[(\\w+)\\])?: (.*)$"
## MSVC: `ruta(línea[,col]): [fatal ]error C2065: mensaje`.
const _MSVC_PATTERN := "^(.+?)\\((\\d+)(?:,\\d+)?\\)\\s*: (?:fatal )?error (\\w+): (.*)$"


## El proyecto nativo de `project_dir`: `{kind, root, file}`, o {} si no hay. Mira la carpeta del
## proyecto y la de arriba (godot-cpp-template abre `project/` y tiene el SConstruct al lado), y en
## cada una `rust/` (el layout del libro de gdext: `godot/` y `rust/` hermanos).
static func find_project(project_dir: String) -> Dictionary:
	var base := project_dir.simplify_path()
	if base.ends_with("/"):
		base = base.left(-1)
	for dir: String in [base, base.path_join("rust"), base.get_base_dir(), base.get_base_dir().path_join("rust")]:
		var found := detect(dir)
		if not found.is_empty():
			return found
	return {}


## El sistema de build de `dir` exactamente (sin buscar arriba), o {}.
static func detect(dir: String) -> Dictionary:
	for marker: Array in MARKERS:
		var file: String = dir.path_join(marker[0])
		if FileAccess.file_exists(file):
			return {"kind": marker[1], "root": dir, "file": file}
	return {}


## Los comandos que corre `build` para `project` (para la tarjeta de permiso y el resultado):
## `[[ejecutable, args...], ...]`. El ejecutable va por nombre; `build` lo resuelve.
static func commands(project: Dictionary, target: String, extra: PackedStringArray) -> Array:
	var root: String = project.root
	match str(project.kind):
		KIND_SCONS:
			return [PackedStringArray(["scons", "-C", root, "target=" + target]) + extra]
		KIND_CMAKE:
			var build_dir := root.path_join(CMAKE_BUILD_DIR)
			# Se configura siempre: el target es una opción de configuración. El generador solo la
			# primera vez (cambiarlo en un build ya configurado es un error de CMake).
			var configure := PackedStringArray(["cmake", "-S", root, "-B", build_dir, "-DGODOTCPP_TARGET=" + target])
			if not FileAccess.file_exists(build_dir.path_join("CMakeCache.txt")) and not CommandResolver.resolve("ninja").is_empty():
				configure.append_array(["-G", "Ninja"])
			return [configure + extra, PackedStringArray(["cmake", "--build", build_dir, "-j"])]
		KIND_CARGO:
			var cargo := PackedStringArray(["cargo", "build", "--manifest-path", project.file, "--message-format=short"])
			if target == "template_release":
				cargo.append("--release")
			return [cargo + extra]
	return []


## Compila `project` (de find_project). Devuelve `{error, results: {ruta: {ok, errors}}, commands,
## seconds}`: `error` no vacío si no se pudo correr o falló sin errores de archivo (con el final de
## la salida); `results` solo tiene los archivos con errores.
static func build(project: Dictionary, target: String = "template_debug", extra: PackedStringArray = []) -> Dictionary:
	var started := Time.get_ticks_msec()
	var steps := commands(project, target, extra)
	var shown: PackedStringArray = []
	for step: PackedStringArray in steps:
		shown.append(" ".join(step))
	var report := {"error": "", "results": {}, "commands": shown, "seconds": 0.0}
	if steps.is_empty():
		report.error = "Unknown build system '%s'." % project.get("kind", "")
		return report
	var lines: PackedStringArray = []
	for step: PackedStringArray in steps:
		var executable := CommandResolver.resolve(step[0])
		if executable.is_empty():
			report.error = missing_tool_message(step[0])
			return report
		var run: Dictionary = await _run(executable, step.slice(1))
		lines.append_array(run.lines)
		if not run.error.is_empty():
			report.error = run.error
			break
		if run.code != 0:
			report.results = parse_output(lines, project.root)
			if report.results.is_empty():
				report.error = "%s failed (exit code %d) without file errors:\n%s" % [step[0], run.code, "\n".join(lines.slice(-TAIL_LINES))]
			break
	report.seconds = (Time.get_ticks_msec() - started) / 1000.0
	return report


static func missing_tool_message(tool: String) -> String:
	match tool:
		"scons":
			return "SCons is not installed or not on the PATH (`pip install scons`, or the system package): the extension can't be built."
		"cmake":
			return "CMake is not installed or not on the PATH: the extension can't be built."
		"cargo":
			return "Cargo is not installed or not on the PATH (install Rust with rustup): the extension can't be built."
	return "%s is not installed or not on the PATH." % tool


static func _run(executable: String, args: PackedStringArray) -> Dictionary:
	var process := AgentProcess.new()
	var lines: PackedStringArray = []
	var state := {"exited": false, "code": 0}
	process.line_received.connect(func(line: String) -> void: lines.append(line))
	process.stderr_received.connect(func(line: String) -> void: lines.append(line))
	process.exited.connect(func(code: int) -> void:
		state.exited = true
		state.code = code)
	# Mensajes del compilador en inglés y sin colores: el agente los lee y parse_output los busca.
	var env := {"LC_MESSAGES": "C", "LANGUAGE": "en", "CARGO_TERM_COLOR": "never", "CLICOLOR": "0"}
	if not process.start(executable, args, env):
		return {"error": "Could not run %s: %s" % [executable.get_file(), process.last_error()], "lines": lines, "code": -1}
	var tree := Engine.get_main_loop() as SceneTree
	var deadline := Time.get_ticks_msec() + int(BUILD_TIMEOUT_S * 1000.0)
	while not state.exited and Time.get_ticks_msec() < deadline:
		await tree.process_frame
	if not state.exited:
		process.stop()
		return {"error": "%s did not finish within %d s." % [executable.get_file(), int(BUILD_TIMEOUT_S)], "lines": lines, "code": -1}
	await tree.create_timer(OUTPUT_GRACE_S).timeout
	process.stop()
	return {"error": "", "lines": lines, "code": int(state.code)}


## Las líneas de error del compilador → `{ruta: {ok: false, errors: ["line N: [código ]mensaje"]}}`.
## Las rutas relativas son relativas a `root` (scons -C, cargo); las del proyecto Godot quedan como
## res://, las de afuera absolutas. Los warnings no cuentan.
static func parse_output(lines: PackedStringArray, root: String) -> Dictionary:
	var gnu := RegEx.create_from_string(_GNU_PATTERN)
	var msvc := RegEx.create_from_string(_MSVC_PATTERN)
	var results: Dictionary = {}
	for raw: String in lines:
		var line := raw.strip_edges()
		var found := msvc.search(line)
		if found == null:
			found = gnu.search(line)
		if found == null:
			continue
		var path := found.get_string(1)
		if path.is_relative_path():
			path = root.path_join(path)
		path = ProjectSettings.localize_path(path.simplify_path())
		var code := found.get_string(3)
		var entry := "line %s: %s%s" % [found.get_string(2), code + " " if not code.is_empty() else "", found.get_string(4)]
		if not results.has(path):
			results[path] = {"ok": false, "errors": []}
		if not entry in results[path].errors:
			results[path].errors.append(entry)
	return results
