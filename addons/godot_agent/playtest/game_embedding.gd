@tool
extends RefCounted
## Embeber el juego en la vista Game (4.4+), apagado para un lanzamiento (m11-51: un juego embebido
## tiene la ventana del tamaño que pone el editor, así que el dispositivo simulado no podría cambiarla).
## La vista Game lee run/window_placement/game_embed_mode y el metadato del proyecto solo al arrancar
## el editor (GameView::NOTIFICATION_READY); en caliente, lo único que cambia es su control:
## - 4.4–4.7: el ítem «Embed Game on Next Play» del menú de opciones. Se aprieta antes de lanzar y otra
##   vez después, así queda como estaba (también el metadato del proyecto, que el menú guarda).
## - 4.8+: tres botones de radio («embedded in the Game workspace», «floating window with the toolbar»,
##   «floating window without the toolbar»). Solo el último corre el juego en su propia ventana (los
##   otros dos lo embeben igual: Engine.is_embedded_in_editor() da true); después se aprieta el que
##   estaba.

const ITEM_TEXT := "Embed Game on Next Play"
## El botón de 4.8+ que corre el juego sin embeber.
const OWN_WINDOW_TOOLTIP := "Run the game in a floating window without the toolbar on the next run."
const EDITOR_DOMAIN := &"godot.editor"


## Apaga el embebido si estaba prendido. Devuelve lo que restore() necesita para dejarlo como estaba
## (el menú, o el botón que estaba apretado), o null si no hacía falta o no se encontró el control.
static func disable() -> Object:
	var own_window := _own_window_button()
	if own_window:
		var previous := own_window.button_group.get_pressed_button() if own_window.button_group else null
		if previous == null or previous == own_window:
			return null
		_press(own_window)
		return previous if own_window.button_pressed else null
	var found := _find_item()
	if found.is_empty():
		return null
	var menu: PopupMenu = found.menu
	var index: int = found.index
	if not menu.is_item_checked(index):
		return null
	menu.id_pressed.emit(menu.get_item_id(index))
	return menu if not menu.is_item_checked(index) else null


## Lo vuelve a prender con lo que devolvió disable().
static func restore(state: Object) -> void:
	if state == null or not is_instance_valid(state):
		return
	if state is BaseButton:
		if not (state as BaseButton).button_pressed:
			_press(state as BaseButton)
		return
	var menu := state as PopupMenu
	var index := _index_in(menu) if menu else -1
	if index >= 0 and not menu.is_item_checked(index):
		menu.id_pressed.emit(menu.get_item_id(index))


## true si el próximo lanzamiento iría embebido.
static func is_on() -> bool:
	var own_window := _own_window_button()
	if own_window:
		return not own_window.button_pressed
	var found := _find_item()
	return not found.is_empty() and (found.menu as PopupMenu).is_item_checked(found.index)


## Como un clic: la vista Game escucha `pressed`, que button_pressed solo no emite.
static func _press(button: BaseButton) -> void:
	button.button_pressed = true
	button.pressed.emit()


static func _own_window_button() -> BaseButton:
	var view := _game_view()
	if view == null:
		return null
	var tooltips := _translations(OWN_WINDOW_TOOLTIP)
	for node: Node in view.find_children("*", "BaseButton", true, false):
		var button := node as BaseButton
		if button.toggle_mode and button.tooltip_text in tooltips:
			return button
	return null


static func _find_item() -> Dictionary:
	var view := _game_view()
	if view == null:
		return {}
	for node: Node in view.find_children("*", "MenuButton", true, false):
		var menu := (node as MenuButton).get_popup()
		var index := _index_in(menu)
		if index >= 0:
			return {"menu": menu, "index": index}
	return {}


static func _index_in(menu: PopupMenu) -> int:
	var texts := _translations(ITEM_TEXT)
	for i in menu.item_count:
		if menu.is_item_checkable(i) and menu.get_item_text(i) in texts:
			return i
	return -1


## El texto en inglés y como lo muestra el editor en su idioma.
static func _translations(text: String) -> PackedStringArray:
	var texts: PackedStringArray = [text]
	if TranslationServer.has_method(&"get_or_add_domain"):
		texts.append(str(TranslationServer.call(&"get_or_add_domain", EDITOR_DOMAIN).call(&"translate", text)))
	return texts


static func _game_view() -> Node:
	var base := EditorInterface.get_base_control()
	if base == null:
		return null
	var views := base.get_tree().root.find_children("*", "GameView", true, false)
	return views[0] if not views.is_empty() else null
