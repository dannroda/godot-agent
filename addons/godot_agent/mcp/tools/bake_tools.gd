@tool
extends RefCounted
## godot.bake (m11-53): hornea la navegación, los lightmaps o los occluders de la escena abierta.
## - navigation: con la API (NavigationRegion3D.bake_navigation_mesh, NavigationRegion2D.bake_navigation_
##   polygon). Se puede deshacer: el paso de undo guarda vertices y polygons de antes sobre el mismo
##   recurso, así un NavigationMesh en un .tres sigue siendo ese archivo.
## - lightmaps y occluders: Godot no los expone a los scripts (LightmapGI y OccluderInstance3D no tienen
##   bake en ClassDB, 4.7 y 4.8). Se selecciona el nodo y se aprieta el botón «Bake Lightmaps» / «Bake
##   Occluders» de la barra del 3D, que se busca por su texto (en inglés y como lo muestra el editor), no
##   por su lugar. El editor escribe el archivo junto a la escena (.lmbake + .exr, .occ) y no lo deja en
##   el historial de deshacer: el informe dice qué archivos escribió.

const McpTool := preload("../mcp_tool.gd")
const WriteTargets := preload("../write_targets.gd")
const PermissionPolicy := preload("../../session/permission_policy.gd")
const SceneAccess := preload("scene_access.gd")
const EditorUndo := preload("../../editor/editor_undo.gd")

const KIND_NAVIGATION := "navigation"
const KIND_LIGHTMAPS := "lightmaps"
const KIND_OCCLUDERS := "occluders"
const KINDS: PackedStringArray = [KIND_NAVIGATION, KIND_LIGHTMAPS, KIND_OCCLUDERS]
## Texto del botón de cada plugin del editor (editor/plugins/*_editor_plugin.cpp).
const BUTTON_TEXTS := {KIND_LIGHTMAPS: "Bake Lightmaps", KIND_OCCLUDERS: "Bake Occluders"}
const NODE_TYPES := {KIND_LIGHTMAPS: "LightmapGI", KIND_OCCLUDERS: "OccluderInstance3D"}
const EDITOR_DOMAIN := &"godot.editor"
const NAVIGATION_TIMEOUT_S := 120.0
## Frames para que el plugin del editor muestre su botón después de seleccionar el nodo.
const BUTTON_WAIT_FRAMES := 10

## `(tool_name, args, info)`: el paso de deshacer, para la tarjeta de la tool (como las demás que editan).
var on_action: Callable


func tools() -> Array:
	return WriteTargets.declare([
		McpTool.create("bake", PermissionPolicy.GROUP_EDIT_SCENE,
			"Bake the open scene: `navigation` rebuilds the navigation of NavigationRegion2D/3D nodes from their geometry (do it after adding or moving level geometry; undoable), `lightmaps` bakes LightmapGI nodes (the scene must be saved; needs the Forward+ or Mobile renderer; writes a .lmbake and .exr files next to the scene) and `occluders` bakes OccluderInstance3D nodes (the scene must be saved; writes a .occ file). Lightmaps and occluders use the editor's own Bake button and, as in the editor, are not undoable. Without `path`, every node of that kind in the scene.",
			{
				"kind": {"type": "string", "enum": Array(KINDS), "description": "What to bake"},
				"path": {"type": "string", "description": "Node path of one region, LightmapGI or OccluderInstance3D, relative to the scene root (default: all of them)"},
			}, ["kind"], _bake),
	], {"bake": written_paths})


func _bake(args: Dictionary) -> Dictionary:
	var kind := McpTool.str_arg(args, "kind")
	if not kind in KINDS:
		return McpTool.error("`kind` must be one of: %s." % ", ".join(KINDS))
	var root := EditorInterface.get_edited_scene_root()
	if root == null:
		return McpTool.error("There is no scene open in the editor: open the scene to bake first (open_scene).")
	var nodes := targets(root, kind, McpTool.str_arg(args, "path"))
	if nodes.is_empty():
		var path := McpTool.str_arg(args, "path")
		if not path.is_empty():
			return McpTool.error("%s is not a %s in %s." % [path, _type_label(kind), root.scene_file_path])
		return McpTool.error("The scene %s has no %s." % [root.scene_file_path, _type_label(kind)])
	if kind == KIND_NAVIGATION:
		return await _bake_navigation(root, nodes, args)
	return await _bake_with_button(root, nodes, kind)


