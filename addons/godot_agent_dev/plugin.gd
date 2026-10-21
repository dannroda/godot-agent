@tool
extends EditorPlugin
## Herramientas de test que necesitan el editor. No hace nada salvo que se lance con:
## - `-- --godot-agent-cycle-test`: alterna el plugin godot_agent N veces y sale.
##   Código de salida: 0 bien, 1 si quedan nodos huérfanos u objetos que crecen ciclo a ciclo.
## - `-- --godot-agent-screenshot=<ruta.png>`: abre la main screen "Agent", guarda una captura
##   del editor y sale (necesita ventana, no headless).
## - `-- --godot-agent-ui-test=<guion> --godot-agent-ui-shot=<ruta.png>`: conecta el dock al agente
##   falso con tests/scripts/<guion>.json, manda "hola", espera el fin del turno, captura y sale.
## - `-- --godot-agent-sync-test`: abre un script, lo modifica en disco como lo haría el agente y
##   verifica que el editor se actualiza sin el diálogo de "modificado afuera" (buffer limpio) y
##   que no pisa cambios sin guardar (conflicto). Necesita ventana.
## - `-- --godot-agent-claude-edit-test`: verificación de M2 con Claude Code real (gasta tokens).
##   En Construir pide editar un script abierto: tiene que haber permiso con diff y el buffer se
##   actualiza sin diálogos. En Preguntar, la misma edición se deniega y el archivo no cambia.
## - `-- --godot-agent-mcp-test`: llama a cada tool godot.* por HTTP real y prueba el shim stdio
##   (ver mcp_check.gd).
## - `-- --godot-agent-claude-mcp-test`: con Claude Code real (gasta tokens), pregunta cuántos nodos
##   tiene la escena de prueba: tiene que contestar 5 usando godot.scene_tree.
## - `-- --godot-agent-edit-test`: tools de edición, undo por pasos, permisos por modo y el botón
##   "↶ undo" (ver edit_check.gd).
## - `-- --godot-agent-run-test`: run_scene con inputs, capture_game_frame, stop_scene, script roto y
##   ciclo de vida del autoload de playtest (ver run_check.gd). Necesita ventana.
## - `-- --godot-agent-claude-scene-test`: verificación de M4 con Claude Code real (gasta tokens).
##   Pide agregar WaveLabel al HUD y conectar WaveTimer.timeout; Ctrl+Z tiene que deshacerlo en pasos.
## - `-- --godot-agent-crash-test=before|during`: mata el editor con el autoload de playtest recién
##   registrado (before) o con un run_scene en curso (during). Al reabrir, no tiene que quedar.

const CYCLE_ARG := "--godot-agent-cycle-test"
const SCREENSHOT_ARG := "--godot-agent-screenshot="
const UI_TEST_ARG := "--godot-agent-ui-test="
const UI_SHOT_ARG := "--godot-agent-ui-shot="
const AgentProfile := preload("res://addons/godot_agent/core/agent_profile.gd")
const ChatEntry := preload("res://addons/godot_agent/session/chat_entry.gd")
const SessionModel := preload("res://addons/godot_agent/session/session_model.gd")
const DOCK_SCRIPT := "res://addons/godot_agent/ui/dock/agent_dock.gd"
const SYNC_ARG := "--godot-agent-sync-test"
const SYNC_SCRIPT := "res://addons/godot_agent/editor/editor_sync.gd"
const SYNC_TARGET := "res://tests/tmp/sync_target.gd"
const CLAUDE_EDIT_ARG := "--godot-agent-claude-edit-test"
const CLAUDE_EDIT_TARGET := "res://tests/tmp/claude_target.gd"
const CLAUDE_TIMEOUT_S := 420.0
const MCP_ARG := "--godot-agent-mcp-test"
const CLAUDE_MCP_ARG := "--godot-agent-claude-mcp-test"
const McpCheck := preload("mcp_check.gd")
const EDIT_ARG := "--godot-agent-edit-test"
const EditCheck := preload("edit_check.gd")
const RUN_ARG := "--godot-agent-run-test"
const RunCheck := preload("run_check.gd")
const CLAUDE_SCENE_ARG := "--godot-agent-claude-scene-test"
const CLAUDE_HUD_FIXTURE := "res://tests/fixtures/hud_fixture.tscn"
const CLAUDE_HUD_SCENE := "res://tests/tmp/claude_hud.tscn"
const CRASH_ARG := "--godot-agent-crash-test="
const MAIN_PLUGIN_SCRIPT := "res://addons/godot_agent/plugin.gd"
const RUN_FIXTURE := "res://tests/fixtures/run_fixture.tscn"
const EditorUndo := preload("res://addons/godot_agent/editor/editor_undo.gd")
const PlaytestAutoload := preload("res://addons/godot_agent/playtest/playtest_autoload.gd")
const MAIN_SCREEN_NAME := "Agent"
const TARGET_PLUGIN := "godot_agent"
const CYCLES := 5
const SETTLE_FRAMES := 5
const SAFETY_TIMEOUT_S := 120.0
## Margen de objetos que se toleran entre el primer y el último ciclo (cachés del editor, tooltips…).
const OBJECT_GROWTH_TOLERANCE := 50


