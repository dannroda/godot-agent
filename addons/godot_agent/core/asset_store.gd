@tool
extends Node
## Godot Asset Store (m7-39): busca addons, lee su ficha y sus releases y los instala en el proyecto,
## con la misma API que usa el editor (store.godotengine.org/api/v1, sin autenticación). La
## instalación sigue al instalador del editor: saca la carpeta raíz del zip (salvo que sea addons/)
## y nunca pisa un archivo que ya existe. Además, por defecto solo instala lo que va en addons/ (los
## zips suelen traer demos, README y hasta un project.godot). Cada instalación queda anotada en
## res://.godot_agent/assets.json (asset, versión, carpetas y archivos), y con eso check_updates()
## avisa de versiones nuevas y una actualización reemplaza la carpeta del addon (borra lo que la
## versión nueva ya no trae). Para los plugins instalados a mano adivina el asset por el nombre.

const AddonUpdater := preload("addon_updater.gd")
const AddonVersion := preload("addon_version.gd")

const API := "https://store.godotengine.org/api/v1"
const STAGE_DIR := "user://godot_agent/assets"
## Resultados por página de search/query (fijo en el store).
const PAGE_SIZE := 24
const SORTS: PackedStringArray = ["relevance", "updated_desc", "reviews_desc", "created_desc"]
const TIMEOUT_S := 60.0
## Cuánto se espera como mucho a que el editor vea los archivos instalados.
const SCAN_TIMEOUT_S := 30.0
## Texto de la ficha que se devuelve como mucho.
const BODY_LIMIT := 4000
## Largo de la descripción de cada resultado de la búsqueda.
const DESCRIPTION_LIMIT := 240
## Qué asset y qué versión vino a cada carpeta de addons/ (.godot_agent/ nunca se exporta:
## el export plugin la saltea).
const MANIFEST_PATH := "res://.godot_agent/assets.json"
## Plugins que no se tocan desde acá: el propio harness (se actualiza con su updater).
const PROTECTED_FOLDERS: PackedStringArray = ["godot_agent", "godot_agent_dev"]

var manifest_path: String = MANIFEST_PATH

## `{assets: [ver parse_hits], count, pages, error}`.
func search(query: String, page: int = 1, sort: String = "relevance") -> Dictionary:
	var response := await _fetch_json(search_path(query, page, sort, Engine.get_version_info()))
	if not response.error.is_empty():
		return {"assets": [], "count": 0, "pages": 0, "error": response.error}
	if not response.data is Dictionary:
		return {"assets": [], "count": 0, "pages": 0, "error": "The Asset Store answered something unexpected."}
	var count := int(str(response.data.get("count", 0)))
	return {"assets": parse_hits(response.data.get("hits", [])), "count": count, "pages": ceili(count / float(PAGE_SIZE)), "error": ""}


## `{asset: {id, name, publisher, description, body, license, tags, source, store_url, price_cent}, error}`.
func details(asset_id: String) -> Dictionary:
	if not is_valid_id(asset_id):
		return {"asset": {}, "error": "The asset id must be publisher/slug (as asset_search shows it)."}
	var response := await _fetch_json("assets/%s/" % asset_id)
	if not response.error.is_empty():
		return {"asset": {}, "error": response.error}
	if not response.data is Dictionary:
		return {"asset": {}, "error": "The Asset Store answered something unexpected."}
	return {"asset": parse_details(asset_id, response.data), "error": ""}


## Releases del asset para esta versión de Godot, de la más nueva a la más vieja:
## `{releases: [{version, stable, min_godot, max_godot, date, download_url, size_mb}], error}`.
func releases(asset_id: String) -> Dictionary:
	if not is_valid_id(asset_id):
		return {"releases": [], "error": "The asset id must be publisher/slug (as asset_search shows it)."}
	var response := await _fetch_json("releases/%s/" % asset_id)
	if not response.error.is_empty():
		return {"releases": [], "error": response.error}
	if not response.data is Array:
		return {"releases": [], "error": "The Asset Store answered something unexpected."}
	return {"releases": compatible_releases(response.data, Engine.get_version_info()), "error": ""}


