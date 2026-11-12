@tool
extends EditorPlugin
## Herramientas de test que necesitan el editor. No hace nada salvo que se lance con:
## - `-- --godot-agent-cycle-test [--godot-agent-cycle-target=<plugin o ruta al plugin.cfg>]`: alterna
##   el plugin godot_agent (u otro) 9 veces, intercalado con un plugin vacío de control, y sale.
##   Código de salida: 0 bien, 1 si quedan nodos huérfanos o si pierde objetos ciclo a ciclo más que el
##   control (tests/fixtures/cycle_plugins/leaky lo tiene que hacer fallar).
## - `-- --godot-agent-screenshot=<ruta.png>`: abre la main screen "One-shot", guarda una captura
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
## - `-- --godot-agent-run-error-test [--godot-agent-ui-shot=<ruta.png>]`: un run manual de un script roto deja en el dock el aviso con
##   «Arreglar con el agente» una vez por run, el botón manda el prompt etiquetado, y ni un run del
##   agente ni el ajuste apagado avisan (ver run_error_check.gd, m11-55). Necesita ventana.
## - `-- --godot-agent-first-run-test=<prefijo>`: el primer uso en vivo sin tokens (ver
##   tests/first_run_check.sh): «Add» arranca la sesión sola y, sin credenciales, llega al login.
## - `-- --godot-agent-claude-scene-test`: verificación de M4 con Claude Code real (gasta tokens).
##   Pide agregar WaveLabel al HUD y conectar WaveTimer.timeout; Ctrl+Z tiene que deshacerlo en pasos.
## - `-- --godot-agent-crash-test=before|during`: mata el editor con el autoload de playtest recién
##   registrado (before) o con un run_scene en curso (during). Al reabrir, no tiene que quedar.
## - `-- --godot-agent-review-test [--godot-agent-ui-shot=<ruta.png>]`: modo Revisar con el agente
##   falso sobre tests/fixtures/review/ (ver review_check.gd). Necesita ventana.
## - `-- --godot-agent-oneshot-test [--godot-agent-ui-shot=<ruta.png>]`: la pantalla One-shot maneja un
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
## - `-- --godot-agent-auto-test [--godot-agent-ui-shot=<prefijo>]`: modo Auto (D57) por la UI: botón del
##   dock, tarjetas con «Permitir siempre», la regla guardada y la sección de Settings → Permisos.
## - `-- --godot-agent-remote-test [--godot-agent-ui-shot=<ruta.png>]`: Remote Control (m7-21) con el
##   agente falso: botón del encabezado, franja con el link, tarjeta contestada desde el celular,
##   «Apagar» y el botón escondido en One-shot.
## - `-- --godot-agent-plan-test [--godot-agent-ui-shot=<prefijo>]`: m11-22 con el agente falso: la
##   tarjeta del plan de ExitPlanMode, Editar con el diff de vuelta, Aprobar y construir sin set_mode,
##   «Denegar con motivo» y Detener después de un rechazo (plan_check.gd).
## - `-- --godot-agent-checks-test`: m11-31 con el agente falso en Auto: el check del proyecto que
##   falla vuelve al agente, uno sin aprobar ofrece «Aprobar…» y el turno de arreglo pasa
##   (turn_checks_check.gd).
## - `-- --godot-agent-ask-menu-test`: m11-54: «Ask the agent» de los menús contextuales de FileSystem,
##   dock Escena y Script Editor, abiertos como los abre el editor (ask_menu_check.gd).
## - `-- --godot-agent-hooks-test`: m11-24: hooks del proyecto con guardados de verdad, aprobación por
##   máquina desde el aviso y la diferencia entre lo que guarda el usuario y el agente (hooks_check.gd).
## - `-- --godot-agent-second-opinion-test`: m11-28 con dos agentes falsos: el botón del aviso del turno,
##   el oráculo de solo lectura (borrar y session_send rechazados), «Send to the agent» en sobre, la tool
##   con permiso y Cancel (second_opinion_check.gd).
## - `-- --godot-agent-instances-test`: m11-50: run_scene con dos instancias de un juego ENet, `instance`
##   en las tools, game_instance list/stop/add y que no quede ningún proceso (instances_check.gd).
## - `-- --godot-agent-bake-test [--godot-agent-bake-lightmaps]`: m11-53: godot.bake (navegación 2D/3D con
##   deshacer, occluders con el botón del editor, lightmaps con la opción) y export_project (sin plantillas,
##   pack, export_presets.cfg intacto) (bake_check.gd).
## - `-- --godot-agent-claude-plan-test [--godot-agent-ui-shot=<prefijo>]`: lo mismo con Claude Code real
##   (gasta tokens): plan → Editar → Aprobar → primera edición en Construir → Denegar con motivo.
## - `-- --godot-agent-pending-test`: con algo preparado por install_extension (m19-05), habilitar el
##   plugin muestra el aviso con Reiniciar y Descartar, y Descartar lo borra (pending_check.gd).
## - `-- --godot-agent-i18n-test`: con GODOT_AGENT_LANGUAGE=es, recorre el dock, la pantalla One-shot,
##   el Agent Log y cada página de Settings: ningún texto visible que tenga traducción queda en inglés.
## - `-- --godot-agent-profile-test`: m13-27, lee el profiler de scripts de un run desde un plugin por
##   la señal interna debug_data de ScriptEditorDebugger y mide el overhead (ver profile_check.gd);
##   después, godot.profile_run por HTTP real (profile_tool_check.gd).
## - `-- --godot-agent-debug-test`: m11-56, game_breakpoint, game_stack y game_debug sobre un juego
##   parado en un breakpoint del agente; al cerrarse la sesión, el juego sigue (debug_check.gd).

const CYCLE_ARG := "--godot-agent-cycle-test"
const SCREENSHOT_ARG := "--godot-agent-screenshot="
const UI_TEST_ARG := "--godot-agent-ui-test="
const UI_SHOT_ARG := "--godot-agent-ui-shot="
const AgentProfile := preload("res://addons/godot_agent/core/agent_profile.gd")
const ChatEntry := preload("res://addons/godot_agent/session/chat_entry.gd")
const SessionModel := preload("res://addons/godot_agent/session/session_model.gd")
const SessionController := preload("res://addons/godot_agent/session/session_controller.gd")
const I18n := preload("res://addons/godot_agent/core/i18n.gd")
const HarnessPrompts := preload("res://addons/godot_agent/session/harness_prompts.gd")
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
const PendingCheck := preload("pending_check.gd")
const PlanCheck := preload("plan_check.gd")
const AgyTourCheck := preload("agy_tour_check.gd")
const HandoffCheck := preload("handoff_check.gd")
const MemoryCheck := preload("memory_check.gd")
const RecipeCheck := preload("recipe_check.gd")
const PathRulesCheck := preload("path_rules_check.gd")
const PlanCriteriaCheck := preload("plan_criteria_check.gd")
const GitCheckpoints := preload("res://addons/godot_agent/oneshot/git_checkpoints.gd")
const TurnChecksCheck := preload("turn_checks_check.gd")
const AskMenuCheck := preload("ask_menu_check.gd")
const HooksCheck := preload("hooks_check.gd")
const SecondOpinionCheck := preload("second_opinion_check.gd")
const InstancesCheck := preload("instances_check.gd")
const BakeCheck := preload("bake_check.gd")
const PlaytestLoopCheck := preload("playtest_loop_check.gd")
const QuitCheck := preload("quit_check.gd")
const ExternalMcpServers := preload("res://addons/godot_agent/mcp/external_mcp_servers.gd")
const EDIT_ARG := "--godot-agent-edit-test"
const EditCheck := preload("edit_check.gd")
const RUN_ARG := "--godot-agent-run-test"
const RunCheck := preload("run_check.gd")
const CLAUDE_SCENE_ARG := "--godot-agent-claude-scene-test"
const CLAUDE_HUD_FIXTURE := "res://tests/fixtures/hud_fixture.tscn"
const CLAUDE_HUD_SCENE := "res://tests/tmp/claude_hud.tscn"
const CRASH_ARG := "--godot-agent-crash-test="
const REVIEW_ARG := "--godot-agent-review-test"
const RUN_ERROR_ARG := "--godot-agent-run-error-test"
const RunErrorCheck := preload("run_error_check.gd")
const CLAUDE_REVIEW_ARG := "--godot-agent-claude-review-test"
const ONESHOT_ARG := "--godot-agent-oneshot-test"
const CLAUDE_ONESHOT_ARG := "--godot-agent-claude-oneshot-test"
## m16-03: tests/playtest_suite.json con Claude Code real (gasta tokens). Con =A,B, solo esos pedidos.
const CLAUDE_PLAYTEST_ARG := "--godot-agent-claude-playtest-suite"
const PlaytestSuiteCheck := preload("playtest_suite_check.gd")
const LONG_ARG := "--godot-agent-long-test"
const SETTINGS_ARG := "--godot-agent-settings-shots="
## m7-37: abre Extensions desde el dock con el CLI real (solo lectura) y saca una captura por pestaña.
const EXTENSIONS_ARG := "--godot-agent-extensions-shots="
## m7-38: muestra el aviso de versión nueva con un release de mentira (sin red), sus notas y
## «Buscar ahora» de Settings, que en el repo dice que es una copia de desarrollo.
const UPDATE_ARG := "--godot-agent-update-shots="
## m7-41: las capturas de la guía (README y wiki) en la carpeta dada. Ver tests/docs_shots.sh.
const DOCS_ARG := "--godot-agent-docs-shots="
## Recorrido de capturas de toda la UI (tests/ux_tour.sh).
const UX_TOUR_ARG := "--godot-agent-ux-tour="
const HISTORY_ARG := "--godot-agent-history-test="
const LOGIN_ARG := "--godot-agent-login-test"
const QUEUE_ARG := "--godot-agent-queue-test"
const COMPLETION_ARG := "--godot-agent-completion-test"
const I18N_ARG := "--godot-agent-i18n-test"
const LayoutCheck := preload("layout_check.gd")
const I18N_CATALOG := "res://addons/godot_agent/i18n/es.po"
const MAIN_SCREEN_SCRIPT := "res://addons/godot_agent/ui/main_screen/agent_main_screen.gd"
const LOG_PANEL_SCRIPT := "res://addons/godot_agent/ui/log_panel/agent_log_panel.gd"
const AgentLog := preload("res://addons/godot_agent/core/agent_log.gd")
## Ids que se muestran tal cual aunque coincidan con un msgid (canales del Agent Log).
const I18N_IDS: Array[String] = ["quota"]
const CompletionCheck := preload("completion_check.gd")
const LongSessionCheck := preload("long_session_check.gd")
const CLAUDE_ONESHOT_TIMEOUT_S := 3600.0
const OneShotUiCheck := preload("oneshot_ui_check.gd")
const ReviewCheck := preload("review_check.gd")
const DocsShots := preload("docs_shots.gd")
const UxTour := preload("ux_tour.gd")
## m7-39: instala un plugin del Asset Store desde Extensions y prueba las tools (red; correr con
## tests/asset_check.sh, que usa una copia del proyecto).
const ASSET_ARG := "--godot-agent-asset-test="
## m12-49: el primer uso en vivo (tests/first_run_check.sh): «Agregar» arranca la sesión y llega al login.
const FIRST_RUN_ARG := "--godot-agent-first-run-test="
const FIRST_RUN_TIMEOUT_S := 400.0
const AssetCheck := preload("asset_check.gd")
## m7-36: la pestaña Skills de Extensions (correr con tests/skills_check.sh: copia del proyecto y
## un CLAUDE_CONFIG_DIR de prueba).
const SKILLS_ARG := "--godot-agent-skills-test="
const SkillsCheck := preload("skills_check.gd")
## m7-44: varias sesiones en pestañas del dock, coordinadas por archivo y por el juego.
const SESSIONS_ARG := "--godot-agent-sessions-test="
const SessionsCheck := preload("sessions_check.gd")
const AUTO_ARG := "--godot-agent-auto-test"
const AutoCheck := preload("auto_check.gd")
const REMOTE_ARG := "--godot-agent-remote-test"
const PENDING_ARG := "--godot-agent-pending-test"
const PLAN_ARG := "--godot-agent-plan-test"
const CHECKS_ARG := "--godot-agent-checks-test"
const ASK_MENU_ARG := "--godot-agent-ask-menu-test"
## m11-49: un playtest con el agente falso en loop se corta como «could not test».
const PLAYTEST_LOOP_ARG := "--godot-agent-playtest-loop-test"
## Cerrar el editor no deja procesos del agente (tests/quit_check.sh).
const QUIT_ARG := "--godot-agent-quit-test"
const HOOKS_ARG := "--godot-agent-hooks-test"
const SECOND_OPINION_ARG := "--godot-agent-second-opinion-test"
const INSTANCES_ARG := "--godot-agent-instances-test"
const BAKE_ARG := "--godot-agent-bake-test"
## Con BAKE_ARG: hornea también los lightmaps (lento con llvmpipe: va en la suite full).
const BAKE_LIGHTMAPS_ARG := "--godot-agent-bake-lightmaps"
## Gasta tokens: Claude Code real con la tarjeta del plan (plan_check.gd run_claude).
const CLAUDE_PLAN_ARG := "--godot-agent-claude-plan-test"
## m11-58 con Antigravity real (sin modo plan; gasta tokens).
const AGY_PLAN_ARG := "--godot-agent-antigravity-plan-test"
## m18-02: recorrido de una sesión con Antigravity (gasta tokens). AGY_TOUR_WRAP/AGY_TOUR_LOG para registrar ACP y MCP.
const AGY_TOUR_ARG := "--godot-agent-antigravity-tour"
const RemoteCheck := preload("remote_check.gd")
const PROFILE_ARG := "--godot-agent-profile-test"
const ProfileCheck := preload("profile_check.gd")
const ProfileToolCheck := preload("profile_tool_check.gd")
const DEBUG_ARG := "--godot-agent-debug-test"
const DebugCheck := preload("debug_check.gd")
const MAIN_PLUGIN_SCRIPT := "res://addons/godot_agent/agent_plugin.gd"
## user:// propio de cada checkout para los checks (m13-17); vive en tests/, que no viaja con el addon.
const TEST_USER_DIR_SCRIPT := "res://tests/test_user_dir.gd"
const RUN_FIXTURE := "res://tests/fixtures/run_fixture.tscn"
const EditorUndo := preload("res://addons/godot_agent/editor/editor_undo.gd")
const PlaytestAutoload := preload("res://addons/godot_agent/playtest/playtest_autoload.gd")
const MAIN_SCREEN_NAME := "One-shot"
const TARGET_PLUGIN := "godot_agent"
## Check de ciclos (m16-12): el plugin que se cicla (por defecto godot_agent; el self-test pasa el que
## pierde objetos) y el control, un plugin vacío que se cicla intercalado en la misma corrida.
const CYCLE_TARGET_ARG := "--godot-agent-cycle-target="
const CYCLE_CONTROL := "res://tests/fixtures/cycle_plugins/empty/plugin.cfg"
const CYCLE_ROUNDS := 9
## Asentado: primero una espera fija (lo que crea el addon al habilitarse vive hasta ~1,3 s y en ese
## rato el conteo puede quedarse quieto) y después el conteo sin cambios en tantos frames seguidos,
## con un tope en ms.
const CYCLE_MIN_WAIT_MS := 2500
const CYCLE_STABLE_FRAMES := 30
const CYCLE_SETTLE_MAX_MS := 8000
## Falla si la mediana del crecimiento por ciclo del plugin supera la del control en esto o más.
const CYCLE_LEAK_PER_CYCLE := 1
## Tarda ~70 s en 4.7.2 (cada ciclo espera a que se asienten los objetos).
const CYCLE_SAFETY_TIMEOUT_S := 400.0
const SETTLE_FRAMES := 5
const SAFETY_TIMEOUT_S := 120.0


