@tool
extends RefCounted
## Tools de edición (spec §6): grupo edit_scene (add_node, set_properties, remove_node,
## reparent_node, rename_node, connect_signal, instantiate_scene, open_scene, save_scene) y
## edit_files (create_scene, attach_script). Cada tool que cambia la escena es una sola acción de
## EditorUndoRedoManager y devuelve el nombre del paso de undo.

const McpTool := preload("../mcp_tool.gd")
const SceneAccess := preload("scene_access.gd")
const ValueCoercion := preload("value_coercion.gd")
const EditorUndo := preload("../../editor/editor_undo.gd")
const PermissionPolicy := preload("../../session/permission_policy.gd")

const ACTION_PREFIX := "Agent: "
const SCENE_ARG := {"type": "string", "description": "res://…tscn scene; opened if it is not the current one (default: the open one)"}

## Callable(tool_name: String, args: Dictionary, undo_info: Dictionary): cada acción commiteada.
var on_action: Callable


func tools() -> Array:
	var scene := PermissionPolicy.GROUP_EDIT_SCENE
	var files := PermissionPolicy.GROUP_EDIT_FILES
	return [
		McpTool.create("add_node", scene,
			"Adds a node to the open scene (with undo). `type` is a Godot class or a project class_name. `properties` uses Inspector property names; vectors as [x, y], colors as \"#rrggbb\", resources as res:// paths.",
			{
				"parent": {"type": "string", "description": "NodePath of the parent (\".\" = root)"},
				"type": {"type": "string"},
				"name": {"type": "string"},
				"properties": {"type": "object"},
				"scene": SCENE_ARG,
			}, ["parent", "type", "name"], _add_node),
		McpTool.create("set_properties", scene,
			"Changes properties of a node (with undo, a single step). Returns the old and new values.",
			{"node_path": {"type": "string"}, "properties": {"type": "object"}, "scene": SCENE_ARG},
			["node_path", "properties"], _set_properties),
		McpTool.create("remove_node", scene, "Deletes a node and its children (with undo). Does not delete the root.",
			{"node_path": {"type": "string"}, "scene": SCENE_ARG}, ["node_path"], _remove_node),
		McpTool.create("reparent_node", scene, "Moves a node under another parent (with undo). Keeps the global transform unless keep_global_transform=false.",
			{"node_path": {"type": "string"}, "new_parent": {"type": "string"}, "keep_global_transform": {"type": "boolean"}, "scene": SCENE_ARG},
			["node_path", "new_parent"], _reparent_node),
		McpTool.create("rename_node", scene, "Renames a node (with undo).",
			{"node_path": {"type": "string"}, "new_name": {"type": "string"}, "scene": SCENE_ARG},
			["node_path", "new_name"], _rename_node),
		McpTool.create("connect_signal", scene,
			"Connects a signal persistently (saved in the scene, with undo). If the method does not exist in the target's script, it warns you: create it by editing the script.",
			{"from": {"type": "string"}, "signal": {"type": "string"}, "to": {"type": "string"}, "method": {"type": "string"}, "scene": SCENE_ARG},
			["from", "signal", "to", "method"], _connect_signal),
		McpTool.create("instantiate_scene", scene, "Instances a .tscn scene as a child of `parent` (with undo).",
			{"parent": {"type": "string"}, "scene_path": {"type": "string"}, "name": {"type": "string"}, "scene": SCENE_ARG},
			["parent", "scene_path"], _instantiate_scene),
		McpTool.create("open_scene", scene, "Opens a scene in the editor (or makes it the current one).",
			{"path": {"type": "string"}}, ["path"], _open_scene),
		McpTool.create("save_scene", scene, "Saves the current scene (or the given one, which must be open).",
			{"path": {"type": "string"}}, [], _save_scene),
		McpTool.create("create_scene", files, "Creates and saves a new .tscn with a root node. Does not open it: use open_scene.",
			{"path": {"type": "string"}, "root_type": {"type": "string"}, "root_name": {"type": "string"}},
			["path", "root_type", "root_name"], _create_scene),
		McpTool.create("attach_script", files,
			"Attaches a script to a node (with undo). If the file does not exist, creates it with `extends <node type>`.",
			{"node_path": {"type": "string"}, "script_path": {"type": "string"}, "scene": SCENE_ARG},
			["node_path", "script_path"], _attach_script),
	]


# --- tools ---------------------------------------------------------------------------------------

