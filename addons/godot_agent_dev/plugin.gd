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
## - `-- --godot-agent-external-test`: el agente escribe `project.godot` y una escena abierta por
##   su cuenta (como el Write de Claude Code): el editor los toma sin el diálogo de "modificado
##   afuera" (settings aplicados, escena recargada) y no pisa una escena con cambios sin guardar.
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
## - `-- --godot-agent-review-test [--godot-agent-ui-shot=<ruta.png>]`: modo Revisar con el agente
##   falso sobre tests/fixtures/review/ (ver review_check.gd). Necesita ventana.
## - `-- --godot-agent-oneshot-test [--godot-agent-ui-shot=<ruta.png>]`: la pantalla Agent maneja un
##   One-shot con el agente falso sobre un repo temporal (cuota, checkpoints, Volver acá, Aceptar).
## - `-- --godot-agent-claude-oneshot-test [--godot-agent-ui-shot=<ruta.png>]`: One-shot de Pong
##   con Claude Code real (gasta tokens), dentro del sandbox de `tests/make_sandbox.sh <dir> --dev`.
## - `-- --godot-agent-long-test`: sesión de más de 600 entradas con el agente falso; mide los frames
##   y comprueba el tope de vistas vivas y "Mostrar anteriores".
## - `-- --godot-agent-completion-test [--godot-agent-ui-shot=<prefijo>]`: completado en el Script
##   Editor real (M8a y M8b): tipea con eventos de teclado y verifica ghost text, Tab, Esc, undo, un
##   bloque de varias líneas y Ctrl+→.
## - `-- --godot-agent-claude-review-test`: lo mismo con Claude Code real (gasta tokens): los tres
##   bugs sembrados tienen que quedar anotados en su línea.
## - `-- --godot-agent-login-test [--godot-agent-ui-shot=<ruta.png>]`: el agente falso pide login
##   (tests/scripts/auth.json); desde los botones del dock corre el login, pega el código en el
##   diálogo y la sesión abre.
## - `-- --godot-agent-queue-test [--godot-agent-ui-shot=<ruta.png>]`: con un turno largo
##   (tests/scripts/cancel.json) se escriben dos prompts en el composer: quedan en cola, el cancel
##   la pausa, «Enviar ahora» la retoma y salen los dos en orden.
## - `-- --godot-agent-i18n-test`: con GODOT_AGENT_LANGUAGE=es, recorre el dock, la pantalla Agent,
##   el Agent Log y cada página de Settings: ningún texto visible que tenga traducción queda en inglés.

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
const EXTERNAL_ARG := "--godot-agent-external-test"
const EXTERNAL_SCENE := "res://tests/fixtures/main_fixture.tscn"
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
const REVIEW_ARG := "--godot-agent-review-test"
const CLAUDE_REVIEW_ARG := "--godot-agent-claude-review-test"
const ONESHOT_ARG := "--godot-agent-oneshot-test"
const CLAUDE_ONESHOT_ARG := "--godot-agent-claude-oneshot-test"
const LONG_ARG := "--godot-agent-long-test"
const SETTINGS_ARG := "--godot-agent-settings-shots="
const HISTORY_ARG := "--godot-agent-history-test="
const LOGIN_ARG := "--godot-agent-login-test"
const QUEUE_ARG := "--godot-agent-queue-test"
const COMPLETION_ARG := "--godot-agent-completion-test"
const I18N_ARG := "--godot-agent-i18n-test"
const I18N_CATALOG := "res://addons/godot_agent/i18n/es.po"
const MAIN_SCREEN_SCRIPT := "res://addons/godot_agent/ui/main_screen/agent_main_screen.gd"
const LOG_PANEL_SCRIPT := "res://addons/godot_agent/ui/log_panel/agent_log_panel.gd"
## Ids que se muestran tal cual aunque coincidan con un msgid (canales del Agent Log).
const I18N_IDS: Array[String] = ["quota"]
const CompletionCheck := preload("completion_check.gd")
const LongSessionCheck := preload("long_session_check.gd")
const CLAUDE_ONESHOT_TIMEOUT_S := 2700.0
const OneShotUiCheck := preload("oneshot_ui_check.gd")
const ReviewCheck := preload("review_check.gd")
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
	if EXTERNAL_ARG in args:
		_run_external_test.call_deferred()
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
	if REVIEW_ARG in args:
		_run_review_test.call_deferred(false)
	if CLAUDE_REVIEW_ARG in args:
		_run_review_test.call_deferred(true)
	if ONESHOT_ARG in args:
		_run_oneshot_test.call_deferred()
	if CLAUDE_ONESHOT_ARG in args:
		_run_claude_oneshot_test.call_deferred()
	if LONG_ARG in args:
		_run_long_test.call_deferred()
	if COMPLETION_ARG in args:
		_run_completion_test.call_deferred()
	if LOGIN_ARG in args:
		_run_login_test.call_deferred(_arg_value(UI_SHOT_ARG))
	if QUEUE_ARG in args:
		_run_queue_test.call_deferred(_arg_value(UI_SHOT_ARG))
	if I18N_ARG in args:
		_run_i18n_test.call_deferred()
	for arg: String in args:
		if arg.begins_with(SCREENSHOT_ARG):
			_take_screenshot.call_deferred(arg.trim_prefix(SCREENSHOT_ARG))
		if arg.begins_with(CRASH_ARG):
			_run_crash_test.call_deferred(arg.trim_prefix(CRASH_ARG))
		if arg.begins_with(HISTORY_ARG):
			_run_history_test.call_deferred(arg.trim_prefix(HISTORY_ARG))
		if arg.begins_with(SETTINGS_ARG):
			_run_settings_shots.call_deferred(arg.trim_prefix(SETTINGS_ARG))
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