func _enter_tree() -> void:
	var args := OS.get_cmdline_user_args()
	if CYCLE_ARG in args:
		_run_cycle_test.call_deferred()
	if SYNC_ARG in args:
		_run_sync_test.call_deferred()
	if CLAUDE_EDIT_ARG in args:
		_run_claude_edit_test.call_deferred()
	if MCP_ARG in args:
		_run_mcp_test.call_deferred()
	if CLAUDE_MCP_ARG in args:
		_run_claude_mcp_test.call_deferred()
	if EDIT_ARG in args:
		_run_edit_test.call_deferred()
	if RUN_ARG in args:
		_run_run_test.call_deferred()
	if CLAUDE_SCENE_ARG in args:
		_run_claude_scene_test.call_deferred()
	for arg: String in args:
		if arg.begins_with(SCREENSHOT_ARG):
			_take_screenshot.call_deferred(arg.trim_prefix(SCREENSHOT_ARG))
		if arg.begins_with(CRASH_ARG):
			_run_crash_test.call_deferred(arg.trim_prefix(CRASH_ARG))
		if arg.begins_with(UI_TEST_ARG):
			_run_ui_test.call_deferred(arg.trim_prefix(UI_TEST_ARG), _arg_value(UI_SHOT_ARG))


func _run_sync_test() -> void:
	get_tree().create_timer(SAFETY_TIMEOUT_S).timeout.connect(_on_safety_timeout)
	var failures: PackedStringArray = []
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://tests/tmp"))
	_write(SYNC_TARGET, "extends Node\n\nvar a := 1\n\nfunc _ready() -> void:\n\tpass\n")
	EditorInterface.get_resource_filesystem().update_file(SYNC_TARGET)
	await get_tree().create_timer(1.5).timeout
	var sync: Node = _find_by_script(SYNC_SCRIPT)
	if sync == null:
		_finish(1, "no se encontró EditorSync")
		return
	EditorInterface.edit_script(load(SYNC_TARGET), 5)
	await get_tree().create_timer(1.0).timeout
	var code_edit := EditorInterface.get_script_editor().get_current_editor().get_base_editor() as CodeEdit
	code_edit.set_caret_line(5)
	code_edit.set_caret_column(1)

	# A · buffer limpio, el agente escribe a disco por su cuenta (sin fs/write): lo toma el watcher.
	var agent_text := "extends Node\n\nsignal hit\n\nvar a := 2\n\nfunc _ready() -> void:\n\tpass\n"
	await get_tree().create_timer(1.1).timeout  # mtime con resolución de 1 s
	_write(SYNC_TARGET, agent_text)
	await get_tree().create_timer(1.5).timeout
	get_tree().root.propagate_notification(NOTIFICATION_APPLICATION_FOCUS_IN)
	await get_tree().create_timer(1.0).timeout
	if code_edit.text != agent_text:
		failures.append("A: el buffer no se actualizó")
	if code_edit.get_caret_line() != 7:
		failures.append("A: el cursor no siguió a su línea (%d)" % code_edit.get_caret_line())
	if code_edit.get_version() != code_edit.get_saved_version():
		failures.append("A: el buffer quedó marcado como modificado")
	failures.append_array(_visible_dialogs("A"))
	code_edit.undo()
	if code_edit.text.contains("signal hit"):
		failures.append("A: un solo Ctrl+Z no deshace la recarga")
	code_edit.redo()
	code_edit.tag_saved_version()

	# B · el usuario tiene cambios sin guardar: no se pisa, queda un conflicto.
	code_edit.set_caret_line(0)
	code_edit.set_caret_column(0)
	code_edit.insert_text_at_caret("# cambio del usuario\n")
	await get_tree().create_timer(1.1).timeout
	_write(SYNC_TARGET, agent_text.replace("var a := 2", "var a := 3"))
	await get_tree().create_timer(1.5).timeout
	if not code_edit.text.begins_with("# cambio del usuario"):
		failures.append("B: se pisó el buffer del usuario")
	if not SYNC_TARGET in sync.call(&"conflicts"):
		failures.append("B: no se detectó el conflicto")
	sync.call(&"resolve_use_disk", SYNC_TARGET)
	await get_tree().process_frame
	if not code_edit.text.contains("var a := 3") or code_edit.text.contains("# cambio del usuario"):
		failures.append("B: 'usar la del agente' no cargó la versión del disco")
	get_tree().root.propagate_notification(NOTIFICATION_APPLICATION_FOCUS_IN)
	await get_tree().create_timer(1.0).timeout
	failures.append_array(_visible_dialogs("B"))

	# C · fs/write: after_agent_write inmediato.
	await get_tree().create_timer(1.1).timeout
	_write(SYNC_TARGET, agent_text.replace("var a := 2", "var a := 4"))
	sync.call(&"after_agent_write", ProjectSettings.globalize_path(SYNC_TARGET))
	if not code_edit.text.contains("var a := 4"):
		failures.append("C: after_agent_write no actualizó el buffer")
	get_tree().root.propagate_notification(NOTIFICATION_APPLICATION_FOCUS_IN)
	await get_tree().create_timer(1.0).timeout
	failures.append_array(_visible_dialogs("C"))

	for failure: String in failures:
		print("[sync-test] FALLA ", failure)
	_finish(0 if failures.is_empty() else 1, "sync-test: %d fallas" % failures.size())


