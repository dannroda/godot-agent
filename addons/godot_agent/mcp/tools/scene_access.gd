@tool
extends RefCounted
## Acceso a escenas y nodos para las tools `godot.*`: resuelve la escena pedida (la abierta o un
## .tscn del disco), busca nodos por NodePath relativo a la raíz y describe propiedades de forma
## compacta (solo las que difieren del default).

const VALUE_MAX_CHARS := 120
## Propiedades que no aportan en el árbol (se ven por otros campos).
const SKIPPED_PROPERTIES: PackedStringArray = ["script", "owner", "scene_file_path", "name"]


## Escena resuelta. Si `temporary`, `root` se instanció del disco y hay que liberarla con `release()`.
class Resolved:
	extends RefCounted
	var root: Node
	var path: String = ""
	var temporary: bool = false
	var error: String = ""

	func release() -> void:
		if temporary and is_instance_valid(root):
			root.free()
		root = null


## `scene` vacío: la escena abierta en el editor. Si es la abierta, se usa la del editor (con los
## cambios sin guardar); si no, se instancia del disco.
static func resolve(scene: String) -> Resolved:
	var resolved := Resolved.new()
	var edited := EditorInterface.get_edited_scene_root()
	if scene.is_empty():
		if edited == null:
			resolved.error = "There is no scene open in the editor. Pass `scene` with a res://…tscn path."
			return resolved
		resolved.root = edited
		resolved.path = edited.scene_file_path
		return resolved
	if not scene.begins_with("res://"):
		resolved.error = "`scene` must be a res:// path (got '%s')." % scene
		return resolved
	resolved.path = scene
	if edited and edited.scene_file_path == scene:
		resolved.root = edited
		return resolved
	if not ResourceLoader.exists(scene, "PackedScene"):
		resolved.error = "The scene %s does not exist." % scene
		return resolved
	var packed := ResourceLoader.load(scene, "PackedScene") as PackedScene
	if packed == null:
		resolved.error = "Could not load %s (is it broken? try get_errors)." % scene
		return resolved
	resolved.root = packed.instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE)
	resolved.temporary = true
	if resolved.root == null:
		resolved.error = "Could not instantiate %s." % scene
	return resolved


## NodePath relativo a la raíz ("." o "" es la raíz; se tolera el nombre de la raíz al principio).
static func find_node(root: Node, node_path: String) -> Node:
	var path := node_path.strip_edges().trim_prefix("/")
	if path.is_empty() or path == ".":
		return root
	if path == String(root.name):
		return root
	if path.begins_with(String(root.name) + "/") and not root.has_node(NodePath(path)):
		path = path.substr(String(root.name).length() + 1)
	return root.get_node_or_null(NodePath(path))


static func relative_path(root: Node, node: Node) -> String:
	return "." if node == root else String(root.get_path_to(node))


## Hijos que pertenecen a la escena (no los internos de una escena instanciada).
static func scene_children(root: Node, node: Node) -> Array[Node]:
	var result: Array[Node] = []
	for child: Node in node.get_children():
		if child.owner == root:
			result.append(child)
	return result


## Propiedades guardables que difieren del default de su clase o script: name -> texto.
static func changed_properties(node: Node, max_chars: int = VALUE_MAX_CHARS) -> Dictionary:
	var result: Dictionary = {}
	var script := node.get_script() as Script
	for property: Dictionary in node.get_property_list():
		var prop_name: String = property.name
		if not property.usage & PROPERTY_USAGE_STORAGE or prop_name in SKIPPED_PROPERTIES:
			continue
		if prop_name.begins_with("metadata/_") or prop_name.begins_with("_"):
			continue
		var value: Variant = node.get(prop_name)
		var default_value: Variant = _default_value(node, script, prop_name)
		if _same(value, default_value):
			continue
		result[prop_name] = format_value(value, max_chars)
	return result


static func _default_value(node: Node, script: Script, prop_name: String) -> Variant:
	if script:
		var script_default: Variant = script.get_property_default_value(prop_name)
		if script_default != null:
			return script_default
	return ClassDB.class_get_property_default_value(node.get_class(), prop_name)


static func _same(a: Variant, b: Variant) -> bool:
	if typeof(a) != typeof(b):
		# null vs objeto vacío, int vs float del default…
		if (a is int or a is float) and (b is int or b is float):
			return is_equal_approx(float(a), float(b))
		return a == null and b == null
	if a is float:
		return is_equal_approx(a, b)
	return a == b


## Valor compacto: recursos por ruta, objetos por tipo, el resto con var_to_str recortado.
static func format_value(value: Variant, max_chars: int = VALUE_MAX_CHARS) -> String:
	var text := ""
	if value is Resource:
		var resource: Resource = value
		if resource.resource_path.is_empty() or resource.resource_path.contains("::"):
			text = "<%s>" % resource.get_class()
		else:
			text = resource.resource_path
	elif value is Object:
		text = "<%s>" % (value as Object).get_class() if is_instance_valid(value) else "<freed>"
	elif value is String or value is StringName:
		text = JSON.stringify(str(value))
	elif value is float:
		text = str(snappedf(value, 0.0001))
	else:
		text = var_to_str(value).replace("\n", " ")
	if text.length() > max_chars:
		text = text.left(max_chars) + "…"
	return text


## Conexiones persistentes (las que se guardan en la escena) que salen de `node`.
static func persistent_connections(root: Node, node: Node) -> PackedStringArray:
	var lines: PackedStringArray = []
	for signal_info: Dictionary in node.get_signal_list():
		for connection: Dictionary in node.get_signal_connection_list(signal_info.name):
			if not int(connection.get("flags", 0)) & CONNECT_PERSIST:
				continue
			var callable: Callable = connection.callable
			var target := callable.get_object() as Node
			var target_text := relative_path(root, target) if target and (target == root or root.is_ancestor_of(target)) else str(callable.get_object())
			lines.append("%s → %s::%s" % [signal_info.name, target_text, callable.get_method()])
	return lines