func _enter_tree() -> void:
	var args := OS.get_cmdline_user_args()
	# Un check en el editor usa el user:// propio del checkout, como los tests headless (m13-17);
	# el editor abierto a mano no cambia.
	for arg: String in args:
		if arg.begins_with("--godot-agent-") and FileAccess.file_exists(TEST_USER_DIR_SCRIPT):
			load(TEST_USER_DIR_SCRIPT).call(&"apply")
			break
	# tests/tmp no está en git: en un clon o worktree nuevo no existe y los checks no podían escribir.
	if not args.is_empty():
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://tests/tmp"))
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
	if RUN_ERROR_ARG in args:
		_run_run_error_test.call_deferred()
	if AUTO_ARG in args:
		_run_auto_test.call_deferred()
	if REMOTE_ARG in args:
		_run_remote_test.call_deferred()
	if PROFILE_ARG in args:
		_run_profile_test.call_deferred()
	if DEBUG_ARG in args:
		_run_debug_test.call_deferred()
	if PENDING_ARG in args:
		_run_pending_test.call_deferred()
	if PLAN_ARG in args:
		_run_plan_test.call_deferred()
	if CHECKS_ARG in args:
		_run_checks_test.call_deferred()
	if ASK_MENU_ARG in args:
		_run_ask_menu_test.call_deferred()
	if HOOKS_ARG in args:
		_run_hooks_test.call_deferred()
	if SECOND_OPINION_ARG in args:
		_run_second_opinion_test.call_deferred()
	if INSTANCES_ARG in args:
		_run_instances_test.call_deferred()
	if BAKE_ARG in args:
		_run_bake_test.call_deferred(BAKE_LIGHTMAPS_ARG in args)
	if PLAYTEST_LOOP_ARG in args:
		_run_playtest_loop_test.call_deferred()
	if QUIT_ARG in args:
		_run_quit_test.call_deferred()
	if CLAUDE_PLAN_ARG in args:
		_run_plan_test.call_deferred(true)
	if AGY_PLAN_ARG in args:
		_run_plan_test.call_deferred(true, true)
	if AGY_TOUR_ARG in args:
		_run_agy_tour.call_deferred()
	if CLAUDE_REVIEW_ARG in args:
		_run_review_test.call_deferred(true)
	for arg: String in args:
		if arg == CLAUDE_PLAYTEST_ARG or arg.begins_with(CLAUDE_PLAYTEST_ARG + "="):
			_run_playtest_suite.call_deferred(arg.trim_prefix(CLAUDE_PLAYTEST_ARG).trim_prefix("="))
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
		if arg.begins_with(EXTENSIONS_ARG):
			_run_extensions_shots.call_deferred(arg.trim_prefix(EXTENSIONS_ARG))
		if arg.begins_with(UPDATE_ARG):
			_run_update_shots.call_deferred(arg.trim_prefix(UPDATE_ARG))
		if arg.begins_with(DOCS_ARG):
			_run_docs_shots.call_deferred(arg.trim_prefix(DOCS_ARG))
		if arg.begins_with(UX_TOUR_ARG):
			_run_ux_tour.call_deferred(arg.trim_prefix(UX_TOUR_ARG))
		if arg.begins_with(ASSET_ARG):
			_run_asset_test.call_deferred(arg.trim_prefix(ASSET_ARG))
		if arg.begins_with(FIRST_RUN_ARG):
			_run_first_run_test.call_deferred(arg.trim_prefix(FIRST_RUN_ARG))
		if arg.begins_with(SKILLS_ARG):
			_run_skills_test.call_deferred(arg.trim_prefix(SKILLS_ARG))
		if arg.begins_with(SESSIONS_ARG):
			_run_sessions_test.call_deferred(arg.trim_prefix(SESSIONS_ARG))
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
	# El disco tiene que coincidir con la memoria antes de editarlo: al cargar, el editor saca de
	# `editor_plugins/enabled` los plugins que el checkout no tiene (en un worktree falta el symlink
	# local de scope_compass) y 4.7 no lo guarda hasta más tarde; si no, EditorSync ve ese cambio
	# como si fuera del agente. project.godot vuelve a quedar como estaba al salir: lo hace
	# tests/run_in_xvfb.sh (m13-19).
	ProjectSettings.save()
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

	# B · el agente edita la escena abierta, sin cambios del usuario: se recarga sola.
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
	if player == null or float(player.get(&"speed")) != 450.0:
		failures.append("B: la escena abierta no se recargó (%s)" % [player.get(&"speed") if player else "sin Player"])
	failures.append_array(_visible_dialogs("B"))
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

	# E · un guardado del editor (Ctrl+S) no es un cambio del agente: no recarga (perdería el undo).
	_write(EXTERNAL_SCENE, scene_text)
	EditorInterface.reload_scene_from_path(EXTERNAL_SCENE)
	await get_tree().create_timer(1.1).timeout
	notices.clear()
	root = EditorInterface.get_edited_scene_root()
	# Sin vista previa: en 4.7.2 el guardado con vista previa (el de Ctrl+S y save_scene()) deja
	# «p_I->data != this» en list.h (sin el addon también), y en este test a veces SIGSEGV
	# (m17-01). Lo que se prueba acá es scene_saved, que este camino también emite.
	EditorInterface.save_scene_as(EXTERNAL_SCENE, false)
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
	_finish_checking_state(0 if failures.is_empty() else 1, "external-test: %d fallas" % failures.size(), "external-test")


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
	var profile := AgentProfile.from_dict(AgentProfile.CLAUDE_CODE)
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
	var failures := _failures(await McpCheck.new().run(get_tree()))
	for failure: String in failures:
		print("[mcp-check] FALLA ", failure)
	_finish(0 if failures.is_empty() else 1, "mcp-test: %d fallas" % failures.size())


func _run_edit_test() -> void:
	get_tree().create_timer(SAFETY_TIMEOUT_S).timeout.connect(_on_safety_timeout)
	await get_tree().create_timer(2.0).timeout
	var failures := _failures(await EditCheck.new().run_edit(get_tree()))
	for failure: String in failures:
		print("[edit-check] FALLA ", failure)
	_finish(0 if failures.is_empty() else 1, "edit-test: %d fallas" % failures.size())


func _run_run_error_test() -> void:
	get_tree().create_timer(SAFETY_TIMEOUT_S).timeout.connect(_on_safety_timeout)
	await get_tree().create_timer(2.0).timeout
	var failures := _failures(await RunErrorCheck.new().run_run_error(get_tree(), _arg_value(UI_SHOT_ARG)))
	for failure: String in failures:
		print("[run-error-check] FALLA ", failure)
	_finish_checking_state(0 if failures.is_empty() else 1, "run-error-test: %d fallas" % failures.size(), "run-error-check")


func _run_run_test() -> void:
	get_tree().create_timer(SAFETY_TIMEOUT_S).timeout.connect(_on_safety_timeout)
	await get_tree().create_timer(2.0).timeout
	var failures := _failures(await RunCheck.new().run_run(get_tree()))
	for failure: String in failures:
		print("[run-check] FALLA ", failure)
	_finish_checking_state(0 if failures.is_empty() else 1, "run-test: %d fallas" % failures.size(), "run-check")


