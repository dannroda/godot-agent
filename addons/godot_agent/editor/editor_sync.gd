@tool
extends Node
## Sincronización editor ↔ disco (spec §8). Claude Code escribe con sus propias herramientas,
## directo al disco: el editor se pone al día después de una escritura del agente (fs/write, un
## tool call de edición o el watcher de scripts, escenas abiertas y project.godot):
## - avisa a EditorFileSystem;
## - si el script está abierto sin cambios, carga la versión del disco en el CodeEdit (deshacible,
##   conservando cursor y scroll) y alinea la fecha del recurso para que no salga el diálogo de
##   "modificado afuera";
## - si el usuario tenía cambios sin guardar, no pisa: emite `conflict_detected`;
## - una escena abierta sin cambios sin guardar se recarga sola; con cambios, no se pisa y se
##   emite `open_scene_modified` (se recarga solo si el usuario acepta);
## - `project.godot` se aplica a ProjectSettings y el editor lo guarda: queda igual que el archivo
##   y Godot no pregunta si recargarlo.

signal conflict_detected(res_path: String)
signal conflict_resolved(res_path: String)
signal open_scene_modified(res_path: String)
## project.godot cambió en disco y se aplicó al editor (`names`: settings que cambiaron).
signal project_settings_applied(names: PackedStringArray)

const AgentLog := preload("../core/agent_log.gd")
const EditorContext := preload("../ui/editor_context.gd")

const POLL_INTERVAL_S := 0.5
const PROJECT_FILE := "res://project.godot"
const EDITOR_MANAGED_EXTENSIONS: PackedStringArray = ["uid", "import"]

var agent_log: AgentLog
## res_path -> mtime visto la última vez (scripts abiertos).
var _known_mtimes: Dictionary = {}
## res_path -> texto del disco en conflicto.
var _conflicts: Dictionary = {}
## res_path -> mtime visto la última vez (escenas abiertas).
var _scene_mtimes: Dictionary = {}
var _project_mtime: int = 0
## project.godot tal como se vio la última vez: para saber qué settings se borraron.
var _project_snapshot: ConfigFile
var _poll_timer: Timer


func setup(log_sink: AgentLog) -> void:
	agent_log = log_sink


func _ready() -> void:
	_poll_timer = Timer.new()
	_poll_timer.wait_time = POLL_INTERVAL_S
	_poll_timer.autostart = true
	_poll_timer.timeout.connect(_poll)
	add_child(_poll_timer)
	_remember_project_file()


func conflicts() -> PackedStringArray:
	return PackedStringArray(_conflicts.keys())


func conflict_disk_text(res_path: String) -> String:
	return _conflicts.get(res_path, "")


# --- lectura -------------------------------------------------------------------------------------

## Texto del buffer si el archivo está abierto con cambios sin guardar; si no, null (leer disco).
func buffer_text(abs_path: String) -> Variant:
	var res_path := EditorContext.to_res_path(abs_path)
	if res_path.is_empty():
		return null
	var open := _open_editor(res_path)
	if open.is_empty():
		return null
	var code_edit: CodeEdit = open.code_edit
	if _is_dirty(code_edit):
		return code_edit.text
	return null


# --- escritura -----------------------------------------------------------------------------------

## Llamado después de que el agente escribió un archivo a disco.
func after_agent_write(abs_path: String, _old_text: String = "", _new_text: String = "") -> void:
	var res_path := EditorContext.to_res_path(abs_path)
	if res_path.is_empty():
		return
	sync_path(res_path)


func sync_path(res_path: String) -> void:
	if res_path.get_extension() in EDITOR_MANAGED_EXTENSIONS:
		_log("aviso: el agente modificó %s (lo maneja el editor)" % res_path)
	if res_path == PROJECT_FILE:
		apply_project_file()
		return
	if res_path.get_extension() in ["tscn", "scn"] and res_path in EditorInterface.get_open_scenes():
		_sync_open_scene(res_path)
		return
	var open := _open_editor(res_path)
	if not open.is_empty():
		_sync_open_script(res_path, open)
	else:
		_reload_cached_script(res_path)
	_update_filesystem(res_path)


func _poll() -> void:
	poll_open_scripts()
	poll_open_scenes()
	poll_project_file()