## Los nodos a hornear: el de `path` si es del tipo, o todos los de la escena (no los de adentro de una
## escena instanciada, que se hornean en la suya).
static func targets(root: Node, kind: String, path: String) -> Array[Node]:
	var found: Array[Node] = []
	if not path.is_empty():
		var node := SceneAccess.find_node(root, path)
		if node and _is_target(node, kind):
			found.append(node)
		return found
	for node: Node in [root] + root.find_children("*", "", true, false):
		if _is_target(node, kind) and (node == root or node.owner == root):
			found.append(node)
	return found


static func _is_target(node: Node, kind: String) -> bool:
	if kind == KIND_NAVIGATION:
		return node is NavigationRegion3D or node is NavigationRegion2D
	return node.is_class(str(NODE_TYPES[kind]))


static func _type_label(kind: String) -> String:
	return "NavigationRegion2D/3D" if kind == KIND_NAVIGATION else str(NODE_TYPES[kind])


# --- Navegación --------------------------------------------------------------------------------------

func _bake_navigation(root: Node, regions: Array[Node], args: Dictionary) -> Dictionary:
	var lines: PackedStringArray = []
	var changes: Array[Dictionary] = []
	for region: Node in regions:
		var label := SceneAccess.relative_path(root, region)
		var resource: Resource = navigation_resource(region)
		if resource == null:
			lines.append("✗ %s: has no %s to bake into; create one in the Inspector (or with set_properties)." % [label, "NavigationMesh" if region is NavigationRegion3D else "NavigationPolygon"])
			continue
		var before := navigation_data(resource)
		var finished := [false]
		var on_finished := func() -> void: finished[0] = true
		region.connect(&"bake_finished", on_finished, CONNECT_ONE_SHOT)
		if region is NavigationRegion3D:
			(region as NavigationRegion3D).bake_navigation_mesh(true)
		else:
			(region as NavigationRegion2D).bake_navigation_polygon(true)
		var tree := Engine.get_main_loop() as SceneTree
		var deadline := Time.get_ticks_msec() + int(NAVIGATION_TIMEOUT_S * 1000)
		while not finished[0] and Time.get_ticks_msec() < deadline:
			await tree.process_frame
		if not finished[0]:
			if region.is_connected(&"bake_finished", on_finished):
				region.disconnect(&"bake_finished", on_finished)
			lines.append("✗ %s: the bake did not finish in %d s." % [label, int(NAVIGATION_TIMEOUT_S)])
			continue
		var after := navigation_data(resource)
		changes.append({"resource": resource, "before": before, "after": after})
		var polygons := int(resource.call(&"get_polygon_count"))
		if polygons == 0:
			lines.append("⚠ %s: 0 polygons. Nothing to walk on was found: check the resource's parsed_geometry_type and source_geometry_mode (by default it reads the region's children: meshes, or collision shapes with static_colliders)%s." % [label, ", and its outlines (the traversable area in 2D)" if region is NavigationRegion2D else ""])
		else:
			lines.append("✓ %s: %d polygons (%s)." % [label, polygons, _resource_label(resource)])
	if changes.is_empty():
		return McpTool.error("\n".join(lines))
	var action := "Bake navigation"
	var undo_redo := EditorInterface.get_editor_undo_redo()
	undo_redo.create_action(action, UndoRedo.MERGE_DISABLE, root)
	for change: Dictionary in changes:
		for property: String in change.after:
			undo_redo.add_do_property(change.resource, property, change.after[property])
			undo_redo.add_undo_property(change.resource, property, change.before[property])
	undo_redo.commit_action(false)  # el horneado ya los dejó así
	if on_action.is_valid():
		on_action.call("bake", args, EditorUndo.record(action, root))
	return McpTool.text("%s\nThe scene has unsaved changes (save_scene). Undo step: «%s»." % ["\n".join(lines), action])


static func navigation_resource(region: Node) -> Resource:
	if region is NavigationRegion3D:
		return (region as NavigationRegion3D).navigation_mesh
	if region is NavigationRegion2D:
		return (region as NavigationRegion2D).navigation_polygon
	return null


## Lo que cambia un horneado: vertices y polygons (copias, para el paso de deshacer).
static func navigation_data(resource: Resource) -> Dictionary:
	var polygons: Array = resource.get(&"polygons")
	return {"vertices": resource.get(&"vertices").duplicate(), "polygons": polygons.duplicate(true)}


