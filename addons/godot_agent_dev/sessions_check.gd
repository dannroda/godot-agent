@tool
extends RefCounted
## m7-44 en el editor: «+» abre una segunda sesión en otra pestaña del dock (sin One-shot), con su
## token del server MCP; un archivo que una sesión escribe en su turno queda fuera del alcance de la
## otra hasta que el turno termina; godot.sessions lo muestra; cerrar la pestaña suelta todo.
## Guarda capturas en `<prefijo>_*.png`.

const SessionModel := preload("res://addons/godot_agent/session/session_model.gd")

const MAIN_PLUGIN_SCRIPT := "res://addons/godot_agent/plugin.gd"
const SOURCE := "res://tests/tmp/sessions_source.txt"
const TARGET := "res://tests/tmp/sessions_target.txt"


func run(tree: SceneTree, main_plugin: Object, dock: Control, prefix: String) -> PackedStringArray:
	var failures: PackedStringArray = []
	var tabs: Control = main_plugin.get(&"_tabs")
	var coordinator: Object = main_plugin.get(&"_coordinator")
	var registry: Object = main_plugin.get(&"_registry")
	var server: Object = main_plugin.get(&"_mcp_server")
	var bar: TabBar = tabs.get(&"_bar")
	if bar.tab_count != 1 or bar.get_tab_button_icon(0) != null:
		failures.append("la primera sesión no va sola y sin botón de cerrar")
	(tabs.find_child("NewSessionTabButton", true, false) as Button).pressed.emit()
	await tree.process_frame
	await tree.process_frame
	var ids: PackedStringArray = tabs.call(&"ids")
	if ids.size() != 2 or bar.tab_count != 2 or bar.get_tab_button_icon(1) == null:
		return ["«+» no abrió otra pestaña: %s" % [ids]]
	var second: String = ids[1]
	var second_dock: Control = tabs.call(&"dock", second)
	if not second_dock.visible or dock.visible:
		failures.append("la pestaña nueva no quedó al frente")
	if second_dock.get(&"allow_oneshot") != false:
		failures.append("la segunda sesión ofrece One-shot")
	if coordinator.call(&"sessions") != PackedStringArray(["s1", second]):
		failures.append("sesiones en el coordinador: %s" % [coordinator.call(&"sessions")])
	var second_session: Dictionary = (main_plugin.get(&"_extra_sessions") as Dictionary).get(second, {})
	var entries: Array = main_plugin.call(&"_mcp_servers", second, second_session.get("model"))
	# HTTP lleva el token en el header; el shim stdio (sin agente conectado), en su entorno.
	var token := ""
	if not entries.is_empty() and entries[0].has("headers"):
		token = str(entries[0].headers[0].value).trim_prefix("Bearer ")
	elif not entries.is_empty() and entries[0].has("env"):
		for variable: Dictionary in entries[0].env:
			if variable.name == "GODOT_AGENT_MCP_TOKEN":
				token = str(variable.value)
	if token.is_empty() or token == server.get(&"token"):
		failures.append("la segunda sesión no tiene token propio del server MCP: %s" % [entries])
	await _save_shot(tree, tabs, "%s_two_tabs.png" % prefix)

	# Las dos en Auto: escribir archivos se permite sin tarjeta.
	(main_plugin.get(&"_model") as SessionModel).set_harness_mode(SessionModel.HarnessMode.AUTO)
	(second_session.model as SessionModel).set_harness_mode(SessionModel.HarnessMode.AUTO)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://tests/tmp"))
	var file := FileAccess.open(SOURCE, FileAccess.WRITE)
	file.store_string("hello\n")
	file.close()
	for path: String in [TARGET, TARGET + ".2"]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	var first: Dictionary = await registry.call(&"call_tool", "copy_file", {"from": SOURCE, "to": TARGET}, "")
	if first.isError:
		failures.append("la primera sesión no pudo copiar: %s" % first.content[0].text)
	var blocked: Dictionary = await registry.call(&"call_tool", "delete_file", {"path": TARGET}, second)
	if not blocked.isError or not str(blocked.content[0].text).contains("being edited by «Session 1»"):
		failures.append("la segunda tocó un archivo de la primera: %s" % blocked.content[0].text)
	var listing: Dictionary = await registry.call(&"call_tool", "sessions", {}, second)
	var text := str(listing.content[0].text)
	if not text.contains("«Session 1»") or not text.contains(TARGET):
		failures.append("godot.sessions no muestra lo que edita la otra: %s" % text)
	var message: Dictionary = await registry.call(&"call_tool", "session_send", {"to": "Session 1", "message": "hi"}, second)
	if not message.isError or not str(message.content[0].text).contains("not connected"):
		failures.append("un mensaje a una sesión sin agente no avisa: %s" % message.content[0].text)
	(main_plugin.get(&"_model") as SessionModel).turn_finished.emit("end_turn")
	var after: Dictionary = await registry.call(&"call_tool", "copy_file", {"from": SOURCE, "to": TARGET + ".2"}, second)
	if after.isError:
		failures.append("al terminar el turno de la primera, la segunda sigue sin poder: %s" % after.content[0].text)
	await _save_shot(tree, tabs, "%s_second.png" % prefix)

	# Cerrar la pestaña: el coordinador y el server MCP la olvidan.
	bar.tab_button_pressed.emit(1)
	await tree.process_frame
	if (tabs.call(&"ids") as PackedStringArray).size() != 1 or bar.tab_count != 1 or not dock.visible:
		failures.append("cerrar la pestaña no volvió a la primera sola")
	if coordinator.call(&"sessions") != PackedStringArray(["s1"]):
		failures.append("la sesión cerrada sigue en el coordinador")
	if server.call(&"_caller", "Bearer " + token) != null:
		failures.append("el token de la sesión cerrada sigue valiendo")
	for path: String in [SOURCE, TARGET, TARGET + ".2"]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	(main_plugin.get(&"_model") as SessionModel).set_harness_mode(SessionModel.HarnessMode.ASK)
	return failures


func _save_shot(tree: SceneTree, control: Control, path: String) -> void:
	await tree.process_frame
	var image := control.get_viewport().get_texture().get_image()
	var rect := Rect2i(control.get_global_rect())
	if rect.size.x > 0 and rect.size.y > 0:
		image.get_region(rect).save_png(path)