func _run_claude_edit_test() -> void:
	get_tree().create_timer(CLAUDE_TIMEOUT_S).timeout.connect(_on_safety_timeout)
	var failures: PackedStringArray = []
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://tests/tmp"))
	var original := "extends Node\n\nvar speed := 1\n\n\nfunc _ready() -> void:\n\tprint(speed)\n"
	_write(CLAUDE_EDIT_TARGET, original)
	EditorInterface.get_resource_filesystem().update_file(CLAUDE_EDIT_TARGET)
	await get_tree().create_timer(2.0).timeout
	var dock := _find_dock()
	if dock == null:
		_finish(1, "no se encontró el dock")
		return
	EditorInterface.edit_script(load(CLAUDE_EDIT_TARGET), 6)
	await get_tree().create_timer(1.0).timeout
	var code_edit := EditorInterface.get_script_editor().get_current_editor().get_base_editor() as CodeEdit
	code_edit.set_caret_line(6)
	var controller: Object = dock.get(&"_controller")
	var model: Object = dock.get(&"_model")
	var requests: Array = []
	model.connect(&"permission_requested", func(request: Object) -> void:
		requests.append(request)
		print("[claude-edit] permiso: %s · grupo %s · diff %s" % [request.get(&"title"), request.get(&"group"), not (request.get(&"diff") as Dictionary).is_empty()])
		var option: String = request.call(&"option_id_for", PackedStringArray(["allow_once"]))
		request.call(&"select", option)
	)
	var profile := AgentProfile.from_dict(AgentProfile.defaults()[0])
	if not await controller.call(&"start", profile):
		_finish(1, "no arrancó Claude: %s" % model.get(&"failure_message"))
		return
	var abs_path := ProjectSettings.globalize_path(CLAUDE_EDIT_TARGET)

	# Construir: edición con permiso y diff.
	model.call(&"set_harness_mode", SessionModel.HarnessMode.BUILD)
	var stop: String = await controller.call(&"send_prompt",
		"En %s cambiá `var speed := 1` por `var speed := 2` con tu herramienta de edición. No leas ni toques otros archivos, no corras comandos." % abs_path)
	print("[claude-edit] construir: stopReason=%s" % stop)
	await get_tree().create_timer(1.5).timeout
	if requests.is_empty():
		failures.append("Construir: no se pidió permiso")
	elif (requests[0].get(&"diff") as Dictionary).is_empty():
		failures.append("Construir: el permiso no trajo diff")
	if not FileAccess.get_file_as_string(CLAUDE_EDIT_TARGET).contains("var speed := 2"):
		failures.append("Construir: el archivo no cambió")
	if not code_edit.text.contains("var speed := 2"):
		failures.append("Construir: el buffer no se actualizó")
	if code_edit.get_version() != code_edit.get_saved_version():
		failures.append("Construir: el buffer quedó modificado")
	get_tree().root.propagate_notification(NOTIFICATION_APPLICATION_FOCUS_IN)
	await get_tree().create_timer(1.0).timeout
	failures.append_array(_visible_dialogs("Construir"))

	# Preguntar: la misma clase de edición se deniega sin tarjeta.
	var asked := requests.size()
	model.call(&"set_harness_mode", SessionModel.HarnessMode.ASK)
	stop = await controller.call(&"send_prompt",
		"Intentá ahora cambiar `var speed := 2` por `var speed := 3` en %s con tu herramienta de edición, una sola vez. Si no se puede, decilo y terminá." % abs_path)
	print("[claude-edit] preguntar: stopReason=%s" % stop)
	await get_tree().create_timer(1.0).timeout
	if requests.size() != asked:
		failures.append("Preguntar: apareció una tarjeta de permiso")
	if FileAccess.get_file_as_string(CLAUDE_EDIT_TARGET).contains("var speed := 3") or code_edit.text.contains("var speed := 3"):
		failures.append("Preguntar: el archivo cambió")
	for entry: Object in model.call(&"entries"):
		if int(entry.get(&"kind")) == ChatEntry.Kind.NOTICE:
			print("[claude-edit] aviso: ", entry.get(&"text"))
		elif int(entry.get(&"kind")) == ChatEntry.Kind.AGENT:
			print("[claude-edit] agente: ", str(entry.get(&"text")).left(300).replace("\n", " "))
	controller.call(&"stop")
	for failure: String in failures:
		print("[claude-edit] FALLA ", failure)
	_finish(0 if failures.is_empty() else 1, "claude-edit: %d fallas" % failures.size())


