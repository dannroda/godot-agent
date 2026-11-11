extends "test_case.gd"
## m11-37: el nodo del juego bajo un punto de la captura: Controles (el que se dibuja último, no el
## fondo), Sprite2D/Polygon2D del mundo 2D con cámara, y nada si el punto cae en el vacío.

const PointPick := preload("res://addons/godot_agent/playtest/runtime/point_pick.gd")


func test_controls_and_2d() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	await tree.process_frame  # la raíz entra al árbol recién en el primer frame
	var viewport := SubViewport.new()
	viewport.size = Vector2i(400, 300)
	tree.root.add_child(viewport)
	var scene := Node2D.new()
	scene.name = "Game"
	viewport.add_child(scene)
	var sprite := Sprite2D.new()
	sprite.name = "Coin"
	sprite.texture = ImageTexture.create_from_image(Image.create_empty(20, 20, false, Image.FORMAT_RGBA8))
	sprite.position = Vector2(100, 200)
	scene.add_child(sprite)
	var polygon := Polygon2D.new()
	polygon.name = "Ground"
	polygon.polygon = PackedVector2Array([Vector2(0, 250), Vector2(400, 250), Vector2(400, 300), Vector2(0, 300)])
	scene.add_child(polygon)
	var hud := CanvasLayer.new()
	hud.name = "HUD"
	scene.add_child(hud)
	var background := ColorRect.new()
	background.name = "Background"
	background.position = Vector2.ZERO
	background.size = Vector2(400, 300)
	hud.add_child(background)
	var menu := Control.new()  # un Container reacomodaría a los hijos
	menu.name = "Menu"
	menu.position = Vector2(10, 80)
	menu.size = Vector2(200, 100)
	hud.add_child(menu)
	var button := Button.new()
	button.name = "Start"
	button.position = Vector2(0, 0)
	button.size = Vector2(200, 40)
	menu.add_child(button)
	var hidden := Button.new()
	hidden.name = "Hidden"
	hidden.position = Vector2(0, 50)
	hidden.size = Vector2(200, 40)
	hidden.visible = false
	menu.add_child(hidden)
	await tree.process_frame

	var size := Vector2(viewport.size)
	var start := PointPick.at(viewport, scene, Vector2(50, 100) / size)
	assert_eq(start.get("node", {}).get("path"), "HUD/Menu/Start", "el botón bajo el punto · %s" % [start])
	assert_eq(start.node.kind, "control", "es un Control")
	assert_eq(start.node.point, [50, 100], "con el punto en píxeles del viewport")
	var under_hidden := PointPick.at(viewport, scene, Vector2(50, 150) / size)
	assert_eq(under_hidden.get("node", {}).get("path"), "HUD/Menu", "un botón oculto no se señala: queda el contenedor · %s" % [under_hidden])
	var coin := PointPick.at(viewport, scene, Vector2(100, 200) / size)
	assert_eq(coin.get("node", {}).get("path"), "Coin", "el fondo a pantalla completa no tapa el Sprite2D del mundo · %s" % [coin])
	assert_eq(coin.node.kind, "2d", "es del mundo 2D")
	var ground := PointPick.at(viewport, scene, Vector2(300, 280) / size)
	assert_eq(ground.get("node", {}).get("path"), "Ground", "el Polygon2D por su polígono · %s" % [ground])
	var empty := PointPick.at(viewport, scene, Vector2(300, 20) / size)
	assert_eq(empty.get("node", {}).get("path"), "HUD/Background", "en el vacío queda el fondo · %s" % [empty])
	background.visible = false
	assert_true(PointPick.at(viewport, scene, Vector2(300, 20) / size).is_empty(), "sin fondo y sin nada: vacío")
	assert_true(PointPick.at(null, scene, Vector2.ZERO).is_empty() and PointPick.at(viewport, null, Vector2.ZERO).is_empty(), "sin viewport o sin escena: vacío")
	viewport.free()


func test_camera_2d_moves_the_world() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	await tree.process_frame
	var viewport := SubViewport.new()
	viewport.size = Vector2i(400, 300)
	tree.root.add_child(viewport)
	var scene := Node2D.new()
	viewport.add_child(scene)
	var camera := Camera2D.new()
	camera.position = Vector2(1000, 1000)
	scene.add_child(camera)
	camera.make_current()
	var sprite := Sprite2D.new()
	sprite.name = "Far"
	sprite.texture = ImageTexture.create_from_image(Image.create_empty(40, 40, false, Image.FORMAT_RGBA8))
	sprite.position = Vector2(1000, 1000)  # el centro de la cámara: el centro de la pantalla
	scene.add_child(sprite)
	await tree.process_frame
	await tree.process_frame
	var hit := PointPick.at(viewport, scene, Vector2(0.5, 0.5))
	assert_eq(hit.get("node", {}).get("path"), "Far", "con cámara, el centro de la pantalla es el sprite · %s" % [hit])
	assert_true(PointPick.at(viewport, scene, Vector2(0.05, 0.05)).is_empty(), "la esquina no toca nada")
	viewport.free()


