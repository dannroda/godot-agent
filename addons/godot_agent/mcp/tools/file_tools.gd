@tool
extends RefCounted
## Archivos del proyecto con las referencias al día (m4-10), grupo edit_files: move_file,
## copy_file y delete_file. Reemplazan a mv, cp y rm, que el harness rechaza dentro del proyecto
## (D48): un mv deja escenas con rutas viejas y un rm las rompe sin aviso.
## - Mover: lleva el `.uid` y el `.import`, mantiene el uid y reescribe `res://viejo` → `res://nuevo`
##   en escenas, recursos, scripts, shaders y project.godot.
## - Copiar: la copia es otro recurso (uid nuevo); también trae archivos de afuera del proyecto.
## - Borrar: se niega si algo lo referencia o si es una escena abierta; va a la papelera si se puede.

const McpTool := preload("../mcp_tool.gd")
const PermissionPolicy := preload("../../session/permission_policy.gd")
const FsHandler := preload("../../acp/fs_handler.gd")

## Archivos de texto donde se buscan y reescriben referencias.
const TEXT_EXTENSIONS: PackedStringArray = ["tscn", "tres", "gd", "gdshader", "gdshaderinc", "godot", "cfg", "json", "cs", "gdextension"]
const SIDECARS: PackedStringArray = ["uid", "import"]
const REFERENCE_LIST_LIMIT := 20
const PROTECTED: PackedStringArray = ["res://project.godot", "res://addons/godot_agent", "res://.godot"]

## Callable(abs_path: String): un archivo del proyecto cambió en disco (para que el editor lo tome).
var on_file_written: Callable
## Callable(abs_path: String) -> Variant: texto del buffer si está abierto con cambios sin guardar.
var unsaved_buffer: Callable


func tools() -> Array:
	var files := PermissionPolicy.GROUP_EDIT_FILES
	var copy := McpTool.create("copy_file", files,
		"Copies a file or folder into the project as a new resource (new uid). `from` can be res:// or an absolute path outside the project (to bring in downloaded assets); the editor imports it.",
		{"from": {"type": "string"}, "to": {"type": "string"}},
		["from", "to"], _copy_file) as McpTool
	# Traer algo de fuera del proyecto lee cualquier archivo de la máquina: pide como un comando de
	# shell (en Auto, pregunta), no como editar archivos (revisión de seguridad, M11).
	copy.group_resolver = func(args: Dictionary) -> String:
		return files if str(args.get("from", "")).strip_edges().begins_with("res://") else PermissionPolicy.GROUP_SHELL
	return [
		McpTool.create("move_file", files,
			"Moves or renames a file or folder inside the project, like the editor's FileSystem dock: keeps the uid, moves the .uid/.import companions and rewrites every res:// reference in scenes, resources, scripts, shaders and project.godot. Use it instead of mv (the harness rejects mv/cp/rm on project files). Not undoable from the editor.",
			{"from": {"type": "string"}, "to": {"type": "string", "description": "New res:// path (for a folder, the new folder path)"}},
			["from", "to"], _move_file),
		copy,
		McpTool.create("delete_file", files,
			"Deletes a file or folder of the project (to the system trash when possible), with its .uid/.import. Refuses if another file still references it (and lists them) or if it is an open scene: fix those references first.",
			{"path": {"type": "string"}},
			["path"], _delete_file),
	]


# --- tools ---------------------------------------------------------------------------------------