func _run_review_test(real_claude: bool) -> void:
	get_tree().create_timer(CLAUDE_TIMEOUT_S if real_claude else SAFETY_TIMEOUT_S).timeout.connect(_on_safety_timeout)
	await get_tree().create_timer(2.0).timeout
	if _find_dock() == null:
		_finish(1, "no se encontró el dock")
		return
	var profile: AgentProfile = AgentProfile.from_dict(AgentProfile.CLAUDE_CODE) if real_claude else null
	var failures := _failures(await ReviewCheck.new().run_review(get_tree(), profile, _arg_value(UI_SHOT_ARG)))
	for failure: String in failures:
		print("[review-check] FALLA ", failure)
	_finish_checking_state(0 if failures.is_empty() else 1, "review-test%s: %d fallas" % [" (Claude)" if real_claude else "", failures.size()], "review-check")


func _run_playtest_suite(only: String) -> void:
	await get_tree().create_timer(2.0).timeout
	var failures := _failures(await PlaytestSuiteCheck.new().run(get_tree(), AgentProfile.from_dict(AgentProfile.CLAUDE_CODE), only))
	for failure: String in failures:
		print("[playtest-suite] FALLA ", failure)
	_finish(0 if failures.is_empty() else 1, "playtest-suite: %d fallas" % failures.size())


func _run_auto_test() -> void:
	get_tree().create_timer(SAFETY_TIMEOUT_S).timeout.connect(_on_safety_timeout)
	await get_tree().create_timer(2.0).timeout
	var failures := _failures(await AutoCheck.new().run_auto(get_tree(), _arg_value(UI_SHOT_ARG)))
	for failure: String in failures:
		print("[auto-check] FALLA ", failure)
	_finish(0 if failures.is_empty() else 1, "auto-test: %d fallas" % failures.size())


func _run_remote_test() -> void:
	get_tree().create_timer(SAFETY_TIMEOUT_S).timeout.connect(_on_safety_timeout)
	await get_tree().create_timer(2.0).timeout
	var failures := _failures(await RemoteCheck.new().run_remote(get_tree(), _arg_value(UI_SHOT_ARG)))
	for failure: String in failures:
		print("[remote-check] FALLA ", failure)
	_finish(0 if failures.is_empty() else 1, "remote-test: %d fallas" % failures.size())


func _run_profile_test() -> void:
	get_tree().create_timer(SAFETY_TIMEOUT_S).timeout.connect(_on_safety_timeout)
	await get_tree().create_timer(2.0).timeout
	var failures := _failures(await ProfileCheck.new().run(get_tree(), self))
	failures.append_array(_failures(await ProfileToolCheck.new().run_profile_tool(get_tree())))
	for failure: String in failures:
		print("[profile-check] FALLA ", failure)
	_finish(0 if failures.is_empty() else 1, "profile-test: %d fallas" % failures.size())


func _run_debug_test() -> void:
	get_tree().create_timer(SAFETY_TIMEOUT_S).timeout.connect(_on_safety_timeout)
	await get_tree().create_timer(2.0).timeout
	var failures := _failures(await DebugCheck.new().run_debug(get_tree()))
	for failure: String in failures:
		print("[debug-check] FALLA ", failure)
	_finish(0 if failures.is_empty() else 1, "debug-test: %d fallas" % failures.size())


func _run_pending_test() -> void:
	get_tree().create_timer(SAFETY_TIMEOUT_S).timeout.connect(_on_safety_timeout)
	await _settle()
	var failures := _failures(await PendingCheck.new().run(get_tree()))
	for failure: String in failures:
		print("[pending-check] FALLA ", failure)
	_finish(0 if failures.is_empty() else 1, "pending-test: %d fallas" % failures.size())


func _run_checks_test() -> void:
	get_tree().create_timer(SAFETY_TIMEOUT_S).timeout.connect(_on_safety_timeout)
	await get_tree().create_timer(2.0).timeout
	var dock := _find_dock()
	if dock == null:
		_finish(1, "no se encontró el dock")
		return
	var failures := _failures(await TurnChecksCheck.new().run(get_tree(), dock))
	for failure: String in failures:
		print("[checks-check] FALLA ", failure)
	_finish_checking_state(0 if failures.is_empty() else 1, "checks-test: %d fallas" % failures.size(), "checks-test")


func _run_ask_menu_test() -> void:
	get_tree().create_timer(SAFETY_TIMEOUT_S).timeout.connect(_on_safety_timeout)
	await get_tree().create_timer(2.0).timeout
	var dock := _find_dock()
	if dock == null:
		_finish(1, "no se encontró el dock")
		return
	var failures := _failures(await AskMenuCheck.new().run(get_tree(), dock))
	for failure: String in failures:
		print("[ask-menu-check] FALLA ", failure)
	_finish(0 if failures.is_empty() else 1, "ask-menu-test: %d fallas" % failures.size())


func _run_hooks_test() -> void:
	get_tree().create_timer(SAFETY_TIMEOUT_S).timeout.connect(_on_safety_timeout)
	await get_tree().create_timer(2.0).timeout
	var dock := _find_dock()
	if dock == null:
		_finish(1, "no se encontró el dock")
		return
	var failures := _failures(await HooksCheck.new().run(get_tree(), dock))
	for failure: String in failures:
		print("[hooks-check] FALLA ", failure)
	_finish(0 if failures.is_empty() else 1, "hooks-test: %d fallas" % failures.size())


func _run_second_opinion_test() -> void:
	get_tree().create_timer(SAFETY_TIMEOUT_S).timeout.connect(_on_safety_timeout)
	await get_tree().create_timer(2.0).timeout
	var dock := _find_dock()
	if dock == null:
		_finish(1, "no se encontró el dock")
		return
	var failures := _failures(await SecondOpinionCheck.new().run(get_tree(), dock))
	for failure: String in failures:
		print("[second-opinion-check] FALLA ", failure)
	_finish_checking_state(0 if failures.is_empty() else 1, "second-opinion-test: %d fallas" % failures.size(), "second-opinion-check")


func _run_bake_test(lightmaps: bool) -> void:
	get_tree().create_timer(SAFETY_TIMEOUT_S).timeout.connect(_on_safety_timeout)
	await get_tree().create_timer(2.0).timeout
	var check := BakeCheck.new()
	check.lightmaps = lightmaps
	var failures := _failures(await check.run(get_tree()))
	for failure: String in failures:
		print("[bake-check] FALLA ", failure)
	_finish_checking_state(0 if failures.is_empty() else 1, "bake-test: %d fallas" % failures.size(), "bake-check")


func _run_instances_test() -> void:
	get_tree().create_timer(SAFETY_TIMEOUT_S).timeout.connect(_on_safety_timeout)
	await get_tree().create_timer(2.0).timeout
	var failures := _failures(await InstancesCheck.new().run(get_tree()))
	for failure: String in failures:
		print("[instances-check] FALLA ", failure)
	_finish_checking_state(0 if failures.is_empty() else 1, "instances-test: %d fallas" % failures.size(), "instances-check")


func _run_quit_test() -> void:
	get_tree().create_timer(SAFETY_TIMEOUT_S).timeout.connect(_on_safety_timeout)
	await get_tree().create_timer(2.0).timeout
	var dock := _find_dock()
	if dock == null:
		_finish(1, "no se encontró el dock")
		return
	var failures := _failures(await QuitCheck.new().run(get_tree(), dock, self))
	for failure: String in failures:
		print("[quit-check] FALLA ", failure)
	if not failures.is_empty():
		_finish(1, "quit-test: %d fallas" % failures.size())
		return
	# Como la X de la ventana: el editor sale por su camino de siempre (los plugins se van al final).
	print("[quit-check] cerrando el editor")
	get_tree().root.propagate_notification(NOTIFICATION_WM_CLOSE_REQUEST)
	await get_tree().create_timer(20.0).timeout
	print("[quit-check] el editor no se cerró con WM_CLOSE_REQUEST")
	get_tree().quit(1)


func _run_playtest_loop_test() -> void:
	get_tree().create_timer(SAFETY_TIMEOUT_S).timeout.connect(_on_safety_timeout)
	await get_tree().create_timer(2.0).timeout
	var dock := _find_dock()
	if dock == null:
		_finish(1, "no se encontró el dock")
		return
	var failures := _failures(await PlaytestLoopCheck.new().run(get_tree(), dock))
	for failure: String in failures:
		print("[playtest-loop-check] FALLA ", failure)
	_finish_checking_state(0 if failures.is_empty() else 1, "playtest-loop-test: %d fallas" % failures.size(), "playtest-loop-check")


func _run_plan_test(real_claude: bool = false, antigravity: bool = false) -> void:
	get_tree().create_timer(CLAUDE_TIMEOUT_S * 3 if real_claude else SAFETY_TIMEOUT_S).timeout.connect(_on_safety_timeout)
	await get_tree().create_timer(2.0).timeout
	var dock := _find_dock()
	if dock == null:
		_finish(1, "no se encontró el dock")
		return
	var check := PlanCheck.new()
	var result: Variant
	if antigravity:
		result = await check.run_antigravity(get_tree(), dock, _arg_value(UI_SHOT_ARG))
	elif real_claude:
		result = await check.run_claude(get_tree(), dock, _arg_value(UI_SHOT_ARG))
	else:
		result = await check.run(get_tree(), dock, _arg_value(UI_SHOT_ARG))
	var failures := _failures(result)
	for failure: String in failures:
		print("[plan-check] FALLA ", failure)
	_finish_checking_state(0 if failures.is_empty() else 1, "plan-test: %d fallas" % failures.size(), "plan-test")


func _run_agy_tour() -> void:
	get_tree().create_timer(CLAUDE_TIMEOUT_S * 8).timeout.connect(_on_safety_timeout)
	await get_tree().create_timer(2.0).timeout
	var dock := _find_dock()
	if dock == null:
		_finish(1, "no se encontró el dock")
		return
	var failures := _failures(await AgyTourCheck.new().run_tour(get_tree(), dock))
	for failure: String in failures:
		print("[agy-tour] FALLA ", failure)
	_finish_checking_state(0 if failures.is_empty() else 1, "agy-tour: %d fallas" % failures.size(), "agy-tour")


func _run_oneshot_test() -> void:
	get_tree().create_timer(SAFETY_TIMEOUT_S).timeout.connect(_on_safety_timeout)
	await get_tree().create_timer(2.0).timeout
	var failures := _failures(await OneShotUiCheck.new().run_oneshot(get_tree(), _arg_value(UI_SHOT_ARG)))
	for failure: String in failures:
		print("[oneshot-check] FALLA ", failure)
	_finish_checking_state(0 if failures.is_empty() else 1, "oneshot-test: %d fallas" % failures.size(), "oneshot-check")


func _run_claude_oneshot_test() -> void:
	get_tree().create_timer(CLAUDE_ONESHOT_TIMEOUT_S).timeout.connect(_on_safety_timeout)
	await get_tree().create_timer(2.0).timeout
	var failures := _failures(await OneShotUiCheck.new().run_claude_oneshot(get_tree(), _arg_value(UI_SHOT_ARG)))
	for failure: String in failures:
		print("[claude-oneshot] FALLA ", failure)
	_finish(0 if failures.is_empty() else 1, "claude-oneshot-test: %d fallas" % failures.size())


func _run_long_test() -> void:
	get_tree().create_timer(SAFETY_TIMEOUT_S).timeout.connect(_on_safety_timeout)
	await get_tree().create_timer(2.0).timeout
	var check := LongSessionCheck.new()
	var failures := _failures(await check.run_long(get_tree()))
	print("[long-check] ", check.report)
	for failure: String in failures:
		print("[long-check] FALLA ", failure)
	_finish(0 if failures.is_empty() else 1, "long-test: %d fallas" % failures.size())


