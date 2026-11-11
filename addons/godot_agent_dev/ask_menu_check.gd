@tool
extends RefCounted
## m11-54 en el editor: «Ask the agent» de los tres menús contextuales, abiertos como los abre el editor.
## 1. FileSystem: con un archivo seleccionado, el clic derecho del árbol (item_mouse_selected) arma el
##    menú con el ítem del plugin; apretarlo deja «@res://… » en el composer.
## 2. Dock Escena: con un nodo seleccionado, rmb_pressed del SceneTreeEditor; deja «@Ruta ».
## 3. Script Editor: una selección real en el CodeEdit y un clic derecho sobre ella (gui_input); deja el
##    bloque con @archivo y las líneas.
## En cada caso el composer de la pestaña activa recibe el texto sin mandarlo (sigue sin turno) y el dock,
## escondido detrás de otra pestaña de su ranura antes del clic, queda al frente.

const PLUGIN_SCRIPT := "res://addons/godot_agent/agent_plugin.gd"
const ITEM := "Ask the agent"
const WORK_DIR := "res://tests/tmp/ask_menu"
const SCRIPT_PATH := WORK_DIR + "/ask_target.gd"
const SCENE_PATH := WORK_DIR + "/ask_scene.tscn"
const SCRIPT_TEXT := "extends Node\n\nfunc jump() -> void:\n\tprint(\"jump\")\n"

var failures: PackedStringArray = []
var _tree: SceneTree
var _dock: Control
var _input: TextEdit


func run(tree: SceneTree, dock: Control) -> PackedStringArray:
	_tree = tree
	_dock = dock
	_input = (dock.get(&"_composer") as Object).get(&"_input")
	var plugin: Node = null
	for node: Node in tree.root.find_children("*", "Node", true, false):
		if node.get_script() and (node.get_script() as Script).resource_path == PLUGIN_SCRIPT:
			plugin = node
	if plugin == null or (plugin.get(&"_ask_menus") as Array).size() != 3:
		failures.append("el plugin no registró los tres menús «Ask the agent»")
		return failures
	_write_fixtures()
	EditorInterface.get_resource_filesystem().scan()
	await _frames(30)
	await _filesystem_case()
	await _scene_case()
	await _script_case()
	_input.text = ""
	return failures


func _filesystem_case() -> void:
	await _prepare()
	EditorInterface.select_file(SCRIPT_PATH)
	await _frames(5)
	var fs_tree := _first_tree(EditorInterface.get_file_system_dock())
	if fs_tree == null:
		failures.append("FileSystem: no se encontró el árbol")
		return
	fs_tree.item_mouse_selected.emit(Vector2(10, 10), MOUSE_BUTTON_RIGHT)
	await _press_item("FileSystem")
	await _expect("FileSystem", "@%s " % SCRIPT_PATH)


func _scene_case() -> void:
	EditorInterface.open_scene_from_path(SCENE_PATH)
	await _frames(10)
	var root := EditorInterface.get_edited_scene_root()
	var player := root.get_node_or_null(^"Player") if root else null
	if player == null:
		failures.append("Escena: no se abrió %s" % SCENE_PATH)
		return
	await _prepare()
	EditorInterface.get_selection().clear()
	EditorInterface.get_selection().add_node(player)
	await _frames(5)
	var editor: Node = null
	for node: Node in EditorInterface.get_base_control().find_children("*", "SceneTreeEditor", true, false):
		if node.has_signal(&"rmb_pressed") and (node as Control).is_visible_in_tree():
			editor = node
	if editor == null:
		failures.append("Escena: no se encontró el SceneTreeEditor del dock")
		return
	var args: Array = [Vector2(10, 10)]
	for signal_info: Dictionary in editor.get_signal_list():
		if signal_info.name == "rmb_pressed" and (signal_info.args as Array).size() > 1:
			args.append(MOUSE_BUTTON_RIGHT)
	editor.callv(&"emit_signal", [&"rmb_pressed"] + args)
	await _press_item("Escena")
	await _expect("Escena", "@Player ")