## Baja el zip de una release (sus links vencen a los 10 minutos: pedir releases() justo antes).
## `{ok, zip, error}`.
func download(asset_id: String, release: Dictionary) -> Dictionary:
	var stage := ProjectSettings.globalize_path(STAGE_DIR)
	DirAccess.make_dir_recursive_absolute(stage)
	var zip_path := stage.path_join("%s.zip" % asset_id.replace("/", "__"))
	var response := await _fetch(str(release.download_url), zip_path)
	if not response.error.is_empty():
		DirAccess.remove_absolute(zip_path)
		return {"ok": false, "zip": "", "error": response.error}
	return {"ok": true, "zip": zip_path, "error": ""}


## Primer paso de instalar: elige la release (`version` o la estable más nueva para esta versión
## de Godot), baja el zip y arma el plan. `{ok, asset_id, release, zip, plan, update, error}`.
## Con `update`, los archivos de las carpetas de addons/ que ya tiene el proyecto se reemplazan y
## `plan.stale` lista los de la versión anotada que la nueva ya no trae.
func prepare(asset_id: String, version: String = "", only_addons: bool = true, update: bool = false) -> Dictionary:
	var fail := func(message: String) -> Dictionary:
		return {"ok": false, "asset_id": asset_id, "release": {}, "zip": "", "plan": {}, "error": message}
	var listed := await releases(asset_id)
	if not listed.error.is_empty():
		return fail.call(listed.error)
	var release := pick_release(listed.releases, version)
	if release.is_empty():
		if version.is_empty():
			return fail.call("%s has no release for Godot %s." % [asset_id, Engine.get_version_info().string])
		return fail.call("%s has no release %s for this Godot version. Available: %s." % [
			asset_id, version, ", ".join(PackedStringArray(listed.releases.map(func(r: Dictionary) -> String: return r.version)))])
	var downloaded := await download(asset_id, release)
	if not downloaded.ok:
		return fail.call(downloaded.error)
	var plan := plan_install(downloaded.zip, only_addons)
	if not plan.error.is_empty():
		return fail.call(plan.error)
	if update:
		var entry: Dictionary = read_manifest(manifest_path).get(asset_id, {})
		plan = plan_install(downloaded.zip, only_addons, "res://", addon_folders(plan))
		plan.stale = stale_files(entry, plan)
	return {"ok": true, "asset_id": asset_id, "release": release, "zip": downloaded.zip, "plan": plan, "update": update, "error": ""}


## Segundo paso: escribe los archivos, hace que el editor los vea, anota la instalación y, con
## `enable_plugins`, activa los plugins que trae. En una actualización, los plugins que estaban
## activos se apagan antes de reemplazar sus scripts y se vuelven a prender después.
## `{ok, written, removed, enabled: [path], error}`.
func finish(prepared: Dictionary, enable_plugins: bool) -> Dictionary:
	var plan: Dictionary = prepared.plan
	var was_enabled: PackedStringArray = []
	if Engine.is_editor_hint() and prepared.get("update", false):
		for path: String in plan.plugins:
			if EditorInterface.is_plugin_enabled(path):
				EditorInterface.set_plugin_enabled(path, false)
				was_enabled.append(path)
	var installed := install(prepared.zip, plan)
	DirAccess.remove_absolute(prepared.zip)
	if not installed.ok:
		return {"ok": false, "written": installed.written, "removed": 0, "enabled": [], "error": installed.error}
	var removed := 0
	for path: String in plan.get("stale", []):
		if DirAccess.remove_absolute(path) == OK:
			removed += 1
	var manifest := read_manifest(manifest_path)
	manifest[prepared.asset_id] = manifest_entry(str(prepared.release.version), plan)
	write_manifest(manifest_path, manifest)
	var enabled: PackedStringArray = []
	if Engine.is_editor_hint():
		await _scan(plan)
		for path: String in plan.plugins:
			if enable_plugins or path in was_enabled:
				EditorInterface.set_plugin_enabled(path, true)
				if EditorInterface.is_plugin_enabled(path):
					enabled.append(path)
	return {"ok": true, "written": installed.written, "removed": removed, "enabled": enabled, "error": ""}