func _run_completion_test() -> void:
	get_tree().create_timer(SAFETY_TIMEOUT_S).timeout.connect(_on_safety_timeout)
	await get_tree().create_timer(2.0).timeout
	var check := CompletionCheck.new()
	var failures := _failures(await check.run(get_tree(), _arg_value(UI_SHOT_ARG)))
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
	if not await controller.call(&"start", AgentProfile.from_dict(AgentProfile.CLAUDE_CODE)):
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
		PlaytestAutoload.register(main_plugin.get(&"_plugin"))
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
	if not await controller.call(&"start", AgentProfile.from_dict(AgentProfile.CLAUDE_CODE)):
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
			# Sube hasta la ranura del editor: el dock va dentro de las pestañas de sesiones (m7-44)
			# y de un MinSizeGuard.
			var guard := node.get_parent()
			var holder := guard.get_parent()
			while holder and not holder.has_method(&"make_visible") and not holder is TabContainer:
				guard = holder
				holder = holder.get_parent()
			if holder == null:
				return node
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
	if scenario == "crash":
		await _check_crash_card(dock, model, shot_path)
		return
	if scenario == "ui_memory":
		var memory_failures: Array = await MemoryCheck.new().run(get_tree(), _find_by_script(MemoryCheck.MAIN_PLUGIN_SCRIPT), dock, shot_path)
		for failure: String in memory_failures:
			print("[memory-check] FALLA ", failure)
		_finish(0 if memory_failures.is_empty() else 1, "ui-memory: %d fallas" % memory_failures.size())
		return
	if scenario == "ui_recipe":
		var recipe_failures: Array = await RecipeCheck.new().run(get_tree(), _find_by_script(RecipeCheck.MAIN_PLUGIN_SCRIPT), dock, shot_path)
		for failure: String in recipe_failures:
			print("[recipe-check] FALLA ", failure)
		_finish(0 if recipe_failures.is_empty() else 1, "ui-recipe: %d fallas" % recipe_failures.size())
		return
	if scenario == "ui_plan_criteria":
		var criteria_failures: Array = await PlanCriteriaCheck.new().run(get_tree(), _find_by_script(PlanCriteriaCheck.MAIN_PLUGIN_SCRIPT), dock, shot_path)
		for failure: String in criteria_failures:
			print("[plan-criteria-check] FALLA ", failure)
		_finish(0 if criteria_failures.is_empty() else 1, "ui-plan-criteria: %d fallas" % criteria_failures.size())
		return
	if scenario == "ui_path_rules":
		var rules_failures: Array = await PathRulesCheck.new().run(get_tree(), _find_by_script(PathRulesCheck.MAIN_PLUGIN_SCRIPT), dock, shot_path)
		for failure: String in rules_failures:
			print("[path-rules-check] FALLA ", failure)
		_finish(0 if rules_failures.is_empty() else 1, "ui-path-rules: %d fallas" % rules_failures.size())
		return
	if scenario == "ui_handoff":
		var handoff_failures: Array = await HandoffCheck.new().run(get_tree(), _find_by_script(HandoffCheck.MAIN_PLUGIN_SCRIPT), dock, shot_path)
		for failure: String in handoff_failures:
			print("[handoff-check] FALLA ", failure)
		_finish(0 if handoff_failures.is_empty() else 1, "ui-handoff: %d fallas" % handoff_failures.size())
		return
	dock.call(&"add_context_files", PackedStringArray(["res://project.godot"]))
	var chips: Dictionary = dock.get(&"_chips")
	if not chips.has("file:res://project.godot"):
		_finish(1, "+ contexto no agregó el chip del archivo")
		return
	# El cuadro de texto crece con 30 líneas, sin pasar del 40 % del dock ni tapar el chat (m17-22).
	var text_box: Control = dock.get(&"_composer")
	var input: Control = text_box.get(&"_input")
	# En automático, sin el alto que haya fijado a mano quien corre el test (se restaura después).
	var saved_height: float = text_box.call(&"manual_height")
	text_box.call(&"set_manual_height", 0.0)
	for i in 2:
		await get_tree().process_frame
	var rest_height := input.size.y
	text_box.call(&"insert_text", "\n".join(range(30).map(func(i: int) -> String: return "línea %d" % i)))
	for i in 3:
		await get_tree().process_frame
	var conversation: Control = dock.get(&"_conversation")
	var grown := input.size.y
	if grown <= rest_height * 1.5 or grown > dock.size.y * 0.41 or conversation.get_global_rect().end.y > text_box.get_global_rect().position.y + 1:
		text_box.call(&"set_manual_height", saved_height)
		_finish(1, "el composer no creció bien: %.0f → %.0f (dock %.0f), chat hasta %.0f, composer desde %.0f" % [rest_height, grown, dock.size.y, conversation.get_global_rect().end.y, text_box.get_global_rect().position.y])
		return
	if not shot_path.is_empty():
		var shot := get_viewport().get_texture().get_image()
		shot.save_png(shot_path.get_basename() + "_composer.png")
	text_box.call(&"clear")
	for i in 3:
		await get_tree().process_frame
	var back_height := input.size.y
	text_box.call(&"set_manual_height", saved_height)
	if not is_equal_approx(back_height, rest_height):
		_finish(1, "el composer no volvió al alto de reposo: %.0f" % back_height)
		return
	# Un texto de afuera del proyecto va como resource_link con su ruta absoluta (m17-21).
	var outside_md := OS.get_user_data_dir().path_join("ui_test_notes.md")
	DirAccess.make_dir_recursive_absolute(OS.get_user_data_dir())  # un worktree nuevo todavía no la tiene
	var md_file := FileAccess.open(outside_md, FileAccess.WRITE)
	md_file.store_string("# notas\n")
	md_file.close()
	dock.call(&"add_context_files", PackedStringArray([outside_md, "/no/existe/x.md"]))
	chips = dock.get(&"_chips")
	var md_chip: Dictionary = chips.get("file:" + outside_md, {})
	if md_chip.is_empty() or md_chip.block.type != "resource_link" or md_chip.block.uri != "file://" + outside_md or md_chip.block.mimeType != "text/markdown":
		_finish(1, "un .md de afuera no quedó como resource_link: %s" % [md_chip])
		return
	if chips.has("file:/no/existe/x.md"):
		_finish(1, "adjuntó un archivo que no existe")
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
	if chips.has("file:res://project.godot") or chips.has("file:" + outside_md) or chips.keys().any(func(id: String) -> bool: return id.begins_with("image:")):
		_finish(1, "los adjuntos siguieron después de enviar: %s" % [chips.keys()])
		return
	# El estado va en una línea arriba del composer, no en el chip del agente (m17-25).
	await get_tree().process_frame
	var state_line: Label = dock.get(&"_state_line")
	var chip: Button = dock.get(&"_agent_chip")
	var composer_top: float = (dock.get(&"_composer") as Control).get_global_rect().position.y
	if not state_line.is_visible_in_tree() or not state_line.text.contains(I18n.t("Working…")) or state_line.get_global_rect().end.y > composer_top + 1 or chip.text.contains("·"):
		_finish(1, "la línea de estado no quedó arriba del composer: «%s» visible=%s, chip «%s»" % [state_line.text, state_line.is_visible_in_tree(), chip.text])
		return
	if not shot_path.is_empty():
		get_viewport().get_texture().get_image().save_png(shot_path.get_basename() + "_state.png")
	if not await _check_header_tooltip(dock, chip, shot_path):
		return
	if scenario == "ui_markdown" and not await _check_machine_chips(dock, shot_path):
		return
	if scenario == "ui_long_permission" and not await _check_long_permission(dock, model, shot_path):
		return
	if scenario == "ui_quota_busy" and not await _check_ring_tooltip(dock, shot_path):
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
		var meter: Control = dock.get(&"_quota_ring")
		if not (send.disabled and send.text.begins_with("⏳") and meter.is_visible_in_tree() and str(meter.get(&"hint_text")).contains("\n")):
			_finish(1, "cuota: el envío no quedó bloqueado (%s, disabled=%s) o no se ve el medidor" % [send.text, send.disabled])
			return
		if not await _check_ring_tooltip(dock, shot_path):
			return
	if scenario == "ui_markdown" and not await _check_markdown_and_viewer(dock, shot_path):
		return
	if scenario == "ui_harness_prompt" and not await _check_harness_prompts(dock, model, controller, shot_path):
		return
	if not shot_path.is_empty():
		var image := EditorInterface.get_base_control().get_viewport().get_texture().get_image()
		image.save_png(shot_path)
	controller.call(&"stop")
	_finish(0, "ui-test %s" % scenario)


## m13-22: el agente se cae en el primer turno y la tarjeta muestra las últimas líneas de su stderr
## recortadas: el agente falso vuelca el prompt entero (con el prompt de sistema en JSON) por
## stderr, y eso no puede tapar la causa. El texto completo queda en el Agent Log.
func _check_crash_card(dock: Control, model: Object, shot_path: String) -> void:
	dock.call(&"_on_submitted", "caete")
	var deadline := Time.get_ticks_msec() + 20000
	while int(model.get(&"state")) != SessionModel.SessionState.FAILED and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	await get_tree().create_timer(0.5).timeout
	if not shot_path.is_empty():
		EditorInterface.get_base_control().get_viewport().get_texture().get_image().save_png(shot_path)
	if int(model.get(&"state")) != SessionModel.SessionState.FAILED:
		_finish(1, "crash: la sesión no quedó en FAILED (%d)" % int(model.get(&"state")))
		return
	var cards: Array = (model.call(&"entries") as Array).filter(func(entry: Object) -> bool: return not str(entry.get(&"details")).is_empty())
	if cards.is_empty():
		_finish(1, "crash: ninguna tarjeta trae las líneas del log")
		return
	var details := str(cards.back().get(&"details"))
	var failures: PackedStringArray = []
	if details.length() > SessionController.STDERR_TAIL * (SessionController.STDERR_LINE_CHARS + 80):
		failures.append("los detalles son demasiado largos: %d caracteres" % details.length())
	for line: String in details.split("\n"):
		if line.length() > SessionController.STDERR_LINE_CHARS + 80:
			failures.append("una línea de %d caracteres: %s…" % [line.length(), line.left(60)])
	if not details.contains(I18n.t("… %d more characters, see the Agent Log").get_slice("%d", 0)):
		failures.append("la línea del prompt no dice cuánto quedó afuera")
	if not details.contains("fake_agent: prompt"):
		failures.append("los detalles no muestran de qué línea se trata: %s" % details.left(120))
	var main_plugin := _find_by_script(MAIN_PLUGIN_SCRIPT)
	var log: Object = main_plugin.get(&"_log")
	var full_in_log := (log.call(&"entries") as Array).any(func(entry: Dictionary) -> bool: return str(entry.message).contains("harness_context"))
	if not full_in_log:
		failures.append("el Agent Log no tiene la línea completa")
	# El agente falso vuelca session/new con el token del server MCP en los headers: redactado.
	var mcp_server: Object = main_plugin.get(&"_mcp_server")
	var token := str(mcp_server.get(&"token")) if mcp_server else ""
	var tail: PackedStringArray = (dock.get(&"_controller") as Object).get(&"_stderr_tail")
	if not token.is_empty() and (details.contains(token) or details.contains(token.left(8))):
		failures.append("los detalles traen el token del server MCP")
	if not token.is_empty() and "\n".join(tail).contains(token):
		failures.append("la cola de stderr del controller guarda el token sin redactar")
	if not "\n".join(tail).contains(AgentLog.REDACTED):
		failures.append("la cola de stderr no tiene la línea de session/new redactada: %s" % ["\n".join(tail).left(300)])
	print("[ui-test] tarjeta de caída: %d caracteres, %d líneas" % [details.length(), details.split("\n").size()])
	for failure: String in failures:
		print("[ui-test] FALLA crash: " + failure)
	_finish(0 if failures.is_empty() else 1, "ui-test crash: %d fallas" % failures.size())