func _add_node(args: Dictionary) -> Dictionary:
	var root := _scene_root(args)
	if root == null:
		return _no_scene(args)
	var parent := SceneAccess.find_node(root, str(args.parent))
	if parent == null:
		return _missing(root, str(args.parent))
	var node_name := str(args.name).validate_node_name()
	if node_name.is_empty():
		return McpTool.error("`name` cannot be empty.")
	if parent.has_node(NodePath(node_name)):
		return McpTool.error("%s already has a child named %s." % [SceneAccess.relative_path(root, parent), node_name])
	var created := _instantiate_type(str(args.type))
	if created is String:
		return McpTool.error(created)
	var node: Node = created
	node.name = node_name
	var applied: PackedStringArray = []
	var properties: Dictionary = args.get("properties", {}) if args.get("properties") is Dictionary else {}
	for property: String in properties:
		var result := ValueCoercion.coerce(node, property, properties[property])
		if not result.ok:
			node.free()
			return McpTool.error(result.error)
		node.set(property, result.value)
		applied.append("%s=%s" % [property, SceneAccess.format_value(result.value)])
	var action := ACTION_PREFIX + "add %s" % node_name
	var undo_redo := EditorInterface.get_editor_undo_redo()
	undo_redo.create_action(action, UndoRedo.MERGE_DISABLE, root)
	undo_redo.add_do_method(parent, &"add_child", node, true)
	undo_redo.add_do_method(node, &"set_owner", root)
	undo_redo.add_do_reference(node)
	undo_redo.add_undo_method(parent, &"remove_child", node)
	undo_redo.commit_action()
	_select(node)
	_record("add_node", args, action, root)
	var text := "Created %s (%s) under %s." % [SceneAccess.relative_path(root, node), node.get_class(), SceneAccess.relative_path(root, parent)]
	if not applied.is_empty():
		text += " Properties: %s." % ", ".join(applied)
	return _done(text, action)


func _set_properties(args: Dictionary) -> Dictionary:
	var root := _scene_root(args)
	if root == null:
		return _no_scene(args)
	var node := SceneAccess.find_node(root, str(args.node_path))
	if node == null:
		return _missing(root, str(args.node_path))
	var properties: Dictionary = args.properties
	if properties.is_empty():
		return McpTool.error("`properties` is empty.")
	var changes: Array = []
	for property: String in properties:
		var result := ValueCoercion.coerce(node, property, properties[property])
		if not result.ok:
			return McpTool.error(result.error)
		changes.append([property, node.get(property), result.value])
	var action := ACTION_PREFIX + "set %s on %s" % [", ".join(PackedStringArray(properties.keys())), node.name]
	var undo_redo := EditorInterface.get_editor_undo_redo()
	undo_redo.create_action(action, UndoRedo.MERGE_DISABLE, root)
	for change: Array in changes:
		undo_redo.add_do_property(node, change[0], change[2])
		undo_redo.add_undo_property(node, change[0], change[1])
	undo_redo.commit_action()
	_record("set_properties", args, action, root)
	var lines: PackedStringArray = []
	for change: Array in changes:
		lines.append("%s: %s → %s" % [change[0], SceneAccess.format_value(change[1]), SceneAccess.format_value(node.get(change[0]))])
	return _done("%s:\n%s" % [SceneAccess.relative_path(root, node), "\n".join(lines)], action)


func _remove_node(args: Dictionary) -> Dictionary:
	var root := _scene_root(args)
	if root == null:
		return _no_scene(args)
	var node := SceneAccess.find_node(root, str(args.node_path))
	if node == null:
		return _missing(root, str(args.node_path))
	if node == root:
		return McpTool.error("Cannot delete the scene root.")
	var parent := node.get_parent()
	var owned := _owned_subtree(root, node)
	var action := ACTION_PREFIX + "delete %s" % node.name
	var path_text := SceneAccess.relative_path(root, node)
	var undo_redo := EditorInterface.get_editor_undo_redo()
	undo_redo.create_action(action, UndoRedo.MERGE_DISABLE, root)
	undo_redo.add_do_method(parent, &"remove_child", node)
	undo_redo.add_undo_method(parent, &"add_child", node, true)
	undo_redo.add_undo_method(parent, &"move_child", node, node.get_index())
	for owned_node: Node in owned:
		undo_redo.add_undo_method(owned_node, &"set_owner", root)
	undo_redo.add_undo_reference(node)
	undo_redo.commit_action()
	_record("remove_node", args, action, root)
	return _done("Deleted %s (and %d child nodes)." % [path_text, owned.size() - 1], action)


