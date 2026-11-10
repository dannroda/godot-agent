@tool
extends RefCounted
## La última versión buena de las GDExtension del proyecto (m19-03): el `.gdextension` y sus
## bibliotecas. Cuando el editor arranca bien, el supervisor los copia a `good/`. Si una build nueva
## crashea el editor al arrancar, vuelve a esas copias (primero el `.gdextension`, que puede nombrar
## otras bibliotecas, y después las bibliotecas que nombra); una extensión sin ninguna copia buena
## (nueva) se desactiva renombrando su `.gdextension`. Sin rutas res://: lo usa el supervisor, fuera
## del proyecto.

const MANIFEST := "manifest.json"
const CRASHED_SUFFIX := ".crashed"
const DISABLED_SUFFIX := ".disabled"


## Los `.gdextension` del proyecto con sus bibliotecas que existen dentro del proyecto:
## `[{gdextension: ruta absoluta, files: [rutas absolutas]}]`. Mira [libraries] y [dependencies].
static func extensions(project_dir: String) -> Array:
	var root := _strip_slash(project_dir)
	var result: Array = []
	for path: String in _gdextension_files(root):
		var config := ConfigFile.new()
		if config.load(path) != OK:
			continue
		result.append({"gdextension": path, "files": _libraries(config, path, root, true)})
	return result


## Las bibliotecas de [libraries] y [dependencies] dentro del proyecto (absolutas); con
## `existing_only`, solo las que existen.
static func _libraries(config: ConfigFile, gdextension: String, root: String, existing_only: bool) -> PackedStringArray:
	var files: PackedStringArray = []
	if config.has_section("libraries"):
		for key: String in config.get_section_keys("libraries"):
			_add_file(files, str(config.get_value("libraries", key)), gdextension, root, existing_only)
	if config.has_section("dependencies"):
		for key: String in config.get_section_keys("dependencies"):
			var deps: Variant = config.get_value("dependencies", key)
			if deps is Dictionary:
				for dep: Variant in deps:
					_add_file(files, str(dep), gdextension, root, existing_only)
	return files


## Copia a `good/` los `.gdextension` y las bibliotecas que cambiaron desde la última copia.
## Devuelve los copiados.
static func snapshot(project_dir: String, state_dir: String) -> PackedStringArray:
	var root := _strip_slash(project_dir)
	var good := state_dir.path_join("good")
	var manifest := _read_manifest(good)
	var copied: PackedStringArray = []
	for extension: Dictionary in extensions(root):
		for file: String in PackedStringArray([extension.gdextension]) + extension.files:
			var relative := file.trim_prefix(root + "/")
			var md5 := FileAccess.get_md5(file)
			if manifest.get(relative, "") == md5 and FileAccess.file_exists(good.path_join(relative)):
				continue
			DirAccess.make_dir_recursive_absolute(good.path_join(relative).get_base_dir())
			if DirAccess.copy_absolute(file, good.path_join(relative)) == OK:
				manifest[relative] = md5
				copied.append(relative)
	if not copied.is_empty():
		_write_manifest(good, manifest)
	return copied


## Las bibliotecas que no son la copia buena: `{changed: [relativas con copia], new: [sin copia]}`.
static func changes(project_dir: String, state_dir: String) -> Dictionary:
	var root := _strip_slash(project_dir)
	var manifest := _read_manifest(state_dir.path_join("good"))
	var changed: PackedStringArray = []
	var fresh: PackedStringArray = []
	for extension: Dictionary in extensions(root):
		for file: String in extension.files:
			var relative := file.trim_prefix(root + "/")
			if not manifest.has(relative):
				fresh.append(relative)
			elif manifest[relative] != FileAccess.get_md5(file):
				changed.append(relative)
	return {"changed": changed, "new": fresh}