func _run_external_test() -> void:
	get_tree().create_timer(SAFETY_TIMEOUT_S).timeout.connect(_on_safety_timeout)
	var failures: PackedStringArray = []
	await get_tree().create_timer(1.5).timeout
	var sync: Node = _find_by_script(SYNC_SCRIPT)
	if sync == null:
		_finish(1, "no se encontró EditorSync")
		return
	EditorInterface.open_scene_from_path(EXTERNAL_SCENE)
	await get_tree().create_timer(1.0).timeout
	var project_text := FileAccess.get_file_as_string("res://project.godot")
	var scene_text := FileAccess.get_file_as_string(EXTERNAL_SCENE)
	var applied: Array[PackedStringArray] = []
	var on_applied := func(names: PackedStringArray) -> void: applied.append(names)
	sync.connect(&"project_settings_applied", on_applied)

	# A · el agente edita project.godot: una acción de input nueva y una descripción.
	await get_tree().create_timer(1.1).timeout  # mtime con resolución de 1 s
	var event := "Object(InputEventKey,\"resource_local_to_scene\":false,\"resource_name\":\"\",\"device\":-1,\"window_id\":0,\"alt_pressed\":false,\"shift_pressed\":false,\"ctrl_pressed\":false,\"meta_pressed\":false,\"pressed\":false,\"keycode\":0,\"physical_keycode\":74,\"key_label\":0,\"unicode\":106,\"location\":0,\"echo\":false,\"script\":null)"
	var edited := project_text.replace("[application]\n", "[application]\n\nconfig/description=\"Editado por el agente\"\n")
	if not edited.contains("[input]"):
		edited += "\n[input]\n"
	edited = edited.replace("[input]\n", "[input]\n\nagent_jump={\n\"deadzone\": 0.2,\n\"events\": [%s]\n}\n" % event)
	_write("res://project.godot", edited)
	await get_tree().create_timer(1.5).timeout
	get_tree().root.propagate_notification(NOTIFICATION_APPLICATION_FOCUS_IN)
	await get_tree().create_timer(1.0).timeout
	if ProjectSettings.get_setting("application/config/description", "") != "Editado por el agente":
		failures.append("A: la descripción no llegó a ProjectSettings")
	var action: Variant = ProjectSettings.get_setting("input/agent_jump", null)
	if not action is Dictionary or (action.get("events", []) as Array).size() != 1 or not action.events[0] is InputEventKey:
		failures.append("A: la acción de input no llegó a ProjectSettings (%s)" % [action])
	failures.append_array(_visible_dialogs("A"))
	if applied.size() != 1 or applied[0] != PackedStringArray(["application/config/description", "input/agent_jump"]):
		failures.append("A: tenía que aplicar solo lo que cambió (%s)" % [applied])

	# B · el agente edita la escena abierta, sin cambios del usuario: se recarga sola. Godot 4.6 no
	# tiene get_unsaved_scenes: no se puede saber si hay cambios, así que avisa y no recarga.
	var supports_unsaved := EditorInterface.has_method(&"get_unsaved_scenes")
	var notices: Array[String] = []
	var on_modified := func(res_path: String) -> void: notices.append(res_path)
	sync.connect(&"open_scene_modified", on_modified)
	await get_tree().create_timer(1.1).timeout
	_write(EXTERNAL_SCENE, scene_text.replace("speed = 300.0", "speed = 450.0"))
	await get_tree().create_timer(1.5).timeout
	get_tree().root.propagate_notification(NOTIFICATION_APPLICATION_FOCUS_IN)
	await get_tree().create_timer(1.0).timeout
	var root := EditorInterface.get_edited_scene_root()
	var player := root.get_node_or_null(^"Player") if root else null
	if supports_unsaved:
		if player == null or float(player.get(&"speed")) != 450.0:
			failures.append("B: la escena abierta no se recargó (%s)" % [player.get(&"speed") if player else "sin Player"])
		failures.append_array(_visible_dialogs("B"))
	else:
		if notices.is_empty():
			failures.append("B (4.6): no avisó que el agente cambió la escena")
		_visible_dialogs("B")  # el de Godot es esperable acá
		EditorInterface.reload_scene_from_path(EXTERNAL_SCENE)
		await get_tree().create_timer(0.5).timeout
	notices.clear()

	# C · la escena tiene cambios sin guardar: no se pisa (aviso para recargar).
	root = EditorInterface.get_edited_scene_root()
	root.get_node(^"Player").set(&"position", Vector2(7, 7))
	EditorInterface.mark_scene_as_unsaved()
	await get_tree().create_timer(1.1).timeout
	_write(EXTERNAL_SCENE, scene_text.replace("speed = 300.0", "speed = 600.0"))
	await get_tree().create_timer(1.5).timeout
	root = EditorInterface.get_edited_scene_root()
	if float(root.get_node(^"Player").get(&"speed")) == 600.0:
		failures.append("C: se recargó encima de los cambios sin guardar")
	if notices.is_empty():
		failures.append("C: no avisó que el agente cambió la escena")
	notices.clear()
	print("[external-test] get_unsaved_scenes: %s" % supports_unsaved)

	# E · un guardado del editor (Ctrl+S) no es un cambio del agente: no recarga (perdería el undo).
	_write(EXTERNAL_SCENE, scene_text)
	EditorInterface.reload_scene_from_path(EXTERNAL_SCENE)
	await get_tree().create_timer(1.1).timeout
	notices.clear()  # en 4.6 la reescritura de arriba avisa: no es lo que se mide acá
	root = EditorInterface.get_edited_scene_root()
	EditorInterface.save_scene()
	await get_tree().create_timer(1.5).timeout
	if EditorInterface.get_edited_scene_root() != root:
		failures.append("E: guardar desde el editor recargó la escena")
	if not notices.is_empty():
		failures.append("E: guardar desde el editor avisó un cambio del agente")

	# Deja todo como estaba (el editor guarda project.godot con lo que tiene en memoria).
	_write(EXTERNAL_SCENE, scene_text)
	EditorInterface.reload_scene_from_path(EXTERNAL_SCENE)
	await get_tree().create_timer(1.1).timeout
	_write("res://project.godot", project_text)
	await get_tree().create_timer(1.5).timeout
	if ProjectSettings.has_setting("input/agent_jump") or ProjectSettings.get_setting("application/config/description", "") != "":
		failures.append("D: al volver project.godot atrás, no se quitó lo del agente")
	if applied.size() != 2 or applied[1] != PackedStringArray(["application/config/description", "input/agent_jump"]):
		failures.append("D: tenía que quitar solo lo del agente (%s)" % [applied])
	sync.disconnect(&"project_settings_applied", on_applied)
	sync.disconnect(&"open_scene_modified", on_modified)
	get_tree().root.propagate_notification(NOTIFICATION_APPLICATION_FOCUS_IN)
	await get_tree().create_timer(1.0).timeout
	_visible_dialogs("fin")
	for failure: String in failures:
		print("[external-test] FALLA ", failure)
	_finish(0 if failures.is_empty() else 1, "external-test: %d fallas" % failures.size())


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
		if int(entry.get(&"kind")) == ChatEntry.EntryKind.NOTICE:
			print("[claude-edit] aviso: ", entry.get(&"text"))
		elif int(entry.get(&"kind")) == ChatEntry.EntryKind.AGENT:
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