func _reparent_node(args: Dictionary) -> Dictionary:
	var root := _scene_root(args)
	if root == null:
		return _no_scene(args)
	var node := SceneAccess.find_node(root, str(args.node_path))
	if node == null:
		return _missing(root, str(args.node_path))
	var new_parent := SceneAccess.find_node(root, str(args.new_parent))
	if new_parent == null:
		return _missing(root, str(args.new_parent))
	if node == root:
		return McpTool.error("Cannot move the scene root.")
	if new_parent == node or node.is_ancestor_of(new_parent):
		return McpTool.error("Cannot move a node inside itself.")
	if new_parent.has_node(NodePath(String(node.name))) and new_parent != node.get_parent():
		return McpTool.error("%s already has a child named %s." % [SceneAccess.relative_path(root, new_parent), node.name])
	var keep: bool = args.get("keep_global_transform", true) != false
	var old_parent := node.get_parent()
	var old_index := node.get_index()
	var owned := _owned_subtree(root, node)
	var action := ACTION_PREFIX + "move %s to %s" % [node.name, new_parent.name]
	var undo_redo := EditorInterface.get_editor_undo_redo()
	undo_redo.create_action(action, UndoRedo.MERGE_DISABLE, root)
	undo_redo.add_do_method(node, &"reparent", new_parent, keep)
	for owned_node: Node in owned:
		undo_redo.add_do_method(owned_node, &"set_owner", root)
	undo_redo.add_undo_method(node, &"reparent", old_parent, keep)
	undo_redo.add_undo_method(old_parent, &"move_child", node, old_index)
	for owned_node: Node in owned:
		undo_redo.add_undo_method(owned_node, &"set_owner", root)
	undo_redo.commit_action()
	_record("reparent_node", args, action, root)
	return _done("Now %s." % SceneAccess.relative_path(root, node), action)


func _rename_node(args: Dictionary) -> Dictionary:
	var root := _scene_root(args)
	if root == null:
		return _no_scene(args)
	var node := SceneAccess.find_node(root, str(args.node_path))
	if node == null:
		return _missing(root, str(args.node_path))
	var new_name := str(args.new_name).validate_node_name()
	if new_name.is_empty():
		return McpTool.error("`new_name` cannot be empty.")
	if node != root and node.get_parent().has_node(NodePath(new_name)):
		return McpTool.error("There is already a sibling named %s." % new_name)
	var old_name := String(node.name)
	var action := ACTION_PREFIX + "rename %s to %s" % [old_name, new_name]
	var undo_redo := EditorInterface.get_editor_undo_redo()
	undo_redo.create_action(action, UndoRedo.MERGE_DISABLE, root)
	undo_redo.add_do_property(node, &"name", new_name)
	undo_redo.add_undo_property(node, &"name", old_name)
	undo_redo.commit_action()
	_record("rename_node", args, action, root)
	return _done("Renamed: %s." % SceneAccess.relative_path(root, node), action)


func _connect_signal(args: Dictionary) -> Dictionary:
	var root := _scene_root(args)
	if root == null:
		return _no_scene(args)
	var source := SceneAccess.find_node(root, str(args.from))
	if source == null:
		return _missing(root, str(args.from))
	var target := SceneAccess.find_node(root, str(args.to))
	if target == null:
		return _missing(root, str(args.to))
	var signal_name := str(args.signal)
	if not source.has_signal(signal_name):
		var names: PackedStringArray = []
		for info: Dictionary in source.get_signal_list():
			names.append(info.name)
		return McpTool.error("%s (%s) has no signal '%s'. Signals: %s." % [source.name, source.get_class(), signal_name, ", ".join(names)])
	var method := str(args.method)
	var callable := Callable(target, method)
	if source.is_connected(signal_name, callable):
		return McpTool.error("The signal is already connected.")
	var action := ACTION_PREFIX + "connect %s.%s → %s::%s" % [source.name, signal_name, target.name, method]
	var undo_redo := EditorInterface.get_editor_undo_redo()
	undo_redo.create_action(action, UndoRedo.MERGE_DISABLE, root)
	undo_redo.add_do_method(source, &"connect", signal_name, callable, CONNECT_PERSIST)
	undo_redo.add_undo_method(source, &"disconnect", signal_name, callable)
	undo_redo.commit_action()
	_record("connect_signal", args, action, root)
	var text := "Connected %s.%s → %s::%s (persistent)." % [SceneAccess.relative_path(root, source), signal_name, SceneAccess.relative_path(root, target), method]
	if not target.has_method(method):
		text += " Note: %s has no method %s; add it to its script." % [target.name, method]
	return _done(text, action)