func _run_mcp_test() -> void:
	get_tree().create_timer(SAFETY_TIMEOUT_S).timeout.connect(_on_safety_timeout)
	await get_tree().create_timer(2.0).timeout
	var failures: PackedStringArray = await McpCheck.new().run(get_tree())
	for failure: String in failures:
		print("[mcp-check] FALLA ", failure)
	_finish(0 if failures.is_empty() else 1, "mcp-test: %d fallas" % failures.size())


func _run_edit_test() -> void:
	get_tree().create_timer(SAFETY_TIMEOUT_S).timeout.connect(_on_safety_timeout)
	await get_tree().create_timer(2.0).timeout
	var failures: PackedStringArray = await EditCheck.new().run_edit(get_tree())
	for failure: String in failures:
		print("[edit-check] FALLA ", failure)
	_finish(0 if failures.is_empty() else 1, "edit-test: %d fallas" % failures.size())


func _run_run_test() -> void:
	get_tree().create_timer(SAFETY_TIMEOUT_S).timeout.connect(_on_safety_timeout)
	await get_tree().create_timer(2.0).timeout
	var failures: PackedStringArray = await RunCheck.new().run_run(get_tree())
	for failure: String in failures:
		print("[run-check] FALLA ", failure)
	_finish(0 if failures.is_empty() else 1, "run-test: %d fallas" % failures.size())


