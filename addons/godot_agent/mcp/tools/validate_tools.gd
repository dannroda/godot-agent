@tool
extends RefCounted
## Validadores de solo lectura (m14-04, idea de Ziva): física (cuerpos sin forma, formas sueltas,
## capas y máscaras que no se cruzan) y TileMapLayers (sin TileSet, celdas que el TileSet no tiene,
## tiles sin colisión). El agente los corre después de tocar física o mapas para verificarse.

const McpTool := preload("../mcp_tool.gd")
const PermissionPolicy := preload("../../session/permission_policy.gd")
const SceneAccess := preload("scene_access.gd")

const SCENE_ARG := {"type": "string", "description": "res://…tscn path (default: the open scene)"}
const NODE_ARG := {"type": "string", "description": "Only this node and what is under it (NodePath from the scene root; default: the whole scene)"}
## Celdas inválidas que se nombran; las demás se cuentan.
const CELLS_SHOWN := 8


func tools() -> Array:
	var group := PermissionPolicy.GROUP_DIAGNOSTICS
	return [
		McpTool.create("validate_physics", group,
			"Checks the physics setup of a scene: bodies and areas without a collision shape, shapes with no shape resource or outside a body, and collision layers and masks that match nothing in the scene. Run it after adding or changing physics.",
			{"scene": SCENE_ARG, "node_path": NODE_ARG}, [], _validate_physics),
		McpTool.create("validate_tilemap", group,
			"Checks the TileMapLayers of a scene: missing TileSet, cells whose source or atlas tile the TileSet doesn't have, and placed tiles without collision when the TileSet has physics layers. Run it after painting or changing a map.",
			{"scene": SCENE_ARG, "node_path": NODE_ARG}, [], _validate_tilemap),
	]


func _validate_physics(args: Dictionary) -> Dictionary:
	return _run(args, physics_issues, "physics")


func _validate_tilemap(args: Dictionary) -> Dictionary:
	return _run(args, tilemap_issues, "TileMapLayer")


func _run(args: Dictionary, check: Callable, what: String) -> Dictionary:
	var resolved := SceneAccess.resolve(McpTool.str_arg(args, "scene"))
	if not resolved.error.is_empty():
		return McpTool.error(resolved.error)
	var node_path := McpTool.str_arg(args, "node_path")
	var start: Node = SceneAccess.find_node(resolved.root, node_path) if not node_path.is_empty() else resolved.root
	if start == null:
		resolved.release()
		return McpTool.error("No node at '%s' in %s." % [node_path, resolved.path])
	var report: Dictionary = check.call(start)
	resolved.release()
	var issues: PackedStringArray = report.issues
	var header := "%s · %s" % [resolved.path if not resolved.path.is_empty() else "(unsaved scene)", report.summary]
	if issues.is_empty():
		return McpTool.text("%s · no %s problems found." % [header, what])
	return McpTool.text("%s · %d problem%s:\n- %s" % [header, issues.size(), "" if issues.size() == 1 else "s", "\n- ".join(issues)])


# --- física ------------------------------------------------------------------------------------------

## `{issues: PackedStringArray, summary: String}` de los cuerpos, áreas y formas bajo `root`.
static func physics_issues(root: Node) -> Dictionary:
	var issues: PackedStringArray = []
	var objects: Array[Node] = []
	var shape_count := 0
	var tile_layers: Array[int] = []
	for node: Node in _all(root):
		if node is CollisionObject2D or node is CollisionObject3D:
			objects.append(node)
			if _shapes_of(node) == 0:
				issues.append("%s (%s) has no enabled CollisionShape or CollisionPolygon child with a shape: it collides with nothing." % [_path(root, node), node.get_class()])
		elif _is_shape_node(node):
			shape_count += 1
			if not (node.get_parent() is CollisionObject2D or node.get_parent() is CollisionObject3D):
				issues.append("%s is not a direct child of a body or area: it does nothing." % _path(root, node))
			elif not _has_shape(node):
				issues.append("%s has no shape (empty `shape` or `polygon`)." % _path(root, node))
		elif node is TileMapLayer and (node as TileMapLayer).tile_set and (node as TileMapLayer).collision_enabled:
			var tile_set := (node as TileMapLayer).tile_set
			for i in tile_set.get_physics_layers_count():
				tile_layers.append(tile_set.get_physics_layer_collision_layer(i))
	for object: Node in objects:
		var layer := int(object.get(&"collision_layer"))
		var mask := int(object.get(&"collision_mask"))
		var is_area := object is Area2D or object is Area3D
		if mask == 0 and (not is_area or bool(object.get(&"monitoring"))):
			issues.append("%s has collision_mask 0: %s." % [_path(root, object), "it detects nothing" if is_area else "it doesn't collide with anything (it falls or passes through everything)"])
		elif mask != 0 and objects.size() + tile_layers.size() > 1 and not _mask_matches(object, mask, objects, tile_layers):
			issues.append("%s's collision_mask (%s) matches no collision_layer in this scene: nothing here can touch it (fine if what it hits is spawned at runtime)." % [_path(root, object), _bits(mask)])
		if layer == 0 and not is_area:
			issues.append("%s has collision_layer 0: no other body or area can detect it." % _path(root, object))
	var summary := "%d bodies/areas, %d shapes" % [objects.size(), shape_count]
	return {"issues": issues, "summary": summary}


