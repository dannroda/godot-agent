@tool
extends RefCounted
## La última versión buena de las bibliotecas de las GDExtension del proyecto (m19-03). Cuando el
## editor arranca bien, el supervisor copia las bibliotecas a `good/`. Si una build nueva crashea el
## editor al arrancar, vuelve a esas copias; una extensión sin copia buena (nueva) se desactiva
## renombrando su `.gdextension`. Sin rutas res://: lo usa el supervisor, fuera del proyecto.

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
		var files: PackedStringArray = []
		if config.has_section("libraries"):
			for key: String in config.get_section_keys("libraries"):
				_add_file(files, str(config.get_value("libraries", key)), path, root)
		if config.has_section("dependencies"):
			for key: String in config.get_section_keys("dependencies"):
				var deps: Variant = config.get_value("dependencies", key)
				if deps is Dictionary:
					for dep: Variant in deps:
						_add_file(files, str(dep), path, root)
		result.append({"gdextension": path, "files": files})
	return result


## Copia a `good/` las bibliotecas que cambiaron desde la última copia. Devuelve las copiadas.
static func snapshot(project_dir: String, state_dir: String) -> PackedStringArray:
	var root := _strip_slash(project_dir)
	var good := state_dir.path_join("good")
	var manifest := _read_manifest(good)
	var copied: PackedStringArray = []
	for extension: Dictionary in extensions(root):
		for file: String in extension.files:
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


## Vuelve a la última versión buena: cada biblioteca cambiada queda como `<archivo>.crashed` y vuelve
## la copia buena; un `.gdextension` cuyas bibliotecas no tienen copia buena se renombra a
## `.gdextension.disabled`. Devuelve `{restored: [...], disabled: [...]}` (rutas relativas).
static func rollback(project_dir: String, state_dir: String) -> Dictionary:
	var root := _strip_slash(project_dir)
	var good := state_dir.path_join("good")
	var manifest := _read_manifest(good)
	var restored: PackedStringArray = []
	var disabled: PackedStringArray = []
	for extension: Dictionary in extensions(root):
		var files: PackedStringArray = extension.files
		var has_good := false
		for file: String in files:
			var relative := file.trim_prefix(root + "/")
			if not manifest.has(relative) or not FileAccess.file_exists(good.path_join(relative)):
				continue
			has_good = true
			if manifest[relative] == FileAccess.get_md5(file):
				continue
			DirAccess.remove_absolute(file + CRASHED_SUFFIX)
			DirAccess.rename_absolute(file, file + CRASHED_SUFFIX)
			if DirAccess.copy_absolute(good.path_join(relative), file) == OK:
				restored.append(relative)
		if not has_good and not files.is_empty():
			var path: String = extension.gdextension
			if DirAccess.rename_absolute(path, path + DISABLED_SUFFIX) == OK:
				disabled.append(path.trim_prefix(root + "/"))
	return {"restored": restored, "disabled": disabled}


static func _add_file(files: PackedStringArray, value: String, gdextension: String, root: String) -> void:
	if value.is_empty():
		return
	var path := value
	if path.begins_with("res://"):
		path = root.path_join(path.trim_prefix("res://"))
	elif path.is_relative_path():
		path = gdextension.get_base_dir().path_join(path)
	path = path.simplify_path()
	if path.begins_with(root + "/") and FileAccess.file_exists(path) and not path in files:
		files.append(path)


static func _gdextension_files(dir: String) -> PackedStringArray:
	var result: PackedStringArray = []
	if FileAccess.file_exists(dir.path_join(".gdignore")):
		return result
	for file: String in DirAccess.get_files_at(dir):
		if file.get_extension() == "gdextension":
			result.append(dir.path_join(file))
	for sub: String in DirAccess.get_directories_at(dir):
		if not sub.begins_with("."):
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