static func _button(parent: Node, node_name: String, position: Vector2, size: Vector2) -> Button:
	var button := Button.new()
	button.name = node_name
	button.position = position
	button.size = size
	parent.add_child(button)
	return button


static func _body(parent: Node, node_name: String, position: Vector2, size: Vector2, area: bool = false) -> CollisionObject2D:
	var body: CollisionObject2D = Area2D.new() if area else StaticBody2D.new()
	body.name = node_name
	body.position = position
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = size
	shape.shape = rect
	body.add_child(shape)
	parent.add_child(body)
	return body


static func _path(hit: Dictionary) -> Variant:
	return hit.get("node", {}).get("path")


## La revisión m13-12-26 (#3): con stretch, uv × visible_rect ya está en coordenadas base y la
## transformación final se aplicaba de nuevo. Con stretch de verdad en la ventana raíz: canvas_items con
## barras (ventana 800×450, base 400×300, keep) y viewport.
func test_stretch_of_the_root_window() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	await tree.process_frame
	var root := tree.root
	var saved := [root.size, root.content_scale_mode, root.content_scale_aspect, root.content_scale_size]
	var scene := Node2D.new()
	scene.name = "StretchGame"
	root.add_child(scene)
	var layer := CanvasLayer.new()  # encima de lo que el runner tenga en la raíz
	layer.name = "Hud"
	layer.layer = 100
	scene.add_child(layer)
	_button(layer, "Btn", Vector2(300, 200), Vector2(50, 50))
	var low := Panel.new()
	low.name = "LowPanel"
	low.position = Vector2(90, 90)
	low.size = Vector2(80, 80)
	layer.add_child(low)
	root.size = Vector2i(800, 450)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
	root.content_scale_size = Vector2i(400, 300)
	await tree.process_frame
	await tree.process_frame
	# La captura es la ventana: el punto base (325, 225) se ve en final × (325, 225), con las barras.
	var window_point := root.get_final_transform() * Vector2(325, 225)
	assert_true(root.get_final_transform().origin.x > 0.0, "keep con 800×450 deja barras a los costados · %s" % [root.get_final_transform()])
	var hit := PointPick.at(root, scene, window_point / Vector2(root.size))
	assert_eq(_path(hit), "Hud/Btn", "canvas_items: el botón bajo el punto, no LowPanel · %s" % [hit])
	assert_eq(hit.get("node", {}).get("point"), [325, 225], "el punto en coordenadas base")
	var panel := PointPick.at(root, scene, (root.get_final_transform() * Vector2(120, 120)) / Vector2(root.size))
	assert_eq(_path(panel), "Hud/LowPanel", "y el panel en el suyo · %s" % [panel])
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
	await tree.process_frame
	await tree.process_frame
	# En modo viewport se dibuja al tamaño base: la captura ya está en esas coordenadas.
	var viewport_hit := PointPick.at(root, scene, Vector2(325, 225) / root.get_visible_rect().size)
	assert_eq(_path(viewport_hit), "Hud/Btn", "viewport: el botón · %s" % [viewport_hit])
	root.size = saved[0]
	root.content_scale_mode = saved[1]
	root.content_scale_aspect = saved[2]
	root.content_scale_size = saved[3]
	scene.free()
	await tree.process_frame


## #13: un CanvasLayer oculto no se señala, y encima va lo de la capa más alta y el z_index mayor, no
## lo último del árbol.
func test_hidden_layers_and_draw_order() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	await tree.process_frame
	var viewport := SubViewport.new()
	viewport.size = Vector2i(400, 300)
	tree.root.add_child(viewport)
	var scene := Node2D.new()
	scene.name = "Game"
	viewport.add_child(scene)
	var top := CanvasLayer.new()
	top.name = "Top"
	top.layer = 5
	scene.add_child(top)
	_button(top, "TopBtn", Vector2(100, 100), Vector2(40, 40))
	var low := Panel.new()  # después en el árbol, pero en la capa 0
	low.name = "LowPanel"
	low.position = Vector2(90, 90)
	low.size = Vector2(80, 80)
	scene.add_child(low)
	var pause := CanvasLayer.new()
	pause.name = "Pause"
	pause.layer = 10
	pause.visible = false
	scene.add_child(pause)
	_button(pause, "Resume", Vector2(0, 0), Vector2(400, 200))
	var raised := _button(scene, "Raised", Vector2(250, 220), Vector2(60, 40))
	raised.z_index = 3
	_button(scene, "Later", Vector2(240, 210), Vector2(80, 60))
	await tree.process_frame
	var size := Vector2(viewport.size)
	assert_eq(_path(PointPick.at(viewport, scene, Vector2(120, 120) / size)), "Top/TopBtn", "la capa 5 tapa a la 0 aunque esté antes en el árbol")
	assert_eq(_path(PointPick.at(viewport, scene, Vector2(30, 30) / size)), null, "el botón de un CanvasLayer oculto no se señala")
	assert_eq(_path(PointPick.at(viewport, scene, Vector2(270, 230) / size)), "Raised", "z_index 3 tapa al que sigue en el árbol")
	viewport.free()


