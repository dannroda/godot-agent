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
## pending.new/ y pending.json.new mientras se prepara; .prev, lo anterior durante el cambio.
const NEW_SUFFIX := ".new"
const PREV_SUFFIX := ".prev"
## Cómo salió la última instalación (apply_pending): la falla se avisa en el dock y en project_info.
const LAST_INSTALL := "last_install.json"

const ProtectedPaths := preload("protected_paths.gd")

const PLATFORMS: PackedStringArray = ["linux", "windows", "macos", "android", "ios", "web", "visionos"]
const ARCHES: PackedStringArray = ["x86_32", "x86_64", "arm32", "arm64", "rv64", "wasm32", "universal", "ppc64"]
## Secciones del .gdextension con rutas a archivos que van con el addon.
const PATH_SECTIONS: PackedStringArray = ["libraries", "icons"]


## Los `.gdextension` del proyecto de prueba que no son de este addon (rutas res://).
static func test_extensions(test_dir: String) -> PackedStringArray:
	var result: PackedStringArray = []
	for path: String in _gdextension_files(_strip_slash(test_dir), "res://"):
		if not ProtectedPaths.is_protected(path):
			result.append(path)
	return result


## El `.gdextension` a instalar si no se pidió uno: el único del proyecto de prueba, o entre varios el
## que se llama como su carpeta de addon (`addons/<x>/<x>.gdextension`) o como la carpeta de la
## extensión (la que tiene el SConstruct, arriba del proyecto de prueba). `{path, error}`.
static func pick_gdextension(test_dir: String) -> Dictionary:
	var candidates := test_extensions(test_dir)
	if candidates.size() == 1:
		return {"path": candidates[0], "error": ""}
	if candidates.is_empty():
		return {"path": "", "error": "%s has no .gdextension. Pass `gdextension`." % test_dir}
	var repo := _strip_slash(test_dir).get_base_dir().get_file()
	var matches: PackedStringArray = []
	for path: String in candidates:
		var base := path.get_file().get_basename()
		var parts := path.trim_prefix("res://").split("/", false)
		var folder := parts[1] if parts.size() >= 3 and parts[0] == "addons" else ""
		if base == folder or base == repo:
			matches.append(path)
	if matches.size() == 1:
		return {"path": matches[0], "error": ""}
	return {"path": "", "error": "%s has several .gdextension files (%s) and %s. Pass `gdextension`." % [test_dir, ", ".join(candidates), "none is named like its addon folder" if matches.is_empty() else "more than one is named like its folder"]}