func _move_file(args: Dictionary) -> Dictionary:
	var from := _normalize(str(args.from))
	var to := _normalize(str(args.to))
	var invalid := _check_target(from, true)
	if invalid.is_empty():
		invalid = _check_target(to, false)
	if not invalid.is_empty():
		return McpTool.error(invalid)
	var is_dir := DirAccess.dir_exists_absolute(from)
	if is_dir and (to + "/").begins_with(from + "/"):
		return McpTool.error("Cannot move a folder inside itself.")
	var open := _open_scenes_in(from, is_dir)
	if not open.is_empty():
		return McpTool.error("%s is open in the editor: close the scene first (%s)." % [from, ", ".join(open)])
	var moved := _resource_files(from, is_dir)
	var uids := {}
	for path: String in moved:
		var id := ResourceLoader.get_resource_uid(path)
		if id != ResourceUID.INVALID_ID:
			uids[path] = id
	var replacements := {from + "/": to + "/"} if is_dir else {from: to}
	# Sin saltear nada: los archivos de una carpeta movida que se nombran entre sí también cambian.
	var rewrites := _referencing_files(replacements, [], [])
	var warnings := _unsaved_warnings(rewrites.keys())
	# Mover en disco: la carpeta entera o el archivo con sus compañeros.
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(to.get_base_dir()))
	var error := DirAccess.rename_absolute(ProjectSettings.globalize_path(from), ProjectSettings.globalize_path(to))
	if error != OK:
		return McpTool.error("Could not move %s: %s." % [from, error_string(error)])
	if not is_dir:
		for sidecar: String in SIDECARS:
			if FileAccess.file_exists(from + "." + sidecar):
				DirAccess.rename_absolute(ProjectSettings.globalize_path(from + "." + sidecar), ProjectSettings.globalize_path(to + "." + sidecar))
	# Las referencias: archivos que apuntaban a lo movido, y los .import de lo movido.
	var changed: PackedStringArray = []
	for path: String in rewrites:
		var target := _moved_path(path, from, to, is_dir)
		if _rewrite(target, replacements):
			changed.append(target)
	for path: String in moved:
		var new_path := _moved_path(path, from, to, is_dir)
		if FileAccess.file_exists(new_path + ".import"):
			_rewrite(new_path + ".import", replacements)
		if uids.has(path):
			ResourceUID.set_id(uids[path], new_path)
		if ResourceLoader.has_cached(path):
			var cached := ResourceLoader.load(path)
			if cached:
				cached.take_over_path(new_path)
	_refresh(changed)
	var lines: PackedStringArray = ["Moved %s → %s (%d file%s, uids kept)." % [from, to, moved.size(), "" if moved.size() == 1 else "s"]]
	if changed.is_empty():
		lines.append("No other file referenced it.")
	else:
		lines.append("Updated references in %d file(s): %s" % [changed.size(), ", ".join(changed.slice(0, REFERENCE_LIST_LIMIT))])
	lines.append_array(warnings)
	if from.get_extension() == "gd" or is_dir:
		lines.append("Relative paths inside scripts (preload(\"x.tscn\")) are not rewritten: check them with validate_scripts.")
	return McpTool.text("\n".join(lines))


func _copy_file(args: Dictionary) -> Dictionary:
	var raw_from := str(args.from)
	var from := _normalize(raw_from) if raw_from.begins_with("res://") else raw_from
	var to := _normalize(str(args.to))
	var invalid := _check_target(to, false)
	if not invalid.is_empty():
		return McpTool.error(invalid)
	var source := ProjectSettings.globalize_path(from) if from.begins_with("res://") else from
	var is_dir := DirAccess.dir_exists_absolute(source)
	if not is_dir and not FileAccess.file_exists(source):
		return McpTool.error("%s does not exist." % raw_from)
	if from.begins_with("res://") and is_dir and (to + "/").begins_with(from + "/"):
		return McpTool.error("Cannot copy a folder inside itself.")
	var copied: PackedStringArray = []
	var error := _copy_recursive(source, ProjectSettings.globalize_path(to), is_dir, copied)
	if error != OK:
		return McpTool.error("Could not copy %s: %s." % [raw_from, error_string(error)])
	_refresh(PackedStringArray())
	var external := "" if from.begins_with("res://") else " from outside the project (the editor imports it)"
	return McpTool.text("Copied %s → %s%s: %d file(s), each a new resource with its own uid." % [raw_from, to, external, copied.size()])


func _delete_file(args: Dictionary) -> Dictionary:
	var path := _normalize(str(args.path))
	var invalid := _check_target(path, true)
	if not invalid.is_empty():
		return McpTool.error(invalid)
	var is_dir := DirAccess.dir_exists_absolute(path)
	var open := _open_scenes_in(path, is_dir)
	if not open.is_empty():
		return McpTool.error("%s is open in the editor (%s): close it first." % [path, ", ".join(open)])
	var deleted := _resource_files(path, is_dir)
	var uid_texts: PackedStringArray = []
	for file: String in deleted:
		var id := ResourceLoader.get_resource_uid(file)
		if id != ResourceUID.INVALID_ID:
			uid_texts.append(ResourceUID.id_to_text(id))
	var replacements := {path + "/": ""} if is_dir else {path: ""}
	var users := _referencing_files(replacements, uid_texts, [path] if is_dir else PackedStringArray([path]))
	if not users.is_empty():
		var lines: PackedStringArray = ["Not deleted: %d file(s) still reference %s and would break:" % [users.size(), path]]
		for user: String in users.keys().slice(0, REFERENCE_LIST_LIMIT):
			lines.append("- %s (line %s)" % [user, ", ".join(users[user])])
		lines.append("Remove or change those references first (or move_file it instead).")
		return McpTool.error("\n".join(lines))
	var targets: PackedStringArray = [path]
	if not is_dir:
		for sidecar: String in SIDECARS:
			if FileAccess.file_exists(path + "." + sidecar):
				targets.append(path + "." + sidecar)
	var trashed := true
	for target: String in targets:
		var absolute := ProjectSettings.globalize_path(target)
		if OS.move_to_trash(absolute) != OK:
			trashed = false
			var error := _remove_recursive(absolute) if DirAccess.dir_exists_absolute(absolute) else DirAccess.remove_absolute(absolute)
			if error != OK:
				return McpTool.error("Could not delete %s: %s." % [target, error_string(error)])
	_refresh(PackedStringArray())
	return McpTool.text("Deleted %s (%d file%s)%s. Nothing referenced it." % [path, deleted.size(), "" if deleted.size() == 1 else "s", " to the system trash" if trashed else ""])


