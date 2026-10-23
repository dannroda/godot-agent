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
	for busy: bool in [false, true]:
		composer.call(&"set_busy", busy)
		for i in 4:
			await tree.process_frame
		for failure: String in dock_fits(dock):
			failures.append("con sesión%s: %s" % [" ocupada" if busy else "", failure])
		for name: StringName in [&"_model_button", &"_send_button"]:
			if not (composer.get(name) as Control).is_visible_in_tree():
				failures.append("con sesión, no se ve %s" % name)
	composer.call(&"set_busy", false)
	composer.call(&"set_usage", 0, 0)
	composer.call(&"set_model_option", {})
	return failures


static func _label(button: BaseButton) -> String:
	if button is Button and not (button as Button).text.is_empty():
		return (button as Button).text
	return button.tooltip_text if not button.tooltip_text.is_empty() else str(button.name)
