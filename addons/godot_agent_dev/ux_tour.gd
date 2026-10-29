@tool
extends RefCounted
## Recorrido de capturas para revisar la UI contra lo propuesto (m12, revisión de UX): dock sin
## agentes y con agente, Ajustes (cada sección), registro de ACP, Extensiones (cada sección), One-shot
## ancho y angosto, Agent Log, y las conversaciones de la guía (DocsShots). Ver tests/ux_tour.sh.

const DocsShots := preload("docs_shots.gd")
const SettingsDialog := preload("res://addons/godot_agent/ui/settings/settings_dialog.gd")
const RegistryDialog := preload("res://addons/godot_agent/ui/settings/acp_registry_dialog.gd")
const AgentProfile := preload("res://addons/godot_agent/core/agent_profile.gd")

const DOCK_SCRIPT := "res://addons/godot_agent/ui/dock/agent_dock.gd"

var failures: PackedStringArray = []
var _tree: SceneTree
var _dir: String


func run(tree: SceneTree, dir: String, hide_bottom_panel: Callable) -> PackedStringArray:
	_tree = tree
	_dir = dir
	DirAccess.make_dir_recursive_absolute(dir)
	var dock := _by_script(DOCK_SCRIPT) as Control
	if dock == null:
		failures.append("no se encontró el dock")
		return failures
	await _set_dock_width(dock, 480)
	_show(dock)
	await _frames(20)
	_save_rect(dock, "01_dock_sin_agentes")

	var settings_button: Button = dock.get(&"_settings_button")
	settings_button.pressed.emit()
	await _frames(20)
	var settings := _by_script("res://addons/godot_agent/ui/settings/settings_dialog.gd") as Window
	if settings:
		for section in SettingsDialog.SECTION_LABELS.size():
			settings.call(&"open", section)
			await _frames(15)
			_save(settings.get_texture().get_image(), "1%d_ajustes_%d" % [section, section])
		settings.hide()

	var registry := RegistryDialog.new()
	EditorInterface.get_base_control().add_child(registry)
	registry.open()
	for i in 600:
		await _tree.process_frame
		if not (registry.get(&"_agents") as Array).is_empty():
			break
	await _frames(15)
	_save(registry.get_texture().get_image(), "18_registro")
	registry.queue_free()

	dock.emit_signal(&"extensions_requested")
	await _frames(30)
	var ext := _by_script("res://addons/godot_agent/ui/extensions/extensions_window.gd") as Window
	if ext:
		for tab in (ext.get(&"_tabs") as TabContainer).get_tab_count():
			ext.call(&"open", tab)
			await _frames(40)
			_save(ext.get_texture().get_image(), "2%d_extensiones_%d" % [tab, tab])
		ext.hide()

	EditorInterface.set_main_screen_editor("One-shot")
	await _frames(30)
	_save(_screen(), "30_oneshot")
	await _set_dock_width(dock, 1230)
	await _frames(30)
	_save(_screen(), "31_oneshot_angosto")
	await _set_dock_width(dock, 480)
	EditorInterface.set_main_screen_editor("2D")
	var log_panel := _by_script("res://addons/godot_agent/ui/log_panel/agent_log_panel.gd")
	if log_panel:
		_show(log_panel)
	await _frames(20)
	_save(_screen(), "32_agent_log")

	_show(dock)
	await _frames(10)
	var docs := DocsShots.new()
	failures.append_array(await docs.run(_tree, dir.path_join("guia"), hide_bottom_panel))
	_show(dock)
	await _frames(20)
	_save_rect(dock, "40_dock_tras_la_guia")
	return failures


func _by_script(path: String) -> Node:
	for node: Node in _tree.root.find_children("*", "", true, false):
		var script := node.get_script() as Script
		if script and script.resource_path == path:
			return node
	return null


## Sube hasta el EditorDock (o la pestaña) que contiene `control` y lo muestra.
func _show(control: Node) -> void:
	var node := control.get_parent()
	var child := control
	while node and node != _tree.root:
		if node.has_method(&"make_visible"):
			if node.has_method(&"open"):
				node.call(&"open")
			node.call(&"make_visible")
			return
		if node is TabContainer:
			(node as TabContainer).current_tab = child.get_index()
		child = node
		node = node.get_parent()


## Como DocsShots._widen_dock, con el ancho que se pida.
func _set_dock_width(dock: Control, width: int) -> void:
	await _frames(5)
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
			for attempt in 4:
				var missing := width - dock.size.x
				if absf(missing) < 4.0:
					return
				var offsets: Variant = split.get(&"split_offsets")
				if offsets is PackedInt32Array and divider >= 0 and divider < (offsets as PackedInt32Array).size():
					var list := offsets as PackedInt32Array
					list[divider] -= int(missing)
					split.set(&"split_offsets", list)
				else:
					split.split_offset -= int(missing)
				await _frames(5)
			return
		node = parent


func _screen() -> Image:
	return EditorInterface.get_base_control().get_viewport().get_texture().get_image()


func _save_rect(control: Control, name: String) -> void:
	_save(_screen().get_region(Rect2i((control.get_parent() as Control).get_global_rect())), name)


func _save(image: Image, name: String) -> void:
	var path := _dir.path_join(name + ".png")
	if image.save_png(path) != OK:
		failures.append("no se pudo guardar %s" % path)
	else:
		print("[ux-tour] ", path)


func _frames(count: int) -> void:
	for i in count:
		await _tree.process_frame
