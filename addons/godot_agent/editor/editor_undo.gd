@tool
extends RefCounted
## Pasos de undo de las tools del agente (spec §6 y §9: botón "↶ undo" en el dock).
## EditorUndoRedoManager no expone undo() a GDScript, y llamar al UndoRedo de una historia directo
## desincroniza la pila del manager. Por eso se usa la opción Undo del menú del editor (la misma
## que Ctrl+Z), y solo si la acción del agente sigue siendo la última de su escena y de la global.

const I18n := preload("../core/i18n.gd")

const GLOBAL_HISTORY := 0


## Datos para deshacer después la acción recién commiteada sobre la escena `root`.
static func record(action_name: String, root: Node) -> Dictionary:
	var undo_redo := EditorInterface.get_editor_undo_redo()
	var history_id := undo_redo.get_object_history_id(root)
	return {
		"action": action_name,
		"scene": root.scene_file_path,
		"history_id": history_id,
		"version": undo_redo.get_history_undo_redo(history_id).get_version(),
		"global_version": undo_redo.get_history_undo_redo(GLOBAL_HISTORY).get_version(),
	}


## "" si se puede deshacer; si no, por qué.
static func check(info: Dictionary) -> String:
	var root := EditorInterface.get_edited_scene_root()
	var scene := str(info.get("scene", ""))
	if not scene in EditorInterface.get_open_scenes() and not (root and root.scene_file_path == scene):
		return I18n.t("The scene %s is no longer open.") % scene
	var undo_redo := EditorInterface.get_editor_undo_redo()
	var history := undo_redo.get_history_undo_redo(int(info.history_id))
	if history == null or history.get_version() != int(info.version):
		return I18n.t("%s changed afterwards: undo with Ctrl+Z in the editor.") % scene.get_file()
	if undo_redo.get_history_undo_redo(GLOBAL_HISTORY).get_version() != int(info.global_version):
		return I18n.t("The editor changed afterwards: undo with Ctrl+Z.")
	return ""


## Deshace la acción si sigue siendo la última. Devuelve "" si se deshizo; si no, el motivo.
static func undo(info: Dictionary) -> String:
	var reason := check(info)
	if not reason.is_empty():
		return reason
	var scene := str(info.scene)
	var root := EditorInterface.get_edited_scene_root()
	if root == null or root.scene_file_path != scene:
		EditorInterface.open_scene_from_path(scene)  # la vuelve la escena actual
	var undo_redo := EditorInterface.get_editor_undo_redo()
	var history := undo_redo.get_history_undo_redo(int(info.history_id))
	if not _trigger_editor_undo():
		return I18n.t("The editor's Undo menu option was not found: use Ctrl+Z.")
	if history.get_version() == int(info.version):
		return I18n.t("The editor did not undo the step (is a mouse button held down?).")
	return ""


## Dispara la opción Undo del menú principal (Escena o Editar, según la versión).
static func _trigger_editor_undo() -> bool:
	var event := InputEventKey.new()
	event.keycode = KEY_Z
	event.command_or_control_autoremap = true
	for node: Node in EditorInterface.get_base_control().find_children("*", "PopupMenu", true, false):
		var popup := node as PopupMenu
		if not popup.get_parent() is MenuBar:
			continue  # menús del Script Editor y otros: no son el undo del editor
		for i in popup.item_count:
			var shortcut := popup.get_item_shortcut(i)
			if shortcut and shortcut.matches_event(event):
				popup.id_pressed.emit(popup.get_item_id(i))
				return true
	return false
