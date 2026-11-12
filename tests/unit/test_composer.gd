extends "test_case.gd"
## Composer del dock: Enter envía; Ctrl+Enter envía y pide seguir al agente; Shift+Enter baja de línea; tipear / o @ abre la
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
	var follows: Array = []
	composer.connect(&"follow_requested", func() -> void: follows.append(sent.size()))
	var input: CodeEdit = composer.get(&"_input")
	input.grab_focus()
	input.text = "hola"
	input.set_caret_column(4)

	# Ctrl+Enter envía y pide seguir al agente, antes de enviar (m11-67).
	await _press(input, KEY_ENTER, true, false)
	assert_eq(sent, PackedStringArray(["hola"]), "Ctrl+Enter envía")
	assert_eq(follows, [0], "y pide seguir al agente antes de enviar")
	input.text = ""
	await _press(input, KEY_ENTER, true, false)
	assert_eq(follows.size(), 1, "Ctrl+Enter sin texto no hace nada")
	sent.clear()
	input.text = "hola"
	input.set_caret_column(4)
	await _press(input, KEY_ENTER, false, true)
	assert_eq(input.text, "hola\n", "Shift+Enter baja de línea")
	assert_eq(sent.size(), 0, "y no envía")
	input.insert_text_at_caret("mundo")
	input.text = "hola\nmundo"
	input.set_caret_line(1)
	input.set_caret_column(5)
	await _press(input, KEY_ENTER, false, false)
	assert_eq(sent, PackedStringArray(["hola\nmundo"]), "Enter envía el texto")
	assert_eq(follows.size(), 1, "Enter solo no pide seguir")
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
	# Ancho fijo: con el mínimo de la fila, «segundo» se partía en dos líneas visuales y arriba se movía adentro.
	composer.custom_minimum_size.x = 400
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
	var busy := [true]  # las lambdas capturan por valor: la lista se muta
	composer.set(&"busy_provider", func() -> bool: return busy[0])
	composer.call(&"refresh_state")
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
	busy[0] = false
	composer.call(&"refresh_state")
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


## m12-18: un «+» en lugar de @, imagen y /; el contexto en la fila solo casi lleno.
func test_add_menu_and_meter() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var composer: VBoxContainer = Composer.new()
	composer.call(&"setup", Color.ORANGE)
	tree.root.add_child(composer)
	await tree.process_frame
	var menu: MenuButton = composer.get(&"_add_menu")
	assert_eq(menu.get_popup().item_count, 5, "nodo o archivo, imagen, comando, planificar (m11-58) y receta (m11-30)")
	var plan_index := menu.get_popup().get_item_index(3)
	assert_true(menu.get_popup().is_item_disabled(plan_index), "«Planificar» apagado sin sesión libre")
	assert_false((composer.get(&"_plan_button") as Control).visible, "y sin el ícono")
	composer.call(&"set_plan_available", true)
	assert_false(menu.get_popup().is_item_disabled(plan_index), "con la sesión libre se ofrece")
	await tree.process_frame
	assert_true((composer.get(&"_plan_button") as Control).visible, "con su ícono al lado del modo")
	composer.call(&"set_plan_available", false)
	assert_false((composer.get(&"_mention_button") as Control).visible, "sin el @ suelto")
	var input: CodeEdit = composer.get(&"_input")
	menu.get_popup().id_pressed.emit(0)
	assert_eq(input.text, "@", "«Nodo o archivo» escribe @")
	composer.call(&"set_usage", 38000, 200000)
	assert_eq((composer.get(&"_meter") as Label).text, "19 %", "el porcentaje siempre a la vista, como en la pantalla propuesta")
	composer.call(&"set_usage", 170000, 200000)
	assert_eq((composer.get(&"_meter") as Label).text, "85 %", "85 %")
	assert_true((composer.get(&"_meter") as Label).tooltip_text.contains("170k / 200k"), "los tokens en el tooltip")
	# El ancho del medidor no cambia con el porcentaje (m12-51): si cambiaba, la fila se recompactaba
	# con cada usage_update y todo se corría bajo el mouse (el tooltip abierto se cerraba).
	# Con márgenes en el estilo, como el tema del editor (m12-53: crecía 7 px igual en 4.8-beta3).
	var padded := StyleBoxFlat.new()
	padded.content_margin_left = 6
	padded.content_margin_right = 6
	(composer.get(&"_meter") as Label).add_theme_stylebox_override(&"normal", padded)
	var widths: Array[float] = []
	for used: int in [2000, 20000, 200000]:
		composer.call(&"set_usage", used, 200000)
		widths.append((composer.get(&"_meter") as Label).get_combined_minimum_size().x)
	assert_eq(widths[0], widths[2], "«1 %» pide lo mismo que «100 %»: " + str(widths))
	assert_eq(widths[1], widths[2], "y «10 %» también")
	composer.call(&"set_screenshot_available", false)
	assert_true(menu.get_popup().is_item_disabled(1), "sin imágenes, la imagen apagada")
	composer.free()
	const QuotaRing := preload("res://addons/godot_agent/ui/dock/quota_ring.gd")
	assert_eq(QuotaRing.context_line(38000, 200000), "Context: 38k of 200k (19 %)", "el contexto en el tooltip del anillo")


