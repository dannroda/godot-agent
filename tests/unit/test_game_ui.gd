extends "test_case.gd"
## La UI del juego que ve el Playtest (m15-09).

const GameUi := preload("res://addons/godot_agent/playtest/runtime/game_ui.gd")


## Un movimiento relativo encima de un control que frena el mouse no le llega al juego: look_at decía
## que el juego no giraba la vista (m16-08).
func test_free_point() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	await tree.process_frame  # la raíz entra al árbol recién en el primer frame
	var viewport := SubViewport.new()
	viewport.size = Vector2i(400, 300)
	tree.root.add_child(viewport)
	var hud := CanvasLayer.new()
	viewport.add_child(hud)
	var overlay := ColorRect.new()
	overlay.position = Vector2(150, 100)
	overlay.size = Vector2(100, 100)
	hud.add_child(overlay)
	var label := Label.new()
	label.position = Vector2(0, 0)
	label.size = Vector2(100, 50)
	hud.add_child(label)
	assert_eq(GameUi.free_point(viewport, Vector2(20, 20)), Vector2(20, 20), "sobre un Label (no frena el mouse): el mismo punto")
	var moved := GameUi.free_point(viewport, Vector2(200, 150))
	assert_true(not Rect2(overlay.position, overlay.size).has_point(moved), "sobre el overlay: otro punto · %s" % moved)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	assert_eq(GameUi.free_point(viewport, Vector2(200, 150)), Vector2(200, 150), "overlay que deja pasar el mouse: el mismo punto")
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.visible = false
	assert_eq(GameUi.free_point(viewport, Vector2(200, 150)), Vector2(200, 150), "overlay oculto: el mismo punto")
	viewport.free()
