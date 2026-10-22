@tool
extends "mcp_check.gd"
## Verificación de las tools de edición (M4) dentro del editor, por HTTP real:
## - cada tool sobre una copia de la escena de prueba;
## - Ctrl+Z (la opción Undo del editor) deshace en pasos;
## - permisos por modo (Preguntar deniega, Construir pregunta);
## - el botón "↶ undo" de un tool call (unido por nombre y argumentos).

const SessionModel := preload("res://addons/godot_agent/session/session_model.gd")
const EditorUndo := preload("res://addons/godot_agent/editor/editor_undo.gd")
const PLUGIN_SCRIPT := "res://addons/godot_agent/plugin.gd"
const DOCK_SCRIPT := "res://addons/godot_agent/ui/dock/agent_dock.gd"
const EDIT_SCENE := "res://tests/tmp/edit_fixture.tscn"
const NEW_SCENE := "res://tests/tmp/edit_new_scene.tscn"
const NEW_SCRIPT := "res://tests/tmp/edit_enemies.gd"
const BOSS_SCRIPT := "res://tests/tmp/edit_boss.gd"
const BOSS_SCENE := "res://tests/tmp/edit_boss.tscn"
const BATCH_SCRIPT := "res://tests/tmp/edit_bar.gd"

var _model: Object
var _plugin: Node


