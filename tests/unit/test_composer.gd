extends "test_case.gd"
## Composer del dock: Enter envía; Ctrl+Enter y Shift+Enter bajan de línea; tipear / o @ abre la
## lista y, abierta, Enter elige la opción.

const Composer := preload("res://addons/godot_agent/ui/dock/composer.gd")


func test_enter_sends_and_ctrl_enter_breaks_line() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var composer: VBoxContainer = Composer.new()
	composer.call(&"setup", Color.ORANGE)
	tree.root.add_child(composer)
	await tree.process_frame
	var sent: PackedStringArray = []
	composer.connect(&"submitted", func(text: String) -> void: sent.append(text))
	var input: CodeEdit = composer.get(&"_input")
	input.grab_focus()
	input.text = "hola"
	input.set_caret_column(4)

	await _press(input, KEY_ENTER, true, false)
	assert_eq(input.text, "hola\n", "Ctrl+Enter baja de línea")
	assert_eq(sent.size(), 0, "y no envía")
	input.insert_text_at_caret("mundo")
	await _press(input, KEY_ENTER, false, true)
	assert_eq(input.text, "hola\nmundo\n", "Shift+Enter también baja de línea")
	input.text = "hola\nmundo"
	input.set_caret_line(1)
	input.set_caret_column(5)
	await _press(input, KEY_ENTER, false, false)
	assert_eq(sent, PackedStringArray(["hola\nmundo"]), "Enter envía el texto")
	assert_eq(input.text, "hola\nmundo", "sin agregar un salto")
	await _press(input, KEY_KP_ENTER, false, false)
	assert_eq(sent.size(), 2, "el Enter del teclado numérico también")

	# Con el popup de / o @ abierto, Enter elige la opción (con su prefijo) y no envía.
	composer.call(&"set_commands", [{"name": "compact", "description": "Compacta el contexto"}])
	composer.set(&"mention_provider", func() -> Array[Dictionary]:
		return [{"label": "res://player.tscn", "insert": "res://player.tscn"}] as Array[Dictionary])
	# Tipear el prefijo abre la lista (el CodeEdit solo no lo hace).
	for case: Array in [["", "/", "/compact"], ["mirá ", "@", "mirá @res://player.tscn"]]:
		input.text = case[0]
		input.set_caret_column(input.text.length())
		await _type(input, case[1])
		assert_true(input.get_code_completion_selected_index() >= 0, "tipear «%s» abre la lista" % case[1])
		await _press(input, KEY_ENTER, false, false)
		assert_eq(sent.size(), 2, "con la lista abierta no envía (%s)" % case[1])
		assert_eq(input.text, case[2], "Enter elige la opción con su prefijo")
		await tree.process_frame
		assert_true(input.get_code_completion_selected_index() < 0, "elegida, la lista no se vuelve a abrir")
	input.text = "a/b"
	input.set_caret_column(1)
	await _type(input, "/")
	assert_true(input.get_code_completion_selected_index() < 0, "una / en el medio no abre comandos")
	composer.free()


func _type(input: CodeEdit, text: String) -> void:
	for c in text:
		var event := InputEventKey.new()
		event.pressed = true
		event.unicode = c.unicode_at(0)
		input.get_viewport().push_input(event)
		await (Engine.get_main_loop() as SceneTree).process_frame


func _press(input: CodeEdit, keycode: Key, ctrl: bool, shift: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.physical_keycode = keycode
	event.ctrl_pressed = ctrl
	event.shift_pressed = shift
	event.pressed = true
	input.get_viewport().push_input(event)
	var release := event.duplicate() as InputEventKey
	release.pressed = false
	input.get_viewport().push_input(release)
	await (Engine.get_main_loop() as SceneTree).process_frame
