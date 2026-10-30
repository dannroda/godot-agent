extends RefCounted
## Qué es qué en el juego en ejecución: el jugador, sus números de movimiento y la búsqueda de nodos
## (m15-07, m15-11, m15-14). Lo usan el probe, los detectores y el kit de game_script.
## Ideas de lib/world.gd de Autopilot (ramenvr/autopilot, Apache 2.0).

const FIND_LIMIT := 50
const FIND_MAX := 500


## El jugador: el cuerpo del que cuelga la cámara actual, si no el primero del grupo "player", si no
## el primer CharacterBody de la escena. null en un menú.
static func player(tree: SceneTree) -> Node:
	var scene := tree.current_scene
	if scene == null:
		return null
	var camera: Node = scene.get_viewport().get_camera_3d()
	if camera == null:
		camera = scene.get_viewport().get_camera_2d()
	while camera != null and camera != scene.get_parent():
		if camera is PhysicsBody3D or camera is PhysicsBody2D:
			return camera
		camera = camera.get_parent()
	for group: StringName in [&"player", &"Player"]:
		var found := tree.get_first_node_in_group(group)
		if found:
			return found
	for type: String in ["CharacterBody3D", "CharacterBody2D"]:
		var bodies := scene.find_children("*", type, true, false)
		if not bodies.is_empty():
			return bodies[0]
	return null


## Los números con que se mueve el jugador, en sus unidades (metros o píxeles): velocidad, salto,
## gravedad y hasta dónde llega un salto (v²/2g). null en lo que no se encuentra; `sources` dice de
## qué variable salió cada uno.
static func movement(tree: SceneTree) -> Dictionary:
	var body := player(tree)
	if body == null:
		return {"error": "There is no player here (a menu?)."}
	var is_2d: bool = body is Node2D
	var speed := _script_number(body, "(^|_)(walk_|move_|run_|max_)?speed$")
	var jump := _script_number(body, "jump_?(velocity|speed|force|impulse|strength)$")
	var gravity := _script_number(body, "^_?gravity$")
	var setting := "physics/2d/default_gravity" if is_2d else "physics/3d/default_gravity"
	var g: float = absf(gravity[0]) if gravity[0] != null else float(ProjectSettings.get_setting(setting, 0.0))
	var result := {
		"player": str(body.get_path()), "walk_speed": speed[0], "jump_speed": absf(jump[0]) if jump[0] != null else null, "gravity": g,
		"sources": {"walk_speed": speed[1], "jump_speed": jump[1], "gravity": gravity[1] if gravity[0] != null else setting},
		"jump_height": null,
	}
	if jump[0] != null and g > 0.0:
		result.jump_height = pow(absf(jump[0]), 2.0) / (2.0 * g)
	return result


## El número que el script del nodo guarda con un nombre que coincide (variables, después constantes):
## [valor, nombre] o [null, ""].
static func _script_number(node: Node, pattern: String) -> Array:
	var script := node.get_script() as Script
	if script == null:
		return [null, ""]
	var regex := RegEx.create_from_string("(?i)" + pattern)
	for info: Dictionary in script.get_script_property_list():
		if int(info.usage) & PROPERTY_USAGE_SCRIPT_VARIABLE and regex.search(info.name):
			var value: Variant = node.get(info.name)
			if value is float or value is int:
				return [float(value), str(info.name)]
	var constants := script.get_script_constant_map()
	for name: String in constants:
		if regex.search(name) and (constants[name] is float or constants[name] is int):
			return [float(constants[name]), name]
	return [null, ""]


## Nodos del juego por clase (de Godot o class_name, con subclases), `group:<nombre>` o parte del
## nombre. Sin filtro, las cosas de la escena: hijos directos, cuerpos y áreas. Rutas, a lo sumo `limit`.
static func find(tree: SceneTree, params: Dictionary, skip: Node) -> Array:
	var type := str(params.get("class", ""))
	var part := str(params.get("name", "")).to_lower()
	var limit := clampi(int(params.get("limit", FIND_LIMIT)), 1, FIND_MAX)
	var found: Array = []
	var stack: Array[Node] = [tree.current_scene if tree.current_scene else tree.root]
	while not stack.is_empty() and found.size() < limit:
		var node: Node = stack.pop_back()
		var children := node.get_children()
		children.reverse()
		for child: Node in children:
			if child != skip:
				stack.append(child)
		if node == tree.current_scene:
			continue
		if not type.is_empty() and not _matches(node, type):
			continue
		if not part.is_empty() and not str(node.name).to_lower().contains(part):
			continue
		if type.is_empty() and part.is_empty() and not (node.get_parent() == tree.current_scene or node is CollisionObject3D or node is CollisionObject2D):
			continue
		found.append(node)
	return found


static func _matches(node: Node, type: String) -> bool:
	if type.begins_with("group:"):
		return node.is_in_group(type.trim_prefix("group:"))
	if node.is_class(type):
		return true
	var script := node.get_script() as Script
	while script:
		if script.get_global_name() == type or script.resource_path.get_file().get_basename() == type:
			return true
		script = script.get_base_script()
	return false