## Versiones nuevas de los plugins del proyecto. Para cada carpeta de addons/ busca su asset en lo
## anotado al instalar o, si se instaló a mano, por el nombre del plugin, y compara la versión
## instalada con la release estable más nueva para esta versión de Godot.
## `{updates: [{folder, name, asset_id, installed, latest, guessed}], checked, error}`.
func check_updates(plugins: Array[Dictionary]) -> Dictionary:
	var manifest := read_manifest(manifest_path)
	var updates: Array[Dictionary] = []
	var seen := {}
	var checked := 0
	var last_error := ""
	for plugin: Dictionary in plugins:
		var top := str(plugin.folder).get_slice("/", 0)
		if top in PROTECTED_FOLDERS or seen.has(top):
			continue
		seen[top] = true
		var asset_id := manifest_asset_for(manifest, top)
		var installed := str(manifest.get(asset_id, {}).get("version", "")) if not asset_id.is_empty() else str(plugin.version)
		var guessed := asset_id.is_empty()
		if guessed:
			if installed.is_empty():
				continue  # sin versión no hay con qué comparar
			var found := await search(str(plugin.name))
			if not found.error.is_empty():
				last_error = found.error
				continue
			asset_id = match_asset(plugin, found.assets)
			if asset_id.is_empty():
				continue
		var listed := await releases(asset_id)
		if not listed.error.is_empty():
			last_error = listed.error
			continue
		checked += 1
		var latest := pick_release(listed.releases)
		if not latest.is_empty() and AddonUpdater.compare_versions(str(latest.version), installed) > 0:
			updates.append({"folder": top, "name": str(plugin.name), "asset_id": asset_id,
				"installed": installed, "latest": str(latest.version), "guessed": guessed})
	return {"updates": updates, "checked": checked, "error": last_error}


## Hace que el editor vea e importe los archivos nuevos, y espera a que registre sus uids y termine
## de importarlos: un plugin que hace preload("uid://…") de un ícono falla al activarlo si el ícono
## todavía no se importó.
func _scan(plan: Dictionary) -> void:
	var filesystem := EditorInterface.get_resource_filesystem()
	filesystem.scan()
	var uids := expected_uids(plan)
	var deadline := Time.get_ticks_msec() + int(SCAN_TIMEOUT_S * 1000)
	await get_tree().process_frame
	var outputs := import_outputs(plan)
	while Time.get_ticks_msec() < deadline and (filesystem.is_scanning()
			or not uids.all(func(id: int) -> bool: return ResourceUID.has_id(id))
			or not Array(outputs).all(func(path: String) -> bool: return FileAccess.file_exists(path))):
		await get_tree().process_frame


# --- estático (testeable sin red) ----------------------------------------------------------------

static func is_valid_id(asset_id: String) -> bool:
	var parts := asset_id.split("/", false)
	if parts.size() != 2:
		return false
	for part: String in parts:
		if not part.is_valid_filename() or part.begins_with(".") or part.contains(" "):
			return false
	return true


## Ruta de search/query como la arma el editor: texto en minúsculas, solo assets (no templates),
## con al menos una release y compatibles con `version` (Engine.get_version_info()).
static func search_path(query: String, page: int, sort: String, version: Dictionary) -> String:
	var compatibility := "%d.%d" % [int(version.get("major", 4)), int(version.get("minor", 0))]
	if int(version.get("patch", 0)) > 0:
		compatibility += ".%d" % int(version.patch)
	var path := "search/query/?query=%s&require_release=true&type=0&sort=%s&compatibility=%s" % [
		query.strip_edges().to_lower().uri_encode(), sort if sort in SORTS else "relevance", compatibility]
	if page > 1:
		path += "&page=%d" % page
	return path


