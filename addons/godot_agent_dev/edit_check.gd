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

	# Project settings por el editor (m4-09): cada cambio guarda project.godot y Ctrl+Z lo revierte.
	# El grupo project se permite en One-shot (D49) y pregunta en Construir.
	var project_asks: Array = []
	var allow_project := func(request: Object) -> void:
		project_asks.append(request.get(&"title"))
		request.call(&"select", request.call(&"option_id_for", PackedStringArray(["allow_once"])))
	_model.connect(&"permission_requested", allow_project)
	var project_before := _without_features(FileAccess.get_file_as_string("res://project.godot"))
	var jump := await _call_text("set_input_action", {"action": "agent_jump", "events": ["Space", "joy_button:a"]})
	var jump_action: Variant = ProjectSettings.get_setting("input/agent_jump", null)
	_expect(jump_action is Dictionary and jump_action.events.size() == 2 and FileAccess.get_file_as_string("res://project.godot").contains("agent_jump") and jump.contains("key Space (physical), joy_button a"), "set_input_action guarda la acción (%s)" % jump)
	await _call_text("set_input_action", {"action": "agent_jump", "events": ["W"], "append": true})
	_expect((ProjectSettings.get_setting("input/agent_jump") as Dictionary).events.size() == 3, "set_input_action con append")
	EditorUndo._trigger_editor_undo()
	_expect((ProjectSettings.get_setting("input/agent_jump") as Dictionary).events.size() == 2, "Ctrl+Z deshace el append")
	EditorUndo._trigger_editor_undo()
	_expect(not ProjectSettings.has_setting("input/agent_jump") and not FileAccess.get_file_as_string("res://project.godot").contains("agent_jump"), "Ctrl+Z saca la acción y guarda")
	var width := await _call_text("set_project_setting", {"name": "display/window/size/viewport_width", "value": 640})
	_expect(int(ProjectSettings.get_setting("display/window/size/viewport_width")) == 640 and width.contains("→ 640"), "set_project_setting (%s)" % width)
	var listed := await _call_text("project_settings", {"prefix": "display/window/size"})
	_expect(listed.contains("display/window/size/viewport_width = 640  (default 1152)"), "project_settings con prefijo (%s)" % listed.left(200))
	var wrong: Dictionary = await _call("set_project_setting", {"name": "display/window/size/viewport_width", "value": "ancho"})
	_expect(wrong.get("isError", false), "set_project_setting con tipo inválido → error")
	var via_input: Dictionary = await _call("set_project_setting", {"name": "input/x", "value": {}})
	_expect(via_input.get("isError", false) and _text(via_input).contains("set_input_action"), "input/ va por su tool")
	EditorUndo._trigger_editor_undo()
	_expect(int(ProjectSettings.get_setting("display/window/size/viewport_width")) == 1152, "Ctrl+Z revierte el setting")
	var autoload := await _call_text("set_autoload", {"name": "AgentState", "path": NEW_SCRIPT})
	_expect(str(ProjectSettings.get_setting("autoload/AgentState", "")) == "*" + NEW_SCRIPT and autoload.contains("Added"), "set_autoload (%s)" % autoload)
	var clash: Dictionary = await _call("set_autoload", {"name": "Input", "path": NEW_SCRIPT})
	_expect(clash.get("isError", false), "set_autoload no pisa un singleton de Godot")
	await _call_text("remove_autoload", {"name": "AgentState"})
	_expect(not ProjectSettings.has_setting("autoload/AgentState"), "remove_autoload")
	EditorUndo._trigger_editor_undo()
	_expect(ProjectSettings.has_setting("autoload/AgentState"), "Ctrl+Z restaura el autoload")
	EditorUndo._trigger_editor_undo()
	_expect(not ProjectSettings.has_setting("autoload/AgentState"), "Ctrl+Z saca el autoload")
	_model.call(&"set_harness_mode", SessionModel.HarnessMode.ASK)
	var denied_setting: Dictionary = await _call("set_project_setting", {"name": "display/window/size/viewport_width", "value": 800})
	_expect(denied_setting.get("isError", false) and int(ProjectSettings.get_setting("display/window/size/viewport_width")) == 1152, "Preguntar deniega el grupo project")
	_model.call(&"set_harness_mode", SessionModel.HarnessMode.ONESHOT)
	_model.call(&"set_harness_mode", SessionModel.HarnessMode.BUILD)
	await _call_text("set_input_action", {"action": "agent_build", "events": ["B"]})
	EditorUndo._trigger_editor_undo()
	_model.call(&"set_harness_mode", SessionModel.HarnessMode.ONESHOT)
	_model.disconnect(&"permission_requested", allow_project)
	_expect(project_asks == ["godot.set_input_action"], "project: One-shot no pregunta, Construir sí (%s)" % [project_asks])
	_expect(_without_features(FileAccess.get_file_as_string("res://project.godot")) == project_before, "project.godot queda como estaba")

	# Archivos con referencias (m4-10): mover arregla rutas y mantiene el uid; borrar se niega si algo
	# lo usa; copiar da un uid nuevo.
	# Carpeta nueva en cada corrida: el caché de uids del editor recuerda las rutas de la anterior.
	for old: String in DirAccess.get_directories_at("res://tests/tmp"):
		if old.begins_with("files_"):
			_remove_tree(ProjectSettings.globalize_path("res://tests/tmp/" + old))
	var FILES_DIR := "res://tests/tmp/files_%d" % Time.get_unix_time_from_system()
	await _call_text("create_scene", {"path": FILES_DIR + "/hero.tscn", "root_type": "Node2D", "root_name": "Hero", "script_path": FILES_DIR + "/hero.gd"})
	EditorInterface.get_resource_filesystem().scan()
	await _tree.create_timer(1.5).timeout
	var hero_uid := ResourceLoader.get_resource_uid(FILES_DIR + "/hero.tscn")
	_write(FILES_DIR + "/level.tscn", '[gd_scene format=3]\n\n[ext_resource type="PackedScene" uid="%s" path="%s/hero.tscn" id="1_hero"]\n\n[node name="Level" type="Node2D"]\n\n[node name="Hero" parent="." instance=ExtResource("1_hero")]\n' % [ResourceUID.id_to_text(hero_uid), FILES_DIR])
	_write(FILES_DIR + "/spawner.gd", 'extends Node\n\nconst HERO := preload("%s/hero.tscn")\nconst HERO_SCRIPT := "%s/hero.gd"\n' % [FILES_DIR, FILES_DIR])
	EditorInterface.get_resource_filesystem().scan()
	await _tree.create_timer(1.5).timeout
	var moved_text := await _call_text("move_file", {"from": FILES_DIR + "/hero.tscn", "to": FILES_DIR + "/actors/hero.tscn"})
	var level_text := FileAccess.get_file_as_string(FILES_DIR + "/level.tscn")
	_expect(FileAccess.file_exists(FILES_DIR + "/actors/hero.tscn") and not FileAccess.file_exists(FILES_DIR + "/hero.tscn"), "move_file mueve (%s)" % moved_text)
	_expect(level_text.contains("path=\"%s/actors/hero.tscn\"" % FILES_DIR) and FileAccess.get_file_as_string(FILES_DIR + "/spawner.gd").contains(FILES_DIR + "/actors/hero.tscn"), "move_file reescribe las referencias (%s | %s)" % [level_text, FileAccess.get_file_as_string(FILES_DIR + "/spawner.gd")])
	_expect(hero_uid != ResourceUID.INVALID_ID and ResourceLoader.get_resource_uid(FILES_DIR + "/actors/hero.tscn") == hero_uid, "move_file mantiene el uid")
	var moved_folder := await _call_text("move_file", {"from": FILES_DIR + "/actors", "to": FILES_DIR + "/characters"})
	_expect(FileAccess.get_file_as_string(FILES_DIR + "/level.tscn").contains(FILES_DIR + "/characters/hero.tscn") and DirAccess.dir_exists_absolute(FILES_DIR + "/characters"), "move_file de una carpeta (%s)" % moved_folder)
	var moved_script := await _call_text("move_file", {"from": FILES_DIR + "/hero.gd", "to": FILES_DIR + "/scripts/hero.gd"})
	_expect(FileAccess.get_file_as_string(FILES_DIR + "/characters/hero.tscn").contains(FILES_DIR + "/scripts/hero.gd") and FileAccess.file_exists(FILES_DIR + "/scripts/hero.gd.uid") and not FileAccess.file_exists(FILES_DIR + "/hero.gd.uid"), "move_file de un script con su .uid (%s)" % moved_script)
	EditorInterface.get_resource_filesystem().scan()
	await _tree.create_timer(1.5).timeout
	var level_scene := ResourceLoader.load(FILES_DIR + "/level.tscn", "", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	var level_node := level_scene.instantiate() if level_scene else null
	_expect(level_node != null and level_node.get_node_or_null("Hero") != null and level_node.get_node("Hero").get_script() != null, "la escena que lo instancia sigue cargando")
	if level_node:
		level_node.free()
	var refused: Dictionary = await _call("delete_file", {"path": FILES_DIR + "/characters/hero.tscn"})
	_expect(refused.get("isError", false) and _text(refused).contains("level.tscn") and _text(refused).contains("spawner.gd") and FileAccess.file_exists(FILES_DIR + "/characters/hero.tscn"), "delete_file se niega y dice qué se rompería (%s)" % _text(refused))
	var copied := await _call_text("copy_file", {"from": FILES_DIR + "/characters/hero.tscn", "to": FILES_DIR + "/hero_copy.tscn"})
	EditorInterface.get_resource_filesystem().scan()
	await _tree.create_timer(1.5).timeout
	var copy_uid := ResourceLoader.get_resource_uid(FILES_DIR + "/hero_copy.tscn")
	_expect(copy_uid != ResourceUID.INVALID_ID and copy_uid != hero_uid, "copy_file da un uid nuevo (%s)" % copied)
	var deleted := await _call_text("delete_file", {"path": FILES_DIR + "/hero_copy.tscn"})
	_expect(not FileAccess.file_exists(FILES_DIR + "/hero_copy.tscn") and deleted.contains("Deleted"), "delete_file sin referencias (%s)" % deleted)
	var open_move: Dictionary = await _call("move_file", {"from": EDIT_SCENE, "to": FILES_DIR + "/moved.tscn"})
	_expect(open_move.get("isError", false) and _text(open_move).contains("open"), "move_file no mueve una escena abierta")
	var overwrite: Dictionary = await _call("move_file", {"from": FILES_DIR + "/level.tscn", "to": FILES_DIR + "/spawner.gd"})
	_expect(overwrite.get("isError", false), "move_file no pisa")

	# Recursos .tres (m4-13): crear con class_name y array tipado, leer, cambiar con undo y asignar.
	var res_dir := FILES_DIR + "/data"
	var loot_text := await _call_text("create_resource", {"path": res_dir + "/loot.tres", "type": "FixtureLoot", "properties": {
		"items": [{"type": "FixtureItem", "title": "Sword", "damage": 7, "style": {"type": "StyleBoxFlat", "bg_color": "#ff0000"}}, {"type": "FixtureItem", "title": "Bow"}],
		"weights": [0.7, 0.3]}})
	var loot := ResourceLoader.load(res_dir + "/loot.tres", "", ResourceLoader.CACHE_MODE_IGNORE)
	_expect(loot != null and (loot.get("items") as Array).size() == 2 and (loot.get("items") as Array)[0].get("style") is StyleBoxFlat, "create_resource con class_name, array tipado y sub-recurso (%s)" % loot_text)
	var read_loot := await _call_text("get_resource", {"path": res_dir + "/loot.tres"})
	_expect(read_loot.contains("FixtureLoot (script") and read_loot.contains("[0] <FixtureItem, inline>") and read_loot.contains("title = \"Sword\"") and read_loot.contains("bg_color") and read_loot.contains("weights = PackedFloat32Array(0.7, 0.3)") and not read_loot.contains("tint"), "get_resource (%s)" % read_loot)
	await _call_text("create_resource", {"path": res_dir + "/panel.tres", "type": "StyleBoxFlat", "properties": {"bg_color": "#102030"}})
	var changed_res := await _call_text("set_resource_properties", {"path": res_dir + "/panel.tres", "properties": {"bg_color": "#ffffff", "corner_radius_top_left": 8}})
	var panel_style := ResourceLoader.load(res_dir + "/panel.tres", "", ResourceLoader.CACHE_MODE_IGNORE) as StyleBoxFlat
	_expect(panel_style != null and panel_style.bg_color == Color.WHITE and panel_style.corner_radius_top_left == 8 and changed_res.contains("saved"), "set_resource_properties guarda (%s)" % changed_res)
	EditorUndo._trigger_editor_undo()
	panel_style = ResourceLoader.load(res_dir + "/panel.tres", "", ResourceLoader.CACHE_MODE_IGNORE) as StyleBoxFlat
	_expect(panel_style != null and panel_style.bg_color == Color.html("#102030") and panel_style.corner_radius_top_left == 0, "Ctrl+Z revierte y guarda el recurso")
	await _call_text("add_node", {"parent": ".", "type": "Panel", "name": "StyledPanel", "properties": {"theme_override_styles/panel": res_dir + "/panel.tres"}})
	var styled := root.get_node_or_null("StyledPanel") as Panel
	_expect(styled != null and styled.get("theme_override_styles/panel") is StyleBoxFlat and (styled.get("theme_override_styles/panel") as Resource).resource_path == res_dir + "/panel.tres", "el recurso se asigna por ruta")
	await _call_text("set_properties", {"node_path": "StyledPanel", "properties": {"theme_override_styles/panel": {"type": "StyleBoxFlat", "bg_color": "#00ff00"}}})
	_expect(styled != null and (styled.get("theme_override_styles/panel") as StyleBoxFlat).bg_color == Color(0, 1, 0), "set_properties con un recurso inline")
	EditorUndo._trigger_editor_undo()
	EditorUndo._trigger_editor_undo()
	_expect(not root.has_node("StyledPanel"), "undo del panel")
	await _call_text("add_nodes", {"parent": ".", "nodes": [{"name": "Grunt", "type": "FixtureEnemy", "properties": {"hp": 5}}]})
	var grunt := root.get_node_or_null("Grunt")
	_expect(grunt != null and grunt.get_script() != null and int(grunt.get(&"hp")) == 5, "add_nodes con un class_name sin @tool")
	EditorUndo._trigger_editor_undo()
	var exists_again: Dictionary = await _call("create_resource", {"path": res_dir + "/panel.tres", "type": "StyleBoxFlat"})
	_expect(exists_again.get("isError", false), "create_resource no pisa")

	# Tilemaps (m4-11): capa con TileSet inline, atlas desde una textura, celdas, terreno y undo.
	var tiles_png := FILES_DIR + "/tiles.png"
	var sheet := Image.create(48, 16, false, Image.FORMAT_RGBA8)
	sheet.fill_rect(Rect2i(0, 0, 16, 16), Color.GREEN)
	sheet.fill_rect(Rect2i(16, 0, 16, 16), Color.SADDLE_BROWN)  # el tercer tile queda transparente
	sheet.save_png(ProjectSettings.globalize_path(tiles_png))
	EditorInterface.get_resource_filesystem().scan()
	await _tree.create_timer(2.0).timeout
	await _call_text("add_node", {"parent": ".", "type": "TileMapLayer", "name": "Ground", "properties": {"tile_set": {"type": "TileSet", "tile_size": [16, 16]}}})
	var atlas_text := await _call_text("tileset_add_atlas", {"node_path": "Ground", "texture": tiles_png, "collision": true})
	var ground := root.get_node_or_null("Ground") as TileMapLayer
	var atlas_source := ground.tile_set.get_source(0) as TileSetAtlasSource if ground and ground.tile_set and ground.tile_set.has_source(0) else null
	_expect(atlas_source != null and atlas_source.get_tiles_count() == 2 and ground.tile_set.get_physics_layers_count() == 1 and atlas_source.get_tile_data(Vector2i(0, 0), 0).get_collision_polygons_count(0) == 1, "tileset_add_atlas: 2 tiles (el transparente no), con colisión (%s)" % atlas_text)
	var cells_text := await _call_text("tilemap_set_cells", {"node_path": "Ground", "rect": [0, 3, 10, 1]})
	await _call_text("tilemap_set_cells", {"node_path": "Ground", "cells": [[2, 2], {"x": 3, "y": 2, "atlas": [1, 0]}]})
	_expect(ground.get_used_cells().size() == 12 and ground.get_cell_atlas_coords(Vector2i(3, 2)) == Vector2i(1, 0) and cells_text.contains("Set 10 cells"), "tilemap_set_cells con rect y celdas (%s)" % cells_text)
	var bad_tile: Dictionary = await _call("tilemap_set_cells", {"node_path": "Ground", "cells": [[0, 0]], "atlas": [2, 0]})
	_expect(bad_tile.get("isError", false) and _text(bad_tile).contains("no tile at atlas"), "tile inexistente → error")
	var map_text := await _call_text("tilemap_get", {"node_path": "Ground"})
	_expect(map_text.contains("12 cells") and map_text.contains("   3 aaaaaaaaaa") and map_text.contains("b = 0:(1,0)") and map_text.contains("Physics layers: 1"), "tilemap_get con mapa y leyenda (%s)" % map_text)
	EditorUndo._trigger_editor_undo()
	_expect(ground.get_used_cells().size() == 10, "Ctrl+Z deshace las celdas sueltas")
	await _call_text("tilemap_set_cells", {"node_path": "Ground", "rect": [0, 3, 2, 1], "erase": true})
	_expect(ground.get_used_cells().size() == 8, "erase")
	await _call_text("tilemap_clear", {"node_path": "Ground"})
	_expect(ground.get_used_cells().is_empty(), "tilemap_clear")
	EditorUndo._trigger_editor_undo()
	_expect(ground.get_used_cells().size() == 8, "Ctrl+Z deshace el clear")
	var no_terrain: Dictionary = await _call("tilemap_paint_terrain", {"node_path": "Ground", "rect": [0, 0, 2, 2], "terrain": 0})
	_expect(no_terrain.get("isError", false) and _text(no_terrain).contains("no terrain sets"), "sin terrenos → error que explica")
	# Un terreno armado como en el editor de TileSet: el tile verde con sus cuatro lados en el terreno 0.
	ground.tile_set.add_terrain_set()
	ground.tile_set.set_terrain_set_mode(0, TileSet.TERRAIN_MODE_MATCH_SIDES)
	ground.tile_set.add_terrain(0)
	ground.tile_set.set_terrain_name(0, 0, "grass")
	var grass := atlas_source.get_tile_data(Vector2i(0, 0), 0)
	grass.terrain_set = 0
	grass.terrain = 0
	for side: int in [TileSet.CELL_NEIGHBOR_RIGHT_SIDE, TileSet.CELL_NEIGHBOR_BOTTOM_SIDE, TileSet.CELL_NEIGHBOR_LEFT_SIDE, TileSet.CELL_NEIGHBOR_TOP_SIDE]:
		grass.set_terrain_peering_bit(side, 0)
	var painted := await _call_text("tilemap_paint_terrain", {"node_path": "Ground", "rect": [10, 0, 3, 3], "terrain": "Grass"})
	_expect(ground.get_cell_source_id(Vector2i(11, 1)) == 0 and ground.get_cell_atlas_coords(Vector2i(11, 1)) == Vector2i(0, 0) and painted.contains("grass"), "tilemap_paint_terrain por nombre (%s)" % painted)
	var not_layer: Dictionary = await _call("tilemap_get", {"node_path": "Timer"})
	_expect(not_layer.get("isError", false) and _text(not_layer).contains("not a TileMapLayer"), "tilemap_get sobre otro nodo → error")

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


## Guardar los settings reescribe config/features con la versión del editor que corre la prueba.
static func _without_features(text: String) -> String:
	return RegEx.create_from_string("config/features=.*\n").sub(text, "")


static func _write(path: String, text: String) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()


static func _remove_tree(absolute: String) -> void:
	if not DirAccess.dir_exists_absolute(absolute):
		return
	for file: String in DirAccess.get_files_at(absolute):
		DirAccess.remove_absolute(absolute.path_join(file))
	for sub: String in DirAccess.get_directories_at(absolute):
		_remove_tree(absolute.path_join(sub))
	DirAccess.remove_absolute(absolute)
