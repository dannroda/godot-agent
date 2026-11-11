@tool
extends RefCounted
## Qué nodo del juego hay debajo de un punto de la captura (m11-37): el usuario hace clic en la
## captura del juego en el dock y el probe contesta con el nodo para escribirlo como @mención.
## Orden: un Control visible bajo el punto (el que se dibuja encima: capa, z_index y orden del árbol),
## salvo que cubra casi toda la pantalla (un fondo); un SubViewportContainer se mira por dentro; después
## el mundo 2D (cuerpos y áreas visibles por física, el de menor tamaño en pantalla; si no, los
## Sprite2D, AnimatedSprite2D, Polygon2D y TileMapLayer visibles; si no, las áreas que cubren casi toda
## la pantalla); después 3D por raycast desde la cámara activa (solo lo visible con colisión); y si no
## hubo nada, el Control grande. Se recorre todo el viewport, no solo la escena en marcha: un HUD en un
## autoload también se señala. Corre dentro del juego: nada de EditorInterface.

## Un Control o un área que ocupa más que esto del viewport se considera un fondo.
const BACKGROUND_AREA := 0.9
const RAY_LENGTH := 4000.0
const MAX_HITS := 32
## Cuántos cuerpos 3D ocultos se saltean antes de rendirse.
const MAX_HIDDEN_3D := 8
## SubViewportContainer dentro de SubViewportContainer: hasta dónde se baja.
const MAX_DEPTH := 4
## Lo del propio harness (el probe y sus hijos) no se señala.
const HARNESS_DIR := "res://addons/godot_agent/"


## `uv` en [0, 1] sobre la captura (la textura del viewport). {node: {path, class, kind, point}} o {}.
## `path` es relativo a `scene_root` (la escena en marcha), como las @menciones del editor; lo que está
## fuera de la escena (un autoload) va con su ruta absoluta (/root/…).
static func at(viewport: Viewport, scene_root: Node, uv: Vector2) -> Dictionary:
	if viewport == null or scene_root == null:
		return {}
	var hit := _pick(viewport, capture_to_point(viewport, uv), 0)
	if hit.is_empty():
		return {}
	return _result(scene_root, hit.node, hit.kind, hit.point)


## Un punto de la captura (uv) en las coordenadas del viewport, las que usan los nodos (con stretch,
## las del tamaño base del proyecto). La captura es la textura del viewport: en el modo canvas_items
## (y sin stretch) tiene el tamaño de la ventana, con las barras del aspecto, y el stretch se deshace con
## la transformación final; en el modo viewport se dibuja al tamaño base y ya está en esas coordenadas.
static func capture_to_point(viewport: Viewport, uv: Vector2) -> Vector2:
	var window := viewport as Window
	if window == null or window.content_scale_mode == Window.CONTENT_SCALE_MODE_VIEWPORT:
		return uv * viewport.get_visible_rect().size
	return viewport.get_final_transform().affine_inverse() * (uv * Vector2(window.size))


static func _result(scene_root: Node, node: Node, kind: String, point: Vector2) -> Dictionary:
	var path := "."
	if node != scene_root:
		path = String(scene_root.get_path_to(node)) if scene_root.is_ancestor_of(node) else String(node.get_path())
	return {"node": {"path": path, "class": node.get_class(), "kind": kind, "point": [roundi(point.x), roundi(point.y)]}}


static func _pick(viewport: Viewport, point: Vector2, depth: int) -> Dictionary:
	var drawn := _drawn(viewport)
	var background: Control = null
	var control := _control_at(drawn, point)
	if control:
		var container := control as SubViewportContainer
		if container and depth < MAX_DEPTH:
			var inner := _inside_container(container, point, depth)
			if not inner.is_empty():
				return inner
		var screen := viewport.get_visible_rect().size
		if control.size.x * control.size.y < BACKGROUND_AREA * screen.x * screen.y:
			return {"node": control, "kind": "control", "point": point}
		background = control
	var physics := _physics_2d_at(viewport, drawn, point)
	if physics.small:
		return {"node": physics.small, "kind": "2d", "point": point}
	var item := _canvas_item_at(drawn, point)
	if item:
		return {"node": item, "kind": "2d", "point": point}
	if physics.large:
		return {"node": physics.large, "kind": "2d", "point": point}
	var body := _body_3d_at(viewport, point)
	if body:
		return {"node": body, "kind": "3d", "point": point}
	if background:
		return {"node": background, "kind": "control", "point": point}
	return {}