func _instantiate_scene(args: Dictionary) -> Dictionary:
	var root := _scene_root(args)
	if root == null:
		return _no_scene(args)
	var parent := SceneAccess.find_node(root, str(args.parent))
	if parent == null:
		return _missing(root, str(args.parent))
	var scene_path := str(args.scene_path)
	if scene_path == root.scene_file_path:
		return McpTool.error("Cannot instance a scene inside itself.")
	if not ResourceLoader.exists(scene_path, "PackedScene"):
		return McpTool.error("The scene %s does not exist." % scene_path)
	var packed := load(scene_path) as PackedScene
	var instance := packed.instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE) if packed else null
	if instance == null:
		return McpTool.error("Could not instantiate %s." % scene_path)
	var wanted := str(args.get("name", "")).validate_node_name()
	if not wanted.is_empty():
		instance.name = wanted
	if parent.has_node(NodePath(String(instance.name))):
		var base := String(instance.name)
		var index := 2
		while parent.has_node(NodePath("%s%d" % [base, index])):
			index += 1
		instance.name = "%s%d" % [base, index]
	var action := ACTION_PREFIX + "instance %s" % scene_path.get_file()
	var undo_redo := EditorInterface.get_editor_undo_redo()
	undo_redo.create_action(action, UndoRedo.MERGE_DISABLE, root)
	undo_redo.add_do_method(parent, &"add_child", instance, true)
	undo_redo.add_do_method(instance, &"set_owner", root)
	undo_redo.add_do_reference(instance)
	undo_redo.add_undo_method(parent, &"remove_child", instance)
	undo_redo.commit_action()
	_select(instance)
	_record("instantiate_scene", args, action, root)
	return _done("Instanced %s as %s." % [scene_path, SceneAccess.relative_path(root, instance)], action)


func _open_scene(args: Dictionary) -> Dictionary:
	var path := str(args.path)
	if not ResourceLoader.exists(path, "PackedScene"):
		return McpTool.error("The scene %s does not exist." % path)
	EditorInterface.open_scene_from_path(path)
	var root := EditorInterface.get_edited_scene_root()
	if root == null or root.scene_file_path != path:
		return McpTool.error("The editor could not open %s (is it broken? try get_errors)." % path)
	return McpTool.text("Opened %s (root %s, %s)." % [path, root.name, root.get_class()])


func _save_scene(args: Dictionary) -> Dictionary:
	var path := McpTool.str_arg(args, "path")
	if not path.is_empty():
		if not path in EditorInterface.get_open_scenes():
			return McpTool.error("%s is not open. Open scenes: %s." % [path, ", ".join(EditorInterface.get_open_scenes())])
		EditorInterface.open_scene_from_path(path)
	var root := EditorInterface.get_edited_scene_root()
	if root == null:
		return McpTool.error("There is no open scene.")
	if root.scene_file_path.is_empty():
		return McpTool.error("The current scene was never saved: it has no path. Create one with create_scene.")
	var error := EditorInterface.save_scene()
	if error != OK:
		return McpTool.error("Could not save %s: %s." % [root.scene_file_path, error_string(error)])
	return McpTool.text("Saved %s." % root.scene_file_path)


func _create_scene(args: Dictionary) -> Dictionary:
	var path := str(args.path)
	if not path.begins_with("res://") or path.get_extension() not in ["tscn", "scn"]:
		return McpTool.error("`path` must be res://…tscn.")
	if FileAccess.file_exists(path):
		return McpTool.error("%s already exists: it is not overwritten. Open it with open_scene." % path)
	var created := _instantiate_type(str(args.root_type))
	if created is String:
		return McpTool.error(created)
	var root: Node = created
	root.name = str(args.root_name).validate_node_name()
	if root.name.is_empty():
		root.free()
		return McpTool.error("`root_name` cannot be empty.")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var packed := PackedScene.new()
	var error := packed.pack(root)
	if error == OK:
		error = ResourceSaver.save(packed, path)
	root.free()
	if error != OK:
		return McpTool.error("Could not save %s: %s." % [path, error_string(error)])
	EditorInterface.get_resource_filesystem().update_file(path)
	return McpTool.text("Created %s with root %s (%s). Open it with open_scene to edit it." % [path, args.root_name, args.root_type])


