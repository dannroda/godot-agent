@tool
extends Node
## Actualizaciones del addon (m7-38): busca el último release en GitHub, baja su zip, lo extrae en
## user:// y reemplaza addons/godot_agent. Después el editor se reinicia (lo hace el plugin). La
## config del proyecto (project_config.tres) no viene en el zip y queda; si system_prompt.md o
## quota_patterns.txt cambian, la copia anterior se guarda aparte. En una copia de desarrollo (el
## addon es un symlink o está el plugin de dev) no se ofrece: ahí se actualiza con git.

const AddonVersion := preload("addon_version.gd")

const REPO := "dannroda/godot-agent"
const API_RELEASES := "https://api.github.com/repos/%s/releases"
const ADDON_DIR := "res://addons/godot_agent"
const ADDON_PATH_IN_ZIP := "addons/godot_agent/"
const STAGE_DIR := "user://godot_agent/update"
## Archivos de config que el usuario puede haber editado: si el release trae otra versión, la vieja
## se copia a la carpeta de respaldo antes de pisarla.
const USER_EDITABLE: PackedStringArray = ["config/system_prompt.md", "config/quota_patterns.txt"]
## Nunca se borran ni se pisan.
const KEEP: PackedStringArray = ["config/project_config.tres"]
## Lo que la versión nueva ya no trae se borra solo si es de estos tipos (lo que trae el release):
## un archivo que el usuario agregó a mano, de otro tipo, queda.
const REMOVABLE_EXTENSIONS: PackedStringArray = ["gd", "uid", "tscn", "po", "cfg", "md", "txt"]
const TIMEOUT_S := 60.0

var _http: HTTPRequest


func _ready() -> void:
	_http = HTTPRequest.new()
	_http.timeout = TIMEOUT_S
	_http.use_threads = false
	add_child(_http)


## true si esta copia del addon es de desarrollo: el addon es un symlink al repo o está el plugin
## de dev al lado. Ahí el updater no reemplaza nada.
static func is_dev_copy() -> bool:
	var addons := DirAccess.open("res://addons")
	if addons and addons.is_link("godot_agent"):
		return true
	return DirAccess.dir_exists_absolute("res://addons/godot_agent_dev")


## `{release, error}`. `release` es {} si no hay uno más nuevo que la versión instalada.
func check(include_prerelease: bool = false) -> Dictionary:
	var response := await _fetch(API_RELEASES % REPO + "?per_page=10")
	if not response.error.is_empty():
		return {"release": {}, "error": response.error}
	var data: Variant = _parse_json(response.body.get_string_from_utf8())
	if not data is Array:
		return {"release": {}, "error": "GitHub answered something unexpected."}
	var release := pick_release(data, include_prerelease)
	if release.is_empty() or compare_versions(release.version, AddonVersion.version()) <= 0:
		return {"release": {}, "error": ""}
	return {"release": release, "error": ""}


## Baja el zip del release, lo extrae y lo valida. `{ok, dir, error}`: `dir` es la carpeta del
## addon extraído (lista para install()).
func download(release: Dictionary) -> Dictionary:
	var stage := ProjectSettings.globalize_path(STAGE_DIR)
	_remove_tree(stage)
	DirAccess.make_dir_recursive_absolute(stage)
	var zip_path := stage.path_join("addon.zip")
	_http.download_file = zip_path
	var response := await _fetch(str(release.zip_url))
	_http.download_file = ""
	if not response.error.is_empty():
		return {"ok": false, "dir": "", "error": response.error}
	return extract(zip_path, stage.path_join("extracted"), str(release.version))


# --- estático (testeable sin red) ----------------------------------------------------------------

## -1, 0 o 1. Acepta "v1.2.3" y sufijos de pre-release ("1.3.0-beta.1" < "1.3.0").
static func compare_versions(a: String, b: String) -> int:
	var parts_a := _version_parts(a)
	var parts_b := _version_parts(b)
	for i in 3:
		if parts_a.numbers[i] != parts_b.numbers[i]:
			return 1 if parts_a.numbers[i] > parts_b.numbers[i] else -1
	if parts_a.pre == parts_b.pre:
		return 0
	if parts_a.pre.is_empty():
		return 1
	if parts_b.pre.is_empty():
		return -1
	return 1 if parts_a.pre > parts_b.pre else -1


## El release más nuevo de la lista de la API (sin borradores; pre-releases solo si se piden) que
## trae el zip del addon. `{version, tag, notes, zip_url, html_url, prerelease}` o {}.
static func pick_release(list: Array, include_prerelease: bool) -> Dictionary:
	var best: Dictionary = {}
	for item: Variant in list:
		if not item is Dictionary or bool(item.get("draft", false)):
			continue
		if bool(item.get("prerelease", false)) and not include_prerelease:
			continue
		var zip_url := ""
		for asset: Variant in item.get("assets", []):
			if asset is Dictionary and str(asset.get("name", "")).ends_with(".zip"):
				zip_url = str(asset.get("browser_download_url", ""))
		if zip_url.is_empty():
			continue
		var tag := str(item.get("tag_name", ""))
		var release := {
			"version": tag.trim_prefix("v"),
			"tag": tag,
			"notes": str(item.get("body", "")),
			"zip_url": zip_url,
			"html_url": str(item.get("html_url", "")),
			"prerelease": bool(item.get("prerelease", false)),
		}
		if best.is_empty() or compare_versions(release.version, best.version) > 0:
			best = release
	return best