func _run_claude_scene_test() -> void:
	get_tree().create_timer(CLAUDE_TIMEOUT_S).timeout.connect(_on_safety_timeout)
	await get_tree().create_timer(2.0).timeout
	var dock := _find_dock()
	if dock == null:
		_finish(1, "no se encontró el dock")
		return
	_write(CLAUDE_HUD_SCENE, FileAccess.get_file_as_string(CLAUDE_HUD_FIXTURE))
	EditorInterface.get_resource_filesystem().update_file(CLAUDE_HUD_SCENE)
	await get_tree().create_timer(0.5).timeout
	if CLAUDE_HUD_SCENE in EditorInterface.get_open_scenes():
		EditorInterface.reload_scene_from_path(CLAUDE_HUD_SCENE)
	EditorInterface.open_scene_from_path(CLAUDE_HUD_SCENE)
	await get_tree().create_timer(0.5).timeout
	var controller: Object = dock.get(&"_controller")
	var model: Object = dock.get(&"_model")
	if not await controller.call(&"start", AgentProfile.from_dict(AgentProfile.defaults()[0])):
		_finish(1, "no arrancó Claude: %s" % model.get(&"failure_message"))
		return
	model.call(&"set_harness_mode", SessionModel.HarnessMode.ONESHOT)
	var stop: String = await controller.call(&"send_prompt",
		"En la escena abierta (%s) agregá un Label llamado WaveLabel como hijo de HUD, con el texto \"Oleada 1\", y conectá la señal timeout de WaveTimer al método _on_wave_timer_timeout de WaveLabel. Usá las tools godot.* del server MCP godot; no edites el .tscn en disco, no crees scripts y no guardes la escena." % CLAUDE_HUD_SCENE)
	var tools: PackedStringArray = []
	for entry: Object in model.call(&"entries"):
		if int(entry.get(&"kind")) == ChatEntry.Kind.TOOL_GROUP:
			for id: String in entry.get(&"tool_call_ids"):
				tools.append(str(model.call(&"tool_call", id).call(&"display_name")))
	print("[claude-scene] stopReason=%s tools: %s" % [stop, ", ".join(tools)])
	controller.call(&"stop")
	var failures: PackedStringArray = []
	var root := EditorInterface.get_edited_scene_root()
	var label := root.get_node_or_null("HUD/WaveLabel") as Label if root else null
	var timer := root.get_node_or_null("WaveTimer") if root else null
	var connected := func() -> bool:
		return is_instance_valid(label) and timer and timer.is_connected("timeout", Callable(label, "_on_wave_timer_timeout"))
	if label == null or label.owner != root or label.text != "Oleada 1":
		failures.append("WaveLabel no está bajo HUD con owner y texto")
	if not connected.call():
		failures.append("WaveTimer.timeout no está conectado a WaveLabel")
	if failures.is_empty():
		EditorUndo._trigger_editor_undo()
		if connected.call() or root.get_node_or_null("HUD/WaveLabel") == null:
			failures.append("el primer Ctrl+Z no deshizo solo la conexión")
		for i in 5:
			if root.get_node_or_null("HUD/WaveLabel") == null:
				break
			EditorUndo._trigger_editor_undo()
		if root.get_node_or_null("HUD/WaveLabel") != null:
			failures.append("Ctrl+Z no sacó WaveLabel")
	if FileAccess.get_file_as_string(CLAUDE_HUD_SCENE).contains("WaveLabel"):
		failures.append("Claude guardó o editó el .tscn en disco")
	for failure: String in failures:
		print("[claude-scene] FALLA ", failure)
	_finish(0 if failures.is_empty() else 1, "claude-scene: %d fallas" % failures.size())


