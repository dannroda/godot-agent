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


## Archivos copiados en un gestor de archivos: `file://` (con %20) o rutas absolutas, una por línea.
## Cualquier otra cosa es texto y se pega como siempre.
func test_clipboard_file_paths() -> void:
	var dir := OS.get_user_data_dir().path_join("clipboard test")
	DirAccess.make_dir_recursive_absolute(dir)
	var png := dir.path_join("a b.png")
	var txt := dir.path_join("notas.txt")
	Image.create(4, 4, false, Image.FORMAT_RGB8).save_png(png)
	FileAccess.open(txt, FileAccess.WRITE).store_string("x")
	var uri := "file://" + png.uri_encode().replace("%2F", "/")
	assert_eq(Composer.clipboard_file_paths(uri), PackedStringArray([png]), "file:// con espacios")
	assert_eq(Composer.clipboard_file_paths("%s\n%s\n" % [png, txt]), PackedStringArray([png, txt]), "rutas absolutas")
	assert_eq(Composer.clipboard_file_paths("hola\n" + png), PackedStringArray(), "una línea de texto: se pega el texto")
	assert_eq(Composer.clipboard_file_paths(dir.path_join("no-existe.png")), PackedStringArray(), "archivo que no existe")
	assert_eq(Composer.clipboard_file_paths("res://icon.svg"), PackedStringArray(), "res:// es texto")
	assert_eq(Composer.clipboard_file_paths(""), PackedStringArray(), "vacío")


## La opción "default" de Claude Code muestra el modelo que usa: «Opus 5.5 (default)».
func test_model_label() -> void:
	var options := [
		{"value": "default", "name": "Default (recommended)", "description": "Opus 5.5"},
		{"value": "opus", "name": "Opus 5.5", "description": "For complex work"},
		{"value": "haiku", "name": "Haiku 5.5", "description": "Fastest"},
	]
	assert_eq(Composer.model_label(options[0], options), "Opus 5.5 (default)", "default con el modelo")
	assert_eq(Composer.model_label(options[1], options), "Opus 5.5", "las demás, con su nombre")
	var unknown := [{"value": "default", "name": "Default (recommended)", "description": "Uses the best model"}, options[1]]
	assert_eq(Composer.model_label(unknown[0], unknown), "Default (recommended)", "descripción que no es un modelo: el nombre")
	var tree := Engine.get_main_loop() as SceneTree
	var composer: VBoxContainer = Composer.new()
	composer.call(&"setup", Color.ORANGE)
	tree.root.add_child(composer)
	await tree.process_frame
	composer.call(&"set_model_option", {"currentValue": "default", "options": options})
	var button: OptionButton = composer.get(&"_model_button")
	assert_eq(button.text, "Opus 5.5 (default)", "el selector muestra el modelo")
	assert_eq(button.get_item_tooltip(0), "Default (recommended)", "y el nombre original en el tooltip")
	composer.queue_free()


## Arrastrar archivos del FileSystem al texto los adjunta (las carpetas se ignoran); el texto
## arrastrado lo sigue insertando el TextEdit.
func test_drop_files() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var composer: VBoxContainer = Composer.new()
	composer.call(&"setup", Color.ORANGE)
	tree.root.add_child(composer)
	# El root headless mide 64x64: el texto tiene que quedar adentro.
	composer.position = Vector2.ZERO
	composer.size = Vector2(60, 60)
	await tree.process_frame
	var attached: Array[PackedStringArray] = []
	composer.connect(&"files_attached", func(paths: PackedStringArray) -> void: attached.append(paths))
	var input: CodeEdit = composer.get(&"_input")
	await _drag_onto(input, {"type": "files_and_dirs", "files": PackedStringArray(["res://dir/", "res://c.tscn"])})
	await _drag_onto(input, {"type": "files", "files": PackedStringArray(["res://a.gd", "res://b.png"]), "from": null})
	assert_eq(attached, [PackedStringArray(["res://c.tscn"]), PackedStringArray(["res://a.gd", "res://b.png"])] as Array[PackedStringArray], "adjunta sin carpetas")
	await _drag_onto(input, "texto")
	assert_eq(input.text, "texto", "el texto arrastrado lo inserta el TextEdit")
	composer.queue_free()


func _drag_onto(target: Control, data: Variant) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	# Una esquina: el centro puede caer fuera del root headless (64x64).
	var center := target.get_global_rect().position + Vector2(10, 10)
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	tree.root.push_input(press)
	target.force_drag(data, null)
	var motion := InputEventMouseMotion.new()
	motion.position = center
	motion.button_mask = MOUSE_BUTTON_MASK_LEFT
	tree.root.push_input(motion)
	await tree.process_frame
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	release.position = center
	tree.root.push_input(release)
	await tree.process_frame


## m12-15: sin agentes el composer no se puede usar y dice qué falta; set_enabled no lo reabre.
func test_unavailable_without_agent() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var composer: VBoxContainer = Composer.new()
	composer.call(&"setup", Color.ORANGE)
	tree.root.add_child(composer)
	await tree.process_frame
	var input: CodeEdit = composer.get(&"_input")
	composer.call(&"set_unavailable", "Add an agent to start")
	composer.call(&"set_enabled", true)
	assert_false(input.editable, "apagado aunque la sesión no esté arrancando")
	assert_eq(input.placeholder_text, "Add an agent to start", "dice qué falta")
	composer.call(&"set_unavailable", "")
	assert_true(input.editable, "con agente vuelve")
	assert_false(input.placeholder_text == "Add an agent to start", "y su placeholder de siempre")
	composer.free()
