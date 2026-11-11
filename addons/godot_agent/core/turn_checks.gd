@tool
extends RefCounted
## Checks del proyecto al terminar un turno de Construir o Auto (m11-31): las regresiones de playtest
## guardadas o un comando (GUT, gdUnit4, un script del proyecto). Viven en project_config.tres
## (`turn_checks`), versionables. Un check es
## `{name, kind: "regressions"|"command", command, paths: [globs res://], timeout_s, enabled}`.
## Un comando es un programa con sus argumentos, sin shell, y corre solo si se aprobó ese texto
## exacto en esta máquina (HarnessSettings.is_command_approved): el archivo viaja con el proyecto.

const AgentProcess := preload("../transport/agent_process.gd")

const KIND_REGRESSIONS := "regressions"
const KIND_COMMAND := "command"
const KINDS: PackedStringArray = [KIND_REGRESSIONS, KIND_COMMAND]
const DEFAULT_TIMEOUT_S := 300
const MAX_TIMEOUT_S := 3600
## `{godot}` en un comando: el binario de este editor (no siempre está en el PATH).
const GODOT_PLACEHOLDER := "{godot}"
## `{project}`: la carpeta del proyecto. El comando corre con el proyecto como carpeta de trabajo
## (la del editor), así que las rutas relativas también valen.
const PROJECT_PLACEHOLDER := "{project}"
const REGRESSION_SCRIPT := "res://addons/godot_agent/playtest/regression_cli.gd"
## regression_cli sale con 2 si no hay regresiones guardadas: no es una falla.
const REGRESSIONS_NONE_CODE := 2
## Lo que se guarda de la salida para el aviso y para el agente.
const OUTPUT_LINES := 40
const OUTPUT_CHARS := 4000
const OUTPUT_GRACE_S := 0.2
## Carpetas que no cuentan como cambios del turno.
const SKIPPED_DIRS: PackedStringArray = [".godot", ".git", ".godot_agent", ".import"]
## Caracteres de shell que un comando no puede tener: corre sin shell.
const SHELL_CHARS := ["|", "&", ";", "<", ">", "`", "$(", "\n", "\r"]

## Presets de la lista de Settings: completan el comando.
const PRESETS: Array[Dictionary] = [
	{
		"label": "Saved playtest regressions",  # i18n
		"name": "Playtest regressions", "kind": KIND_REGRESSIONS, "command": "",
	},
	{
		"label": "GUT tests",  # i18n
		"name": "GUT", "kind": KIND_COMMAND, "command": "{godot} --headless --path {project} -s res://addons/gut/gut_cmdln.gd -gexit",
	},
	{
		"label": "gdUnit4 tests",  # i18n
		"name": "gdUnit4", "kind": KIND_COMMAND, "command": "{godot} --headless --path {project} -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://test",
	},
	{
		"label": "Command",  # i18n
		"name": "", "kind": KIND_COMMAND, "command": "",
	},
]

## Resultado de un check: ok, falló, no corrió porque no está aprobado, o no tocaba.
const PASSED := "passed"
const FAILED := "failed"
const UNAPPROVED := "unapproved"
const SKIPPED := "skipped"


static func make(kind: String = KIND_COMMAND, name: String = "", command: String = "") -> Dictionary:
	return {"name": name, "kind": kind if kind in KINDS else KIND_COMMAND, "command": command, "paths": PackedStringArray(), "timeout_s": DEFAULT_TIMEOUT_S, "enabled": true}


## Un check guardado, con todos los campos y del tipo esperado ({} si no es un Dictionary).
static func normalize(data: Variant) -> Dictionary:
	if not data is Dictionary:
		return {}
	var source: Dictionary = data
	var check := make(str(source.get("kind", KIND_COMMAND)), str(source.get("name", "")).strip_edges(), str(source.get("command", "")).strip_edges())
	if source.get("paths") is Array or source.get("paths") is PackedStringArray:
		for path: Variant in source.paths:
			if not str(path).strip_edges().is_empty():
				check.paths.append(str(path).strip_edges())
	check.timeout_s = clampi(int(source.get("timeout_s", DEFAULT_TIMEOUT_S)), 1, MAX_TIMEOUT_S)
	check.enabled = bool(source.get("enabled", true))
	if check.name.is_empty():
		check.name = "Playtest regressions" if check.kind == KIND_REGRESSIONS else check.command.get_slice(" ", 0).get_file()
	return check


static func normalize_list(data: Variant) -> Array:
	var result: Array = []
	if data is Array:
		for item: Variant in data:
			var check := normalize(item)
			if not check.is_empty():
				result.append(check)
	return result


## Los argumentos del comando: comillas simples o dobles agrupan; `{godot}` queda como está (lo
## reemplaza `expand`). `{args, error}`: error si está vacío, si una comilla no cierra o si usa
## algo de shell (|, &&, ;, redirecciones, $()), que no se interpreta.
static func parse_command(text: String) -> Dictionary:
	var source := text.strip_edges()
	if source.is_empty():
		return {"args": PackedStringArray(), "error": "The command is empty."}
	for token: String in SHELL_CHARS:
		if source.contains(token):
			return {"args": PackedStringArray(), "error": "The command runs without a shell: «%s» isn't allowed. Put that in a script of the project and run the script." % token.c_escape()}
	var args := PackedStringArray()
	var current := ""
	var quote := ""
	var has_token := false
	for i in source.length():
		var c := source[i]
		if not quote.is_empty():
			if c == quote:
				quote = ""
			else:
				current += c
		elif c == "'" or c == "\"":
			quote = c
			has_token = true
		elif c == " " or c == "\t":
			if has_token:
				args.append(current)
				current = ""
				has_token = false
		else:
			current += c
			has_token = true
	if not quote.is_empty():
		return {"args": PackedStringArray(), "error": "A quote isn't closed."}
	if has_token:
		args.append(current)
	return {"args": args, "error": ""}