## Vuelve a la última versión buena: un `.gdextension` cambiado y cada biblioteca cambiada quedan
## como `<archivo>.crashed` y vuelve la copia buena (las bibliotecas, las que nombra el `.gdextension`
## ya restaurado). Un `.gdextension` sin copia buena, ni de él ni de sus bibliotecas, se renombra a
## `.gdextension.disabled`. Devuelve `{restored: [...], disabled: [...]}` (rutas relativas).
static func rollback(project_dir: String, state_dir: String) -> Dictionary:
	var root := _strip_slash(project_dir)
	var good := state_dir.path_join("good")
	var manifest := _read_manifest(good)
	var restored: PackedStringArray = []
	var disabled: PackedStringArray = []
	for extension: Dictionary in extensions(root):
		var path: String = extension.gdextension
		var files: PackedStringArray = extension.files
		var has_good := _restore(path, root, good, manifest, restored)
		if has_good:
			# El .gdextension bueno puede nombrar otras bibliotecas (o las mismas, sin existir).
			var config := ConfigFile.new()
			if config.load(path) == OK:
				files = _libraries(config, path, root, false)
		for file: String in files:
			if _restore(file, root, good, manifest, restored):
				has_good = true
		if not has_good and not files.is_empty():
			if DirAccess.rename_absolute(path, path + DISABLED_SUFFIX) == OK:
				disabled.append(path.trim_prefix(root + "/"))
	return {"restored": restored, "disabled": disabled}


## Qué puede hacer rollback() con el `.gdextension` (relativa al proyecto) si la build nueva crashea al
## arrancar: "full" (hay copia buena del `.gdextension`), "libraries" (solo de las bibliotecas, de un
## supervisor anterior a m19-05) o "none" (se desactiva).
static func restorable(project_dir: String, state_dir: String, gdextension: String) -> String:
	var root := _strip_slash(project_dir)
	var good := state_dir.path_join("good")
	var manifest := _read_manifest(good)
	if manifest.has(gdextension) and FileAccess.file_exists(good.path_join(gdextension)):
		return "full"
	var config := ConfigFile.new()
	if config.load(root.path_join(gdextension)) == OK:
		for file: String in _libraries(config, root.path_join(gdextension), root, false):
			var relative := file.trim_prefix(root + "/")
			if manifest.has(relative) and FileAccess.file_exists(good.path_join(relative)):
				return "libraries"
	return "none"


## Vuelve la copia buena de `file` si tiene una y cambió (la actual queda como `.crashed`). Devuelve
## si tiene copia buena.
static func _restore(file: String, root: String, good: String, manifest: Dictionary, restored: PackedStringArray) -> bool:
	var relative := file.trim_prefix(root + "/")
	if not manifest.has(relative) or not FileAccess.file_exists(good.path_join(relative)):
		return false
	if FileAccess.file_exists(file) and manifest[relative] == FileAccess.get_md5(file):
		return true
	DirAccess.remove_absolute(file + CRASHED_SUFFIX)
	DirAccess.rename_absolute(file, file + CRASHED_SUFFIX)
	DirAccess.make_dir_recursive_absolute(file.get_base_dir())
	if DirAccess.copy_absolute(good.path_join(relative), file) == OK:
		restored.append(relative)
	return true


static func _add_file(files: PackedStringArray, value: String, gdextension: String, root: String, existing_only: bool = true) -> void:
	if value.is_empty():
		return
	var path := value
	if path.begins_with("res://"):
		path = root.path_join(path.trim_prefix("res://"))
	elif path.is_relative_path():
		path = gdextension.get_base_dir().path_join(path)
	path = path.simplify_path()
	if path.begins_with(root + "/") and (FileAccess.file_exists(path) or not existing_only) and not path in files:
		files.append(path)


static func _gdextension_files(dir: String) -> PackedStringArray:
	var result: PackedStringArray = []
	if FileAccess.file_exists(dir.path_join(".gdignore")):
		return result
	for file: String in DirAccess.get_files_at(dir):
		if file.get_extension() == "gdextension":
			result.append(dir.path_join(file))
	for sub: String in DirAccess.get_directories_at(dir):
		# Como el editor: una subcarpeta con su project.godot es otro proyecto y no la escanea.
		if not sub.begins_with(".") and not FileAccess.file_exists(dir.path_join(sub).path_join("project.godot")):
			result.append_array(_gdextension_files(dir.path_join(sub)))
	return result


static func _read_manifest(good: String) -> Dictionary:
	var path := good.path_join(MANIFEST)
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}


static func _write_manifest(good: String, manifest: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute(good)
	var handle := FileAccess.open(good.path_join(MANIFEST), FileAccess.WRITE)
	if handle:
		handle.store_string(JSON.stringify(manifest, "\t"))
		handle.close()


static func _strip_slash(path: String) -> String:
	return path.left(-1) if path.ends_with("/") and path.length() > 1 else path
