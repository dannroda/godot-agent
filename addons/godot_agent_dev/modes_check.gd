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
## 3b. godot.request_mode (m11-68), segundo turno: desde Construir pide Auto (tarjeta con el aviso de
##    más permisos, aunque sea read; se acepta y pasa a Auto) y después Revisar (se queda en Auto).
## 4. Extensiones › Modes lista los dos (el roto con sus problemas) y «Use» pone el modo en el dock.
## 5. One-shot: el selector «Builder's project mode» ofrece Levels y, elegido, avisa en una línea qué
##    queda negado (shell, project tools, MCP de terceros).
## No toca los EditorSettings: la carpeta de modos va por dock.modes_dir.

const SessionModel := preload("res://addons/godot_agent/session/session_model.gd")
const PermissionRequest := preload("res://addons/godot_agent/session/permission_request.gd")
const LayoutCheck := preload("layout_check.gd")
const MAIN_PLUGIN_SCRIPT := "res://addons/godot_agent/agent_plugin.gd"
const WORK_DIR := "res://tests/tmp/modes"
const WAIT_MS := 30000

var failures: Array[String] = []
var _tree: SceneTree
var _model: SessionModel


func run(tree: SceneTree, plugin: Object, dock: Control, shot_path: String) -> Array[String]:
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
	await _check_request_mode(dock)
	await _check_long_name(dock)
	if plugin:
		_check_extensions(plugin)
		_check_oneshot(plugin)
	else:
		failures.append("no está el plugin principal")
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


func _check_request_mode(dock: Control) -> void:
	_model.set_project_mode({})
	_model.set_harness_mode(SessionModel.HarnessMode.BUILD)
	dock.call(&"_on_submitted", "Fix the level scripts.")
	var request := await _next_card()
	_expect(request != null and request.title == "Switch to Auto", "request_mode muestra la tarjeta · %s" % (request.title if request else "sin tarjeta"))
	if request == null:
		return
	_expect(request.description.contains("From Build to Auto.") and request.description.contains("More permissions") and request.description.contains("Many small edits"), "con de dónde a dónde, el aviso y el porqué · %s" % request.description)
	_expect(request.option_id_for([PermissionRequest.KIND_ALLOW_ALWAYS]).is_empty(), "sin «siempre»")
	request.select("switch")
	request = await _next_card()
	_expect(_model.harness_mode == SessionModel.HarnessMode.AUTO, "aceptada, pasa a Auto")
	_expect(request != null and request.title == "Switch to Review", "la segunda pide Revisar, también con tarjeta en Auto")
	if request:
		_expect(not request.description.contains("More permissions"), "Revisar tiene menos: sin aviso")
		request.select("stay")
	var deadline := Time.get_ticks_msec() + WAIT_MS
	while _model.is_busy() and Time.get_ticks_msec() < deadline:
		await _tree.process_frame
	_expect(_model.harness_mode == SessionModel.HarnessMode.AUTO, "«Quedarse» deja Auto")
	var results: Array = []
	for index in range(1, 12):
		var call: Object = _model.tool_call("mcp-%d" % index)
		var raw := str(call.raw_output) if call else ""
		if raw.contains("switched this session to Auto") or raw.contains("chose to stay in Auto"):
			results.append(raw)
	_expect(results.size() == 2, "el agente recibe las dos respuestas · %d" % results.size())
	_model.set_harness_mode(SessionModel.HarnessMode.BUILD)


