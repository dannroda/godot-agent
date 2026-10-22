@tool
extends RefCounted
## Tools de tilemaps (m4-11): tilemap_get (grupo read) y tileset_add_atlas, tileset_add_scenes,
## tilemap_set_cells, tilemap_paint_terrain y tilemap_clear (grupo edit_scene), sobre nodos
## TileMapLayer. `tile_map_data` no se puede escribir a mano: sin estas tools el agente armaba los
## niveles desde código. Cada cambio es un paso de deshacer.
## La capa se crea con add_node/add_nodes (type TileMapLayer, tile_set inline {"type": "TileSet",
## "tile_size": [16, 16]} o una ruta .tres).

const McpTool := preload("../mcp_tool.gd")
const SceneAccess := preload("scene_access.gd")
const EditorUndo := preload("../../editor/editor_undo.gd")
const PermissionPolicy := preload("../../session/permission_policy.gd")

const ACTION_PREFIX := "Agent: "
const MAX_CELLS := 20000
const MAP_MAX_WIDTH := 100
const MAP_MAX_HEIGHT := 60
const LEGEND := "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789#$%&*+=?@"
const SCENE_ARG := {"type": "string", "description": "res://…tscn scene; opened if it is not the current one (default: the open one)"}
const NODE_ARG := {"type": "string", "description": "NodePath of the TileMapLayer"}
const CELLS_ARG := {"type": "array", "description": "Cells as [x, y], or {\"x\", \"y\", \"atlas\"?: [ax, ay], \"source\"?, \"alt\"?} to vary the tile per cell"}
const RECT_ARG := {"type": "array", "description": "[x, y, width, height] in cells: every cell of the rectangle"}

## Callable(tool_name: String, args: Dictionary, undo_info: Dictionary): cada acción commiteada.
var on_action: Callable


func tools() -> Array:
	var scene := PermissionPolicy.GROUP_EDIT_SCENE
	return [
		McpTool.create("tilemap_get", PermissionPolicy.GROUP_READ,
			"Reads a TileMapLayer: its TileSet (sources with their tiles, physics layers, terrain sets) and an ASCII map of the cells with a legend. Use `rect` for big maps.",
			{"node_path": NODE_ARG, "rect": RECT_ARG, "scene": SCENE_ARG}, ["node_path"], _tilemap_get),
		McpTool.create("tileset_add_atlas", scene,
			"Adds a texture as an atlas source to the TileSet of a TileMapLayer (with undo). Creates a tile for every grid cell that is not fully transparent. `collision`=true gives each tile a full-square collision shape (a physics layer is added if there is none).",
			{
				"node_path": NODE_ARG, "texture": {"type": "string", "description": "res:// image"},
				"tile_size": {"type": "array", "description": "[w, h] in pixels (default: the TileSet's tile_size)"},
				"separation": {"type": "array"}, "margins": {"type": "array"},
				"collision": {"type": "boolean"}, "source_id": {"type": "integer"}, "scene": SCENE_ARG,
			}, ["node_path", "texture"], _tileset_add_atlas),
		McpTool.create("tileset_add_scenes", scene,
			"Adds a scenes-collection source to the TileSet of a TileMapLayer (with undo): each scene becomes a tile (atlas [0, 0], alternative = its index) that is instanced in the cells where it is placed.",
			{"node_path": NODE_ARG, "scenes": {"type": "array", "description": "res://…tscn paths"}, "source_id": {"type": "integer"}, "scene": SCENE_ARG},
			["node_path", "scenes"], _tileset_add_scenes),
		McpTool.create("tilemap_set_cells", scene,
			"Places tiles on a TileMapLayer in one undo step: a list of cells and/or a filled rectangle, with `source_id` (default: the first source), `atlas` [x, y] (default [0, 0]) and `alternative`. `erase`=true empties them instead.",
			{
				"node_path": NODE_ARG, "cells": CELLS_ARG, "rect": RECT_ARG,
				"source_id": {"type": "integer"}, "atlas": {"type": "array"}, "alternative": {"type": "integer"},
				"erase": {"type": "boolean"}, "scene": SCENE_ARG,
			}, ["node_path"], _tilemap_set_cells),
		McpTool.create("tilemap_paint_terrain", scene,
			"Paints cells with a terrain of the TileSet (autotiling, with undo): the right tiles are chosen so edges connect. `terrain` is its index or name. `mode`: \"connect\" (an area, default) or \"path\" (cells in order, like a road).",
			{
				"node_path": NODE_ARG, "cells": CELLS_ARG, "rect": RECT_ARG,
				"terrain_set": {"type": "integer"}, "terrain": {}, "mode": {"type": "string", "enum": ["connect", "path"]},
				"scene": SCENE_ARG,
			}, ["node_path", "terrain"], _tilemap_paint_terrain),
		McpTool.create("tilemap_clear", scene, "Empties every cell of a TileMapLayer (with undo).",
			{"node_path": NODE_ARG, "scene": SCENE_ARG}, ["node_path"], _tilemap_clear),
	]