## m13-29: el tooltip del chip del agente dice el estado de cada máquina con su antigüedad (la
## sesión trabajando, el juego de run_scene), leído al momento. Con captura, se abre de verdad.
func _check_header_tooltip(dock: Control, chip: Button, shot_path: String) -> bool:
	var tooltip := chip.tooltip_text
	var session_line := I18n.t("Session") + ": " + I18n.t("working")
	var game_line := I18n.t("Game") + ": "
	if not tooltip.begins_with(session_line) or not tooltip.contains(game_line) or not tooltip.contains(" s\n"):
		_finish(1, "el tooltip del encabezado no dice el estado de las máquinas: «%s»" % tooltip.replace("\n", " | "))
		return false
	if not shot_path.is_empty():
		var hover := InputEventMouseMotion.new()
		hover.position = chip.get_global_rect().get_center()
		hover.global_position = hover.position
		chip.get_viewport().push_input(hover)
		await get_tree().create_timer(1.5).timeout
		if not _tooltip_open(chip.get_viewport()):
			_finish(1, "el tooltip del encabezado no se abrió con el mouse encima")
			return false
		# El tooltip es una ventana aparte: la textura del editor no lo trae, se compone encima.
		var shot := get_viewport().get_texture().get_image()
		for window: Window in _tooltip_windows(chip.get_viewport()):
			var tip := window.get_texture().get_image()
			tip.convert(shot.get_format())
			shot.blit_rect(tip, Rect2i(Vector2i.ZERO, tip.get_size()), window.position - get_window().position)
		shot.save_png(shot_path.get_basename() + "_header_tooltip.png")
		var away := InputEventMouseMotion.new()
		away.position = Vector2(4, dock.get_global_rect().end.y - 4)
		away.global_position = away.position
		chip.get_viewport().push_input(away)
		await get_tree().create_timer(0.5).timeout
	return true


## m12-47: con un juego en marcha, un chip junto al estado dice qué hace (sin pasar el mouse); sin
## juego no hay chip. Corre un run manual (el debugger lo ve igual que run_scene) y lo para.
func _check_machine_chips(dock: Control, shot_path: String) -> bool:
	var chips: Control = dock.get(&"_machine_chips")
	var deadline := Time.get_ticks_msec() + 5000
	while chips.is_visible_in_tree() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame  # el run_scene del guion ya terminó: el chip se va solo
	if chips.is_visible_in_tree():
		_finish(1, "sin juego en marcha sigue habiendo un chip: «%s»" % (chips.get_child(0) as Label).text)
		return false
	EditorInterface.play_custom_scene("res://tests/fixtures/run_fixture.tscn")
	deadline = Time.get_ticks_msec() + 15000
	while not chips.is_visible_in_tree() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	if not chips.is_visible_in_tree() or chips.get_child_count() != 1:
		EditorInterface.stop_playing_scene()
		_finish(1, "con el juego corriendo no apareció el chip del juego (%d chips)" % chips.get_child_count())
		return false
	var label := chips.get_child(0) as Label
	if not label.text.begins_with(I18n.t("Game") + " · ") or not label.text.contains(" s") or label.tooltip_text != dock.call(&"header_tooltip"):
		EditorInterface.stop_playing_scene()
		_finish(1, "el chip del juego no dice el estado con su antigüedad o no lleva el tooltip del encabezado: «%s»" % label.text)
		return false
	for failure: String in LayoutCheck.dock_fits(dock):
		EditorInterface.stop_playing_scene()
		_finish(1, "con el chip del juego: " + failure)
		return false
	if not shot_path.is_empty():
		await get_tree().create_timer(0.5).timeout
		_save_dock_shot(dock, shot_path.get_basename() + "_game_chip.png")
		await LayoutCheck.set_dock_width(dock, 300)
		await get_tree().create_timer(0.5).timeout
		for failure: String in LayoutCheck.dock_fits(dock):
			EditorInterface.stop_playing_scene()
			_finish(1, "con el chip del juego y el dock angosto: " + failure)
			return false
		_save_dock_shot(dock, shot_path.get_basename() + "_game_chip_narrow.png")
		await LayoutCheck.set_dock_width(dock, 480)
	EditorInterface.stop_playing_scene()
	deadline = Time.get_ticks_msec() + 10000
	while chips.is_visible_in_tree() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	if chips.is_visible_in_tree():
		_finish(1, "el chip del juego quedó después de pararlo: «%s»" % label.text)
		return false
	return true


func _save_dock_shot(dock: Control, path: String) -> void:
	var image := get_viewport().get_texture().get_image()
	image.get_region(Rect2i((dock.get_parent() as Control).get_global_rect())).save_png(path)


## m17-14: el tooltip del anillo de cuota sigue abierto con el mouse encima, aunque el dock lo
## refresque cada segundo y el turno vaya cambiando el contexto usado.
func _check_ring_tooltip(dock: Control, shot_path: String = "") -> bool:
	var ring: Control = dock.get(&"_quota_ring")
	await get_tree().create_timer(0.5).timeout
	var hover := InputEventMouseMotion.new()
	hover.position = ring.get_global_rect().get_center()
	hover.global_position = hover.position
	ring.get_viewport().push_input(hover)
	var seen: Array[bool] = []
	for i in 8:
		await get_tree().create_timer(0.5).timeout
		seen.append(bool(ring.call(&"is_hint_visible")))
	print("[ui-test] detalle del anillo: %s" % [seen])
	var panel: Control = ring.get(&"_hint_panel")
	if not seen.slice(2).all(func(open: bool) -> bool: return open) or panel == null:
		_finish(1, "cuota: el detalle del anillo no quedó abierto con el mouse encima: %s" % [seen])
		return false
	# Arriba del anillo, sin tapar el mouse (lo que cerraba el tooltip de Godot), y adentro de la ventana.
	var area := ring.get_viewport().get_visible_rect()
	if panel.get_global_rect().has_point(hover.position) or not area.encloses(panel.get_global_rect()) or panel.get_global_rect().end.y > ring.get_global_rect().position.y:
		_finish(1, "cuota: el detalle tapa el mouse o se sale de la ventana: %s, anillo %s" % [panel.get_global_rect(), ring.get_global_rect()])
		return false
	if not shot_path.is_empty():
		ring.get_viewport().get_texture().get_image().save_png(shot_path.get_basename() + "_quota_hint.png")
	if _tooltip_open(ring.get_viewport()):
		_finish(1, "cuota: además del panel se abrió el tooltip de Godot")
		return false
	var away := InputEventMouseMotion.new()
	away.position = Vector2(10, 10)
	away.global_position = away.position
	ring.get_viewport().push_input(away)
	await get_tree().create_timer(0.2).timeout
	if bool(ring.call(&"is_hint_visible")):
		_finish(1, "cuota: el detalle no se cerró al sacar el mouse")
		return false
	return true


func _tooltip_open(viewport: Viewport) -> bool:
	return not _tooltip_windows(viewport).is_empty()


## Los tooltips de Godot abiertos bajo `viewport` (ventanas propias, no se ven en su textura).
func _tooltip_windows(viewport: Viewport) -> Array[Window]:
	var windows: Array[Window] = []
	for node: Node in viewport.find_children("*", "Window", true, false):
		if (node as Window).visible and node.get_class() in ["PopupPanel", "TooltipPanel"]:
			windows.append(node)
	return windows


## m7-28/m7-29: el mensaje del agente lleva su bloque de código en una caja aparte, y un clic en la
## captura del tool call abre el visor (captura en <shot>_viewer.png), que se libera al cerrarlo.
## m17-26: un permiso con un comando de 150 líneas deja los botones a la vista, dentro del dock.
func _check_long_permission(dock: Control, model: Object, shot_path: String) -> bool:
	var pending: Array = model.get(&"pending_permissions")
	var waited := 0.0
	while pending.is_empty() and waited < 10.0:
		await get_tree().create_timer(0.1).timeout
		waited += 0.1
		pending = model.get(&"pending_permissions")
	if pending.is_empty():
		_finish(1, "no llegó el permiso largo")
		return false
	for i in 3:
		await get_tree().process_frame
	var buttons: Array[Node] = dock.find_children("*", "Button", true, false).filter(func(node: Node) -> bool:
		return node is Button and (node as Button).is_visible_in_tree() and (node as Button).text == I18n.t("Allow once"))
	if buttons.is_empty():
		_finish(1, "el botón «%s» no se ve" % I18n.t("Allow once"))
		return false
	var button := buttons[0] as Button
	var dock_rect := dock.get_global_rect()
	if not dock_rect.encloses(button.get_global_rect()):
		_finish(1, "el botón quedó fuera del dock: %s en %s" % [button.get_global_rect(), dock_rect])
		return false
	if not shot_path.is_empty():
		get_viewport().get_texture().get_image().save_png(shot_path.get_basename() + "_long_permission.png")
	button.pressed.emit()
	return true


## m12-44: lo que manda el harness (el chequeo después del turno, lo que vio el supervisor) sale
## atenuado y plegado, con la etiqueta en el idioma de la interfaz; «Ver prompt» muestra lo que le
## llegó al agente, en inglés.
func _check_harness_prompts(dock: Control, model: Object, controller: Object, shot_path: String) -> bool:
	var check := "[Automatic check after your turn] These scripts you changed don't parse. Fix them, then check again with godot.validate_scripts:\nres://player.gd:12 - Parse Error: Expected end of statement after expression."
	await controller.call(&"send_prompt", controller.call(&"label_prompt", check, HarnessPrompts.TURN_CHECK))
	var supervisor := "The editor crashed while the game was running (res://boss.gd:40). The supervisor reopened it."
	dock.call(&"send_text", supervisor, HarnessPrompts.SUPERVISOR)
	var users := func() -> Array: return (model.call(&"entries") as Array).filter(func(entry: ChatEntry) -> bool: return entry.kind == ChatEntry.EntryKind.USER)
	var deadline := Time.get_ticks_msec() + 15000
	while (users.call().size() < 3 or int(model.get(&"state")) != 2) and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	var labels: Array = users.call().map(func(entry: ChatEntry) -> String: return entry.harness_label)
	if labels != ["", HarnessPrompts.TURN_CHECK, HarnessPrompts.SUPERVISOR]:
		_finish(1, "harness: etiquetas de los prompts %s" % [labels])
		return false
	if users.call()[1].text != check or users.call()[2].text != supervisor:
		_finish(1, "harness: el texto que recibe el agente cambió")
		return false
	await get_tree().create_timer(0.5).timeout
	var conversation: Control = dock.get(&"_conversation")
	var views: Array = (conversation.get(&"_views") as Dictionary).values().filter(func(view: Node) -> bool: return view.has_method(&"is_harness") and view.call(&"is_harness"))
	if views.size() != 2:
		_finish(1, "harness: %d vistas del harness (2 esperadas)" % views.size())
		return false
	var first: Control = views[0]
	var caption: Label = first.get(&"_caption")
	var prompt: Label = first.get(&"_label")
	var toggle: Button = first.get(&"_toggle")
	var expected := "⚙ " + I18n.t(HarnessPrompts.TURN_CHECK)
	if caption.text != expected or not caption.is_visible_in_tree() or prompt.visible or toggle.text != I18n.t("Show prompt"):
		_finish(1, "harness: plegado «%s» (esperado «%s»), prompt visible=%s, botón «%s»" % [caption.text, expected, prompt.visible, toggle.text])
		return false
	conversation.call(&"_scroll_to_bottom")
	await get_tree().create_timer(0.3).timeout
	if not shot_path.is_empty():
		EditorInterface.get_base_control().get_viewport().get_texture().get_image().save_png(shot_path.get_basename() + "_harness.png")
	# La etiqueta entera en hasta dos líneas, sin «…», en los dos prompts y con el ancho del dock.
	for view: Control in views:
		var label: Label = view.get(&"_caption")
		if label.get_line_count() > label.max_lines_visible or label.get_line_count() < 1:
			_finish(1, "harness: «%s» no entra en %d líneas (%d, %.0f px de ancho)" % [label.text, label.max_lines_visible, label.get_line_count(), label.size.x])
			return false
		var button: Button = view.get(&"_toggle")
		if not button.is_visible_in_tree() or button.get_global_rect().end.x > conversation.get_global_rect().end.x + 1:
			_finish(1, "harness: «%s» no se ve entero" % button.text)
			return false
	toggle.pressed.emit()
	await get_tree().create_timer(0.3).timeout
	if not prompt.is_visible_in_tree() or prompt.text != check or toggle.text != I18n.t("Hide prompt"):
		_finish(1, "harness: «Ver prompt» no mostró el prompt (visible=%s, botón «%s»)" % [prompt.is_visible_in_tree(), toggle.text])
		return false
	if prompt.get_global_rect().end.x > conversation.get_global_rect().end.x + 1:
		_finish(1, "harness: el prompt desplegado se sale del chat")
		return false
	conversation.call(&"_scroll_to_bottom")
	await get_tree().create_timer(0.3).timeout
	if not shot_path.is_empty():
		EditorInterface.get_base_control().get_viewport().get_texture().get_image().save_png(shot_path.get_basename() + "_harness_open.png")
	print("[ui-test] harness: %s plegado y desplegado" % caption.text)
	return true


