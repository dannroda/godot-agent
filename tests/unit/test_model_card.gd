extends "test_case.gd"
## m11-89: la tarjeta 3D de preview_model en el chat. Carga el modelo en su mundo propio, la cámara
## orbita, se mueve y acerca alrededor de su caja, como mucho 3 vivas, se suelta al ocultarse y al
## liberarse, y una sesión reanudada arranca con la miniatura. Lo que se dibuja de verdad lo mira
## mcp_check en el editor (acá no hay GPU).

const ModelCard := preload("res://addons/godot_agent/ui/dock/entries/model_card.gd")
const ToolGroupView := preload("res://addons/godot_agent/ui/dock/entries/tool_group_view.gd")
const SessionModel := preload("res://addons/godot_agent/session/session_model.gd")
const SessionHistory := preload("res://addons/godot_agent/session/session_history.gd")
const MarkdownBBCode := preload("res://addons/godot_agent/ui/markdown/markdown_bbcode.gd")

const DIR := "res://tests/tmp/model_card"

var _holder: VBoxContainer


## Un contenedor nuevo para las tarjetas de cada test (libera el anterior).
func _fresh_holder() -> void:
	if _holder and is_instance_valid(_holder):
		_holder.free()
	_holder = VBoxContainer.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(_holder)


func assert_almost(actual: float, expected: float, tolerance: float, label: String = "") -> void:
	assert_true(absf(actual - expected) <= tolerance, "%s (%f, se esperaba %f)" % [label, actual, expected])


## Una caja de 2 × 1 × 1 centrada en (0, 0.5, 0), como escena sin scripts.
func _scene() -> String:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))
	var path := DIR.path_join("box.tscn")
	if ResourceLoader.exists(path):
		return path
	var root := Node3D.new()
	var child := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(2, 1, 1)
	child.mesh = mesh
	child.position = Vector3(0, 0.5, 0)
	root.add_child(child)
	child.owner = root
	var scene := PackedScene.new()
	scene.pack(root)
	root.free()
	ResourceSaver.save(scene, path)
	return path


func _card(path: String, live: bool = true) -> Control:
	if _holder == null or not is_instance_valid(_holder):
		_fresh_holder()
	var card: Control = ModelCard.new()
	card.call(&"setup", path, null, live)
	_holder.add_child(card)
	return card


func _frames(count: int = 2) -> void:
	for i in count:
		await (Engine.get_main_loop() as SceneTree).process_frame


func test_loads_the_model_and_frames_it() -> void:
	_fresh_holder()
	var card := _card(_scene())
	await _frames()
	assert_true(card.call(&"is_live"), "un resultado nuevo arranca en 3D")
	var viewport: SubViewport = card.get(&"_viewport")
	assert_true(viewport != null and viewport.own_world_3d, "en un mundo propio")
	assert_true(viewport.render_target_update_mode in [SubViewport.UPDATE_ONCE, SubViewport.UPDATE_DISABLED], "se dibuja una vez, no cada frame")
	assert_true(card.call(&"is_on_screen"), "en pantalla")
	_holder.position = Vector2(100000, 0)
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	card.call(&"orbit", Vector2(10, 0))
	await _frames()
	assert_false(card.call(&"is_on_screen"), "fuera de pantalla")
	assert_eq(viewport.render_target_update_mode, SubViewport.UPDATE_DISABLED, "fuera de pantalla no se dibuja")
	_holder.position = Vector2.ZERO
	await _frames(1)
	assert_eq(viewport.render_target_update_mode, SubViewport.UPDATE_ONCE, "al volver, se dibuja lo que cambió")
	await _frames(1)
	assert_eq(viewport.render_target_update_mode, SubViewport.UPDATE_DISABLED, "una sola vez")
	assert_true(card.is_in_group(ModelCard.LIVE_GROUP), "cuenta entre las vivas")
	var box: AABB = card.get(&"_box")
	assert_true(box.size.is_equal_approx(Vector3(2, 1, 1)), "la caja del modelo: %s" % box)
	var camera: Transform3D = card.call(&"camera_transform")
	var center := Vector3(0, 0.5, 0)
	var radius := box.size.length() / 2.0
	assert_almost(camera.origin.distance_to(center), radius * ModelCard.FRAME_RADII, 0.001, "a la distancia en que entra")
	assert_almost((-camera.basis.z).dot((center - camera.origin).normalized()), 1.0, 0.0001, "mira al centro")
	assert_almost(rad_to_deg(asin((camera.origin - center).normalized().y)), ModelCard.START_ELEVATION, 0.01, "30° arriba, como la primera vista")


