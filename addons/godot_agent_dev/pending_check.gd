@tool
extends RefCounted
## Verificación de lo que install_extension preparó y no entró (m19-05) en el editor: con algo en
## `.godot/agent_supervisor/pending/`, habilitar el plugin muestra el aviso en el dock con
## «Reiniciar» y «Descartar», y «Descartar» lo borra sin tocar el proyecto. «Reiniciar» no se
## aprieta: reiniciaría el editor de la prueba.

const NativeInstall := preload("res://addons/godot_agent/core/native_install.gd")
const SupervisorState := preload("res://addons/godot_agent/supervisor/supervisor_state.gd")
const DOCK_SCRIPT := "res://addons/godot_agent/ui/dock/agent_dock.gd"
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
	dock.emit_signal(&"action_forwarded", DISCARD, null)
	await _tree.process_frame
	_expect(NativeInstall.pending_info(state).is_empty() and not DirAccess.dir_exists_absolute(state.path_join("pending")), "Descartar borra lo preparado")
	_expect(not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path("res://" + TARGET)), "y no instala nada")
	var model: Object = dock.get(&"_model")
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
