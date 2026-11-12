@tool
extends RefCounted
## ui-plan-criteria (m11-23) con el agente falso (tests/scripts/ui_plan_criteria.json):
## 1. Un plan en bloque con 2 criterios «WHEN …, THE GAME SHALL …»: la tarjeta tiene la casilla
##    «Verify the criteria by playing (2)», prendida, y la línea que dice que cada criterio es un playtest.
## 2. «Aprobar y construir» desde la tarjeta: el turno construye; después el harness juega el criterio 1
##    (pasa) y el 2 (falla), un turno de Revisar cada uno, como prompts del harness.
## 3. El que falló vuelve al agente («Plan · fix the criteria that failed»), se arregla y se juega solo
##    ese de nuevo: pasa. El aviso final dice «2 ✓ · 0 ✗», la tarjeta muestra ✓ en los dos y el plan
##    guardado tiene «## Verification».
## Las regresiones van a una carpeta temporal; el plan guardado se borra al final.

const I18n := preload("res://addons/godot_agent/core/i18n.gd")
const PlanApproval := preload("res://addons/godot_agent/session/plan_approval.gd")
const PlanStore := preload("res://addons/godot_agent/session/plan_store.gd")
const HarnessPrompts := preload("res://addons/godot_agent/session/harness_prompts.gd")
const SessionModel := preload("res://addons/godot_agent/session/session_model.gd")
const PlanApprovalView := preload("res://addons/godot_agent/ui/dock/entries/plan_approval_view.gd")
const MAIN_PLUGIN_SCRIPT := "res://addons/godot_agent/agent_plugin.gd"
const WAIT_MS := 40000
const PLAN := "# Plan: Lives for the criteria check\n\n## Acceptance criteria\n- WHEN the player touches an enemy, THE GAME SHALL take one life away.\n- WHEN lives reach 0, THE GAME SHALL show the game over screen.\n\n## Tasks\n1. Add a Lives autoload.\n"

var failures: Array[String] = []
var _tree: SceneTree
var _model: SessionModel


func run(tree: SceneTree, _plugin: Object, dock: Control, shot_path: String) -> Array[String]:
	_tree = tree
	_model = dock.get(&"_model")
	var controller: Object = dock.get(&"_controller")
	var saved_regressions: String = controller.get(&"regressions_dir")
	var saved_settings: Callable = controller.get(&"plan_criteria_settings")
	controller.set(&"regressions_dir", ProjectSettings.globalize_path("user://plan_criteria_regressions"))
	controller.set(&"plan_criteria_settings", func() -> Dictionary: return {"on": true, "max": 6})
	await _check(dock, controller, shot_path)
	controller.set(&"regressions_dir", saved_regressions)
	controller.set(&"plan_criteria_settings", saved_settings)
	return failures