## `[{id, name, publisher, description, license, score, price_cent, store_url, thumbnail}]`.
static func parse_hits(hits: Variant) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not hits is Array:
		return result
	for hit: Variant in hits:
		var asset: Variant = hit.get("asset") if hit is Dictionary else null
		if not asset is Dictionary:
			continue
		var publisher: Dictionary = asset.get("publisher") if asset.get("publisher") is Dictionary else {}
		var id := "%s/%s" % [publisher.get("slug", ""), asset.get("slug", "")]
		if not is_valid_id(id):
			continue
		result.append({
			"id": id,
			"name": str(asset.get("name", id)),
			"publisher": str(publisher.get("name", publisher.get("slug", ""))),
			"description": one_line(str(asset.get("description", ""))),
			"license": str(asset.get("license_type", "")),
			"score": int(asset.get("reviews_score", 0)),
			"price_cent": int(asset.get("price_cent", 0)),
			"store_url": str(asset.get("store_url", "")),
			"thumbnail": str(asset.get("thumbnail", "")),
		})
	return result


## La descripción corta de un resultado en una línea: algunas traen párrafos y líneas en blanco.
static func one_line(text: String, limit: int = DESCRIPTION_LIMIT) -> String:
	var spaces := RegEx.create_from_string("\\s+")
	var line := spaces.sub(text, " ", true).strip_edges()
	return line if line.length() <= limit else line.left(limit).strip_edges() + "…"


static func parse_details(asset_id: String, data: Dictionary) -> Dictionary:
	var publisher: Dictionary = data.get("publisher") if data.get("publisher") is Dictionary else {}
	var tags: PackedStringArray = []
	for tag: Variant in data.get("tags", []):
		if tag is Dictionary:
			tags.append(str(tag.get("display_name", tag.get("slug", ""))))
	var body := bbcode_to_text(str(data.get("body_bbcode", "")))
	if body.length() > BODY_LIMIT:
		body = body.left(BODY_LIMIT) + "…"
	return {
		"id": asset_id,
		"name": str(data.get("name", asset_id)),
		"publisher": str(publisher.get("name", publisher.get("slug", ""))),
		"description": str(data.get("description", "")).strip_edges(),
		"body": body,
		"license": str(data.get("license_type", "")),
		"tags": tags,
		"source": str(data.get("source", "")) if data.get("source") is String else "",
		"store_url": str(data.get("store_url", "")),
		"price_cent": int(str(data.get("price_cent", 0))),
	}


## Texto plano de la ficha: sin etiquetas BBCode, con las listas como guiones.
static func bbcode_to_text(bbcode: String) -> String:
	var text := bbcode.replace("[*]", "\n- ").replace("[li]", "\n- ")
	var tags := RegEx.create_from_string("\\[/?[a-zA-Z_]+(=[^\\]]*)?[^\\]]*\\]")
	text = tags.sub(text, "", true)
	var blank_lines := RegEx.create_from_string("\\n{3,}")
	return blank_lines.sub(text, "\n\n", true).strip_edges()


## Las releases que sirven para `version` (dentro de min/max_godot_version), en el orden de la API
## (la más nueva primero).
static func compatible_releases(list: Array, version: Dictionary) -> Array[Dictionary]:
	var current := "%d.%d.%d" % [int(version.get("major", 4)), int(version.get("minor", 0)), int(version.get("patch", 0))]
	var result: Array[Dictionary] = []
	for item: Variant in list:
		if not item is Dictionary or str(item.get("download_url", "")).is_empty():
			continue
		var low: Variant = item.get("min_godot_version")
		var high: Variant = item.get("max_godot_version")
		if low is String and not low.is_empty() and _compare_to_bound(current, low) < 0:
			continue
		if high is String and not high.is_empty() and _compare_to_bound(current, high) > 0:
			continue
		result.append({
			"version": str(item.get("version", "")),
			"stable": bool(item.get("stable", true)),
			"min_godot": str(low) if low is String else "",
			"max_godot": str(high) if high is String else "",
			"date": str(item.get("created", "")),
			"download_url": str(item.download_url),
			"size_mb": float(item.get("size", 0.0)),
		})
	return result