func _run_review_test(real_claude: bool) -> void:
	get_tree().create_timer(CLAUDE_TIMEOUT_S if real_claude else SAFETY_TIMEOUT_S).timeout.connect(_on_safety_timeout)
	await get_tree().create_timer(2.0).timeout
	if _find_dock() == null:
		_finish(1, "no se encontró el dock")
		return
	var profile: AgentProfile = AgentProfile.from_dict(AgentProfile.defaults()[0]) if real_claude else null
	var failures: PackedStringArray = await ReviewCheck.new().run_review(get_tree(), profile, _arg_value(UI_SHOT_ARG))
	for failure: String in failures:
		print("[review-check] FALLA ", failure)
	_finish(0 if failures.is_empty() else 1, "review-test%s: %d fallas" % [" (Claude)" if real_claude else "", failures.size()])


func _run_oneshot_test() -> void:
	get_tree().create_timer(SAFETY_TIMEOUT_S).timeout.connect(_on_safety_timeout)
	await get_tree().create_timer(2.0).timeout
	var failures: PackedStringArray = await OneShotUiCheck.new().run_oneshot(get_tree(), _arg_value(UI_SHOT_ARG))
	for failure: String in failures:
		print("[oneshot-check] FALLA ", failure)
	_finish(0 if failures.is_empty() else 1, "oneshot-test: %d fallas" % failures.size())