func _check(dock: Control, controller: Object, shot_path: String) -> void:
	_model.set_harness_mode(SessionModel.HarnessMode.ASK)
	var request := PlanApproval.block_request(PLAN)
	_model.add_permission(request)
	var view: Control = null
	for i in 20:
		await _tree.process_frame
		view = _find_view(dock)
		if view != null:
			break
	if view == null:
		failures.append("no apareció la tarjeta del plan")
		return

	# 1. La casilla y su costo.
	var check: CheckBox = view.find_child("VerifyCriteria", true, false)
	var cost: Label = view.find_child("VerifyCost", true, false)
	_expect(check != null and check.is_visible_in_tree() and check.button_pressed, "la casilla se ve, prendida por defecto")
	if check == null:
		return
	_expect(check.text == "Verify the criteria by playing (2)" or check.text.contains("(2)"), "con la cantidad de criterios: %s" % check.text)
	_expect(cost.is_visible_in_tree() and cost.text.contains("playtest"), "y la línea del costo: %s" % cost.text)
	if not shot_path.is_empty():
		for i in 10:
			await _tree.process_frame
		dock.get_viewport().get_texture().get_image().save_png(shot_path.get_basename() + "_card.png")

	# 2. Aprobar desde la tarjeta: construye, juega el 1 (pasa) y el 2 (falla).
	var approve: Button = null
	for button: Button in view.find_children("*", "Button", true, false):
		if button.text == I18n.t("Approve and build"):
			approve = button
	if approve == null:
		failures.append("sin «Approve and build»")
		return
	approve.pressed.emit()
	await _tree.process_frame
	_expect(str((controller.call(&"recipe_run") as Dictionary).get("origin", "")) == "plan", "arranca la corrida del plan")
	var fix: Object = await _wait_user_entry(HarnessPrompts.PLAN_CRITERIA_FIX)
	if fix == null:
		failures.append("el criterio que falló no volvió al agente")
		_dump()
		return
	_expect(str(fix.get(&"text")).contains("WHEN lives reach 0") and str(fix.get(&"text")).contains("game over screen never shows"), "con lo que vio el playtest")
	var plays := _user_entries(HarnessPrompts.PLAN_CRITERION)
	_expect(plays.size() == 2, "un playtest por criterio antes de corregir (%d)" % plays.size())
	if plays.size() == 2:
		_expect(str(plays[0].get(&"text")).contains("touches an enemy") and str(plays[1].get(&"text")).contains("lives reach 0"), "en orden")
	_expect(_status(request) == ["pass", "retest"], "la tarjeta: %s" % [_status(request)])

	# 3. Arreglado, juega solo el 2 y pasa.
	var deadline := Time.get_ticks_msec() + WAIT_MS
	while _notice_with("acceptance criteria checked") == null and Time.get_ticks_msec() < deadline:
		await _tree.process_frame
	var final: Object = _notice_with("acceptance criteria checked")
	if final == null:
		failures.append("no llegó el aviso final")
		_dump()
		return
	_expect(str(final.get(&"text")).contains("2 ✓ · 0 ✗"), "el aviso final: %s" % final.get(&"text"))
	_expect(_user_entries(HarnessPrompts.PLAN_CRITERION).size() == 3, "se volvió a jugar solo el que falló")
	_expect(_status(request) == ["pass", "pass"], "la tarjeta con los dos ✓: %s" % [_status(request)])
	_expect((controller.call(&"recipe_run") as Dictionary).is_empty(), "la corrida terminó")
	_expect(_model.harness_mode == SessionModel.HarnessMode.BUILD, "vuelve a Construir")
	await _tree.process_frame
	var box: Control = view.find_child("CriteriaResults", true, false)
	_expect(box != null and box.is_visible_in_tree() and (box.get_child(0) as Label).text.begins_with("✓"), "la tarjeta los muestra")
	var plan_file := _plan_file()
	_expect(not plan_file.is_empty() and FileAccess.get_file_as_string(plan_file).contains("## Verification"), "el plan guardado tiene la verificación")
	if not shot_path.is_empty():
		for i in 10:
			await _tree.process_frame
		dock.get_viewport().get_texture().get_image().save_png(shot_path.get_basename() + "_results.png")
	if not plan_file.is_empty():
		DirAccess.remove_absolute(plan_file)


func _find_view(root: Node) -> Control:
	for node: Node in root.find_children("*", "VBoxContainer", true, false):
		if node.get_script() == PlanApprovalView:
			return node
	return null


func _status(request: Object) -> Array:
	return (request.get(&"criteria_results") as Array).map(func(i: Dictionary) -> String: return str(i.status))


func _plan_file() -> String:
	var dir := ProjectSettings.globalize_path("res://").path_join(PlanStore.DIR)
	for file: String in DirAccess.get_files_at(dir):
		if file.contains("lives-for-the-criteria-check"):
			return dir.path_join(file)
	return ""


func _notice_with(text: String) -> Object:
	var found: Object = null
	for entry: Object in _model.entries():
		if int(entry.get(&"kind")) == 7 and str(entry.get(&"text")).contains(text):
			found = entry
	return found


func _user_entries(label: String) -> Array:
	return _model.entries().filter(func(entry: Object) -> bool: return int(entry.get(&"kind")) == 0 and str(entry.get(&"harness_label")) == label)


func _wait_user_entry(label: String) -> Object:
	var deadline := Time.get_ticks_msec() + WAIT_MS
	while Time.get_ticks_msec() < deadline:
		var found := _user_entries(label)
		if not found.is_empty():
			return found[0]
		await _tree.process_frame
	return null


func _dump() -> void:
	for entry: Object in _model.entries():
		var kind := int(entry.get(&"kind"))
		if kind in [0, 1, 7]:
			print("[plan-criteria-check] %s: %s" % [{0: "user", 1: "agent", 7: "notice"}[kind], str(entry.get(&"harness_label")) + " " + str(entry.get(&"text")).left(300).replace("\n", " ")])


func _expect(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