# --- tools ---------------------------------------------------------------------------------------

func _tilemap_get(args: Dictionary) -> Dictionary:
	var found := _layer(args)
	if found.has("error"):
		return McpTool.error(found.error)
	var layer: TileMapLayer = found.layer
	var root: Node = found.root
	var lines: PackedStringArray = []
	var used := layer.get_used_rect()
	var tile_set := layer.tile_set
	var tile_set_text := "none"
	if tile_set:
		tile_set_text = "%s, tile %dx%d" % ["inline" if tile_set.resource_path.is_empty() or tile_set.resource_path.contains("::") else tile_set.resource_path, tile_set.tile_size.x, tile_set.tile_size.y]
	lines.append("TileMapLayer %s · tile_set: %s · %d cells%s" % [SceneAccess.relative_path(root, layer), tile_set_text, layer.get_used_cells().size(),
		", used rect x=%d y=%d %dx%d" % [used.position.x, used.position.y, used.size.x, used.size.y] if used.has_area() else ""])
	if tile_set == null:
		lines.append("No TileSet: set one with set_properties {\"tile_set\": {\"type\": \"TileSet\", \"tile_size\": [16, 16]}}, then tileset_add_atlas.")
		return McpTool.text("\n".join(lines))
	lines.append_array(_tileset_lines(tile_set))
	var rect := used
	if args.get("rect") is Array:
		var parsed: Variant = _rect(args.rect)
		if parsed is String:
			return McpTool.error(parsed)
		rect = parsed
	if not rect.has_area():
		lines.append("Map: empty.")
		return McpTool.text("\n".join(lines))
	if rect.size.x > MAP_MAX_WIDTH or rect.size.y > MAP_MAX_HEIGHT:
		lines.append("Map: %dx%d is too big to draw; pass `rect` (at most %dx%d)." % [rect.size.x, rect.size.y, MAP_MAX_WIDTH, MAP_MAX_HEIGHT])
		return McpTool.text("\n".join(lines))
	var legend := {}
	var rows: PackedStringArray = []
	for y: int in range(rect.position.y, rect.end.y):
		var row := ""
		for x: int in range(rect.position.x, rect.end.x):
			var cell := Vector2i(x, y)
			var source := layer.get_cell_source_id(cell)
			if source == -1:
				row += "."
				continue
			var key := "%d:(%d,%d)%s" % [source, layer.get_cell_atlas_coords(cell).x, layer.get_cell_atlas_coords(cell).y, "" if layer.get_cell_alternative_tile(cell) == 0 else " alt %d" % layer.get_cell_alternative_tile(cell)]
			if not legend.has(key):
				legend[key] = LEGEND[legend.size()] if legend.size() < LEGEND.length() else "?"
			row += legend[key]
		rows.append("%4d %s" % [y, row])
	lines.append("Map, x=%d..%d (left to right), y=%d..%d (top to bottom), '.' = empty:" % [rect.position.x, rect.end.x - 1, rect.position.y, rect.end.y - 1])
	lines.append_array(rows)
	var keys: PackedStringArray = []
	for key: String in legend:
		keys.append("%s = %s" % [legend[key], key])
	lines.append("Legend (source:(atlas x,y)): %s" % ", ".join(keys))
	return McpTool.text("\n".join(lines))