## Arma el plan de instalación. `gdextension`: res:// del proyecto de prueba; `target`: res:// del
## juego, o "" para el lugar por defecto: donde el juego ya tiene un `.gdextension` con ese nombre
## (se reemplaza ese, nunca se agrega otro), o `res://addons/<carpeta del addon o nombre>/`. Devuelve
## `{error, source, target, gdextension, gdextension_text, files: [{from, to, text?}], new_extension,
## replaces}`: `from` absoluta en el proyecto de prueba, `to` relativa a la raíz del juego, `text` el
## contenido reescrito de cada `.gdextension`; `gdextension` es el `to` del elegido y `replaces`, el
## res:// del que el juego ya tenía ("" si es nueva).
static func plan(test_dir: String, gdextension: String, game_dir: String, target: String = "") -> Dictionary:
	var test_root := _strip_slash(test_dir)
	var game_root := _strip_slash(game_dir)
	var result := {"error": "", "source": "", "target": "", "gdextension": "", "gdextension_text": "", "files": [], "new_extension": false, "replaces": ""}
	var gdext_rel := gdextension.trim_prefix("res://")
	var gdext_abs := test_root.path_join(gdext_rel)
	var text := FileAccess.get_file_as_string(gdext_abs)
	var config := ConfigFile.new()
	if text.is_empty() or config.parse(text) != OK:
		result.error = "Can't read %s in %s." % [gdextension, test_root]
		return result
	# La carpeta del addon: addons/<x>/ entera si ya está armado así; si no, la del .gdextension (bin/).
	var source_rel := gdext_rel.get_base_dir()
	var parts := source_rel.split("/", false)
	var addon_layout := parts.size() >= 2 and parts[0] == "addons"
	if addon_layout:
		source_rel = "addons/" + parts[1]
	if source_rel.is_empty():
		result.error = "%s is at the root of the test project: put it with its libraries in a folder (bin/ or addons/<name>/) to install it as an addon." % gdextension
		return result
	# Dónde queda el .gdextension dentro del addon: «lab.gdextension», o «bin/lab.gdextension» en un
	# addons/<x>/ que lo tiene en una subcarpeta.
	var gdext_sub := gdext_rel.substr(source_rel.length() + 1)
	var existing := game_copies(game_root, gdext_rel.get_file())
	if existing.size() > 1:
		result.error = "The game already has %s in several places (res://%s): Godot loads each one. Leave one and try again." % [gdext_rel.get_file(), ", res://".join(existing)]
		return result
	var target_rel := ""
	if target.strip_edges().is_empty():
		if existing.is_empty():
			target_rel = "addons/" + (parts[1] if addon_layout else gdext_rel.get_file().get_basename())
		elif existing[0].ends_with("/" + gdext_sub) and _same(existing[0].get_file(), gdext_sub.get_file()):
			target_rel = existing[0].left(-gdext_sub.length() - 1)
		else:
			result.error = "The game already has %s at res://%s, but this addon keeps it at <folder>/%s: installing it would leave two copies. Move or remove res://%s first, or pass `target`." % [gdext_rel.get_file(), existing[0], gdext_sub, existing[0]]
			return result
	else:
		var normalized := ProtectedPaths.normalize_relative(target)
		if not str(normalized.error).is_empty():
			result.error = "Can't install into %s." % normalized.error
			return result
		target_rel = normalized.rel
	if target_rel.is_empty():
		result.error = "Can't install into the root of the game (res://): pass a folder as `target`, like res://addons/%s." % gdext_rel.get_file().get_basename()
		return result
	var guard := ProtectedPaths.write_error(target_rel, game_root)
	if not guard.is_empty():
		result.error = "Can't install into res://%s: %s." % [target_rel, guard]
		return result
	result.source = "res://" + source_rel
	result.target = "res://" + target_rel
	result.gdextension = target_rel.path_join(gdext_sub)
	result.new_extension = existing.is_empty()
	result.replaces = "res://" + existing[0] if not existing.is_empty() else ""
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
	if addon_layout:
		for file: String in _all_files(source_abs):
			add.call(file)
	else:
		add.call(gdext_abs)
		if FileAccess.file_exists(gdext_abs + ".uid"):
			add.call(gdext_abs + ".uid")
	files.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a.to) < str(b.to))
	for file: Dictionary in files:
		var to := str(file.to)
		var file_guard := ProtectedPaths.write_error(to, game_root)
		if not file_guard.is_empty():
			result.error = "Can't install %s: %s." % [str(file.from).trim_prefix(test_root + "/"), file_guard]
			return result
		if to.get_extension() != "gdextension":
			continue
		# Todos los .gdextension del addon van con sus rutas reescritas, y ninguno puede quedar
		# registrado dos veces en el juego.
		file.text = rewrite_paths(FileAccess.get_file_as_string(str(file.from)), source_rel, target_rel)
		for copy: String in game_copies(game_root, to.get_file()):
			if not _same(copy, to):
				result.error = "The game already has %s at res://%s: installing into %s would register it twice. Leave `target` out to replace that one, or remove it first." % [to.get_file(), copy, result.target]
				return result
		if to == result.gdextension:
			result.gdextension_text = file.text
	result.files = files
	return result


## Los `.gdextension` con ese nombre de archivo que el juego ya tiene (relativas), donde Godot los
## registra: sin carpetas ocultas, ni con .gdignore, ni proyectos anidados, ni las protegidas.
static func game_copies(game_root: String, file_name: String) -> PackedStringArray:
	var result: PackedStringArray = []
	for path: String in _gdextension_files(_strip_slash(game_root), ""):
		if _same(path.get_file(), file_name) and not ProtectedPaths.is_protected("res://" + path):
			result.append(path)
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


## La clave de `section` que carga un Godot con esas features, como
## GDExtensionLibraryLoader::find_extension_library: entre las que tienen todas sus etiquetas como
## feature, la de más etiquetas; en un empate, la primera. "" si ninguna.
static func loaded_key(config: ConfigFile, section: String, has_feature: Callable) -> String:
	var best := ""
	var best_tags := 0
	if not config.has_section(section):
		return best
	for key: String in config.get_section_keys(section):
		var tags := key.split(".")
		var met := true
		for tag: String in tags:
			if not has_feature.call(tag.strip_edges()):
				met = false
				break
		if met and tags.size() > best_tags:
			best = key
			best_tags = tags.size()
	return best