func _run_claude_oneshot_test() -> void:
	get_tree().create_timer(CLAUDE_ONESHOT_TIMEOUT_S).timeout.connect(_on_safety_timeout)
	await get_tree().create_timer(2.0).timeout
	var failures: PackedStringArray = await OneShotUiCheck.new().run_claude_oneshot(get_tree(), _arg_value(UI_SHOT_ARG))
	for failure: String in failures:
		print("[claude-oneshot] FALLA ", failure)
	_finish(0 if failures.is_empty() else 1, "claude-oneshot-test: %d fallas" % failures.size())


func _run_long_test() -> void:
	get_tree().create_timer(SAFETY_TIMEOUT_S).timeout.connect(_on_safety_timeout)
	await get_tree().create_timer(2.0).timeout
	var check := LongSessionCheck.new()
	var failures: PackedStringArray = await check.run_long(get_tree())
	print("[long-check] ", check.report)
	for failure: String in failures:
		print("[long-check] FALLA ", failure)
	_finish(0 if failures.is_empty() else 1, "long-test: %d fallas" % failures.size())


func _run_completion_test() -> void:
	get_tree().create_timer(SAFETY_TIMEOUT_S).timeout.connect(_on_safety_timeout)
	await get_tree().create_timer(2.0).timeout
	var check := CompletionCheck.new()
	var failures: PackedStringArray = await check.run(get_tree(), _arg_value(UI_SHOT_ARG))
	check.cleanup()
	for line: String in check.report:
		print("[completion-check] ", line)
	for failure: String in failures:
		print("[completion-check] FALLA ", failure)
	_finish(0 if failures.is_empty() else 1, "completion-test: %d fallas" % failures.size())


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
		if int(entry.get(&"kind")) == ChatEntry.EntryKind.TOOL_GROUP:
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
		if int(entry.get(&"kind")) == ChatEntry.EntryKind.AGENT:
			reply += str(entry.get(&"text"))
		elif int(entry.get(&"kind")) == ChatEntry.EntryKind.TOOL_GROUP:
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
			var guard := node.get_parent()  # MinSizeGuard
			var holder := guard.get_parent()
			if holder.has_method(&"make_visible"):
				holder.call(&"make_visible")
			elif holder is TabContainer:
				(holder as TabContainer).current_tab = guard.get_index()
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
	# Imágenes: un archivo de afuera del proyecto (como al pegar archivos copiados) y una pegada,
	# grande, que se achica.
	var outside_png := OS.get_user_data_dir().path_join("ui_test_attach.png")
	Image.create(16, 8, false, Image.FORMAT_RGB8).save_png(outside_png)
	dock.call(&"add_context_files", PackedStringArray([outside_png]))
	var pasted := Image.create(2560, 1000, false, Image.FORMAT_RGBA8)
	pasted.fill(Color.ORANGE)
	dock.call(&"attach_image", pasted, "pegada")
	var images: Array = (dock.call(&"_context_blocks") as Array).filter(func(block: Dictionary) -> bool: return block.type == "image")
	if images.size() != 2:
		_finish(1, "las imágenes adjuntas no quedaron como bloques de imagen: %d" % images.size())
		return
	var decoded := Image.new()
	decoded.load_png_from_buffer(Marshalls.base64_to_raw(str(images[1].data)))
	if decoded.get_width() != 1280 or pasted.get_width() != 2560:
		_finish(1, "la imagen pegada no se achicó a 1280 (o se tocó la original): %d" % decoded.get_width())
		return
	dock.call(&"_on_submitted", "hola, ¿qué hay que hacer con las oleadas?")
	chips = dock.get(&"_chips")
	if chips.has("file:res://project.godot") or chips.keys().any(func(id: String) -> bool: return id.begins_with("image:")):
		_finish(1, "los adjuntos siguieron después de enviar: %s" % [chips.keys()])
		return
	while int(model.get(&"state")) != 2:  # READY
		await get_tree().process_frame
	await get_tree().create_timer(0.5).timeout
	dock.emit_signal(&"show_log_requested")
	await get_tree().create_timer(0.5).timeout
	var entries: Array = model.call(&"entries")
	print("[ui-test] %d entradas, título '%s'" % [entries.size(), model.get(&"title")])
	if scenario == "ui_quota":
		var composer: Control = dock.get(&"_composer")
		var send: Button = composer.get(&"_send_button")
		var meter: Control = dock.get(&"_quota_meter")
		if not (send.disabled and send.text.begins_with("⏳") and meter.visible):
			_finish(1, "cuota: el envío no quedó bloqueado (%s, disabled=%s) o no se ve el medidor" % [send.text, send.disabled])
			return
	if not shot_path.is_empty():
		var image := EditorInterface.get_base_control().get_viewport().get_texture().get_image()
		image.save_png(shot_path)
	controller.call(&"stop")
	_finish(0, "ui-test %s" % scenario)


