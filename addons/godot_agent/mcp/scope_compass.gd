@tool
extends RefCounted
## Scope Compass integrado (m7-56): si el proyecto tiene el plugin activado y su tablero (compass/),
## el agente recibe el MCP `scompass` sin instalarlo a mano, y el prompt le dice que el tablero es la
## forma de organizar el proyecto.
##
## scompass sale solo de lugares del usuario (el registro que anota al correr, la opción del plugin en
## Editor Settings o el PATH), nunca de una carpeta del proyecto: un repo clonado no elige qué corre.

const SERVER_NAME := "scompass"
const PLUGIN_CFG := "res://addons/scope_compass/plugin.cfg"
const BOARD_DIR := "compass"
## Opción del plugin de Scope Compass con la ruta de scompass (addons/scope_compass/scope_compass.gd).
const PATH_SETTING := "scope_compass/scompass_path"
## Tools que solo leen (readOnlyHint del server): van al grupo Read. Las demás, a `mcp:scompass`.
const READ_TOOLS: PackedStringArray = [
	"list_tasks", "show_task", "task_history", "list_milestones", "show_milestone", "list_links",
	"list_playtests", "show_playtest", "list_decisions", "list_docs", "search_docs", "show_doc", "doc_coverage",
]


## true si el proyecto de `project_dir` tiene Scope Compass activado en project.godot y su tablero.
static func detect(project_dir: String) -> bool:
	var board := project_dir.path_join(BOARD_DIR)
	if not DirAccess.dir_exists_absolute(board):
		return false
	var config := ConfigFile.new()
	if config.load(project_dir.path_join("project.godot")) != OK:
		return false
	var enabled: Variant = config.get_value("editor_plugins", "enabled", PackedStringArray())
	return (enabled is PackedStringArray or enabled is Array) and PLUGIN_CFG in Array(enabled)


## [programa, args previos] de scompass, o [] si no está. `configured`: la opción del plugin.
static func command(configured: String = "") -> Array:
	var recorded := recorded_command()
	if not recorded.is_empty():
		return recorded
	if not configured.is_empty():
		var path := configured.replace("\\", "/")
		if path.ends_with(".js") and FileAccess.file_exists(path):
			return ["node", [path]]
		if FileAccess.file_exists(path) and path.get_extension().to_lower() not in ["cmd", "ps1"]:
			return [path, []]
	return _from_path()


## La instalación que scompass anota al correr: <datos>/scompass.json con command y args. [] si no
## está o el programa ya no existe.
static func recorded_command() -> Array:
	var file := data_dir().path_join("scompass.json")
	if not FileAccess.file_exists(file):
		return []
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(file))
	if not parsed is Dictionary or not parsed.get("command") is String:
		return []
	var program: String = parsed.command
	var args: Array = parsed.get("args") if parsed.get("args") is Array else []
	if not FileAccess.file_exists(program):
		return []
	for arg: Variant in args:
		if not arg is String or not FileAccess.file_exists(arg):
			return []
	return [program, args]


## Carpeta de datos de Scope Compass: SCOMPASS_DATA, o la del sistema.
static func data_dir() -> String:
	var data := OS.get_environment("SCOMPASS_DATA")
	if data.is_empty():
		if OS.get_name() == "Windows":
			var local := OS.get_environment("LOCALAPPDATA")
			if local.is_empty():
				local = OS.get_environment("USERPROFILE").path_join("AppData/Local")
			data = local.path_join("scope-compass")
		else:
			var xdg := OS.get_environment("XDG_DATA_HOME")
			if xdg.is_empty():
				xdg = OS.get_environment("HOME").path_join(".local/share")
			data = xdg.path_join("scope-compass")
	return data.replace("\\", "/")


static func _from_path() -> Array:
	var out: Array = []
	if OS.get_name() == "Windows":
		# El binario de la release (scompass.exe); el shim .cmd de npm no se lanza sin consola.
		if OS.execute("where", ["scompass"], out) == 0:
			for line: String in str(out[0]).split("\n"):
				var found := line.strip_edges().replace("\\", "/")
				if found.get_extension().to_lower() == "exe" and FileAccess.file_exists(found):
					return [found, []]
				var js := found.get_base_dir().path_join("node_modules/scope-compass/bin/scompass.js")
				if not found.is_empty() and FileAccess.file_exists(js):
					return ["node", [js]]
		return []
	if OS.execute("sh", ["-c", "command -v scompass"], out) == 0 and not str(out[0]).strip_edges().is_empty():
		return [str(out[0]).strip_edges(), []]
	return []


## El server para la lista de servers de terceros (formato de external_mcp_servers.gd), o {} si el
## proyecto no usa Scope Compass o no se encontró scompass. `program`: el de command() (para tests).
static func server_entry(project_dir: String, program: Array) -> Dictionary:
	if program.is_empty() or not detect(project_dir):
		return {}
	var args: Array = []
	for arg: Variant in program[1]:
		args.append(str(arg))
	args.append_array(["--dir", project_dir, "mcp"])
	return {
		"name": SERVER_NAME, "transport": "stdio", "command": str(program[0]), "args": args,
		"env": {}, "url": "", "headers": {}, "enabled": true, "builtin": true,
	}


## true si `tool` (`list_tasks`) del server scompass solo lee.
static func is_read_tool(tool: String) -> bool:
	return tool in READ_TOOLS
