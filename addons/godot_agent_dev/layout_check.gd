@tool
extends RefCounted
## El dock entra en el ancho que le da el editor (m7-23): su mínimo no pasa el ancho del panel
## (lo que sobra lo recorta el MinSizeGuard), ningún botón queda fuera del borde y los modos se leen
## enteros. Lo usan el check de Remote Control (en inglés) y el de i18n (en español).


static func dock_fits(dock: Control) -> PackedStringArray:
	var failures: PackedStringArray = []
	var guard := dock.get_parent() as Control
	var width := guard.size.x
	if dock.get_combined_minimum_size().x > width + 1.0:
		failures.append("el dock pide %d px y el panel tiene %d" % [dock.get_combined_minimum_size().x, width])
	var right := guard.get_global_rect().end.x
	for node: Node in dock.find_children("*", "BaseButton", true, false):
		var button := node as BaseButton
		if button.is_visible_in_tree() and button.get_global_rect().end.x > right + 1.0:
			failures.append("«%s» queda fuera del dock (%d > %d)" % [_label(button), button.get_global_rect().end.x, right])
	var mode_button: OptionButton = (dock.get(&"_composer") as Object).get(&"_mode_button")
	if not mode_button.is_visible_in_tree():
		failures.append("no se ve el selector de modo")
	return failures


## Con una sesión activa la fila del composer suma el medidor, el modelo y Detener (m7-42): se
## compacta hasta entrar, con el modelo y Enviar/Detener siempre a la vista. Deja el composer como
## estaba.
static func composer_fits(dock: Control) -> PackedStringArray:
	var composer: Object = dock.get(&"_composer")
	var tree := dock.get_tree()
	composer.call(&"set_usage", 38000, 200000)
	composer.call(&"set_model_option", {"currentValue": "default", "options": [
		{"value": "default", "name": "Default (recommended)", "description": "Opus 5.5"},
		{"value": "opus", "name": "Opus 5.5"},
		{"value": "sonnet", "name": "Sonnet 5.5"}]})
	var failures: PackedStringArray = []
	# El composer lee si hay un turno en curso con `busy_provider` (m13-14): acá se le presta uno fijo.
	var model_busy: Callable = composer.get(&"busy_provider")
	for busy: bool in [false, true]:
		composer.set(&"busy_provider", func() -> bool: return busy)
		composer.call(&"refresh_state")
		for i in 4:
			await tree.process_frame
		for failure: String in dock_fits(dock):
			failures.append("con sesión%s: %s" % [" ocupada" if busy else "", failure])
		for name: StringName in [&"_model_button", &"_send_button"]:
			if not (composer.get(name) as Control).is_visible_in_tree():
				failures.append("con sesión, no se ve %s" % name)
	composer.set(&"busy_provider", model_busy)
	composer.call(&"refresh_state")
	composer.call(&"set_usage", 0, 0)
	composer.call(&"set_model_option", {})
	return failures


## Un mensaje corto del usuario se lee en una línea (m13-21): el globo no colapsa al ancho de una o
## dos letras («h / ol / a»). Agrega «hola» al chat del dock, mide el globo y lo deja en el chat.
static func user_bubble_fits(dock: Control) -> PackedStringArray:
	var failures: PackedStringArray = []
	var tree := dock.get_tree()
	var model: Object = dock.get(&"_model")
	var conversation: Object = dock.get(&"_conversation")
	var entry: Object = model.call(&"add_user_message", "hola")
	for i in 6:
		await tree.process_frame
	var view: Control = (conversation.get(&"_views") as Dictionary).get(entry.get(&"id"))
	var label: Label = view.get(&"_label") if view else null
	if label == null or not label.is_visible_in_tree():
		failures.append("no se ve el globo de «hola»")
		return failures
	var font := label.get_theme_font(&"font")
	var text_width := font.get_string_size("hola", HORIZONTAL_ALIGNMENT_LEFT, -1, label.get_theme_font_size(&"font_size")).x
	# El estilo `normal` del Label en el tema del editor tiene márgenes: el texto tiene menos lugar
	# que el ancho del Label.
	var style := label.get_theme_stylebox(&"normal")
	var room := label.size.x - (style.get_minimum_size().x if style else 0.0)
	if label.get_line_count() != 1 or room + 0.5 < text_width:
		failures.append("el globo de «hola» se parte en %d líneas (lugar para el texto %d px, el texto pide %d, vista %d)" % [label.get_line_count(), room, text_width, view.size.x])
	return failures


static func _label(button: BaseButton) -> String:
	if button is Button and not (button as Button).text.is_empty():
		return (button as Button).text
	return button.tooltip_text if not button.tooltip_text.is_empty() else str(button.name)