## #30: cuerpos en un CanvasLayer con offset, ocultos, y áreas grandes que no tapan lo de adentro.
func test_physics_layers_hidden_and_big_areas() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	await tree.process_frame
	var viewport := SubViewport.new()
	viewport.size = Vector2i(400, 300)
	tree.root.add_child(viewport)
	var scene := Node2D.new()
	scene.name = "Game"
	viewport.add_child(scene)
	var shifted := CanvasLayer.new()
	shifted.name = "L2"
	shifted.offset = Vector2(200, 0)
	scene.add_child(shifted)
	_body(shifted, "Body", Vector2(20, 250), Vector2(20, 20))
	_body(scene, "Level", Vector2(200, 150), Vector2(400, 300), true)  # un trigger del nivel entero
	_body(scene, "Room", Vector2(100, 100), Vector2(120, 120), true)
	_body(scene, "Player", Vector2(100, 100), Vector2(20, 30))
	var ghost := _body(scene, "Ghost", Vector2(300, 60), Vector2(30, 30))
	ghost.visible = false
	for i in 3:
		await tree.physics_frame
		await tree.process_frame
	var size := Vector2(viewport.size)
	assert_eq(_path(PointPick.at(viewport, scene, Vector2(220, 250) / size)), "L2/Body", "el cuerpo de un CanvasLayer con offset, donde se dibuja")
	assert_eq(_path(PointPick.at(viewport, scene, Vector2(100, 100) / size)), "Player", "el jugador, no el área que lo contiene ni el trigger del nivel")
	assert_eq(_path(PointPick.at(viewport, scene, Vector2(60, 60) / size)), "Room", "dentro del cuarto, sin nadie: el cuarto")
	assert_eq(_path(PointPick.at(viewport, scene, Vector2(300, 60) / size)), "Level", "un cuerpo oculto no se señala: queda el trigger grande")
	viewport.free()


## #30: un HUD fuera de la escena (un autoload) va con ruta absoluta, no «../X»; un SubViewportContainer
## (pixel art) se mira por dentro con su stretch_shrink.
func test_outside_the_scene_and_subviewport_container() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	await tree.process_frame
	var viewport := SubViewport.new()
	viewport.name = "PickHost"
	viewport.size = Vector2i(400, 300)
	tree.root.add_child(viewport)
	var hud := CanvasLayer.new()
	hud.name = "Hud"
	viewport.add_child(hud)
	_button(hud, "Menu", Vector2(350, 0), Vector2(50, 30))
	var scene := Control.new()
	scene.name = "Game"
	scene.size = Vector2(400, 300)
	viewport.add_child(scene)
	var container := SubViewportContainer.new()
	container.name = "Screen"
	container.stretch = true
	container.stretch_shrink = 2
	container.size = Vector2(400, 300)
	scene.add_child(container)
	var pixels := SubViewport.new()
	pixels.name = "Pixels"
	container.add_child(pixels)
	var world := Node2D.new()
	world.name = "World"
	pixels.add_child(world)
	var coin := Sprite2D.new()
	coin.name = "Coin"
	coin.texture = ImageTexture.create_from_image(Image.create_empty(10, 10, false, Image.FORMAT_RGBA8))
	coin.position = Vector2(50, 40)  # en el viewport de 200×150: en pantalla (100, 80)
	world.add_child(coin)
	await tree.process_frame
	await tree.process_frame
	var size := Vector2(viewport.size)
	var menu := PointPick.at(viewport, scene, Vector2(370, 10) / size)
	assert_eq(_path(menu), String(viewport.get_path()) + "/Hud/Menu", "fuera de la escena: ruta absoluta · %s" % [menu])
	var inner := PointPick.at(viewport, scene, Vector2(100, 80) / size)
	assert_eq(_path(inner), "Screen/Pixels/World/Coin", "dentro del SubViewportContainer · %s" % [inner])
	assert_eq(inner.get("node", {}).get("point"), [50, 40], "con el punto en las coordenadas de su viewport")
	assert_eq(_path(PointPick.at(viewport, scene, Vector2(300, 250) / size)), "Screen", "sin nada adentro queda el contenedor como fondo")
	viewport.free()
