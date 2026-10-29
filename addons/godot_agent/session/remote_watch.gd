@tool
extends RefCounted
## Archivos del proyecto que cambian mientras Remote Control está prendido (m7-22). Claude Code no
## le pasa al dock los turnos que se mandan desde el celular (D58), pero los archivos que tocan sí se
## ven: se guarda una foto del proyecto (fecha y tamaño de cada archivo, y el texto de los chicos) y
## `poll` devuelve lo que cambió desde la foto anterior. Con el texto de antes, un cambio se puede
## ver como diff y deshacer.

enum FileChange { MODIFIED, CREATED, DELETED }

## Extensiones cuyo texto se guarda para el diff y el deshacer.
const TEXT_EXTENSIONS: PackedStringArray = [
	"gd", "cs", "csproj", "gdshader", "gdshaderinc", "shader", "tscn", "tres", "cfg", "godot", "json", "md", "txt",
	"csv", "cs", "ini", "yaml", "yml", "toml", "xml", "html", "js", "css", "py", "sh",
]
## Los maneja el editor: cambian solos al importar.
const IGNORED_EXTENSIONS: PackedStringArray = ["import", "uid", "tmp"]
const MAX_TEXT_BYTES := 256 * 1024
const MAX_TEXT_TOTAL := 32 * 1024 * 1024
## Con más archivos, la foto se corta: un proyecto así tarda demasiado en recorrerse cada 2 s.
const MAX_FILES := 5000

## Carpeta del proyecto, absoluta y sin barra final.
var root: String = ""
## Rutas relativas que no se miran (los archivos que escribe el propio harness).
var ignored: PackedStringArray = []
## Se cortó la foto en MAX_FILES.
var truncated: bool = false
## ruta relativa -> {mtime, size, text (String o null)}
var _files: Dictionary = {}
var _text_total: int = 0


func start(project_root: String) -> void:
	root = project_root.trim_suffix("/")
	rebase()


func stop() -> void:
	root = ""
	_files.clear()
	_text_total = 0


func is_active() -> bool:
	return not root.is_empty()


## Foto nueva sin reportar nada: lo que cambió hasta acá no viene del celular (un turno del dock).
func rebase() -> void:
	_files.clear()
	_text_total = 0
	truncated = false
	if not is_active():
		return
	for rel: String in _list_files():
		_files[rel] = _read_entry(rel)


## Un archivo que se guardó desde el editor: se actualiza la foto sin reportarlo.
func note_saved(res_path: String) -> void:
	if not is_active():
		return
	var rel := res_path.trim_prefix("res://")
	if FileAccess.file_exists(_abs(rel)):
		_forget_text(rel)
		_files[rel] = _read_entry(rel)
	else:
		_forget_text(rel)
		_files.erase(rel)


## Cambios desde la foto anterior: `[{path: "res://…", change: FileChange, before: String o null}]`,
## ordenados por ruta. La foto queda al día.
func poll() -> Array[Dictionary]:
	var changes: Array[Dictionary] = []
	if not is_active():
		return changes
	var seen := {}
	for rel: String in _list_files():
		seen[rel] = true
		var known: Variant = _files.get(rel)
		var mtime := FileAccess.get_modified_time(_abs(rel))
		var size := _size(rel)
		if known == null:
			_files[rel] = _read_entry(rel)
			changes.append({"path": "res://" + rel, "change": FileChange.CREATED, "before": null})
		elif known.mtime != mtime or known.size != size:
			var before: Variant = known.text
			var entry := _read_entry_after(rel, known)
			_files[rel] = entry
			# Misma fecha nueva pero mismo contenido (un editor que guarda sin cambios): no cuenta.
			if before != null and entry.text != null and before == entry.text:
				continue
			changes.append({"path": "res://" + rel, "change": FileChange.MODIFIED, "before": before})
	for rel: String in _files.keys():
		if not seen.has(rel):
			changes.append({"path": "res://" + rel, "change": FileChange.DELETED, "before": _files[rel].text})
			_forget_text(rel)
			_files.erase(rel)
	changes.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a.path) < str(b.path))
	return changes


