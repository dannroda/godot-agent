@tool
extends RefCounted
## ui-modes (m11-39) con el agente falso (tests/scripts/ui_modes.json) y un modo del proyecto
## «Levels» (base Auto, edita solo tests/tmp/modes/levels/**) en una carpeta de modos temporal:
## 1. El selector del composer lo muestra después del separador «Project modes», como «Levels (Auto)»,
##    con lo que edita en el tooltip. Elegirlo pasa a Auto con la capa puesta, y el system prompt lleva
##    sus archivos e instrucciones.
## 2. En el turno: el Edit y el fs/write_text_file de adentro pasan sin tarjeta (Auto); los de afuera se
##    rechazan sin tarjeta, con el aviso del modo; godot.create_scene adentro crea la escena y afuera
##    falla con el motivo; godot.asset_install (no dice qué escribe) se rechaza; `ls` (en la allowlist de
##    Auto) pregunta igual, sin «siempre» ni regla.
## 3. Elegir Construir en el selector saca la capa.
## No toca los EditorSettings: la carpeta de modos va por dock.modes_dir.

const SessionModel := preload("res://addons/godot_agent/session/session_model.gd")
const PermissionRequest := preload("res://addons/godot_agent/session/permission_request.gd")
const MAIN_PLUGIN_SCRIPT := "res://addons/godot_agent/agent_plugin.gd"
const WORK_DIR := "res://tests/tmp/modes"
const WAIT_MS := 30000

var failures: Array[String] = []
var _tree: SceneTree
var _model: SessionModel


func run(tree: SceneTree, _plugin: Object, dock: Control, shot_path: String) -> Array[String]:
	_tree = tree
	_model = dock.get(&"_model")
	var controller: Object = dock.get(&"_controller")
	var saved_dir: String = dock.get(&"modes_dir")
	_cleanup()
	var dir := ProjectSettings.globalize_path(WORK_DIR)
	DirAccess.make_dir_recursive_absolute(dir.path_join("modes"))
	DirAccess.make_dir_recursive_absolute(dir.path_join("levels"))
	_write(dir.path_join("modes/levels.json"), JSON.stringify({
		"version": 1, "name": "Levels", "base": "auto", "when_to_use": "Building the test levels",
		"instructions": "Only touch the level files. Say LEVELS-MODE-OK when done.",
		"editable": [WORK_DIR + "/levels/**"], "icon": "TileMap",
	}, "\t"))
	_write(dir.path_join("modes/broken.json"), "{\"name\": \"Broken\", \"base\": \"oneshot\"}")
	dock.set(&"modes_dir", WORK_DIR + "/modes")
	dock.call(&"load_project_modes")
	await _check(dock, controller, shot_path)
	_model.set_project_mode({})
	_model.set_harness_mode(SessionModel.HarnessMode.BUILD)
	dock.set(&"modes_dir", saved_dir)
	dock.call(&"load_project_modes")
	_cleanup()
	return failures