func run_edit(tree: SceneTree) -> PackedStringArray:
	_tree = tree
	for node: Node in tree.root.find_children("*", "Node", true, false):
		var script := node.get_script() as Script
		if script == null:
			continue
		match script.resource_path:
			SERVER_SCRIPT:
				_server = node
			PLUGIN_SCRIPT:
				_plugin = node
			DOCK_SCRIPT:
				_model = node.get(&"_model")
	if _server == null or _plugin == null or _model == null:
		failures.append("no se encontró el server, el plugin o el modelo")
		return failures
	for path: String in [EDIT_SCENE, NEW_SCENE, NEW_SCRIPT, BOSS_SCRIPT, BOSS_SCENE, BATCH_SCRIPT]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	# Copia sin el uid de la cabecera: dos .tscn con el mismo uid confunden al editor.
	var header_uid := RegEx.create_from_string(" uid=\"uid://[a-z0-9]+\"")
	var lines := FileAccess.get_file_as_string(FIXTURE_SCENE).split("\n")
	lines[0] = header_uid.sub(lines[0], "")
	var copy_file := FileAccess.open(EDIT_SCENE, FileAccess.WRITE)
	copy_file.store_string("\n".join(lines))
	copy_file.close()
	EditorInterface.get_resource_filesystem().update_file(EDIT_SCENE)
	await _tree.create_timer(0.5).timeout
	if EDIT_SCENE in EditorInterface.get_open_scenes():
		EditorInterface.reload_scene_from_path(EDIT_SCENE)  # el editor restauró la pestaña de la corrida anterior
		await _tree.create_timer(0.5).timeout
	await _rpc("initialize", {"protocolVersion": "2025-06-18", "capabilities": {}, "clientInfo": {"name": "edit-check", "version": "1"}})
	_model.call(&"set_harness_mode", SessionModel.HarnessMode.ONESHOT)

	var opened := await _call_text("open_scene", {"path": EDIT_SCENE})
	_expect(opened.contains("Opened"), "open_scene")
	var root := EditorInterface.get_edited_scene_root()

	# add_node + set_properties + connect_signal, y después Ctrl+Z en pasos.
	var added := await _call_text("add_node", {"parent": ".", "type": "Label", "name": "WaveLabel", "properties": {"text": "Oleada 1", "position": [10, 20]}})
	_expect(added.contains("Undo step: «Agent: add WaveLabel»"), "add_node devuelve el paso de undo")
	var label := root.get_node_or_null("WaveLabel") as Label
	_expect(label != null and label.owner == root and label.text == "Oleada 1" and label.position == Vector2(10, 20), "add_node: nodo con owner y propiedades")
	var changed := await _call_text("set_properties", {"node_path": "WaveLabel", "properties": {"modulate": "#ff0000", "horizontal_alignment": "Center"}})
	_expect(label != null and label.modulate == Color(1, 0, 0) and changed.contains("modulate: Color(1, 1, 1, 1) → Color(1, 0, 0, 1)"), "set_properties con valores anteriores y nuevos")
	var connected := await _call_text("connect_signal", {"from": "Timer", "signal": "timeout", "to": "WaveLabel", "method": "_on_wave"})
	var timer := root.get_node("Timer")
	_expect(timer.is_connected("timeout", Callable(label, "_on_wave")) and connected.contains("Note:"), "connect_signal persistente con aviso de método faltante")
	var bad_prop: Dictionary = await _call("set_properties", {"node_path": "WaveLabel", "properties": {"txt": "x"}})
	_expect(bad_prop.get("isError", false) and _text(bad_prop).contains("text"), "propiedad inexistente → error con sugerencia")
	var bad_type: Dictionary = await _call("add_node", {"parent": ".", "type": "Nodo", "name": "X"})
	_expect(bad_type.get("isError", false), "tipo inexistente → error")

	EditorUndo._trigger_editor_undo()
	_expect(not timer.is_connected("timeout", Callable(label, "_on_wave")), "Ctrl+Z 1: deshace la conexión")
	EditorUndo._trigger_editor_undo()
	_expect(label.modulate == Color(1, 1, 1) and label.horizontal_alignment == HORIZONTAL_ALIGNMENT_LEFT, "Ctrl+Z 2: deshace las propiedades")
	EditorUndo._trigger_editor_undo()
	_expect(root.get_node_or_null("WaveLabel") == null, "Ctrl+Z 3: saca el nodo")

	# rename, reparent, remove (con undo que restaura owners).
	await _call_text("add_node", {"parent": ".", "type": "Node2D", "name": "Group"})
	await _call_text("add_node", {"parent": "Group", "type": "Sprite2D", "name": "Icon"})
	var renamed := await _call_text("rename_node", {"node_path": "Group", "new_name": "Squad"})
	_expect(root.has_node("Squad/Icon") and renamed.contains("Squad"), "rename_node")
	await _call_text("reparent_node", {"node_path": "Squad", "new_parent": "Enemies"})
	_expect(root.has_node("Enemies/Squad/Icon") and root.get_node("Enemies/Squad/Icon").owner == root, "reparent_node conserva owners")
	await _call_text("remove_node", {"node_path": "Enemies/Squad"})
	_expect(not root.has_node("Enemies/Squad"), "remove_node")
	EditorUndo._trigger_editor_undo()
	_expect(root.has_node("Enemies/Squad/Icon") and root.get_node("Enemies/Squad/Icon").owner == root, "undo de remove_node restaura hijos con owner")
	var root_removal: Dictionary = await _call("remove_node", {"node_path": "."})
	_expect(root_removal.get("isError", false), "no borra la raíz")

	# add_nodes: un subárbol entero en un paso de undo; un item inválido no crea nada.
	var batch := await _call_text("add_nodes", {"parent": ".", "nodes": [
		{"name": "HUD", "type": "CanvasLayer", "groups": ["ui"], "children": [
			{"name": "Score", "type": "Label", "properties": {"text": "0", "position": [8, 8]}},
			{"name": "Bar", "type": "HBoxContainer", "script": BATCH_SCRIPT, "children": [
				{"name": "Pause", "type": "Button", "properties": {"text": "II"}},
				{"name": "Mini", "scene": FIXTURE_SCENE},
			]},
		]},
		{"name": "Spawner", "type": "Marker2D"},
	]})
	var hud := root.get_node_or_null("HUD")
	var all_owned := hud != null
	for path: String in ["HUD", "HUD/Score", "HUD/Bar", "HUD/Bar/Pause", "HUD/Bar/Mini", "Spawner"]:
		all_owned = all_owned and root.has_node(path) and root.get_node(path).owner == root
	_expect(all_owned and batch.contains("Created 6 nodes"), "add_nodes crea el subárbol con owners (%s)" % batch)
	_expect(hud != null and hud.is_in_group("ui") and (root.get_node("HUD/Score") as Label).text == "0" and root.get_node("HUD/Bar").get_script() != null and FileAccess.file_exists(BATCH_SCRIPT), "add_nodes: grupos, propiedades y script creado")
	_expect(root.has_node("HUD/Bar/Mini/Player") and root.get_node("HUD/Bar/Mini/Player").owner != root and root.get_node("HUD/Bar/Mini").scene_file_path == FIXTURE_SCENE, "add_nodes: escena instanciada sin abrir sus nodos")
	EditorUndo._trigger_editor_undo()
	_expect(not root.has_node("HUD") and not root.has_node("Spawner"), "Ctrl+Z deshace add_nodes de una vez")
	var bad_batch: Dictionary = await _call("add_nodes", {"parent": ".", "nodes": [{"name": "Ok", "type": "Node2D"}, {"name": "Bad", "type": "Node2D", "children": [{"name": "X", "type": "Nodo"}]}]})
	_expect(bad_batch.get("isError", false) and _text(bad_batch).contains("Bad/X") and not root.has_node("Ok"), "add_nodes inválido no crea nada (%s)" % _text(bad_batch))

	# duplicate_node: copia con hijos, script, grupos y propiedades; undo la saca.
	var duplicated := await _call_text("duplicate_node", {"node_path": "Player"})
	var twin := root.get_node_or_null("Player2")
	_expect(twin != null and twin.owner == root and twin.get_node("Sprite").owner == root and twin.is_in_group("player") and twin.get_script() != null and twin.position == Vector2(100, 50), "duplicate_node (%s)" % duplicated)
	_expect(twin != null and twin.get_index() == root.get_node("Player").get_index() + 1, "duplicate_node la pone al lado del original")
	EditorUndo._trigger_editor_undo()
	_expect(not root.has_node("Player2"), "Ctrl+Z deshace duplicate_node")
	await _call_text("duplicate_node", {"node_path": "Player", "new_name": "Ghost", "new_parent": "Enemies"})
	_expect(root.has_node("Enemies/Ghost/Sprite"), "duplicate_node con nombre y padre")
	EditorUndo._trigger_editor_undo()

	# instantiate_scene, attach_script, create_scene, save_scene.
	var instanced := await _call_text("instantiate_scene", {"parent": "Enemies", "scene_path": FIXTURE_SCENE, "name": "Copy"})
	var copy := root.get_node_or_null("Enemies/Copy")
	_expect(copy != null and copy.scene_file_path == FIXTURE_SCENE and copy.owner == root and instanced.contains("Instanced"), "instantiate_scene")
	var attached := await _call_text("attach_script", {"node_path": "Enemies", "script_path": NEW_SCRIPT})
	_expect(FileAccess.file_exists(NEW_SCRIPT) and root.get_node("Enemies").get_script() != null and attached.contains("(created)"), "attach_script crea y adjunta")
	var wrong_base: Dictionary = await _call("attach_script", {"node_path": "Timer", "script_path": GOOD_SCRIPT})
	_expect(wrong_base.get("isError", false), "attach_script con base incompatible → error")
	var created := await _call_text("create_scene", {"path": NEW_SCENE, "root_type": "Node2D", "root_name": "Level"})
	_expect(FileAccess.file_exists(NEW_SCENE) and created.contains("Created"), "create_scene")
	var again: Dictionary = await _call("create_scene", {"path": NEW_SCENE, "root_type": "Node2D", "root_name": "Level"})
	_expect(again.get("isError", false), "create_scene no pisa")
	# Lo que el agente de great-boy-one escribió a mano con `cat > boss_torre.tscn` (D48): raíz con
	# script y exports, en una sola llamada.
	var boss := FileAccess.open(BOSS_SCRIPT, FileAccess.WRITE)
	boss.store_string("extends Node\n\n@export var mission := \"planta\"\n@export var at := Vector2(2200, 192)\n")
	boss.close()
	EditorInterface.get_resource_filesystem().update_file(BOSS_SCRIPT)
	var boss_text := await _call_text("create_scene", {"path": BOSS_SCENE, "root_type": "Node", "root_name": "BossTorre",
		"script_path": BOSS_SCRIPT, "properties": {"mission": "torre", "at": [360, 160]}})
	var boss_root: Node = (load(BOSS_SCENE) as PackedScene).instantiate() if FileAccess.file_exists(BOSS_SCENE) else null
	_expect(boss_root != null and boss_root.get_script() != null and str(boss_root.get(&"mission")) == "torre" and boss_root.get(&"at") == Vector2(360, 160) and boss_text.contains("script"),
		"create_scene con script y exports (%s)" % boss_text)
	if boss_root:
		boss_root.free()
	var saved := await _call_text("save_scene", {})
	var saved_text := FileAccess.get_file_as_string(EDIT_SCENE)
	_expect(saved.contains("Saved") and saved_text.contains("name=\"Copy\"") and saved_text.contains("edit_enemies.gd"), "save_scene guarda los cambios")

	# Permisos: Preguntar deniega; Construir pregunta (se acepta solo).
	_model.call(&"set_harness_mode", SessionModel.HarnessMode.ASK)
	var denied: Dictionary = await _call("add_node", {"parent": ".", "type": "Node", "name": "Denied"})
	_expect(denied.get("isError", false) and _text(denied).contains("denied") and not root.has_node("Denied"), "Preguntar deniega edit_scene")
	_model.call(&"set_harness_mode", SessionModel.HarnessMode.BUILD)
	var asked: Array = []
	var on_permission := func(request: Object) -> void:
		asked.append(request.get(&"title"))
		request.call(&"select", request.call(&"option_id_for", PackedStringArray(["allow_once"])))
	_model.connect(&"permission_requested", on_permission)
	var allowed := await _call_text("add_node", {"parent": ".", "type": "Node", "name": "Allowed"})
	_model.disconnect(&"permission_requested", on_permission)
	_expect(asked == ["godot.add_node"] and root.has_node("Allowed") and allowed.contains("Created"), "Construir pide permiso y ejecuta")

	# Botón "↶ undo": el tool call ACP se une a la acción por nombre y argumentos.
	_model.call(&"set_harness_mode", SessionModel.HarnessMode.ONESHOT)
	var args := {"parent": ".", "type": "Node", "name": "ViaButton"}
	_model.call(&"apply_update", {"sessionUpdate": "tool_call", "toolCallId": "edit-check-1", "title": "mcp__godot__add_node", "kind": "other", "status": "in_progress", "rawInput": args})
	await _call_text("add_node", args)
	_model.call(&"apply_update", {"sessionUpdate": "tool_call_update", "toolCallId": "edit-check-1", "status": "completed"})
	var call: Object = _model.call(&"tool_call", "edit-check-1")
	_expect(call.call(&"can_undo"), "el tool call recibió su paso de undo")
	_plugin.call(&"_undo_tool_call", "edit-check-1")
	_expect(not root.has_node("ViaButton") and call.get(&"undo_done"), "↶ undo deshace la acción")
	var args_two := {"parent": ".", "type": "Node", "name": "Stale"}
	_model.call(&"apply_update", {"sessionUpdate": "tool_call", "toolCallId": "edit-check-2", "title": "mcp__godot__add_node", "kind": "other", "status": "in_progress", "rawInput": args_two})
	await _call_text("add_node", args_two)
	_model.call(&"apply_update", {"sessionUpdate": "tool_call_update", "toolCallId": "edit-check-2", "status": "completed"})
	await _call_text("set_properties", {"node_path": "Stale", "properties": {"editor_description": "después"}})
	_plugin.call(&"_undo_tool_call", "edit-check-2")
	var stale_call: Object = _model.call(&"tool_call", "edit-check-2")
	_expect(root.has_node("Stale") and not stale_call.get(&"undo_done"), "↶ undo no deshace si hubo cambios posteriores")
	var last_entry: Object = (_model.call(&"entries") as Array).back()
	_expect(str(last_entry.get(&"text")).contains("changed afterwards"), "avisa por qué no deshizo")

	EditorInterface.save_scene()
	return failures