## M7: dos turnos con el agente falso, cerrar, y reabrir la sesión desde el menú de historial del dock.
func _run_history_test(shot_path: String) -> void:
	get_tree().create_timer(SAFETY_TIMEOUT_S).timeout.connect(_on_safety_timeout)
	await get_tree().create_timer(2.0).timeout
	var dock := _find_dock()
	if dock == null:
		_finish(1, "no se encontró el dock")
		return
	var controller: Object = dock.get(&"_controller")
	var model: Object = dock.get(&"_model")
	if controller.get(&"history") == null:
		_finish(1, "el plugin no le dio historial al controller")
		return
	var profile := AgentProfile.from_dict({
		"id": "fake", "display_name": "Agente falso", "command": OS.get_executable_path(),
		"args": ["--headless", "--no-header", "--path", ProjectSettings.globalize_path("res://"),
			"--script", "res://tests/fake_agent.gd", "--", "--scenario=res://tests/scripts/history.json"],
	})
	if not await controller.call(&"start", profile):
		_finish(1, "no arrancó la sesión: %s" % model.get(&"failure_message"))
		return
	var session_id: String = model.get(&"session_id")
	await controller.call(&"send_prompt", "arreglá la pelota")
	await controller.call(&"send_prompt", "seguí")
	controller.call(&"stop")
	(dock.get(&"_history_button") as Button).pressed.emit()
	await get_tree().create_timer(0.3).timeout
	var menu: PopupMenu = dock.get(&"_history_menu")
	var items: Array = dock.get(&"_history_items")
	if not menu.visible or items.is_empty() or items[0].get("id") != session_id or not menu.get_item_text(0).contains("Arreglar la pelota"):
		_finish(1, "el menú de historial no muestra la sesión (%s, %s)" % [menu.visible, items])
		return
	menu.hide()
	# El perfil "fake" no está en Settings: se reabre con el activo, que acá se cambia por el falso.
	var settings: Object = dock.get(&"_settings")
	var saved_profiles: Array = settings.call(&"profiles")
	var with_fake: Array[AgentProfile] = [profile]
	settings.call(&"save_profiles", with_fake)
	var resumed: bool = await dock.call(&"open_history_session", session_id)
	settings.call(&"save_profiles", saved_profiles)
	await get_tree().create_timer(0.5).timeout
	if not resumed or model.get(&"session_id") != session_id or int(model.get(&"state")) != 2:
		_finish(1, "no se reanudó la sesión (%s, %s)" % [resumed, model.get(&"failure_message")])
		return
	if not shot_path.is_empty():
		EditorInterface.get_base_control().get_viewport().get_texture().get_image().save_png(shot_path)
	controller.call(&"stop")
	_finish(0, "historial: la sesión se reabrió desde el dock")


func _run_login_test(shot_path: String) -> void:
	get_tree().create_timer(SAFETY_TIMEOUT_S).timeout.connect(_on_safety_timeout)
	await get_tree().create_timer(2.0).timeout
	var dock := _find_dock()
	if dock == null:
		_finish(1, "no se encontró el dock")
		return
	var controller: Object = dock.get(&"_controller")
	var model: Object = dock.get(&"_model")
	var marker := ProjectSettings.globalize_path("user://fake_login_ok")
	DirAccess.remove_absolute(marker)
	var profile := AgentProfile.from_dict({
		"id": "fake", "display_name": "Agente falso", "command": OS.get_executable_path(),
		"args": ["--headless", "--no-header", "--path", ProjectSettings.globalize_path("res://"),
			"--script", "res://tests/fake_agent.gd", "--", "--scenario=res://tests/scripts/auth.json"],
	})
	if await controller.call(&"start", profile):
		_finish(1, "la sesión abrió sin login")
		return
	var login_button := await _wait_button(dock, "Sign in · Cuenta falsa")
	if login_button == null:
		_finish(1, "el aviso no ofrece iniciar sesión")
		return
	login_button.pressed.emit()
	var code_button := await _wait_button(dock, "Paste code…")
	if code_button == null or _find_button(dock, "Open link") == null:
		_finish(1, "no apareció el enlace del login")
		return
	await get_tree().create_timer(0.3).timeout
	if not shot_path.is_empty():
		EditorInterface.get_base_control().get_viewport().get_texture().get_image().save_png(shot_path)
	code_button.pressed.emit()
	await get_tree().process_frame
	var dialog: ConfirmationDialog = dock.get(&"_login_code_dialog")
	if dialog == null or not dialog.visible:
		_finish(1, "no se abrió el diálogo del código")
		return
	(dock.get(&"_login_code_input") as LineEdit).text = "CODE123"
	dialog.get_ok_button().pressed.emit()
	var deadline := Time.get_ticks_msec() + 20000
	while int(model.get(&"state")) != 2 and Time.get_ticks_msec() < deadline:  # READY
		await get_tree().process_frame
	DirAccess.remove_absolute(marker)
	if int(model.get(&"state")) != 2:
		_finish(1, "la sesión no abrió después del login (%s)" % model.get(&"failure_message"))
		return
	controller.call(&"stop")
	_finish(0, "login: desde el dock, con el código pegado, la sesión abrió")