## La release a instalar: la de `version` si se pide (con o sin "v"), si no la estable más nueva
## (o la más nueva si no hay estables). {} si no hay.
static func pick_release(list: Array[Dictionary], version: String = "") -> Dictionary:
	var wanted := version.strip_edges().trim_prefix("v")
	if not wanted.is_empty():
		for release: Dictionary in list:
			if str(release.version).trim_prefix("v") == wanted:
				return release
		return {}
	for release: Dictionary in list:
		if release.stable:
			return release
	return list[0] if not list.is_empty() else {}


## Qué escribiría instalar el zip en `target_root` (res:// en el editor):
## `{files: [{zip, target}], conflicts: [target], other: [target], plugins: [res://…/plugin.cfg], error}`.
## `files` son los que se escriben (`replaces` si pisan uno que existe); `conflicts` ya existen y no
## se tocan; `other` quedan afuera por no ir en addons/ (con `only_addons` y si el zip trae
## addons/). Lo que cae dentro de una carpeta de `replace` (actualizar) se pisa.
static func plan_install(zip_path: String, only_addons: bool = true, target_root: String = "res://", replace: PackedStringArray = []) -> Dictionary:
	var plan := {"files": [], "conflicts": [], "other": [], "plugins": [], "stale": [], "error": ""}
	var reader := ZIPReader.new()
	if reader.open(zip_path) != OK:
		plan.error = "The downloaded file is not a valid zip."
		return plan
	var names := reader.get_files()
	reader.close()
	var root := _toplevel(names)
	if root == "addons/":
		root = ""
	var entries: Array[Dictionary] = []
	var has_addons := false
	for name: String in names:
		if name.ends_with("/"):
			continue
		var relative := name.trim_prefix(root)
		if relative.is_empty() or relative.is_absolute_path() or ".." in relative.split("/") or relative.begins_with("/"):
			continue
		if relative.begins_with("addons/"):
			has_addons = true
		entries.append({"zip": name, "relative": relative})
	for entry: Dictionary in entries:
		var relative: String = entry.relative
		var target := target_root.path_join(relative)
		if only_addons and has_addons and not relative.begins_with("addons/"):
			plan.other.append(target)
			continue
		var exists := FileAccess.file_exists(target)
		if exists and not Array(replace).any(func(folder: String) -> bool: return target.begins_with(folder + "/")):
			plan.conflicts.append(target)
			continue
		plan.files.append({"zip": entry.zip, "target": target, "replaces": exists})
		if relative.begins_with("addons/") and relative.get_file() == "plugin.cfg":
			plan.plugins.append(target)
	if entries.is_empty():
		plan.error = "The zip is empty."
	return plan


## Escribe los archivos del plan. `{ok, written, error}`.
static func install(zip_path: String, plan: Dictionary) -> Dictionary:
	var reader := ZIPReader.new()
	if reader.open(zip_path) != OK:
		return {"ok": false, "written": 0, "error": "The downloaded file is not a valid zip."}
	var written := 0
	for entry: Dictionary in plan.files:
		var target: String = entry.target
		DirAccess.make_dir_recursive_absolute(target.get_base_dir())
		var file := FileAccess.open(target, FileAccess.WRITE)
		if file == null:
			reader.close()
			return {"ok": false, "written": written, "error": "Could not write %s." % target}
		file.store_buffer(reader.read_file(entry.zip))
		file.close()
		written += 1
	reader.close()
	return {"ok": true, "written": written, "error": ""}


## Los assets anotados cuyas carpetas siguen en el proyecto: id -> versión (si se borró la carpeta a
## mano, ya no está instalado).
static func installed_assets(path: String) -> Dictionary:
	var result := {}
	var manifest := read_manifest(path)
	for asset_id: String in manifest:
		var entry: Variant = manifest[asset_id]
		if entry is Dictionary and (entry.get("folders", []) as Array).any(func(folder: Variant) -> bool: return DirAccess.dir_exists_absolute(str(folder))):
			result[asset_id] = str(entry.get("version", ""))
	return result