## Las features de este editor para check(): OS.has_feature.
static func editor_features() -> Callable:
	return Callable(OS, &"has_feature")


## Revisión del `.gdextension` contra las bibliotecas (como check_gdextension.py de la skill
## gdextension-build). `gdext_dir` es la carpeta del `.gdextension` y `project_root` la raíz para
## las rutas res://. `has_feature` (Callable(tag) -> bool) son las features del editor que la va a
## cargar (editor_features()); sin él no se mira cuál carga. Devuelve `{problems, warnings, not_built}`:
## `problems` es lo que impide que este editor la cargue (no instala): ninguna clave para él, o la
## que elige no tiene archivo o no tiene el entry_symbol; `warnings`, lo que la skill marca para
## publicar (falta la release, un archivo de otra plataforma, una clave debug que apunta a una
## release), que no frena a quien itera con template_debug.
static func check(text: String, gdext_dir: String, project_root: String, has_feature: Callable = Callable()) -> Dictionary:
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
	var here := loaded_key(config, "libraries", has_feature) if has_feature.is_valid() else ""
	if has_feature.is_valid() and here.is_empty():
		problems.append("no library this editor can load on %s: no key in [libraries] has only tags this editor has" % _describe(has_feature))
	var groups: Dictionary = {}  # "platform.arch.variant" -> [{key, path, build, full, exists}]
	for key: String in config.get_section_keys("libraries"):
		var tags := key.split(".")
		var key_platform := _first_in(tags, PLATFORMS)
		if key_platform.is_empty():
			if key != here:
				warnings.append("%s: no platform tag (one of %s)" % [key, ", ".join(PLATFORMS)])
				continue
			key_platform = "any"
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
		if not groups.has(label):
			groups[label] = []
		groups[label].append({"key": key, "path": path, "build": _first_in(tags, PackedStringArray(["debug", "release", "editor"])), "full": full, "exists": FileAccess.file_exists(full) or DirAccess.dir_exists_absolute(full)})
	var labels := groups.keys()
	labels.sort()
	for label: String in labels:
		var entries: Array = groups[label]
		var has_here := entries.any(func(e: Dictionary) -> bool: return e.key == here)
		var built := entries.any(func(e: Dictionary) -> bool: return e.exists)
		if not built and not has_here:
			not_built.append(label)
			continue
		var builds: PackedStringArray = []
		for entry: Dictionary in entries:
			var file := str(entry.path).get_file()
			var loads_here: bool = entry.key == here
			if entry.build == "release" and file.contains("template_debug"):
				warnings.append("%s is a release key but points to a debug library: %s" % [entry.key, entry.path])
			if entry.build == "debug" and file.contains("template_release"):
				warnings.append("%s is a debug key but points to a release library: %s" % [entry.key, entry.path])
			if not entry.build in builds:
				builds.append(entry.build)
			if not entry.exists:
				var missing := "%s: file not found: %s%s" % [entry.key, entry.path, _prefix_hint(entry.full)]
				(problems if loads_here else warnings).append(missing + (" (it's the key this editor loads)" if loads_here else ""))
				continue
			if not symbol.is_empty() and FileAccess.file_exists(entry.full) and not _file_contains(entry.full, symbol):
				(problems if loads_here else warnings).append("%s: entry_symbol %s not found in %s" % [entry.key, symbol, entry.path])
		if not "" in builds:
			if not "release" in builds:
				warnings.append("%s has a debug library but no release key: release exports won't load it" % label)
			if not "debug" in builds and not "editor" in builds:
				warnings.append("%s has a release library but no debug key: the editor won't load it" % label)
	if config.has_section("dependencies"):
		var dep_here := loaded_key(config, "dependencies", has_feature) if has_feature.is_valid() else ""
		for key: String in config.get_section_keys("dependencies"):
			var deps: Variant = config.get_value("dependencies", key)
			if not deps is Dictionary:
				(problems if key == dep_here else warnings).append("[dependencies] %s: value must be a { \"path\": \"target dir\" } dictionary" % key)
				continue
			for dep: Variant in deps:
				if not FileAccess.file_exists(_resolve(str(dep), gdext_dir, project_root)):
					(problems if key == dep_here else warnings).append("[dependencies] %s: file not found: %s" % [key, dep])
	return {"problems": problems, "warnings": warnings, "not_built": not_built}