func _run_queue_test(shot_path: String) -> void:
	get_tree().create_timer(SAFETY_TIMEOUT_S).timeout.connect(_on_safety_timeout)
	await get_tree().create_timer(2.0).timeout
	var dock := _find_dock()
	if dock == null:
		_finish(1, "no se encontró el dock")
		return
	var controller: Object = dock.get(&"_controller")
	var model: Object = dock.get(&"_model")
	var composer: Object = dock.get(&"_composer")
	var queue: Object = dock.get(&"_queue")
	var profile := AgentProfile.from_dict({
		"id": "fake", "display_name": "Agente falso", "command": OS.get_executable_path(),
		"args": ["--headless", "--no-header", "--path", ProjectSettings.globalize_path("res://"),
			"--script", "res://tests/fake_agent.gd", "--", "--scenario=res://tests/scripts/cancel.json"],
	})
	if not await controller.call(&"start", profile):
		_finish(1, "no arrancó la sesión (%s)" % model.get(&"failure_message"))
		return
	var failures: PackedStringArray = []
	var user_messages := func() -> Array:
		return (model.call(&"entries") as Array).filter(func(entry: Object) -> bool: return int(entry.get(&"kind")) == 0).map(func(entry: Object) -> String: return str(entry.get(&"text")))
	var input: CodeEdit = composer.get(&"_input")
	# Turno largo; mientras corre, dos prompts escritos en el composer con Enter.
	for text: String in ["arrancá", "primero en cola", "segundo en cola"]:
		input.text = text
		composer.call(&"_submit")
		await get_tree().process_frame
	if not bool(model.call(&"is_busy")):
		failures.append("el primer turno no quedó corriendo")
	if int(queue.call(&"size")) != 2 or user_messages.call() != ["arrancá"]:
		failures.append("no se encolaron: cola %d, mensajes %s" % [queue.call(&"size"), user_messages.call()])
	if not input.text.is_empty():
		failures.append("el composer no se vació al encolar")
	var queue_view: Control = dock.get(&"_queue_view")
	if not queue_view.is_visible_in_tree():
		failures.append("la cola no se ve")
	if not shot_path.is_empty():
		await get_tree().create_timer(0.3).timeout
		EditorInterface.get_base_control().get_viewport().get_texture().get_image().save_png(shot_path)
	# Cancelar pausa la cola: no sale nada solo.
	dock.call(&"_on_cancel_requested")
	var deadline := Time.get_ticks_msec() + 10000
	while bool(model.call(&"is_busy")) and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	await get_tree().create_timer(1.0).timeout
	if not bool(queue.get(&"paused")) or user_messages.call().size() != 1:
		failures.append("el cancel no pausó la cola: pausada %s, mensajes %s" % [queue.get(&"paused"), user_messages.call()])
	var send_now := await _wait_button(dock, "Send now")
	if send_now == null or send_now.disabled:
		failures.append("no se ofrece «Enviar ahora»")
	else:
		send_now.pressed.emit()
	deadline = Time.get_ticks_msec() + 15000
	while (not bool(queue.call(&"is_empty")) or bool(model.call(&"is_busy"))) and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	if user_messages.call() != ["arrancá", "primero en cola", "segundo en cola"]:
		failures.append("no salieron en orden: %s" % [user_messages.call()])
	if queue_view.visible:
		failures.append("la cola vacía sigue visible")
	controller.call(&"stop")
	for failure: String in failures:
		print("[queue-test] FALLA ", failure)
	_finish(0 if failures.is_empty() else 1, "queue-test: %d fallas" % failures.size())


func _wait_button(root: Node, text: String) -> Button:
	var deadline := Time.get_ticks_msec() + 20000
	while Time.get_ticks_msec() < deadline:
		var button := _find_button(root, text)
		if button:
			return button
		await get_tree().process_frame
	return null


func _find_button(root: Node, text: String) -> Button:
	for node: Node in root.find_children("*", "Button", true, false):
		if (node as Button).text == text and node.is_visible_in_tree():
			return node
	return null


