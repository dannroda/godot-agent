@tool
extends RefCounted
## Recursos `.tres` por el editor (m4-13): get_resource (grupo read), create_resource y
## set_resource_properties (grupo edit_files). Es lo que pide el diseño data-driven (valores
## ajustables en Resources) sin escribir `.tres` a mano, que el harness rechaza (D48).

const McpTool := preload("../mcp_tool.gd")
const SceneAccess := preload("scene_access.gd")
const ValueCoercion := preload("value_coercion.gd")
const PermissionPolicy := preload("../../session/permission_policy.gd")

const ACTION_PREFIX := "Agent: "
const MAX_DEPTH := 4
const PROPERTIES_HELP := "`properties` uses the Inspector names; vectors as [x, y], colors as \"#rrggbb\", other resources as res:// paths or inline as {\"type\": \"ClassName\", …properties}, typed arrays element by element."


func tools() -> Array:
	var files := PermissionPolicy.GROUP_EDIT_FILES
	return [
		McpTool.create("get_resource", PermissionPolicy.GROUP_READ,
			"Reads a resource file (.tres/.res): type, script, uid and every saved property that differs from the default, with its sub-resources.",
			{"path": {"type": "string"}}, ["path"], _get_resource),
		McpTool.create("create_resource", files,
			"Creates and saves a resource file (.tres): a Godot Resource class (StyleBoxFlat, LabelSettings, Curve, Gradient…) or a project class_name that extends Resource, with its properties. Never write a .tres by hand: the harness rejects it. Assign it to a node with set_properties using its res:// path. " + PROPERTIES_HELP,
			{"path": {"type": "string"}, "type": {"type": "string"}, "properties": {"type": "object"}},
			["path", "type"], _create_resource),
		McpTool.create("set_resource_properties", files,
			"Changes properties of a resource file and saves it (one undo step, Ctrl+Z in the editor). Scenes that use it see the change. " + PROPERTIES_HELP,
			{"path": {"type": "string"}, "properties": {"type": "object"}},
			["path", "properties"], _set_resource_properties),
	]


# --- tools ---------------------------------------------------------------------------------------

func _get_resource(args: Dictionary) -> Dictionary:
	var path := str(args.path)
	if not ResourceLoader.exists(path):
		return McpTool.error("The resource %s does not exist." % path)
	var resource := load(path)
	if resource == null:
		return McpTool.error("Could not load %s (broken? try get_errors)." % path)
	var lines: PackedStringArray = [_header(resource, path)]
	var id := ResourceLoader.get_resource_uid(path)
	if id != ResourceUID.INVALID_ID:
		lines.append("uid: %s" % ResourceUID.id_to_text(id))
	var properties := _describe(resource, 1)
	lines.append_array(properties if not properties.is_empty() else PackedStringArray(["  (every property has its default value)"]))
	return McpTool.text("\n".join(lines))


func _create_resource(args: Dictionary) -> Dictionary:
	var path := str(args.path)
	if not path.begins_with("res://") or path.get_extension() not in ["tres", "res"]:
		return McpTool.error("`path` must be res://….tres.")
	if FileAccess.file_exists(path):
		return McpTool.error("%s already exists: it is not overwritten. Change it with set_resource_properties." % path)
	var made: Variant = ValueCoercion.new_resource(str(args.type))
	if made is String:
		return McpTool.error(made)
	var resource: Resource = made
	var properties: Dictionary = args.get("properties") if args.get("properties") is Dictionary else {}
	for property: String in properties:
		var result := ValueCoercion.coerce(resource, property, properties[property])
		if not result.ok:
			return McpTool.error(result.error)
		resource.set(property, result.value)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var error := ResourceSaver.save(resource, path)
	if error != OK:
		return McpTool.error("Could not save %s: %s." % [path, error_string(error)])
	resource.take_over_path(path)
	EditorInterface.get_resource_filesystem().update_file(path)
	var lines: PackedStringArray = ["Created %s (%s)." % [path, args.type]]
	lines.append_array(_describe(resource, 1))
	return McpTool.text("\n".join(lines))


