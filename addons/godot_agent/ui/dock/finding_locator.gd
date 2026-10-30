@tool
extends RefCounted
## Lleva un hallazgo de playtest a la escena (m15-18): abre su escena si hace falta, busca el nodo por
## nombre o el más cercano a donde pasó, lo selecciona y encuadra la cámara.
## Basado en _show_in_level de dock.gd de Autopilot (ramenvr/autopilot, Apache 2.0).

const I18n := preload("../../core/i18n.gd")


## Devuelve qué mostró, o el problema (para el aviso del chat): [ok, texto].
static func show(finding: Dictionary) -> Array:
	var scene := str(finding.get("scene", ""))
	var root := EditorInterface.get_edited_scene_root()
	if not scene.is_empty() and (root == null or root.scene_file_path != scene):
		EditorInterface.open_scene_from_path(scene)
		await EditorInterface.get_base_control().get_tree().process_frame
		root = EditorInterface.get_edited_scene_root()
	if root == null:
		return [false, I18n.t("Open the scene to show this finding in it.")]
	var target := nearest_node(root, str(finding.get("node", "")), finding.get("where", []))
	if target == null:
		return [false, I18n.t("Nothing in the open scene matches this finding.")]
	var selection := EditorInterface.get_selection()
	selection.clear()
	selection.add_node(target)
	EditorInterface.edit_node(target)
	EditorInterface.set_main_screen_editor("3D" if target is Node3D else "2D")
	var tree := EditorInterface.get_base_control().get_tree()
	await tree.process_frame
	await tree.process_frame
	_frame_selection(target is Node3D)
	var exact := str(target.name) == str(finding.get("node", ""))
	return [true, (I18n.t("Showing %s.") if exact else I18n.t("Showing %s, the nearest node to the finding.")) % target.name]


## El nodo de ese nombre (el del juego puede ser `Nombre#2`) o el más cercano a `where`, o null.
static func nearest_node(root: Node, node_name: String, where: Variant) -> Node:
	var plain := node_name.get_slice("#", 0)
	if not plain.is_empty():
		if str(root.name) == plain:
			return root
		var named := root.find_child(plain, true, false)
		if named:
			return named
	if not where is Array or (where as Array).size() < 2:
		return null
	var points: Array = where
	var best: Node = null
	var best_distance := INF
	if points.size() == 3:
		var point := Vector3(points[0], points[1], points[2])
		for node: Node in root.find_children("*", "Node3D", true, true):
			var distance: float = (node as Node3D).global_position.distance_squared_to(point)
			if distance < best_distance:
				best_distance = distance
				best = node
	else:
		var point := Vector2(points[0], points[1])
		for node: Node in root.find_children("*", "Node2D", true, true):
			var distance: float = (node as Node2D).global_position.distance_squared_to(point)
			if distance < best_distance:
				best_distance = distance
				best = node
	return best


## Como View > Focus Selection: el ítem del menú con ese atajo, sea cual sea el idioma del editor.
static func _frame_selection(is_3d: bool) -> void:
	var settings := EditorInterface.get_editor_settings()
	var key := "spatial_editor/focus_selection" if is_3d else "canvas_item_editor/frame_selection"
	if not settings.has_shortcut(key):
		return
	var shortcut := settings.get_shortcut(key)
	var node: Node = EditorInterface.get_editor_viewport_3d(0) if is_3d else EditorInterface.get_editor_viewport_2d()
	var owner_class := "Node3DEditorViewport" if is_3d else "CanvasItemEditor"
	while node != null and node.get_class() != owner_class:
		node = node.get_parent()
	if node == null:
		return
	var stack: Array[Node] = [node]
	while not stack.is_empty():
		var current: Node = stack.pop_back()
		if current is PopupMenu:
			var menu := current as PopupMenu
			for i: int in menu.item_count:
				if menu.get_item_shortcut(i) == shortcut:
					menu.id_pressed.emit(menu.get_item_id(i))
					return
		stack.append_array(current.get_children(true))