## M7: abre Settings desde el botón del dock y guarda una captura por sección en `<prefijo>_<n>.png`.
func _run_i18n_test() -> void:
	get_tree().create_timer(SAFETY_TIMEOUT_S).timeout.connect(_on_safety_timeout)
	await get_tree().create_timer(2.0).timeout
	var catalog := load(I18N_CATALOG) as Translation
	var dock := _find_dock()
	var main_screen := _find_by_script(MAIN_SCREEN_SCRIPT)
	var log_panel := _find_by_script(LOG_PANEL_SCRIPT)
	if catalog == null or dock == null or main_screen == null or log_panel == null:
		_finish(1, "falta el catálogo, el dock, la pantalla Agent o el Agent Log")
		return
	var failures: PackedStringArray = []
	var seen := {}
	_untranslated(dock, catalog, "dock", failures, seen)
	EditorInterface.set_main_screen_editor(MAIN_SCREEN_NAME)
	await get_tree().create_timer(0.5).timeout
	_untranslated(main_screen, catalog, "pantalla Agent", failures, seen)
	_untranslated(log_panel, catalog, "Agent Log", failures, seen)
	(dock.get(&"_settings_button") as Button).pressed.emit()
	await get_tree().create_timer(0.5).timeout
	var dialog: Window = null
	for node: Node in EditorInterface.get_base_control().get_children():
		if node is ConfirmationDialog and node.has_method(&"matrix_overrides"):
			dialog = node
	if dialog == null:
		failures.append("el botón de Settings no abrió el diálogo")
	else:
		var nav: ItemList = dialog.get(&"_nav")
		for i in nav.item_count:
			nav.select(i)
			nav.item_selected.emit(i)
			await get_tree().create_timer(0.3).timeout
			_untranslated(dialog, catalog, "Settings", failures, seen)
		dialog.hide()
	EditorInterface.set_main_screen_editor("2D")
	# Los textos a la vista que sí están en español: si son pocos, el idioma no se aplicó.
	var spanish := seen.keys().filter(func(text: String) -> bool: return text in ["Iniciar sesión", "Construir", "Presupuestos", "Permisos"])
	if spanish.size() < 4:
		failures.append("faltan textos en español esperados (vistos: %s)" % [spanish])
	if failures.is_empty():
		_finish(0, "i18n-test: %d textos revisados en español" % seen.size())
	else:
		_finish(1, "i18n-test: %s" % "; ".join(failures))


## Textos visibles bajo `root` que el catálogo traduce pero se muestran sin traducir.
func _untranslated(root: Node, catalog: Translation, label: String, failures: PackedStringArray, seen: Dictionary) -> void:
	for node: Node in [root] + root.find_children("*", "", true, false):
		var texts: PackedStringArray = []
		for property: StringName in [&"text", &"tooltip_text", &"placeholder_text", &"title"]:
			if property in node and typeof(node.get(property)) == TYPE_STRING:
				texts.append(str(node.get(property)))
		if node is ItemList:
			for i in (node as ItemList).item_count:
				texts.append((node as ItemList).get_item_text(i))
		if node is OptionButton:
			for i in (node as OptionButton).item_count:
				texts.append((node as OptionButton).get_item_text(i))
		if node is TabBar:
			for i in (node as TabBar).tab_count:
				texts.append((node as TabBar).get_tab_title(i))
		for text: String in texts:
			if text.strip_edges().is_empty():
				continue
			seen[text] = true
			if text in I18N_IDS:
				continue
			var translated := String(catalog.get_message(text))
			if not translated.is_empty() and translated != text:
				var problem := "%s: «%s» sin traducir (%s)" % [label, text.left(60), node.name]
				if problem not in failures:
					failures.append(problem)