func _tileset_add_atlas(args: Dictionary) -> Dictionary:
	var found := _layer(args)
	if found.has("error"):
		return McpTool.error(found.error)
	var layer: TileMapLayer = found.layer
	var root: Node = found.root
	if layer.tile_set == null:
		return McpTool.error("%s has no TileSet: set one first with set_properties {\"tile_set\": {\"type\": \"TileSet\", \"tile_size\": [16, 16]}}." % layer.name)
	var tile_set := layer.tile_set
	var texture := load(str(args.texture)) as Texture2D if ResourceLoader.exists(str(args.texture)) else null
	if texture == null:
		return McpTool.error("%s is not a texture of the project." % args.texture)
	var size := tile_set.tile_size
	for key: String in ["tile_size", "separation", "margins"]:
		if args.has(key) and not _vector(args[key]) is Vector2i:
			return McpTool.error("`%s` must be [x, y] in pixels." % key)
	if args.has("tile_size"):
		size = _vector(args.tile_size)
	var source := TileSetAtlasSource.new()
	source.texture = texture
	source.texture_region_size = size
	if args.has("separation"):
		source.separation = _vector(args.separation)
	if args.has("margins"):
		source.margins = _vector(args.margins)
	var grid := source.get_atlas_grid_size()
	if grid.x <= 0 or grid.y <= 0:
		return McpTool.error("The texture (%dx%d) does not fit one %dx%d tile." % [texture.get_width(), texture.get_height(), size.x, size.y])
	var source_id := McpTool.int_arg(args, "source_id", tile_set.get_next_source_id())
	if tile_set.has_source(source_id):
		return McpTool.error("The TileSet already has a source %d." % source_id)
	var image := texture.get_image()
	if image and image.is_compressed():
		image.decompress()
	var added_physics := false
	var collision: bool = args.get("collision") == true
	var physics_before := tile_set.get_physics_layers_count()
	tile_set.add_source(source, source_id)
	if collision and physics_before == 0:
		tile_set.add_physics_layer()
		added_physics = true
	var created := 0
	for y: int in grid.y:
		for x: int in grid.x:
			var coords := Vector2i(x, y)
			var region := source.get_tile_texture_region(coords) if source.has_tile(coords) else Rect2i(source.margins + coords * (size + source.separation), size)
			if image and image.get_region(region).is_invisible():
				continue
			source.create_tile(coords)
			created += 1
			if collision:
				var data := source.get_tile_data(coords, 0)
				var half := Vector2(size) / 2.0
				data.add_collision_polygon(0)
				data.set_collision_polygon_points(0, 0, PackedVector2Array([-half, Vector2(half.x, -half.y), half, Vector2(-half.x, half.y)]))
	var action := ACTION_PREFIX + "add atlas %s to %s" % [str(args.texture).get_file(), layer.name]
	var undo_redo := EditorInterface.get_editor_undo_redo()
	undo_redo.create_action(action, UndoRedo.MERGE_DISABLE, root)
	if added_physics:
		undo_redo.add_do_method(tile_set, &"add_physics_layer")
	undo_redo.add_do_method(tile_set, &"add_source", source, source_id)
	undo_redo.add_do_reference(source)
	undo_redo.add_undo_method(tile_set, &"remove_source", source_id)
	if added_physics:
		undo_redo.add_undo_method(tile_set, &"remove_physics_layer", 0)
	_save_tileset_steps(undo_redo, tile_set)
	undo_redo.commit_action(false)
	_save_tileset(tile_set)
	_record("tileset_add_atlas", args, action, root)
	return _done("Added source %d: %s, tiles %dx%d, grid %dx%d, %d tiles created%s." % [source_id, args.texture, size.x, size.y, grid.x, grid.y, created, ", with full-square collision" if collision else ""], action)


func _tileset_add_scenes(args: Dictionary) -> Dictionary:
	var found := _layer(args)
	if found.has("error"):
		return McpTool.error(found.error)
	var layer: TileMapLayer = found.layer
	var root: Node = found.root
	if layer.tile_set == null:
		return McpTool.error("%s has no TileSet: set one first." % layer.name)
	var tile_set := layer.tile_set
	var source := TileSetScenesCollectionSource.new()
	var lines: PackedStringArray = []
	for path: Variant in args.scenes:
		if not ResourceLoader.exists(str(path), "PackedScene"):
			return McpTool.error("The scene %s does not exist." % path)
		var id := source.create_scene_tile(load(str(path)))
		lines.append("alternative %d = %s" % [id, path])
	var source_id := McpTool.int_arg(args, "source_id", tile_set.get_next_source_id())
	if tile_set.has_source(source_id):
		return McpTool.error("The TileSet already has a source %d." % source_id)
	var action := ACTION_PREFIX + "add scene tiles to %s" % layer.name
	var undo_redo := EditorInterface.get_editor_undo_redo()
	undo_redo.create_action(action, UndoRedo.MERGE_DISABLE, root)
	undo_redo.add_do_method(tile_set, &"add_source", source, source_id)
	undo_redo.add_do_reference(source)
	undo_redo.add_undo_method(tile_set, &"remove_source", source_id)
	_save_tileset_steps(undo_redo, tile_set)
	undo_redo.commit_action()
	_record("tileset_add_scenes", args, action, root)
	return _done("Added scenes source %d (place with tilemap_set_cells source_id=%d, atlas [0, 0], alternative):\n%s" % [source_id, source_id, "\n".join(lines)], action)


