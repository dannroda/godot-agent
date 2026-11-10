@tool
extends RefCounted
## Qué nodo del juego hay debajo de un punto de la captura (m11-37): el usuario hace clic en la
## captura del juego en el dock y el probe contesta con el nodo para escribirlo como @mención.
## Orden: un Control visible bajo el punto (el que se dibuja último entre los que lo contienen),
## salvo que cubra casi toda la pantalla (un fondo); después el mundo 2D (cuerpos y áreas por física,
## y si no los Sprite2D, AnimatedSprite2D, Polygon2D y TileMapLayer visibles); después 3D por raycast
## desde la cámara activa (solo lo que tiene colisión); y si no hubo nada, el Control grande.
## Corre dentro del juego: nada de EditorInterface.

## Un Control que ocupa más que esto del viewport se considera un fondo.
const BACKGROUND_AREA := 0.9
const RAY_LENGTH := 4000.0


## `uv` en [0, 1] sobre la captura (que es el viewport entero). {node: {path, class, kind, point}} o {}.
## `path` es relativo a `scene_root` (la escena en marcha), como las @menciones del editor.
static func at(viewport: Viewport, scene_root: Node, uv: Vector2) -> Dictionary:
	if viewport == null or scene_root == null:
		return {}
	var pixel := uv * Vector2(viewport.get_visible_rect().size)
	var point := viewport.get_final_transform().affine_inverse() * pixel
	var background: Control = null
	var control := _control_at(scene_root, viewport, point)
	if control:
		var area := control.size.x * control.size.y
		var screen := viewport.get_visible_rect().size
		if area < BACKGROUND_AREA * screen.x * screen.y:
			return _result(scene_root, control, "control", point)
		background = control
	var item := _canvas_item_at(scene_root, viewport, point)
	if item:
		return _result(scene_root, item, "2d", point)
	var body := _body_3d_at(viewport, pixel)
	if body:
		return _result(scene_root, body, "3d", point)
	if background:
		return _result(scene_root, background, "control", point)
	return {}


static func _result(scene_root: Node, node: Node, kind: String, point: Vector2) -> Dictionary:
	var path := "." if node == scene_root else String(scene_root.get_path_to(node))
	return {"node": {"path": path, "class": node.get_class(), "kind": kind, "point": [roundi(point.x), roundi(point.y)]}}


## El último Control visible (en orden de dibujo) que contiene el punto.
static func _control_at(root: Node, viewport: Viewport, point: Vector2) -> Control:
	var found: Control = null
	for node: Node in _visible_descendants(root, viewport):
		var control := node as Control
		if control == null:
			continue
		var local := control.get_global_transform_with_canvas().affine_inverse() * point
		if Rect2(Vector2.ZERO, control.size).has_point(local):
			found = control
	return found


static func _canvas_item_at(root: Node, viewport: Viewport, point: Vector2) -> Node:
	var world := viewport.find_world_2d()
	if world and world.direct_space_state:
		var query := PhysicsPointQueryParameters2D.new()
		query.position = viewport.get_canvas_transform().affine_inverse() * point
		query.collide_with_areas = true
		query.collide_with_bodies = true
		var hits := world.direct_space_state.intersect_point(query, 8)
		var best: Node = null
		for hit: Dictionary in hits:
			var collider := hit.get("collider") as Node
			if collider and (best == null or _is_later(best, collider)):
				best = collider
		if best:
			return best
	var found: Node = null
	for node: Node in _visible_descendants(root, viewport):
		if node is Control:
			continue
		var item := node as CanvasItem
		if item and _canvas_item_has_point(item, item.get_global_transform_with_canvas().affine_inverse() * point):
			found = item
	return found


static func _canvas_item_has_point(item: CanvasItem, local: Vector2) -> bool:
	if item is Sprite2D:
		return (item as Sprite2D).get_rect().has_point(local)
	if item is AnimatedSprite2D:
		var sprite := item as AnimatedSprite2D
		var frames := sprite.sprite_frames
		if frames == null or not frames.has_animation(sprite.animation):
			return false
		var texture := frames.get_frame_texture(sprite.animation, sprite.frame)
		if texture == null:
			return false
		var size := texture.get_size()
		var origin := -size / 2.0 if sprite.centered else Vector2.ZERO
		return Rect2(origin + sprite.offset, size).has_point(local)
	if item is Polygon2D:
		return Geometry2D.is_point_in_polygon(local - (item as Polygon2D).offset, (item as Polygon2D).polygon)
	if item is TileMapLayer:
		var layer := item as TileMapLayer
		return layer.get_cell_source_id(layer.local_to_map(local)) != -1
	return false


static func _body_3d_at(viewport: Viewport, pixel: Vector2) -> Node:
	var camera := viewport.get_camera_3d()
	var world := viewport.find_world_3d()
	if camera == null or world == null or world.direct_space_state == null:
		return null
	var query := PhysicsRayQueryParameters3D.create(camera.project_ray_origin(pixel), camera.project_ray_origin(pixel) + camera.project_ray_normal(pixel) * RAY_LENGTH)
	query.collide_with_areas = true
	var hit := world.direct_space_state.intersect_ray(query)
	return hit.get("collider") as Node if not hit.is_empty() else null


## Los descendientes visibles en pantalla, en orden de dibujo (preorden), dentro de `viewport`.
static func _visible_descendants(root: Node, viewport: Viewport) -> Array[Node]:
	var out: Array[Node] = []
	_walk(root, viewport, out)
	return out


static func _walk(node: Node, viewport: Viewport, out: Array[Node]) -> void:
	if node is CanvasItem and not (node as CanvasItem).visible:
		return
	if node is Viewport and node != viewport:
		return  # otro viewport (un SubViewport) dibuja en su propia textura
	if node is CanvasItem and node.get_viewport() == viewport:
		out.append(node)
	for child: Node in node.get_children():
		_walk(child, viewport, out)


## `b` se dibuja después de `a` (está más adelante en preorden).
static func _is_later(a: Node, b: Node) -> bool:
	return b.is_greater_than(a)
