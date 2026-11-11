@tool
extends RefCounted
## ui-memory (m11-36) con el agente falso: /remember guarda la línea en el archivo de instrucciones del
## agente (AGENTS.md para uno genérico) con un aviso, la sesión la recibe en el próximo prompt dentro
## de un sobre, «Deshacer» la saca, y la pestaña Memoria de Extensiones la lista y la borra.

const SessionModel := preload("res://addons/godot_agent/session/session_model.gd")
const ProjectMemory := preload("res://addons/godot_agent/core/project_memory.gd")
const UntrustedText := preload("res://addons/godot_agent/mcp/untrusted_text.gd")
const AgentLog := preload("res://addons/godot_agent/core/agent_log.gd")
const MAIN_PLUGIN_SCRIPT := "res://addons/godot_agent/agent_plugin.gd"

var failures: Array[String] = []
var _tree: SceneTree


func _expect(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)


func _wait(condition: Callable, seconds: float = 20.0) -> bool:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000.0)
	while not condition.call() and Time.get_ticks_msec() < deadline:
		await _tree.process_frame
	return condition.call()


func run(tree: SceneTree, plugin: Object, dock: Control, shot_path: String) -> Array[String]:
	_tree = tree
	var file := str(dock.call(&"instructions_file"))
	var path := ProjectSettings.globalize_path("res://").path_join(file)
	var existed := FileAccess.file_exists(path)
	var before := FileAccess.get_file_as_string(path) if existed else ""
	await _check(plugin, dock, file, path, shot_path)
	# Deja el archivo como estaba.
	if existed:
		var out := FileAccess.open(path, FileAccess.WRITE)
		out.store_string(before)
		out.close()
	elif FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	return failures


func _check(plugin: Object, dock: Control, file: String, path: String, shot_path: String) -> void:
	var model: SessionModel = dock.get(&"_model")
	_expect(file == "AGENTS.md", "un agente genérico recuerda en AGENTS.md (%s)" % file)
	dock.call(&"_on_submitted", "/recordar El salto del jugador mide 2 tiles")
	await _tree.process_frame
	_expect(ProjectMemory.read_remembered(path) == PackedStringArray(["El salto del jugador mide 2 tiles"]), "/recordar guardó la línea en %s" % file)
	var notices := model.entries().filter(func(e: Variant) -> bool: return (e.get(&"actions") as Array).any(func(a: Dictionary) -> bool: return a.id == "view_memory"))
	_expect(notices.size() == 1, "un aviso con «Ver memoria»")
	_expect(model.entries().filter(func(e: Variant) -> bool: return e.get(&"kind") == 0).is_empty(), "el comando no va al agente")
	# Lo que se manda después lleva la nota, en un sobre.
	var log: Object = plugin.get(&"_log")
	var first_log := (log.call(&"entries") as Array).size()
	dock.call(&"_on_submitted", "Hola")
	await _wait(func() -> bool: return not model.is_busy() and model.entries().any(func(e: Variant) -> bool: return e.get(&"kind") == 1))
	var prompt_lines := (log.call(&"entries") as Array).slice(first_log).filter(func(e: Dictionary) -> bool: return str(e.message).contains("fake_agent: prompt"))
	var prompt := str(prompt_lines[0].message) if not prompt_lines.is_empty() else ""
	_expect(prompt.contains("remembered facts") and prompt.contains("untrusted"), "el próximo prompt lleva la nota en un sobre: %s" % prompt.left(300))
	# Deshacer, y otra vez para la pestaña.
	if not notices.is_empty():
		dock.call(&"_on_action_requested", "remember_undo", (notices[0].get(&"actions") as Array)[0].data)
	_expect(ProjectMemory.read_remembered(path).is_empty(), "«Deshacer» saca la línea")
	dock.call(&"_on_submitted", "/remember Las escenas van en res://scenes")
	await _tree.process_frame
	notices = model.entries().filter(func(e: Variant) -> bool: return (e.get(&"actions") as Array).any(func(a: Dictionary) -> bool: return a.id == "view_memory"))
	dock.call(&"_on_action_requested", "view_memory", notices[notices.size() - 1])
	await _wait(func() -> bool: return plugin.get(&"_extensions_window") != null and (plugin.get(&"_extensions_window") as Window).visible, 10.0)
	var window: Window = plugin.get(&"_extensions_window")
	if window == null:
		_expect(false, "«Ver memoria» abre Extensiones")
		return
	var tabs: TabContainer = window.get(&"_tabs")
	_expect(tabs.current_tab == 7, "en la pestaña Memoria (%d)" % tabs.current_tab)
	var tab: Object = window.get(&"_memory_tab")
	var entries: Array = tab.call(&"entries")
	_expect(entries.any(func(e: Dictionary) -> bool: return e.kind == "remembered" and str(e.text) == "Las escenas van en res://scenes"), "la pestaña lista el recuerdo: %s" % [entries.map(func(e: Dictionary) -> String: return e.text)])
	if not shot_path.is_empty():
		for i in 10:
			await _tree.process_frame
		window.get_texture().get_image().save_png(shot_path.get_basename() + "_memory_tab.png")
	tab.call(&"select_entry", "remembered", "Las escenas")
	tab.call(&"_on_delete")
	_expect(ProjectMemory.read_remembered(path).is_empty(), "«Borrar» en la pestaña saca la línea")
	window.hide()