func _run_settings_shots(prefix: String) -> void:
	get_tree().create_timer(SAFETY_TIMEOUT_S).timeout.connect(_on_safety_timeout)
	await get_tree().create_timer(2.0).timeout
	var dock := _find_dock()
	if dock == null:
		_finish(1, "no se encontró el dock")
		return
	(dock.get(&"_settings_button") as Button).pressed.emit()
	await get_tree().create_timer(0.5).timeout
	var dialog: Window = null
	for node: Node in EditorInterface.get_base_control().get_children():
		if node is ConfirmationDialog and node.has_method(&"matrix_overrides"):
			dialog = node
	if dialog == null or not dialog.visible:
		_finish(1, "el botón de Settings no abrió el diálogo")
		return
	if not (dialog.call(&"validate") as Dictionary).is_empty():
		_finish(1, "los settings actuales no validan: %s" % dialog.call(&"validate"))
		return
	var nav: ItemList = dialog.get(&"_nav")
	for i in nav.item_count:
		nav.select(i)
		nav.item_selected.emit(i)
		await get_tree().create_timer(0.4).timeout
		dialog.get_texture().get_image().save_png("%s_%d.png" % [prefix, i])
	# Guardar aplica la matriz en caliente y escribe project_config.tres (se borra al final).
	var config_path := "res://addons/godot_agent/config/project_config.tres"
	var had_config := FileAccess.file_exists(config_path)
	var option: OptionButton = (dialog.get(&"_matrix") as Dictionary)["read"][0]  # Lectura · Preguntar
	option.select(2)  # no
	dialog.call(&"_on_save")
	var policy: Object = (dock.get(&"_controller") as Object).get(&"policy")
	var saved_ok: bool = not dialog.visible and policy.call(&"matrix_value", "read", 0) == "deny" and FileAccess.file_exists(config_path)
	if not had_config:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(config_path))
	policy.set(&"overrides", {})
	if not saved_ok:
		_finish(1, "settings: guardar no aplicó la matriz (visible=%s, read/ask=%s)" % [dialog.visible, policy.call(&"matrix_value", "read", 0)])
		return
	_finish(0, "settings: %d secciones, guardar aplica la matriz" % nav.item_count)


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
	var layout_problems: PackedStringArray = await _layout_problems()
	if not layout_problems.is_empty():
		_finish(1, "layout: %s" % "; ".join(layout_problems))
	elif not addon_orphans.is_empty():
		_finish(1, "nodos huérfanos del addon: %s" % ", ".join(addon_orphans))
	elif orphans_after > orphans_before:
		_print_new_orphans(orphan_ids_before)
		_finish(1, "quedaron %d nodos huérfanos nuevos" % (orphans_after - orphans_before))
	elif growth > OBJECT_GROWTH_TOLERANCE:
		_finish(1, "los objetos crecieron %d entre el ciclo 1 y el %d" % [growth, CYCLES])
	else:
		_finish(0, "%d ciclos sin huérfanos (crecimiento de objetos: %d)" % [CYCLES, growth])


## Labels con autowrap que quedaron del ancho de una letra (piden miles de píxeles de alto) y un
## editor estirado por el mínimo de una superficie oculta (D29): el dock oculto con el banner de
## export, el dock visible y cada sección de Settings.
func _layout_problems() -> PackedStringArray:
	var problems: PackedStringArray = []
	var dock := _find_dock()
	if dock == null:
		return PackedStringArray(["no se encontró el dock"])
	var guard := dock.get_parent() as Control
	var tabs := guard.get_parent()
	var holder := tabs.get_parent() if tabs and tabs.get_class() == "EditorDock" else tabs
	var banner: Control = dock.get(&"_export_banner")
	var banner_label: Label = dock.get(&"_export_banner_label")
	var banner_state := [banner.visible, banner_label.text]
	banner_label.text = "The export presets Android, Android (bench) do not exclude 'addons/godot_agent/*'. If you export with the plugin disabled, the addon ends up in the game."
	banner.visible = true
	# Oculto: otra pestaña del slot al frente.
	var slot := holder as TabContainer if holder is TabContainer else null
	if slot == null and holder:
		slot = holder.get_parent() as TabContainer
	var window_height := float(EditorInterface.get_base_control().get_window().size.y)
	if slot and slot.get_tab_count() > 1:
		var previous := slot.current_tab
		slot.current_tab = 0 if slot.get_tab_control(0) != holder and slot.get_tab_control(0) != guard else 1
		await _settle()
		if slot.get_combined_minimum_size().y > window_height:
			problems.append("con el dock oculto, su slot pide %d px de alto (ventana: %d)" % [slot.get_combined_minimum_size().y, window_height])
		slot.current_tab = previous
	await _settle()
	problems.append_array(_narrow_labels(guard))
	banner.visible = banner_state[0]
	banner_label.text = banner_state[1]
	(dock.get(&"_settings_button") as Button).pressed.emit()
	await _settle()
	for node: Node in EditorInterface.get_base_control().get_children():
		if node is ConfirmationDialog and node.has_method(&"matrix_overrides"):
			var nav: ItemList = node.get(&"_nav")
			for i in nav.item_count:
				nav.select(i)
				nav.item_selected.emit(i)
				await _settle()
				problems.append_array(_narrow_labels(node))
			(node as Window).hide()
	return problems


func _narrow_labels(root: Node) -> PackedStringArray:
	var result: PackedStringArray = []
	for node: Node in root.find_children("*", "Label", true, false):
		var label := node as Label
		if label.is_visible_in_tree() and label.autowrap_mode != TextServer.AUTOWRAP_OFF and label.text.length() > 8 and label.size.x < 40.0:
			result.append("label de %d px de ancho: «%s»" % [label.size.x, label.text.left(40)])
	return result


func _settle() -> void:
	for i: int in SETTLE_FRAMES:
		await get_tree().process_frame


func _objects() -> int:
	return int(Performance.get_monitor(Performance.OBJECT_COUNT))


func _orphans() -> int:
	return int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))


func _orphan_ids() -> Array:
	return Array(Node.get_orphan_node_ids())


## Huérfanos con un script del addon.
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
