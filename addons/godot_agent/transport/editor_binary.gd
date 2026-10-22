@tool
extends RefCounted
## El binario de Godot que corre este editor (D43). Cuando el agente corre Godot por línea de
## comandos (`--headless`, `--import`, tests) tiene que usar este y no el `godot` del PATH, que
## puede ser otra versión. Le llega por tres lados: GODOT/GODOT_BIN en su entorno, un shim
## `godot` al frente de su PATH y la ruta en el system prompt (la shell del agente puede volver a
## armar el PATH desde el perfil del usuario, así que el prompt es lo que manda).

const ENV_KEYS: PackedStringArray = ["GODOT", "GODOT_BIN"]
const SHIM_ROOT := "godot_agent"


static func path() -> String:
	return OS.get_executable_path()


## Entorno del agente: `env` (el del perfil) más GODOT/GODOT_BIN, si el perfil no los define, y la
## carpeta del shim al frente del PATH (`base_path` si `env` no trae uno).
static func child_env(env: Dictionary, base_path: String) -> Dictionary:
	var result := env.duplicate()
	for key: String in ENV_KEYS:
		if not result.has(key):
			result[key] = path()
	var current: String = result.get("PATH", base_path)
	var dir := shim_dir()
	result["PATH"] = current if dir.is_empty() else dir + _separator() + current
	return result


## Carpeta con un `godot` (`godot.cmd` en Windows) que lanza `executable`. Una por binario, para
## que dos editores de versiones distintas no se pisen. "" si no se pudo crear.
static func shim_dir(executable: String = path()) -> String:
	var dir := OS.get_cache_dir().path_join(SHIM_ROOT).path_join("bin-" + executable.md5_text().left(12))
	var windows := OS.get_name() == "Windows"
	var shim := dir.path_join("godot.cmd" if windows else "godot")
	var content := shim_content(executable, windows)
	if FileAccess.file_exists(shim) and FileAccess.get_file_as_string(shim) == content:
		return dir
	if DirAccess.make_dir_recursive_absolute(dir) != OK:
		return ""
	var file := FileAccess.open(shim, FileAccess.WRITE)
	if file == null:
		return ""
	file.store_string(content)
	file.close()
	if not windows:
		FileAccess.set_unix_permissions(shim, FileAccess.UNIX_READ_OWNER | FileAccess.UNIX_WRITE_OWNER
			| FileAccess.UNIX_EXECUTE_OWNER | FileAccess.UNIX_READ_GROUP | FileAccess.UNIX_EXECUTE_GROUP
			| FileAccess.UNIX_READ_OTHER | FileAccess.UNIX_EXECUTE_OTHER)
	return dir


static func shim_content(executable: String, windows: bool) -> String:
	if windows:
		return "@\"%s\" %%*\r\n" % executable
	return "#!/bin/sh\nexec '%s' \"$@\"\n" % executable.replace("'", "'\\''")


static func _separator() -> String:
	return ";" if OS.get_name() == "Windows" else ":"