## Mata el editor en la ventana de riesgo del autoload de playtest; el script de shell reabre y verifica.
func _run_crash_test(when: String) -> void:
	await get_tree().create_timer(2.0).timeout
	var main_plugin := _find_by_script(MAIN_PLUGIN_SCRIPT)
	if main_plugin == null:
		_finish(1, "no se encontró el plugin godot_agent")
		return
	if when == "during":
		var run_tools: Object = main_plugin.get(&"_run_tools")
		run_tools.call(&"_run_scene", {"scene": RUN_FIXTURE, "seconds": 60})
		var deadline := Time.get_ticks_msec() + 20000
		while Time.get_ticks_msec() < deadline and not (EditorInterface.is_playing_scene() and not PlaytestAutoload.is_registered()):
			await get_tree().process_frame
		await get_tree().create_timer(1.0).timeout
	else:
		PlaytestAutoload.register(main_plugin)
	var on_disk := FileAccess.get_file_as_string("res://project.godot").contains(PlaytestAutoload.NAME)
	print("[crash-test] %s: autoload en project.godot al matar: %s" % [when, on_disk])
	OS.kill(OS.get_process_id())


func _run_claude_mcp_test() -> void:
	get_tree().create_timer(CLAUDE_TIMEOUT_S).timeout.connect(_on_safety_timeout)
	await get_tree().create_timer(2.0).timeout
	var dock := _find_dock()
	if dock == null:
		_finish(1, "no se encontró el dock")
		return
	var controller: Object = dock.get(&"_controller")
	var model: Object = dock.get(&"_model")
	var log_sink: Object = controller.get(&"agent_log")
	log_sink.connect(&"entry_added", func(entry: Dictionary) -> void:
		if entry.channel == &"mcp":
			print("[claude-mcp] mcp: ", str(entry.message).left(200))
	)
	if not await controller.call(&"start", AgentProfile.from_dict(AgentProfile.defaults()[0])):
		_finish(1, "no arrancó Claude: %s" % model.get(&"failure_message"))
		return
	print("[claude-mcp] http MCP: ", model.call(&"supports_http_mcp"))
	model.call(&"set_harness_mode", SessionModel.HarnessMode.ASK)
	var stop: String = await controller.call(&"send_prompt",
		"¿Cuántos nodos tiene la escena res://tests/fixtures/main_fixture.tscn? Usá la tool scene_tree del server MCP godot y respondé con el número y la lista de nombres.")
	var used_scene_tree := false
	var reply := ""
	for entry: Object in model.call(&"entries"):
		if int(entry.get(&"kind")) == ChatEntry.Kind.AGENT:
			reply += str(entry.get(&"text"))
		elif int(entry.get(&"kind")) == ChatEntry.Kind.TOOL_GROUP:
			for id: String in entry.get(&"tool_call_ids"):
				var call: Object = model.call(&"tool_call", id)
				print("[claude-mcp] tool call: %s · %s" % [call.call(&"display_name"), call.get(&"status")])
				used_scene_tree = used_scene_tree or str(call.call(&"display_name")).contains("scene_tree")
	print("[claude-mcp] stopReason=%s respuesta: %s" % [stop, reply.replace("\n", " ").left(400)])
	controller.call(&"stop")
	var failures: PackedStringArray = []
	if not used_scene_tree:
		failures.append("no usó godot.scene_tree")
	if not reply.contains("5"):
		failures.append("la respuesta no dice 5")
	for failure: String in failures:
		print("[claude-mcp] FALLA ", failure)
	_finish(0 if failures.is_empty() else 1, "claude-mcp: %d fallas" % failures.size())


