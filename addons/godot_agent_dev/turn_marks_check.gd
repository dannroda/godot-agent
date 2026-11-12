@tool
extends RefCounted
## turn-marks (m11-66): los trozos del último turno en el Script Editor, con snapshots de git de verdad.
## 1. Un script de tests/m11_66_fixture cambia en dos lugares entre dos snapshots: es el último turno de la
##    pestaña activa. Abierto en el Script Editor, el gutter marca los dos trozos en sus líneas y la banda
##    dice «2 to review».
## 2. ✓ en el primero lo marca conservado (el archivo no cambia); ✗ en el segundo lo rechaza: el archivo
##    y el editor vuelven a las líneas de antes, y el chat dice «Rejected a change…». ✗ otra vez lo
##    vuelve a aplicar.
## 3. Una línea escrita arriba (sin guardar) corre las marcas una línea, y el ✗ no rechaza: el motivo
##    (cambios sin guardar) sale en la banda.

const PLUGIN_SCRIPT := "res://addons/godot_agent/agent_plugin.gd"
const FOLDER := "res://tests/m11_66_fixture"
const SCRIPT_PATH := FOLDER + "/marks_target.gd"
const BEFORE := "extends CharacterBody2D\n\nvar speed := 100\n\n\nfunc _ready() -> void:\n\tprint(\"ready\")\n\n\nfunc jump() -> void:\n\tpass\n"
const AFTER := "extends CharacterBody2D\n\nvar speed := 250\n\n\nfunc _ready() -> void:\n\tprint(\"ready\")\n\n\nfunc jump() -> void:\n\tvelocity.y = -400\n\tprint(\"jump\")\n"

var failures: PackedStringArray = []
var _tree: SceneTree


func run(tree: SceneTree, _dock: Control) -> PackedStringArray:
	_tree = tree
	var plugin: Node = null
	for node: Node in tree.root.find_children("*", "Node", true, false):
		if node.get_script() and (node.get_script() as Script).resource_path == PLUGIN_SCRIPT:
			plugin = node
	if plugin == null:
		return PackedStringArray(["no se encontró el plugin"])
	var snapshots: Object = plugin.get(&"_turn_snapshots")
	var marks: Object = plugin.get(&"_turn_marks")
	var controller: Object = plugin.get(&"_controller")
	if snapshots == null or not snapshots.get(&"available"):
		return PackedStringArray(["sin snapshots de git en el proyecto"])
	if marks == null:
		return PackedStringArray(["sin _turn_marks en el plugin"])
	var saved_changes: Dictionary = controller.get(&"last_turn_changes")
	await _check(snapshots, marks, controller)
	controller.set(&"last_turn_changes", saved_changes)
	marks.call(&"refresh")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SCRIPT_PATH))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SCRIPT_PATH + ".uid"))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(FOLDER))
	EditorInterface.get_resource_filesystem().scan()
	return failures