func _attach_script(args: Dictionary) -> Dictionary:
	var root := _scene_root(args)
	if root == null:
		return _no_scene(args)
	var node := SceneAccess.find_node(root, str(args.node_path))
	if node == null:
		return _missing(root, str(args.node_path))
	var script_path := str(args.script_path)
	if not script_path.begins_with("res://") or script_path.get_extension() != "gd":
		return McpTool.error("`script_path` must be res://…gd.")
	var created_file := false
	if not FileAccess.file_exists(script_path):
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(script_path.get_base_dir()))
		var file := FileAccess.open(script_path, FileAccess.WRITE)
		if file == null:
			return McpTool.error("Could not create %s: %s." % [script_path, error_string(FileAccess.get_open_error())])
		file.store_string("extends %s\n\n\nfunc _ready() -> void:\n\tpass\n" % node.get_class())
		file.close()
		EditorInterface.get_resource_filesystem().update_file(script_path)
		created_file = true
	var script := ResourceLoader.load(script_path, "", ResourceLoader.CACHE_MODE_REPLACE) as Script
	if script == null:
		return McpTool.error("Could not load %s (does it have errors? try validate_scripts)." % script_path)
	var base := script.get_instance_base_type()
	if not String(base).is_empty() and not node.is_class(base):
		return McpTool.error("%s extends %s and %s is %s: cannot attach it." % [script_path, base, node.name, node.get_class()])
	var action := ACTION_PREFIX + "attach %s to %s" % [script_path.get_file(), node.name]
	var undo_redo := EditorInterface.get_editor_undo_redo()
	undo_redo.create_action(action, UndoRedo.MERGE_DISABLE, root)
	undo_redo.add_do_property(node, &"script", script)
	undo_redo.add_undo_property(node, &"script", node.get_script())
	undo_redo.commit_action()
	_record("attach_script", args, action, root)
	return _done("%s%s attached to %s." % [script_path, " (created)" if created_file else "", SceneAccess.relative_path(root, node)], action)


# --- internos ------------------------------------------------------------------------------------

## La escena sobre la que se edita: la indicada en `scene` (se abre si hace falta) o la actual.
func _scene_root(args: Dictionary) -> Node:
	var scene := McpTool.str_arg(args, "scene")
	var root := EditorInterface.get_edited_scene_root()
	if scene.is_empty() or (root and root.scene_file_path == scene):
		return root
	if not ResourceLoader.exists(scene, "PackedScene"):
		return null
	EditorInterface.open_scene_from_path(scene)
	root = EditorInterface.get_edited_scene_root()
	return root if root and root.scene_file_path == scene else null


func _no_scene(args: Dictionary) -> Dictionary:
	var scene := McpTool.str_arg(args, "scene")
	if scene.is_empty():
		return McpTool.error("There is no open scene. Open one with open_scene or create it with create_scene.")
	return McpTool.error("Could not open %s." % scene)


func _missing(root: Node, node_path: String) -> Dictionary:
	var children: PackedStringArray = []
	for child: Node in SceneAccess.scene_children(root, root):
		children.append(String(child.name))
	return McpTool.error("There is no node '%s' in %s. Paths are relative to the root (\".\"); children of the root: %s. Use scene_tree." % [node_path, root.scene_file_path.get_file(), ", ".join(children)])


## Instancia una clase de Godot o un class_name del proyecto. Devuelve el Node o un mensaje.
static func _instantiate_type(type_name: String) -> Variant:
	if ClassDB.class_exists(type_name):
		if not ClassDB.is_parent_class(type_name, &"Node"):
			return "%s is not a Node." % type_name
		if not ClassDB.can_instantiate(type_name):
			return "%s is abstract: choose a subclass." % type_name
		return ClassDB.instantiate(type_name)
	for info: Dictionary in ProjectSettings.get_global_class_list():
		if info.get("class") == type_name:
			var script := load(str(info.path)) as Script
			if script == null or not script.can_instantiate():
				return "Could not instantiate the class_name %s (%s)." % [type_name, info.path]
			var instance: Variant = script.new()
			if not instance is Node:
				return "%s does not extend Node." % type_name
			return instance
	return "There is no class '%s' (neither as a Godot class nor as a project class_name)." % type_name


## El nodo y sus descendientes que pertenecen a la escena (para restaurar owners).
static func _owned_subtree(root: Node, node: Node) -> Array[Node]:
	var result: Array[Node] = [node]
	for child: Node in node.find_children("*", "", true, false):
		if child.owner == root:
			result.append(child)
	return result


func _select(node: Node) -> void:
	var selection := EditorInterface.get_selection()
	selection.clear()
	selection.add_node(node)


func _record(tool_name: String, args: Dictionary, action: String, root: Node) -> void:
	if on_action.is_valid():
		on_action.call(tool_name, args, EditorUndo.record(action, root))


static func _done(text: String, action: String) -> Dictionary:
	return McpTool.text("%s\nUndo step: «%s»." % [text, action])