func test_height_follows_text_and_grip() -> void:
	assert_eq(Composer.target_height(10.0, 0.0, 1000.0, 72.0), 72.0, "nunca menos que el mínimo")
	assert_eq(Composer.target_height(300.0, 0.0, 1000.0, 72.0), 300.0, "sigue al texto")
	assert_eq(Composer.target_height(900.0, 0.0, 1000.0, 72.0), 400.0, "solo hasta el 40 % del dock")
	assert_eq(Composer.target_height(900.0, 650.0, 1000.0, 72.0), 650.0, "a mano manda el alto fijado")
	assert_eq(Composer.target_height(10.0, 900.0, 1000.0, 72.0), 700.0, "a mano, hasta el 70 %")
	assert_eq(Composer.target_height(10.0, 0.0, 50.0, 72.0), 72.0, "un dock muy chico no baja del mínimo")

	var tree := Engine.get_main_loop() as SceneTree
	var holder := Control.new()
	holder.size = Vector2(400, 1000)
	tree.root.add_child(holder)
	var composer: VBoxContainer = Composer.new()
	composer.call(&"setup", Color.ORANGE)
	holder.add_child(composer)
	composer.size = Vector2(400, 200)
	await tree.process_frame
	composer.call(&"set_manual_height", 0.0)
	var input: CodeEdit = composer.get(&"_input")
	var resting := input.custom_minimum_size.y
	assert_eq(resting, 72.0, "vacío: el alto de reposo")
	composer.call(&"insert_text", "\n".join(range(30).map(func(i: int) -> String: return "línea %d" % i)))
	assert_eq(input.custom_minimum_size.y, 400.0, "30 líneas: crece hasta el tope")
	composer.call(&"clear")
	assert_eq(input.custom_minimum_size.y, resting, "al mandar vuelve al reposo")

	var grip: Control = composer.get(&"_grip")
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.global_position = Vector2(10, 500)
	composer.call(&"_on_grip_input", press)
	var motion := InputEventMouseMotion.new()
	motion.global_position = Vector2(10, 300)
	composer.call(&"_on_grip_input", motion)
	assert_eq(input.custom_minimum_size.y, 272.0, "arrastrar hacia arriba agranda")
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.global_position = motion.global_position
	composer.call(&"_on_grip_input", release)
	assert_eq(composer.call(&"manual_height"), 272.0, "queda fijado")
	composer.call(&"insert_text", "una línea")
	assert_eq(input.custom_minimum_size.y, 272.0, "fijado a mano no sigue al texto")
	var double := InputEventMouseButton.new()
	double.button_index = MOUSE_BUTTON_LEFT
	double.pressed = true
	double.double_click = true
	composer.call(&"_on_grip_input", double)
	assert_eq(input.custom_minimum_size.y, resting, "doble clic vuelve a seguir al texto")
	assert_true(grip != null, "hay manija")
	holder.free()