static func _shapes_of(object: Node) -> int:
	var count := 0
	for child: Node in object.get_children():
		if _is_shape_node(child) and _has_shape(child) and not bool(child.get(&"disabled")):
			count += 1
	return count


static func _is_shape_node(node: Node) -> bool:
	return node is CollisionShape2D or node is CollisionPolygon2D or node is CollisionShape3D or node is CollisionPolygon3D


static func _has_shape(node: Node) -> bool:
	if node is CollisionShape2D or node is CollisionShape3D:
		return node.get(&"shape") != null
	return not (node.get(&"polygon") as PackedVector2Array).is_empty()


static func _mask_matches(object: Node, mask: int, objects: Array[Node], tile_layers: Array[int]) -> bool:
	for other: Node in objects:
		if other != object and int(other.get(&"collision_layer")) & mask:
			return true
	return tile_layers.any(func(layer: int) -> bool: return layer & mask)


static func _bits(value: int) -> String:
	var bits: PackedStringArray = []
	for i in 32:
		if value & (1 << i):
			bits.append(str(i + 1))
	return "layer%s %s" % ["s" if bits.size() > 1 else "", ", ".join(bits)]


# --- TileMapLayer --------------------------------------------------------------------------------------

## `{issues: PackedStringArray, summary: String}` de los TileMapLayers bajo `root` (incluido él).
static func tilemap_issues(root: Node) -> Dictionary:
	var issues: PackedStringArray = []
	var layers := 0
	var cells := 0
	for node: Node in _all(root):
		if not node is TileMapLayer:
			continue
		var layer := node as TileMapLayer
		layers += 1
		var used := layer.get_used_cells()
		cells += used.size()
		var name := _path(root, layer)
		if layer.tile_set == null:
			if not used.is_empty():
				issues.append("%s has %d cells but no TileSet: nothing is drawn." % [name, used.size()])
			else:
				issues.append("%s has no TileSet." % name)
			continue
		var tile_set := layer.tile_set
		var invalid: PackedStringArray = []
		var invalid_count := 0
		var with_collision := 0
		for coords: Vector2i in used:
			var source_id := layer.get_cell_source_id(coords)
			var atlas_coords := layer.get_cell_atlas_coords(coords)
			var source := tile_set.get_source(source_id) if tile_set.has_source(source_id) else null
			var atlas := source as TileSetAtlasSource
			if source == null or (atlas and not atlas.has_tile(atlas_coords)):
				invalid_count += 1
				if invalid.size() < CELLS_SHOWN:
					invalid.append("(%d, %d)" % [coords.x, coords.y])
				continue
			if atlas and tile_set.get_physics_layers_count() > 0:
				var data := layer.get_cell_tile_data(coords)
				if data and _tile_has_collision(data, tile_set.get_physics_layers_count()):
					with_collision += 1
		if invalid_count > 0:
			issues.append("%s: %d cells use a source or atlas tile its TileSet doesn't have (they draw nothing): %s%s." % [name, invalid_count, ", ".join(invalid), "…" if invalid_count > invalid.size() else ""])
		if tile_set.get_physics_layers_count() > 0:
			if not layer.collision_enabled:
				issues.append("%s has collision_enabled off although its TileSet has physics layers: its tiles don't collide." % name)
			elif with_collision == 0 and used.size() > invalid_count:
				issues.append("%s: none of its placed tiles has a collision polygon although the TileSet has physics layers (tileset_add_atlas with collision=true adds them)." % name)
	return {"issues": issues, "summary": "%d TileMapLayer%s, %d cells" % [layers, "" if layers == 1 else "s", cells]}


static func _tile_has_collision(data: TileData, physics_layers: int) -> bool:
	for i in physics_layers:
		if data.get_collision_polygons_count(i) > 0:
			return true
	return false


# --- utilidades ----------------------------------------------------------------------------------------

## `root` y todo lo que tiene debajo, también lo de las escenas instanciadas (sus formas cuentan).
static func _all(root: Node) -> Array[Node]:
	var result: Array[Node] = [root]
	for node: Node in root.find_children("*", "", true, false):
		result.append(node)
	return result


static func _path(root: Node, node: Node) -> String:
	return "." if node == root else str(root.get_path_to(node))