## `{godot}` → el binario del editor y `{project}` → la carpeta del proyecto, en cualquier argumento.
static func expand(args: PackedStringArray, godot_path: String, project_dir: String = "") -> PackedStringArray:
	var result := PackedStringArray()
	for arg: String in args:
		result.append(arg.replace(GODOT_PLACEHOLDER, godot_path).replace(PROJECT_PLACEHOLDER, project_dir))
	return result


## El programa y los argumentos con que corre `check` en el proyecto `project_dir`.
static func invocation(check: Dictionary, godot_path: String, project_dir: String) -> Dictionary:
	if check.kind == KIND_REGRESSIONS:
		return {"program": godot_path, "args": PackedStringArray(["--headless", "--path", project_dir, "--script", REGRESSION_SCRIPT]), "error": ""}
	var parsed := parse_command(str(check.command))
	if not str(parsed.error).is_empty():
		return {"program": "", "args": PackedStringArray(), "error": parsed.error}
	var args := expand(parsed.args, godot_path, project_dir)
	return {"program": args[0], "args": args.slice(1), "error": ""}


## Si `check` toca este turno: sin globs, cualquier cambio; con globs, alguno de `changed` (res://).
static func applies(check: Dictionary, changed: PackedStringArray) -> bool:
	if changed.is_empty():
		return false
	if (check.paths as PackedStringArray).is_empty():
		return true
	for path: String in changed:
		for glob: String in check.paths:
			if path.match(glob) or path.match(glob.trim_suffix("/**") + "/*"):
				return true
	return false


## Los archivos del proyecto (res://) modificados desde `since_unix`, sin .godot, .git ni .godot_agent.
static func changed_since(project_dir: String, since_unix: int, max_files: int = 20000) -> PackedStringArray:
	var result := PackedStringArray()
	var pending: Array[String] = [""]
	var seen := 0
	while not pending.is_empty() and seen < max_files:
		var rel: String = pending.pop_back()
		var dir := DirAccess.open(project_dir.path_join(rel))
		if dir == null:
			continue
		dir.include_hidden = true
		for name: String in dir.get_directories():
			if not name in SKIPPED_DIRS:
				pending.append(rel.path_join(name) if not rel.is_empty() else name)
		for name: String in dir.get_files():
			seen += 1
			var file_rel := rel.path_join(name) if not rel.is_empty() else name
			if FileAccess.get_modified_time(project_dir.path_join(file_rel)) >= since_unix:
				result.append("res://" + file_rel)
	return result


## La clave con que se aprueba un comando en esta máquina: el proyecto y el texto exacto.
static func approval_key(project_dir: String, command: String) -> String:
	return (project_dir.simplify_path() + "\n" + command.strip_edges()).sha256_text()


## Corre un check ya decidido (aplica y, si es un comando, está aprobado). Devuelve
## `{name, status, code, output, timed_out}`.
static func run(check: Dictionary, godot_path: String, project_dir: String) -> Dictionary:
	var result := {"name": str(check.name), "status": FAILED, "code": -1, "output": "", "timed_out": false}
	var how := invocation(check, godot_path, project_dir)
	if not str(how.error).is_empty():
		result.output = how.error
		return result
	var process := AgentProcess.new()
	var lines: PackedStringArray = []
	var state := {"exited": false, "code": 0}
	process.line_received.connect(func(line: String) -> void: lines.append(line))
	process.stderr_received.connect(func(line: String) -> void: lines.append(line))
	process.exited.connect(func(code: int) -> void:
		state.exited = true
		state.code = code)
	if not process.start(str(how.program), how.args):
		result.output = "Could not launch %s: %s" % [how.program, process.last_error()]
		return result
	var tree := Engine.get_main_loop() as SceneTree
	var deadline := Time.get_ticks_msec() + int(check.timeout_s) * 1000
	while not state.exited and Time.get_ticks_msec() < deadline:
		await tree.process_frame
	if not state.exited:
		process.stop()
		result.timed_out = true
		result.output = tail(lines) + "\n(stopped after %d s)" % int(check.timeout_s)
		return result
	await tree.create_timer(OUTPUT_GRACE_S).timeout
	process.stop()
	result.code = int(state.code)
	result.output = tail(lines)
	if check.kind == KIND_REGRESSIONS and result.code == REGRESSIONS_NONE_CODE and result.output.contains("none found"):
		result.status = SKIPPED
	else:
		result.status = PASSED if result.code == 0 else FAILED
	return result


## El final de la salida: las últimas OUTPUT_LINES líneas, hasta OUTPUT_CHARS.
static func tail(lines: PackedStringArray) -> String:
	var text := "\n".join(lines.slice(maxi(0, lines.size() - OUTPUT_LINES))).strip_edges()
	return text.right(OUTPUT_CHARS) if text.length() > OUTPUT_CHARS else text
