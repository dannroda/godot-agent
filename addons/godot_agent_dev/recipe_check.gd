@tool
extends RefCounted
## ui-recipe (m11-30) con el agente falso (tests/scripts/ui_recipe.json):
## 1. `/recipe fix_target` abre el formulario generado de la receta (una carpeta de recetas temporal);
##    «Usar» sin lo obligatorio no sale; con los valores, el prompt expandido queda en el composer (no
##    se manda), en el modo de la receta, con el chip «Receta: … · checks: Lint».
## 2. Mandarlo arranca la corrida: el agente deja target.gd «broken», el check Lint de la receta falla
##    y su salida vuelve como prompt del harness «Receta · falló un check».
## 3. El segundo turno lo arregla: el aviso final dice «checks passed (attempt 2)» y la corrida termina.
## Las aprobaciones van a una tienda en memoria (el Xvfb usa los EditorSettings del usuario).

const SessionModel := preload("res://addons/godot_agent/session/session_model.gd")
const HarnessPrompts := preload("res://addons/godot_agent/session/harness_prompts.gd")
const HarnessSettings := preload("res://addons/godot_agent/core/harness_settings.gd")
const TurnChecks := preload("res://addons/godot_agent/core/turn_checks.gd")
const MAIN_PLUGIN_SCRIPT := "res://addons/godot_agent/agent_plugin.gd"
const WORK_DIR := "res://tests/tmp/recipe"
const WAIT_MS := 30000

var failures: Array[String] = []
var _tree: SceneTree
var _model: SessionModel


func run(tree: SceneTree, dock: Control, shot_path: String) -> Array[String]:
	_tree = tree
	_model = dock.get(&"_model")
	var controller: Object = dock.get(&"_controller")
	var saved := {"is_approved": controller.get(&"is_command_approved"), "approve": controller.get(&"approve_command"), "dir": dock.get(&"recipes_dir")}
	await _check(dock, controller, shot_path)
	controller.set(&"is_command_approved", saved.is_approved)
	controller.set(&"approve_command", saved.approve)
	dock.set(&"recipes_dir", saved.dir)
	var dir := ProjectSettings.globalize_path(WORK_DIR)
	for file: String in ["target.gd", "lint.gd", "recipes/fix_target.json"]:
		DirAccess.remove_absolute(dir.path_join(file))
	DirAccess.remove_absolute(dir.path_join("recipes"))
	return failures