# --- referencias ---------------------------------------------------------------------------------

## Archivos de texto del proyecto que nombran alguna clave de `replacements` (ruta exacta, o prefijo
## si termina en "/") o alguno de `uid_texts`. Saltea lo que está bajo `skip`. path -> [líneas].
func _referencing_files(replacements: Dictionary, uid_texts: PackedStringArray, skip: PackedStringArray) -> Dictionary:
	var patterns: Array[RegEx] = []
	for old: String in replacements:
		patterns.append(_path_regex(old))
	for uid_text: String in uid_texts:
		patterns.append(RegEx.create_from_string(_escape(uid_text) + "(?![a-z0-9])"))
	var result := {}
	for file: String in project_text_files():
		var skipped := false
		for prefix: String in skip:
			if file == prefix or file.begins_with(prefix + "/") or file.begins_with(prefix + "."):
				skipped = true
		if skipped:
			continue
		var text := FileAccess.get_file_as_string(file)
		var lines: PackedStringArray = []
		for regex: RegEx in patterns:
			for found: RegExMatch in regex.search_all(text):
				var line := str(text.count("\n", 0, found.get_start()) + 1)
				if not line in lines:
					lines.append(line)
		if not lines.is_empty():
			result[file] = lines
	return result


## Reemplaza en el archivo las rutas viejas por las nuevas. true si cambió.
func _rewrite(path: String, replacements: Dictionary) -> bool:
	var text := FileAccess.get_file_as_string(path)
	var updated := text
	for old: String in replacements:
		updated = _path_regex(old).sub(updated, _escape_replacement(replacements[old]), true)
	if updated == text:
		return false
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(updated)
	file.close()
	return true


## Una ruta exacta termina donde termina el string (comillas, espacio, `::` de sub-recurso…); un
## prefijo de carpeta ("res://a/") matchea cualquier cosa debajo.
static func _path_regex(old: String) -> RegEx:
	if old.ends_with("/"):
		return RegEx.create_from_string(_escape(old))
	return RegEx.create_from_string(_escape(old) + "(?=[\"'\\s)\\],:]|$)")


static func _escape(text: String) -> String:
	var escaped := ""
	for character: String in text:
		escaped += "\\" + character if character in ".^$*+?()[]{}|\\/" else character
	return escaped


static func _escape_replacement(text: String) -> String:
	return text.replace("$", "$$")


## Archivos de texto del proyecto (sin carpetas ocultas, con .gdignore ni el addon del harness).
static func project_text_files() -> PackedStringArray:
	var result: PackedStringArray = []
	_collect("res://", result, true)
	return result


static func _collect(dir: String, result: PackedStringArray, text_only: bool) -> void:
	if FileAccess.file_exists(dir.path_join(".gdignore")) and dir != "res://":
		return
	for file: String in DirAccess.get_files_at(dir):
		if not text_only or file.get_extension().to_lower() in TEXT_EXTENSIONS:
			result.append(dir.path_join(file))
	for sub: String in DirAccess.get_directories_at(dir):
		if not sub.begins_with(".") and not dir.path_join(sub) in PROTECTED:
			_collect(dir.path_join(sub), result, text_only)


# --- internos ------------------------------------------------------------------------------------

static func _normalize(path: String) -> String:
	var clean := path.strip_edges().simplify_path()
	if not clean.begins_with("res://"):
		clean = "res://" + clean.trim_prefix("/") if not clean.begins_with("/") else clean
	return clean.trim_suffix("/")