func test_orbit_pan_zoom_frame_and_reset() -> void:
	_fresh_holder()
	var card := _card(_scene())
	await _frames()
	var center := Vector3(0, 0.5, 0)
	var start: Transform3D = card.call(&"camera_transform")
	card.call(&"orbit", Vector2(-90.0, 0.0))
	var turned: Transform3D = card.call(&"camera_transform")
	assert_almost(turned.origin.distance_to(center), start.origin.distance_to(center), 0.001, "orbitar no cambia la distancia")
	assert_almost(rad_to_deg((start.origin - center).slide(Vector3.UP).angle_to((turned.origin - center).slide(Vector3.UP))), 90.0, 0.01, "giró 90° alrededor")
	card.call(&"orbit", Vector2(0.0, 500.0))
	var top: Transform3D = card.call(&"camera_transform")
	assert_almost(rad_to_deg(asin((top.origin - center).normalized().y)), ModelCard.MAX_ELEVATION, 0.01, "no pasa por arriba del polo")
	var before: Transform3D = card.call(&"camera_transform")
	card.call(&"zoom", 0.5)
	var near: Transform3D = card.call(&"camera_transform")
	assert_almost(near.origin.distance_to(center), before.origin.distance_to(center) * 0.5, 0.001, "acerca hacia el centro")
	card.call(&"pan", Vector2(40, 0))
	var panned: Transform3D = card.call(&"camera_transform")
	assert_true(panned.basis.is_equal_approx(near.basis), "mover no gira")
	assert_true((panned.origin - near.origin).dot(near.basis.x) < 0.0, "arrastrar a la derecha lleva la cámara a la izquierda (el modelo sigue al puntero)")
	card.call(&"frame_model")
	var framed: Transform3D = card.call(&"camera_transform")
	assert_true(framed.basis.is_equal_approx(panned.basis), "encuadrar no cambia el ángulo")
	assert_almost((-framed.basis.z).dot((center - framed.origin).normalized()), 1.0, 0.0001, "encuadrar vuelve a centrar")
	card.call(&"reset_view")
	assert_true((card.call(&"camera_transform") as Transform3D).is_equal_approx(start), "restablecer vuelve al principio")


func test_input_drags_and_wheel() -> void:
	_fresh_holder()
	var card := _card(_scene())
	await _frames()
	var screen: Control = card.get(&"_screen")
	var start: Transform3D = card.call(&"camera_transform")
	var drag := InputEventMouseMotion.new()
	drag.button_mask = MOUSE_BUTTON_MASK_LEFT
	drag.relative = Vector2(30, 0)
	card.call(&"handle_input", drag, screen)
	var orbited: Transform3D = card.call(&"camera_transform")
	assert_false(orbited.basis.is_equal_approx(start.basis), "arrastrar orbita")
	var shift := drag.duplicate() as InputEventMouseMotion
	shift.shift_pressed = true
	card.call(&"handle_input", shift, screen)
	var panned: Transform3D = card.call(&"camera_transform")
	assert_true(panned.basis.is_equal_approx(orbited.basis) and not panned.origin.is_equal_approx(orbited.origin), "Shift + arrastrar mueve")
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel.pressed = true
	var distance: float = card.get(&"_distance")
	card.call(&"handle_input", wheel, screen)
	assert_almost(float(card.get(&"_distance")), distance / ModelCard.ZOOM_STEP, 0.0001, "la rueda acerca")