## Watcher: detecta escrituras al disco de scripts abiertos que no pasaron por fs/write
## (p. ej. herramientas propias del agente).
func poll_open_scripts() -> void:
	for open: Dictionary in _open_editors():
		var script: Script = open.script
		var res_path := script.resource_path
		if res_path.is_empty() or not FileAccess.file_exists(res_path):
			continue
		var mtime := FileAccess.get_modified_time(res_path)
		if not _known_mtimes.has(res_path):
			_known_mtimes[res_path] = mtime
			continue
		if _known_mtimes[res_path] == mtime:
			continue
		_known_mtimes[res_path] = mtime
		_sync_open_script(res_path, open)


func _sync_open_script(res_path: String, open: Dictionary) -> void:
	var code_edit: CodeEdit = open.code_edit
	var script: Script = open.script
	var disk_text := FileAccess.get_file_as_string(res_path)
	_known_mtimes[res_path] = FileAccess.get_modified_time(res_path)
	if code_edit.text == disk_text:
		# Lo guardó el usuario, o ya está al día: solo se alinea la fecha del recurso.
		if script.source_code != disk_text:
			_adopt_resource(script, disk_text)
		return
	if _is_dirty(code_edit):
		_conflicts[res_path] = disk_text
		_log("conflicto: %s tiene cambios sin guardar y el agente lo modificó" % res_path)
		conflict_detected.emit(res_path)
		return
	replace_buffer(code_edit, disk_text)
	code_edit.tag_saved_version()
	_adopt_resource(script, disk_text)
	_log("recargado en el Script Editor: %s" % res_path)


## Watcher de escenas abiertas. Los guardados del editor no cuentan: los avisa `note_scene_saved`.
func poll_open_scenes() -> void:
	var open_scenes := EditorInterface.get_open_scenes()
	for res_path: String in _scene_mtimes.keys():
		if not res_path in open_scenes:
			_scene_mtimes.erase(res_path)
	for res_path: String in open_scenes:
		if res_path.is_empty() or not FileAccess.file_exists(res_path):
			continue
		var mtime := FileAccess.get_modified_time(res_path)
		if not _scene_mtimes.has(res_path):
			_scene_mtimes[res_path] = mtime
		elif _scene_mtimes[res_path] != mtime:
			_sync_open_scene(res_path)


## El editor guardó la escena (EditorPlugin.scene_saved): no es un cambio del agente.
func note_scene_saved(res_path: String) -> void:
	if FileAccess.file_exists(res_path):
		_scene_mtimes[res_path] = FileAccess.get_modified_time(res_path)
	if res_path == PROJECT_FILE:
		_remember_project_file()


func poll_project_file() -> void:
	if FileAccess.file_exists(PROJECT_FILE) and FileAccess.get_modified_time(PROJECT_FILE) != _project_mtime:
		apply_project_file()


## Pone ProjectSettings igual a project.godot (lo que el agente agregó, cambió o borró) y lo guarda
## desde el editor: así Godot no pregunta si recargarlo, y un guardado posterior del editor no pisa
## lo del agente. Si el editor ya tenía lo mismo (lo guardó él), no hace nada. Un archivo que no
## se puede leer no se toca: queda el diálogo de Godot.
func apply_project_file() -> PackedStringArray:
	var changed: PackedStringArray = []
	var file := ConfigFile.new()
	var error := file.load(PROJECT_FILE)
	if error != OK:
		_project_mtime = FileAccess.get_modified_time(PROJECT_FILE)
		_log("project.godot cambió en disco pero no se puede leer (%s): no se aplicó" % error_string(error))
		return changed
	for section: String in file.get_sections():
		if section.is_empty():
			continue  # config_version: es del formato, no un setting
		for key: String in file.get_section_keys(section):
			var setting := "%s/%s" % [section, key]
			var value: Variant = file.get_value(section, key)
			if not ProjectSettings.has_setting(setting) or var_to_str(ProjectSettings.get_setting(setting)) != var_to_str(value):
				ProjectSettings.set_setting(setting, value)
				changed.append(setting)
	if _project_snapshot:
		for section: String in _project_snapshot.get_sections():
			if section.is_empty():
				continue
			for key: String in _project_snapshot.get_section_keys(section):
				var setting := "%s/%s" % [section, key]
				if not file.has_section_key(section, key) and ProjectSettings.has_setting(setting):
					ProjectSettings.set_setting(setting, null)
					changed.append(setting)
	if not changed.is_empty():
		var save_error := ProjectSettings.save()
		if save_error != OK:
			_log("no se pudo guardar project.godot: %s" % error_string(save_error))
		_log("project.godot: el editor tomó %d %s del disco (%s)" % [changed.size(), "cambio" if changed.size() == 1 else "cambios", ", ".join(changed.slice(0, 6))])
		project_settings_applied.emit(changed)
	_project_snapshot = file
	_project_mtime = FileAccess.get_modified_time(PROJECT_FILE)
	return changed


