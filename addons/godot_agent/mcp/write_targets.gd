@tool
extends RefCounted
## Lo que escribe una tool godot.* (m11-39), para los modos del proyecto que limitan archivos: las
## piezas con que cada tool arma su write_targets. Ver McpTool.write_targets.

const SceneAccess := preload("tools/scene_access.gd")


## La escena que edita una tool con `scene` (vacío: la abierta en el editor). Sin escena abierta, o una
## escena nueva sin guardar, nada: la tool falla o no escribe disco (guardarla pasa por save_scene).
static func scene(args: Dictionary) -> PackedStringArray:
	var path := str(args.get("scene", "")).strip_edges()
	if path.is_empty():
		path = edited_scene()
	return PackedStringArray([path]) if not path.is_empty() else PackedStringArray()


static func edited_scene() -> String:
	if not Engine.is_editor_hint() or not ClassDB.class_exists(&"EditorInterface"):
		return ""
	var root := EditorInterface.get_edited_scene_root()
	return root.scene_file_path if root else ""


## Los valores de `keys` que son rutas (las listas también).
static func keys(args: Dictionary, names: PackedStringArray) -> PackedStringArray:
	var result: PackedStringArray = []
	for name: String in names:
		var values: Array = args[name] if args.get(name) is Array else [args.get(name)]
		for value: Variant in values:
			if value is String and not str(value).strip_edges().is_empty():
				result.append(str(value).strip_edges())
	return result


## Una tool que no escribe nada del proyecto aunque su grupo escriba (abrir una escena).
static func nothing(_args: Dictionary) -> PackedStringArray:
	return PackedStringArray()


## Las escrituras de project.godot.
static func project_settings(_args: Dictionary) -> PackedStringArray:
	return PackedStringArray(["res://project.godot"])


## El archivo propio (.tres, .res) de un recurso, o "" si está dentro de una escena.
static func resource_file(resource: Resource) -> String:
	if resource == null or resource.resource_path.is_empty() or resource.resource_path.contains("::"):
		return ""
	return resource.resource_path


## La escena de la tool más el archivo propio del recurso que edita en el nodo `args.node_path`
## (`resource_of(node, args) -> Resource` o una lista): un TileSet, SpriteFrames o AnimationLibrary en su .tres se
## guarda aparte de la escena.
static func scene_and_resource(args: Dictionary, resource_of: Callable) -> PackedStringArray:
	var result := scene(args)
	if result.is_empty() or not Engine.is_editor_hint():
		return result
	var resolved := SceneAccess.resolve(str(args.get("scene", "")).strip_edges())
	if resolved.root:
		var node := SceneAccess.find_node(resolved.root, str(args.get("node_path", "")))
		var resources: Variant = resource_of.call(node, args) if node else null
		for resource: Variant in (resources if resources is Array else [resources]):
			var file := resource_file(resource as Resource) if resource is Resource else ""
			if not file.is_empty() and not file in result:
				result.append(file)
	resolved.release()
	return result


## Pone write_targets a las tools de `tools` que están en `targets` (nombre -> Callable(args)).
static func declare(tools: Array, targets: Dictionary) -> Array:
	for tool: Variant in tools:
		if targets.has(tool.name):
			tool.write_targets = targets[tool.name]
	return tools