func _set_resource_properties(args: Dictionary) -> Dictionary:
	var path := str(args.path)
	if not path.begins_with("res://") or not ResourceLoader.exists(path):
		return McpTool.error("The resource %s does not exist. Create it with create_resource." % path)
	if path.get_extension() not in ["tres", "res"]:
		return McpTool.error("%s is not a .tres/.res resource file: scenes are edited with the scene tools, scripts with your file tools." % path)
	var resource := load(path)
	if resource == null:
		return McpTool.error("Could not load %s." % path)
	var properties: Dictionary = args.properties
	if properties.is_empty():
		return McpTool.error("`properties` is empty.")
	var changes: Array = []
	for property: String in properties:
		var result := ValueCoercion.coerce(resource, property, properties[property])
		if not result.ok:
			return McpTool.error(result.error)
		changes.append([property, resource.get(property), result.value])
	var action := ACTION_PREFIX + "set %s on %s" % [", ".join(PackedStringArray(properties.keys())), path.get_file()]
	var undo_redo := EditorInterface.get_editor_undo_redo()
	undo_redo.create_action(action, UndoRedo.MERGE_DISABLE, resource)
	for change: Array in changes:
		undo_redo.add_do_property(resource, change[0], change[2])
		undo_redo.add_undo_property(resource, change[0], change[1])
	undo_redo.add_do_method(ResourceSaver, &"save", resource, path)
	undo_redo.add_undo_method(ResourceSaver, &"save", resource, path)
	undo_redo.commit_action()
	EditorInterface.get_resource_filesystem().update_file(path)
	var lines: PackedStringArray = []
	for change: Array in changes:
		lines.append("%s: %s → %s" % [change[0], SceneAccess.format_value(change[1]), SceneAccess.format_value(resource.get(change[0]))])
	return McpTool.text("%s (saved):\n%s\nUndo step: «%s» (Ctrl+Z in the editor)." % [path, "\n".join(lines), action])


# --- formato -------------------------------------------------------------------------------------

static func _header(resource: Resource, path: String) -> String:
	var script := resource.get_script() as Script
	var type := resource.get_class()
	if script:
		var global := script.get_global_name()
		type = "%s (script %s)" % [global if not String(global).is_empty() else type, script.resource_path]
	return "%s: %s" % [path, type]


## Propiedades guardadas que difieren del default, con los sub-recursos anidados.
static func _describe(resource: Resource, depth: int) -> PackedStringArray:
	var lines: PackedStringArray = []
	var indent := "  ".repeat(depth)
	for info: Dictionary in resource.get_property_list():
		var name := str(info.name)
		if not int(info.usage) & PROPERTY_USAGE_STORAGE or name in ["script", "resource_local_to_scene", "resource_name", "resource_path"] or name.begins_with("metadata/_"):
			continue
		var value: Variant = resource.get(name)
		if SceneAccess._same(value, _default_value(resource, name)):
			continue
		if value is Resource and (value.resource_path.is_empty() or value.resource_path.contains("::")):
			lines.append("%s%s = <%s, inline>" % [indent, name, _type_name(value)])
			if depth < MAX_DEPTH:
				lines.append_array(_describe(value, depth + 1))
		elif value is Array and not value.is_empty() and value[0] is Resource:
			lines.append("%s%s = [%d items]" % [indent, name, value.size()])
			for i: int in value.size():
				var item: Variant = value[i]
				if item is Resource and (item.resource_path.is_empty() or item.resource_path.contains("::")) and depth < MAX_DEPTH:
					lines.append("%s  [%d] <%s, inline>" % [indent, i, _type_name(item)])
					lines.append_array(_describe(item, depth + 2))
				else:
					lines.append("%s  [%d] %s" % [indent, i, SceneAccess.format_value(item)])
		else:
			lines.append("%s%s = %s" % [indent, name, SceneAccess.format_value(value)])
	return lines


## Default de una propiedad: el del script (sin instanciarlo: en el editor un script sin @tool no
## se instancia) o el de la clase nativa.
static func _default_value(resource: Resource, name: String) -> Variant:
	var script := resource.get_script() as Script
	if script:
		for info: Dictionary in script.get_script_property_list():
			if info.name == name:
				var script_default: Variant = script.get_property_default_value(name)
				if script_default == null and script.can_instantiate():
					script_default = (script.new() as Object).get(name)  # fuera del editor no hay caché de defaults
				return script_default
	return ClassDB.class_get_property_default_value(resource.get_class(), name)


static func _type_name(resource: Resource) -> String:
	var script := resource.get_script() as Script
	if script and not String(script.get_global_name()).is_empty():
		return String(script.get_global_name())
	return resource.get_class()