func _remember_project_file() -> void:
	if not FileAccess.file_exists(PROJECT_FILE):
		return
	var file := ConfigFile.new()
	if file.load(PROJECT_FILE) == OK:
		_project_snapshot = file
	_project_mtime = FileAccess.get_modified_time(PROJECT_FILE)


## Escena abierta que cambió en disco: sin cambios sin guardar se recarga (sin el diálogo de
## Godot); con cambios, no se pisa y se avisa. Sin `get_unsaved_scenes` (Godot 4.6) no se puede
## saber, así que se avisa siempre.
func _sync_open_scene(res_path: String) -> void:
	_scene_mtimes[res_path] = FileAccess.get_modified_time(res_path)
	_update_filesystem(res_path)
	var unsaved: PackedStringArray = EditorInterface.call(&"get_unsaved_scenes") if EditorInterface.has_method(&"get_unsaved_scenes") else PackedStringArray([res_path])
	if res_path in unsaved:
		_log("escena abierta con cambios sin guardar modificada en disco: %s" % res_path)
		open_scene_modified.emit(res_path)
		return
	reload_scene(res_path)


## Conflicto: usar la versión del agente (el cambio en el buffer se puede deshacer con Ctrl+Z).
func resolve_use_disk(res_path: String) -> void:
	var open := _open_editor(res_path)
	_conflicts.erase(res_path)
	if open.is_empty():
		conflict_resolved.emit(res_path)
		return
	var disk_text := FileAccess.get_file_as_string(res_path)
	var code_edit: CodeEdit = open.code_edit
	replace_buffer(code_edit, disk_text)
	code_edit.tag_saved_version()
	_adopt_resource(open.script, disk_text)
	_log("conflicto resuelto con la versión del agente: %s" % res_path)
	conflict_resolved.emit(res_path)


## Conflicto: mantener el buffer del usuario. Se guarda a disco: pisa la versión del agente.
func resolve_keep_buffer(res_path: String) -> void:
	var open := _open_editor(res_path)
	_conflicts.erase(res_path)
	if not open.is_empty():
		var code_edit: CodeEdit = open.code_edit
		_adopt_resource(open.script, code_edit.text)
		code_edit.tag_saved_version()
		_known_mtimes[res_path] = FileAccess.get_modified_time(res_path)
		_update_filesystem(res_path)
	_log("conflicto resuelto con la versión del usuario: %s" % res_path)
	conflict_resolved.emit(res_path)


func reload_scene(res_path: String) -> void:
	EditorInterface.reload_scene_from_path(res_path)
	if FileAccess.file_exists(res_path):
		_scene_mtimes[res_path] = FileAccess.get_modified_time(res_path)
	_log("escena recargada: %s" % res_path)


## Reemplaza solo el tramo de líneas que cambió, en una operación deshacible, y conserva el
## cursor y el scroll.
static func replace_buffer(code_edit: CodeEdit, new_text: String) -> void:
	var old_lines := code_edit.text.split("\n")
	var new_lines := new_text.split("\n")
	var prefix := 0
	while prefix < old_lines.size() and prefix < new_lines.size() and old_lines[prefix] == new_lines[prefix]:
		prefix += 1
	var suffix := 0
	while (suffix < old_lines.size() - prefix and suffix < new_lines.size() - prefix
			and old_lines[old_lines.size() - 1 - suffix] == new_lines[new_lines.size() - 1 - suffix]):
		suffix += 1
	if prefix == old_lines.size() and prefix == new_lines.size():
		return
	var caret_line := code_edit.get_caret_line()
	var caret_column := code_edit.get_caret_column()
	var scroll := code_edit.scroll_vertical
	var delta := new_lines.size() - old_lines.size()

	var old_end := old_lines.size() - suffix  # primera línea que no cambia, al final
	var new_count := new_lines.size() - suffix - prefix
	var middle := "\n".join(new_lines.slice(prefix, prefix + new_count))
	code_edit.begin_complex_operation()
	code_edit.deselect()
	if old_end > prefix and new_count > 0:
		# Reemplazo de las líneas [prefix, old_end).
		code_edit.select(prefix, 0, old_end - 1, old_lines[old_end - 1].length())
		code_edit.insert_text_at_caret(middle)
	elif old_end > prefix:
		# Borrado de líneas enteras, con su salto de línea.
		if old_end < old_lines.size():
			code_edit.select(prefix, 0, old_end, 0)
		else:
			code_edit.select(prefix - 1, old_lines[prefix - 1].length(), old_end - 1, old_lines[old_end - 1].length())
		code_edit.delete_selection()
	elif prefix < old_lines.size():
		# Inserción antes de la línea `prefix`.
		code_edit.set_caret_line(prefix, false)
		code_edit.set_caret_column(0, false)
		code_edit.insert_text_at_caret(middle + "\n")
	else:
		code_edit.set_caret_line(old_lines.size() - 1, false)
		code_edit.set_caret_column(old_lines[old_lines.size() - 1].length(), false)
		code_edit.insert_text_at_caret("\n" + middle)
	code_edit.end_complex_operation()
	var target_line := caret_line + delta if caret_line >= old_end else mini(caret_line, new_lines.size() - 1)
	code_edit.set_caret_line(clampi(target_line, 0, code_edit.get_line_count() - 1), false)
	code_edit.set_caret_column(caret_column, false)
	code_edit.scroll_vertical = scroll