func _check(snapshots: Object, marks: Object, controller: Object) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(FOLDER))
	_write(BEFORE)
	var session := str(controller.get(&"session_key"))
	var start: String = await snapshots.call(&"take", session)
	_write(AFTER)
	var end: String = await snapshots.call(&"take", session)
	var rel := SCRIPT_PATH.trim_prefix("res://")
	EditorInterface.get_resource_filesystem().update_file(SCRIPT_PATH)
	await _tree.create_timer(0.5).timeout
	var data := {"session": session, "start": start, "end": end, "files": [{"path": rel, "status": "M", "added": 3, "removed": 2}]}
	controller.set(&"last_turn_changes", data)
	EditorInterface.edit_script(load(SCRIPT_PATH))
	EditorInterface.set_main_screen_editor("Script")
	controller.emit_signal(&"turn_changes_reported", data)

	# 1. Las marcas.
	var shown: Array = await _wait_hunks(marks, 2)
	_expect(shown.size() == 2, "dos trozos marcados: %s" % [shown])
	if shown.size() != 2:
		return
	_expect(int(shown[0].line) == 2 and int(shown[1].line) == 10, "en sus líneas (3 y 11): %s" % [shown.map(func(h: Dictionary) -> int: return h.line)])
	var lines: Dictionary = marks.call(&"marked_lines", SCRIPT_PATH)
	_expect(lines.has(11) and not lines[11].first, "el segundo trozo marca sus dos líneas: %s" % [lines.keys()])
	_expect(str(marks.call(&"band_text", SCRIPT_PATH)).contains("2 to review"), "la banda: %s" % marks.call(&"band_text", SCRIPT_PATH))
	await _shot("turn_marks")

	# 2. ✓ y ✗.
	var error: String = await marks.call(&"act", SCRIPT_PATH, int(shown[0].index), true)
	_expect(error.is_empty(), "✓ conserva: %s" % error)
	shown = await _wait_state(marks, int(shown[0].index), "kept")
	_expect(FileAccess.get_file_as_string(SCRIPT_PATH) == AFTER, "conservar no cambia el archivo")
	_expect(str(marks.call(&"band_text", SCRIPT_PATH)).contains("1 kept"), "la banda cuenta el conservado: %s" % marks.call(&"band_text", SCRIPT_PATH))
	var second := int(shown[1].index)
	error = await marks.call(&"act", SCRIPT_PATH, second, false)
	_expect(error.is_empty(), "✗ rechaza: %s" % error)
	shown = await _wait_state(marks, second, "rejected")
	_expect(FileAccess.get_file_as_string(SCRIPT_PATH).ends_with("func jump() -> void:\n\tpass\n"), "el archivo vuelve a lo de antes en ese trozo")
	_expect(FileAccess.get_file_as_string(SCRIPT_PATH).contains("speed := 250"), "y deja el otro")
	var code := _code_edit()
	_expect(code != null and code.text.contains("\tpass") and not code.text.contains("velocity.y"), "el editor muestra el archivo nuevo")
	_expect(_notices(controller).any(func(t: String) -> bool: return t.contains("Rejected a change in %s" % rel)), "el chat lo dice")
	await _shot("turn_marks_rejected")
	error = await marks.call(&"act", SCRIPT_PATH, second, false)
	_expect(error.is_empty(), "✗ en un rechazado lo vuelve a aplicar: %s" % error)
	shown = await _wait_state(marks, second, "")
	_expect(FileAccess.get_file_as_string(SCRIPT_PATH) == AFTER, "con el trozo de vuelta")

	# 3. Una línea escrita arriba corre las marcas y bloquea el rechazo.
	code = _code_edit()
	if code == null:
		failures.append("sin CodeEdit")
		return
	code.set_caret_line(0)
	code.set_caret_column(0)
	code.insert_text_at_caret("# a note\n")
	for i in 4:
		await _tree.process_frame
	shown = marks.call(&"hunks_shown", SCRIPT_PATH)
	_expect(shown.size() == 2 and int(shown[0].line) == 3 and int(shown[1].line) == 11, "las marcas bajan una línea: %s" % [shown.map(func(h: Dictionary) -> int: return h.line)])
	marks.call(&"refresh")
	shown = await _wait_hunks(marks, 2)
	error = await marks.call(&"act", SCRIPT_PATH, second, false)
	_expect(error.contains("unsaved changes"), "con cambios sin guardar no rechaza: %s" % error)
	_expect(str(marks.call(&"band_text", SCRIPT_PATH)).contains("unsaved changes"), "y la banda dice por qué")
	_expect(FileAccess.get_file_as_string(SCRIPT_PATH) == AFTER, "no escribió nada")
	code.undo()
	code.tag_saved_version()


func _wait_hunks(marks: Object, count: int) -> Array:
	var deadline := Time.get_ticks_msec() + 10000
	var shown: Array = []
	while Time.get_ticks_msec() < deadline:
		shown = marks.call(&"hunks_shown", SCRIPT_PATH)
		if shown.size() == count:
			return shown
		await _tree.process_frame
	return shown


func _wait_state(marks: Object, index: int, state: String) -> Array:
	var deadline := Time.get_ticks_msec() + 10000
	var shown: Array = []
	while Time.get_ticks_msec() < deadline:
		shown = marks.call(&"hunks_shown", SCRIPT_PATH)
		for hunk: Dictionary in shown:
			if int(hunk.index) == index and str(hunk.state) == state:
				return shown
		await _tree.process_frame
	failures.append("el trozo %d no llegó a «%s»: %s" % [index, state, shown])
	return shown


func _code_edit() -> CodeEdit:
	var current := EditorInterface.get_script_editor().get_current_editor()
	return current.get_base_editor() as CodeEdit if current else null


func _notices(controller: Object) -> Array:
	var model: Object = controller.get(&"model")
	return model.call(&"entries").filter(func(e: Object) -> bool: return int(e.get(&"kind")) == 7).map(func(e: Object) -> String: return str(e.get(&"text")))


func _shot(name: String) -> void:
	var dir := OS.get_environment("SUITE_LOGS")
	if dir.is_empty():
		return
	for i in 10:
		await _tree.process_frame
	EditorInterface.get_base_control().get_viewport().get_texture().get_image().save_png(dir.path_join(name + ".png"))


func _write(text: String) -> void:
	var file := FileAccess.open(SCRIPT_PATH, FileAccess.WRITE)
	file.store_string(text)
	file.close()


func _expect(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
