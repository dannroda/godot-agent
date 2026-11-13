@tool
extends RefCounted
## Verificación de lo que install_extension preparó y no entró (m19-05) en el editor: con algo en
## `.godot/agent_supervisor/pending/`, habilitar el plugin muestra el aviso en el dock con
## «Reiniciar» y «Descartar», y «Descartar» lo borra sin tocar el proyecto. «Reiniciar» pasa por
## restart_editor bajo el supervisor (m19-05 #7), como la tool: se aprieta con restart_override,
## sin reiniciar el editor de la prueba. Una instalación que falló (last_install.json) se avisa.

const NativeInstall := preload("res://addons/godot_agent/core/native_install.gd")
const SupervisorState := preload("res://addons/godot_agent/supervisor/supervisor_state.gd")
const RestartResume := preload("res://addons/godot_agent/session/restart_resume.gd")
const DOCK_SCRIPT := "res://addons/godot_agent/ui/dock/agent_dock.gd"
const PLUGIN_SCRIPT := "res://addons/godot_agent/agent_plugin.gd"
const TARGET_PLUGIN := "godot_agent"
const NAME := "pending_check_ext"
const TARGET := "addons/" + NAME
const RESTART := "pending_install_restart"
const DISCARD := "pending_install_discard"
const WAIT_S := 10.0

var failures: PackedStringArray = []
var _tree: SceneTree


func run(tree: SceneTree) -> PackedStringArray:
	_tree = tree
	var state := SupervisorState.state_dir(ProjectSettings.globalize_path("res://"))
	_stage(state)
	await _run(state)
	NativeInstall.discard_pending(state)
	# Reiniciar guarda las pestañas para retomarlas (m12-54): que no las reabra el próximo check.
	RestartResume.discard(state)
	return failures


func _run(state: String) -> void:
	EditorInterface.set_plugin_enabled(TARGET_PLUGIN, false)
	await _tree.create_timer(1.0).timeout
	EditorInterface.set_plugin_enabled(TARGET_PLUGIN, true)
	var dock: Control = null
	var notice: Object = null
	var deadline := Time.get_ticks_msec() + int(WAIT_S * 1000)
	while notice == null and Time.get_ticks_msec() < deadline:
		await _tree.create_timer(0.2).timeout
		dock = _dock()
		notice = _notice(dock)
	if notice == null:
		failures.append("al habilitar el plugin no apareció el aviso de lo preparado")
		return
	var text := str(notice.get(&"text"))
	_expect(text.contains(NAME) and text.contains("res://" + TARGET), "el aviso nombra la extensión y dónde va · " + text)
	var ids: Array = (notice.get(&"actions") as Array).map(func(action: Dictionary) -> String: return str(action.get("id")))
	_expect(ids == [RESTART, DISCARD], "con Reiniciar y Descartar · %s" % [ids])
	_expect(FileAccess.file_exists(state.path_join("pending.json")), "el aviso no instala ni borra nada")
	var model: Object = dock.get(&"_model")
	var failure_shown := false
	for entry: Object in model.call(&"entries"):
		var entry_text := str(entry.get(&"text"))
		if (entry_text.contains("Could not install the staged GDExtension") or entry_text.contains("No se pudo instalar la GDExtension preparada")) and entry_text.contains("disk full"):
			failure_shown = true
	_expect(failure_shown, "la instalación que falló se avisa en el dock")
	_expect(NativeInstall.take_install_failure(state).is_empty(), "una sola vez")
	var plugin := _plugin()
	var restarts: Array = []
	if plugin == null:
		failures.append("no se encontró el plugin")
	else:
		plugin.set(&"restart_override", func(supervise: bool, reason: String) -> String:
			restarts.append(supervise)
			return "")
		dock.emit_signal(&"action_forwarded", RESTART, null)
		await _tree.process_frame
		plugin.set(&"restart_override", Callable())
		_expect(restarts == [true], "Reiniciar pasa por restart_editor con el supervisor · %s" % [restarts])
	dock.emit_signal(&"action_forwarded", DISCARD, null)
	await _tree.process_frame
	_expect(NativeInstall.pending_info(state).is_empty() and not DirAccess.dir_exists_absolute(state.path_join("pending")), "Descartar borra lo preparado")
	_expect(not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path("res://" + TARGET)), "y no instala nada")
	var discarded := false
	for entry: Object in model.call(&"entries"):
		if str(entry.get(&"text")).contains("Discarded the staged install of " + NAME) or str(entry.get(&"text")).contains("Se descartó la instalación preparada de " + NAME):
			discarded = true
	_expect(discarded, "y lo dice")


func _stage(state: String) -> void:
	var gdext := TARGET.path_join(NAME + ".gdextension")
	var path := state.path_join("pending").path_join(gdext)
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string("[configuration]\nentry_symbol = \"x\"\ncompatibility_minimum = \"4.5\"\n")
	file.close()
	var manifest := FileAccess.open(state.path_join("pending.json"), FileAccess.WRITE)
	manifest.store_string(JSON.stringify({"files": [gdext], "target": "res://" + TARGET, "source": "res://bin", "time": Time.get_datetime_string_from_system()}))
	manifest.close()
	var last := FileAccess.open(state.path_join(NativeInstall.LAST_INSTALL), FileAccess.WRITE)
	last.store_string(JSON.stringify({"ok": false, "failed": [gdext], "error": "could not copy %s into the game: disk full" % gdext, "extensions": [NAME], "time": Time.get_datetime_string_from_system()}))
	last.close()


func _plugin() -> Node:
	for node: Node in _tree.root.find_children("*", "Node", true, false):
		if node.get_script() and (node.get_script() as Script).resource_path == PLUGIN_SCRIPT:
			return node
	return null


func _dock() -> Control:
	for node: Node in EditorInterface.get_base_control().find_children("*", "VBoxContainer", true, false):
		if node.get_script() and (node.get_script() as Script).resource_path == DOCK_SCRIPT and node.is_inside_tree():
			return node
	return null


func _notice(dock: Control) -> Object:
	if dock == null or dock.get(&"_model") == null:
		return null
	for entry: Object in dock.get(&"_model").call(&"entries"):
		for action: Dictionary in entry.get(&"actions"):
			if action.get("id") == RESTART:
				return entry
	return null


func _expect(condition: bool, what: String) -> void:
	if not condition:
		failures.append(what)