func test_at_most_three_live_cards() -> void:
	_fresh_holder()
	var path := _scene()
	var cards: Array[Control] = []
	for i in ModelCard.MAX_LIVE + 1:
		cards.append(_card(path))
		await _frames()
	assert_eq((Engine.get_main_loop() as SceneTree).get_nodes_in_group(ModelCard.LIVE_GROUP).size(), ModelCard.MAX_LIVE, "como mucho 3 vivas")
	assert_false(cards[0].call(&"is_live"), "se soltó la más vieja")
	assert_false(cards[0].get(&"wanted"), "y no vuelve sola")
	assert_true((cards[0].get(&"_view_button") as Button).visible, "queda el botón para verla en 3D")
	assert_true(cards[ModelCard.MAX_LIVE].call(&"is_live"), "la nueva está viva")
	(cards[0].get(&"_view_button") as Button).pressed.emit()
	assert_true(cards[0].call(&"is_live"), "el botón la vuelve a cargar")
	assert_false(cards[1].call(&"is_live"), "y suelta la que ahora es la más vieja")


func test_hiding_releases_and_showing_reloads() -> void:
	_fresh_holder()
	var card := _card(_scene())
	await _frames()
	_holder.visible = false
	assert_false(card.call(&"is_live"), "oculta (grupo plegado) suelta la geometría")
	assert_true(card.get(&"wanted"), "pero vuelve cuando se vea")
	_holder.visible = true
	await _frames()
	assert_true(card.call(&"is_live"), "volvió a 3D al mostrarse")
	_holder.remove_child(card)
	assert_false(card.call(&"is_live"), "fuera del árbol, suelta")
	_holder.add_child(card)
	await _frames()
	assert_true(card.call(&"is_live"), "de vuelta en el árbol, carga")


func test_resumed_starts_with_thumbnail() -> void:
	_fresh_holder()
	var image := Image.create(8, 6, false, Image.FORMAT_RGBA8)
	var card: Control = ModelCard.new()
	card.call(&"setup", _scene(), ImageTexture.create_from_image(image), false)
	_holder.add_child(card)
	await _frames()
	assert_false(card.call(&"is_live"), "reanudada: sin 3D")
	assert_true((card.get(&"_thumb_rect") as TextureRect).visible, "con la miniatura")
	assert_true((card.get(&"_view_button") as Button).visible, "y el botón")
	assert_true((card.get(&"_buttons") as Array).all(func(button: Button) -> bool: return button.disabled), "sin 3D, Encuadrar/Restablecer/Ampliar no hacen nada")


func test_refuses_scenes_with_scripts_and_missing_models() -> void:
	_fresh_holder()
	var scripted := _card("res://tests/fixtures/debug_fixture.tscn")
	var missing := _card("res://tests/tmp/model_card/nowhere.glb")
	await _frames()
	for card: Control in [scripted, missing]:
		assert_false(card.call(&"is_live"), "no carga %s" % card.get(&"path"))
		assert_false((card.get(&"_view_button") as Button).visible, "sin botón para reintentar")
	assert_true((scripted.get(&"_status") as Label).text.contains("has scripts"), "dice por qué: %s" % (scripted.get(&"_status") as Label).text)
	assert_true((missing.get(&"_status") as Label).text.contains("does not exist"), "dice por qué")