## Se pueden deshacer si se conoce el texto de antes de cada archivo modificado o borrado.
static func can_restore(changes: Array) -> bool:
	if changes.is_empty():
		return false
	for change: Dictionary in changes:
		if change.change != FileChange.CREATED and change.before == null:
			return false
	return true


## Deja los archivos como estaban antes de `changes` (crea los borrados, borra los creados) y
## actualiza la foto. Devuelve las rutas que no se pudieron restaurar.
func restore(changes: Array) -> PackedStringArray:
	var failed: PackedStringArray = []
	for change: Dictionary in changes:
		var rel := str(change.path).trim_prefix("res://")
		var path := _abs(rel)
		if change.change == FileChange.CREATED:
			if FileAccess.file_exists(path) and DirAccess.remove_absolute(path) != OK:
				failed.append(change.path)
				continue
			_forget_text(rel)
			_files.erase(rel)
		else:
			DirAccess.make_dir_recursive_absolute(path.get_base_dir())
			var file := FileAccess.open(path, FileAccess.WRITE)
			if file == null:
				failed.append(change.path)
				continue
			file.store_string(str(change.before))
			file.close()
			if is_active():
				_forget_text(rel)
				_files[rel] = _read_entry(rel)
	return failed


## Juntar dos tandas de cambios del mismo archivo: queda el texto de antes de la primera.
static func merge(pending: Array[Dictionary], changes: Array[Dictionary]) -> Array[Dictionary]:
	var by_path := {}
	var order: Array[String] = []
	for change: Dictionary in pending:
		by_path[change.path] = change
		order.append(change.path)
	for change: Dictionary in changes:
		var previous: Variant = by_path.get(change.path)
		if previous == null:
			by_path[change.path] = change
			order.append(change.path)
			continue
		if previous.change == FileChange.CREATED and change.change == FileChange.DELETED:
			by_path.erase(change.path)  # apareció y desapareció: no hay nada que contar
			continue
		var kind: FileChange = change.change
		if previous.change == FileChange.CREATED:
			kind = FileChange.CREATED
		elif previous.change == FileChange.DELETED and change.change == FileChange.CREATED:
			kind = FileChange.MODIFIED
		by_path[change.path] = {"path": change.path, "change": kind, "before": previous.before}
	var result: Array[Dictionary] = []
	for path: String in order:
		if by_path.has(path) and not result.any(func(c: Dictionary) -> bool: return c.path == path):
			result.append(by_path[path])
	return result


func _list_files() -> PackedStringArray:
	var result: PackedStringArray = []
	var pending: Array[String] = [""]
	while not pending.is_empty():
		var dir: String = pending.pop_back()
		var abs_dir := root if dir.is_empty() else root + "/" + dir
		if not dir.is_empty() and FileAccess.file_exists(abs_dir + "/.gdignore"):
			continue
		for sub: String in DirAccess.get_directories_at(abs_dir):
			if not sub.begins_with("."):
				pending.append(sub if dir.is_empty() else dir + "/" + sub)
		for file: String in DirAccess.get_files_at(abs_dir):
			if file.begins_with(".") or file.get_extension().to_lower() in IGNORED_EXTENSIONS:
				continue
			var rel := file if dir.is_empty() else dir + "/" + file
			if rel in ignored:
				continue
			result.append(rel)
			if result.size() >= MAX_FILES:
				truncated = true
				return result
	return result


func _read_entry(rel: String) -> Dictionary:
	var size := _size(rel)
	var entry := {"mtime": FileAccess.get_modified_time(_abs(rel)), "size": size, "text": null}
	if rel.get_extension().to_lower() in TEXT_EXTENSIONS and size <= MAX_TEXT_BYTES and _text_total + size <= MAX_TEXT_TOTAL:
		entry.text = FileAccess.get_file_as_string(_abs(rel))
		_text_total += size
	return entry


func _read_entry_after(rel: String, known: Dictionary) -> Dictionary:
	if known.text != null:
		_text_total -= int(known.size)
	return _read_entry(rel)


func _forget_text(rel: String) -> void:
	var known: Variant = _files.get(rel)
	if known != null and known.text != null:
		_text_total -= int(known.size)


func _size(rel: String) -> int:
	var file := FileAccess.open(_abs(rel), FileAccess.READ)
	return file.get_length() if file else -1


func _abs(rel: String) -> String:
	return root + "/" + rel