## "" si la ruta sirve (`must_exist`: tiene que existir; si no, no tiene que existir).
func _check_target(path: String, must_exist: bool) -> String:
	if not path.begins_with("res://") or path == "res://":
		return "%s must be a res:// path inside the project." % path
	for protected: String in PROTECTED:
		if path == protected or path.begins_with(protected + "/"):
			return "%s is managed by the editor or the harness: it is not moved, copied over or deleted." % path
	var exists := FileAccess.file_exists(path) or DirAccess.dir_exists_absolute(path)
	if must_exist and not exists:
		return "%s does not exist." % path
	if not must_exist and exists:
		return "%s already exists: it is not overwritten." % path
	if path.get_extension() in SIDECARS:
		return "%s is a .uid/.import companion: move or delete the file it belongs to." % path
	# Una carpeta del proyecto que es un enlace a otro lado no sirve para mover o borrar afuera.
	var project := ProjectSettings.globalize_path("res://").trim_suffix("/")
	var link := FsHandler.link_escape(ProjectSettings.globalize_path(path), PackedStringArray([project]))
	if not link.is_empty():
		return "%s goes outside the project through the link %s: it is not moved, copied over or deleted." % [path, ProjectSettings.localize_path(link)]
	return ""


## Archivos que son recursos (sin compañeros) de una ruta: el archivo o todo lo de la carpeta.
static func _resource_files(path: String, is_dir: bool) -> PackedStringArray:
	if not is_dir:
		return PackedStringArray([path])
	var all: PackedStringArray = []
	_collect(path, all, false)
	var result: PackedStringArray = []
	for file: String in all:
		if not file.get_extension() in SIDECARS:
			result.append(file)
	return result


static func _open_scenes_in(path: String, is_dir: bool) -> PackedStringArray:
	var result: PackedStringArray = []
	for scene: String in EditorInterface.get_open_scenes():
		if scene == path or (is_dir and scene.begins_with(path + "/")):
			result.append(scene)
	return result


static func _moved_path(path: String, from: String, to: String, is_dir: bool) -> String:
	if path == from:
		return to
	if is_dir and path.begins_with(from + "/"):
		return to + path.substr(from.length())
	return path


func _unsaved_warnings(paths: Array) -> PackedStringArray:
	var warnings: PackedStringArray = []
	if not unsaved_buffer.is_valid():
		return warnings
	for path: String in paths:
		if unsaved_buffer.call(ProjectSettings.globalize_path(path)) != null:
			warnings.append("Warning: %s has unsaved changes in the editor; the user will be asked which version to keep." % path)
	return warnings


func _copy_recursive(source: String, target: String, is_dir: bool, copied: PackedStringArray) -> Error:
	if not is_dir:
		if source.get_extension() in SIDECARS:
			return OK
		DirAccess.make_dir_recursive_absolute(target.get_base_dir())
		var error := DirAccess.copy_absolute(source, target)
		if error == OK:
			_renew_uid(target)
			copied.append(target)
		return error
	DirAccess.make_dir_recursive_absolute(target)
	for file: String in DirAccess.get_files_at(source):
		var error := _copy_recursive(source.path_join(file), target.path_join(file), false, copied)
		if error != OK:
			return error
	for sub: String in DirAccess.get_directories_at(source):
		if not sub.begins_with("."):
			var error := _copy_recursive(source.path_join(sub), target.path_join(sub), true, copied)
			if error != OK:
				return error
	return OK


## Una escena o recurso de texto copiado trae el uid del original en la cabecera: se cambia por uno
## nuevo para que sean dos recursos distintos.
static func _renew_uid(absolute: String) -> void:
	if not absolute.get_extension() in ["tscn", "tres"]:
		return
	var text := FileAccess.get_file_as_string(absolute)
	var header_end := text.find("\n")
	var header := text.substr(0, header_end if header_end >= 0 else text.length())
	var uid := RegEx.create_from_string(" uid=\"uid://[a-z0-9]+\"")
	if uid.search(header) == null:
		return
	var fresh := " uid=\"%s\"" % ResourceUID.id_to_text(ResourceUID.create_id())
	var file := FileAccess.open(absolute, FileAccess.WRITE)
	file.store_string(uid.sub(header, fresh) + text.substr(header.length()))
	file.close()


static func _remove_recursive(absolute: String) -> Error:
	for file: String in DirAccess.get_files_at(absolute):
		var error := DirAccess.remove_absolute(absolute.path_join(file))
		if error != OK:
			return error
	for sub: String in DirAccess.get_directories_at(absolute):
		var error := _remove_recursive(absolute.path_join(sub))
		if error != OK:
			return error
	return DirAccess.remove_absolute(absolute)


func _refresh(changed: PackedStringArray) -> void:
	if on_file_written.is_valid():
		for path: String in changed:
			on_file_written.call(ProjectSettings.globalize_path(path))
	EditorInterface.get_resource_filesystem().scan()
