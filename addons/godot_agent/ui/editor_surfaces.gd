@tool
extends RefCounted
## Agrega y quita las superficies del addon en el editor: dock lateral, panel inferior y main screen.
## Usa EditorDock + add_dock donde existe y la API vieja en las versiones anteriores
## (docs/decisions.md, D9). Todo lo de EditorDock va por reflexión para que parsee en 4.4.

enum Surface { SIDE, BOTTOM, MAIN_SCREEN }

const _DOCK_CLASS := &"EditorDock"

## Slot inicial del dock lateral: nombre de la constante (igual en EditorPlugin y EditorDock).
## Con EditorDock solo cuenta la primera vez: después el editor recuerda dónde lo dejó el usuario.
var side_slot: StringName = &"DOCK_SLOT_RIGHT_UL"
var _plugin: EditorPlugin
## { surface: Surface, control: Control, wrapper: Control (EditorDock o null) }
var _entries: Array[Dictionary] = []


func _init(plugin: EditorPlugin) -> void:
	_plugin = plugin


## true si la superficie se monta con EditorDock en esta versión del editor.
static func uses_dock_api(surface: Surface) -> bool:
	if not ClassDB.class_exists(_DOCK_CLASS):
		return false
	match surface:
		Surface.BOTTOM:
			return ClassDB.class_has_integer_constant(_DOCK_CLASS, &"DOCK_SLOT_BOTTOM")
		Surface.MAIN_SCREEN:
			return ClassDB.class_has_integer_constant(_DOCK_CLASS, &"DOCK_SLOT_MAIN_SCREEN")
	return true


func add(surface: Surface, control: Control, title: String, layout_key: String, icon: Texture2D = null) -> void:
	var wrapper: Control = null
	if uses_dock_api(surface):
		wrapper = _make_dock(surface, control, title, layout_key, icon)
		_plugin.call(&"add_dock", wrapper)
	else:
		match surface:
			Surface.SIDE:
				_plugin.add_control_to_dock(ClassDB.class_get_integer_constant(&"EditorPlugin", side_slot) as EditorPlugin.DockSlot, control)
			Surface.BOTTOM:
				_plugin.add_control_to_bottom_panel(control, title)
			Surface.MAIN_SCREEN:
				# El plugin responde _has_main_screen() == true y maneja la visibilidad en _make_visible().
				control.visible = false
				EditorInterface.get_editor_main_screen().add_child(control)
	_entries.append({ "surface": surface, "control": control, "wrapper": wrapper, "title": title })


## Visibilidad de la main screen con la API vieja (llamado desde EditorPlugin._make_visible).
func set_legacy_main_screen_visible(visible: bool) -> void:
	for entry: Dictionary in _entries:
		if entry.surface == Surface.MAIN_SCREEN and entry.wrapper == null and is_instance_valid(entry.control):
			(entry.control as Control).visible = visible


## Muestra la superficie (p. ej. "Ver log" abre el panel inferior). La main screen se muestra con
## EditorInterface.set_main_screen_editor().
func make_visible(surface: Surface) -> void:
	for entry: Dictionary in _entries:
		if entry.surface != surface:
			continue
		var wrapper: Control = entry.wrapper
		if is_instance_valid(wrapper):
			wrapper.call(&"make_visible")
			return
		var control: Control = entry.control
		if not is_instance_valid(control):
			return
		match surface:
			Surface.BOTTOM:
				_plugin.make_bottom_panel_item_visible(control)
			Surface.SIDE:
				var tabs := control.get_parent() as TabContainer
				if tabs:
					tabs.current_tab = control.get_index()
			Surface.MAIN_SCREEN:
				EditorInterface.set_main_screen_editor(entry.title)
		return


func remove_all() -> void:
	for entry: Dictionary in _entries:
		var control: Control = entry.control
		var wrapper: Control = entry.wrapper
		if is_instance_valid(wrapper):
			# 4.8-beta1: quitar la main screen activa al cerrar el editor da
			# "Condition !is_inside_tree()" en grab_focus. Se cambia de pantalla antes. A "2D" y no a
			# "Script": con "Script", en headless, el editor entra en un bucle de llamadas diferidas y crashea.
			if entry.surface == Surface.MAIN_SCREEN and wrapper.is_visible_in_tree():
				EditorInterface.set_main_screen_editor("2D")
			_plugin.call(&"remove_dock", wrapper)
			wrapper.queue_free()
			continue
		if not is_instance_valid(control):
			continue
		match entry.surface:
			Surface.SIDE:
				_plugin.remove_control_from_docks(control)
			Surface.BOTTOM:
				_plugin.remove_control_from_bottom_panel(control)
		control.queue_free()
	_entries.clear()


func _make_dock(surface: Surface, control: Control, title: String, layout_key: String, icon: Texture2D) -> Control:
	var dock: Control = ClassDB.instantiate(_DOCK_CLASS)
	dock.set(&"title", title)
	dock.set(&"layout_key", layout_key)
	if icon:
		dock.set(&"dock_icon", icon)
	match surface:
		Surface.SIDE:
			dock.set(&"default_slot", _dock_const(side_slot))
		Surface.BOTTOM:
			dock.set(&"default_slot", _dock_const(&"DOCK_SLOT_BOTTOM"))
			dock.set(&"available_layouts", _dock_const(&"DOCK_LAYOUT_HORIZONTAL") | _dock_const(&"DOCK_LAYOUT_FLOATING"))
		Surface.MAIN_SCREEN:
			dock.set(&"default_slot", _dock_const(&"DOCK_SLOT_MAIN_SCREEN"))
			dock.set(&"available_layouts", _dock_const(&"DOCK_LAYOUT_MAIN_SCREEN"))
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	control.size_flags_vertical = Control.SIZE_EXPAND_FILL
	dock.add_child(control)
	return dock


static func _dock_const(name: StringName) -> int:
	return ClassDB.class_get_integer_constant(_DOCK_CLASS, name)
