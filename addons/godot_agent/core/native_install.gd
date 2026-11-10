@tool
extends RefCounted
## Llevar la GDExtension probada al juego (m19-05). test_extension la prueba en su proyecto de
## prueba (project/, demo/, godot/); el juego la usa como addon (`addons/<ext>/` con el
## `.gdextension` y las bibliotecas). Esto arma el addon desde el proyecto de prueba, reescribe las
## rutas `res://` al lugar nuevo, lo revisa como `check_gdextension.py` de la skill gdextension-build
## y lo deja preparado en `.godot/agent_supervisor/pending/`.
##
## Preparado y no copiado: el editor abierto registra y carga un `.gdextension` nuevo cuando escanea
## los archivos, y recarga uno con `reloadable = true` cuando cambia su biblioteca; un crash ahí lo
## tira abajo con el agente. Los archivos entran al juego en el reinicio: el supervisor los mueve
## antes de abrir el editor nuevo (y si crashea al arrancar, hace rollback a la build buena), o el
## plugin justo antes de reiniciar sin supervisor. Sin rutas res:// propias: lo usa el supervisor.

const PENDING_DIR := "pending"
const PENDING_MANIFEST := "pending.json"
const OLD_SUFFIX := ".old"
const TMP_SUFFIX := ".installing"

const PLATFORMS: PackedStringArray = ["linux", "windows", "macos", "android", "ios", "web", "visionos"]
const ARCHES: PackedStringArray = ["x86_32", "x86_64", "arm32", "arm64", "rv64", "wasm32", "universal", "ppc64"]
## Secciones del .gdextension con rutas a archivos que van con el addon.
const PATH_SECTIONS: PackedStringArray = ["libraries", "icons"]


## Los `.gdextension` del proyecto de prueba que no son de este addon (rutas res://).
static func test_extensions(test_dir: String) -> PackedStringArray:
	var result: PackedStringArray = []
	for path: String in _gdextension_files(_strip_slash(test_dir), "res://"):
		if not path.begins_with("res://addons/godot_agent/"):
			result.append(path)
	return result


## Arma el plan de instalación. `gdextension`: res:// del proyecto de prueba; `target`: res:// del
## juego, o "" para el lugar por defecto (la carpeta donde el juego ya tiene un `.gdextension` con
## ese nombre, o `res://addons/<nombre>/`). Devuelve
## `{error, source, target, gdextension_text, files: [{from, to}], new_extension}` con `from`
## absoluta en el proyecto de prueba y `to` relativa a la raíz del juego.
static func plan(test_dir: String, gdextension: String, game_dir: String, target: String = "") -> Dictionary:
	var test_root := _strip_slash(test_dir)
	var game_root := _strip_slash(game_dir)
	var result := {"error": "", "source": "", "target": "", "gdextension_text": "", "files": [], "new_extension": false}
	var gdext_abs := test_root.path_join(gdextension.trim_prefix("res://"))
	var text := FileAccess.get_file_as_string(gdext_abs)
	var config := ConfigFile.new()
	if text.is_empty() or config.parse(text) != OK:
		result.error = "Can't read %s in %s." % [gdextension, test_root]
		return result
	# La carpeta del addon: addons/<x>/ entera si ya está armado así; si no, la del .gdextension (bin/).
	var source_rel := gdextension.trim_prefix("res://").get_base_dir()
	var parts := source_rel.split("/", false)
	if parts.size() >= 2 and parts[0] == "addons":
		source_rel = "addons/" + parts[1]
	if source_rel.is_empty():
		result.error = "%s is at the root of the test project: put it with its libraries in a folder (bin/ or addons/<name>/) to install it as an addon." % gdextension
		return result
	var name := gdextension.get_file().get_basename()
	var target_rel := target.strip_edges().trim_prefix("res://").trim_suffix("/")
	if target_rel.is_empty():
		var existing := Array(_gdextension_files(game_root, "")).filter(func(path: String) -> bool: return path.get_file() == gdextension.get_file())
		target_rel = (existing[0] as String).get_base_dir() if not existing.is_empty() else "addons/" + name
		result.new_extension = existing.is_empty()
	else:
		result.new_extension = not FileAccess.file_exists(game_root.path_join(target_rel).path_join(gdextension.get_file()))
	if target_rel.begins_with("addons/godot_agent") or target_rel.begins_with(".") or target_rel.contains(".."):
		result.error = "Can't install into res://%s." % target_rel
		return result
	result.source = "res://" + source_rel
	result.target = "res://" + target_rel
	var source_abs := test_root.path_join(source_rel)
	var files: Array = []
	var seen: Dictionary = {}
	var add := func(from_abs: String) -> void:
		if seen.has(from_abs):
			return
		seen[from_abs] = true
		files.append({"from": from_abs, "to": target_rel.path_join(from_abs.trim_prefix(source_abs + "/"))})
	var gdext_dir := gdext_abs.get_base_dir()
	var outside: PackedStringArray = []
	for value: String in referenced_paths(config):
		var full := _resolve(value, gdext_dir, test_root)
		if not full.begins_with(source_abs + "/"):
			outside.append(value)
		elif FileAccess.file_exists(full):
			add.call(full)
	if not outside.is_empty():
		result.error = "%s points outside %s, so those files wouldn't go with the addon: %s. Move them into %s/ (the skill layout is bin/<platform>/ next to the .gdextension)." % [gdextension, result.source, ", ".join(outside), result.source]
		return result
	if source_rel.begins_with("addons/"):
		for file: String in _all_files(source_abs):
			add.call(file)
	else:
		add.call(gdext_abs)
		if FileAccess.file_exists(gdext_abs + ".uid"):
			add.call(gdext_abs + ".uid")
	files.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a.to) < str(b.to))
	result.files = files
	result.gdextension_text = rewrite_paths(text, source_rel, target_rel)
	return result


