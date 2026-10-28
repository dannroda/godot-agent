@tool
extends Node
## Registro de agentes ACP (m11-12): el JSON público con cada agente y cómo instalarlo (npx, uvx o
## un binario por plataforma), el mismo que usa Zed. Lo lee, arma el perfil de un agente y, para
## los binarios, baja el archivo, lo verifica con su sha256 (si el registro lo trae) y lo
## descomprime en la carpeta de datos del editor, compartida por todos los proyectos.

const AddonVersion := preload("addon_version.gd")

const REGISTRY_URL := "https://cdn.agentclientprotocol.com/registry/v1/latest/registry.json"
const TIMEOUT_S := 120.0
const KIND_NPX := "npx"
const KIND_UVX := "uvx"
const KIND_BINARY := "binary"
## Orden de preferencia: npx y uvx se actualizan solos y no bajan nada al instalar.
const KINDS: PackedStringArray = [KIND_NPX, KIND_UVX, KIND_BINARY]

## Dónde se descomprimen los binarios: `<carpeta>/<id>/<versión>/`.
var install_root: String = ""


func _init() -> void:
	if Engine.is_editor_hint():
		install_root = EditorInterface.get_editor_paths().get_data_dir().path_join("godot_agent/agents")


## `{agents: [ver parse], error}`.
func fetch() -> Dictionary:
	var response := await _fetch(REGISTRY_URL)
	if not response.error.is_empty():
		return {"agents": [], "error": response.error}
	var data: Variant = JSON.parse_string(response.body.get_string_from_utf8())
	if not data is Dictionary:
		return {"agents": [], "error": "The ACP registry answered something unexpected."}
	return {"agents": parse(data, platform_key()), "error": ""}


## Instala un agente de `parse` y devuelve `{ok, profile, error}`: el perfil (Dictionary de
## AgentProfile) listo para guardar. npx y uvx no bajan nada; un binario se baja y se descomprime.
func install(agent: Dictionary) -> Dictionary:
	if agent.kind != KIND_BINARY:
		return {"ok": true, "profile": profile_for(agent, ""), "error": ""}
	var binary: Dictionary = agent.binary
	var dest := install_root.path_join(agent.id).path_join(agent.version)
	var archive := install_root.path_join("%s-%s.download" % [agent.id, agent.version])
	DirAccess.make_dir_recursive_absolute(install_root)
	var response := await _fetch(binary.archive, archive)
	if not response.error.is_empty():
		DirAccess.remove_absolute(archive)
		return {"ok": false, "profile": {}, "error": response.error}
	if not str(binary.sha256).is_empty() and FileAccess.get_sha256(archive) != str(binary.sha256).to_lower():
		DirAccess.remove_absolute(archive)
		return {"ok": false, "profile": {}, "error": "The download doesn't match the registry's checksum: it was not installed."}
	var extracted := extract(archive, str(binary.archive), dest, str(binary.cmd))
	DirAccess.remove_absolute(archive)
	if not extracted.is_empty():
		return {"ok": false, "profile": {}, "error": extracted}
	return {"ok": true, "profile": profile_for(agent, dest), "error": ""}


# --- estático (testeable sin red) ----------------------------------------------------------------

## Clave de plataforma del registro: `linux-x86_64`, `darwin-aarch64`, `windows-x86_64`…
static func platform_key() -> String:
	var os := {"Linux": "linux", "macOS": "darwin", "Windows": "windows"}.get(OS.get_name(), OS.get_name().to_lower())
	var arch := Engine.get_architecture_name()
	return "%s-%s" % [os, "aarch64" if arch == "arm64" else arch]


## Los agentes que se pueden instalar en `platform`, ordenados por nombre:
## `[{id, name, version, description, authors, website, kind, package, args, env, binary}]`, con
## `kind` el primero de KINDS que trae (`binary`: `{archive, cmd, args, env, sha256}`).
static func parse(data: Dictionary, platform: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for item: Variant in data.get("agents", []):
		if not item is Dictionary or not item.get("distribution") is Dictionary or not str(item.get("id", "")).is_valid_filename():
			continue
		var distribution: Dictionary = item.distribution
		var agent := {
			"id": str(item.id), "name": str(item.get("name", item.id)), "version": str(item.get("version", "")),
			"description": str(item.get("description", "")), "authors": _strings(item.get("authors", [])),
			"website": str(item.get("website", "")), "kind": "", "package": "", "args": PackedStringArray(), "env": {}, "binary": {},
		}
		for kind: String in KINDS:
			var entry: Variant = distribution.get(kind)
			if kind == KIND_BINARY and entry is Dictionary:
				entry = entry.get(platform)
			if not entry is Dictionary:
				continue
			if kind == KIND_BINARY:
				if not entry.get("archive") is String or not entry.get("cmd") is String:
					continue
				agent.binary = {"archive": entry.archive, "cmd": entry.cmd, "sha256": str(entry.get("sha256", ""))}
			elif not entry.get("package") is String:
				continue
			agent.kind = kind
			agent.package = str(entry.get("package", ""))
			agent.args = _strings(entry.get("args", []))
			agent.env = entry.env if entry.get("env") is Dictionary else {}
			break
		if not agent.kind.is_empty():
			result.append(agent)
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.name.naturalnocasecmp_to(b.name) < 0)
	return result