func _check_markdown_and_viewer(dock: Control, shot_path: String) -> bool:
	dock.emit_signal(&"show_log_requested")  # el log ocupa lugar: se vuelve a plegar
	var code_views := dock.find_children("*", "PanelContainer", true, false).filter(func(node: Node) -> bool:
		return str(node.get_script().resource_path if node.get_script() else "").ends_with("code_block_view.gd"))
	if code_views.size() != 1:
		_finish(1, "markdown: se esperaba 1 bloque de código en su caja, hay %d" % code_views.size())
		return false
	var thumbs := dock.find_children("*", "TextureRect", true, false).filter(func(node: Node) -> bool:
		return (node as TextureRect).mouse_default_cursor_shape == Control.CURSOR_POINTING_HAND and (node as Control).is_visible_in_tree())
	if thumbs.size() != 1:
		_finish(1, "visor: se esperaba 1 miniatura clicable, hay %d" % thumbs.size())
		return false
	var thumb: TextureRect = thumbs[0]
	var scroll := dock.find_children("*", "ScrollContainer", true, false)
	for node: Node in scroll:
		if (node as ScrollContainer).is_ancestor_of(thumb):
			(node as ScrollContainer).ensure_control_visible(thumb)
	await get_tree().create_timer(0.3).timeout
	if not shot_path.is_empty():
		EditorInterface.get_base_control().get_viewport().get_texture().get_image().save_png(shot_path.get_basename() + "_chat.png")
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = thumb.size / 2.0
	thumb.gui_input.emit(click)
	await get_tree().create_timer(0.5).timeout
	var viewers := EditorInterface.get_base_control().find_children("*", "AcceptDialog", false, false).filter(func(node: Node) -> bool:
		return node.get_script() != null and str(node.get_script().resource_path).ends_with("image_viewer.gd"))
	if viewers.size() != 1 or not (viewers[0] as Window).visible:
		_finish(1, "visor: el clic en la miniatura no abrió el visor (%d)" % viewers.size())
		return false
	var viewer: AcceptDialog = viewers[0]
	if not str(viewer.title).contains("480×270"):
		_finish(1, "visor: el título no tiene el tamaño de la imagen: %s" % viewer.title)
		return false
	if not shot_path.is_empty():
		viewer.get_texture().get_image().save_png(shot_path.get_basename() + "_viewer.png")
	viewer.hide()
	await get_tree().process_frame
	await get_tree().process_frame
	if is_instance_valid(viewer):
		_finish(1, "visor: no se liberó al cerrarlo")
		return false
	return true


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
	var login_button := await _wait_button(dock, "Cuenta falsa")
	if login_button == null:
		_finish(1, "el aviso no ofrece iniciar sesión")
		return
	login_button.pressed.emit()
	var code_button := await _wait_button(dock, I18n.t("Paste code…"))
	if code_button == null or _find_button(dock, I18n.t("Open link")) == null:
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
	_finish_checking_state(0, "login: desde el dock, con el código pegado, la sesión abrió", "login-test")


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
	var send_now := await _wait_button(dock, I18n.t("Send now"))
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
	# m7-33: con un turno largo corriendo, «Enviar ahora» de la segunda fila corta el turno y manda
	# ese prompt antes que el primero.
	profile.args[profile.args.size() - 1] = "--scenario=res://tests/scripts/queue_now.json"
	if not await controller.call(&"start", profile):
		failures.append("no arrancó la segunda sesión (%s)" % model.get(&"failure_message"))
	else:
		for text: String in ["largo", "uno", "dos"]:
			input.text = text
			composer.call(&"_submit")
			await get_tree().process_frame
		var rows: VBoxContainer = queue_view.get(&"_rows")
		await get_tree().process_frame
		if rows.get_child_count() != 2:
			failures.append("enviar ahora: la cola no tiene 2 filas (%d)" % rows.get_child_count())
		else:
			(rows.get_child(1).get_child(1) as Button).pressed.emit()
			deadline = Time.get_ticks_msec() + 20000
			while user_messages.call().size() < 2 and Time.get_ticks_msec() < deadline:
				await get_tree().process_frame
			var agent_text := (model.call(&"entries") as Array).filter(func(entry: Object) -> bool: return int(entry.get(&"kind")) == 1).map(func(entry: Object) -> String: return str(entry.get(&"text")))
			if user_messages.call() != ["largo", "dos"]:
				failures.append("enviar ahora: no salió «dos» enseguida: %s" % [user_messages.call()])
			if agent_text.any(func(text: String) -> bool: return text.contains("no tendría que llegar")):
				failures.append("enviar ahora: el turno largo no se cortó")
			if int(queue.call(&"size")) != 1 or bool(queue.get(&"paused")):
				failures.append("enviar ahora: «uno» no quedó en la cola sin pausa (%d, pausada %s)" % [queue.call(&"size"), queue.get(&"paused")])
			deadline = Time.get_ticks_msec() + 20000
			while (not bool(queue.call(&"is_empty")) or bool(model.call(&"is_busy"))) and Time.get_ticks_msec() < deadline:
				await get_tree().process_frame
			if user_messages.call() != ["largo", "dos", "uno"]:
				failures.append("enviar ahora: el resto de la cola no siguió: %s" % [user_messages.call()])
		controller.call(&"stop")
	for failure: String in failures:
		print("[queue-test] FALLA ", failure)
	_finish_checking_state(0 if failures.is_empty() else 1, "queue-test: %d fallas" % failures.size(), "queue-test")


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
		_finish(1, "falta el catálogo, el dock, la pantalla One-shot o el Agent Log")
		return
	var failures: PackedStringArray = []
	var seen := {}
	_untranslated(dock, catalog, "dock", failures, seen)
	# Con los textos en español (más largos), el dock sigue entrando en su panel (m7-23).
	failures.append_array(LayoutCheck.dock_fits(dock))
	failures.append_array(await LayoutCheck.composer_fits(dock))
	failures.append_array(await LayoutCheck.user_bubble_fits(dock))
	EditorInterface.set_main_screen_editor(MAIN_SCREEN_NAME)
	await get_tree().create_timer(0.5).timeout
	_untranslated(main_screen, catalog, "pantalla One-shot", failures, seen)
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
	# Los textos a la vista que sí están en español: si son pocos, el idioma no se aplicó. El botón
	# de arrancar dice «Nueva sesión» cuando hay sesiones recientes en el historial (m17-07).
	var spanish := seen.keys().filter(func(text: String) -> bool: return text in ["Iniciar sesión", "Nueva sesión", "Construir", "Presupuestos", "Permisos"])
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
	# El formulario de un agente abierto, al ancho del diálogo (los campos no se achican).
	if not (dialog.get(&"_profiles") as Array).is_empty():
		nav.select(0)
		nav.item_selected.emit(0)
		dialog.call(&"_edit_profile", 0)
		await get_tree().create_timer(0.4).timeout
		dialog.get_texture().get_image().save_png("%s_agent_form.png" % prefix)
		dialog.call(&"_apply_profile_form")
	# m7-34/m7-35: un server de terceros en la lista suma su fila a la matriz de permisos.
	var mcp_page: Object = dialog.get(&"_mcp_servers_page")
	mcp_page.call(&"import_mcp_json", JSON.stringify({"mcpServers": {"blender": {"command": "uvx", "args": ["blender-mcp"], "env": {"BLENDER_TOKEN": "$BLENDER_TOKEN"}}}}))
	mcp_page.emit_signal(&"servers_changed")
	mcp_page.call(&"_edit", 0)
	nav.select(2)
	nav.item_selected.emit(2)
	await get_tree().create_timer(0.4).timeout
	dialog.get_texture().get_image().save_png("%s_mcp_servers.png" % prefix)
	# m11-31: la lista de checks con uno que vino en el archivo sin aprobar y un preset agregado. Se
	# vuelve a cargar la del proyecto antes de guardar: no aprueba nada en los EditorSettings.
	var checks_editor: Control = dialog.get(&"_turn_checks_editor")
	checks_editor.call(&"load_from", [{"name": "Lint", "command": "{godot} --headless --path {project} -s res://tests/lint.gd", "paths": ["res://scripts/**"]}], func(_key: String) -> bool: return false, ProjectSettings.globalize_path("res://"))
	checks_editor.call(&"_on_preset", 1)
	await get_tree().process_frame
	var scroll := checks_editor.get_parent()
	while scroll and not scroll is ScrollContainer:
		if scroll is FoldableContainer:
			(scroll as FoldableContainer).folded = false
		scroll = scroll.get_parent()
	await get_tree().process_frame
	if scroll:
		(scroll as ScrollContainer).ensure_control_visible(checks_editor.get_child(checks_editor.get_child_count() - 1))
	await get_tree().create_timer(0.4).timeout
	dialog.get_texture().get_image().save_png("%s_turn_checks.png" % prefix)
	var project_config: Object = dialog.get(&"_config")
	checks_editor.call(&"load_from", project_config.get(&"turn_checks"), func(_key: String) -> bool: return false, ProjectSettings.globalize_path("res://"))
	nav.select(1)
	nav.item_selected.emit(1)
	await get_tree().create_timer(0.4).timeout
	dialog.get_texture().get_image().save_png("%s_mcp_permissions.png" % prefix)
	var matrix: Dictionary = dialog.get(&"_matrix")
	if not matrix.has("mcp:blender"):
		_finish(1, "settings: la matriz no tiene la fila de mcp:blender (%s)" % [matrix.keys()])
		return
	(matrix["mcp:blender"][3] as OptionButton).select(0)  # One-shot (HarnessMode 3) · Permitir
	# Guardar aplica la matriz en caliente y escribe project_config.tres (se restaura al final).
	var config_path := "res://addons/godot_agent/config/project_config.tres"
	var had_config := FileAccess.file_exists(config_path)
	var config_before := FileAccess.get_file_as_string(config_path) if had_config else ""
	var option: OptionButton = matrix["read"][0]  # Lectura · Preguntar
	option.select(2)  # no
	# m13-31: importado de .mcp.json no queda aprobado; «Allow on this machine» sí (se borra al final:
	# estos checks usan los EditorSettings del usuario).
	var blender: Dictionary = (mcp_page.get(&"_servers") as Array).filter(func(e: Dictionary) -> bool: return e.name == "blender")[0]
	var held_before_save: bool = mcp_page.call(&"needs_approval", blender)
	blender["_allow"] = true
	var blender_key: String = ExternalMcpServers.approval_key(ProjectSettings.globalize_path("res://"), blender)
	var user_settings: Object = dialog.get(&"_settings")
	var approved_before: Dictionary = (user_settings.call(&"get_value", "security/approved_commands", {}) as Dictionary).duplicate()
	dialog.call(&"_on_save")
	var approved_by_save: bool = user_settings.call(&"is_command_approved", blender_key)
	user_settings.call(&"set_value", "security/approved_commands", approved_before)
	var controller: Object = dock.get(&"_controller")
	var policy: Object = controller.get(&"policy")
	var saved_ok: bool = not dialog.visible and policy.call(&"matrix_value", "read", 0) == "deny" and FileAccess.file_exists(config_path)
	var mcp_ok: bool = policy.call(&"matrix_value", "mcp:blender", 3) == "allow" and policy.call(&"matrix_value", "mcp:blender", 2) == "ask"
	var names: PackedStringArray = controller.get(&"external_mcp_names")
	var saved_text := FileAccess.get_file_as_string(config_path)
	if had_config:
		var file := FileAccess.open(config_path, FileAccess.WRITE)
		file.store_string(config_before)
		file.close()
	else:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(config_path))
	policy.set(&"overrides", {})
	controller.set(&"external_mcp_names", PackedStringArray())
	if not saved_ok:
		_finish(1, "settings: guardar no aplicó la matriz (visible=%s, read/ask=%s)" % [dialog.visible, policy.call(&"matrix_value", "read", 0)])
		return
	if not held_before_save or not approved_by_save:
		_finish(1, "settings: el server importado no pidió aprobación o «Allow on this machine» no lo aprobó (held=%s, approved=%s)" % [held_before_save, approved_by_save])
		return
	if not mcp_ok or names != PackedStringArray(["blender"]) or not saved_text.contains("blender-mcp"):
		_finish(1, "settings: el server MCP no quedó guardado o permitido (oneshot=%s, nombres=%s)" % [mcp_ok, names])
		return
	_finish(0, "settings: %d secciones, guardar aplica la matriz y los servers MCP" % nav.item_count)