## Las rutas `res://<from>/…` del `.gdextension` pasan a `res://<to>/…`. Las relativas no cambian.
static func rewrite_paths(text: String, from_rel: String, to_rel: String) -> String:
	if from_rel == to_rel:
		return text
	return text.replace("\"res://%s/" % from_rel, "\"res://%s/" % to_rel)


## Las rutas a archivos de [libraries], [icons] y las claves de [dependencies].
static func referenced_paths(config: ConfigFile) -> PackedStringArray:
	var result: PackedStringArray = []
	for section: String in PATH_SECTIONS:
		if config.has_section(section):
			for key: String in config.get_section_keys(section):
				var value := str(config.get_value(section, key, ""))
				if not value.is_empty() and not value in result:
					result.append(value)
	if config.has_section("dependencies"):
		for key: String in config.get_section_keys("dependencies"):
			var deps: Variant = config.get_value("dependencies", key)
			if deps is Dictionary:
				for dep: Variant in deps:
					if not str(dep) in result:
						result.append(str(dep))
	return result


## Revisión del `.gdextension` contra las bibliotecas (como check_gdextension.py de la skill
## gdextension-build). `gdext_dir` es la carpeta del `.gdextension` y `project_root` la raíz para
## las rutas res://. `platform` y `arch` son los de este editor. Devuelve
## `{problems, warnings, not_built}`: `problems` es lo que impide que el editor cargue la extensión
## (no instala); `warnings`, lo que la skill marca para publicar (falta la release, un archivo de otra
## plataforma, una clave debug que apunta a una release), que no frena a quien itera con template_debug.
static func check(text: String, gdext_dir: String, project_root: String, platform: String = "", arch: String = "", double: bool = false) -> Dictionary:
	var problems: PackedStringArray = []
	var warnings: PackedStringArray = []
	var not_built: PackedStringArray = []
	var config := ConfigFile.new()
	if config.parse(text) != OK:
		return {"problems": PackedStringArray(["the .gdextension can't be parsed"]), "warnings": warnings, "not_built": not_built}
	var symbol := str(config.get_value("configuration", "entry_symbol", ""))
	if symbol.is_empty():
		problems.append("[configuration] has no entry_symbol")
	var minimum := str(config.get_value("configuration", "compatibility_minimum", ""))
	if minimum.is_empty():
		problems.append("[configuration] has no compatibility_minimum")
	elif _version_greater(minimum, Engine.get_version_info()):
		problems.append("compatibility_minimum %s is newer than this Godot (%s): it won't load" % [minimum, Engine.get_version_info().string])
	if not config.has_section("libraries") or config.get_section_keys("libraries").is_empty():
		problems.append("[libraries] is empty")
		return {"problems": problems, "warnings": warnings, "not_built": not_built}
	var groups: Dictionary = {}  # "platform.arch.variant" -> [{key, path, build, full, exists, here}]
	for key: String in config.get_section_keys("libraries"):
		var tags := key.split(".")
		var key_platform := _first_in(tags, PLATFORMS)
		if key_platform.is_empty():
			warnings.append("%s: no platform tag (one of %s)" % [key, ", ".join(PLATFORMS)])
			continue
		var key_arch := _first_in(tags, ARCHES)
		var variant: PackedStringArray = []
		for tag: String in tags:
			if tag in ["single", "double", "threads", "nothreads"]:
				variant.append(tag)
		variant.sort()
		var label_tags := PackedStringArray([key_platform])
		if not key_arch.is_empty():
			label_tags.append(key_arch)
		var label := ".".join(label_tags + variant)
		var path := str(config.get_value("libraries", key))
		var full := _resolve(path, gdext_dir, project_root)
		# La que carga este editor: su plataforma y arquitectura, y su precisión.
		var here := key_platform == platform and (key_arch.is_empty() or key_arch == arch) and not ("double" in variant and not double) and not ("single" in variant and double)
		if not groups.has(label):
			groups[label] = []
		groups[label].append({"key": key, "path": path, "build": _first_in(tags, PackedStringArray(["debug", "release", "editor"])), "full": full, "exists": FileAccess.file_exists(full) or DirAccess.dir_exists_absolute(full), "here": here})
	var here_loaded := false
	var labels := groups.keys()
	labels.sort()
	for label: String in labels:
		var entries: Array = groups[label]
		var is_here := entries.any(func(e: Dictionary) -> bool: return e.here)
		var built := entries.any(func(e: Dictionary) -> bool: return e.exists)
		if not built and not is_here:
			not_built.append(label)
			continue
		var builds: PackedStringArray = []
		for entry: Dictionary in entries:
			var file := str(entry.path).get_file()
			var loaded_here: bool = entry.here and entry.build in ["debug", "editor", ""]
			if entry.build == "release" and file.contains("template_debug"):
				warnings.append("%s is a release key but points to a debug library: %s" % [entry.key, entry.path])
			if entry.build == "debug" and file.contains("template_release"):
				warnings.append("%s is a debug key but points to a release library: %s" % [entry.key, entry.path])
			if not entry.build in builds:
				builds.append(entry.build)
			if not entry.exists:
				var missing := "%s: file not found: %s%s" % [entry.key, entry.path, _prefix_hint(entry.full)]
				if not loaded_here:
					warnings.append(missing)
				continue
			if loaded_here:
				here_loaded = true
			if not symbol.is_empty() and FileAccess.file_exists(entry.full) and not _file_contains(entry.full, symbol):
				(problems if loaded_here else warnings).append("%s: entry_symbol %s not found in %s" % [entry.key, symbol, entry.path])
		if not "" in builds:
			if not "release" in builds:
				warnings.append("%s has a debug library but no release key: release exports won't load it" % label)
			if not "debug" in builds and not "editor" in builds:
				warnings.append("%s has a release library but no debug key: the editor won't load it" % label)
	if not platform.is_empty() and not here_loaded:
		problems.append("no library this editor can load on %s.%s (a debug or editor key whose file exists)" % [platform, arch])
	if config.has_section("dependencies"):
		for key: String in config.get_section_keys("dependencies"):
			var deps: Variant = config.get_value("dependencies", key)
			if not deps is Dictionary:
				warnings.append("[dependencies] %s: value must be a { \"path\": \"target dir\" } dictionary" % key)
				continue
			var dep_tags := key.split(".")
			var dep_arch := _first_in(dep_tags, ARCHES)
			var dep_here := _first_in(dep_tags, PLATFORMS) == platform and (dep_arch.is_empty() or dep_arch == arch) and not "release" in dep_tags
			for dep: Variant in deps:
				if not FileAccess.file_exists(_resolve(str(dep), gdext_dir, project_root)):
					(problems if dep_here else warnings).append("[dependencies] %s: file not found: %s" % [key, dep])
	return {"problems": problems, "warnings": warnings, "not_built": not_built}


