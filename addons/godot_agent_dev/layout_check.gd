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


## El formulario del One-shot entra en el centro del editor (m12-41, reabre m12-09): con el dock
## ancho el centro queda en ~380 px y nada se corta por los bordes. `form` es el ScrollContainer de
## la pantalla: el panel no pide más ancho que el área y ningún control visible sale de ella.
static func form_fits(form: Control) -> PackedStringArray:
	var failures: PackedStringArray = []
	var area := form.get_global_rect()
	var panel := form.get_child(0).get_child(0) as Control
	if panel.get_combined_minimum_size().x > area.size.x + 1.0:
		failures.append("el formulario pide %d px y el centro tiene %d" % [panel.get_combined_minimum_size().x, area.size.x])
	for node: Node in panel.find_children("*", "Control", true, false):
		var control := node as Control
		if control.get_child_count() > 0 or not control.is_visible_in_tree():
			continue
		var rect := control.get_global_rect()
		if rect.position.x < area.position.x - 1.0 or rect.end.x > area.end.x + 1.0:
			failures.append("«%s» sale del centro (%d..%d, centro %d..%d)" % [_name(control), rect.position.x, rect.end.x, area.position.x, area.end.x])
	return failures


## Lleva el dock al ancho pedido moviendo el divisor del SplitContainer que lo contiene (como
## DocsShots._widen_dock). El tour de UX y el check del One-shot lo usan para el centro angosto.
static func set_dock_width(dock: Control, width: int) -> void:
	var tree := dock.get_tree()
	for i in 5:
		await tree.process_frame
	var node: Node = dock
	while node and node != EditorInterface.get_base_control():
		var parent := node.get_parent()
		if parent is SplitContainer and not (parent as SplitContainer).vertical and node.get_index() > 0:
			var split := parent as SplitContainer
			var divider := -1
			for child: Node in split.get_children():
				if child == node:
					break
				if child is Control and (child as Control).visible:
					divider += 1
			# El offset guardado puede no ser el que el split aplica: con el layout por defecto el del dock
			# derecho es -210 pero su mínimo es 229, así que mover el divisor desde ahí rendía 19 px menos y
			# eso se tomaba como un mínimo que lo frenaba (el centro quedaba en 378 y no en 340).
			split.clamp_split_offset(divider)
			for attempt in 4:
				var missing := width - dock.size.x
				if absf(missing) < 4.0:
					return
				var before := dock.size.x
				_move_divider(split, divider, -int(missing))
				for i in 5:
					await tree.process_frame
				var unmet := int(missing - (dock.size.x - before))
				if absi(unmet) >= 2:
					# Un mínimo frenó al split: se deshace lo que no se movió. Si no, el offset guardado
					# se aleja en cada intento y queda en el layout del editor para el próximo run, que
					# arranca de otro lugar (dock_hsplit_3=-6328 tras varios oneshot-test).
					_move_divider(split, divider, unmet)
					for i in 2:
						await tree.process_frame
					return
			return
		node = parent


static func _name(control: Control) -> String:
	if control is BaseButton:
		return _label(control as BaseButton)
	if control is Label:
		return (control as Label).text.left(40)
	if control is RichTextLabel:
		return (control as RichTextLabel).get_parsed_text().left(40)
	return str(control.name)


static func _label(button: BaseButton) -> String:
	if button is Button and not (button as Button).text.is_empty():
		return (button as Button).text
	return button.tooltip_text if not button.tooltip_text.is_empty() else str(button.name)


## Mueve el divisor `divider` de `split` `delta` px (split_offsets en 4.6+, split_offset antes).
static func _move_divider(split: SplitContainer, divider: int, delta: int) -> void:
	var offsets: Variant = split.get(&"split_offsets")
	if offsets is PackedInt32Array and divider >= 0 and divider < (offsets as PackedInt32Array).size():
		var list := offsets as PackedInt32Array
		list[divider] += delta
		split.set(&"split_offsets", list)
	else:
		split.split_offset += delta