func _write(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()


func _find_by_script(path: String) -> Node:
	for node: Node in get_tree().root.find_children("*", "Node", true, false):
		var script := node.get_script() as Script
		if script and script.resource_path == path:
			return node
	return null


## Diálogos visibles del editor (p. ej. "Los siguientes archivos son más nuevos en disco").
func _visible_dialogs(label: String) -> PackedStringArray:
	var found: PackedStringArray = []
	for window: Node in EditorInterface.get_base_control().find_children("*", "AcceptDialog", true, false):
		var dialog := window as AcceptDialog
		if dialog.visible:
			found.append("%s: diálogo visible '%s': %s" % [label, dialog.title, dialog.dialog_text.left(120)])
			dialog.hide()
	return found


func _arg_value(prefix: String) -> String:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with(prefix):
			return arg.trim_prefix(prefix)
	return ""


func _find_dock() -> Control:
	for node: Node in EditorInterface.get_base_control().find_children("*", "VBoxContainer", true, false):
		if node.get_script() and (node.get_script() as Script).resource_path == DOCK_SCRIPT:
			var holder := node.get_parent()
			if holder.has_method(&"make_visible"):
				holder.call(&"make_visible")
			elif holder is TabContainer:
				(holder as TabContainer).current_tab = node.get_index()
			return node
	return null


func _run_ui_test(scenario: String, shot_path: String) -> void:
	get_tree().create_timer(SAFETY_TIMEOUT_S).timeout.connect(_on_safety_timeout)
	await get_tree().create_timer(2.0).timeout
	var dock := _find_dock()
	if dock == null:
		_finish(1, "no se encontró el dock")
		return
	var controller: Object = dock.get(&"_controller")
	var model: Object = dock.get(&"_model")
	var profile := AgentProfile.from_dict({
		"id": "fake", "display_name": "Agente falso", "command": OS.get_executable_path(),
		"args": ["--headless", "--no-header", "--path", ProjectSettings.globalize_path("res://"),
			"--script", "res://tests/fake_agent.gd", "--", "--scenario=res://tests/scripts/%s.json" % scenario],
	})
	var ok: bool = await controller.call(&"start", profile)
	if not ok:
		_finish(1, "no arrancó la sesión: %s" % model.get(&"failure_message"))
		return
	dock.call(&"add_context_files", PackedStringArray(["res://project.godot"]))
	var chips: Dictionary = dock.get(&"_chips")
	if not chips.has("file:res://project.godot"):
		_finish(1, "+ contexto no agregó el chip del archivo")
		return
	dock.call(&"_on_submitted", "hola, ¿qué hay que hacer con las oleadas?")
	chips = dock.get(&"_chips")
	if chips.has("file:res://project.godot"):
		_finish(1, "el chip del archivo siguió después de enviar")
		return
	while int(model.get(&"state")) != 2:  # READY
		await get_tree().process_frame
	await get_tree().create_timer(0.5).timeout
	dock.emit_signal(&"show_log_requested")
	await get_tree().create_timer(0.5).timeout
	var entries: Array = model.call(&"entries")
	print("[ui-test] %d entradas, título '%s'" % [entries.size(), model.get(&"title")])
	if not shot_path.is_empty():
		var image := EditorInterface.get_base_control().get_viewport().get_texture().get_image()
		image.save_png(shot_path)
	controller.call(&"stop")
	_finish(0, "ui-test %s" % scenario)


func _take_screenshot(path: String) -> void:
	get_tree().create_timer(SAFETY_TIMEOUT_S).timeout.connect(_on_safety_timeout)
	await get_tree().create_timer(3.0).timeout
	for dock: Node in EditorInterface.get_base_control().find_children("*", "EditorDock", true, false):
		print("[dbg] dock title=%s parent=%s inside=%s visible=%s slot=%s child=%s" % [dock.get(&"title"), dock.get_parent().get_path() if dock.get_parent() else "-", dock.is_inside_tree(), (dock as Control).visible, dock.get(&"default_slot"), dock.get_child(0).name if dock.get_child_count() > 0 else "-"])
	EditorInterface.set_main_screen_editor(MAIN_SCREEN_NAME)
	await get_tree().create_timer(1.0).timeout
	var image := EditorInterface.get_base_control().get_viewport().get_texture().get_image()
	var err := image.save_png(path)
	_finish(0 if err == OK else 1, "captura en %s (%s)" % [path, error_string(err)])


func _run_cycle_test() -> void:
	get_tree().create_timer(SAFETY_TIMEOUT_S).timeout.connect(_on_safety_timeout)
	await _settle()
	# Si el editor está escaneando (p. ej. después de abrir el proyecto con otra versión), los
	# objetos crecen solos: se espera a que termine.
	var fs := EditorInterface.get_resource_filesystem()
	while fs.is_scanning():
		await get_tree().process_frame
	await get_tree().create_timer(1.0).timeout
	if not EditorInterface.is_plugin_enabled(TARGET_PLUGIN):
		EditorInterface.set_plugin_enabled(TARGET_PLUGIN, true)
		await _settle()

	# La línea base se toma después del primer ciclo: el editor termina de restaurar su estado
	# (pestañas de scripts, escenas abiertas) recién en los primeros frames y crea nodos sueltos
	# propios que no son del addon.
	var orphans_before: int = -1
	var orphan_ids_before: Array = []
	var objects_after_first: int = -1
	for i: int in CYCLES:
		EditorInterface.set_plugin_enabled(TARGET_PLUGIN, false)
		await _settle()
		if EditorInterface.is_plugin_enabled(TARGET_PLUGIN):
			_finish(1, "cycle %d: el plugin no se deshabilitó" % (i + 1))
			return
		EditorInterface.set_plugin_enabled(TARGET_PLUGIN, true)
		await _settle()
		if not EditorInterface.is_plugin_enabled(TARGET_PLUGIN):
			_finish(1, "cycle %d: el plugin no se habilitó" % (i + 1))
			return
		var objects: int = _objects()
		if i == 0:
			objects_after_first = objects
			orphans_before = _orphans()
			orphan_ids_before = _orphan_ids()
		print("[cycle-test] cycle %d ok · objects=%d orphan_nodes=%d" % [i + 1, objects, _orphans()])

	var orphans_after: int = _orphans()
	var growth: int = _objects() - objects_after_first
	var addon_orphans := _addon_orphans()
	if not addon_orphans.is_empty():
		_finish(1, "nodos huérfanos del addon: %s" % ", ".join(addon_orphans))
	elif orphans_after > orphans_before:
		_print_new_orphans(orphan_ids_before)
		_finish(1, "quedaron %d nodos huérfanos nuevos" % (orphans_after - orphans_before))
	elif growth > OBJECT_GROWTH_TOLERANCE:
		_finish(1, "los objetos crecieron %d entre el ciclo 1 y el %d" % [growth, CYCLES])
	else:
		_finish(0, "%d ciclos sin huérfanos (crecimiento de objetos: %d)" % [CYCLES, growth])


func _settle() -> void:
	for i: int in SETTLE_FRAMES:
		await get_tree().process_frame


func _objects() -> int:
	return int(Performance.get_monitor(Performance.OBJECT_COUNT))


func _orphans() -> int:
	return int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))


