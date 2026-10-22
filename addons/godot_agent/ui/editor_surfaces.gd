@tool
extends RefCounted
## Agrega y quita las superficies del addon en el editor: dock lateral, panel inferior y main screen.
## Usa EditorDock + add_dock donde existe y la API vieja en las versiones anteriores
## (docs/decisions.md, D9). Lo de EditorDock va por reflexión: los slots de panel inferior y main
## screen existen recién en 4.8.
## Cada superficie se monta dentro de un MinSizeGuard: su tamaño mínimo no puede agrandar el editor.

enum EditorSurface { SIDE, BOTTOM, MAIN_SCREEN }

const MinSizeGuard := preload("min_size_guard.gd")
const AgentTheme := preload("agent_theme.gd")
const _DOCK_CLASS := &"EditorDock"

## Slot inicial del dock lateral: nombre de la constante (igual en EditorPlugin y EditorDock).
## Con EditorDock solo cuenta la primera vez: después el editor recuerda dónde lo dejó el usuario.
var side_slot: StringName = &"DOCK_SLOT_RIGHT_UL"
var _plugin: EditorPlugin
## { surface: Surface, control: Control, mounted: MinSizeGuard (lo que se agrega al editor),
##   wrapper: Control (EditorDock o null), title: String }
var _entries: Array[Dictionary] = []


func _init(plugin: EditorPlugin) -> void:
	_plugin = plugin


## true si la superficie se monta con EditorDock en esta versión del editor.
static func uses_dock_api(surface: EditorSurface) -> bool:
	if not ClassDB.class_exists(_DOCK_CLASS):
		return false
	match surface:
		EditorSurface.BOTTOM:
			return ClassDB.class_has_integer_constant(_DOCK_CLASS, &"DOCK_SLOT_BOTTOM")
		EditorSurface.MAIN_SCREEN:
			return ClassDB.class_has_integer_constant(_DOCK_CLASS, &"DOCK_SLOT_MAIN_SCREEN")
	return true


func add(surface: EditorSurface, control: Control, title: String, layout_key: String, icon: Texture2D = null) -> void:
	var wrapper: Control = null
	var mounted := MinSizeGuard.new(control, AgentTheme.editor_scale())
	if uses_dock_api(surface):
		wrapper = _make_dock(surface, mounted, title, layout_key, icon)
		_plugin.call(&"add_dock", wrapper)
	else:
		match surface:
			EditorSurface.SIDE:
				_plugin.add_control_to_dock(ClassDB.class_get_integer_constant(&"EditorPlugin", side_slot) as EditorPlugin.DockSlot, mounted)
			EditorSurface.BOTTOM:
				_plugin.add_control_to_bottom_panel(mounted, title)
			EditorSurface.MAIN_SCREEN:
				# El plugin responde _has_main_screen() == true y maneja la visibilidad en _make_visible().
				mounted.visible = false
				EditorInterface.get_editor_main_screen().add_child(mounted)
	_entries.append({ "surface": surface, "control": control, "mounted": mounted, "wrapper": wrapper, "title": title })


## Visibilidad de la main screen con la API vieja (llamado desde EditorPlugin._make_visible).
func set_legacy_main_screen_visible(visible: bool) -> void:
	for entry: Dictionary in _entries:
		if entry.surface == EditorSurface.MAIN_SCREEN and entry.wrapper == null and is_instance_valid(entry.mounted):
			(entry.mounted as Control).visible = visible


## Muestra la superficie (p. ej. "Ver log" abre el panel inferior). La main screen se muestra con
## EditorInterface.set_main_screen_editor().
func make_visible(surface: EditorSurface) -> void:
	for entry: Dictionary in _entries:
		if entry.surface != surface:
			continue
		var wrapper: Control = entry.wrapper
		if is_instance_valid(wrapper):
			wrapper.call(&"make_visible")
			return
		var mounted: Control = entry.mounted
		if not is_instance_valid(mounted):
			return
		match surface:
			EditorSurface.BOTTOM:
				_plugin.make_bottom_panel_item_visible(mounted)
			EditorSurface.SIDE:
				var tabs := mounted.get_parent() as TabContainer
				if tabs:
					tabs.current_tab = mounted.get_index()
			EditorSurface.MAIN_SCREEN:
				EditorInterface.set_main_screen_editor(entry.title)
		return


func remove_all() -> void:
	for entry: Dictionary in _entries:
		var mounted: Control = entry.mounted
		var wrapper: Control = entry.wrapper
		if is_instance_valid(wrapper):
			# 4.8-beta1: quitar la main screen activa al cerrar el editor da
			# "Condition !is_inside_tree()" en grab_focus. Se cambia de pantalla antes. A "2D" y no a
			# "Script": con "Script", en headless, el editor entra en un bucle de llamadas diferidas y crashea.
			if entry.surface == EditorSurface.MAIN_SCREEN and wrapper.is_visible_in_tree():
				EditorInterface.set_main_screen_editor("2D")
			_plugin.call(&"remove_dock", wrapper)
			wrapper.queue_free()
			continue
		if not is_instance_valid(mounted):
			continue
		match entry.surface:
			EditorSurface.SIDE:
				_plugin.remove_control_from_docks(mounted)
			EditorSurface.BOTTOM:
				_plugin.remove_control_from_bottom_panel(mounted)
		mounted.queue_free()
	_entries.clear()


func _make_dock(surface: EditorSurface, control: Control, title: String, layout_key: String, icon: Texture2D) -> Control:
	var dock: Control = ClassDB.instantiate(_DOCK_CLASS)
	dock.set(&"title", title)
	dock.set(&"layout_key", layout_key)
	if icon:
		dock.set(&"dock_icon", icon)
	match surface:
		EditorSurface.SIDE:
			dock.set(&"default_slot", _dock_const(side_slot))
		EditorSurface.BOTTOM:
			dock.set(&"default_slot", _dock_const(&"DOCK_SLOT_BOTTOM"))
			dock.set(&"available_layouts", _dock_const(&"DOCK_LAYOUT_HORIZONTAL") | _dock_const(&"DOCK_LAYOUT_FLOATING"))
		EditorSurface.MAIN_SCREEN:
			dock.set(&"default_slot", _dock_const(&"DOCK_SLOT_MAIN_SCREEN"))
			dock.set(&"available_layouts", _dock_const(&"DOCK_LAYOUT_MAIN_SCREEN"))
	dock.add_child(control)
	return dock


static func _dock_const(name: StringName) -> int:
	return ClassDB.class_get_integer_constant(_DOCK_CLASS, name)