## Revisa lo preparado como va a quedar en el juego: `pending/` tiene la misma estructura que el
## juego, así que las rutas res:// reescritas se resuelven contra esa carpeta.
static func check_staged(planned: Dictionary, state_dir: String) -> Dictionary:
	var pending_root := state_dir.path_join(PENDING_DIR)
	var gdext := pending_root.path_join(_gdextension_target(planned))
	return check(planned.gdextension_text, gdext.get_base_dir(), pending_root, OS.get_name().to_lower(), _arch(), OS.has_feature("double"))


## Deja el plan en `<state_dir>/pending/` (con el `.gdextension` reescrito) y lo anota en
## pending.json. Reemplaza lo que hubiera preparado antes. Devuelve "" o el error.
static func stage(planned: Dictionary, state_dir: String) -> String:
	var pending := state_dir.path_join(PENDING_DIR)
	_remove_tree(pending)
	var staged: PackedStringArray = []
	for file: Dictionary in planned.files:
		var to := pending.path_join(str(file.to))
		DirAccess.make_dir_recursive_absolute(to.get_base_dir())
		var error := OK
		if str(file.to) == _gdextension_target(planned):
			var handle := FileAccess.open(to, FileAccess.WRITE)
			error = FileAccess.get_open_error() if handle == null else OK
			if handle:
				handle.store_string(planned.gdextension_text)
				handle.close()
		else:
			error = DirAccess.copy_absolute(str(file.from), to)
		if error != OK:
			_remove_tree(pending)
			return "Could not stage %s: %s" % [file.to, error_string(error)]
		staged.append(str(file.to))
	var manifest := FileAccess.open(state_dir.path_join(PENDING_MANIFEST), FileAccess.WRITE)
	if manifest == null:
		return "Could not write %s." % state_dir.path_join(PENDING_MANIFEST)
	manifest.store_string(JSON.stringify({"files": Array(staged), "target": planned.target, "source": planned.source, "time": Time.get_datetime_string_from_system()}, "\t"))
	manifest.close()
	return ""