func _script_case() -> void:
	EditorInterface.edit_script(load(SCRIPT_PATH), 3, 0)
	await _frames(10)
	var current := EditorInterface.get_script_editor().get_current_editor()
	var code := current.get_base_editor() as CodeEdit if current else null
	if code == null:
		failures.append("Script Editor: no se abrió %s" % SCRIPT_PATH)
		return
	EditorInterface.set_main_screen_editor("Script")
	await _prepare()
	await _frames(10)
	if not code.is_visible_in_tree():
		failures.append("Script Editor: el CodeEdit no está a la vista")
	code.grab_focus()
	code.select(2, 0, 3, 14)
	await _frames(3)
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_RIGHT
	var target := code.get_rect_at_line_column(2, 3)
	click.position = Vector2(target.get_center())
	if target.position.x < 0 or code.get_line_column_at_pos(Vector2i(click.position)) != Vector2i(3, 2):
		failures.append("Script Editor: el punto del clic no cae en la selección (%s → %s)" % [target, code.get_line_column_at_pos(Vector2i(click.position))])
	# ScriptTextEditor ubica el clic con la posición global (menos la del CodeEdit).
	click.global_position = code.get_global_transform() * click.position
	click.pressed = true
	code.gui_input.emit(click)
	var release := click.duplicate() as InputEventMouseButton
	release.pressed = false
	code.gui_input.emit(release)
	if not code.has_selection():
		failures.append("Script Editor: el clic derecho sacó la selección")
	await _press_item("Script Editor")
	await _expect("Script Editor", "@%s (lines 3-4):\n```gdscript\nfunc jump() -> void:\n\tprint(\"jump\")\n```\n" % SCRIPT_PATH)


## Composer vacío y el dock tapado por otra pestaña de su ranura, para ver que el ítem lo trae al frente.
func _prepare() -> void:
	_input.text = ""
	var guard: Node = _dock
	var holder := _dock.get_parent()
	while holder and not holder is TabContainer:
		guard = holder
		holder = holder.get_parent()
	if holder is TabContainer and (holder as TabContainer).get_tab_count() > 1:
		var tabs := holder as TabContainer
		tabs.current_tab = (guard.get_index() + 1) % tabs.get_tab_count()
	await _frames(3)
	if _dock.is_visible_in_tree():
		failures.append("no se pudo tapar el dock antes del clic (no hay otra pestaña en su ranura)")


## Aprieta «Ask the agent» en el PopupMenu que abrió el editor y lo cierra.
func _press_item(where: String) -> void:
	await _frames(3)
	for node: Node in EditorInterface.get_base_control().get_tree().root.find_children("*", "PopupMenu", true, false):
		var menu := node as PopupMenu
		if not menu.visible:
			continue
		for i in menu.item_count:
			if menu.get_item_text(i) == ITEM:
				menu.id_pressed.emit(menu.get_item_id(i))
				menu.hide()
				await _frames(5)
				return
	failures.append("%s: el menú abierto no tiene «%s»" % [where, ITEM])


func _expect(where: String, text: String) -> void:
	if _input.text != text:
		failures.append("%s: el composer tiene %s y se esperaba %s" % [where, JSON.stringify(_input.text), JSON.stringify(text)])
	if not _dock.is_visible_in_tree():
		failures.append("%s: el dock no quedó al frente" % where)
	if (_dock.get(&"_model") as Object).call(&"is_busy"):
		failures.append("%s: se mandó un turno" % where)


func _write_fixtures() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(WORK_DIR))
	var file := FileAccess.open(SCRIPT_PATH, FileAccess.WRITE)
	file.store_string(SCRIPT_TEXT)
	file.close()
	var root := Node2D.new()
	root.name = "AskScene"
	var player := Node2D.new()
	player.name = "Player"
	root.add_child(player)
	player.owner = root
	var scene := PackedScene.new()
	scene.pack(root)
	ResourceSaver.save(scene, SCENE_PATH)
	root.free()


static func _first_tree(parent: Node) -> Tree:
	for node: Node in parent.find_children("*", "Tree", true, false):
		if (node as Tree).is_visible_in_tree():
			return node
	return null


func _frames(count: int) -> void:
	for i in count:
		await _tree.process_frame
