extends "test_case.gd"
## Revisión m13-12-26 (#30): en el visor en modo señalar, un clic señala; un arrastre que vuelve cerca
## del punto de partida, el doble clic (zoom) y un soltar sin press propio no. El temblor de un clic no
## mueve la imagen.

const ImageViewer := preload("res://addons/godot_agent/ui/image_viewer.gd")


func _viewer(picked: Array) -> AcceptDialog:
	var viewer: AcceptDialog = ImageViewer.new()
	viewer.set(&"_image", Image.create_empty(100, 100, false, Image.FORMAT_RGBA8))
	viewer.set(&"_on_pick", func(uv: Vector2) -> void: picked.append(uv))
	return viewer


static func _button(viewer: AcceptDialog, at: Vector2, pressed: bool, double: bool = false) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.position = at
	event.pressed = pressed
	event.double_click = double
	viewer.call(&"_on_canvas_input", event)


static func _move(viewer: AcceptDialog, to: Vector2, relative: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = to
	event.relative = relative
	viewer.call(&"_on_canvas_input", event)


func test_click_picks_and_drags_do_not() -> void:
	var picked: Array = []
	var viewer := _viewer(picked)
	_button(viewer, Vector2(10, 10), true)
	_move(viewer, Vector2(12, 10), Vector2(2, 0))
	assert_eq(viewer.get(&"_offset"), Vector2.ZERO, "el temblor de un clic no mueve la imagen")
	_button(viewer, Vector2(12, 10), false)
	assert_eq(picked, [Vector2(0.12, 0.1)], "un clic con temblor señala")
	viewer.free()

	picked.clear()
	viewer = _viewer(picked)
	_button(viewer, Vector2(10, 10), true)
	_move(viewer, Vector2(13, 10), Vector2(3, 0))
	_move(viewer, Vector2(10, 10), Vector2(-3, 0))
	_button(viewer, Vector2(10, 10), false)
	assert_true(picked.is_empty(), "un arrastre que vuelve al punto de partida no señala · %s" % [picked])
	_button(viewer, Vector2(20, 20), true)
	_move(viewer, Vector2(40, 20), Vector2(20, 0))
	assert_eq(viewer.get(&"_offset"), Vector2(20, 0), "pasado el margen, la imagen se mueve con todo lo arrastrado")
	_button(viewer, Vector2(40, 20), false)
	assert_true(picked.is_empty(), "un arrastre largo no señala")
	viewer.free()


func test_double_click_and_stray_release_do_not_pick() -> void:
	var picked: Array = []
	var viewer := _viewer(picked)
	_button(viewer, Vector2(30, 30), false)
	assert_true(picked.is_empty(), "soltar sin haber apretado en el visor no señala")
	_button(viewer, Vector2(30, 30), true, true)
	_button(viewer, Vector2(30, 30), false)
	assert_true(picked.is_empty(), "el doble clic cambia el zoom y no señala · %s" % [picked])
	viewer.free()