## Node.get_orphan_node_ids() no existe en 4.4: se llama por reflexión para que el script parsee igual.
func _orphan_ids() -> Array:
	if not ClassDB.class_has_method(&"Node", &"get_orphan_node_ids"):
		return []
	return ClassDB.call(&"class_call_static", &"Node", &"get_orphan_node_ids")


## Huérfanos con un script del addon (solo 4.5+, donde existe get_orphan_node_ids).
func _addon_orphans() -> PackedStringArray:
	var result: PackedStringArray = []
	for id: int in _orphan_ids():
		var node := instance_from_id(id) as Node
		var script := node.get_script() as Script if node else null
		if script and script.resource_path.begins_with("res://addons/godot_agent/"):
			result.append("%s (%s)" % [node.name, script.resource_path.get_file()])
	return result


func _print_new_orphans(before: Array) -> void:
	for id: int in _orphan_ids():
		if id in before:
			continue
		var node := instance_from_id(id) as Node
		if node:
			print("[cycle-test] huérfano nuevo: '%s' (%s) title=%s children=%s" % [node.name, node.get_class(), node.get(&"title"), node.get_children()])


func _on_safety_timeout() -> void:
	_finish(1, "timeout")


func _finish(code: int, message: String) -> void:
	print("[cycle-test] %s: %s" % ["PASS" if code == 0 else "FAIL", message])
	get_tree().quit(code)