func _tilemap_set_cells(args: Dictionary) -> Dictionary:
	var found := _layer(args)
	if found.has("error"):
		return McpTool.error(found.error)
	var layer: TileMapLayer = found.layer
	var cells: Variant = _cells(args)
	if cells is String:
		return McpTool.error(cells)
	var erase: bool = args.get("erase") == true
	var defaults := {"source": -1, "atlas": Vector2i.ZERO, "alt": McpTool.int_arg(args, "alternative", 0)}
	if not erase:
		if layer.tile_set == null or layer.tile_set.get_source_count() == 0:
			return McpTool.error("%s has no tile sources: add one with tileset_add_atlas." % layer.name)
		defaults.source = McpTool.int_arg(args, "source_id", layer.tile_set.get_source_id(0))
		if args.has("atlas"):
			if not _vector(args.atlas) is Vector2i:
				return McpTool.error("`atlas` must be [x, y].")
			defaults.atlas = _vector(args.atlas)
	var placements: Array = []
	for cell: Dictionary in cells:
		var source: int = -1 if erase else int(cell.get("source", defaults.source))
		var atlas: Vector2i = cell.get("atlas", defaults.atlas)
		var alt: int = int(cell.get("alt", defaults.alt))
		if not erase:
			var problem := _check_tile(layer.tile_set, source, atlas, alt)
			if not problem.is_empty():
				return McpTool.error("Cell (%d, %d): %s" % [cell.coords.x, cell.coords.y, problem])
		placements.append([cell.coords, source, atlas, alt])
	var action := ACTION_PREFIX + "%s %d cells on %s" % ["erase" if erase else "set", placements.size(), layer.name]
	_apply_cells(found, action, "tilemap_set_cells", args, func() -> void:
		for placement: Array in placements:
			layer.set_cell(placement[0], placement[1], placement[2], placement[3]))
	return _done("%s %d cells on %s (now %d cells)." % ["Erased" if erase else "Set", placements.size(), layer.name, layer.get_used_cells().size()], action)


func _tilemap_paint_terrain(args: Dictionary) -> Dictionary:
	var found := _layer(args)
	if found.has("error"):
		return McpTool.error(found.error)
	var layer: TileMapLayer = found.layer
	var tile_set := layer.tile_set
	if tile_set == null or tile_set.get_terrain_sets_count() == 0:
		return McpTool.error("%s's TileSet has no terrain sets. Terrains (and the peering bits of each tile) are set up in the TileSet editor; until then, place tiles with tilemap_set_cells." % layer.name)
	var terrain_set := McpTool.int_arg(args, "terrain_set", 0)
	if terrain_set < 0 or terrain_set >= tile_set.get_terrain_sets_count():
		return McpTool.error("There is no terrain set %d (there are %d)." % [terrain_set, tile_set.get_terrain_sets_count()])
	var terrain := -1
	var names: PackedStringArray = []
	for i: int in tile_set.get_terrains_count(terrain_set):
		names.append("%d %s" % [i, tile_set.get_terrain_name(terrain_set, i)])
		if str(args.terrain) == str(i) or str(args.terrain).to_lower() == tile_set.get_terrain_name(terrain_set, i).to_lower():
			terrain = i
	if args.terrain is float or args.terrain is int:
		terrain = int(args.terrain) if int(args.terrain) < tile_set.get_terrains_count(terrain_set) else -1
	if terrain < 0:
		return McpTool.error("Unknown terrain %s in set %d. Terrains: %s." % [args.terrain, terrain_set, ", ".join(names)])
	var cells: Variant = _cells(args)
	if cells is String:
		return McpTool.error(cells)
	var coords: Array[Vector2i] = []
	for cell: Dictionary in cells:
		coords.append(cell.coords)
	var path: bool = args.get("mode") == "path"
	var action := ACTION_PREFIX + "paint terrain %s on %s" % [tile_set.get_terrain_name(terrain_set, terrain), layer.name]
	_apply_cells(found, action, "tilemap_paint_terrain", args, func() -> void:
		if path:
			layer.set_cells_terrain_path(coords, terrain_set, terrain)
		else:
			layer.set_cells_terrain_connect(coords, terrain_set, terrain))
	return _done("Painted %d cells with terrain %s (set %d, %s) on %s." % [coords.size(), tile_set.get_terrain_name(terrain_set, terrain), terrain_set, "path" if path else "connect", layer.name], action)


