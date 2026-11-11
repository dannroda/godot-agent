@tool
extends RefCounted
## «Embeber el juego en la vista Game» (4.4+), apagado para un lanzamiento (m11-51: un juego embebido
## tiene la ventana del tamaño que pone el editor, así que el dispositivo simulado no podría cambiarla).
## La vista Game lee run/window_placement/game_embed_mode y el metadato del proyecto solo al arrancar
## el editor (GameView::NOTIFICATION_READY); en caliente, lo único que cambia embed_on_play es su menú
## de opciones («Embed Game on Next Play»). Se aprieta ese ítem antes de lanzar y otra vez después,
## así queda como estaba (también el metadato del proyecto, que el menú guarda).

const ITEM_TEXT := "Embed Game on Next Play"
const EDITOR_DOMAIN := &"godot.editor"


## Apaga el embebido si estaba prendido. Devuelve el menú para restore(), o null si no hacía falta
## o no se encontró (otro Godot, sin vista Game).
static func disable() -> PopupMenu:
	var found := _find_item()
	if found.is_empty():
		return null
	var menu: PopupMenu = found.menu
	var index: int = found.index
	if not menu.is_item_checked(index):
		return null
	menu.id_pressed.emit(menu.get_item_id(index))
	return menu if not menu.is_item_checked(index) else null


## Lo vuelve a prender (el menú que devolvió disable()).
static func restore(menu: PopupMenu) -> void:
	if menu == null or not is_instance_valid(menu):
		return
	var index := _index_in(menu)
	if index >= 0 and not menu.is_item_checked(index):
		menu.id_pressed.emit(menu.get_item_id(index))


## true si el próximo lanzamiento iría embebido (el ítem existe y está tildado).
static func is_on() -> bool:
	var found := _find_item()
	return not found.is_empty() and (found.menu as PopupMenu).is_item_checked(found.index)


static func _find_item() -> Dictionary:
	var base := EditorInterface.get_base_control()
	if base == null:
		return {}
	for node: Node in base.find_children("*", "MenuButton", true, false):
		if not _inside_game_view(node):
			continue
		var menu := (node as MenuButton).get_popup()
		var index := _index_in(menu)
		if index >= 0:
			return {"menu": menu, "index": index}
	return {}


static func _index_in(menu: PopupMenu) -> int:
	var texts: PackedStringArray = [ITEM_TEXT]
	if TranslationServer.has_method(&"get_or_add_domain"):
		texts.append(str(TranslationServer.call(&"get_or_add_domain", EDITOR_DOMAIN).call(&"translate", ITEM_TEXT)))
	for i in menu.item_count:
		if menu.is_item_checkable(i) and menu.get_item_text(i) in texts:
			return i
	return -1


static func _inside_game_view(node: Node) -> bool:
	var current := node.get_parent()
	while current:
		if current.get_class() == "GameView":
			return true
		current = current.get_parent()
	return false
