extends RefCounted
## capture_game_frame y capture_editor_viewport (m11-64) desde otra cámara (m11-52): una cámara del juego elegida, una posición y un punto
## (look_from/look_at), o varios ángulos alrededor de un punto. Renderiza en un SubViewport fuera de
## pantalla que comparte el mundo del juego, con una cámara temporal: la cámara del jugador no se mueve
## y el juego no se ve distinto. Ideas de screen_capture del MCP de Roblox Studio (cámara y objetivo) y
## CaptureMultiAngleSceneView del Assistant de Unity. Corre dentro del juego: sin código de editor.

const MAX_ANGLES := 8
const ELEVATION_DEG := 30.0
const MIN_DISTANCE := 4.0
## Distancia al centro, en radios del contenido, cuando no se pasa `distance`.
const RADII := 2.5


## Si hay algo para elegir la vista: camera, look_from, look_at o angles.
static func wants_view(params: Dictionary) -> bool:
	return params.has("camera") or params.has("look_from") or params.has("look_at") or params.has("angles")


## Valida lo pedido y arma las vistas, sin renderizar. {views: [{label, transform (3D) | position, zoom (2D), source}], three_d} o {error}.
static func plan(root: Node, viewport: Viewport, params: Dictionary) -> Dictionary:
	var source: Node = null
	if params.has("camera"):
		var path := str(params.camera)
		source = root.get_node_or_null(NodePath(path)) if not path.begins_with("/") else root.get_tree().root.get_node_or_null(NodePath(path))
		if source == null:
			source = root.find_child(path, true, false)
		if not (source is Camera3D or source is Camera2D):
			return {"error": "camera «%s» is not a Camera3D or Camera2D in the running scene (a node path from the scene root, or a name)." % path}
	var three_d: bool = source is Camera3D if source else (viewport.get_camera_3d() != null or not root.find_children("*", "VisualInstance3D", true, false).is_empty())
	# El editor dice cuál de sus vistas (capture_editor_viewport `which`, m11-64).
	if source == null and params.get("view_3d") is bool:
		three_d = params.view_3d
	var look_from: Variant = _vector(params.get("look_from"), three_d)
	var look_at: Variant = _vector(params.get("look_at"), three_d)
	if params.has("look_from") and look_from == null or params.has("look_at") and look_at == null:
		return {"error": "look_from and look_at take %s numbers [x, y%s]." % ["3" if three_d else "2", ", z" if three_d else ""]}
	var angles := int(params.get("angles", 0))
	if params.has("angles") and (angles < 1 or angles > MAX_ANGLES):
		return {"error": "angles goes from 1 to %d." % MAX_ANGLES}
	if angles > 0 and not three_d:
		return {"error": "angles is for 3D scenes; in 2D use look_at [x, y] and zoom."}
	if angles > 0 and look_from != null:
		return {"error": "angles orbits around look_at (or the scene's center): it does not take look_from."}
	var views: Array[Dictionary] = []
	if not three_d:
		var camera_2d := source as Camera2D if source else viewport.get_camera_2d()
		var center: Vector2 = look_at if look_at != null else (camera_2d.get_screen_center_position() if camera_2d else viewport.get_visible_rect().size / 2.0)
		var zoom := float(params.get("zoom", camera_2d.zoom.x if camera_2d else 1.0))
		views.append({"label": "2D view at (%.1f, %.1f), zoom %.2f" % [center.x, center.y, zoom], "position": center, "zoom": zoom, "source": camera_2d})
		return {"views": views, "three_d": false}
	var reference := source as Camera3D if source else viewport.get_camera_3d()
	if angles > 0:
		var center: Vector3 = look_at if look_at != null else content_center(root)
		var distance := float(params.get("distance", maxf(MIN_DISTANCE, content_radius(root, center) * RADII)))
		for i in angles:
			var heading := 360.0 * i / angles
			views.append({"label": "angle %d of %d: heading %d°, %d° up, %.1f m from (%.1f, %.1f, %.1f)" % [i + 1, angles, roundi(heading), roundi(ELEVATION_DEG), distance, center.x, center.y, center.z],
				"transform": orbit(center, heading, ELEVATION_DEG, distance), "source": reference})
		return {"views": views, "three_d": true}
	if look_from != null or look_at != null:
		var from: Vector3 = look_from if look_from != null else (reference.global_position if reference else Vector3(0, 2, 6))
		var target: Vector3 = look_at if look_at != null else from + (-reference.global_basis.z if reference else Vector3.FORWARD)
		if from.is_equal_approx(target):
			return {"error": "look_from and look_at are the same point."}
		views.append({"label": "from (%.1f, %.1f, %.1f) looking at (%.1f, %.1f, %.1f)" % [from.x, from.y, from.z, target.x, target.y, target.z],
			"transform": _looking(from, target), "source": reference})
		return {"views": views, "three_d": true}
	views.append({"label": "camera %s" % source.name, "transform": (source as Camera3D).global_transform, "source": source})
	return {"views": views, "three_d": true}