## Lo que dibuja un SubViewportContainer (un juego en pixel art suele ir así): el punto pasa a las
## coordenadas de su SubViewport.
static func _inside_container(container: SubViewportContainer, point: Vector2, depth: int) -> Dictionary:
	var local := container.get_global_transform_with_canvas().affine_inverse() * point
	if container.stretch:
		local /= float(maxi(container.stretch_shrink, 1))
	for child: Node in container.get_children():
		var sub := child as SubViewport
		if sub:
			return _pick(sub, local, depth + 1)
	return {}


## El Control que se dibuja encima entre los que contienen el punto.
static func _control_at(drawn: Array[Dictionary], point: Vector2) -> Control:
	var found: Dictionary = {}
	for entry: Dictionary in drawn:
		var control := entry.node as Control
		if control == null:
			continue
		var local := control.get_global_transform_with_canvas().affine_inverse() * point
		if Rect2(Vector2.ZERO, control.size).has_point(local) and (found.is_empty() or _drawn_after(entry.key, found.key)):
			found = entry
	return found.get("node") as Control if not found.is_empty() else null


## Cuerpos y áreas 2D visibles bajo el punto, por capa (cada CanvasLayer tiene su transformación).
## `small`: el de menor tamaño en pantalla entre los que no la cubren casi toda; `large`: un área
## enorme (un trigger del nivel) o algo sin forma medible (un TileMapLayer con colisión).
static func _physics_2d_at(viewport: Viewport, drawn: Array[Dictionary], point: Vector2) -> Dictionary:
	var out := {"small": null, "large": null}
	var world := viewport.find_world_2d()
	if world == null or world.direct_space_state == null:
		return out
	var layers: Array = [null]
	var keys := {}
	for entry: Dictionary in drawn:
		keys[entry.node] = entry.key
		if entry.node is CanvasLayer:
			layers.append(entry.node)
	var screen := viewport.get_visible_rect().size
	var limit := BACKGROUND_AREA * screen.x * screen.y
	var best_area := INF
	for layer: Variant in layers:
		var canvas: Transform2D = (layer as CanvasLayer).get_final_transform() if layer else viewport.get_canvas_transform()
		var query := PhysicsPointQueryParameters2D.new()
		query.position = canvas.affine_inverse() * point
		# Sin esto la consulta solo ve el canvas por defecto: lo de un CanvasLayer no aparece.
		query.canvas_instance_id = (layer as CanvasLayer).get_instance_id() if layer else 0
		query.collide_with_areas = true
		query.collide_with_bodies = true
		for hit: Dictionary in world.direct_space_state.intersect_point(query, MAX_HITS):
			var collider := hit.get("collider") as Node
			if collider == null or not keys.has(collider):
				continue  # oculto, de otro viewport o del harness
			if collider is CanvasItem and (collider as CanvasItem).get_canvas_layer_node() != layer:
				continue  # el punto cayó en sus coordenadas, pero se dibuja en otra capa
			var area := _screen_area(collider)
			if area >= limit:
				if out.large == null or _drawn_after(keys[collider], keys[out.large]):
					out.large = collider
			elif out.small == null or area < best_area or (is_equal_approx(area, best_area) and _drawn_after(keys[collider], keys[out.small])):
				out.small = collider
				best_area = area
	return out