## La entrada del chat: un preview_model terminado lleva la tarjeta, la línea del tamaño y las vistas
## plegadas (se decodifican al abrirlas); uno que falló, no. Del historial, solo la miniatura.
func test_tool_group_shows_the_card() -> void:
	_fresh_holder()
	var path := _scene()
	var png := Marshalls.raw_to_base64(Image.create(8, 6, false, Image.FORMAT_RGBA8).save_png_to_buffer())
	var content := [{"type": "content", "content": {"type": "text", "text": "%s: size (2, 1, 1) m" % path}}]
	for i in 2:
		content.append({"type": "content", "content": {"type": "text", "text": "angle %d of 2" % (i + 1)}})
		content.append({"type": "content", "content": {"type": "image", "mimeType": "image/png", "data": png}})
	var model := SessionModel.new()
	model.apply_update({"sessionUpdate": "tool_call", "toolCallId": "p1", "title": "mcp__godot__preview_model", "status": "completed",
		"rawInput": {"path": path}, "content": content})
	model.apply_update({"sessionUpdate": "tool_call", "toolCallId": "p2", "title": "mcp__godot__preview_model", "status": "failed",
		"rawInput": {"path": path}, "content": [{"type": "content", "content": {"type": "text", "text": "nope"}}]})
	var view: Control = ToolGroupView.new()
	view.call(&"setup", model.entries()[0], Color.ORANGE, MarkdownBBCode.new())
	view.set(&"tool_call_lookup", model.tool_call)
	_holder.add_child(view)
	await _frames()
	var rows: Dictionary = view.get(&"_rows")
	var extra: VBoxContainer = rows.p1.extra
	var cards := extra.find_children("*", "VBoxContainer", false, false).filter(func(node: Node) -> bool: return node.get_script() == ModelCard)
	assert_eq(cards.size(), 1, "la tarjeta en el resultado")
	if cards.is_empty():
		view.free()
		return
	var card: Control = cards[0]
	assert_true(card.call(&"is_live"), "nueva: en 3D")
	assert_true((card.get(&"thumbnail") as Texture2D) != null, "con la primera vista de miniatura")
	assert_eq(extra.find_children("*", "TextureRect", true, false).filter(func(rect: Node) -> bool: return not card.is_ancestor_of(rect)).size(), 0, "las vistas, plegadas y sin decodificar")
	var toggle: Button = null
	for button: Node in extra.find_children("*", "Button", true, false):
		if (button as Button).text == "▸ 2 views":
			toggle = button
	assert_true(toggle != null, "«▸ 2 views»")
	if toggle:
		toggle.button_pressed = true
		assert_eq(extra.find_children("*", "TextureRect", true, false).filter(func(rect: Node) -> bool: return not card.is_ancestor_of(rect)).size(), 2, "abiertas, las dos vistas")
	assert_eq((rows.p2.extra as Node).find_children("*", "VBoxContainer", false, false).filter(func(node: Node) -> bool: return node.get_script() == ModelCard).size(), 0, "si falló, sin tarjeta")
	view.free()
	# Lo mismo rearmado del historial: miniatura sola.
	var resumed := SessionModel.new()
	SessionHistory.replay({"events": [{"type": "update", "update": {"sessionUpdate": "tool_call", "toolCallId": "p1", "title": "mcp__godot__preview_model",
		"status": "completed", "rawInput": {"path": path}, "content": content}}]}, resumed)
	assert_true(resumed.tool_call("p1").from_history, "marcado como del historial")
	var old_view: Control = ToolGroupView.new()
	old_view.call(&"setup", resumed.entries()[0], Color.ORANGE, MarkdownBBCode.new())
	old_view.set(&"tool_call_lookup", resumed.tool_call)
	_holder.add_child(old_view)
	await _frames()
	var old_cards: Array = (old_view.get(&"_rows").p1.extra as Node).find_children("*", "VBoxContainer", false, false).filter(func(node: Node) -> bool: return node.get_script() == ModelCard)
	assert_eq(old_cards.size(), 1, "también tiene la tarjeta")
	if not old_cards.is_empty():
		assert_false(old_cards[0].call(&"is_live"), "pero sin cargar el modelo")
	old_view.free()


## Liberar la entrada (lo que hace el chat al soltar las viejas) no deja nodos sueltos.
func test_freeing_leaves_no_orphans() -> void:
	_fresh_holder()
	var path := _scene()
	await _frames()
	var before := int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	var nodes_before := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	for i in 3:
		var card := _card(path)
		await _frames()
		card.call(&"enlarge")
		await _frames()
		card.queue_free()
		await _frames(3)
	var hidden := _card(path)
	await _frames()
	_holder.visible = false
	await _frames(3)
	_holder.visible = true
	hidden.queue_free()
	await _frames(3)
	assert_eq(int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)), before, "sin huérfanos")
	assert_eq(int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)), nodes_before, "ni nodos de más (tarjeta, mundo, ventana)")
	_holder.free()