func _run_extensions_shots(prefix: String) -> void:
	get_tree().create_timer(SAFETY_TIMEOUT_S).timeout.connect(_on_safety_timeout)
	await get_tree().create_timer(2.0).timeout
	var dock := _find_dock()
	if dock == null:
		_finish(1, "no se encontró el dock")
		return
	var button: Button = null
	for child: Node in dock.get_node("Header").get_children():
		if child is Button and child.name == &"ExtensionsButton":
			button = child
	if button == null:
		_finish(1, "extensions: el header no tiene el botón")
		return
	button.pressed.emit()
	await get_tree().create_timer(0.5).timeout
	var window: Window = null
	for node: Node in EditorInterface.get_base_control().get_children():
		if node is AcceptDialog and node.has_method(&"refresh") and node.get(&"_mcp_box") != null:
			window = node
	if window == null or not window.visible:
		_finish(1, "extensions: el botón no abrió la ventana")
		return
	var deadline := Time.get_ticks_msec() + 150000
	while not (window.get(&"_loading") as Dictionary).is_empty() and Time.get_ticks_msec() < deadline:
		await get_tree().create_timer(0.5).timeout
	if not (window.get(&"_loading") as Dictionary).is_empty():
		_finish(1, "extensions: no terminó de cargar (%s)" % [window.get(&"_loading")])
		return
	var tabs: TabContainer = window.get(&"_tabs")
	for i in tabs.get_tab_count():
		tabs.current_tab = i
		await get_tree().create_timer(0.5).timeout
		window.get_texture().get_image().save_png("%s_%d.png" % [prefix, i])
	(window.get(&"_plugin_search") as LineEdit).text = "godot"
	(window.get(&"_plugin_search") as LineEdit).text_changed.emit("godot")
	tabs.current_tab = 0
	await get_tree().create_timer(0.5).timeout
	window.get_texture().get_image().save_png("%s_search.png" % prefix)
	var installed: Array = window.get(&"_installed")
	var available: Array = window.get(&"_available")
	var mcp: Array = window.get(&"_mcp")
	var errors := [window.get(&"_plugins_error"), window.get(&"_markets_error"), window.get(&"_mcp_error")].filter(func(text: String) -> bool: return not text.is_empty())
	window.hide()
	if not errors.is_empty():
		_finish(1, "extensions: errores %s" % [errors])
		return
	_finish(0, "extensions: %d instalados, %d disponibles, %d marketplaces, %d MCP servers" % [installed.size(), available.size(), (window.get(&"_markets") as Array).size(), mcp.size()])


func _run_docs_shots(dir: String) -> void:
	get_tree().create_timer(SAFETY_TIMEOUT_S).timeout.connect(_on_safety_timeout)
	await get_tree().create_timer(3.0).timeout
	var failures := _failures(await DocsShots.new().run(get_tree(), dir, hide_bottom_panel))
	for failure: String in failures:
		print("[docs-shots] FALLA ", failure)
	_finish(0 if failures.is_empty() else 1, "docs-shots: %d fallas" % failures.size())


func _run_ux_tour(dir: String) -> void:
	get_tree().create_timer(SAFETY_TIMEOUT_S * 4).timeout.connect(_on_safety_timeout)  # recorre toda la UI y la guía
	await get_tree().create_timer(3.0).timeout
	var failures := _failures(await UxTour.new().run(get_tree(), dir, hide_bottom_panel))
	for failure: String in failures:
		print("[ux-tour] FALLA ", failure)
	_finish(0 if failures.is_empty() else 1, "ux-tour: %d fallas" % failures.size())


func _run_sessions_test(prefix: String) -> void:
	get_tree().create_timer(SAFETY_TIMEOUT_S).timeout.connect(_on_safety_timeout)
	await get_tree().create_timer(2.0).timeout
	var dock := _find_dock()
	var main_plugin := _find_by_script(MAIN_PLUGIN_SCRIPT)
	if dock == null or main_plugin == null:
		_finish(1, "no se encontró el dock o el plugin")
		return
	var failures := await SessionsCheck.new().run(get_tree(), main_plugin, dock, prefix)
	_finish(0 if failures.is_empty() else 1, "sessions-test: %s" % ("ok" if failures.is_empty() else "; ".join(failures)))


func _run_skills_test(prefix: String) -> void:
	get_tree().create_timer(SAFETY_TIMEOUT_S).timeout.connect(_on_safety_timeout)
	await get_tree().create_timer(2.0).timeout
	var dock := _find_dock()
	if dock == null:
		_finish(1, "no se encontró el dock")
		return
	var failures := await SkillsCheck.new().run(get_tree(), dock, prefix)
	_finish(0 if failures.is_empty() else 1, "skills-test: %s" % ("ok" if failures.is_empty() else "; ".join(failures)))


## m12-49: en un editor sin agentes (tests/first_run_check.sh: self-contained, CLAUDE_CONFIG_DIR vacío,
## sin API key), «Agregar» en Claude Code arranca la sesión sola; npx baja el adaptador y, sin
## credenciales, la sesión termina en la tarjeta de login con su botón. Cuenta las interacciones del
## camino mínimo y guarda <prefijo>_01_sin_agentes.png, _02_conectando.png y _03_login.png.
func _run_first_run_test(prefix: String) -> void:
	get_tree().create_timer(FIRST_RUN_TIMEOUT_S).timeout.connect(_on_safety_timeout)
	await get_tree().create_timer(2.0).timeout
	var dock := _find_dock()
	if dock == null:
		_finish(1, "no se encontró el dock")
		return
	var model: Object = dock.get(&"_model")
	var controller: Object = dock.get(&"_controller")
	var settings: Object = dock.get(&"_settings")
	if not (settings.call(&"profiles") as Array).is_empty():
		_finish(1, "el check necesita un editor sin agentes: corré tests/first_run_check.sh")
		return
	var guide: Control = dock.get(&"_suggested_box")
	if guide == null or not guide.is_visible_in_tree():
		_finish(1, "no se ve la guía del primer arranque")
		return
	_save_dock_shot(dock, prefix + "_01_sin_agentes.png")
	var add := _find_button(guide, I18n.t("Add"))
	if add == null:
		_finish(1, "no hay botón «Add» en los sugeridos")
		return
	var started_at := Time.get_ticks_msec()
	add.pressed.emit()  # interacción 1 en el dock
	await get_tree().process_frame
	await get_tree().process_frame
	if (settings.call(&"profiles") as Array).is_empty():
		_finish(1, "«Add» no guardó el perfil de Claude Code")
		return
	if int(model.get(&"state")) != SessionModel.SessionState.STARTING:
		_finish(1, "«Add» no arrancó la sesión sola (estado %d)" % int(model.get(&"state")))
		return
	await get_tree().create_timer(0.5).timeout
	_save_dock_shot(dock, prefix + "_02_conectando.png")
	var deadline := Time.get_ticks_msec() + int((FIRST_RUN_TIMEOUT_S - 30.0) * 1000)
	while int(model.get(&"state")) == SessionModel.SessionState.STARTING and Time.get_ticks_msec() < deadline:
		await get_tree().create_timer(0.2).timeout
	var seconds := (Time.get_ticks_msec() - started_at) / 1000
	var state_line: Label = dock.get(&"_state_line")
	var connecting_line := state_line.text
	match int(model.get(&"state")):
		SessionModel.SessionState.LOGIN_REQUIRED:
			pass
		SessionModel.SessionState.READY:
			# claude-agent-acp abre la sesión sin credenciales y es el primer turno el que pide login:
			# un mensaje corto no gasta tokens porque el turno falla antes de llegar al modelo.
			if not str((model.get(&"account") as Dictionary).get("email", "")).is_empty():
				_finish(1, "abrió con una cuenta (%s): el entorno tiene credenciales" % (model.get(&"account") as Dictionary).get("email"))
				return
			dock.call(&"send_text", "hi")  # interacción 2 en el dock: el primer mensaje
			var prompt_deadline := Time.get_ticks_msec() + 90000
			while Time.get_ticks_msec() < prompt_deadline and not _has_login_notice(model):
				await get_tree().create_timer(0.2).timeout
			if not _has_login_notice(model):
				_finish(1, "el primer mensaje no pidió login en 90 s (estado %d): revisá que el entorno no tenga credenciales" % int(model.get(&"state")))
				return
		SessionModel.SessionState.FAILED:
			_finish(1, "la sesión falló (¿sin red para npx?): %s" % model.get(&"failure_message"))
			return
		_:
			_finish(1, "la sesión no llegó al login en %d s (estado %d)" % [seconds, int(model.get(&"state"))])
			return
	var login: Object = _login_notice(model)
	if login == null:
		_finish(1, "pidió login pero no hay tarjeta con el botón de iniciar sesión")
		return
	var primary: Array = (login.get(&"actions") as Array).filter(func(action: Dictionary) -> bool: return bool(action.get("primary", false)))
	if primary.is_empty() or _find_button(dock, str(primary[0].label)) == null:
		_finish(1, "la tarjeta de login no tiene el botón principal a la vista (%s)" % [login.get(&"actions")])
		return
	await get_tree().create_timer(0.5).timeout
	_save_dock_shot(dock, prefix + "_03_login.png")
	var at_prompt := int(model.get(&"state")) != SessionModel.SessionState.LOGIN_REQUIRED
	print("[first-run-check] «Add» arrancó la sesión sola (%d s hasta conectar; línea de estado: «%s»); el login lo pidió %s con «%s». Camino mínimo: activar el plugin, Add, %s«%s» (navegador), pegar el código%s: 5 interacciones (4 en el dock)." % [seconds, connecting_line, "el primer mensaje" if at_prompt else "la sesión al abrir", primary[0].label, "escribir el primer mensaje, " if at_prompt else "", primary[0].label, "" if at_prompt else ", escribir el primer mensaje"])
	controller.call(&"stop")
	await get_tree().process_frame
	_finish(0, "first-run-test: ok (%d s hasta conectar, login %s)" % [seconds, "en el primer mensaje" if at_prompt else "al abrir"])