## El perfil (Dictionary de AgentProfile) de un agente; `install_dir` es donde quedó su binario.
static func profile_for(agent: Dictionary, install_dir: String) -> Dictionary:
	var command := ""
	var args := PackedStringArray()
	match agent.kind:
		KIND_NPX:
			command = "npx"
			args = PackedStringArray(["-y", agent.package])
		KIND_UVX:
			command = "uvx"
			args = PackedStringArray([agent.package])
		KIND_BINARY:
			command = install_dir.path_join(str(agent.binary.cmd).trim_prefix("./"))
	args.append_array(agent.args)
	var env := {}
	for key: Variant in agent.env:
		env[str(key)] = str(agent.env[key])
	return {"id": agent.id, "display_name": agent.name, "command": command, "args": Array(args), "env": env, "default": false}


## Descomprime `archive` en `dest` según la extensión de `url`: .zip con ZIPReader (sin rutas que
## salgan de `dest`), .tar.* con el `tar` del sistema, y cualquier otra cosa es el ejecutable mismo.
## Después deja ejecutable `cmd`. Devuelve "" o el error.
static func extract(archive: String, url: String, dest: String, cmd: String) -> String:
	DirAccess.make_dir_recursive_absolute(dest)
	var name := url.get_file().to_lower()
	if name.ends_with(".zip"):
		var reader := ZIPReader.new()
		if reader.open(archive) != OK:
			return "The downloaded file is not a valid zip."
		for path: String in reader.get_files():
			if path.ends_with("/") or path.is_absolute_path() or ".." in path.split("/"):
				continue
			var target := dest.path_join(path)
			DirAccess.make_dir_recursive_absolute(target.get_base_dir())
			var file := FileAccess.open(target, FileAccess.WRITE)
			if file == null:
				reader.close()
				return "Could not write %s." % target
			file.store_buffer(reader.read_file(path))
			file.close()
		reader.close()
	elif ".tar." in name or name.ends_with(".tgz"):
		var output := []
		if OS.execute("tar", ["-xf", ProjectSettings.globalize_path(archive), "-C", ProjectSettings.globalize_path(dest)], output, true) != 0:
			return "Could not extract the archive with tar: %s" % "".join(output).strip_edges()
	elif DirAccess.copy_absolute(archive, dest.path_join(cmd.trim_prefix("./"))) != OK:
		return "Could not save the downloaded program."
	var program := dest.path_join(cmd.trim_prefix("./"))
	if not FileAccess.file_exists(program):
		return "The archive doesn't have %s." % cmd
	if OS.get_name() != "Windows":
		OS.execute("chmod", ["+x", ProjectSettings.globalize_path(program)])
	return ""


static func _strings(value: Variant) -> PackedStringArray:
	var result := PackedStringArray()
	if value is Array:
		for item: Variant in value:
			result.append(str(item))
	return result


## `{body: PackedByteArray, error}`. Con `download_file`, el cuerpo va a ese archivo.
func _fetch(url: String, download_file: String = "") -> Dictionary:
	var http := HTTPRequest.new()
	http.timeout = TIMEOUT_S
	http.download_file = download_file
	add_child(http)
	var headers := PackedStringArray(["User-Agent: godot-agent-harness/%s" % AddonVersion.version()])
	if http.request(url, headers) != OK:
		http.queue_free()
		return {"body": PackedByteArray(), "error": "Could not connect to %s." % url.get_slice("/", 2)}
	var result: Array = await http.request_completed
	http.queue_free()
	if int(result[0]) != HTTPRequest.RESULT_SUCCESS:
		return {"body": PackedByteArray(), "error": "No connection to %s (%d)." % [url.get_slice("/", 2), int(result[0])]}
	if int(result[1]) != 200:
		return {"body": PackedByteArray(), "error": "%s answered %d." % [url.get_slice("/", 2), int(result[1])]}
	return {"body": result[3], "error": ""}