func _tilemap_clear(args: Dictionary) -> Dictionary:
	var found := _layer(args)
	if found.has("error"):
		return McpTool.error(found.error)
	var layer: TileMapLayer = found.layer
	var count := layer.get_used_cells().size()
	var action := ACTION_PREFIX + "clear %s" % layer.name
	_apply_cells(found, action, "tilemap_clear", args, layer.clear)
	return _done("Cleared %d cells of %s." % [count, layer.name], action)


# --- internos ------------------------------------------------------------------------------------

## {layer, root} o {error}.
func _layer(args: Dictionary) -> Dictionary:
	var scene := McpTool.str_arg(args, "scene")
	var root := EditorInterface.get_edited_scene_root()
	if not scene.is_empty() and (root == null or root.scene_file_path != scene):
		if not ResourceLoader.exists(scene, "PackedScene"):
			return {"error": "The scene %s does not exist." % scene}
		EditorInterface.open_scene_from_path(scene)
		root = EditorInterface.get_edited_scene_root()
	if root == null:
		return {"error": "There is no open scene. Open one with open_scene."}
	var node := SceneAccess.find_node(root, str(args.node_path))
	if node == null:
		return {"error": "There is no node '%s' in %s. Use scene_tree." % [args.node_path, root.scene_file_path.get_file()]}
	if not node is TileMapLayer:
		var hint := " (the old TileMap node is deprecated: use TileMapLayer)" if node.get_class() == "TileMap" else ""
		return {"error": "%s is %s, not a TileMapLayer%s." % [node.name, node.get_class(), hint]}
	return {"layer": node, "root": root}


## Aplica el cambio de celdas y lo registra como un paso de deshacer (tile_map_data antes y después).
func _apply_cells(found: Dictionary, action: String, tool_name: String, args: Dictionary, change: Callable) -> void:
	var layer: TileMapLayer = found.layer
	var before := layer.tile_map_data
	change.call()
	var after := layer.tile_map_data
	var undo_redo := EditorInterface.get_editor_undo_redo()
	undo_redo.create_action(action, UndoRedo.MERGE_DISABLE, found.root)
	undo_redo.add_do_property(layer, &"tile_map_data", after)
	undo_redo.add_undo_property(layer, &"tile_map_data", before)
	undo_redo.commit_action(false)
	_record(tool_name, args, action, found.root)


## Celdas de `cells` y `rect`: [{coords: Vector2i, atlas?, source?, alt?}] o el error.
func _cells(args: Dictionary) -> Variant:
	var result: Array[Dictionary] = []
	if args.get("cells") is Array:
		for item: Variant in args.cells:
			if item is Array:
				var coords: Variant = _vector(item)
				if not coords is Vector2i:
					return "Each cell must be [x, y] or {\"x\", \"y\", …}; got %s." % JSON.stringify(item)
				result.append({"coords": coords})
			elif item is Dictionary and (item.get("x") is float or item.get("x") is int) and (item.get("y") is float or item.get("y") is int):
				var cell := {"coords": Vector2i(int(item.x), int(item.y))}
				if item.has("atlas"):
					if not _vector(item.atlas) is Vector2i:
						return "`atlas` of cell (%d, %d) must be [x, y]." % [cell.coords.x, cell.coords.y]
					cell.atlas = _vector(item.atlas)
				for key: String in ["source", "alt"]:
					if item.has(key):
						cell[key] = int(item[key])
				result.append(cell)
			else:
				return "Each cell must be [x, y] or {\"x\", \"y\", …}; got %s." % JSON.stringify(item)
	if args.get("rect") is Array:
		var rect: Variant = _rect(args.rect)
		if rect is String:
			return rect
		for y: int in range(rect.position.y, rect.end.y):
			for x: int in range(rect.position.x, rect.end.x):
				result.append({"coords": Vector2i(x, y)})
	if result.is_empty():
		return "Pass `cells` and/or `rect`."
	if result.size() > MAX_CELLS:
		return "%d cells in one call; the limit is %d." % [result.size(), MAX_CELLS]
	return result