## Lo preparado, o {} si no hay nada.
static func pending(state_dir: String) -> Dictionary:
	var path := state_dir.path_join(PENDING_MANIFEST)
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}


## Mueve lo preparado al juego (con el editor cerrado o a punto de cerrarse). Cada archivo entra por
## rename, así un editor que todavía tiene mapeada la biblioteca vieja no ve el cambio; en Windows,
## donde una DLL cargada no se puede pisar pero sí renombrar, la vieja queda como `.old`.
## Devuelve `{applied: [...], failed: [...]}` (relativas al juego).
static func apply_pending(project_dir: String, state_dir: String) -> Dictionary:
	var root := _strip_slash(project_dir)
	var manifest := pending(state_dir)
	var applied: PackedStringArray = []
	var failed: PackedStringArray = []
	if manifest.is_empty():
		return {"applied": applied, "failed": failed}
	var staged := state_dir.path_join(PENDING_DIR)
	for relative: Variant in manifest.get("files", []):
		var from := staged.path_join(str(relative))
		var to := root.path_join(str(relative))
		if not FileAccess.file_exists(from):
			failed.append(str(relative))
			continue
		DirAccess.make_dir_recursive_absolute(to.get_base_dir())
		if _replace(from, to) == OK:
			applied.append(str(relative))
		else:
			failed.append(str(relative))
	_remove_tree(staged)
	DirAccess.remove_absolute(state_dir.path_join(PENDING_MANIFEST))
	return {"applied": applied, "failed": failed}


static func discard_pending(state_dir: String) -> void:
	_remove_tree(state_dir.path_join(PENDING_DIR))
	DirAccess.remove_absolute(state_dir.path_join(PENDING_MANIFEST))