func _has_login_notice(model: Object) -> bool:
	return _login_notice(model) != null


func _login_notice(model: Object) -> Object:
	var login: Object = null
	for entry: Object in model.call(&"entries"):
		if entry.get(&"kind") == 7 and (entry.get(&"actions") as Array).any(func(action: Dictionary) -> bool: return str(action.id) == "login"):  # NOTICE
			login = entry
	return login


func _run_asset_test(prefix: String) -> void:
	get_tree().create_timer(SAFETY_TIMEOUT_S).timeout.connect(_on_safety_timeout)
	await get_tree().create_timer(2.0).timeout
	var dock := _find_dock()
	if dock == null:
		_finish(1, "no se encontró el dock")
		return
	var failures := await AssetCheck.new().run(get_tree(), dock, prefix)
	_finish(0 if failures.is_empty() else 1, "asset-test: %s" % ("ok" if failures.is_empty() else "; ".join(failures)))


func _run_update_shots(prefix: String) -> void:
	get_tree().create_timer(SAFETY_TIMEOUT_S).timeout.connect(_on_safety_timeout)
	await get_tree().create_timer(2.0).timeout
	var dock := _find_dock()
	if dock == null:
		_finish(1, "no se encontró el dock")
		return
	var banner: Control = null
	for child: Node in dock.get_children():
		if child.has_method(&"show_release"):
			banner = child
	if banner == null:
		_finish(1, "update: el dock no tiene el aviso")
		return
	if banner.get_index() != (dock.get(&"_export_banner") as Control).get_index() + 1:
		_finish(1, "update: el aviso no está debajo del de export")
		return
	banner.call(&"show_release", {
		"version": "9.9.9",
		"notes": "## Added\n\n- **Updater**: the dock tells you when a new version is out.\n- Something else with `code`.\n\n## Fixed\n\n- A bug.",
		"html_url": "https://github.com/dannroda/godot-agent/releases/tag/v9.9.9",
		"zip_url": "",
	}, "0.1.3")
	await get_tree().create_timer(0.5).timeout
	var image := EditorInterface.get_base_control().get_viewport().get_texture().get_image()
	image.get_region(Rect2i(dock.get_global_rect())).save_png("%s_banner.png" % prefix)
	banner.get(&"_buttons").get_child(0).pressed.emit()
	await get_tree().create_timer(0.5).timeout
	var notes: Window = banner.get(&"_notes_dialog")
	if not notes.visible:
		_finish(1, "update: «What's new» no abrió las notas")
		return
	notes.get_texture().get_image().save_png("%s_notes.png" % prefix)
	notes.hide()
	(dock.get(&"_settings_button") as Button).pressed.emit()
	await get_tree().create_timer(0.5).timeout
	var dialog: Window = null
	for node: Node in EditorInterface.get_base_control().get_children():
		if node is ConfirmationDialog and node.has_method(&"matrix_overrides"):
			dialog = node
	var nav: ItemList = dialog.get(&"_nav")
	nav.select(5)
	nav.item_selected.emit(5)
	(dialog.get(&"_update_button") as Button).pressed.emit()
	await get_tree().create_timer(0.5).timeout
	var status := (dialog.get(&"_update_status") as Label).text
	dialog.get_texture().get_image().save_png("%s_settings.png" % prefix)
	dialog.hide()
	if not status.contains("git"):
		_finish(1, "update: «Check now» en el repo no dijo que es una copia de desarrollo: %s" % status)
		return
	banner.get(&"_buttons").get_child(1).pressed.emit()
	if banner.visible:
		_finish(1, "update: «Later» no ocultó el aviso")
		return
	var settings := EditorInterface.get_editor_settings()
	var dismissed := str(settings.get_setting("godot_agent/update/dismissed_version"))
	settings.set_setting("godot_agent/update/dismissed_version", "")
	if dismissed != "9.9.9":
		_finish(1, "update: «Later» no guardó la versión (%s)" % dismissed)
		return
	_finish(0, "update: aviso, notas, Settings (%s) y «Later»" % status)


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
	get_tree().create_timer(CYCLE_SAFETY_TIMEOUT_S).timeout.connect(_on_safety_timeout)
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
	var target := _arg_value(CYCLE_TARGET_ARG)
	if target.is_empty():
		target = TARGET_PLUGIN

	# Cada ciclo se mide con los objetos ya asentados: al habilitarse, el addon crea objetos que viven
	# hasta ~1,3 s (trabajo asíncrono), y medir a los pocos frames los contaba como fuga según el
	# timing (m16-12). Se compara contra un plugin vacío ciclado intercalado en la misma corrida, que se
	# lleva lo que el editor crece por su cuenta, por la mediana: un salto de caché aislado no la mueve
	# y una fuga de un objeto por ciclo sí.
	# Un ciclo de cada uno sin medir antes: el primero carga scripts y llena cachés.
	for plugin: String in [target, CYCLE_CONTROL]:
		var warm_error: String = await _cycle_plugin(plugin)
		if not warm_error.is_empty():
			_finish(1, "calentamiento: " + warm_error)
			return
	# La línea base de huérfanos se toma después de ese primer ciclo: el editor termina de restaurar su
	# estado (pestañas de scripts, escenas abiertas) en los primeros frames y crea nodos sueltos propios.
	var orphans_before: int = _orphans()
	var orphan_ids_before: Array = _orphan_ids()
	var rounds: PackedStringArray = []
	var target_growth: Array[int] = []
	var control_growth: Array[int] = []
	var last: int = await _settled_objects()
	if last < 0:
		_finish(1, "los objetos no se asientan en %d ms" % CYCLE_SETTLE_MAX_MS)
		return
	for i: int in CYCLE_ROUNDS:
		for plugin: String in [target, CYCLE_CONTROL]:
			var error: String = await _cycle_plugin(plugin)
			if not error.is_empty():
				_finish(1, "ronda %d: %s" % [i + 1, error])
				return
			var now: int = await _settled_objects()
			if now < 0:
				_finish(1, "ronda %d: los objetos no se asientan en %d ms después de ciclar %s" % [i + 1, CYCLE_SETTLE_MAX_MS, plugin])
				return
			(target_growth if plugin == target else control_growth).append(now - last)
			last = now
		# Se imprime al final: cada línea del Output del editor es un objeto que queda, y en medio de las
		# rondas sumaba uno a la medición siguiente.
		rounds.append("[cycle-test] round %d ok · objects=%d nodes=%d resources=%d orphan_nodes=%d" % [i + 1, last, int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)), int(Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT)), _orphans()])

	for line: String in rounds:
		print(line)
	var target_median := _median(target_growth)
	var control_median := _median(control_growth)
	print("[cycle-test] objetos por ciclo: %s %s (mediana %d) · plugin vacío %s (mediana %d)" % [target, target_growth, target_median, control_growth, control_median])
	var orphans_after: int = _orphans()
	var addon_orphans := _addon_orphans()
	var layout_problems: PackedStringArray = await _layout_problems()
	if not layout_problems.is_empty():
		_finish(1, "layout: %s" % "; ".join(layout_problems))
	elif not addon_orphans.is_empty():
		_finish(1, "nodos huérfanos del addon: %s" % ", ".join(addon_orphans))
	elif orphans_after > orphans_before:
		_print_new_orphans(orphan_ids_before)
		_finish(1, "quedaron %d nodos huérfanos nuevos" % (orphans_after - orphans_before))
	elif target_median - control_median >= CYCLE_LEAK_PER_CYCLE:
		_finish(1, "%s pierde objetos: %d por ciclo de mediana contra %d del plugin vacío (%d ciclos)" % [target, target_median, control_median, CYCLE_ROUNDS])
	else:
		_finish(0, "%d ciclos sin huérfanos ni fugas (objetos por ciclo: %d, plugin vacío: %d)" % [CYCLE_ROUNDS, target_median, control_median])


## Deshabilita y vuelve a habilitar `plugin`, o al revés si estaba deshabilitado: queda como estaba.
## "" si anduvo; si no, qué falló.
func _cycle_plugin(plugin: String) -> String:
	var was_enabled := EditorInterface.is_plugin_enabled(plugin)
	for enabled: bool in [not was_enabled, was_enabled]:
		EditorInterface.set_plugin_enabled(plugin, enabled)
		await _settle()
		if EditorInterface.is_plugin_enabled(plugin) != enabled:
			return "%s no se %s" % [plugin, "habilitó" if enabled else "deshabilitó"]
	return ""


## Los objetos vivos pasados CYCLE_MIN_WAIT_MS, cuando el conteo no cambia en CYCLE_STABLE_FRAMES
## frames; -1 si no se asienta en CYCLE_SETTLE_MAX_MS.
func _settled_objects() -> int:
	var deadline := Time.get_ticks_msec() + CYCLE_SETTLE_MAX_MS
	await get_tree().create_timer(CYCLE_MIN_WAIT_MS / 1000.0).timeout
	var last := _objects()
	var stable := 0
	while stable < CYCLE_STABLE_FRAMES:
		if Time.get_ticks_msec() > deadline:
			return -1
		await get_tree().process_frame
		var now := _objects()
		stable = stable + 1 if now == last else 0
		last = now
	return last


static func _median(values: Array[int]) -> int:
	var sorted := values.duplicate()
	sorted.sort()
	return sorted[sorted.size() / 2] if not sorted.is_empty() else 0


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


## Las fallas que devolvió un check. Si el check se cortó por un error de script, la corrutina
## devuelve null: antes eso se leía como "0 fallas" y la prueba pasaba sin haber corrido.
static func _failures(result: Variant) -> PackedStringArray:
	if result is PackedStringArray:
		return result
	return PackedStringArray(["el check se cortó por un error de script (ver el Output)"])


func _finish(code: int, message: String) -> void:
	print("[cycle-test] %s: %s" % ["PASS" if code == 0 else "FAIL", message])
	# Un git de los checkpoints en curso (el snapshot de un turno): salir con su Thread vivo aborta el
	# editor («Thread object is being destroyed…») y el check sale con 134 aunque haya pasado.
	var deadline := Time.get_ticks_msec() + 10000
	while GitCheckpoints.pending() > 0 and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	get_tree().quit(code)


## Los checks que mueven la sesión, el juego o el One-shot terminan por acá (m13-18): si el flujo
## dejó una transición fuera de tabla en el canal `state` del Agent Log del plugin (D61), el check
## falla aunque todo lo demás haya pasado. `tag` es el prefijo de las líneas FALLA de ese check.
func _finish_checking_state(code: int, message: String, tag: String) -> void:
	var lines := _state_channel_lines()
	for line: String in lines:
		print("[%s] FALLA canal state: %s" % [tag, line])
	if code == 0 and not lines.is_empty():
		_finish(1, "%s, %d en el canal state" % [message, lines.size()])
		return
	_finish(code, message)


func _state_channel_lines() -> PackedStringArray:
	var main_plugin := _find_by_script(MAIN_PLUGIN_SCRIPT)
	var log: Object = main_plugin.get(&"_log") if main_plugin else null
	if log == null:
		return PackedStringArray(["no se encontró el Agent Log del plugin"])
	var lines: PackedStringArray = []
	for entry: Dictionary in log.call(&"entries"):
		if entry.channel == AgentLog.CH_STATE:
			lines.append(str(entry.message))
	return lines