static func _check_tile(tile_set: TileSet, source_id: int, atlas: Vector2i, alt: int) -> String:
	if not tile_set.has_source(source_id):
		var ids: PackedStringArray = []
		for i: int in tile_set.get_source_count():
			ids.append(str(tile_set.get_source_id(i)))
		return "there is no source %d (sources: %s)." % [source_id, ", ".join(ids)]
	var source := tile_set.get_source(source_id)
	if not source.has_tile(atlas):
		return "source %d has no tile at atlas %s (use tilemap_get to see its tiles)." % [source_id, atlas]
	if not source.has_alternative_tile(atlas, alt):
		return "source %d has no alternative %d at %s." % [source_id, alt, atlas]
	return ""


static func _tileset_lines(tile_set: TileSet) -> PackedStringArray:
	var lines: PackedStringArray = ["Sources:"]
	for i: int in tile_set.get_source_count():
		var id := tile_set.get_source_id(i)
		var source := tile_set.get_source(id)
		if source is TileSetAtlasSource:
			var atlas := source as TileSetAtlasSource
			var tiles: PackedStringArray = []
			for t: int in atlas.get_tiles_count():
				var coords := atlas.get_tile_id(t)
				tiles.append("(%d,%d)" % [coords.x, coords.y])
			var shown := ", ".join(tiles.slice(0, 64)) + (" …" if tiles.size() > 64 else "")
			lines.append("  %d: atlas %s, tiles %dx%d, grid %dx%d, %d tiles: %s" % [id, atlas.texture.resource_path if atlas.texture else "(no texture)", atlas.texture_region_size.x, atlas.texture_region_size.y,
				atlas.get_atlas_grid_size().x, atlas.get_atlas_grid_size().y, atlas.get_tiles_count(), shown])
		elif source is TileSetScenesCollectionSource:
			var scenes := source as TileSetScenesCollectionSource
			var items: PackedStringArray = []
			for t: int in scenes.get_scene_tiles_count():
				var scene_id := scenes.get_scene_tile_id(t)
				var packed := scenes.get_scene_tile_scene(scene_id)
				items.append("alt %d = %s" % [scene_id, packed.resource_path if packed else "?"])
			lines.append("  %d: scenes, %s" % [id, ", ".join(items)])
	if tile_set.get_source_count() == 0:
		lines.append("  (none: add one with tileset_add_atlas)")
	lines.append("Physics layers: %d" % tile_set.get_physics_layers_count())
	for terrain_set: int in tile_set.get_terrain_sets_count():
		var terrains: PackedStringArray = []
		for t: int in tile_set.get_terrains_count(terrain_set):
			terrains.append("%d %s" % [t, tile_set.get_terrain_name(terrain_set, t)])
		lines.append("Terrain set %d (%s): %s" % [terrain_set, ["match corners and sides", "match corners", "match sides"][tile_set.get_terrain_set_mode(terrain_set)], ", ".join(terrains)])
	return lines


## Si el TileSet es un .tres propio, se guarda al hacer y al deshacer.
static func _save_tileset_steps(undo_redo: EditorUndoRedoManager, tile_set: TileSet) -> void:
	if _is_file(tile_set):
		undo_redo.add_do_method(ResourceSaver, &"save", tile_set, tile_set.resource_path)
		undo_redo.add_undo_method(ResourceSaver, &"save", tile_set, tile_set.resource_path)


static func _save_tileset(tile_set: TileSet) -> void:
	if _is_file(tile_set):
		ResourceSaver.save(tile_set, tile_set.resource_path)


static func _is_file(resource: Resource) -> bool:
	return not resource.resource_path.is_empty() and not resource.resource_path.contains("::")


static func _vector(value: Variant) -> Variant:
	if value is Array and value.size() == 2 and (value[0] is float or value[0] is int) and (value[1] is float or value[1] is int):
		return Vector2i(int(value[0]), int(value[1]))
	return null


static func _rect(value: Variant) -> Variant:
	if value is Array and value.size() == 4:
		for item: Variant in value:
			if not (item is float or item is int):
				return "`rect` must be [x, y, width, height]."
		if int(value[2]) <= 0 or int(value[3]) <= 0:
			return "`rect` needs a positive width and height."
		return Rect2i(int(value[0]), int(value[1]), int(value[2]), int(value[3]))
	return "`rect` must be [x, y, width, height]."


func _record(tool_name: String, args: Dictionary, action: String, root: Node) -> void:
	if on_action.is_valid():
		on_action.call(tool_name, args, EditorUndo.record(action, root))


static func _done(text: String, action: String) -> Dictionary:
	return McpTool.text("%s\nUndo step: «%s»." % [text, action])