## Revisa lo preparado como va a quedar en el juego: `pending/` tiene la misma estructura que el
## juego, así que las rutas res:// reescritas se resuelven contra esa carpeta.
static func check_staged(planned: Dictionary, state_dir: String, has_feature: Callable = editor_features()) -> Dictionary:
	var pending_root := state_dir.path_join(PENDING_DIR)
	var gdext := pending_root.path_join(str(planned.gdextension))
	return check(planned.gdextension_text, gdext.get_base_dir(), pending_root, has_feature)


## Deja el plan en `<state_dir>/pending/` (con los `.gdextension` reescritos) y lo anota en
## pending.json, reemplazando lo que hubiera preparado antes. Se arma aparte (pending.new/,
## pending.json.tmp) y se cambia al final: si falla, lo preparado antes queda como estaba; el
## manifest sale primero y entra último, así nunca nombra archivos de otra preparación. Devuelve ""
## o el error.
static func stage(planned: Dictionary, state_dir: String) -> String:
	var pending_dir := state_dir.path_join(PENDING_DIR)
	var staging := pending_dir + NEW_SUFFIX
	var manifest := state_dir.path_join(PENDING_MANIFEST)
	var manifest_tmp := manifest + NEW_SUFFIX
	_remove_tree(staging)
	DirAccess.remove_absolute(manifest_tmp)
	var staged: PackedStringArray = []
	for file: Dictionary in planned.files:
		var to := staging.path_join(str(file.to))
		DirAccess.make_dir_recursive_absolute(to.get_base_dir())
		var error := OK
		if file.has("text"):
			error = _write_text(to, str(file.text))
		else:
			error = DirAccess.copy_absolute(str(file.from), to)
		if error != OK:
			_remove_tree(staging)
			return "Could not stage %s: %s" % [file.to, error_string(error)]
		staged.append(str(file.to))
	var error := _write_text(manifest_tmp, JSON.stringify({"files": Array(staged), "target": planned.target, "source": planned.source, "gdextension": "res://" + str(planned.gdextension), "time": Time.get_datetime_string_from_system()}, "\t"))
	if error != OK:
		_remove_tree(staging)
		return "Could not write %s: %s" % [manifest_tmp, error_string(error)]
	# El cambio: lo anterior pasa a .prev y vuelve si algo falla.
	var manifest_prev := manifest + PREV_SUFFIX
	var pending_prev := pending_dir + PREV_SUFFIX
	DirAccess.remove_absolute(manifest_prev)
	_remove_tree(pending_prev)
	if FileAccess.file_exists(manifest):
		DirAccess.rename_absolute(manifest, manifest_prev)
	if DirAccess.dir_exists_absolute(pending_dir):
		DirAccess.rename_absolute(pending_dir, pending_prev)
	error = DirAccess.rename_absolute(staging, pending_dir)
	if error == OK:
		error = DirAccess.rename_absolute(manifest_tmp, manifest)
	if error != OK:
		_remove_tree(pending_dir)
		_remove_tree(staging)
		DirAccess.remove_absolute(manifest_tmp)
		DirAccess.rename_absolute(pending_prev, pending_dir)
		DirAccess.rename_absolute(manifest_prev, manifest)
		return "Could not stage into %s: %s" % [pending_dir, error_string(error)]
	_remove_tree(pending_prev)
	DirAccess.remove_absolute(manifest_prev)
	DirAccess.remove_absolute(state_dir.path_join(LAST_INSTALL))
	return ""


## Lo preparado, o {} si no hay nada.
static func pending(state_dir: String) -> Dictionary:
	var path := state_dir.path_join(PENDING_MANIFEST)
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}