## m12-52: un modo del proyecto de nombre largo («Level design (Build)») compacta la fila del composer
## en vez de ensanchar el dock, con el dock a 480 y a 320 px y la fila de una sesión activa (medidor,
## modelo, Enviar).
func _check_long_name(dock: Control) -> void:
	var dir := ProjectSettings.globalize_path(WORK_DIR)
	_write(dir.path_join("modes/level_design.json"), JSON.stringify({
		"version": 1, "name": "Level design", "base": "build", "when_to_use": "Laying out levels",
		"editable": [WORK_DIR + "/levels/*.tscn"], "icon": "TileMap",
	}, "\t"))
	dock.call(&"load_project_modes")
	_expect(bool(dock.call(&"choose_project_mode", "Level design")), "se elige «Level design»")
	var composer: Object = dock.get(&"_composer")
	composer.call(&"set_usage", 38000, 200000)
	composer.call(&"set_model_option", {"currentValue": "default", "options": [
		{"value": "default", "name": "Default (recommended)", "description": "Opus 5.5"},
		{"value": "opus", "name": "Opus 5.5"}]})
	# El MinSizeGuard: el ancho que el editor le da al dock. El contenido puede pedir más (se recorta).
	var guard: Control = dock
	while guard and not (guard.get_script() and (guard.get_script() as Script).resource_path.ends_with("min_size_guard.gd")):
		guard = guard.get_parent() as Control
	var start_width := int(guard.size.x)
	for width: int in [480, 400, 320]:
		await LayoutCheck.set_dock_width(guard, width)
		# Un cambio de compactación que deshace el anterior espera FIT_SETTLE_MS (250 ms) y se vuelve a medir.
		await _tree.create_timer(0.5).timeout
		var row: Control = composer.get(&"_row")
		_expect(absf(guard.size.x - width) < 4.0, "con «Level design (Build)» el dock queda en %d px, no se ensancha (%d)" % [width, guard.size.x])
		_expect(row.get_combined_minimum_size().x <= guard.size.x + 1.0, "a %d px la fila del composer pide %d: tiene que compactarse" % [width, row.get_combined_minimum_size().x])
		for failure: String in LayoutCheck.dock_fits(dock):
			failures.append("a %d px: %s" % [width, failure])
		# Con la escala del editor en 1,33 (la de un editor sin ajustes, la del CI) a 320 px ni cortando
		# el modelo entra: el modo también se corta, y su tooltip dice el nombre entero.
		var mode_button: OptionButton = composer.get(&"_mode_button")
		if int(composer.get(&"_compact_level")) >= 7:
			_expect(mode_button.tooltip_text.begins_with("Level design (Build)"), "cortado, el tooltip del modo empieza con su nombre · %s" % mode_button.tooltip_text.left(80))
	await LayoutCheck.set_dock_width(guard, start_width)
	composer.call(&"set_usage", 0, 0)
	composer.call(&"set_model_option", {})
	DirAccess.remove_absolute(dir.path_join("modes/level_design.json"))


## La próxima tarjeta pendiente (o null si el turno termina antes).
func _next_card() -> PermissionRequest:
	var deadline := Time.get_ticks_msec() + WAIT_MS
	while Time.get_ticks_msec() < deadline:
		for pending: PermissionRequest in _model.pending_permissions:
			if pending.is_pending():
				return pending
		if not _model.is_busy():
			return null
		await _tree.process_frame
	return null


func _check_extensions(plugin: Object) -> void:
	var window: Object = plugin.call(&"_get_extensions_window")
	var saved: Callable = window.get(&"modes_dir_provider")
	window.set(&"modes_dir_provider", func() -> String: return WORK_DIR + "/modes")
	var tab: Object = window.get(&"_modes_tab")
	tab.call(&"refresh")
	_expect(int(tab.call(&"mode_count")) == 2, "Extensiones › Modes lista los dos modos · %d" % int(tab.call(&"mode_count")))
	_model.set_harness_mode(SessionModel.HarnessMode.ASK)
	tab.emit_signal(&"use_requested", "levels")
	_expect(_model.project_mode.get("name") == "Levels" and _model.harness_mode == SessionModel.HarnessMode.AUTO, "«Use» pone el modo en el dock")
	_model.set_project_mode({})
	_model.set_harness_mode(SessionModel.HarnessMode.BUILD)
	window.set(&"modes_dir_provider", saved)
	tab.call(&"refresh")


func _check_oneshot(plugin: Object) -> void:
	var screen: Object = plugin.get(&"_main_screen")
	if screen == null:
		failures.append("no está la pantalla de One-shot")
		return
	var saved: String = screen.get(&"modes_dir")
	screen.set(&"modes_dir", WORK_DIR + "/modes")
	screen.call(&"refresh_builder_modes")
	var button: OptionButton = screen.get(&"_builder_mode_button")
	var note: Label = screen.get(&"_builder_mode_note")
	_expect(button.get_parent().visible and _items(button) == ["None", "Levels"], "el selector del constructor ofrece Levels (no el roto) · %s" % [_items(button)])
	_expect(not note.visible, "sin modo, sin aviso")
	_expect(bool(screen.call(&"choose_builder_mode", "levels")), "se elige Levels")
	_expect(note.visible and note.text.contains("Shell commands, project tools and other MCP servers are denied"), "el aviso dice qué queda negado · %s" % note.text)
	_expect(screen.call(&"selected_builder_mode").get("name") == "Levels", "es el que se le pasa al run")
	screen.set(&"modes_dir", saved)
	screen.call(&"refresh_builder_modes")


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