static func _replace(from: String, to: String) -> Error:
	# Mismo disco (pending/ está en .godot del juego): rename es atómico y no toca el inode viejo.
	var tmp := to + TMP_SUFFIX
	DirAccess.remove_absolute(tmp)
	var error := DirAccess.rename_absolute(from, tmp)
	if error != OK:
		error = DirAccess.copy_absolute(from, tmp)
		if error != OK:
			return error
	error = DirAccess.rename_absolute(tmp, to)
	if error != OK and FileAccess.file_exists(to):
		DirAccess.remove_absolute(to + OLD_SUFFIX)
		if DirAccess.rename_absolute(to, to + OLD_SUFFIX) == OK:
			error = DirAccess.rename_absolute(tmp, to)
	if error != OK:
		DirAccess.remove_absolute(tmp)
	return error


static func _gdextension_target(planned: Dictionary) -> String:
	for file: Dictionary in planned.files:
		if str(file.to).get_extension() == "gdextension":
			return str(file.to)
	return ""


static func _resolve(path: String, gdext_dir: String, project_root: String) -> String:
	if path.begins_with("res://"):
		return _strip_slash(project_root).path_join(path.trim_prefix("res://")).simplify_path()
	if path.is_absolute_path():
		return path.simplify_path()
	return gdext_dir.path_join(path).simplify_path()


static func _first_in(tags: PackedStringArray, options: PackedStringArray) -> String:
	for tag: String in tags:
		if tag in options:
			return tag
	return ""


static func _version_greater(minimum: String, info: Dictionary) -> bool:
	var parts := minimum.split(".")
	var mine := [int(info.major), int(info.minor), int(info.patch)]
	for i: int in mini(parts.size(), 3):
		var wanted := int(parts[i])
		if wanted != mine[i]:
			return wanted > mine[i]
	return false


static func _arch() -> String:
	for arch: String in ["x86_64", "arm64", "x86_32", "arm32", "rv64", "ppc64", "wasm32"]:
		if OS.has_feature(arch):
			return arch
	return ""


static func _prefix_hint(full: String) -> String:
	var file := full.get_file()
	var other := file.substr(3) if file.begins_with("lib") else "lib" + file
	if FileAccess.file_exists(full.get_base_dir().path_join(other)):
		return " (%s exists: MinGW keeps the lib prefix, MSVC drops it)" % other
	return ""


static func _file_contains(path: String, needle: String) -> bool:
	var handle := FileAccess.open(path, FileAccess.READ)
	if handle == null:
		return false
	# En hex, para buscar con String.find (nativo) sin cortar en los bytes nulos; un match en una
	# posición impar cae entre dos bytes y no cuenta.
	var wanted := needle.to_utf8_buffer().hex_encode()
	var carry := ""
	while handle.get_position() < handle.get_length():
		var data := carry + handle.get_buffer(1 << 20).hex_encode()
		var index := data.find(wanted)
		while index >= 0:
			if index % 2 == 0:
				return true
			index = data.find(wanted, index + 1)
		carry = data.substr(maxi(data.length() - wanted.length() + 2, 0))
		if carry.length() % 2 == 1:
			carry = carry.substr(1)
	return false


static func _gdextension_files(dir: String, prefix: String) -> PackedStringArray:
	var result: PackedStringArray = []
	if FileAccess.file_exists(dir.path_join(".gdignore")):
		return result
	for file: String in DirAccess.get_files_at(dir):
		if file.get_extension() == "gdextension":
			result.append(prefix + file)
	for sub: String in DirAccess.get_directories_at(dir):
		if not sub.begins_with("."):
			result.append_array(_gdextension_files(dir.path_join(sub), prefix + sub + "/"))
	return result


static func _all_files(dir: String) -> PackedStringArray:
	var result: PackedStringArray = []
	for file: String in DirAccess.get_files_at(dir):
		if not file.ends_with(".crashed") and not file.ends_with(".disabled") and not file.ends_with(".import"):
			result.append(dir.path_join(file))
	for sub: String in DirAccess.get_directories_at(dir):
		if not sub.begins_with("."):
			result.append_array(_all_files(dir.path_join(sub)))
	return result


static func _remove_tree(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		return
	for file: String in DirAccess.get_files_at(path):
		DirAccess.remove_absolute(path.path_join(file))
	for sub: String in DirAccess.get_directories_at(path):
		_remove_tree(path.path_join(sub))
	DirAccess.remove_absolute(path)


static func _strip_slash(path: String) -> String:
	return path.left(-1) if path.ends_with("/") and path.length() > 1 else path
