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


## Un control sin viewport no está en pantalla y no tira error (m16-22).
func test_on_screen_without_viewport() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	await tree.process_frame
	var loose := Button.new()
	assert_false(GameUi._on_screen(loose), "fuera del árbol")
	var viewport := SubViewport.new()
	viewport.size = Vector2i(200, 100)
	tree.root.add_child(viewport)
	var button := Button.new()
	button.size = Vector2(50, 20)
	viewport.add_child(button)
	assert_true(GameUi._on_screen(button), "en el árbol, adentro del viewport")
	viewport.remove_child(button)
	assert_false(GameUi._on_screen(button), "sacado del árbol")
	button.free()
	loose.free()
	viewport.free()


## Un detector que tira un error en el código del harness se apaga (m16-22): con el debugger, cada
## error frena el juego, y uno por frame lo dejaba parado.
func test_detector_turns_off_after_a_harness_error() -> void:
	var detectors: Object = load("res://addons/godot_agent/playtest/runtime/detectors.gd").new()
	detectors.call(&"start")
	var calls := {"n": 0}
	var fine := func() -> void: calls.n += 1
	detectors.call(&"_guarded", "fine", fine)
	detectors.call(&"_guarded", "fine", fine)
	assert_eq(calls.n, 2, "uno sano corre siempre")
	# Un error de script en un archivo del harness, como lo ve el Logger (el runner falla el test con
	# uno de verdad; el camino real lo cubre run_check con el debugger).
	var errors: Logger = detectors.get(&"_errors")
	var broken := func() -> void:
		calls.n += 1
		errors._log_error("_on_screen", "res://addons/godot_agent/playtest/runtime/game_ui.gd", 212, "", "Cannot call method 'get_visible_rect' on a null value.", false, Logger.ERROR_TYPE_SCRIPT, [])
	detectors.call(&"_guarded", "broken", broken)
	detectors.call(&"_guarded", "broken", broken)
	assert_eq(calls.n, 3, "el que falló no corre más")
	var off: Dictionary = detectors.get(&"off")
	assert_true(off.has("broken") and str(off.broken).contains("game_ui.gd:212"), "queda apagado con el error · %s" % off)
	var game_code := func() -> void:
		errors._log_error("_ready", "res://player.gd", 3, "", "boom", false, Logger.ERROR_TYPE_SCRIPT, [])
	detectors.call(&"_guarded", "game_code", game_code)
	assert_false(off.has("game_code"), "un error del juego no lo apaga")
	var warning := func() -> void:
		errors._log_error("f", "res://addons/godot_agent/x.gd", 1, "", "w", false, Logger.ERROR_TYPE_WARNING, [])
	detectors.call(&"_guarded", "warning", warning)
	assert_false(off.has("warning"), "un warning del harness no lo apaga")
	detectors.call(&"stop")
