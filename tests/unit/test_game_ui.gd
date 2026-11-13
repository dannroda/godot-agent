extends "test_case.gd"
## La UI del juego que ve el Playtest (m15-09).

const GameUi := preload("res://addons/godot_agent/playtest/runtime/game_ui.gd")
const Probe := preload("res://addons/godot_agent/playtest/runtime/playtest_probe.gd")
const RunTools := preload("res://addons/godot_agent/mcp/tools/run_tools.gd")


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


## m16-23: un doble click llega a _gui_input de un Control como lo manda el sistema: un click y otro
## con double_click en la pulsación. Por game_ui_act y por los pasos de game_input (`double: true`).
func test_double_click_reaches_gui_input() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	await tree.process_frame
	var viewport := SubViewport.new()
	viewport.size = Vector2i(400, 300)
	tree.root.add_child(viewport)
	var row := PanelContainer.new()
	row.set_script(_recorder())
	row.position = Vector2(100, 100)
	row.size = Vector2(120, 40)
	viewport.add_child(row)
	await tree.process_frame
	var ui := GameUi.new(viewport)
	ui._push_mouse(row, MOUSE_BUTTON_LEFT, true)
	assert_eq(row.get(&"presses"), [false, true], "game_ui_act double_click: primero un click, después la pulsación con double_click")
	row.set(&"presses", [])
	ui._push_mouse(row, MOUSE_BUTTON_LEFT)
	assert_eq(row.get(&"presses"), [false], "un click no es doble")
	# game_input: los pasos que arma normalize_steps, convertidos por la sonda y empujados al viewport.
	row.set(&"presses", [])
	var steps: Array = []
	assert_eq(RunTools.normalize_steps([{"click": [160, 120], "double": true}], steps), "", "paso con double")
	var probe: Node = Probe.new()
	for step: Dictionary in steps:
		var event: InputEvent = probe.call(&"_event", step)
		viewport.push_input(event, true)
	probe.free()
	assert_eq(row.get(&"presses"), [false, true], "game_input {click, double: true}: le llega el doble click")
	viewport.free()


func test_double_click_steps() -> void:
	var steps: Array = []
	assert_eq(RunTools.normalize_steps([{"click": [10, 20], "double": true}, {"action": "ui_accept"}], steps), "", "válido")
	var buttons := steps.filter(func(step: Dictionary) -> bool: return step.kind == "mouse_button")
	assert_eq(buttons.map(func(step: Dictionary) -> Array: return [step.pressed, step.get("double", false)]), [[true, false], [false, false], [true, true], [false, false]], "apretar, soltar, apretar con double, soltar")
	assert_true(absf(float(buttons[3].t) - 3 * RunTools.DOUBLE_GAP_S) < 0.001, "cuatro eventos seguidos, dentro de los 400 ms de Godot")
	assert_true(float(steps[steps.size() - 2].t) > float(buttons[3].t), "el paso siguiente va después del doble click")
	steps.clear()
	assert_eq(RunTools.normalize_steps([{"frame": 5, "click": [10, 20], "double": true}], steps), "", "por frame")
	assert_eq(steps.filter(func(step: Dictionary) -> bool: return step.kind == "mouse_button").map(func(step: Dictionary) -> int: return step.frame), [5, 7, 9, 11], "un evento cada DOUBLE_GAP_FRAMES")
	steps.clear()
	assert_eq(RunTools.normalize_steps([{"click": [10, 20], "double": true, "pressed": true}], steps), "", "solo la pulsación")
	assert_eq(steps[1].get("double"), true, "marcada como segunda de un doble")
	assert_true(RunTools.normalize_steps([{"action": "ui_accept", "double": true}], []).contains("click"), "double sin click")
	assert_true(RunTools.normalize_steps([{"click": [1, 2], "double": "yes"}], []).contains("true or false"), "double no booleano")


func _recorder() -> GDScript:
	var script := GDScript.new()
	script.source_code = "extends PanelContainer\nvar presses: Array = []\nfunc _gui_input(event: InputEvent) -> void:\n\tif event is InputEventMouseButton and event.pressed:\n\t\tpresses.append(event.double_click)\n"
	script.reload()
	return script


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
	var calls := {"n": 0}
	var fine := func() -> void: calls.n += 1
	detectors.call(&"_guarded", "fine", fine)
	detectors.call(&"_guarded", "fine", fine)
	assert_eq(calls.n, 2, "uno sano corre siempre")
	# El aviso del editor llega con el juego parado en el error, o sea adentro del detector (el runner
	# falla el test con un error de verdad; el camino real lo cubre run_check con el debugger).
	var reason := "Cannot call method 'get_visible_rect' on a null value. (res://addons/godot_agent/playtest/runtime/game_ui.gd:212)"
	var broken := func() -> void:
		calls.n += 1
		detectors.call(&"harness_error", reason)
	detectors.call(&"_guarded", "broken", broken)
	detectors.call(&"_guarded", "broken", broken)
	assert_eq(calls.n, 3, "el que falló no corre más")
	var off: Dictionary = detectors.get(&"off")
	assert_eq(off.get("broken"), reason, "queda apagado con el error")
	detectors.call(&"_guarded", "after", fine)
	assert_false(off.has("after"), "el aviso no queda pegado para el detector siguiente")
	# Un aviso que llegó fuera de un detector (otro código de la probe) no apaga al que corre después.
	detectors.call(&"harness_error", reason)
	detectors.call(&"_guarded", "later", fine)
	assert_false(off.has("later"), "un aviso viejo no apaga al siguiente")