## Lo que ocupan en pantalla las formas de un cuerpo o área; INF si no se puede medir.
static func _screen_area(node: Node) -> float:
	var object := node as CollisionObject2D
	if object == null:
		return INF
	var canvas := object.get_global_transform_with_canvas()
	var bounds := Rect2()
	var any := false
	for owner_id: int in object.get_shape_owners():
		if object.is_shape_owner_disabled(owner_id):
			continue
		var transform := canvas * object.shape_owner_get_transform(owner_id)
		for i in object.shape_owner_get_shape_count(owner_id):
			var rect := transform * object.shape_owner_get_shape(owner_id, i).get_rect()
			bounds = bounds.merge(rect) if any else rect
			any = true
	return bounds.get_area() if any else INF


## El Sprite2D, AnimatedSprite2D, Polygon2D o TileMapLayer que se dibuja encima bajo el punto.
static func _canvas_item_at(drawn: Array[Dictionary], point: Vector2) -> Node:
	var found: Dictionary = {}
	for entry: Dictionary in drawn:
		var item := entry.node as CanvasItem
		if item == null or item is Control:
			continue
		if _canvas_item_has_point(item, item.get_global_transform_with_canvas().affine_inverse() * point) and (found.is_empty() or _drawn_after(entry.key, found.key)):
			found = entry
	return found.get("node") as Node if not found.is_empty() else null


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


## El primer cuerpo 3D visible en el rayo desde la cámara. `point` en coordenadas del viewport, las
## mismas que usan project_ray_origin y unproject_position.
static func _body_3d_at(viewport: Viewport, point: Vector2) -> Node:
	var camera := viewport.get_camera_3d()
	var world := viewport.find_world_3d()
	if camera == null or world == null or world.direct_space_state == null:
		return null
	var origin := camera.project_ray_origin(point)
	var query := PhysicsRayQueryParameters3D.create(origin, origin + camera.project_ray_normal(point) * RAY_LENGTH)
	query.collide_with_areas = true
	var exclude: Array[RID] = []
	for attempt in MAX_HIDDEN_3D:
		query.exclude = exclude
		var hit := world.direct_space_state.intersect_ray(query)
		if hit.is_empty():
			return null
		var collider := hit.get("collider") as Node
		var node_3d := collider as Node3D
		if collider and (node_3d == null or node_3d.is_visible_in_tree()) and not _is_harness(collider):
			return collider
		exclude.append(hit.rid)
	return null


## Lo que se dibuja en `viewport`, con su orden de dibujo: `[{node, key}]`. Sin lo oculto (un
## CanvasItem o un CanvasLayer con visible en falso), sin otros viewports (un SubViewport dibuja en su
## textura) y sin lo del harness. Incluye los CanvasLayer visibles (para las consultas de física).
static func _drawn(viewport: Viewport) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for child: Node in viewport.get_children():
		_walk(child, viewport, out)
	return out


static func _walk(node: Node, viewport: Viewport, out: Array[Dictionary]) -> void:
	if node is Viewport or _is_harness(node):
		return
	if node is CanvasItem and not (node as CanvasItem).visible:
		return
	if node is CanvasLayer and not (node as CanvasLayer).visible:
		return
	if node is CanvasLayer or (node is CanvasItem and node.get_viewport() == viewport):
		out.append({"node": node, "key": _draw_key(node, out.size())})
	for child: Node in node.get_children():
		_walk(child, viewport, out)


static func _is_harness(node: Node) -> bool:
	var script := node.get_script() as Script
	return script != null and script.resource_path.begins_with(HARNESS_DIR)


## [capa, z_index efectivo, orden en el árbol]: lo que decide qué se dibuja encima.
static func _draw_key(node: Node, index: int) -> Array:
	if node is CanvasLayer:
		return [(node as CanvasLayer).layer, 0, index]
	var item := node as CanvasItem
	var layer_node := item.get_canvas_layer_node()
	var z := 0
	var current: Node = item
	while current is CanvasItem:
		var canvas_item := current as CanvasItem
		z += canvas_item.z_index
		if not canvas_item.z_as_relative:
			break
		current = current.get_parent()
	return [layer_node.layer if layer_node else 0, z, index]


## `a` se dibuja después (encima) de `b`.
static func _drawn_after(a: Array, b: Array) -> bool:
	for i in a.size():
		if a[i] != b[i]:
			return a[i] > b[i]
	return false
