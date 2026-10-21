@tool
extends RefCounted
## Prepara el shim stdio → HTTP (spec §4.3) en un proyecto vacío propio bajo user://, para que el
## proceso del shim no cargue autoloads ni scripts del proyecto del usuario.

const SHIM_SOURCE := "res://addons/godot_agent/mcp/mcp_stdio_shim.gd"
const SHIM_DIR := "user://godot_agent_mcp_shim"
const PROJECT_FILE := """config_version=5

[application]

config/name="godot_agent_mcp_shim"
run/flush_stdout_on_print=true
"""


## Entrada `mcpServers` de tipo stdio para session/new, o {} si no se pudo preparar.
static func server_entry(name: String, url: String, token: String) -> Dictionary:
	var dir := ensure_installed()
	if dir.is_empty():
		return {}
	return {
		"name": name,
		"command": OS.get_executable_path(),
		"args": ["--headless", "--no-header", "--path", dir, "--script", "res://mcp_stdio_shim.gd"],
		"env": [
			{"name": "GODOT_AGENT_MCP_URL", "value": url},
			{"name": "GODOT_AGENT_MCP_TOKEN", "value": token},
		],
	}


## Copia el shim y un project.godot mínimo. Devuelve la ruta absoluta de la carpeta, o "".
static func ensure_installed() -> String:
	var dir := ProjectSettings.globalize_path(SHIM_DIR)
	if DirAccess.make_dir_recursive_absolute(dir) != OK:
		return ""
	if not _write_if_changed(dir.path_join("project.godot"), PROJECT_FILE):
		return ""
	if not _write_if_changed(dir.path_join("mcp_stdio_shim.gd"), FileAccess.get_file_as_string(SHIM_SOURCE)):
		return ""
	return dir


static func _write_if_changed(path: String, text: String) -> bool:
	if text.is_empty():
		return false
	if FileAccess.file_exists(path) and FileAccess.get_file_as_string(path) == text:
		return true
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(text)
	file.close()
	return true