## Mueve lo preparado al juego (con el editor cerrado o a punto de cerrarse), todo o nada: primero
## copia cada archivo junto a su destino (`.installing`), después cambia cada uno por rename (el
## que había queda como `.old`: un editor que todavía tiene mapeada la biblioteca vieja no ve el
## cambio, y en Windows una DLL cargada se puede renombrar aunque no pisar). Si algo falla, vuelve
## lo que había, lo preparado sigue en pending/ y la falla queda en last_install.json (el aviso del
## dock y godot.project_info). Las rutas del manifest se validan: relativas, dentro del juego, nada
## protegido. Devuelve `{applied, failed, error}` (relativas al juego).
static func apply_pending(project_dir: String, state_dir: String) -> Dictionary:
	var root := _strip_slash(project_dir)
	var applied: PackedStringArray = []
	var result := {"applied": applied, "failed": PackedStringArray(), "error": ""}
	if not FileAccess.file_exists(state_dir.path_join(PENDING_MANIFEST)):
		return result
	var manifest := pending(state_dir)
	var staged := state_dir.path_join(PENDING_DIR)
	var validated := _manifest_files(manifest, root, staged)
	var files: PackedStringArray = validated.files
	if not str(validated.error).is_empty():
		return _install_failed(state_dir, manifest, files, validated.error)
	for relative: String in files:
		var to := root.path_join(relative)
		_remove_leftovers(to)
		DirAccess.make_dir_recursive_absolute(to.get_base_dir())
		var error := DirAccess.copy_absolute(staged.path_join(relative), to + TMP_SUFFIX)
		if error != OK:
			_undo_install(root, files, [])
			return _install_failed(state_dir, manifest, files, "could not copy %s into the game: %s" % [relative, error_string(error)])
	var swapped: Array = []  # [{relative, backup}]
	for relative: String in files:
		var to := root.path_join(relative)
		var backup := FileAccess.file_exists(to)
		if backup and DirAccess.rename_absolute(to, to + OLD_SUFFIX) != OK:
			_undo_install(root, files, swapped)
			return _install_failed(state_dir, manifest, files, "could not move res://%s aside (is it open in another program?)" % relative)
		var error := DirAccess.rename_absolute(to + TMP_SUFFIX, to)
		if error != OK:
			if backup:
				DirAccess.rename_absolute(to + OLD_SUFFIX, to)
			_undo_install(root, files, swapped)
			return _install_failed(state_dir, manifest, files, "could not put res://%s in place: %s" % [relative, error_string(error)])
		swapped.append({"relative": relative, "backup": backup})
		applied.append(relative)
	for entry: Dictionary in swapped:
		if entry.backup:
			# En Windows falla mientras el editor viejo tiene la DLL cargada: la próxima instalación
			# la borra (_remove_leftovers).
			DirAccess.remove_absolute(root.path_join(entry.relative) + OLD_SUFFIX)
	_remove_tree(staged)
	DirAccess.remove_absolute(state_dir.path_join(PENDING_MANIFEST))
	_write_text(state_dir.path_join(LAST_INSTALL), JSON.stringify({"ok": true, "applied": Array(applied), "time": Time.get_datetime_string_from_system()}, "\t"))
	return result


## La última instalación (last_install.json): `{ok, applied | failed, error, extensions, time,
## reported}`, o {} si no hubo desde la última preparación.
static func last_install(state_dir: String) -> Dictionary:
	var path := state_dir.path_join(LAST_INSTALL)
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}


## La falla de la última instalación si todavía no se avisó en el dock, y la marca avisada; o {}.
static func take_install_failure(state_dir: String) -> Dictionary:
	var last := last_install(state_dir)
	if last.is_empty() or last.get("ok", false) or last.get("reported", false):
		return {}
	last.reported = true
	_write_text(state_dir.path_join(LAST_INSTALL), JSON.stringify(last, "\t"))
	return last


## Lo preparado, para avisar (m19-05): `{extensions: [res:// de los .gdextension], target, files,
## time}`, o {} si no hay nada.
static func pending_info(state_dir: String) -> Dictionary:
	var manifest := pending(state_dir)
	var files: Array = manifest.get("files", [])
	if files.is_empty():
		return {}
	var extensions: PackedStringArray = []
	for file: Variant in files:
		if str(file).get_extension() == "gdextension":
			extensions.append("res://" + str(file))
	return {"extensions": extensions, "target": str(manifest.get("target", "")), "files": files.size(), "time": str(manifest.get("time", ""))}


## Los nombres de las extensiones preparadas (el nombre del .gdextension sin extensión).
static func pending_names(info: Dictionary) -> String:
	var names: PackedStringArray = []
	for path: String in info.get("extensions", PackedStringArray()):
		names.append(path.get_file().get_basename())
	return ", ".join(names) if not names.is_empty() else str(info.get("target", ""))


## Líneas para el agente (godot.project_info): lo preparado que no entró y la última instalación que
## falló (hasta la próxima preparación o el descarte), o "".
static func pending_line(state_dir: String) -> String:
	var lines: PackedStringArray = []
	var last := last_install(state_dir)
	if not last.is_empty() and not last.get("ok", false):
		lines.append("The last install of the staged GDExtension (%s) failed and the game kept the build it had: %s." % [str(last.get("time", "time unknown")), str(last.get("error", ""))])
	var info := pending_info(state_dir)
	if not info.is_empty():
		lines.append("Staged GDExtension install (install_extension, %s): %d files for %s, not in the project yet. They enter it with godot.restart_editor; the user can also restart or discard it from the dock." % [info.time if not str(info.time).is_empty() else "time unknown", info.files, ", ".join(info.extensions) if not (info.extensions as PackedStringArray).is_empty() else info.target])
	return "\n".join(lines)