## Uids que declaran los archivos instalados: los `.uid` de los scripts y el `uid="uid://…"` del
## encabezado de `.import`, `.tscn` y `.tres`.
static func expected_uids(plan: Dictionary) -> Array[int]:
	var result: Array[int] = []
	var header := RegEx.create_from_string("uid=\"(uid://[a-z0-9]+)\"")
	for entry: Dictionary in plan.files:
		var target := str(entry.target)
		var text := ""
		match target.get_extension():
			"uid":
				text = FileAccess.get_file_as_string(target).strip_edges()
			"import", "tscn", "tres":
				var found := header.search(FileAccess.get_file_as_string(target).left(1000))
				text = found.get_string(1) if found else ""
		var id := ResourceUID.text_to_id(text) if text.begins_with("uid://") else ResourceUID.INVALID_ID
		if id != ResourceUID.INVALID_ID:
			result.append(id)
	return result


## Lo que el editor genera al importar los archivos instalados: los `dest_files` de sus `.import`.
static func import_outputs(plan: Dictionary) -> PackedStringArray:
	var result: PackedStringArray = []
	for entry: Dictionary in plan.files:
		if not str(entry.target).ends_with(".import"):
			continue
		var config := ConfigFile.new()
		if config.load(entry.target) != OK:
			continue
		for path: Variant in config.get_value("deps", "dest_files", []):
			result.append(str(path))
	return result


## Carpetas de addons/ que toca el plan (`res://addons/x`), con lo que escribe y lo que ya existe.
static func addon_folders(plan: Dictionary) -> PackedStringArray:
	var result: PackedStringArray = []
	var targets: Array = plan.files.map(func(entry: Dictionary) -> String: return entry.target) + Array(plan.conflicts)
	for target: String in targets:
		var at := target.find("/addons/")
		if at < 0:
			continue
		var folder := target.left(at + "/addons/".length()) + target.substr(at + "/addons/".length()).get_slice("/", 0)
		if not folder in result and folder != target:
			result.append(folder)
	return result


## Lo que se anota de una instalación: versión, carpetas de addons/ y archivos escritos.
static func manifest_entry(version: String, plan: Dictionary) -> Dictionary:
	return {
		"version": version,
		"folders": Array(addon_folders(plan)),
		"files": plan.files.map(func(entry: Dictionary) -> String: return entry.target),
	}


## Archivos de la versión anotada que la nueva ya no trae (solo dentro de sus carpetas de addons/).
static func stale_files(entry: Dictionary, plan: Dictionary) -> PackedStringArray:
	var result: PackedStringArray = []
	var new_files := {}
	for file: Dictionary in plan.files:
		new_files[file.target] = true
	var folders: Array = entry.get("folders", [])
	for path: Variant in entry.get("files", []):
		var file := str(path)
		if not new_files.has(file) and folders.any(func(folder: String) -> bool: return file.begins_with(folder + "/")) and FileAccess.file_exists(file):
			result.append(file)
	return result


