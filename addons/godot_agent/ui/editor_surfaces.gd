@tool
extends RefCounted
## Agrega y quita las superficies del addon en el editor: dock lateral, panel inferior y main screen.
## Dock lateral y panel inferior son EditorDock + add_dock; la main screen también desde 4.8, y en
## 4.7 va con la API vieja (docs/decisions.md, D9). El slot de main screen va por reflexión.
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


## true si la superficie se monta con EditorDock en esta versión del editor (todas menos la main
## screen en 4.7).
static func uses_dock_api(surface: EditorSurface) -> bool:
	return surface != EditorSurface.MAIN_SCREEN or ClassDB.class_has_integer_constant(_DOCK_CLASS, &"DOCK_SLOT_MAIN_SCREEN")


func add(surface: EditorSurface, control: Control, title: String, layout_key: String, icon: Texture2D = null) -> void:
	var wrapper: Control = null
	var mounted := MinSizeGuard.new(control, AgentTheme.editor_scale())
	if uses_dock_api(surface):
		wrapper = _make_dock(surface, mounted, title, layout_key, icon)
		_plugin.call(&"add_dock", wrapper)
	else:
		# Main screen en 4.7: el plugin responde _has_main_screen() == true y maneja la visibilidad
		# en _make_visible().
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
			wrapper.call(&"open")  # si el usuario cerró el panel, make_visible solo no lo vuelve a abrir
			wrapper.call(&"make_visible")
			return
		if is_instance_valid(entry.mounted):
			EditorInterface.set_main_screen_editor(entry.title)
		return


func remove_all() -> void:
	for entry: Dictionary in _entries:
		var mounted: Control = entry.mounted
		var wrapper: Control = entry.wrapper
		if is_instance_valid(wrapper):
			# Precaución (D9): durante el desarrollo, quitar la main screen activa al cerrar el editor daba
			# "Condition !is_inside_tree()" en grab_focus. En 4.8-beta1 y dev7 ya no se reproduce, pero
			# cambiar antes de pantalla no cuesta nada. A "2D" y no a "Script", que en headless crasheaba.
			if entry.surface == EditorSurface.MAIN_SCREEN and wrapper.is_visible_in_tree():
				EditorInterface.set_main_screen_editor("2D")
			_plugin.call(&"remove_dock", wrapper)
			wrapper.queue_free()
			continue
		if is_instance_valid(mounted):
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
