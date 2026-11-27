@tool
extends RefCounted
## El editor deja dónde escucha su MCP y un token propio para la app aparte (m20-05): un archivo por
## proyecto, solo legible por el usuario (0600), al lado de los datos del editor. Lo borra al cerrar;
## si el editor se cae y lo deja, nadie escucha en el puerto y no se usa.

const AcpRegistry := preload("../core/acp_registry.gd")

const DIR := "godot_agent/mcp"
## El caller de las llamadas que llegan con el token publicado: la app, sin pestaña en el editor.
const APP_CALLER := "standalone"
const PRIVATE_FILE := 384  # 0o600
const PRIVATE_DIR := 448  # 0o700


static func path_for(project: String) -> String:
	return AcpRegistry.editor_data_dir().path_join(DIR).path_join(project.simplify_path().trim_suffix("/").md5_text() + ".json")


static func publish(project: String, url: String, token: String) -> Error:
	var path := path_for(project)
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	FileAccess.set_unix_permissions(path.get_base_dir(), PRIVATE_DIR)
	var temp := path + ".tmp"
	# Vacío y con permisos antes de escribir el token: nunca queda legible para otros.
	var file := FileAccess.open(temp, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.close()
	FileAccess.set_unix_permissions(temp, PRIVATE_FILE)
	file = FileAccess.open(temp, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify({"project": project.simplify_path().trim_suffix("/"), "url": url, "token": token, "pid": OS.get_process_id()}))
	file.close()
	var error := DirAccess.rename_absolute(temp, path)
	if error != OK:
		DirAccess.remove_absolute(temp)
	return error


## {url, token} del editor abierto en `project`, o {} si no hay uno vivo.
static func read(project: String) -> Dictionary:
	var path := path_for(project)
	if not FileAccess.file_exists(path):
		return {}
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not data is Dictionary or str(data.get("project", "")) != project.simplify_path().trim_suffix("/") \
			or str(data.get("token", "")).is_empty() or not listening(str(data.get("url", ""))):
		return {}
	return {"url": str(data.url), "token": str(data.token)}


## Si algo acepta conexiones en el puerto de `url` (127.0.0.1): rechaza enseguida si no.
## OS.is_process_running no sirve: en Linux solo ve procesos hijos.
static func listening(url: String) -> bool:
	var port := url.get_slice("://", 1).get_slice("/", 0).get_slice(":", 1).to_int()
	if port <= 0:
		return false
	var peer := StreamPeerTCP.new()
	if peer.connect_to_host("127.0.0.1", port) != OK:
		return false
	var deadline := Time.get_ticks_msec() + 300
	while Time.get_ticks_msec() < deadline:
		peer.poll()
		if peer.get_status() != StreamPeerTCP.STATUS_CONNECTING:
			break
		OS.delay_msec(5)
	var connected := peer.get_status() == StreamPeerTCP.STATUS_CONNECTED
	peer.disconnect_from_host()
	return connected


## Solo si es el de este editor: otro abierto en el mismo proyecto lo pudo haber reemplazado.
static func remove(project: String) -> void:
	var path := path_for(project)
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else null
	if data is Dictionary and int(data.get("pid", 0)) == OS.get_process_id():
		DirAccess.remove_absolute(path)