static func discard_pending(state_dir: String) -> void:
	_remove_tree(state_dir.path_join(PENDING_DIR))
	_remove_tree(state_dir.path_join(PENDING_DIR + NEW_SUFFIX))
	DirAccess.remove_absolute(state_dir.path_join(PENDING_MANIFEST))
	DirAccess.remove_absolute(state_dir.path_join(PENDING_MANIFEST + NEW_SUFFIX))
	DirAccess.remove_absolute(state_dir.path_join(LAST_INSTALL))


## Las rutas del manifest, validadas: `{files, error}`.
static func _manifest_files(manifest: Dictionary, root: String, staged: String) -> Dictionary:
	var files: PackedStringArray = []
	var listed: Variant = manifest.get("files")
	if not listed is Array or (listed as Array).is_empty():
		return {"files": files, "error": "%s lists no files" % PENDING_MANIFEST}
	for value: Variant in listed:
		var relative := str(value)
		var normalized := ProtectedPaths.normalize_relative(relative)
		if not value is String or relative.is_empty() or not str(normalized.error).is_empty() or normalized.rel != relative:
			return {"files": files, "error": "%s has a path that isn't relative to the game: %s" % [PENDING_MANIFEST, relative]}
		var guard := ProtectedPaths.write_error(relative, root)
		if not guard.is_empty():
			return {"files": files, "error": "%s: %s" % [PENDING_MANIFEST, guard]}
		if not FileAccess.file_exists(staged.path_join(relative)):
			return {"files": files, "error": "res://%s is not in %s" % [relative, staged]}
		if not relative in files:
			files.append(relative)
	return {"files": files, "error": ""}


## Deshace una instalación a medias: saca lo nuevo que ya entró y vuelve lo que había (`.old`), y
## borra los `.installing`.
static func _undo_install(root: String, files: PackedStringArray, swapped: Array) -> void:
	for i: int in range(swapped.size() - 1, -1, -1):
		var to := root.path_join(str(swapped[i].relative))
		DirAccess.remove_absolute(to)
		if swapped[i].backup:
			DirAccess.rename_absolute(to + OLD_SUFFIX, to)
	for relative: String in files:
		DirAccess.remove_absolute(root.path_join(relative) + TMP_SUFFIX)


static func _install_failed(state_dir: String, manifest: Dictionary, files: PackedStringArray, error: String) -> Dictionary:
	var extensions: PackedStringArray = []
	for file: Variant in manifest.get("files", []):
		if str(file).get_extension() == "gdextension":
			extensions.append(str(file).get_file().get_basename())
	_write_text(state_dir.path_join(LAST_INSTALL), JSON.stringify({"ok": false, "failed": Array(files), "error": error, "extensions": Array(extensions), "time": Time.get_datetime_string_from_system()}, "\t"))
	return {"applied": PackedStringArray(), "failed": files, "error": error}


## Los `.old` y `.installing` que dejó una instalación anterior junto a `to`.
static func _remove_leftovers(to: String) -> void:
	for suffix: String in [OLD_SUFFIX, TMP_SUFFIX]:
		if FileAccess.file_exists(to + suffix):
			DirAccess.remove_absolute(to + suffix)


static func _write_text(path: String, text: String) -> Error:
	var handle := FileAccess.open(path, FileAccess.WRITE)
	if handle == null:
		return FileAccess.get_open_error()
	handle.store_string(text)
	handle.close()
	return OK


static func _same(a: String, b: String) -> bool:
	return a.to_lower() == b.to_lower() if ProtectedPaths.case_insensitive() else a == b


static func _describe(has_feature: Callable) -> String:
	var platform := ""
	for option: String in PLATFORMS:
		if has_feature.call(option):
			platform = option
			break
	var arch := ""
	for option: String in ARCHES:
		if has_feature.call(option):
			arch = option
			break
	return "%s.%s" % [platform if not platform.is_empty() else "?", arch if not arch.is_empty() else "?"]


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
		# Una subcarpeta con su project.godot es otro proyecto (el de prueba dentro del juego): Godot
		# no la escanea.
		if not sub.begins_with(".") and not FileAccess.file_exists(dir.path_join(sub).path_join("project.godot")):
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
