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