static func _resource_label(resource: Resource) -> String:
	if resource.resource_path.is_empty() or resource.resource_path.contains("::"):
		return "saved with the scene"
	return "saved in %s when the scene is saved" % resource.resource_path


# --- Lightmaps y occluders ---------------------------------------------------------------------------

func _bake_with_button(root: Node, nodes: Array[Node], kind: String) -> Dictionary:
	if root.scene_file_path.is_empty():
		return McpTool.error("Save the scene first (save_scene with a path): the editor bakes %s next to the scene file, and asks for a file otherwise." % kind)
	if kind == KIND_LIGHTMAPS and RenderingServer.get_current_rendering_method() == "gl_compatibility":
		return McpTool.error("Lightmaps can't be baked with the Compatibility renderer. Switch the project to Forward+ or Mobile (Project Settings → Rendering → Renderer) and restart the editor.")
	EditorInterface.set_main_screen_editor("3D")
	var lines: PackedStringArray = []
	var ok := 0
	for node: Node in nodes:
		var label := SceneAccess.relative_path(root, node)
		var outcome: Dictionary = await press_bake_button(node, kind)
		if outcome.has("error"):
			lines.append("✗ %s: %s" % [label, outcome.error])
		else:
			ok += 1
			lines.append("✓ %s: wrote %s." % [label, ", ".join(outcome.files)])
	if ok == 0:
		return McpTool.error("\n".join(lines))
	EditorInterface.mark_scene_as_unsaved()
	return McpTool.text("%s\nThe scene has unsaved changes (the node points at the baked data): save it (save_scene). As in the editor, a bake is not undoable." % "\n".join(lines))


## Selecciona `node`, aprieta el botón de hornear del editor y espera el archivo. `{files}` o `{error}`.
func press_bake_button(node: Node, kind: String) -> Dictionary:
	var tree := Engine.get_main_loop() as SceneTree
	var selection := EditorInterface.get_selection()
	selection.clear()
	selection.add_node(node)
	EditorInterface.edit_node(node)
	var button: BaseButton = null
	for frame in BUTTON_WAIT_FRAMES:
		await tree.process_frame
		button = find_bake_button(kind)
		if button:
			break
	if button == null:
		return {"error": "the editor's «%s» button was not found (Godot %s): bake it from the 3D editor toolbar with the node selected." % [BUTTON_TEXTS[kind], Engine.get_version_info().string]}
	var before := _files_state(node, kind)
	var dialogs_before := _visible_dialogs()
	# Como un clic: el plugin escucha `pressed`. El horneado corre en esta llamada (con su barra de progreso).
	button.pressed.emit()
	await tree.process_frame
	await tree.process_frame
	# La primera vez (el nodo todavía no apunta a un archivo) el editor abre «Guardar» con la ruta que
	# propone, junto a la escena. Se acepta solo esa: es lo que haría el usuario con Enter.
	var proposed := default_file(node, kind)
	for dialog: AcceptDialog in _visible_dialogs():
		if dialog is FileDialog and not dialog in dialogs_before and _dialog_path(dialog as FileDialog) == proposed:
			dialog.hide()
			(dialog as FileDialog).file_selected.emit(proposed)
			await tree.process_frame
			await tree.process_frame
	var message := _new_dialog_text(dialogs_before)
	var after := _files_state(node, kind)
	var written: PackedStringArray = []
	for path: String in after:
		if not before.has(path) or before[path] != after[path]:
			written.append(path)
	var main_ext := ".lmbake" if kind == KIND_LIGHTMAPS else ".occ"
	if not Array(written).any(func(path: String) -> bool: return path.ends_with(main_ext)):
		var detail := message if not message.is_empty() else "the editor did not write the %s file (see get_errors)" % main_ext
		return {"error": detail + (" Files written anyway: %s." % ", ".join(written) if not written.is_empty() else "")}
	if not message.is_empty():
		written.append("(the editor said: %s)" % message)
	return {"files": written}