func _check(dock: Control, controller: Object, shot_path: String) -> void:
	# 1. El selector.
	var composer: Object = dock.get(&"_composer")
	var button: OptionButton = composer.get(&"_mode_button")
	var separator := -1
	var item := -1
	for index: int in button.item_count:
		if button.is_item_separator(index) and button.get_item_text(index) == "Project modes":
			separator = index
		elif button.get_item_text(index) == "Levels (Auto)":
			item = index
	_expect(separator >= 0, "el separador «Project modes» está en el selector")
	_expect(item > separator, "«Levels (Auto)» va después del separador")
	_expect(not _items(button).any(func(text: String) -> bool: return text.begins_with("Broken")), "un modo con errores no sale")
	if item < 0:
		return
	var tooltip := button.get_item_tooltip(item)
	_expect(tooltip.contains("Building the test levels") and tooltip.contains("edits only " + WORK_DIR + "/levels/**") and tooltip.contains("shell always asks"), "el tooltip dice cuándo usarlo y qué edita · %s" % tooltip)
	_model.set_harness_mode(SessionModel.HarnessMode.ASK)
	_expect(bool(dock.call(&"choose_project_mode", "levels")), "se elige por el slug")
	_expect(_model.harness_mode == SessionModel.HarnessMode.AUTO and _model.project_mode.get("name") == "Levels", "pasa a Auto con la capa puesta")
	_expect(button.get_item_text(button.selected) == "Levels (Auto)", "el selector lo muestra elegido · %s" % button.get_item_text(button.selected))
	var prompt := str(controller.call(&"system_prompt"))
	_expect(prompt.contains("Levels (a project mode based on Auto)") and prompt.contains("LEVELS-MODE-OK") and prompt.contains("you may only write files matching " + WORK_DIR + "/levels/**"), "el system prompt lleva el modo, sus archivos y sus instrucciones")
	if not shot_path.is_empty():
		for i in 10:
			await _tree.process_frame
		dock.get_viewport().get_texture().get_image().save_png(shot_path.get_basename() + "_modes.png")

	# 2. El turno.
	dock.call(&"_on_submitted", "Build the room.")
	var deadline := Time.get_ticks_msec() + WAIT_MS
	while _model.pending_permissions.is_empty() and _model.is_busy() and Time.get_ticks_msec() < deadline:
		await _tree.process_frame
	_expect(_model.pending_permissions.size() == 1, "una sola tarjeta en todo el turno: la de la shell")
	if not _model.pending_permissions.is_empty():
		var request: PermissionRequest = _model.pending_permissions[0]
		_expect(request.description == "ls", "la tarjeta es la de `ls` · %s" % request.description)
		_expect(request.rule_pattern.is_empty() and request.option_id_for([PermissionRequest.KIND_ALLOW_ALWAYS]).is_empty(), "sin regla de Auto ni «siempre»")
		request.select(request.option_id_for([PermissionRequest.KIND_REJECT_ONCE]))
	deadline = Time.get_ticks_msec() + WAIT_MS
	while _model.is_busy() and Time.get_ticks_msec() < deadline:
		await _tree.process_frame
	_expect(not _model.is_busy(), "el turno terminó")
	var dir := ProjectSettings.globalize_path(WORK_DIR)
	_expect(FileAccess.get_file_as_string(dir.path_join("levels/a.gd")) == "extends Node\n", "fs/write adentro escribió")
	_expect(not FileAccess.file_exists(dir.path_join("outside.gd")), "fs/write afuera no escribió")
	_expect(_notice_with("Rejected: mode «Levels» only edits") != null and _notice_with("outside.gd") != null, "el aviso del rechazo nombra el modo y el archivo")
	_expect(_notice_with("a.gd") == null or not str(_notice_with("a.gd").get(&"text")).contains("Rejected"), "adentro no hay aviso de rechazo")
	var inside: Object = _model.tool_call("mcp-1")
	var outside: Object = _model.tool_call("mcp-2")
	var asset: Object = _model.tool_call("mcp-3")
	_expect(inside != null and inside.status == "completed" and FileAccess.file_exists(dir.path_join("levels/room.tscn")), "godot.create_scene adentro creó la escena")
	_expect(outside != null and outside.status == "failed" and str(outside.raw_output).contains("Rejected by the project mode «Levels»"), "godot.create_scene afuera falla con el motivo · %s" % (str(outside.raw_output).left(200) if outside else "sin tool call"))
	_expect(not FileAccess.file_exists(dir.path_join("room.tscn")), "y no creó nada")
	_expect(asset != null and asset.status == "failed" and str(asset.raw_output).contains("a file the harness can't see"), "godot.asset_install, que no dice qué escribe, se rechaza · %s" % (str(asset.raw_output).left(200) if asset else "sin tool call"))
	if not failures.is_empty():
		_dump()

	# 3. Un modo fijo saca la capa.
	composer.call(&"choose_mode", SessionModel.HarnessMode.BUILD)
	_expect(_model.project_mode.is_empty() and _model.harness_mode == SessionModel.HarnessMode.BUILD, "elegir Construir saca el modo del proyecto")


func _items(button: OptionButton) -> Array:
	var texts: Array = []
	for index: int in button.item_count:
		texts.append(button.get_item_text(index))
	return texts


func _cleanup() -> void:
	var dir := ProjectSettings.globalize_path(WORK_DIR)
	for file: String in ["modes/levels.json", "modes/broken.json", "levels/a.gd", "levels/room.tscn", "outside.gd", "room.tscn"]:
		if FileAccess.file_exists(dir.path_join(file)):
			DirAccess.remove_absolute(dir.path_join(file))
	for sub: String in ["modes", "levels", ""]:
		DirAccess.remove_absolute(dir.path_join(sub))


func _write(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()


func _notice_with(text: String) -> Object:
	var found: Object = null
	for entry: Object in _model.entries():
		if int(entry.get(&"kind")) == 7 and str(entry.get(&"text")).contains(text):
			found = entry
	return found


func _dump() -> void:
	for entry: Object in _model.entries():
		var kind := int(entry.get(&"kind"))
		if kind in [0, 1, 7]:
			print("[modes-check] %s: %s" % [{0: "user", 1: "agent", 7: "notice"}[kind], str(entry.get(&"text")).left(300).replace("\n", " ")])


func _expect(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