func _check(dock: Control, controller: Object, shot_path: String) -> void:
	var dir := ProjectSettings.globalize_path(WORK_DIR)
	DirAccess.make_dir_recursive_absolute(dir.path_join("recipes"))
	var target := dir.path_join("target.gd")
	_write(target, "extends Node\nvar state := \"fine\"\n")
	_write(dir.path_join("lint.gd"), "extends SceneTree\n\nfunc _init() -> void:\n\tif FileAccess.get_file_as_string(\"%s\").contains(\"broken\"):\n\t\tprint(\"lint: target.gd is broken\")\n\t\tquit(1)\n\telse:\n\t\tquit(0)\n" % target)
	var lint := "{godot} --headless --script \"%s\"" % dir.path_join("lint.gd")
	_write(dir.path_join("recipes/fix_target.json"), JSON.stringify({
		"version": 1, "title": "Fix the target", "description": "Writes the target script and keeps Lint green.", "mode": "auto",
		"prompt": "Write {{script}} so that it {{what}}.",
		"parameters": [
			{"key": "script", "type": "script", "label": "Script"},
			{"key": "what", "type": "multiline", "label": "What it does"},
		],
		"checks": [{"kind": "command", "name": "Lint", "command": lint}],
		"max_retries": 2,
	}, "\t"))
	dock.set(&"recipes_dir", WORK_DIR + "/recipes")
	var store := HarnessSettings.new()
	store.approve_command(TurnChecks.approval_key(ProjectSettings.globalize_path("res://"), lint))
	controller.set(&"is_command_approved", store.is_command_approved)
	controller.set(&"approve_command", store.approve_command)
	_model.set_harness_mode(SessionModel.HarnessMode.ASK)

	# 1. El formulario.
	dock.call(&"_on_submitted", "/recipe fix_target")
	await _tree.process_frame
	var form: ConfirmationDialog = dock.get(&"_recipe_form")
	_expect(form != null and form.visible, "/recipe abre el formulario")
	if form == null:
		return
	_expect(_model.entries().filter(func(e: Variant) -> bool: return e.get(&"kind") == 0).is_empty(), "el comando no va al agente")
	form.call(&"_on_confirmed")
	_expect(form.visible, "sin lo obligatorio, «Usar» no sale")
	form.call(&"set_value", "script", WORK_DIR + "/target.gd")
	form.call(&"set_value", "what", "keeps its state fine")
	if not shot_path.is_empty():
		for i in 10:
			await _tree.process_frame
		form.get_texture().get_image().save_png(shot_path.get_basename() + "_recipe_form.png")
	form.call(&"_on_confirmed")
	_expect(not form.visible, "«Usar» cierra el formulario")
	var composer: Object = dock.get(&"_composer")
	var text := str(composer.call(&"current_text"))
	_expect(text == "Write @%s/target.gd so that it keeps its state fine." % WORK_DIR, "el prompt expandido queda en el composer · %s" % text)
	_expect(_model.harness_mode == SessionModel.HarnessMode.AUTO, "en el modo de la receta")
	_expect(not (dock.call(&"recipe_chip") as Dictionary).is_empty(), "con el chip de la receta")
	_expect(not _model.is_busy() and _model.entries().filter(func(e: Variant) -> bool: return e.get(&"kind") == 0).is_empty(), "no se mandó nada")
	if not shot_path.is_empty():
		for i in 10:
			await _tree.process_frame
		dock.get_viewport().get_texture().get_image().save_png(shot_path.get_basename() + "_recipe_chip.png")

	# 2. Mandarlo: el check de la receta falla y vuelve al agente.
	dock.call(&"_on_submitted", text)
	_expect((dock.call(&"recipe_chip") as Dictionary).is_empty(), "el chip sale con el mensaje")
	var fix: Object = await _wait_user_entry(HarnessPrompts.RECIPE_CHECK)
	if fix == null:
		failures.append("la falla de Lint no volvió al agente")
		_dump()
		return
	_expect(str(fix.get(&"text")).contains("### Lint (exit code 1)") and str(fix.get(&"text")).contains("target.gd is broken"), "con la salida del check")
	_expect(_notice_with("recipe «Fix the target»") != null, "el aviso de los checks nombra la receta")

	# 3. El arreglo pasa.
	var deadline := Time.get_ticks_msec() + WAIT_MS
	while _notice_with("checks passed") == null and Time.get_ticks_msec() < deadline:
		await _tree.process_frame
	var final: Object = _notice_with("checks passed")
	_expect(final != null and str(final.get(&"text")).contains("attempt 2"), "el aviso final: pasó en el segundo intento")
	if final == null:
		_dump()
	_expect((controller.call(&"recipe_run") as Dictionary).is_empty(), "la corrida terminó")
	_model.set_harness_mode(SessionModel.HarnessMode.BUILD)


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


func _wait_user_entry(label: String) -> Object:
	var deadline := Time.get_ticks_msec() + WAIT_MS
	while Time.get_ticks_msec() < deadline:
		for entry: Object in _model.entries():
			if int(entry.get(&"kind")) == 0 and str(entry.get(&"harness_label")) == label:
				return entry
		await _tree.process_frame
	return null


func _dump() -> void:
	for entry: Object in _model.entries():
		var kind := int(entry.get(&"kind"))
		if kind in [0, 1, 7]:
			print("[recipe-check] %s: %s" % [{0: "user", 1: "agent", 7: "notice"}[kind], str(entry.get(&"harness_label")) + " " + str(entry.get(&"text")).left(300).replace("\n", " ")])


func _expect(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