## Extrae `addons/godot_agent/` del zip a `dest` y comprueba que plugin.cfg diga `version`.
static func extract(zip_path: String, dest: String, version: String) -> Dictionary:
	var reader := ZIPReader.new()
	if reader.open(zip_path) != OK:
		return {"ok": false, "dir": "", "error": "The downloaded file is not a valid zip."}
	_remove_tree(dest)
	var count := 0
	for name: String in reader.get_files():
		if not name.begins_with(ADDON_PATH_IN_ZIP) or name.ends_with("/"):
			continue
		var relative := name.trim_prefix(ADDON_PATH_IN_ZIP)
		if relative.contains("..") or relative.is_absolute_path():
			continue
		var target := dest.path_join(relative)
		DirAccess.make_dir_recursive_absolute(target.get_base_dir())
		var file := FileAccess.open(target, FileAccess.WRITE)
		if file == null:
			reader.close()
			return {"ok": false, "dir": "", "error": "Could not write %s." % target}
		file.store_buffer(reader.read_file(name))
		file.close()
		count += 1
	reader.close()
	if count == 0:
		return {"ok": false, "dir": "", "error": "The zip doesn't have addons/godot_agent."}
	var config := ConfigFile.new()
	if config.load(dest.path_join("plugin.cfg")) != OK:
		return {"ok": false, "dir": "", "error": "The zip has no plugin.cfg."}
	var found := str(config.get_value("plugin", "version", ""))
	if compare_versions(found, version) != 0:
		return {"ok": false, "dir": "", "error": "The zip is version %s, not %s." % [found, version]}
	return {"ok": true, "dir": dest, "error": ""}


## Copia el addon extraído sobre `target` (rutas absolutas). Borra lo que la versión nueva ya no
## trae (salvo KEEP y lo que no es de REMOVABLE_EXTENSIONS) y respalda en `backup` los
## USER_EDITABLE que cambian.
## `{ok, written, removed, backed_up, error}`.
static func install(staged: String, target: String, backup: String) -> Dictionary:
	var new_files := _list_files(staged)
	if not "plugin.cfg" in new_files:
		return {"ok": false, "written": 0, "removed": [], "backed_up": [], "error": "The new version has no plugin.cfg."}
	var backed_up: PackedStringArray = []
	for relative: String in USER_EDITABLE:
		var current := target.path_join(relative)
		if FileAccess.file_exists(current) and relative in new_files and FileAccess.get_file_as_string(current) != FileAccess.get_file_as_string(staged.path_join(relative)):
			DirAccess.make_dir_recursive_absolute(backup.path_join(relative).get_base_dir())
			DirAccess.copy_absolute(current, backup.path_join(relative))
			backed_up.append(relative)
	var written := 0
	for relative: String in new_files:
		if relative in KEEP:
			continue
		var destination := target.path_join(relative)
		DirAccess.make_dir_recursive_absolute(destination.get_base_dir())
		if DirAccess.copy_absolute(staged.path_join(relative), destination) != OK:
			return {"ok": false, "written": written, "removed": [], "backed_up": backed_up, "error": "Could not write %s." % destination}
		written += 1
	var removed: PackedStringArray = []
	for relative: String in _list_files(target):
		if relative in new_files or relative in KEEP or not relative.get_extension() in REMOVABLE_EXTENSIONS:
			continue
		if DirAccess.remove_absolute(target.path_join(relative)) == OK:
			removed.append(relative)
	return {"ok": true, "written": written, "removed": removed, "backed_up": backed_up, "error": ""}


static func _version_parts(text: String) -> Dictionary:
	var clean := text.strip_edges().trim_prefix("v")
	var dash := clean.find("-")
	var pre := clean.substr(dash + 1) if dash >= 0 else ""
	var numbers: Array[int] = [0, 0, 0]
	var pieces := (clean.left(dash) if dash >= 0 else clean).split(".")
	for i in mini(pieces.size(), 3):
		numbers[i] = int(pieces[i])
	return {"numbers": numbers, "pre": pre}


## Rutas relativas de todos los archivos bajo `root`.
static func _list_files(root: String, prefix: String = "") -> PackedStringArray:
	var result: PackedStringArray = []
	var dir := root.path_join(prefix) if not prefix.is_empty() else root
	if not DirAccess.dir_exists_absolute(dir):
		return result
	for file: String in DirAccess.get_files_at(dir):
		result.append(prefix.path_join(file) if not prefix.is_empty() else file)
	for sub: String in DirAccess.get_directories_at(dir):
		result.append_array(_list_files(root, prefix.path_join(sub) if not prefix.is_empty() else sub))
	return result


static func _remove_tree(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		return
	for file: String in DirAccess.get_files_at(path):
		DirAccess.remove_absolute(path.path_join(file))
	for sub: String in DirAccess.get_directories_at(path):
		_remove_tree(path.path_join(sub))
	DirAccess.remove_absolute(path)


static func _parse_json(text: String) -> Variant:
	var json := JSON.new()
	return json.data if json.parse(text) == OK else null


## `{body: PackedByteArray, error}`.
func _fetch(url: String) -> Dictionary:
	var headers := PackedStringArray(["User-Agent: godot-agent-harness/%s" % AddonVersion.version(), "Accept: application/vnd.github+json"])
	if _http.request(url, headers) != OK:
		return {"body": PackedByteArray(), "error": "Could not connect to GitHub."}
	var result: Array = await _http.request_completed
	if int(result[0]) != HTTPRequest.RESULT_SUCCESS:
		return {"body": PackedByteArray(), "error": "No connection to GitHub (%d)." % int(result[0])}
	if int(result[1]) != 200:
		return {"body": PackedByteArray(), "error": "GitHub answered %d." % int(result[1])}
	return {"body": result[3], "error": ""}