## Lo que escribe un horneado (m11-39): la escena abierta, el recurso del nodo si es un archivo propio y,
## para luces y oclusores, el archivo que propone el editor junto a la escena.
static func written_paths(args: Dictionary) -> PackedStringArray:
	var result := WriteTargets.scene({})
	var root: Node = EditorInterface.get_edited_scene_root() if Engine.is_editor_hint() else null
	var kind := McpTool.str_arg(args, "kind")
	if root == null or not kind in KINDS:
		return result
	for node: Node in targets(root, kind, McpTool.str_arg(args, "path")):
		var data: Variant
		match kind:
			KIND_NAVIGATION: data = node.get(&"navigation_mesh") if node is NavigationRegion3D else node.get(&"navigation_polygon")
			KIND_LIGHTMAPS: data = node.get(&"light_data")
			_: data = node.get(&"occluder")
		var file := WriteTargets.resource_file(data as Resource) if data is Resource else ""
		if not file.is_empty():
			result.append(file)
		if kind != KIND_NAVIGATION and not default_file(node, kind).is_empty():
			result.append(default_file(node, kind))
	return result


## Lo que propone el editor al hornear por primera vez: la escena con .lmbake u .occ.
static func default_file(node: Node, kind: String) -> String:
	var scene := node.scene_file_path
	if scene.is_empty() and node.owner:
		scene = node.owner.scene_file_path
	return scene.get_basename() + (".lmbake" if kind == KIND_LIGHTMAPS else ".occ") if not scene.is_empty() else ""


static func _dialog_path(dialog: FileDialog) -> String:
	var path := dialog.current_path
	if not path.begins_with("res://") and not dialog.current_dir.is_empty():
		path = dialog.current_dir.path_join(dialog.current_file)
	return path.simplify_path()


## El botón visible con el texto del plugin, en inglés o como lo muestra el editor en su idioma.
static func find_bake_button(kind: String) -> BaseButton:
	var base := EditorInterface.get_base_control()
	if base == null:
		return null
	var texts := translations(str(BUTTON_TEXTS[kind]))
	for found: Node in base.find_children("*", "Button", true, false):
		var button := found as Button
		if button.is_visible_in_tree() and not button.disabled and button.text in texts:
			return button
	return null


static func translations(text: String) -> PackedStringArray:
	var texts: PackedStringArray = [text]
	if TranslationServer.has_method(&"get_or_add_domain"):
		texts.append(str(TranslationServer.call(&"get_or_add_domain", EDITOR_DOMAIN).call(&"translate", text)))
	return texts


## Ruta → fecha de modificación de los archivos del horneado: el que apunta el nodo y los que deja el
## editor junto a la escena (.lmbake y sus .exr, .occ).
static func _files_state(node: Node, kind: String) -> Dictionary:
	var state := {}
	var paths: PackedStringArray = []
	var data: Variant = node.get(&"light_data") if kind == KIND_LIGHTMAPS else node.get(&"occluder")
	if data is Resource and not (data as Resource).resource_path.is_empty() and not (data as Resource).resource_path.contains("::"):
		paths.append((data as Resource).resource_path)
	var scene := node.owner.scene_file_path if node.owner else node.scene_file_path
	var base := scene.get_basename()
	var dir := scene.get_base_dir()
	for file: String in DirAccess.get_files_at(dir):
		var path := dir.path_join(file)
		if kind == KIND_LIGHTMAPS and path.begins_with(base) and (file.ends_with(".lmbake") or file.ends_with(".exr")):
			paths.append(path)
		elif kind == KIND_OCCLUDERS and path.begins_with(base) and file.ends_with(".occ"):
			paths.append(path)
	for path: String in paths:
		if FileAccess.file_exists(path):
			state[path] = FileAccess.get_modified_time(path)
	return state


static func _visible_dialogs() -> Array[AcceptDialog]:
	var visible: Array[AcceptDialog] = []
	var base := EditorInterface.get_base_control()
	if base:
		for found: Node in base.get_tree().root.find_children("*", "AcceptDialog", true, false):
			if (found as AcceptDialog).visible:
				visible.append(found)
	return visible


## El texto de un aviso que abrió el editor al hornear («No meshes to bake…»), que se cierra: «» si no hubo.
static func _new_dialog_text(before: Array[AcceptDialog]) -> String:
	for dialog: AcceptDialog in _visible_dialogs():
		if dialog in before:
			continue
		if dialog is FileDialog:
			# No tendría que pasar con la escena guardada; nunca se deja abierto esperando al usuario.
			dialog.hide()
			return "the editor asked where to save the baked file instead of baking"
		var text := dialog.dialog_text.strip_edges()
		dialog.hide()
		if not text.is_empty():
			return text.replace("\n", " ")
	return ""
