extends "test_case.gd"
## Composer del dock: Enter envía; Ctrl+Enter y Shift+Enter bajan de línea; tipear / o @ abre la
## lista propia (filtra, flechas, Enter/Tab eligen, Esc cierra).

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

	# Tipear el prefijo abre la lista propia arriba del texto; filtra mientras se escribe.
	composer.call(&"set_commands", [{"name": "compact", "description": "Compacta el contexto"},
		{"name": "godot-code-review", "description": "Revisa código GDScript"}, {"name": "init", "description": "Crea CLAUDE.md"}])
	composer.set(&"mention_provider", func() -> Array[Dictionary]:
		return [{"label": "res://player.tscn", "insert": "res://player.tscn"}, {"label": "res://enemy.gd", "insert": "res://enemy.gd"}] as Array[Dictionary])
	var list: Node = composer.get(&"_suggestions")
	input.text = ""
	await _type(input, "/")
	assert_true(list.call(&"is_open"), "tipear / abre la lista")
	assert_eq(list.call(&"item_count"), 3, "con todos los comandos")
	await _type(input, "go")
	assert_eq(list.call(&"item_count"), 1, "filtra mientras se escribe")
	assert_eq((list.call(&"selected_item") as Dictionary).get("label"), "/godot-code-review", "y elige el primero")
	await _press(input, KEY_ENTER, false, false)
	assert_eq(sent.size(), 2, "con la lista abierta Enter no envía")
	assert_eq(input.text, "/godot-code-review ", "Enter reemplaza la palabra por el comando y un espacio")
	assert_false(list.call(&"is_open"), "y la cierra")
	input.undo()
	assert_eq(input.text, "/go", "un solo paso de deshacer")

	input.text = ""
	await _type(input, "/")
	await _press(input, KEY_DOWN, false, false)
	await _press(input, KEY_DOWN, false, false)
	assert_eq((list.call(&"selected_item") as Dictionary).get("label"), "/init", "las flechas mueven la selección")
	await _press(input, KEY_DOWN, false, false)
	assert_eq((list.call(&"selected_item") as Dictionary).get("label"), "/compact", "y dan la vuelta")
	await _press(input, KEY_ESCAPE, false, false)
	assert_false(list.call(&"is_open"), "Esc la cierra")
	await _type(input, "c")
	assert_false(list.call(&"is_open"), "y no se vuelve a abrir en la misma palabra")

	input.text = "mirá "
	input.set_caret_column(input.text.length())
	await _type(input, "@ene")
	assert_eq(list.call(&"item_count"), 1, "@ filtra nodos y archivos")
	await _press(input, KEY_TAB, false, false)
	assert_eq(input.text, "mirá @res://enemy.gd ", "Tab también elige")

	input.text = "a"
	input.set_caret_column(1)
	await _type(input, "/")
	assert_false(list.call(&"is_open"), "una / en el medio no abre comandos")
	composer.call(&"set_commands", [])
	input.text = ""
	await _type(input, "/")
	assert_true(list.call(&"is_open") and list.call(&"item_count") == 0, "sin comandos, la lista avisa por qué está vacía")
	await _press(input, KEY_ENTER, false, false)
	assert_eq(sent.size(), 3, "y Enter envía")
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


func test_prompt_history() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var path := "user://godot_agent_test/prompt_history.json"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	var composer: VBoxContainer = Composer.new()
	composer.call(&"setup", Color.ORANGE)
	composer.set(&"history_path", path)
	tree.root.add_child(composer)
	await tree.process_frame
	var sent: PackedStringArray = []
	composer.connect(&"submitted", func(text: String) -> void: sent.append(text))
	var input: CodeEdit = composer.get(&"_input")
	input.grab_focus()
	for prompt: String in ["primero", "segundo\nde dos líneas", "tercero"]:
		input.text = prompt
		await _press(input, KEY_ENTER, false, false)
		composer.call(&"clear")
	input.text = "borrador"
	input.set_caret_column(8)

	await _press(input, KEY_UP, false, false)
	assert_eq(input.text, "tercero", "arriba: el último enviado")
	await _press(input, KEY_UP, false, false)
	assert_eq(input.text, "segundo\nde dos líneas", "otra vez: el anterior, con el caret al final")
	assert_eq(input.get_caret_line(), 1, "caret en la última línea")
	await _press(input, KEY_UP, false, false)
	assert_eq(input.text, "segundo\nde dos líneas", "en la segunda línea, arriba mueve el caret")
	assert_eq(input.get_caret_line(), 0, "a la primera línea")
	await _press(input, KEY_UP, false, false)
	assert_eq(input.text, "primero", "desde la primera línea, sigue al anterior")
	await _press(input, KEY_UP, false, false)
	assert_eq(input.text, "primero", "no hay más viejos: se queda")
	await _press(input, KEY_DOWN, false, false)
	await _press(input, KEY_DOWN, false, false)
	assert_eq(input.text, "tercero", "abajo: los más nuevos")
	await _press(input, KEY_DOWN, false, false)
	assert_eq(input.text, "borrador", "después del más nuevo, el borrador")
	await _press(input, KEY_DOWN, false, false)
	assert_eq(input.text, "borrador", "abajo sin historial que recorrer no hace nada")

	# Repetir el último no lo duplica; el historial queda en disco para la próxima vez.
	input.text = "tercero"
	await _press(input, KEY_ENTER, false, false)
	assert_eq(sent.size(), 4, "envió")
	composer.free()
	var reopened: VBoxContainer = Composer.new()
	reopened.set(&"history_path", path)
	tree.root.add_child(reopened)
	await tree.process_frame
	assert_eq(reopened.get(&"_history"), PackedStringArray(["primero", "segundo\nde dos líneas", "tercero"]), "persiste, sin duplicar el último")
	reopened.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path.get_base_dir()))


## Con un turno en curso, Enter igual entrega el texto (el dock lo encola) y el placeholder lo avisa.
func test_enter_while_busy_and_insert_text() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var composer: VBoxContainer = Composer.new()
	composer.call(&"setup", Color.ORANGE)
	tree.root.add_child(composer)
	await tree.process_frame
	var sent: PackedStringArray = []
	composer.connect(&"submitted", func(text: String) -> void: sent.append(text))
	var input: CodeEdit = composer.get(&"_input")
	composer.call(&"set_busy", true)
	assert_true(input.placeholder_text.contains("queue"), "el placeholder avisa que encola")
	input.grab_focus()
	input.text = "después"
	input.set_caret_column(7)
	await _press(input, KEY_ENTER, false, false)
	assert_eq(sent, PackedStringArray(["después"]), "Enter entrega el texto con un turno en curso")
	composer.call(&"set_locked", "⏳ 3 h")
	await _press(input, KEY_ENTER, false, false)
	assert_eq(sent.size(), 1, "con el límite del plan no se entrega")
	composer.call(&"set_locked", "")
	composer.call(&"set_busy", false)
	assert_false(input.placeholder_text.contains("queue"), "placeholder normal")
	input.text = ""
	composer.call(&"insert_text", "editar esto")
	assert_eq(input.text, "editar esto", "insert_text en vacío")
	composer.call(&"insert_text", "y esto")
	assert_eq(input.text, "editar esto\ny esto", "insert_text después de lo escrito")
	composer.queue_free()