# --- internos ------------------------------------------------------------------------------------

func _update_filesystem(res_path: String) -> void:
	var fs := EditorInterface.get_resource_filesystem()
	if fs.get_file_type(res_path).is_empty():
		fs.scan()
	else:
		fs.update_file(res_path)


## Alinea el recurso Script con el texto del disco: ResourceSaver deja la fecha de modificación
## del recurso igual a la del archivo, así el Script Editor no ofrece recargarlo.
func _adopt_resource(script: Script, text: String) -> void:
	script.source_code = text
	var error := ResourceSaver.save(script, script.resource_path)
	if error != OK:
		_log("no se pudo alinear %s: %s" % [script.resource_path, error_string(error)])
		return
	_known_mtimes[script.resource_path] = FileAccess.get_modified_time(script.resource_path)
	script.reload(true)
	_update_filesystem(script.resource_path)
	_notify_saved(script)


## El Script Editor guarda la fecha de cada pestaña y solo la actualiza con la señal
## `resource_saved` de EditorNode (que ResourceSaver no emite). Sin esto, al volver el foco
## recarga el archivo con set_text y agrega un paso de undo.
func _notify_saved(resource: Resource) -> void:
	var editor_node := _editor_node()
	if editor_node and editor_node.has_signal(&"resource_saved"):
		editor_node.emit_signal(&"resource_saved", resource)


func _editor_node() -> Node:
	if not is_inside_tree():
		return null
	for child: Node in get_tree().root.get_children():
		if child.is_class("EditorNode"):
			return child
	return null


## Script cerrado pero cargado en memoria (p. ej. por una escena abierta): se recarga del disco.
func _reload_cached_script(res_path: String) -> void:
	if res_path.get_extension() != "gd" or not ResourceLoader.has_cached(res_path):
		return
	var script := load(res_path) as Script
	if script:
		script.source_code = FileAccess.get_file_as_string(res_path)
		script.reload(true)


func _open_editor(res_path: String) -> Dictionary:
	for open: Dictionary in _open_editors():
		if (open.script as Script).resource_path == res_path:
			return open
	return {}


## Pares {script, code_edit} de los scripts abiertos. `get_open_scripts` y
## `get_open_script_editors` recorren las pestañas en el mismo orden; si la cantidad no coincide
## (hay archivos de texto abiertos), se empareja por contenido.
func _open_editors() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var script_editor := EditorInterface.get_script_editor()
	if script_editor == null:
		return result
	var scripts := script_editor.get_open_scripts()
	var editors := script_editor.get_open_script_editors()
	var code_edits: Array[CodeEdit] = []
	for editor: ScriptEditorBase in editors:
		var base := editor.get_base_editor() as CodeEdit
		if base:
			code_edits.append(base)
	if scripts.size() == code_edits.size():
		for i in scripts.size():
			result.append({"script": scripts[i], "code_edit": code_edits[i]})
		return result
	var used: Dictionary = {}
	for script: Script in scripts:
		for code_edit: CodeEdit in code_edits:
			if not used.has(code_edit) and code_edit.text == script.source_code:
				used[code_edit] = true
				result.append({"script": script, "code_edit": code_edit})
				break
	return result


static func _is_dirty(code_edit: CodeEdit) -> bool:
	return code_edit.get_version() != code_edit.get_saved_version()


func _log(message: String) -> void:
	if agent_log:
		agent_log.add(AgentLog.CH_FS, message)