## Una cámara en la órbita: `heading` alrededor del eje Y, `elevation` hacia arriba.
static func orbit(center: Vector3, heading_deg: float, elevation_deg: float, distance: float) -> Transform3D:
	var heading := deg_to_rad(heading_deg)
	var elevation := deg_to_rad(elevation_deg)
	var offset := Vector3(sin(heading) * cos(elevation), sin(elevation), cos(heading) * cos(elevation)) * distance
	return _looking(center + offset, center)


static func _looking(from: Vector3, target: Vector3) -> Transform3D:
	var up := Vector3.UP if absf((target - from).normalized().dot(Vector3.UP)) < 0.99 else Vector3.FORWARD
	return Transform3D(Basis.looking_at(target - from, up), from)


## El centro de lo que se dibuja en 3D (las cajas de los VisualInstance3D visibles), o el origen.
static func content_center(root: Node) -> Vector3:
	var box := _content_box(root)
	return box.get_center() if box.size != Vector3.ZERO or box.position != Vector3.ZERO else Vector3.ZERO


static func content_radius(root: Node, center: Vector3) -> float:
	var box := _content_box(root)
	var radius := 0.0
	for i in 8:
		radius = maxf(radius, center.distance_to(box.get_endpoint(i)))
	return radius


static func _content_box(root: Node) -> AABB:
	var box := AABB()
	var first := true
	for node: Node in root.find_children("*", "VisualInstance3D", true, false):
		var visual := node as VisualInstance3D
		if not visual.is_visible_in_tree():
			continue
		var global_box := visual.global_transform * visual.get_aabb()
		box = global_box if first else box.merge(global_box)
		first = false
	return box


static func _vector(value: Variant, three_d: bool) -> Variant:
	if value == null:
		return null
	if not value is Array or (value as Array).size() != (3 if three_d else 2):
		return null
	for number: Variant in value:
		if not (number is float or number is int):
			return null
	return Vector3(value[0], value[1], value[2]) if three_d else Vector2(value[0], value[1])


## Renderiza las vistas de `plan` del tamaño de `viewport` (por defecto el del juego), con su mundo.
## [{label, png}] o {error}.
static func render(host: Node, planned: Dictionary, max_side: int, viewport: Viewport = null) -> Variant:
	if viewport == null:
		viewport = host.get_viewport()
	var size := Vector2i(viewport.get_visible_rect().size)
	var sub := SubViewport.new()
	sub.size = size
	sub.render_target_update_mode = SubViewport.UPDATE_DISABLED
	if planned.three_d:
		sub.world_3d = viewport.find_world_3d()
	else:
		sub.world_2d = viewport.find_world_2d()
	host.add_child(sub)
	var shots: Array[Dictionary] = []
	for view: Dictionary in planned.views:
		var camera: Node = _camera(view, planned.three_d)
		sub.add_child(camera)
		if planned.three_d:
			(camera as Camera3D).make_current()
		else:
			(camera as Camera2D).make_current()
		sub.render_target_update_mode = SubViewport.UPDATE_ONCE
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		var image := sub.get_texture().get_image()
		camera.queue_free()
		if image == null or image.is_empty():
			sub.queue_free()
			return {"error": "Could not read the rendered view."}
		var longest := maxi(image.get_width(), image.get_height())
		if max_side > 0 and longest > max_side:
			var scale := float(max_side) / longest
			image.resize(maxi(1, roundi(image.get_width() * scale)), maxi(1, roundi(image.get_height() * scale)), Image.INTERPOLATE_BILINEAR)
		shots.append({"label": view.label, "png": image.save_png_to_buffer()})
	sub.queue_free()
	return shots


## La cámara temporal: copia lente y entorno de la de referencia (la elegida o la del juego).
static func _camera(view: Dictionary, three_d: bool) -> Node:
	if not three_d:
		var camera_2d := Camera2D.new()
		camera_2d.position = view.position
		camera_2d.zoom = Vector2.ONE * float(view.zoom)
		camera_2d.anchor_mode = Camera2D.ANCHOR_MODE_DRAG_CENTER
		return camera_2d
	var camera := Camera3D.new()
	var source := view.get("source") as Camera3D
	if source:
		for property in [&"fov", &"near", &"far", &"projection", &"size", &"keep_aspect", &"environment", &"attributes", &"cull_mask", &"h_offset", &"v_offset"]:
			camera.set(property, source.get(property))
	camera.transform = view.transform
	return camera