static func read_manifest(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return data if data is Dictionary else {}


static func write_manifest(path: String, manifest: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(manifest, "\t", true))
		file.close()


## El asset anotado que instaló `addons/<folder>` ("" si no hay).
static func manifest_asset_for(manifest: Dictionary, folder: String) -> String:
	for asset_id: String in manifest:
		var entry: Variant = manifest[asset_id]
		if entry is Dictionary and (entry.get("folders", []) as Array).any(func(path: Variant) -> bool: return str(path).get_file() == folder):
			return asset_id
	return ""


## El resultado de una búsqueda que es este plugin instalado a mano: mismo nombre o slug igual a la
## carpeta (sin mayúsculas ni signos). "" si ninguno coincide.
static func match_asset(plugin: Dictionary, assets: Array[Dictionary]) -> String:
	var name := _simplify(str(plugin.name))
	var folder := _simplify(str(plugin.folder).get_slice("/", 0))
	for asset: Dictionary in assets:
		if _simplify(str(asset.name)) == name or _simplify(str(asset.id).get_slice("/", 1)) == folder:
			return str(asset.id)
	return ""


static func _simplify(text: String) -> String:
	var result := ""
	for character in text.to_lower():
		if character.is_valid_identifier() or character.is_valid_int():
			result += character
	return result.replace("_", "")


## Plugins del proyecto: `[{path, folder, name, version, description, author}]`, por carpeta.
## `addons_dir` es res://addons en el editor. Mira hasta dos niveles (addons/x/ y addons/x/y/).
static func project_plugins(addons_dir: String = "res://addons") -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not DirAccess.dir_exists_absolute(addons_dir):
		return result
	var folders := Array(DirAccess.get_directories_at(addons_dir))
	folders.sort()
	for folder: String in folders:
		var candidates: PackedStringArray = [folder]
		for sub: String in DirAccess.get_directories_at(addons_dir.path_join(folder)):
			candidates.append(folder.path_join(sub))
		for candidate: String in candidates:
			var path := addons_dir.path_join(candidate).path_join("plugin.cfg")
			if not FileAccess.file_exists(path):
				continue
			var config := ConfigFile.new()
			if config.load(path) != OK:
				continue
			result.append({
				"path": path,
				"folder": candidate,
				"name": str(config.get_value("plugin", "name", candidate)),
				"version": str(config.get_value("plugin", "version", "")),
				"description": str(config.get_value("plugin", "description", "")),
				"author": str(config.get_value("plugin", "author", "")),
			})
	return result


## Carpeta raíz común del zip ("carpeta/") o "" si no hay una (como el instalador del editor).
static func _toplevel(names: PackedStringArray) -> String:
	if names.is_empty():
		return ""
	var first := names[0]
	var slash := first.find("/")
	if slash < 0:
		return ""
	var root := first.left(slash + 1)
	for name: String in names:
		if not name.begins_with(root):
			return ""
	return root


## Compara la versión actual con una cota del store ("4.6", "4.7.2") con la precisión de la cota:
## 4.7.2 está dentro de un máximo "4.7".
static func _compare_to_bound(current: String, bound: String) -> int:
	var parts := bound.strip_edges().split(".")
	var trimmed := ".".join(current.split(".").slice(0, parts.size()))
	return AddonUpdater.compare_versions(trimmed, bound)


func _fetch_json(path: String) -> Dictionary:
	var response := await _fetch(API + "/" + path)
	if not response.error.is_empty():
		return {"data": null, "error": response.error}
	var json := JSON.new()
	if json.parse(response.body.get_string_from_utf8()) != OK:
		return {"data": null, "error": "The Asset Store answered something unexpected."}
	return {"data": json.data, "error": ""}


## `{body: PackedByteArray, error}`. Un HTTPRequest por pedido: la pestaña y las tools del agente
## pueden pedir a la vez. Con `download_file`, el cuerpo va a ese archivo.
func _fetch(url: String, download_file: String = "") -> Dictionary:
	var http := HTTPRequest.new()
	http.timeout = TIMEOUT_S
	http.download_file = download_file
	add_child(http)
	var headers := PackedStringArray(["User-Agent: godot-agent-harness/%s (Godot %s)" % [AddonVersion.version(), Engine.get_version_info().string]])
	if http.request(url, headers) != OK:
		http.queue_free()
		return {"body": PackedByteArray(), "error": "Could not connect to the Asset Store."}
	var result: Array = await http.request_completed
	http.queue_free()
	if int(result[0]) != HTTPRequest.RESULT_SUCCESS:
		return {"body": PackedByteArray(), "error": "No connection to the Asset Store (%d)." % int(result[0])}
	if int(result[1]) == 404:
		return {"body": PackedByteArray(), "error": "The Asset Store has no such asset."}
	if int(result[1]) != 200:
		return {"body": PackedByteArray(), "error": "The Asset Store answered %d." % int(result[1])}
	return {"body": result[3], "error": ""}
