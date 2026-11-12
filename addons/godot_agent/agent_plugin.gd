@tool
extends Node
## Raíz de composición del addon: crea los servicios y la UI, y los desarma al deshabilitar.
## Vive como hijo del EditorPlugin de plugin.gd, que no referencia nada por tipo para que habilitar
## el plugin no recompile todo esto (m16-15).

const AgentExportPlugin := preload("export/agent_export_plugin.gd")
const PlaytestAutoload := preload("playtest/playtest_autoload.gd")
const EditorSurfaces := preload("ui/editor_surfaces.gd")
const AgentProcess := preload("transport/agent_process.gd")
const EditorWindows := preload("ui/editor_windows.gd")
const AgentDockScene := preload("ui/dock/agent_dock.tscn")
const AgentMainScreenScene := preload("ui/main_screen/agent_main_screen.tscn")
const AgentLogPanelScene := preload("ui/log_panel/agent_log_panel.tscn")
const AgentLog := preload("core/agent_log.gd")
const HarnessSettings := preload("core/harness_settings.gd")
const AgentProfile := preload("core/agent_profile.gd")
const SettingsDialog := preload("ui/settings/settings_dialog.gd")
const ExtensionsWindow := preload("ui/extensions/extensions_window.gd")
const ClaudeExtensions := preload("extensions/claude_extensions.gd")
const AgentAdapters := preload("session/agents/agent_adapters.gd")
const AgentAdapter := preload("session/agents/agent_adapter.gd")
const I18n := preload("core/i18n.gd")
const SessionHistory := preload("session/session_history.gd")
const SessionModel := preload("session/session_model.gd")
const SessionController := preload("session/session_controller.gd")
const EditorContext := preload("ui/editor_context.gd")
const EditorSync := preload("editor/editor_sync.gd")
const AgentFollower := preload("editor/agent_follower.gd")
const RemoteActivity := preload("session/remote_activity.gd")
const FsHandler := preload("acp/fs_handler.gd")
const TerminalHandler := preload("acp/terminal_handler.gd")
const PermissionPolicy := preload("session/permission_policy.gd")
const ProjectConfig := preload("config/project_config.gd")
const ExternalMcpServers := preload("mcp/external_mcp_servers.gd")
const ChatEntry := preload("session/chat_entry.gd")
const ToolCall := preload("session/tool_call.gd")
const DiffDialog := preload("ui/diff_dialog.gd")
const TurnChangesDialog := preload("ui/turn_changes_dialog.gd")
const TurnChanges := preload("ui/turn_changes.gd")
const TurnCounter := preload("ui/turn_counter.gd")
const TurnSnapshots := preload("session/turn_snapshots.gd")
const InlineEdit := preload("editor/inline_edit.gd")
## Lo que trae @output: el final del panel Output.
const OUTPUT_MENTION_CHARS := 4000
const TurnReport := preload("session/turn_report.gd")
const WorktreeSession := preload("session/worktree_session.gd")
const GithubReviews := preload("core/github_reviews.gd")
const InlineEditMenu := preload("editor/inline_edit_menu.gd")
const AskAgentMenu := preload("editor/ask_agent_menu.gd")
const McpServer := preload("mcp/mcp_server.gd")
const ToolRegistry := preload("mcp/tool_registry.gd")
const ModeModels := preload("core/mode_models.gd")
const ProjectToolLoader := preload("mcp/project_tool_loader.gd")
const UntrustedText := preload("mcp/untrusted_text.gd")
const ReadTools := preload("mcp/tools/read_tools.gd")
const MapTools := preload("mcp/tools/map_tools.gd")
const DebugTools := preload("mcp/tools/debug_tools.gd")
const ApiTools := preload("mcp/tools/api_tools.gd")
const ProjectTools := preload("mcp/tools/project_tools.gd")
const AssetTools := preload("mcp/tools/asset_tools.gd")
const AssetStore := preload("core/asset_store.gd")
const FileTools := preload("mcp/tools/file_tools.gd")
const ResourceTools := preload("mcp/tools/resource_tools.gd")
const TilemapTools := preload("mcp/tools/tilemap_tools.gd")
const ValidateTools := preload("mcp/tools/validate_tools.gd")
const AnimationTools := preload("mcp/tools/animation_tools.gd")
const DiagnosticTools := preload("mcp/tools/diagnostic_tools.gd")
const SupervisorClient := preload("supervisor/supervisor_client.gd")
const NativeBuild := preload("core/native_build.gd")
const NativeInstall := preload("core/native_install.gd")
const SceneEditTools := preload("mcp/tools/scene_edit_tools.gd")
const RunTools := preload("mcp/tools/run_tools.gd")
const ProfileTools := preload("mcp/tools/profile_tools.gd")
const PlaytestRegressions := preload("review/playtest_regressions.gd")
const RegressionsWorkflow := preload("review/regressions_workflow.gd")
const PlaytestDebugger := preload("playtest/playtest_debugger.gd")
const EditorUndo := preload("editor/editor_undo.gd")
const StdioShimInstaller := preload("mcp/stdio_shim_installer.gd")
const ErrorCollector := preload("editor/error_collector.gd")
const RunErrorWatcher := preload("editor/run_error_watcher.gd")
const HookRunner := preload("editor/hook_runner.gd")
const ProjectHooks := preload("core/project_hooks.gd")
const MachineApproval := preload("core/machine_approval.gd")
const ReviewAnnotations := preload("review/review_annotations.gd")
const ReviewStore := preload("review/review_store.gd")
const HarnessPrompts := preload("session/harness_prompts.gd")
const AgentDock := preload("ui/dock/agent_dock.gd")
const OneShotRun := preload("oneshot/oneshot_run.gd")
const GameCriteria := preload("oneshot/game_criteria.gd")
const CompletionService := preload("completion/completion_service.gd")
const AddonUpdater := preload("core/addon_updater.gd")
const AddonVersion := preload("core/addon_version.gd")
const UpdateBanner := preload("ui/dock/update_banner.gd")
const SessionCoordinator := preload("session/session_coordinator.gd")
const SessionTabs := preload("ui/dock/session_tabs.gd")
const SessionTools := preload("mcp/tools/session_tools.gd")
const SecondOpinion := preload("session/second_opinion.gd")
const SecondOpinionTools := preload("mcp/tools/second_opinion_tools.gd")

const ACTION_CONFLICT_DIFF := "conflict_diff"
const ACTION_CONFLICT_USE_AGENT := "conflict_use_agent"
const ACTION_CONFLICT_KEEP_MINE := "conflict_keep_mine"
const ACTION_RELOAD_SCENE := "reload_scene"
const ACTION_UNDO_TOOL_CALL := "undo_tool_call"
const ACTION_ONESHOT_RESUME := "oneshot_resume"
const ACTION_ONESHOT_SHOW := "oneshot_show"
## Reiniciar el editor bajo el supervisor (m19-03) y copiar el comando para abrirlo así.
const ACTION_SUPERVISE := "supervise"
const ACTION_COPY_SUPERVISOR_COMMAND := "copy_supervisor_command"
## Lo que preparó install_extension y no entró (m19-05): reiniciar para instalarlo o descartarlo.
const ACTION_PENDING_INSTALL_RESTART := "pending_install_restart"
const ACTION_PENDING_INSTALL_DISCARD := "pending_install_discard"
## «Overwrite» del aviso cuando el workflow de regresiones ya existe (m16-10).
const ACTION_OVERWRITE_REGRESSIONS_WORKFLOW := "overwrite_regressions_workflow"
## «Arreglar con el agente» del aviso de un run manual con error (m11-55): el payload es el prompt.
const ACTION_FIX_RUN_ERROR := "fix_run_error"
const ACTION_CANCEL_MUTATION := "cancel_mutation"
const ACTION_OPEN_MUTANT := "open_mutant"
const MutationTesting := preload("playtest/mutation/mutation_testing.gd")
## «Send to the agent» del aviso de un hook de prompt (m11-24); `data` es el prompt.
const ACTION_SEND_HOOK_PROMPT := "send_hook_prompt"
## El panel Stack Trace del debugger se llena un momento después de la pausa.
const BREAK_READ_DELAY_S := 0.5
## Avisos de RegressionsWorkflow.write() para el usuario.
const REGRESSIONS_WORKFLOW_WARNINGS: Dictionary = {
	RegressionsWorkflow.WARN_NO_GIT: "The project is not in a git repository: the workflow was written in the project folder. GitHub only reads .github/workflows/ at the root of the repository, so move it there (and adjust --path if the project is in a subfolder).",  # i18n
	RegressionsWorkflow.WARN_IGNORED_REGRESSIONS: ".godot_agent/ is ignored by git: the saved regressions won't be in the repository, so the CI will find none. Un-ignore .godot_agent/playtests/regressions/ or commit it with git add -f.",  # i18n
	RegressionsWorkflow.WARN_IGNORED_ADDON: "addons/godot_agent/ is ignored by git: the CI needs the addon to run the regressions. Commit it or install it in the workflow.",  # i18n
	RegressionsWorkflow.WARN_CUSTOM_BUILD: "This editor is not an official Godot release, so the download URL in the workflow probably does not exist: point the Install Godot step to a build you host, or to the official release closest to this version.",  # i18n
}
## Acciones de edición del server MCP que todavía no se unieron a su tool call (llegan antes).
const PENDING_UNDO_TTL_MS := 60000
## Kinds de tool call que escriben archivos: al completarse se sincroniza el editor.
const WRITING_KINDS: PackedStringArray = ["edit", "delete", "move"]

const PLUGIN_NAME := "One-shot"
const DOCK_TITLE := "Agent"
const LOG_PANEL_TITLE := "Agent Log"
## Runs del One-shot (D37): datos del usuario, fuera del repo.
const ONESHOT_STORE_DIR := "user://godot_agent/oneshot"
const UPDATE_BACKUP_DIR := "user://godot_agent/update/backup-%s"
const UPDATE_CHECK_INTERVAL_S := 86400
const ICON_NAME := &"Script"
## Id de la primera sesión (m7-44); el token principal del server MCP es el suyo.
const PRIMARY_SESSION := "s1"
## Cuánto espera una tool que escribe a que el editor termine de importar (m14-02).
const IMPORT_WAIT_S := 8

## La medición de regresiones con mutantes en curso (m11-41), o null.
var _mutation: MutationTesting = null
var _export_plugin: AgentExportPlugin
var _surfaces: EditorSurfaces
var _settings: HarnessSettings
var _log: AgentLog
var _log_panel: Control
var _model: SessionModel
var _controller: SessionController
## Breakpoints, pila y pasos del debugger (m11-56).
var _debug_tools: DebugTools
## godot.project_map: su worker se espera en _exit_tree.
var _map_tools: MapTools
var _project_config: ProjectConfig
var _sync: EditorSync
## Seguir al agente (m11-33): salta a lo que edita la pestaña activa, si tiene el botón prendido.
var _follower: AgentFollower
var _remote_activity: RemoteActivity
## Hooks del proyecto en eventos del editor (m11-24).
var _hooks: HookRunner
## Prompts de hooks mandados solos (auto_send) desde el último mensaje del usuario.
var _hook_prompts_in_row: int = 0
var _diff_dialog: DiffDialog
var _turn_dialog: TurnChangesDialog
var _turn_changes: TurnChanges
## El contador vivo de cambios del turno arriba del composer (m11-34).
var _turn_counter: TurnCounter
## Snapshots por turno de todas las sesiones (m11-01); `available` queda en false sin git.
var _turn_snapshots: TurnSnapshots
var _mcp_server: McpServer
var _errors: ErrorCollector
## Errores de un run manual del juego → aviso con «Arreglar con el agente» (m11-55).
var _run_errors: RunErrorWatcher
var _diagnostics: DiagnosticTools
var _playtest_debugger: PlaytestDebugger
var _run_tools: RunTools
var _profile_tools: ProfileTools
var _pending_undo: Array[Dictionary] = []  # {tool, args, info, time}
var _review_annotations: ReviewAnnotations
var _oneshot: OneShotRun
## La pestaña de sesión del run (m17-19): el One-shot corre en la suya, no en la primera.
var _oneshot_tab_id: String = ""
var _settings_dialog: SettingsDialog
var _extensions_window: ExtensionsWindow
var _main_screen: Control
var _fs: FsHandler
var _registry: ToolRegistry
## El oráculo de la segunda opinión (m11-28): sin pestaña, se arma con la primera pregunta.
var _second_opinion: SecondOpinion
## Las tools propias del proyecto (m11-46) y las claves de las frenadas que ya se avisaron.
var _project_tools: ProjectToolLoader
var _tools_announced: Dictionary = {}
var _completion: CompletionService
## Chat en línea en el Script Editor (m11-05).
var _inline_edit: InlineEdit
var _inline_menu: InlineEditMenu
## «Preguntar al agente» en los menús contextuales (m11-54), uno por slot.
var _ask_menus: Array[EditorContextMenuPlugin] = []
var _updater: AddonUpdater
var _store: AssetStore
var _update_banner: UpdateBanner
## Varias sesiones a la vez (m7-44). La primera es `_model`/`_controller` (PRIMARY_SESSION), la del One-shot,
## la revisión y Remote Control; las otras: id -> {model, controller}.
var _coordinator: SessionCoordinator
var _tabs: SessionTabs
var _extra_sessions: Dictionary = {}
var _session_serial: int = 1
## El EditorPlugin de plugin.gd: docks, export/debugger/context menu y sus señales van por él.
var _plugin: EditorPlugin


func _init(plugin: EditorPlugin) -> void:
	_plugin = plugin


func _enter_tree() -> void:
	PlaytestAutoload.remove_orphan(_plugin)
	# Las extensiones ya cargaron (Godot las carga antes que los plugins): el arranque fue bueno.
	SupervisorClient.mark_ready()
	if SupervisorClient.is_supervised():
		SupervisorClient.install_restart_guard(get_tree())

	_export_plugin = AgentExportPlugin.new()
	_export_plugin.setup(_remove_playtest_autoload)
	_export_plugin.on_export_begin = func(path: String) -> void:
		if _hooks:
			_hooks.fire({"event": ProjectHooks.EVENT_EXPORT, "path": path, "by": ProjectHooks.BY_USER})
	_plugin.add_export_plugin(_export_plugin)

	_settings = HarnessSettings.new(EditorInterface.get_editor_settings())
	I18n.setup(_settings.language(), _editor_language())
	_log = AgentLog.new()
	for removed: String in _settings.retire_old_presets():
		_log.add(AgentLog.CH_ACP, "removed the old %s agent preset: it was never set up" % removed)
	_model = SessionModel.new()
	_project_config = ProjectConfig.load_or_default()
	_coordinator = SessionCoordinator.new()
	_sync = EditorSync.new()
	_sync.setup(_log)
	_sync.conflict_detected.connect(_on_conflict_detected)
	_sync.open_scene_modified.connect(_on_open_scene_modified)
	add_child(_sync)
	_plugin.scene_saved.connect(_sync.note_scene_saved)
	_follower = AgentFollower.new()
	_follower.dock = func() -> Control: return _tabs
	add_child(_follower)
	_turn_snapshots = TurnSnapshots.new(EditorContext.project_path())
	_turn_snapshots.setup()
	_controller = _make_controller(_model, PRIMARY_SESSION)
	_fs = _controller.fs
	_coordinator.register(PRIMARY_SESSION, I18n.t("Session 1"))
	EditorInterface.get_editor_settings().settings_changed.connect(_on_editor_settings_changed)

	_remote_activity = RemoteActivity.new()
	_remote_activity.setup(_model, _log, EditorContext.project_path())
	_remote_activity.after_restore = _sync.after_agent_write
	add_child(_remote_activity)
	_plugin.scene_saved.connect(_remote_activity.note_saved)
	_hooks = HookRunner.new()
	_hooks.name = "ProjectHooks"
	_hooks.provider = func() -> Dictionary:
		return {"hooks": _project_config.hooks if _project_config else [], "godot": OS.get_executable_path(), "project": ProjectSettings.globalize_path("res://")}
	_hooks.is_approved = _settings.is_command_approved
	_hooks.held = _on_hook_held
	_hooks.failed = _on_hook_failed
	_hooks.run_action = _run_hook_action
	_hooks.log_line = func(text: String) -> void:
		if _log:
			_log.add(AgentLog.CH_PROC, text)
	add_child(_hooks)
	_plugin.scene_saved.connect(_on_saved_for_hooks)
	_plugin.resource_saved.connect(func(resource: Resource) -> void: _on_saved_for_hooks(resource.resource_path))
	_plugin.resource_saved.connect(func(resource: Resource) -> void:
		if _remote_activity:
			_remote_activity.note_saved(resource.resource_path))
	_diff_dialog = DiffDialog.new()
	_diff_dialog.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	EditorInterface.get_base_control().add_child(_diff_dialog)
	_turn_dialog = TurnChangesDialog.new()
	_turn_dialog.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	EditorInterface.get_base_control().add_child(_turn_dialog)
	_turn_changes = TurnChanges.new()
	_turn_changes.project_snapshots = _turn_snapshots
	_turn_changes.primary_session = PRIMARY_SESSION
	_turn_changes.diff_dialog = _diff_dialog
	_turn_changes.dialog = _turn_dialog
	_turn_changes.controller_of = _controller_of
	_turn_changes.model_of = _model_of
	_turn_changes.after_restore = _after_oneshot_restore
	_turn_dialog.diff_requested.connect(_turn_changes.show_diff)
	_turn_dialog.revert_requested.connect(func(data: Dictionary, path: String) -> void: _turn_changes.restore(data, PackedStringArray([path])))
	_turn_dialog.hunks_requested.connect(_turn_changes.show_hunks)
	_turn_dialog.hunk_action.connect(_turn_changes.on_hunk_action)
	_turn_dialog.reject_file_requested.connect(_turn_changes.on_reject_file)
	_turn_counter = TurnCounter.new()
	_turn_counter.snapshots_of = _turn_changes._snapshots_of
	_turn_counter.model_of = _model_of
	_turn_counter.dock_of = func(id: String) -> Object: return _tabs.dock(id) if _tabs else null
	_turn_counter.open_dialog = _turn_dialog.show_turn
	add_child(_turn_counter)
	# m11-34: un archivo con cambios sin guardar o que otra sesión edita no se toca por trozo.
	_turn_changes.unsaved_of = func(res_path: String) -> bool:
		return (_sync and _sync.buffer_text(ProjectSettings.globalize_path(res_path)) != null) or res_path in EditorInterface.get_unsaved_scenes()
	_turn_changes.holder_of = func(session: String, res_path: String) -> String:
		return _coordinator.holder_label(session, res_path) if _coordinator else ""
	_playtest_debugger = PlaytestDebugger.new()
	# El juego ya leyó project.godot cuando su sesión de debug arranca: el autoload se quita ahí.
	_playtest_debugger.session_started.connect(_remove_playtest_autoload)
	_playtest_debugger.session_stopped.connect(_remove_playtest_autoload)
	_plugin.add_debugger_plugin(_playtest_debugger)
	_start_mcp_server()

	_review_annotations = ReviewAnnotations.new()
	_review_annotations.setup(_controller.review, _model, _settings.accent_color())
	_review_annotations.action_requested.connect(_on_review_action)
	add_child(_review_annotations)

	_oneshot = OneShotRun.new()
	_oneshot.setup(_controller, EditorContext.project_path())
	_oneshot.after_restore = _after_oneshot_restore
	_oneshot.restart_session = func(lost_id: String) -> bool:
		# El agente con el que corría el run, o el elegido en su pestaña.
		var controller := _oneshot.controller
		var profile := controller.profile() if controller.profile() else _tab_profile(_session_id_of(controller))
		return profile != null and await controller.reopen(profile, lost_id)
	_oneshot.prepare_session = _prepare_oneshot_tab
	_oneshot.resume_auto = _settings.quota_resume_auto()
	_oneshot.store.dir = ONESHOT_STORE_DIR
	_oneshot.loops.repeats = _project_config.loop_repeats
	_oneshot.qa_max_rounds = _project_config.qa_rounds
	_oneshot.criteria = GameCriteria.resolve(_project_config.criteria)
	add_child(_oneshot)
	_model.harness_mode_changed.connect(_on_harness_mode_changed)

	var dock := AgentDockScene.instantiate()
	dock.setup(_model, _controller, _settings)
	dock.show_log_requested.connect(_show_log)
	dock.settings_requested.connect(_open_settings)
	dock.new_tab_requested.connect(_open_session_tab)
	dock.registry_requested.connect(func(query: String) -> void:
		var settings := _get_settings_dialog()
		settings.open()
		settings.open_registry(query))
	dock.extensions_requested.connect(func() -> void: _open_extensions())
	dock.tools_requested.connect(func() -> void: _open_extensions(ExtensionsWindow.ExtensionsTab.TOOLS))
	dock.action_forwarded.connect(_on_dock_action)
	dock.game_capture = _capture_game_for_dock
	dock.game_point = _point_game_for_dock
	dock.context_provider = _context_for_mention
	_wire_oneshot(dock, PRIMARY_SESSION)
	_wire_elsewhere(dock, PRIMARY_SESSION)
	var log_panel := AgentLogPanelScene.instantiate()
	_log_panel = log_panel
	log_panel.setup(_log)
	_tabs = SessionTabs.new()
	_tabs.name = dock.name  # con la API vieja de docks, el título de la pestaña es el nombre del nodo
	_tabs.add_session(PRIMARY_SESSION, dock, _model, I18n.t("Session 1"))
	_tabs.notify_outside_enabled = _settings.notify_when_unfocused
	_tabs.new_session_requested.connect(_open_session_tab)
	_tabs.active_changed.connect(func(_id: String) -> void: _follower.cancel())
	dock.follow_toggled.connect(_on_follow_toggled)
	dock.turn_changes_requested.connect(func() -> void:
		if _turn_counter:
			_turn_counter.open(_session_of_dock(dock)))
	_tabs.close_requested.connect(_close_session_tab)
	_tabs.rename_requested.connect(_rename_session)
	# Los textos ya vienen traducidos por I18n: que el editor no los vuelva a traducir con los suyos.
	for surface: Node in [_tabs, log_panel]:
		surface.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED

	_surfaces = EditorSurfaces.new(_plugin)
	_surfaces.side_slot = HarnessSettings.DOCK_SLOTS[_settings.dock_slot()]
	_surfaces.add(EditorSurfaces.EditorSurface.SIDE, _tabs, DOCK_TITLE, "godot_agent_dock")
	_surfaces.add(EditorSurfaces.EditorSurface.BOTTOM, log_panel, LOG_PANEL_TITLE, "godot_agent_log")
	_main_screen = AgentMainScreenScene.instantiate()
	_main_screen.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_main_screen.setup(_oneshot, _settings.accent_color(), _oneshot_defaults())
	_main_screen.diff_requested.connect(_diff_dialog.show_diff)
	_main_screen.settings_requested.connect(_open_settings)
	_main_screen.agent_name = func() -> String:
		# El del run en curso; si no, el de la pestaña activa, que es el que va a usar el próximo run.
		var controller := _oneshot.controller if _oneshot else null
		var profile := controller.profile() if controller and _oneshot.is_active() and controller.profile() else _tab_profile()
		return profile.display_name if profile else ""
	_settings.changed.connect(func(key: String) -> void:
		if _main_screen and key in [HarnessSettings.KEY_PROFILES, HarnessSettings.KEY_LAST_PROFILE]:
			_main_screen.refresh_agent())
	_surfaces.add(EditorSurfaces.EditorSurface.MAIN_SCREEN, _main_screen, PLUGIN_NAME, "godot_agent_main", plugin_icon())
	_restore_oneshot.call_deferred()
	_report_supervisor_events.call_deferred(dock)

	_updater = AddonUpdater.new()
	add_child(_updater)
	_update_banner = UpdateBanner.new()
	_update_banner.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_update_banner.update_requested.connect(_on_update_requested)
	_update_banner.dismissed.connect(func() -> void:
		_settings.set_value(HarnessSettings.KEY_UPDATE_DISMISSED, str(_update_banner.release().get("version", ""))))
	dock.add_banner(_update_banner)
	if _settings.update_check_on_start() and Time.get_unix_time_from_system() - int(_settings.get_value(HarnessSettings.KEY_UPDATE_LAST_CHECK, 0)) >= UPDATE_CHECK_INTERVAL_S:
		_check_updates.call_deferred(false)

	_completion = CompletionService.new()
	_completion.setup(_settings, _project_config, _log)
	add_child(_completion)
	_inline_edit = InlineEdit.new()
	_inline_edit.ask = _ask_inline
	_inline_edit.cancel = func() -> void:
		var controller := _controller_of(_active_session_id())
		if controller:
			controller.cancel()
	_inline_edit.start_session = _start_inline_session
	_inline_edit.agent_name = func() -> String:
		var controller := _controller_of(_active_session_id())
		return controller.profile().display_name if controller and controller.profile() else ""
	add_child(_inline_edit)
	_inline_menu = InlineEditMenu.new()
	_inline_menu.inline_edit = _inline_edit
	_plugin.add_context_menu_plugin(EditorContextMenuPlugin.CONTEXT_SLOT_SCRIPT_EDITOR_CODE, _inline_menu)
	for slot in [EditorContextMenuPlugin.CONTEXT_SLOT_FILESYSTEM, EditorContextMenuPlugin.CONTEXT_SLOT_SCENE_TREE, EditorContextMenuPlugin.CONTEXT_SLOT_SCRIPT_EDITOR_CODE]:
		var menu := AskAgentMenu.new(slot)
		menu.ask = _ask_agent
		_plugin.add_context_menu_plugin(slot, menu)
		_ask_menus.append(menu)


func _exit_tree() -> void:
	SupervisorClient.mark_closed()
	# Antes de liberar dock, main screen y diálogos: el ProgressDialog del editor puede estar adentro (m16-08).
	EditorWindows.rescue_progress(EditorInterface.get_base_control())
	if EditorInterface.get_editor_settings().settings_changed.is_connected(_on_editor_settings_changed):
		EditorInterface.get_editor_settings().settings_changed.disconnect(_on_editor_settings_changed)
	if _completion:
		remove_child(_completion)
		_completion.queue_free()
		_completion = null
	if _inline_menu:
		_plugin.remove_context_menu_plugin(_inline_menu)
		_inline_menu = null
	for menu in _ask_menus:
		_plugin.remove_context_menu_plugin(menu)
	_ask_menus.clear()
	if _inline_edit:
		remove_child(_inline_edit)
		_inline_edit.queue_free()
		_inline_edit = null
	if _updater:
		remove_child(_updater)
		_updater.queue_free()
		_updater = null
	if _store:
		remove_child(_store)
		_store.queue_free()
		_store = null
	_update_banner = null
	if _oneshot:
		_oneshot.suspend()  # queda guardado para retomarlo al volver (D37)
		remove_child(_oneshot)
		_oneshot.queue_free()
		_oneshot = null
	for id: String in _extra_sessions.keys():
		_close_session_tab(id, false)
	_tabs = null
	if _second_opinion:
		_second_opinion.controller.stop()  # su proceso; AgentProcess.stop_all cubre lo que quede
		if _second_opinion.controller.history:
			_second_opinion.controller.history.flush()
		_second_opinion = null
	if _controller:
		_controller.stop()
		if _controller.history:
			_controller.history.flush()  # la última escritura del historial va en un worker
		_controller = null
	if _mcp_server:
		_log.remove_secret(_mcp_server.token)
		_mcp_server.stop()
		_mcp_server.queue_free()
		_mcp_server = null
	if _errors:
		_errors.stop()
		_errors = null
	if _remote_activity:
		_remote_activity.queue_free()
		_remote_activity = null
	if _sync:
		_sync.queue_free()
		_sync = null
	if _follower:
		_follower.queue_free()
		_follower = null
	if _turn_counter:
		_turn_counter.queue_free()
		_turn_counter = null
	if _review_annotations:
		remove_child(_review_annotations)
		_review_annotations.queue_free()
		_review_annotations = null
	if _diff_dialog:
		_diff_dialog.queue_free()
		_diff_dialog = null
	if _turn_dialog:
		_turn_dialog.queue_free()
		_turn_dialog = null
	_turn_snapshots = null
	_turn_changes = null
	if _settings_dialog:
		_settings_dialog.queue_free()
		_settings_dialog = null
	if _extensions_window:
		_extensions_window.queue_free()
		_extensions_window = null
	_main_screen = null
	_fs = null
	# El índice del mapa se arma en un worker: cortarlo y esperarlo antes de que se descargue el addon.
	if _map_tools:
		_map_tools.wait()
		_map_tools = null
	_registry = null
	_project_tools = null
	var filesystem := EditorInterface.get_resource_filesystem()
	if filesystem and filesystem.filesystem_changed.is_connected(_on_project_tools_changed):
		filesystem.filesystem_changed.disconnect(_on_project_tools_changed)
	_diagnostics = null
	if _profile_tools:
		_profile_tools.shutdown()
		_profile_tools = null
	var debugger_node := _editor_debugger_node()
	if debugger_node and debugger_node.is_connected(&"breakpoint_toggled", _on_editor_breakpoint_toggled):
		debugger_node.disconnect(&"breakpoint_toggled", _on_editor_breakpoint_toggled)
	_debug_tools = null
	if _playtest_debugger:
		_plugin.remove_debugger_plugin(_playtest_debugger)
		_playtest_debugger = null
	_run_tools = null
	_run_errors = null
	PlaytestAutoload.unregister(_plugin)

	if _export_plugin:
		_plugin.remove_export_plugin(_export_plugin)
		_export_plugin = null

	if _surfaces:
		_surfaces.remove_all()
		_surfaces = null
	# Lo que siga vivo de cualquier dueño (una terminal, un hook, un build, un objeto que se libera
	# recién en el cierre): sin esto quedaban huérfanos el agente y sus hijos (npx → node).
	AgentProcess.stop_all()


## El EditorDebuggerNode del editor (clase interna, sin API): emite breakpoint_toggled(path, line, enabled)
## cuando el usuario prende o apaga una línea del margen, después de mandarla a los juegos.
static func _editor_debugger_node() -> Node:
	var found := EditorInterface.get_base_control().find_children("*", "EditorDebuggerNode", true, false)
	return found[0] if not found.is_empty() and found[0].has_signal(&"breakpoint_toggled") else null


func _on_editor_breakpoint_toggled(path: String, line: int, enabled: bool) -> void:
	if _debug_tools:
		_debug_tools.on_user_breakpoint_toggled(path, line, enabled)


func _on_game_breaked() -> void:
	await get_tree().create_timer(BREAK_READ_DELAY_S).timeout
	if _run_errors:
		_run_errors.on_game_breaked()


## Un run manual paró con un error (m11-55): aviso en la pestaña activa con el error, la pila plegada
## y «Arreglar con el agente». Nada se manda hasta que el usuario lo aprieta.
## Un guardado del editor (m11-24): es del agente si una tool suya está corriendo.
func _on_saved_for_hooks(res_path: String) -> void:
	if _hooks and res_path.begins_with("res://"):
		var by := ProjectHooks.BY_AGENT if _registry and _registry.running_calls > 0 else ProjectHooks.BY_USER
		_hooks.fire({"event": ProjectHooks.EVENT_SAVED, "path": res_path, "by": by})


## Lo que escriben las file tools y fs/write del agente: el editor lo relee, y para los hooks es un
## guardado del agente.
func _after_agent_write(abs_path: String, old_text: String = "", new_text: String = "") -> void:
	if _sync:
		_sync.after_agent_write(abs_path, old_text, new_text)
	var res_path := EditorContext.to_res_path(abs_path)
	if _hooks and not res_path.is_empty() and res_path.get_extension() in ["tscn", "scn", "gd", "cs", "gdshader", "tres", "res"]:
		_hooks.fire({"event": ProjectHooks.EVENT_SAVED, "path": res_path, "by": ProjectHooks.BY_AGENT})


## Un hook del proyecto sin aprobar en esta máquina (m11-24): aviso en la pestaña activa con «Aprobar…».
func _on_hook_held(hook: Dictionary, key: String) -> void:
	var model := _model_of(_active_session_id())
	if model == null:
		return
	var item := {"name": str(hook.name), "command": "%s → %s: %s" % [hook.event, hook.action, ProjectHooks.describe_action(hook)], "key": key}
	model.add_notice(I18n.t("Project hook «%s» is not approved on this machine, so it didn't run. It comes with the project's settings and runs on its own when its event happens.") % hook.name,
		ChatEntry.NoticeLevel.WARNING, [{"id": SessionController.ACTION_APPROVE_ON_MACHINE, "label": I18n.t("Approve «%s»…") % hook.name,
			"data": MachineApproval.request(MachineApproval.KIND_HOOK, [item]), "tooltip": I18n.t("See what the hook runs and allow it on this machine.")}])


## Las acciones de un hook que no son un comando (m11-24): `{ok, output}` para el log.
func _run_hook_action(hook: Dictionary, event: Dictionary) -> Dictionary:
	match str(hook.action):
		ProjectHooks.ACTION_TOOL:
			var args: Dictionary = hook.args
			var group := _registry.tool_group(str(hook.tool), args) if _registry else ""
			if group.is_empty():
				return {"ok": false, "output": "There is no tool godot.%s." % hook.tool}
			if not group in ProjectHooks.TOOL_GROUPS:
				return {"ok": false, "output": "godot.%s is in the «%s» group: a hook only runs tools that read, check or run the game (%s)." % [hook.tool, group, ", ".join(ProjectHooks.TOOL_GROUPS)]}
			var text: String = await _registry.run_for_user(str(hook.tool), args)
			return {"ok": true, "output": text}
		ProjectHooks.ACTION_PROMPT:
			return _hook_prompt(hook, event)
	return {"ok": false, "output": "Unknown action."}


## Un hook de prompt: por defecto, un aviso con «Send to the agent»; con auto_send, se manda solo hasta
## MAX_AUTO_PROMPTS seguidos sin un mensaje del usuario. Nunca en One-shot.
func _hook_prompt(hook: Dictionary, event: Dictionary) -> Dictionary:
	var dock := _tabs.dock(_tabs.active_id()) as AgentDock if _tabs else null
	var model := _model_of(_tabs.active_id()) if _tabs else null
	if dock == null or model == null:
		return {"ok": false, "output": "No session tab."}
	if model.harness_mode == SessionModel.HarnessMode.ONESHOT:
		return {"ok": false, "output": "Not sent: the active tab is in One-shot."}
	var text := ProjectHooks.prompt_text(hook, event)
	if bool(hook.auto_send) and _hook_prompts_in_row < ProjectHooks.MAX_AUTO_PROMPTS:
		_hook_prompts_in_row += 1
		dock.send_text(text, HarnessPrompts.HOOK)
		return {"ok": true, "output": "Sent to the agent."}
	var capped := bool(hook.auto_send)
	var body := str(hook.prompt) + ("\n" + str(event.path) if not str(event.get("path", "")).is_empty() else "")
	if capped:
		body += "\n\n" + I18n.t("Not sent on its own: hooks already sent %d prompts in a row without a message from you.") % ProjectHooks.MAX_AUTO_PROMPTS
	var entry := model.add_notice(body, ChatEntry.NoticeLevel.INFO, [{"id": ACTION_SEND_HOOK_PROMPT, "label": I18n.t("Send to the agent"), "primary": true, "data": text}])
	entry.title = I18n.t("Project hook «%s»") % hook.name
	model.notify_entry_changed(entry)
	return {"ok": true, "output": "Notice with «Send to the agent»%s." % (" (auto_send capped)" if capped else "")}


func _on_hook_failed(hook: Dictionary, _result: Dictionary) -> void:
	EditorInterface.get_editor_toaster().push_toast(I18n.t("Project hook «%s» failed. Its output is in the Agent Log.") % hook.name, EditorToaster.SEVERITY_WARNING)


func _on_run_error(info: Dictionary) -> void:
	var model := _model_of(_tabs.active_id()) if _tabs else _model
	if model == null:
		return
	var actions: Array[Dictionary] = [{"id": ACTION_FIX_RUN_ERROR, "label": I18n.t("Fix with the agent"), "primary": true, "data": RunErrorWatcher.prompt(info)}]
	var entry := model.add_notice(RunErrorWatcher.notice_text(info), ChatEntry.NoticeLevel.WARNING, actions)
	entry.title = RunErrorWatcher.notice_title(info)
	entry.details = RunErrorWatcher.notice_details(info)
	entry.details_title = I18n.t("Errors and stack")
	model.notify_entry_changed(entry)


## «+ contexto → Señalar en el juego…» (m11-37): el nodo bajo el punto `uv` de la captura, por el probe.
func _point_game_for_dock(uv: Vector2) -> Dictionary:
	if not EditorInterface.is_playing_scene():
		return {"error": I18n.t("No game is running.")}
	if _run_tools == null or not _playtest_debugger.has_probe():
		return {"error": I18n.t("This run has no playtest autoload, so it cannot be captured. Run it from the agent, or enable «Use the playtest autoload also when running the game manually» in Settings → MCP servers → Advanced.")}
	if _playtest_debugger.any_breaked():
		return {"error": I18n.t("The game is stopped in the debugger: continue it first.")}
	return await _run_tools.point_at(uv)


## «+ contexto → Captura del juego»: el frame como Image, o el motivo (traducido) si no se puede.
func _capture_game_for_dock() -> Variant:
	if not EditorInterface.is_playing_scene():
		return I18n.t("No game is running.")
	if _run_tools == null or not _playtest_debugger.has_probe():
		return I18n.t("This run has no playtest autoload, so it cannot be captured. Run it from the agent, or enable «Use the playtest autoload also when running the game manually» in Settings → MCP servers → Advanced.")
	var frame: Variant = await _run_tools.capture_frame()
	return frame if frame is Image else I18n.t("Could not capture the game frame.")


## Justo antes de correr el juego: alta del autoload de playtest si el run lo pidió el harness
## (run_scene) o si Settings lo activa también para los runs manuales (spec §6).
func build() -> bool:
	var requested := _run_tools != null and _run_tools.harness_requested
	if requested or (_project_config and _project_config.playtest_on_manual_runs):
		PlaytestAutoload.register(_plugin)
	return true


## Solo con la API vieja (4.7). En 4.8+ la main screen es un EditorDock (ver EditorSurfaces).
static func has_main_screen() -> bool:
	return not EditorSurfaces.uses_dock_api(EditorSurfaces.EditorSurface.MAIN_SCREEN)


func make_visible(visible: bool) -> void:
	if _surfaces:
		_surfaces.set_legacy_main_screen_visible(visible)


## El idioma de la interfaz del editor. Desde 4.7 el setting está en `localization/`.
static func _editor_language() -> String:
	var settings := EditorInterface.get_editor_settings()
	for key: String in ["interface/editor/localization/editor_language", "interface/editor/editor_language"]:
		if settings.has_setting(key):
			return str(settings.get_setting(key))
	return ""


static func plugin_name() -> String:
	return PLUGIN_NAME


static func plugin_icon() -> Texture2D:
	return EditorInterface.get_editor_theme().get_icon(ICON_NAME, &"EditorIcons")


func _show_log(seq: int = 0) -> void:
	if _surfaces:
		_surfaces.make_visible(EditorSurfaces.EditorSurface.BOTTOM)
	if seq > 0 and is_instance_valid(_log_panel):
		_log_panel.focus_entry.call_deferred(seq)


## Seguir al agente (m11-33): solo la pestaña activa, y solo si ese dock tiene el botón prendido.
func _follow_call(call: ToolCall, model: SessionModel) -> void:
	if _follower == null or _tabs == null:
		return
	var id := _tabs.active_id()
	if _model_of(id) != model:
		return
	var dock := _tabs.dock(id) as AgentDock
	if dock and dock.follow_enabled:
		_follower.follow(call)


func _on_follow_toggled(enabled: bool) -> void:
	if not enabled and _follower:
		_follower.cancel()


## Un tool call que escribió archivos terminó: el editor se pone al día (spec §8.1).
func _on_tool_call_changed(call: ToolCall, _group: ChatEntry, model: SessionModel = null) -> void:
	if (model if model else _model).replaying:
		return
	_follow_call(call, model if model else _model)
	if not _pending_undo.is_empty() and call.undo_info.is_empty() and not call.godot_tool_name().is_empty():
		_match_pending_undo()
	if call.status != ToolCall.STATUS_COMPLETED or not call.kind in WRITING_KINDS:
		return
	var paths: Dictionary = {}
	for diff: Dictionary in call.diffs():
		paths[str(diff.get("path", ""))] = true
	for location: Variant in call.locations:
		if location is Dictionary and location.get("path") is String:
			paths[location.path] = true
	for path: String in paths:
		if not path.is_empty():
			_sync.after_agent_write(path)


func _on_conflict_detected(res_path: String) -> void:
	var data := {"path": res_path}
	_model.add_notice(
		I18n.t("%s has unsaved changes and the agent modified it on disk. Nothing was overwritten.") % res_path,
		ChatEntry.NoticeLevel.WARNING,
		[
			{"id": ACTION_CONFLICT_DIFF, "label": I18n.t("View diff"), "data": data},
			{"id": ACTION_CONFLICT_USE_AGENT, "label": I18n.t("Use the agent's"), "data": data},
			{"id": ACTION_CONFLICT_KEEP_MINE, "label": I18n.t("Keep mine"), "data": data},
		]
	)


func _on_open_scene_modified(res_path: String) -> void:
	_model.add_notice(
		I18n.t("The agent modified the open scene %s on disk, and it has unsaved changes: it was not reloaded. Reloading it discards your changes.") % res_path,
		ChatEntry.NoticeLevel.WARNING,
		[{"id": ACTION_RELOAD_SCENE, "label": I18n.t("Reload scene"), "data": {"path": res_path}}]
	)


func _on_dock_action(action: String, payload: Variant) -> void:
	var path := str(payload.get("path", "")) if payload is Dictionary else ""
	match action:
		AgentDock.ACTION_VIEW_MEMORY:
			_open_extensions(ExtensionsWindow.ExtensionsTab.MEMORY)
		SessionController.ACTION_REINSTALL_AGENT:
			var settings := _get_settings_dialog()
			settings.open()
			settings.open_registry()
		ACTION_CONFLICT_DIFF:
			var buffer: Variant = _sync.buffer_text(ProjectSettings.globalize_path(path))
			_diff_dialog.show_diff(I18n.t("Conflict: %s") % path.get_file(), I18n.t("your version"), str(buffer) if buffer != null else "", I18n.t("agent's version"), _sync.conflict_disk_text(path))
		ACTION_CONFLICT_USE_AGENT:
			_sync.resolve_use_disk(path)
		ACTION_CONFLICT_KEEP_MINE:
			_sync.resolve_keep_buffer(path)
		ACTION_RELOAD_SCENE:
			_sync.reload_scene(path)
		ACTION_UNDO_TOOL_CALL:
			_undo_tool_call(str(payload))
		SessionController.ACTION_TURN_CHANGES:
			_turn_dialog.show_turn(payload)
		SessionController.ACTION_SECOND_OPINION:
			_second_opinion_for_user(payload)
		SessionController.ACTION_SECOND_OPINION_CANCEL:
			if _second_opinion:
				_second_opinion.cancel()
		SessionController.ACTION_SECOND_OPINION_OPEN:
			_open_elsewhere(str(payload.get("session", PRIMARY_SESSION)), str(payload.get("session_id", "")))
		SessionController.ACTION_TURN_RESTORE:
			_turn_changes.confirm_restore(payload)
		TurnChanges.ACTION_HUNK_UNDO:
			_turn_changes.undo_hunk(payload)
		SessionController.ACTION_TURN_REPORT:
			_turn_changes.save_report(payload)
		RemoteActivity.ACTION_DIFF:
			var texts := _remote_activity.diff_texts(int(payload))
			_diff_dialog.show_diff(I18n.t("Changes from Remote Control"), I18n.t("before"), texts[0], I18n.t("now"), texts[1])
		RemoteActivity.ACTION_UNDO:
			_remote_activity.undo(int(payload))
		ACTION_ONESHOT_RESUME:
			if _oneshot:
				_oneshot.take_dock_retry(_oneshot.model)
		ACTION_ONESHOT_SHOW:
			if _surfaces:
				_surfaces.make_visible(EditorSurfaces.EditorSurface.MAIN_SCREEN)
		ACTION_SUPERVISE:
			var error := restart_editor(true, "the user asked for the supervisor")
			if not error.is_empty():
				_model.add_notice(error, ChatEntry.NoticeLevel.WARNING)
		ACTION_PENDING_INSTALL_RESTART:
			if NativeInstall.pending_info(SupervisorClient.state_dir()).is_empty():
				_model.add_notice(I18n.t("There is nothing staged to install anymore."), ChatEntry.NoticeLevel.INFO)
			else:
				# Como restart_editor: bajo el supervisor, que vuelve atrás si la build crashea al arrancar.
				var error := restart_editor(true, "the user restarted to install the staged GDExtension")
				if not error.is_empty():
					_model.add_notice(error, ChatEntry.NoticeLevel.WARNING)
		ACTION_PENDING_INSTALL_DISCARD:
			var info := NativeInstall.pending_info(SupervisorClient.state_dir())
			NativeInstall.discard_pending(SupervisorClient.state_dir())
			if not info.is_empty():
				_model.add_notice(I18n.t("Discarded the staged install of %s. The game keeps the build it has.") % NativeInstall.pending_names(info), ChatEntry.NoticeLevel.INFO)
		ACTION_COPY_SUPERVISOR_COMMAND:
			DisplayServer.clipboard_set(SupervisorClient.command_line())
			_model.add_notice(I18n.t("Command copied: open the editor with it from a terminal."), ChatEntry.NoticeLevel.INFO)
		AgentDock.ACTION_REVIEW_FOCUS:
			if not _review_annotations.focus_finding(int(payload)):
				_model.add_notice(I18n.t("Could not open the finding."), ChatEntry.NoticeLevel.WARNING)
		AgentDock.ACTION_REVIEW_FIX_ALL:
			_fix_review_findings(_controller.review.findings.duplicate())
		AgentDock.ACTION_RUN_REGRESSIONS:
			_run_regressions(int(payload) if payload is int else 1)
		AgentDock.ACTION_REGRESSIONS_WORKFLOW:
			_write_regressions_workflow(false)
		AgentDock.ACTION_MEASURE_REGRESSIONS:
			_measure_regressions()
		ACTION_CANCEL_MUTATION:
			if _mutation:
				_mutation.cancel()
		ACTION_OPEN_MUTANT:
			var where := str(payload)
			EditorContext.open_location(where.get_slice("#", 0), where.get_slice("#", 1).to_int())
		ACTION_OVERWRITE_REGRESSIONS_WORKFLOW:
			_write_regressions_workflow(true)
		ACTION_SEND_HOOK_PROMPT:
			var hook_dock := _tabs.dock(_tabs.active_id()) as AgentDock if _tabs else null
			if hook_dock:
				_hook_prompts_in_row = 0
				hook_dock.send_text(str(payload), HarnessPrompts.HOOK)
		ACTION_FIX_RUN_ERROR:
			var dock := _tabs.dock(_tabs.active_id()) as AgentDock if _tabs else null
			if dock:
				dock.send_text(str(payload), HarnessPrompts.RUN_ERROR)
		AgentDock.ACTION_OPEN_RUN_FILE:
			if _surfaces:
				_surfaces.make_visible(EditorSurfaces.EditorSurface.MAIN_SCREEN)
			_main_screen.call(&"show_run_file", path)


## Repite los playtests guardados sin agente (m16-06), `repeat` veces cada uno (m11-42), y deja el
## resultado en el chat. Con varias corridas, las inestables quedan marcadas en el panel.
func _run_regressions(repeat: int = 1) -> void:
	if _run_tools == null or _run_tools.regressions_running:
		return
	var entries := PlaytestRegressions.new().list()
	repeat = clampi(repeat, 1, PlaytestRegressions.MAX_REPEAT)
	_model.add_notice((I18n.t("Running the saved regressions (%d) without the agent…") % entries.size()) if repeat == 1 else I18n.t("Running the saved regressions (%d), %d times each, without the agent…") % [entries.size(), repeat], ChatEntry.NoticeLevel.INFO)
	var results := await _run_tools.run_saved_regressions(entries, repeat)
	_controller.review.changed.emit()  # el panel muestra cuántas quedaron inestables
	var summary := PlaytestRegressions.summary(results, false, Callable(I18n, &"t"))
	# La salida trae los textos del juego en sobres con el marcador del proceso: sin sellar, el marcador
	# queda a la vista en el chat y en lo que se copie de ahí (m11-45).
	summary.details = UntrustedText.seal(str(summary.details), UntrustedText.new_nonce())
	if summary.failed == 0 and summary.flaky == 0:
		_model.add_notice(I18n.t("Regressions: none fail (%d).") % results.size() if repeat == 1 else I18n.t("Regressions: none fail (%d, %d times each).") % [results.size(), repeat], ChatEntry.NoticeLevel.INFO)
	elif summary.failed == 0:
		_model.add_notice("%s\n%s" % [I18n.t("Regressions: none of %d fail, %d flaky.") % [results.size(), summary.flaky], summary.details], ChatEntry.NoticeLevel.WARNING)
	else:
		var head := I18n.t("Regressions: %d of %d fail.") % [summary.failed, results.size()] if summary.flaky == 0 else I18n.t("Regressions: %d of %d fail, %d flaky.") % [summary.failed, results.size(), summary.flaky]
		_model.add_notice("%s\n%s" % [head, summary.details], ChatEntry.NoticeLevel.ERROR)


## «Medir regresiones» (m11-41): mutantes del código del juego, cada uno en un Godot headless aparte y
## solo en su memoria. El progreso va en un aviso con «Cancelar» y el resultado, con el puntaje, los
## que no se detectaron (con «Abrir») y cuántos atrapó cada regresión, en otro; queda en mutation.json.
func _measure_regressions() -> void:
	if _mutation:
		_model.add_notice(I18n.t("The regressions are already being measured."), ChatEntry.NoticeLevel.INFO)
		return
	var entries := PlaytestRegressions.new().list()
	var progress := _model.add_notice(I18n.t("Measuring the regressions: first they run without mutants…"), ChatEntry.NoticeLevel.INFO,
		[{"id": ACTION_CANCEL_MUTATION, "label": I18n.t("Cancel")}])
	_mutation = MutationTesting.new()
	_mutation.on_progress = func(done: int, total: int, _mutant: Dictionary) -> void:
		progress.text = I18n.t("Measuring the regressions: mutant %d of %d…") % [done, total]
		_model.notify_entry_changed(progress)
	var result := await _mutation.run(entries)
	_mutation = null
	progress.actions = []
	if not result.ok:
		progress.text = I18n.t(str(result.error))
		progress.level = ChatEntry.NoticeLevel.INFO if result.get("cancelled", false) else ChatEntry.NoticeLevel.WARNING
		_model.notify_entry_changed(progress)
		return
	var file := FileAccess.open(MutationTesting.RESULT_FILE, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(result, "\t"))
		file.close()
	var goals := {}
	for entry: Dictionary in entries:
		goals[str(entry.get("file", ""))] = str(entry.get("goal", ""))
	var notice := MutationTesting.notice(result, goals, Callable(I18n, &"t"))
	for survivor: Dictionary in notice.survivors:
		progress.actions.append({"id": ACTION_OPEN_MUTANT, "label": I18n.t("Open %s:%d") % [str(survivor.path).get_file(), int(survivor.line)], "data": "%s#%d" % [survivor.path, int(survivor.line)]})
	progress.title = notice.title
	progress.text = notice.text
	progress.sections.assign(notice.sections)
	progress.level = ChatEntry.NoticeLevel.WARNING if notice.level_warning else ChatEntry.NoticeLevel.INFO
	_model.notify_entry_changed(progress)


## El workflow de CI que corre las regresiones grabadas (m16-10). Uno que ya existe no se pisa:
## el aviso ofrece «Overwrite».
func _write_regressions_workflow(overwrite: bool) -> void:
	if PlaytestRegressions.new().list().is_empty():
		_model.add_notice(I18n.t("There are no saved regressions yet: a playtest that passes saves one. The workflow would fail on every push, so it was not written."), ChatEntry.NoticeLevel.WARNING)
		return
	var root := ProjectSettings.globalize_path("res://").trim_suffix("/")
	var written := RegressionsWorkflow.write(root, false, overwrite)
	if written.ok:
		_model.add_notice(I18n.t("Workflow written: %s, for Godot %s. Commit it and push: GitHub Actions will run the saved regressions on every push and pull request.") % [written.root.path_join(written.path), RegressionsWorkflow.editor_version()], ChatEntry.NoticeLevel.INFO)
		for warning: String in written.warnings:
			_model.add_notice(I18n.t(REGRESSIONS_WORKFLOW_WARNINGS[warning]), ChatEntry.NoticeLevel.WARNING)
		EditorInterface.get_resource_filesystem().scan()
	elif written.existed:
		_model.add_notice(I18n.t("%s already exists. Overwrite it with the harness's workflow?") % written.path, ChatEntry.NoticeLevel.WARNING,
			[{"id": ACTION_OVERWRITE_REGRESSIONS_WORKFLOW, "label": I18n.t("Overwrite"), "primary": true}])
	else:
		_model.add_notice(I18n.t("Could not write the workflow: %s") % written.error, ChatEntry.NoticeLevel.ERROR)


## Botones de la tarjeta de un hallazgo en el Script Editor (spec §9.4).
func _on_review_action(action: String, finding: Dictionary) -> void:
	match action:
		ReviewAnnotations.ACTION_DISMISS:
			_controller.review.dismiss(int(finding.id))
		ReviewAnnotations.ACTION_ASK:
			if _can_send():
				_controller.send_prompt(_controller.label_prompt(ReviewStore.question_prompt(finding), HarnessPrompts.REVIEW_QUESTION), [], false)
		ReviewAnnotations.ACTION_APPLY:
			var list: Array[Dictionary] = [finding]
			_fix_review_findings(list)


## Pasa a Construir y pide los arreglos; si el turno termina bien, esos hallazgos salen de la revisión.
func _fix_review_findings(list: Array[Dictionary]) -> void:
	if list.is_empty() or not _can_send():
		return
	var stop_reason := await _controller.send_in_mode(SessionModel.HarnessMode.BUILD, _controller.label_prompt(ReviewStore.fix_prompt(list), HarnessPrompts.REVIEW_FIX))
	if stop_reason == "end_turn" and _controller:
		for finding: Dictionary in list:
			_controller.review.dismiss(int(finding.id))


func _can_send() -> bool:
	if _model.state == SessionModel.SessionState.READY:
		return true
	_model.add_notice(I18n.t("That needs a ready session with no turn in progress."), ChatEntry.NoticeLevel.WARNING)
	return false


## Una tool de edición commiteó un paso de undo: se une a su tool call para el botón "↶ undo".
func _on_mcp_edit_action(tool_name: String, args: Dictionary, info: Dictionary) -> void:
	_pending_undo.append({"tool": tool_name, "args": args, "info": info, "time": Time.get_ticks_msec()})
	_match_pending_undo()


func _match_pending_undo() -> void:
	var now := Time.get_ticks_msec()
	for pending: Dictionary in _pending_undo.duplicate():
		var call: ToolCall = null
		for model: SessionModel in _models():
			call = model.find_godot_tool_call(pending.tool, pending.args, _log.redact_data)
			if call:
				call.undo_info = pending.info
				model.touch_tool_call(call)
				_pending_undo.erase(pending)
				break
		if call:
			continue
		elif now - int(pending.time) > PENDING_UNDO_TTL_MS:
			_pending_undo.erase(pending)


func _undo_tool_call(call_id: String) -> void:
	var model := _model
	for candidate: SessionModel in _models():
		if candidate.tool_call(call_id):
			model = candidate
	var call := model.tool_call(call_id)
	if call == null or not call.can_undo():
		return
	var reason := EditorUndo.undo(call.undo_info)
	if reason.is_empty():
		call.undo_done = true
		model.touch_tool_call(call)
		_log.add(AgentLog.CH_MCP, "undone: %s" % call.undo_info.get("action", ""))
	else:
		model.add_notice(I18n.t("Could not undo «%s»: %s") % [call.undo_info.get("action", ""), reason], ChatEntry.NoticeLevel.WARNING)


## El cliente del Asset Store, compartido por la pestaña de Extensions y las tools del agente.
func _asset_store() -> AssetStore:
	if _store == null:
		_store = AssetStore.new()
		add_child(_store)
	return _store


## Server MCP con las tools godot.* (spec §5). La política de permisos se aplica del lado del server
## con el modo actual del harness; "ask" muestra una tarjeta y vence a los permission_timeout_s.
func _start_mcp_server() -> void:
	_errors = ErrorCollector.new()
	_errors.start()
	var registry := ToolRegistry.new()
	_registry = registry
	registry.agent_log = _log
	registry.max_output_chars = _project_config.max_output_chars
	registry.max_image_side = _project_config.max_image_side
	registry.compact = _project_config.compact_tools
	registry.session_authorizer = func(caller: String, group: String, title: String, description: String) -> bool:
		var controller := _controller_of(_session_of(caller))
		return controller != null and await controller.authorize(group, title, description, {}, _project_config.permission_timeout_s)
	registry.guard = _guard_tool
	registry.precheck = _precheck_tool
	registry.error_mark = _errors.mark
	registry.errors_since = _errors.entries_since
	registry.register_provider(ReadTools.new())
	_map_tools = MapTools.new()
	_map_tools.editor_focus = _editor_focus
	registry.register_provider(_map_tools)
	var api_tools := ApiTools.new()
	api_tools.doc_cache_path = ApiTools.editor_doc_cache_path()
	registry.register_provider(api_tools, true)
	_diagnostics = DiagnosticTools.new()
	_diagnostics.setup(_errors, EditorContext.project_path())
	registry.register_provider(_diagnostics)
	# Solo la usa un proyecto con GDExtension (m19-01): no gasta contexto en los demás.
	registry.mark_extended(PackedStringArray(["build_extension", "test_extension", "install_extension", "restart_editor"]))
	_diagnostics.restarter = func(supervise: bool) -> String:
		var error := _prepare_restart(supervise)
		if error.is_empty():
			# Después de devolver el resultado de la tool: el agente lo recibe antes de que se cierre.
			get_tree().create_timer(1.0).timeout.connect(_restart_now.bind("restart_editor"))
		return error
	var edit_tools := SceneEditTools.new()
	edit_tools.on_action = _on_mcp_edit_action
	registry.register_provider(edit_tools)
	registry.register_provider(ProjectTools.new(), true)
	var asset_tools := AssetTools.new()
	asset_tools.store = _asset_store()
	registry.register_provider(asset_tools, true)
	var file_tools := FileTools.new()
	file_tools.on_file_written = _after_agent_write
	file_tools.unsaved_buffer = _sync.buffer_text
	registry.register_provider(file_tools, true)
	registry.register_provider(ResourceTools.new(), true)
	var tilemap_tools := TilemapTools.new()
	tilemap_tools.on_action = _on_mcp_edit_action
	registry.register_provider(tilemap_tools, true)
	registry.register_provider(ValidateTools.new(), true)
	var animation_tools := AnimationTools.new()
	animation_tools.on_action = _on_mcp_edit_action
	registry.register_provider(animation_tools, true)
	_run_tools = RunTools.new()
	_run_tools.setup(_errors, _playtest_debugger)
	_run_tools.max_image_side = _project_config.max_image_side
	_run_tools.cleanup = _remove_playtest_autoload
	_run_tools.agent_log = _log
	registry.register_provider(_run_tools)
	_run_errors = RunErrorWatcher.new()
	_run_errors.errors = _errors
	_run_errors.launched_by_harness = func() -> bool: return _run_tools != null and _run_tools.harness_run
	_run_errors.break_reason = PlaytestDebugger.break_reason
	_run_errors.still_breaked = func() -> bool: return _playtest_debugger != null and _playtest_debugger.any_breaked()
	_run_errors.enabled = func() -> bool: return _settings != null and _settings.offer_fix_on_run_error()
	_run_errors.error_found.connect(_on_run_error)
	_run_tools.regressions_finished.connect(func(results: Array) -> void:
		if _hooks:
			var failed := results.filter(func(result: Dictionary) -> bool: return not result.passed and not result.get("flaky", false))
			var lines := PackedStringArray(failed.map(func(result: Dictionary) -> String: return "✗ " + str(result.get("goal", ""))))
			_hooks.fire({"event": ProjectHooks.EVENT_REGRESSIONS, "path": "", "by": ProjectHooks.BY_AGENT if _registry and _registry.running_calls > 0 else ProjectHooks.BY_USER,
				"errors": failed.size(), "lines": lines}))
	_run_errors.game_ended.connect(func(info: Dictionary) -> void:
		if _hooks:
			_hooks.fire({"event": ProjectHooks.EVENT_GAME_STOPPED, "path": "", "by": info.by, "errors": info.count, "lines": info.lines}))
	# Después de run_tools.setup: cuando llega la señal, run_tools ya decidió quién lanzó el run.
	_playtest_debugger.session_started.connect(_run_errors.on_game_started)
	_playtest_debugger.session_breaked.connect(_on_game_breaked)
	_playtest_debugger.session_stopped.connect(_run_errors.on_game_stopped)
	_debug_tools = DebugTools.new()
	_debug_tools.setup(_run_tools, _playtest_debugger)
	_debug_tools.caller = func() -> String: return _registry.current_caller if _registry else ""
	_debug_tools.user_breakpoints = func() -> PackedStringArray: return EditorInterface.get_script_editor().get_breakpoints()
	var debugger_node := _editor_debugger_node()
	if debugger_node:
		debugger_node.connect(&"breakpoint_toggled", _on_editor_breakpoint_toggled)
	registry.register_provider(_debug_tools)
	registry.mark_extended(RunTools.GAME_TOOLS)
	# m13-27: lee el profiler por una API interna del editor; sin ella, la tool contesta por qué no puede.
	_profile_tools = ProfileTools.new()
	_profile_tools.setup(_run_tools, _playtest_debugger)
	registry.register_provider(_profile_tools, true)
	var session_tools := SessionTools.new()
	# Por el campo y no por `registry`: el registro guarda la tool y la lambda no puede guardarlo a él.
	session_tools.caller = func() -> String: return _session_of(_registry.current_caller if _registry else "")
	session_tools.describe = _describe_sessions
	session_tools.send = _send_to_session
	registry.register_provider(session_tools, true)
	var second_opinion_tools := SecondOpinionTools.new()
	second_opinion_tools.caller = func() -> String: return _session_of(_registry.current_caller if _registry else "")
	second_opinion_tools.ask = _ask_second_opinion_tool
	registry.register_provider(second_opinion_tools, true)
	_project_tools = ProjectToolLoader.new()
	_project_tools.dir = ProjectToolLoader.resolve_dir(_project_config.project_tools_dir)
	# La carpeta del proyecto del editor, no la de una copia aparte: la clave es la misma en las dos.
	_project_tools.project_dir = ProjectSettings.globalize_path("res://")
	_project_tools.is_approved = _settings.is_command_approved
	# Lambdas que capturan el plugin, no el registro: el registro guarda el loader.
	_project_tools.reserved = func(tool_name: String) -> bool: return _registry != null and _registry.is_builtin(tool_name)
	_project_tools.log_line = func(text: String) -> void: _log.add(AgentLog.CH_MCP, text)
	_project_tools.undo_redo = EditorInterface.get_editor_undo_redo()
	registry.project_tools = _project_tools
	_project_tools.changed.connect(_on_project_tools_changed)
	var filesystem := EditorInterface.get_resource_filesystem()
	if not filesystem.filesystem_changed.is_connected(_on_project_tools_changed):
		filesystem.filesystem_changed.connect(_on_project_tools_changed)
	_mcp_server = McpServer.new()
	_mcp_server.registry = registry
	_mcp_server.agent_log = _log
	add_child(_mcp_server)
	if _mcp_server.start(_settings.mcp_port()) == OK:
		_log.add_secret(_mcp_server.token)


## Entradas `mcpServers` para session/new: la del addon (HTTP si el agente lo soporta; si no, el
## shim stdio) y los servers de terceros de Settings (m7-34).
func _mcp_servers(session: String = PRIMARY_SESSION, model: SessionModel = null) -> Array:
	if model == null:
		model = _model
	var result: Array = []
	if _mcp_server and _mcp_server.is_listening():
		var token := _mcp_server.token if session == PRIMARY_SESSION else _mcp_server.session_token(session)
		_log.add_secret(token)  # el de cada pestaña también: el JSON crudo de session/new lo lleva
		if model.supports_http_mcp():
			result.append(_mcp_server.http_server_entry(token))
		else:
			var entry := StdioShimInstaller.server_entry(McpServer.SERVER_NAME, _mcp_server.url(), token)
			if entry.is_empty():
				_log.add(AgentLog.CH_MCP, "could not prepare the stdio shim in user://: the agent will not have the godot.* tools")
			else:
				result.append(entry)
	var held: Array = []
	for server: Dictionary in _external_mcp_servers():
		if not bool(server.enabled):
			continue
		if bool(server.get("held", false)):
			held.append({"name": server.name, "command": ExternalMcpServers.approval_description(server), "key": server.approval_key})
			continue
		var entry := ExternalMcpServers.to_acp(server, model.supports_http_mcp())
		if entry.is_empty():
			_log.add(AgentLog.CH_MCP, "%s left out: the agent doesn't take HTTP MCP servers" % server.name)
			model.add_notice(I18n.t("The MCP server «%s» was left out: this agent only takes stdio servers.") % server.name, ChatEntry.NoticeLevel.WARNING)
			continue
		for secret: String in ExternalMcpServers.secret_values(server):
			_log.add_secret(secret)
		result.append(entry)
	_announce_held_tools([model], true)
	if not held.is_empty():
		# m13-31: un server del proyecto sin aprobar no corre, y no en silencio: la primera vez el aviso
		# explica el cambio (un proyecto que ya los usaba los pierde al actualizar).
		var explain := not bool(_settings.get_value(HarnessSettings.KEY_MCP_APPROVAL_EXPLAINED, false))
		_settings.set_value(HarnessSettings.KEY_MCP_APPROVAL_EXPLAINED, true)
		var notice := SessionController.held_servers_notice(held, explain)
		_log.add(AgentLog.CH_MCP, "project MCP servers not approved on this machine, left out: %s" % ", ".join(PackedStringArray(held.map(func(item: Dictionary) -> String: return item.name))))
		model.add_notice(notice.text, ChatEntry.NoticeLevel.WARNING, notice.actions)
	return result


## Algo cambió en el filesystem: una tool del proyecto nueva o editada (también por el agente) queda
## frenada, y se avisa una vez en todas las pestañas (m11-46).
func _on_project_tools_changed() -> void:
	if _project_tools != null:
		_announce_held_tools(_models(), false)


## El aviso de las tools del proyecto sin aprobar. `all`: todas (al empezar una sesión); si no, solo
## las que no se avisaron todavía.
func _announce_held_tools(models: Array, all: bool) -> void:
	if _project_tools == null:
		return
	_project_tools.refresh()
	var held: Array = _project_tools.held().filter(func(item: Dictionary) -> bool: return all or not _tools_announced.has(item.key))
	if held.is_empty():
		return
	for item: Dictionary in held:
		_tools_announced[item.key] = true
	_log.add(AgentLog.CH_MCP, "project tools not approved on this machine: %s" % ", ".join(PackedStringArray(held.map(func(item: Dictionary) -> String: return item.name))))
	var notice := SessionController.held_tools_notice(held)
	for model: SessionModel in models:
		model.add_notice(notice.text, ChatEntry.NoticeLevel.WARNING, notice.actions)


## Servers de terceros del usuario y del proyecto (si se llaman igual, gana el del proyecto). Uno del
## proyecto que no está aprobado en esta máquina (m13-31) viene con `held` y su `approval_key`.
func _external_mcp_servers() -> Array:
	var project_dir := ProjectSettings.globalize_path("res://")
	var project: Array = ExternalMcpServers.normalize_list(_project_config.mcp_servers)
	for server: Dictionary in project:
		server["approval_key"] = ExternalMcpServers.approval_key(project_dir, server)
		server["held"] = not _settings.is_command_approved(server.approval_key)
	return ExternalMcpServers.merge(_settings.mcp_servers(), project)


func _external_mcp_names() -> PackedStringArray:
	var names: PackedStringArray = []
	for server: Dictionary in _external_mcp_servers():
		if bool(server.enabled) and not bool(server.get("held", false)):
			names.append(server.name)
	return names


func _prompt_variables() -> Dictionary:
	return {
		"project_name": str(ProjectSettings.get_setting("application/config/name", "")),
		"project_path": EditorContext.project_path(),
		"godot_version": Engine.get_version_info().string,
		"project_tools_dir": ProjectToolLoader.resolve_dir(_project_config.project_tools_dir),
	}


func _oneshot_defaults() -> Dictionary:
	return {
		OneShotRun.BUDGET_TIME: _project_config.budget_minutes,
		OneShotRun.BUDGET_TOKENS: _project_config.budget_tokens,
		OneShotRun.BUDGET_PLAYTESTS: _project_config.budget_playtests,
		"checkpoints": _project_config.checkpoints_enabled,
		"spec_review": _project_config.spec_review,
	}


## Guarda la config del proyecto («Permitir siempre» del modo Auto, permisos, skills apagadas…).
func _save_project_config() -> void:
	var result := _project_config.save_to_project()
	if result != OK:
		_log.add(AgentLog.CH_PERM, "could not save %s: %s" % [ProjectConfig.PATH, error_string(result)])


## «Permitir siempre en este proyecto» en la tarjeta de un MCP server de terceros (m7-35).
func _on_permissions_changed(controller: SessionController = null) -> void:
	_project_config.permissions = (controller if controller else _controller).policy.overrides
	for other: SessionController in _controllers():
		other.policy.overrides = _project_config.permissions
	_save_project_config()


## `_meta` de session/new y session/load: lo arma el adaptador del agente (m13-04).
func _session_meta(controller: SessionController = null) -> Dictionary:
	return (controller if controller else _controller).adapter.session_meta(_project_config.disabled_skills)


## El agente de una pestaña (por defecto, la activa): el de su sesión si está conectada; si no, el
## elegido en ella. Cada pestaña puede usar otro perfil, por ejemplo otra cuenta de Claude Code.
func _tab_profile(id: String = "") -> AgentProfile:
	if id.is_empty():
		id = _active_session_id()
	var controller := _controller_of(id)
	if controller and controller.profile() and controller.is_connected_to_agent():
		return controller.profile()
	var dock := _tabs.dock(id) as AgentDock if _tabs else null
	return dock.selected_profile() if dock else _settings.active_profile()


## El adaptador del agente de la pestaña activa (antes de conectar): qué familia de extensiones mostrar.
func _active_adapter() -> AgentAdapter:
	var profile := _tab_profile()
	return AgentAdapters.for_profile(profile.command, profile.args, profile.id) if profile else AgentAdapter.new()


## El CLI corre con el entorno del agente de la pestaña activa (CLAUDE_CONFIG_DIR y demás), como el agente.
func _open_extensions(tab: ExtensionsWindow.ExtensionsTab = ExtensionsWindow.ExtensionsTab.PLUGINS) -> void:
	var profile := _tab_profile()
	var window := _get_extensions_window()
	window.extensions = ClaudeExtensions.new(EditorContext.project_path(), profile.resolved_env() if profile else {})
	window.disabled_skills = _project_config.disabled_skills
	window.open(tab)


## Busca un release nuevo (m7-38) y, si hay, muestra el aviso en el dock. Al abrir el editor
## (`manual` false) no vuelve a mostrar la versión a la que se le dijo «Después». Devuelve el texto
## para Settings.
func _check_updates(manual: bool) -> String:
	if AddonUpdater.is_dev_copy():
		return I18n.t("This is a development copy of the addon (a link or with godot_agent_dev): update it with git.")
	if not _updater:
		return ""
	var result: Dictionary = await _updater.check()
	if not _updater:
		return ""
	if not result.error.is_empty():
		_log.add(AgentLog.CH_UPDATE, "could not check for a new version: %s" % result.error)
		return I18n.t("Could not check: %s") % result.error
	_settings.set_value(HarnessSettings.KEY_UPDATE_LAST_CHECK, int(Time.get_unix_time_from_system()))
	var release: Dictionary = result.release
	if release.is_empty():
		return I18n.t("You have the latest version (%s).") % AddonVersion.version()
	if manual or str(release.version) != str(_settings.get_value(HarnessSettings.KEY_UPDATE_DISMISSED, "")):
		_update_banner.show_release(release, AddonVersion.version())
	return I18n.t("Version %s is available: see the notice in the dock.") % release.version


func _on_update_requested() -> void:
	var release := _update_banner.release()
	var confirm := ConfirmationDialog.new()
	confirm.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	confirm.title = I18n.t("Update")
	confirm.dialog_text = I18n.t("Godot Agent Harness %s will be downloaded and installed over addons/godot_agent, and the editor will restart. Open scenes are saved first and the agent session closes. Your project settings (project_config.tres) are kept.") % release.version
	confirm.ok_button_text = I18n.t("Update and restart")
	confirm.cancel_button_text = I18n.t("Cancel")
	confirm.confirmed.connect(_install_update.bind(release))
	confirm.visibility_changed.connect(func() -> void:
		if not confirm.visible:
			EditorWindows.free_later.call_deferred(confirm))
	EditorInterface.get_base_control().add_child(confirm)
	confirm.popup_centered()


## Baja, valida e instala el release y reinicia el editor. Entre escribir los archivos y reiniciar
## no hay awaits: el editor no llega a recargar los scripts nuevos con el plugin viejo cargado.
func _install_update(release: Dictionary) -> void:
	if AddonUpdater.is_dev_copy():
		_update_banner.set_error(I18n.t("This is a development copy of the addon (a link or with godot_agent_dev): update it with git."))
		return
	_update_banner.set_progress(I18n.t("Downloading %s…") % release.version)
	var staged: Dictionary = await _updater.download(release)
	if not _updater:
		return
	if not staged.ok:
		_log.add(AgentLog.CH_UPDATE, "could not download %s: %s" % [release.version, staged.error])
		_update_banner.set_error(staged.error)
		return
	_update_banner.set_progress(I18n.t("Installing %s…") % release.version)
	_save_all_scenes()
	if _controller:
		_controller.stop()
	var backup := ProjectSettings.globalize_path(UPDATE_BACKUP_DIR % AddonVersion.version())
	var installed := AddonUpdater.install(staged.dir, ProjectSettings.globalize_path(AddonUpdater.ADDON_DIR), backup)
	if not installed.ok:
		_log.add(AgentLog.CH_UPDATE, "could not install %s: %s" % [release.version, installed.error])
		_update_banner.set_error(installed.error)
		return
	_log.add(AgentLog.CH_UPDATE, "installed %s: %d files written, %d removed, backed up: %s" % [release.version, installed.written, installed.removed.size(), ", ".join(installed.backed_up) if not installed.backed_up.is_empty() else "none"])
	if not installed.backed_up.is_empty():
		print("Godot Agent Harness: %s" % (I18n.t("your previous %s were saved in %s") % [", ".join(installed.backed_up), backup]))
	EditorInterface.restart_editor(false)


## save_all_scenes() usa el guardado con vista previa solo para la escena activa y solo si tiene
## cambios (EditorNode::_save_all_scenes en 4.7.2); las demás van por el camino sin vista previa.
## Guardar antes la activa sin vista previa la saca de esa lista (m17-01, D60). Las escenas que nunca
## se guardaron siguen en save_all_scenes, que le pide una ruta al usuario.
static func _save_all_scenes() -> void:
	var root := EditorInterface.get_edited_scene_root()
	var path := root.scene_file_path if root else ""
	if not path.is_empty() and path in EditorInterface.get_unsaved_scenes() and DirAccess.dir_exists_absolute(path.get_base_dir()):
		EditorInterface.save_scene_as(path, false)
	EditorInterface.save_all_scenes()


func _open_settings() -> void:
	_get_settings_dialog().open()


## Ajustes se arma la primera vez que se abre: no hace falta para que aparezca el dock y
## construirlo lleva ~135 ms (m16-15).
func _get_settings_dialog() -> SettingsDialog:
	if _settings_dialog:
		return _settings_dialog
	_settings_dialog = SettingsDialog.new()
	_settings_dialog.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_settings_dialog.setup(_settings, _project_config)
	_settings_dialog.mcp_url_provider = func() -> String:
		return _mcp_server.url() if _mcp_server and _mcp_server.is_listening() else ""
	_settings_dialog.regenerate_token = _regenerate_mcp_token
	_settings_dialog.seen_mcp_servers_provider = func() -> PackedStringArray:
		return PackedStringArray(_controller.seen_mcp_servers.keys())
	_settings_dialog.completion_metrics_provider = func() -> Array[Dictionary]:
		return _completion.metrics.summary() if _completion else ([] as Array[Dictionary])
	_settings_dialog.completion_metrics_reset = func() -> void:
		if _completion:
			_completion.metrics.clear()
	_settings_dialog.saved.connect(_on_settings_saved)
	_settings_dialog.update_checker = _check_updates.bind(true)
	_settings_dialog.show_tools = func() -> void: _open_extensions(ExtensionsWindow.ExtensionsTab.TOOLS)
	EditorInterface.get_base_control().add_child(_settings_dialog)
	return _settings_dialog


## Extensiones, igual que Ajustes: la primera vez que se abre (~20 ms).
func _get_extensions_window() -> ExtensionsWindow:
	if _extensions_window:
		return _extensions_window
	_extensions_window = ExtensionsWindow.new()
	_extensions_window.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_extensions_window.addon_servers_provider = _external_mcp_servers
	_extensions_window.tools_catalog_provider = func() -> Array[Dictionary]: return _registry.catalog() if _registry else ([] as Array[Dictionary])
	_extensions_window.tools_policy_provider = func() -> PermissionPolicy: return PermissionPolicy.new(_project_config.permissions if _project_config else {})
	_extensions_window.tools_compact_provider = func() -> bool: return _project_config != null and _project_config.compact_tools
	_extensions_window.tools_approve = func(data: Dictionary) -> void:
		var dock: Control = _tabs.dock(PRIMARY_SESSION) if _tabs else null
		if is_instance_valid(dock):
			(dock as AgentDock).confirm_on_machine(data)
	_extensions_window.asset_store = _asset_store()
	_extensions_window.is_claude_provider = func() -> bool:
		return _active_adapter().kind == ClaudeExtensions.AGENT_CLAUDE
	_extensions_window.has_agent_provider = func() -> bool: return _tab_profile() != null
	_extensions_window.agents_requested.connect(func() -> void:
		_extensions_window.hide()
		_get_settings_dialog().open(SettingsDialog.SettingsSection.AGENTS))
	_extensions_window.agent_kind_provider = func() -> String:
		return _active_adapter().kind if _tab_profile() != null else ClaudeExtensions.AGENT_CLAUDE
	_extensions_window.new_session_requested.connect(func() -> void:
		var dock: Control = _tabs.dock(PRIMARY_SESSION) if _tabs else null
		if is_instance_valid(dock):
			(dock as AgentDock).new_session())
	_extensions_window.disabled_skills_changed.connect(func(names: PackedStringArray) -> void:
		_project_config.disabled_skills = names
		_save_project_config())
	_extensions_window.mcp_settings_requested.connect(func() -> void: _get_settings_dialog().open(SettingsDialog.SettingsSection.MCP))
	EditorInterface.get_base_control().add_child(_extensions_window)
	return _extensions_window


## La config del proyecto se aplica en caliente; los settings de usuario llegan por settings_changed.
func _on_settings_saved() -> void:
	for controller: SessionController in _controllers():
		controller.policy.overrides = _project_config.permissions
		controller.policy.subagent_limits = _project_config.subagent_limits
		controller.shell_rules = _project_config.auto_shell_rules
		controller.external_mcp_names = _external_mcp_names()
		controller.fs.extra_roots = _project_config.extra_fs_roots
		if controller.cwd == EditorContext.project_path():  # una copia (m11-09) tiene los suyos
			controller.snapshots = _turn_snapshots if _project_config.turn_snapshots else null
	_registry.max_output_chars = _project_config.max_output_chars
	_registry.max_image_side = _project_config.max_image_side
	_registry.compact = _project_config.compact_tools
	_project_tools.dir = ProjectToolLoader.resolve_dir(_project_config.project_tools_dir)
	_run_tools.max_image_side = _project_config.max_image_side
	_main_screen.call(&"set_defaults", _oneshot_defaults())
	_oneshot.loops.repeats = _project_config.loop_repeats
	_oneshot.qa_max_rounds = _project_config.qa_rounds
	_oneshot.criteria = GameCriteria.resolve(_project_config.criteria)
	_completion.apply_settings()
	_log.add(AgentLog.CH_ACP, "settings saved")


## Mismo puerto (para no cambiar la URL), token nuevo. Las sesiones abiertas quedan con el viejo.
func _regenerate_mcp_token() -> void:
	var port := _mcp_server.port() if _mcp_server.is_listening() else _settings.mcp_port()
	_log.remove_secret(_mcp_server.token)
	if _mcp_server.start(port) == OK:
		_log.add_secret(_mcp_server.token)
		_model.add_notice(I18n.t("MCP token regenerated: the godot.* tools reach new sessions."), ChatEntry.NoticeLevel.INFO)


## Umbrales de cuota del usuario (spec §10.1, EditorSettings godot_agent/quota/*).
func _apply_quota_settings() -> void:
	for controller: SessionController in _controllers():
		controller.quota.configure(_settings.quota_warn(), _settings.quota_pause(), _settings.quota_pause_enabled())


func _on_editor_settings_changed() -> void:
	if _completion and EditorInterface.get_editor_settings().check_changed_settings_in_group(HarnessSettings.PREFIX + "completion"):
		_completion.apply_settings()
	if _controller and EditorInterface.get_editor_settings().check_changed_settings_in_group(HarnessSettings.PREFIX + "quota"):
		_apply_quota_settings()
		if _oneshot:
			_oneshot.resume_auto = _settings.quota_resume_auto()


# --- One-shot ------------------------------------------------------------------------------------

## Elegir One-shot en el dock abre la pantalla One-shot (ahí se escribe el objetivo).
func _on_harness_mode_changed(mode: SessionModel.HarnessMode) -> void:
	if mode == SessionModel.HarnessMode.ONESHOT and _oneshot and not _oneshot.is_active() and _surfaces:
		_surfaces.make_visible(EditorSurfaces.EditorSurface.MAIN_SCREEN)


## Un One-shot que quedó a medias (el editor se cerró o se cayó) vuelve en pausa.
## «Al abrir el editor: continuar la última sesión» (m12-12); no con un One-shot a medias.
func _continue_last_session(dock: Control) -> void:
	if not _settings.continue_on_open() or not is_instance_valid(dock) or (_oneshot and _oneshot.is_active()):
		return
	dock.continue_last_session()


## Al abrir el editor: lo que pasó mientras estuvo cerrado o caído (m19-03). Con un evento del
## supervisor (crash, rollback, reinicio), retoma la última sesión y se lo cuenta al agente; si no,
## sigue como siempre («continuar la última sesión», m12-12). En un proyecto que compila una
## GDExtension y no corre bajo el supervisor, ofrece abrirlo así.
func _report_supervisor_events(dock: Control) -> void:
	var events := SupervisorClient.take_events()
	_report_pending_install()
	if not SupervisorClient.is_supervised() and not NativeBuild.find_project(EditorContext.project_path()).is_empty():
		_model.add_notice(I18n.t("This project builds a GDExtension. Under the supervisor, a build that crashes the editor while starting is rolled back and the editor reopens, instead of crashing every time you open it."), ChatEntry.NoticeLevel.INFO, [
			{"id": ACTION_SUPERVISE, "label": I18n.t("Restart under the supervisor")},
			{"id": ACTION_COPY_SUPERVISOR_COMMAND, "label": I18n.t("Copy the command")},
		])
	if events.is_empty():
		_continue_last_session(dock)
		return
	var messages: PackedStringArray = []
	for event: Dictionary in events:
		messages.append(SupervisorClient.agent_message(event))
		var level := ChatEntry.NoticeLevel.INFO if event.get("kind") == SupervisorClient.State.EVENT_RESTART else ChatEntry.NoticeLevel.WARNING
		_model.add_notice(_supervisor_notice(event), level)
	if not is_instance_valid(dock) or (_oneshot and _oneshot.is_active()):
		return
	if await dock.continue_last_session():
		dock.send_text("\n\n".join(messages), HarnessPrompts.SUPERVISOR)


## Lo que preparó install_extension y todavía no entró (m19-05): el editor se cerró sin pasar por
## restart_editor (o se abrió de nuevo a mano). Sin este aviso quedaba en pending/ sin que nadie lo
## supiera.
func _report_pending_install() -> void:
	var failure := NativeInstall.take_install_failure(SupervisorClient.state_dir())
	if not failure.is_empty():
		_model.add_notice(I18n.t("Could not install the staged GDExtension %s: %s. The game keeps the build it had.") % [", ".join(PackedStringArray(failure.get("extensions", []))), str(failure.get("error", ""))], ChatEntry.NoticeLevel.WARNING)
	var info := NativeInstall.pending_info(SupervisorClient.state_dir())
	if info.is_empty():
		return
	_model.add_notice(I18n.t("The GDExtension %s is ready to install in %s, tested by the agent: restart the editor to load it.") % [NativeInstall.pending_names(info), info.target], ChatEntry.NoticeLevel.INFO, [
		{"id": ACTION_PENDING_INSTALL_RESTART, "label": I18n.t("Restart"), "primary": true},
		{"id": ACTION_PENDING_INSTALL_DISCARD, "label": I18n.t("Discard")},
	])


func _supervisor_notice(event: Dictionary) -> String:
	var restored := ", ".join(PackedStringArray(event.get("restored", [])))
	var disabled := ", ".join(PackedStringArray(event.get("disabled", [])))
	match str(event.get("kind", "")):
		SupervisorClient.State.EVENT_RESTART:
			return I18n.t("The editor restarted and loaded the current builds.")
		SupervisorClient.State.EVENT_CRASH:
			return I18n.t("The editor crashed and the supervisor reopened it.")
		SupervisorClient.State.EVENT_GAVE_UP:
			return I18n.t("The editor crashed several times in a row and the supervisor stopped reopening it.")
	var text := I18n.t("The editor crashed while starting and the supervisor reopened it.")
	if not restored.is_empty():
		text += " " + I18n.t("Restored the last good build of: %s.") % restored
	if not disabled.is_empty():
		text += " " + I18n.t("Disabled (renamed to .disabled): %s.") % disabled
	return text


## Reemplaza restart_editor() en las verificaciones del editor (pending_check): Callable(supervise,
## reason) -> String. Sin él, reinicia de verdad.
var restart_override: Callable


## Reinicia el editor para que cargue las bibliotecas nuevas (m19-03). Con `supervise` y sin
## supervisor, lanza uno que espera a que este editor se cierre y abre el nuevo bajo su vigilancia.
## Bajo el supervisor, el reinicio pasa por él (SupervisorClient.mark_closed). Devuelve "" o el error.
func restart_editor(supervise: bool, reason: String) -> String:
	if restart_override.is_valid():
		return restart_override.call(supervise, reason)
	var error := _prepare_restart(supervise)
	if error.is_empty():
		_restart_now(reason)
	return error


func _prepare_restart(supervise: bool) -> String:
	if supervise and not SupervisorClient.is_supervised():
		var error := SupervisorClient.launch_supervisor()
		if not error.is_empty():
			return error
		SupervisorClient.handoff = true
		SupervisorClient.install_restart_guard(get_tree())
	return ""


func _restart_now(reason: String) -> void:
	if not SupervisorClient.is_supervised() or SupervisorClient.handoff:
		# El supervisor solo deja eventos de los editores que lanzó: este lo deja el plugin.
		SupervisorClient.add_local_event({"kind": SupervisorClient.State.EVENT_RESTART, "reason": reason})
	_save_all_scenes()
	if not SupervisorClient.is_supervised() and not SupervisorClient.handoff:
		# Sin supervisor, lo que preparó install_extension (m19-05) entra ahora, justo antes de
		# cerrar: por rename, así este editor sigue con las bibliotecas que tiene mapeadas. Con
		# supervisor lo mueve él antes de abrir el editor nuevo.
		var installed := NativeInstall.apply_pending(ProjectSettings.globalize_path("res://"), SupervisorClient.state_dir())
		if not str(installed.error).is_empty():
			# Queda en last_install.json: el editor nuevo lo avisa en el dock.
			_log.add(AgentLog.CH_PROC, "install_extension: could not install the staged files (they stay staged): %s" % installed.error)
		elif not (installed.applied as PackedStringArray).is_empty():
			_log.add(AgentLog.CH_PROC, "install_extension: moved %d staged files into the game" % installed.applied.size())
	EditorInterface.restart_editor(true)


func _restore_oneshot() -> void:
	if _oneshot == null or not _oneshot.restore_interrupted():
		return
	_model.add_notice(I18n.t("There is an unfinished One-shot: «%s». It is paused; «Resume One-shot» reopens the agent session.") % _oneshot.goal.left(80), ChatEntry.NoticeLevel.WARNING, [
		{"id": ACTION_ONESHOT_RESUME, "label": I18n.t("Resume One-shot")},
		{"id": ACTION_ONESHOT_SHOW, "label": I18n.t("Open One-shot screen")},
	])


## Después de "Volver acá": el editor relee lo que cambió en disco. Las escenas abiertas se recargan
## directamente (el usuario pidió volver); los scripts abiertos pasan por EditorSync (si tenían
## cambios sin guardar, conflicto en lugar de pisarlos).
func _after_oneshot_restore(paths: PackedStringArray) -> void:
	var open_scenes := EditorInterface.get_open_scenes()
	for path: String in paths:
		var res_path := "res://" + path
		if res_path in open_scenes:
			if FileAccess.file_exists(res_path):
				_sync.reload_scene(res_path)
		elif FileAccess.file_exists(res_path):
			_sync.sync_path(res_path)
	EditorInterface.get_resource_filesystem().scan()


## Lo abierto en el editor, el foco de godot.project_map sin `focus` (m11-26): la escena actual y
## el script del editor de scripts.
func _editor_focus() -> PackedStringArray:
	var focus := PackedStringArray()
	var scene := EditorInterface.get_edited_scene_root()
	if scene and not scene.scene_file_path.is_empty():
		focus.append(scene.scene_file_path)
	var script := EditorInterface.get_script_editor().get_current_script()
	var script_path := MapTools.focus_of_script(script.resource_path) if script else ""
	if not script_path.is_empty() and not script_path in focus:
		focus.append(script_path)
	return focus


## El texto de una mención especial del composer (m11-08): las mismas tools que usa el agente, sin
## permiso porque las pide el usuario.
func _context_for_mention(kind: String, arg: String) -> String:
	if _registry == null:
		return ""
	match kind:
		"errors":
			return await _registry.run_for_user("get_errors", {"since": 0})
		"output":
			var text := _errors.output_text() if _errors else ""
			# Lo imprime el juego: va en un sobre como en los resultados de las tools (m11-45).
			return UntrustedText.seal(UntrustedText.wrap(text.right(OUTPUT_MENTION_CHARS).strip_edges()), UntrustedText.new_nonce())
		"game":
			return await _registry.run_for_user("game_tree", {})
		"docs":
			return await _registry.run_for_user("class_info", {"class": arg})
	return ""


## Un pedido del chat en línea (m11-05): va a la sesión de la pestaña activa y espera su turno.
func _active_session_id() -> String:
	var id := _tabs.active_id() if _tabs else PRIMARY_SESSION
	return id if not id.is_empty() else PRIMARY_SESSION


func _ask_inline(prompt: String) -> Dictionary:
	var id := _active_session_id()
	var controller := _controller_of(id)
	var model := _model_of(id)
	if controller == null or not controller.is_connected_to_agent():
		return {"text": "", "error": I18n.t("There's no session open in the Agent dock."), "no_session": true}
	if model.state != SessionModel.SessionState.READY:
		return {"text": "", "error": I18n.t("The agent is busy: try again when its turn ends.")}
	var first := model.entries().size()
	var reason: String = await controller.send_prompt(controller.label_prompt(prompt, HarnessPrompts.INLINE_EDIT))
	return {"text": controller.agent_text_since(first), "error": "" if reason == "end_turn" else I18n.t("The turn ended with «%s».") % reason}


## «Iniciar sesión» del Alt+I: la abre en la pestaña activa del dock, como su botón.
func _start_inline_session() -> bool:
	var id := _active_session_id()
	var dock := _tabs.dock(id) as AgentDock if _tabs else null
	if dock == null:
		return false
	await dock.start_session()
	var controller := _controller_of(id)
	return controller != null and controller.is_connected_to_agent()


## «Preguntar al agente» (m11-54): lo elegido va al composer de la pestaña activa, sin mandarlo.
func _ask_agent(text: String) -> void:
	var dock := _tabs.dock(_active_session_id()) as AgentDock if _tabs else null
	if dock == null:
		return
	_surfaces.make_visible(EditorSurfaces.EditorSurface.SIDE)
	dock.add_to_composer(text)


func _remove_playtest_autoload() -> void:
	PlaytestAutoload.unregister(_plugin)


# --- varias sesiones (m7-44) ----------------------------------------------------------------------

## Controller de una sesión con lo que comparten todas: política y reglas del proyecto, fs con el
## editor, el server MCP con su token propio y la coordinación de archivos.
func _make_controller(model: SessionModel, id: String, copy: WorktreeSession = null) -> SessionController:
	var controller := SessionController.new()
	var root: String = copy.info.project if copy else EditorContext.project_path()
	controller.setup(model, _log, root)
	controller.prompt_variables_provider = _prompt_variables
	# Lo que guarda el controller o el modelo se refiere a la sesión por id: un Callable que los
	# capture armaría un ciclo de referencias y no se liberarían al cerrar.
	controller.session_meta_provider = func() -> Dictionary: return _session_meta(_controller_of(id))
	controller.history = SessionHistory.new()
	controller.policy = PermissionPolicy.new(_project_config.permissions)
	controller.policy.subagent_limits = _project_config.subagent_limits
	controller.shell_rules = _project_config.auto_shell_rules
	controller.shell_rules_changed.connect(_save_project_config)
	controller.disconnected.connect(_on_agent_disconnected.bind(id))
	controller.permissions_changed.connect(func() -> void: _on_permissions_changed(_controller_of(id)))
	controller.external_mcp_names = _external_mcp_names()
	controller.quota.configure(_settings.quota_warn(), _settings.quota_pause(), _settings.quota_pause_enabled())
	var fs := FsHandler.new()
	fs.setup(root, _log)
	fs.extra_roots = _project_config.extra_fs_roots
	if copy == null:  # en una copia (m11-09) no hay buffers del editor que sincronizar
		fs.buffer_reader = _sync.buffer_text
		fs.after_write = _after_agent_write
	controller.set_fs_handler(fs)
	var terminal := TerminalHandler.new()
	terminal.setup(root, _log)
	terminal.extra_roots = _project_config.extra_fs_roots
	controller.set_terminal_handler(terminal)
	controller.mcp_servers_provider = _mcp_servers.bind(id, model)
	controller.session_key = id
	if copy:
		# Sus archivos no son los del editor: sin locks ni verificación por res://, y snapshots propios.
		var snapshots := TurnSnapshots.new(root)
		snapshots.setup()
		controller.snapshots = snapshots if _project_config.turn_snapshots else null
		return _finish_controller(controller, model, id)
	controller.file_guard = func(paths: PackedStringArray) -> String: return _coordinator.claim_label(id, paths) if _coordinator else ""
	controller.snapshots = _turn_snapshots if _project_config.turn_snapshots else null
	controller.turn_verifier = func(since_unix: int) -> String:
		if _diagnostics == null or not _project_config.verify_after_turn:
			return ""
		return await _diagnostics.verify_changed_scripts(since_unix)
	controller.turn_checks_provider = _turn_checks_info
	controller.is_command_approved = _settings.is_command_approved
	controller.notice_seen = _notice_seen
	controller.approve_command = _settings.approve_command
	return _finish_controller(controller, model, id)


## Los checks del proyecto (m11-31) y la tienda de aprobaciones de esta máquina.
func _turn_checks_info() -> Dictionary:
	return {"checks": _project_config.turn_checks if _project_config else [], "godot": OS.get_executable_path(),
		"project": ProjectSettings.globalize_path("res://")}


func _finish_controller(controller: SessionController, model: SessionModel, id: String) -> SessionController:
	controller.mode_models = ModeModels.new(_settings)  # el modelo de cada modo, por perfil (m11-38)
	# Un mensaje del usuario (sin etiqueta del harness) vuelve a habilitar los prompts de hooks (m11-24).
	model.entry_added.connect(func(entry: ChatEntry) -> void:
		if entry.kind == ChatEntry.EntryKind.USER and entry.harness_label.is_empty():
			_hook_prompts_in_row = 0)
	# El contador vivo (m11-34): el turno empieza al pasar a PROMPTING y cada tool call terminada
	# pide recalcular.
	model.state_changed.connect(func(state: SessionModel.SessionState) -> void:
		if _turn_counter:
			_turn_counter.on_state(id, state))
	model.tool_call_changed.connect(func(call: ToolCall, _group: ChatEntry) -> void:
		if _turn_counter and call.status == ToolCall.STATUS_COMPLETED:
			_turn_counter.note_activity(id))
	model.tool_call_changed.connect(func(call: ToolCall, group: ChatEntry) -> void: _on_tool_call_changed(call, group, _model_of(id)))
	model.turn_finished.connect(func(_stop_reason: String) -> void:
		if _coordinator:
			_coordinator.release_files(id))
	return controller


func _open_session_tab(in_copy: bool = false) -> void:
	var copy: WorktreeSession = null
	if in_copy:
		copy = WorktreeSession.new(EditorContext.project_path())
		var stamp := Time.get_datetime_string_from_system().replace("-", "").replace(":", "").replace("T", "-")
		if not await copy.create(stamp):
			EditorInterface.get_editor_toaster().push_toast(I18n.t("Could not create the separate copy: %s") % copy.last_error, EditorToaster.SEVERITY_WARNING)
			return
	var id := _create_session_tab(copy)
	var model := _model_of(id)
	var controller := _controller_of(id)
	if copy:
		copy_notice(model, copy.info.project, copy.info.branch)
		controller.note_for_agent("[You work in a separate git worktree of the project at %s (branch %s), not in the project open in the editor. Edit files there with your own tools. The godot.* tools that edit scenes or files, change the project or run the game act on the editor's project, so they are not available to you. To check your work and build scenes, run Godot headless on your folder (\"$GODOT\" --headless --path %s …) as this guide says:]\n\n%s" % [copy.info.project, copy.info.branch, copy.info.project, FileAccess.get_file_as_string(SessionController.HEADLESS_GUIDE_PATH)])


## El aviso de una sesión en una copia aparte (m12-45): una tarjeta corta con título; la carpeta va
## plegada con «Copiar» (antes era un párrafo centrado de 8 líneas con la ruta entera en el dock angosto).
static func copy_notice(model: SessionModel, folder: String, branch: String) -> ChatEntry:
	var entry := model.add_notice(I18n.t("Branch %s, from your last commit: uncommitted changes aren't in it. When you close the tab you choose whether to apply its changes to the project.") % branch)
	entry.title = I18n.t("Works in a separate copy")
	entry.details_title = I18n.t("Folder of the copy")
	entry.details = folder
	model.notify_entry_changed(entry)
	return entry


## Agrega una pestaña de sesión y devuelve su id. `label` vacío: «Sesión N». `for_oneshot`: la
## pestaña de un run (m17-19), que puede mostrar el modo One-shot.
func _create_session_tab(copy: WorktreeSession = null, label: String = "", for_oneshot: bool = false) -> String:
	_session_serial += 1
	var id := "s%d" % _session_serial
	if label.is_empty():
		# Una copia lleva ícono en la pestaña, no el sufijo «(copy)» que se cortaba (m12-45).
		var pattern := I18n.t("Session %d")
		label = pattern % _session_serial
		while _coordinator.label_taken(label, id):  # alguna otra se renombró así
			_session_serial += 1
			label = pattern % _session_serial
	else:
		var base := label
		var n := 2
		while _coordinator.label_taken(label, id):
			label = "%s (%d)" % [base, n]
			n += 1
	var model := SessionModel.new()
	var controller := _make_controller(model, id, copy)
	_extra_sessions[id] = {"model": model, "controller": controller, "copy": copy}
	_coordinator.register(id, label)
	var dock := AgentDockScene.instantiate()
	dock.allow_oneshot = for_oneshot
	dock.setup(model, controller, _settings)
	dock.show_log_requested.connect(_show_log)
	dock.settings_requested.connect(_open_settings)
	dock.new_tab_requested.connect(_open_session_tab)
	dock.extensions_requested.connect(func() -> void: _open_extensions())
	dock.tools_requested.connect(func() -> void: _open_extensions(ExtensionsWindow.ExtensionsTab.TOOLS))
	dock.action_forwarded.connect(_on_dock_action)
	dock.game_capture = _capture_game_for_dock
	dock.game_point = _point_game_for_dock
	dock.context_provider = _context_for_mention
	if copy == null:
		_wire_oneshot(dock, id)
	_wire_elsewhere(dock, id)
	dock.follow_toggled.connect(_on_follow_toggled)
	dock.turn_changes_requested.connect(func() -> void:
		if _turn_counter:
			_turn_counter.open(_session_of_dock(dock)))
	_tabs.add_session(id, dock, model, label)
	if copy:
		_tabs.set_copy(id, I18n.t("Works in a separate copy of the project · branch %s") % copy.info.branch)
		_coordinator.mark_copy(id, copy.info.branch)
	_log.add(AgentLog.CH_ACP, "%s opened" % label)
	return id


## Lo del One-shot en el dock de la pestaña `id` vale solo si el run corre en esa sesión (m17-19):
## la guía (con adjuntos), «Reintentar», el login, cambiar de sesión y el composer en modo One-shot.
## Todo por id: un Callable que capture el controller o el dock armaría ciclos al cerrar la pestaña.
func _wire_oneshot(dock: AgentDock, id: String) -> void:
	dock.submit_interceptor = func(text: String, take_blocks: Callable) -> bool:
		return _runs_in(id) and _oneshot.is_active() and _oneshot.take_dock_prompt(text, take_blocks.call())
	dock.retry_interceptor = func() -> bool: return _runs_in(id) and _oneshot.take_dock_retry(_model_of(id))
	dock.can_switch_session = func() -> bool: return not (_runs_in(id) and _oneshot.is_active())
	dock.oneshot_active = func() -> bool: return _runs_in(id) and _oneshot.is_active()
	dock.machine_states = func() -> Array[Dictionary]: return _machine_states(id)
	_controller_of(id).after_login = func() -> bool: return _runs_in(id) and _oneshot.take_login()
	var listener := func() -> void:
		var tab_dock := _tabs.dock(id) as AgentDock if _tabs else dock
		if is_instance_valid(tab_dock):
			tab_dock.refresh_oneshot()
	_oneshot.changed.connect(listener)
	if id != PRIMARY_SESSION:
		_extra_sessions[id]["oneshot_listener"] = listener


## El estado del juego de run_scene y del One-shot de la pestaña `id`, para el tooltip del
## encabezado del dock (m13-29): leído al momento de las máquinas de D61, sin copias.
func _machine_states(id: String) -> Array[Dictionary]:
	var states: Array[Dictionary] = []
	if _run_tools:
		var game_state := _run_tools.run_state
		# `live`: se muestra como chip junto al estado (m12-47); `alert`: en ámbar (parado en el debugger).
		states.append({"machine": I18n.t("Game"), "label": I18n.t(_run_tools.run_state_name()), "age": -1 if game_state == RunTools.GameRunState.IDLE else _run_tools.run_state_age_seconds(),
			"live": game_state in [RunTools.GameRunState.LAUNCHING, RunTools.GameRunState.STARTED, RunTools.GameRunState.PROBE_READY, RunTools.GameRunState.BREAKED], "alert": game_state == RunTools.GameRunState.BREAKED})  # sin juego, la antigüedad no dice nada
	if _second_opinion and _second_opinion.is_busy() and _second_opinion.requested_by == id:
		states.append({"machine": I18n.t("Second opinion"), "label": I18n.t("thinking"), "age": _second_opinion.age_seconds(), "live": true, "alert": false,
			"detail": _second_opinion.agent_label()})
	if _oneshot and _runs_in(id) and _oneshot.is_active():
		var label := "%s · %s" % [_oneshot.phase_label(), I18n.t(OneShotRun.STAGE_LABELS[_oneshot.stage()])]
		states.append({"machine": I18n.t("One-shot"), "label": label, "age": _oneshot.phase_age_seconds(), "live": true, "alert": _oneshot.phase in [OneShotRun.RunPhase.PAUSED_QUOTA, OneShotRun.RunPhase.LIMITED, OneShotRun.RunPhase.WAITING_CONFIRM]})
	return states


## m17-17: con la pestaña `id` ocupada, «Nueva sesión» y el historial abren en otra; y una sesión que
## ya está abierta en otra pestaña se elige en vez de abrirla dos veces.
func _wire_elsewhere(dock: AgentDock, id: String) -> void:
	dock.open_elsewhere_requested.connect(func(session_id: String) -> void: _open_elsewhere(id, session_id))
	dock.handoff_ready.connect(func(handoff: Dictionary) -> void: _open_handoff(id, handoff))
	dock.session_focuser = func(session_id: String) -> bool: return _focus_session(id, session_id)


## Traspaso (m11-35): otra pestaña con el agente, la cuenta y el modo de `from`, la sesión arrancada
## y el borrador en el composer, sin mandar.
func _open_handoff(from: String, handoff: Dictionary) -> void:
	var id := _create_session_tab()
	var dock := _tabs.dock(id) as AgentDock
	var source := _tabs.dock(from) as AgentDock
	if dock == null:
		return
	var running: AgentProfile = null
	if source:
		dock.copy_agent_from(source)
		dock.copy_mode_from(source)
		var source_controller := _controller_of(from)
		running = source_controller.profile() if source_controller and source_controller.is_connected_to_agent() else null
	_tabs.select(id)
	dock.use_handoff(handoff)
	# Con el perfil que corre allá (cuenta incluida), aunque no esté guardado en Ajustes.
	dock.start_session(running)


func _open_elsewhere(from: String, session_id: String) -> void:
	var id := _create_session_tab()
	var dock := _tabs.dock(id) as AgentDock
	var source := _tabs.dock(from) as AgentDock
	if dock and source:
		dock.copy_agent_from(source)
	_tabs.select(id)
	if session_id.is_empty():
		dock.start_session()
	else:
		dock.open_history_session(session_id)


func _focus_session(from: String, session_id: String) -> bool:
	if session_id.is_empty():
		return false
	for id: String in [PRIMARY_SESSION] + _extra_sessions.keys():
		var model := _model_of(id)
		if id != from and model and model.session_id == session_id:
			_tabs.select(id)
			return true
	return false


## true si el One-shot corre en la sesión de la pestaña `id`.
func _runs_in(id: String) -> bool:
	return _oneshot != null and _controller_of(id) != null and _oneshot.controller == _controller_of(id)


func _session_id_of(controller: SessionController) -> String:
	if controller == _controller:
		return PRIMARY_SESSION
	for id: String in _extra_sessions:
		if _extra_sessions[id].controller == controller:
			return id
	return PRIMARY_SESSION


## Antes de empezar un run (o de retomar uno que vino de disco): una pestaña nueva para él, con el
## agente y la cuenta de la pestaña desde la que se lanzó (m17-19). Las demás siguen como chats.
func _prepare_oneshot_tab() -> void:
	if _oneshot == null or _tabs == null:
		return
	var from := _active_session_id()
	var label := I18n.t("One-shot · %s") % _oneshot.goal.left(24).strip_edges()
	var id := _create_session_tab(null, label, true)
	var dock := _tabs.dock(id) as AgentDock
	var source := _tabs.dock(from) as AgentDock
	if dock and source and from != id:
		dock.copy_agent_from(source)
	_oneshot_tab_id = id
	_oneshot.bind(_controller_of(id))
	_tabs.select(id)


## Cerrar una pestaña. Una sesión en una copia (m11-09) primero commitea lo suyo en su rama y, si
## cambió algo, pregunta qué hacer; `ask` en false (al apagar el plugin) cierra sin tocar la copia.
func _close_session_tab(id: String, ask: bool = true) -> void:
	var session: Dictionary = _extra_sessions.get(id, {})
	if session.is_empty():
		return
	if _runs_in(id) and _oneshot.is_active():
		(session.model as SessionModel).add_notice(I18n.t("The One-shot runs in this tab: stop it from the One-shot screen before closing it."), ChatEntry.NoticeLevel.WARNING)
		return
	if _runs_in(id):  # el run terminado vuelve a la primera sesión; la pestaña se va
		_oneshot.bind(_controller)
		_oneshot_tab_id = ""
	if session.has("oneshot_listener") and _oneshot and _oneshot.changed.is_connected(session.oneshot_listener):
		_oneshot.changed.disconnect(session.oneshot_listener)
	var copy: WorktreeSession = session.get("copy")
	if copy and ask and not session.get("resolved", false):
		(session.controller as SessionController).stop()
		var changed := await copy.commit_changes()
		if changed.is_empty():
			await copy.remove(true)
		else:
			_ask_copy_fate(id, copy, changed)
			return
	_extra_sessions.erase(id)
	var controller: SessionController = session.controller
	controller.stop()
	if controller.history:
		controller.history.flush()
	if _coordinator:
		_log.add(AgentLog.CH_ACP, "%s closed" % _coordinator.label(id))
		_coordinator.unregister(id)
	if _mcp_server:
		_mcp_server.remove_session_token(id)
	if _tabs:
		_tabs.remove_session(id)


func _ask_copy_fate(id: String, copy: WorktreeSession, changed: PackedStringArray) -> void:
	var dialog := ConfirmationDialog.new()
	dialog.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	dialog.title = I18n.t("Changes of the separate copy")
	var shown := PackedStringArray(Array(changed).slice(0, 12))
	if changed.size() > 12:
		shown.append("…")
	dialog.dialog_text = I18n.t("«%s» changed %d files in its copy:\n%s\n\nApply them to the project as uncommitted changes, keep them only in the branch %s, or discard them?") % [_coordinator.label(id), changed.size(), "\n".join(shown), copy.info.branch]
	dialog.ok_button_text = I18n.t("Apply to the project")
	dialog.add_button(I18n.t("Keep the branch"), false, "keep")
	if _project_config.github_pull_requests:
		dialog.add_button(I18n.t("Push and open a PR"), false, "pr")
	dialog.add_button(I18n.t("Discard"), false, "discard")
	dialog.cancel_button_text = I18n.t("Cancel")
	dialog.confirmed.connect(func() -> void: _resolve_copy(id, copy, changed, "apply"))
	dialog.custom_action.connect(func(action: StringName) -> void:
		dialog.hide()
		_resolve_copy(id, copy, changed, String(action)))
	dialog.visibility_changed.connect(func() -> void:
		if not dialog.visible:
			EditorWindows.free_later.call_deferred(dialog))
	EditorInterface.get_base_control().add_child(dialog)
	dialog.popup_centered()


## Lo que eligió el usuario para la copia al cerrar su pestaña; después la pestaña se cierra.
func _resolve_copy(id: String, copy: WorktreeSession, changed: PackedStringArray, action: String) -> void:
	var label := _coordinator.label(id) if _coordinator else id
	match action:
		"apply":
			var error := await copy.apply_to_project()
			if error.is_empty():
				await copy.remove(true)
				_after_oneshot_restore(changed)
				_model.add_notice(I18n.t("The changes of «%s» are in the project now, uncommitted (%d files).") % [label, changed.size()])
			else:
				await copy.remove(false)
				_model.add_notice(error, ChatEntry.NoticeLevel.WARNING)
		"keep":
			await copy.remove(false)
			_model.add_notice(I18n.t("The changes of «%s» stay in the branch %s.") % [label, copy.info.branch])
		"pr":
			var body := "Changes made by the agent session \"%s\" of Godot Agent Harness in a separate copy.\n\nFiles:\n%s" % [label, "\n".join(Array(changed).map(func(path: String) -> String: return "- `%s`" % path))]
			var opened: Dictionary = await GithubReviews.new(EditorContext.project_path()).open_pull_request(str(copy.info.dir), str(copy.info.branch), str(copy.info.base_branch), label, body)
			await copy.remove(false)
			if str(opened.error).is_empty():
				_model.add_notice(I18n.t("Pull request opened with the changes of «%s»: %s") % [label, opened.url])
			else:
				_model.add_notice(I18n.t("%s The changes stay in the branch %s.") % [opened.error, copy.info.branch], ChatEntry.NoticeLevel.WARNING)
		"discard":
			await copy.remove(true)
		_:
			return
	var session: Dictionary = _extra_sessions.get(id, {})
	session.resolved = true
	_close_session_tab(id)


## Renombrar una pestaña (m7-53): el nombre es también el que usan los agentes en godot.sessions y
## godot.session_send, así que no se repite.
func _rename_session(id: String, name: String) -> void:
	var label := name if not name.is_empty() else _tabs.default_label(id)
	if _coordinator.label_taken(label, id):
		_model_of(id).add_notice(I18n.t("There is already a session called «%s»: pick another name.") % label, ChatEntry.NoticeLevel.WARNING)
		return
	_coordinator.register(id, label)
	_tabs.set_label(id, label)


## La sesión de quien llama a una tool godot.*: el token principal ("") es el de la primera.
## Una sesión que se cierra no deja breakpoints suyos ni el juego parado por ellos (m11-56).
func _on_agent_disconnected(id: String) -> void:
	if _debug_tools:
		var released: PackedStringArray = await _debug_tools.release_session("" if id == PRIMARY_SESSION else id)
		if not released.is_empty():
			_log.add(AgentLog.CH_STATE, "session %s closed: cleared its breakpoints %s" % [id, ", ".join(released)])


## El oráculo, armado la primera vez (m11-28): su controller es como el de una pestaña, con el id
## SecondOpinion.SESSION_ID para el server MCP; el historial guarda su conversación.
func _oracle() -> SecondOpinion:
	if _second_opinion == null:
		var model := SessionModel.new()
		var controller := _make_controller(model, SecondOpinion.SESSION_ID)
		_second_opinion = SecondOpinion.new(controller, model)
	return _second_opinion


## Reemplaza el perfil de Settings › Agentes › Segunda opinión en las verificaciones del editor
## (second_opinion_check): un agente falso sin tocar EditorSettings. Sin él, el de Settings.
var second_opinion_profile_override: AgentProfile


func _second_opinion_profile() -> AgentProfile:
	return second_opinion_profile_override if second_opinion_profile_override else _settings.second_opinion_profile()


## El contexto del diff para la segunda opinión: el turno en curso de `session` hasta ahora, o si no
## hay, el último turno con cambios. {diff, files} o {} sin snapshots.
func _turn_diff(session: String) -> Dictionary:
	var controller := _controller_of(session)
	if controller == null or controller.snapshots == null or not controller.snapshots.available:
		return {}
	var from := controller.current_turn_start
	var to := ""
	var files: PackedStringArray = []
	if not from.is_empty():
		var peeked: Dictionary = await controller.snapshots.peek(controller.session_key, from)
		to = str(peeked.get("tree", ""))
		for file: Dictionary in peeked.get("files", []):
			files.append(str(file.path))
	if to.is_empty() or files.is_empty():
		var last := controller.last_turn_changes
		from = str(last.get("start", ""))
		to = str(last.get("end", ""))
		files = PackedStringArray((last.get("files", []) as Array).map(func(file: Dictionary) -> String: return str(file.path)))
	if from.is_empty() or to.is_empty() or files.is_empty():
		return {}
	return {"diff": await controller.snapshots.patch(from, to), "files": files}


## godot.ask_second_opinion: la pregunta del agente de la pestaña `caller`.
func _ask_second_opinion_tool(caller: String, question: String, include_diff: bool, paths: Array) -> Dictionary:
	if caller == SecondOpinion.SESSION_ID:
		return {"ok": false, "error": "The second opinion can't ask for another one."}
	var context := {"paths": paths}
	if include_diff:
		context.merge(await _turn_diff(caller))
	return await _oracle().ask(question, context, _second_opinion_profile(), caller)


## Lo pide el usuario (aviso del fin de turno, tarjeta del plan, /second-opinion): `payload`
## {session, question?, plan?, diff?: bool}. La respuesta vuelve como aviso en esa pestaña, con
## «Send to the agent» y «Open the conversation»; no le llega sola al agente principal.
func _second_opinion_for_user(payload: Variant) -> void:
	var data: Dictionary = payload if payload is Dictionary else {}
	var session := str(data.get("session", PRIMARY_SESSION))
	var model := _model_of(session)
	if model == null:
		return
	var profile := _second_opinion_profile()
	if profile == null:
		model.add_notice(I18n.t("No agent is chosen for second opinions: pick one in Settings › Agents › Second opinion."), ChatEntry.NoticeLevel.WARNING,
			[{"id": SessionController.ACTION_EDIT_AGENT, "label": I18n.t("Open Settings")}])
		return
	var context := {"plan": str(data.get("plan", ""))}
	if bool(data.get("diff", false)):
		context.merge(await _turn_diff(session))
	var oracle := _oracle()
	var waiting: ChatEntry = model.add_notice(I18n.t("Asking %s for a second opinion…") % profile.label(), ChatEntry.NoticeLevel.INFO,
		[{"id": SessionController.ACTION_SECOND_OPINION_CANCEL, "label": I18n.t("Cancel")}])
	var result: Dictionary = await oracle.ask(str(data.get("question", "")), context, profile, session)
	model = _model_of(session)  # la pestaña pudo cerrarse mientras tanto
	if model == null:
		return
	SecondOpinion.fill_notice(waiting, result, session)
	model.notify_entry_changed(waiting)


func _session_of(caller: String) -> String:
	return PRIMARY_SESSION if caller.is_empty() else caller


func _controller_of(id: String) -> SessionController:
	if id == PRIMARY_SESSION:
		return _controller
	if id == SecondOpinion.SESSION_ID:  # sin pestaña: el server MCP lo autoriza con su política de solo lectura
		return _second_opinion.controller if _second_opinion else null
	var session: Dictionary = _extra_sessions.get(id, {})
	return session.get("controller")


## El id de la pestaña de un dock.
func _session_of_dock(dock: Control) -> String:
	if _tabs:
		for id: String in _tabs.ids():
			if _tabs.dock(id) == dock:
				return id
	return PRIMARY_SESSION


func _model_of(id: String) -> SessionModel:
	if id == PRIMARY_SESSION:
		return _model
	if id == SecondOpinion.SESSION_ID:
		return _second_opinion.model if _second_opinion else null
	var session: Dictionary = _extra_sessions.get(id, {})
	return session.get("model")


func _controllers() -> Array[SessionController]:
	var result: Array[SessionController] = []
	if _controller:
		result.append(_controller)
	for id: String in _extra_sessions:
		result.append(_extra_sessions[id].controller)
	return result


func _models() -> Array[SessionModel]:
	var result: Array[SessionModel] = []
	if _model:
		result.append(_model)
	for id: String in _extra_sessions:
		result.append(_extra_sessions[id].model)
	return result


## Coordinación de las tools godot.* entre sesiones: el juego para una a la vez (las demás esperan
## en cola) y los archivos que otra está editando, fuera de alcance.
## Una sesión en una copia aparte (m11-09) no puede usar las tools que editan o corren el proyecto
## del editor: se rechazan antes de pedir permiso.
func _precheck_tool(mcp_caller: String, tool_name: String) -> String:
	var copy: WorktreeSession = _extra_sessions.get(_session_of(mcp_caller), {}).get("copy")
	if copy and (_registry.group_of(tool_name) != PermissionPolicy.GROUP_READ or tool_name in RunTools.GAME_TOOLS):
		return "You work in a separate copy at %s: godot.%s acts on the project open in the editor, not on your copy. Edit the files in your copy and check them with Godot headless (\"$GODOT\" --headless --path %s --quit)." % [copy.info.project, tool_name, copy.info.project]
	return ""


func _guard_tool(mcp_caller: String, tool_name: String, args: Dictionary) -> String:
	var importing := await _wait_import(tool_name)
	if not importing.is_empty() or _coordinator == null:
		return importing
	var root := EditorInterface.get_edited_scene_root()
	var edited := root.scene_file_path if root else ""
	return await _coordinator.guard_tool(_session_of(mcp_caller), tool_name, _registry.group_of(tool_name), args, edited)


## Las tools que escriben esperan a que el editor termine de importar (m14-02): editar mientras
## importa pisa recursos a medio cargar. "" para seguir; si no termina a tiempo, el motivo.
func _wait_import(tool_name: String) -> String:
	if not _registry.group_of(tool_name) in [PermissionPolicy.GROUP_EDIT_SCENE, PermissionPolicy.GROUP_EDIT_FILES, PermissionPolicy.GROUP_PROJECT]:
		return ""
	var filesystem := EditorInterface.get_resource_filesystem()
	var deadline := Time.get_ticks_msec() + int(IMPORT_WAIT_S * 1000)
	while filesystem.is_scanning() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	if filesystem.is_scanning():
		return "EDITOR_IMPORTING: the editor is still importing assets after %d s. Retry godot.%s in a few seconds; editing now could overwrite half-loaded resources." % [IMPORT_WAIT_S, tool_name]
	return ""


## Lo que ve una sesión de las demás (godot.sessions).
func _describe_sessions(caller: String) -> String:
	if _coordinator == null:
		return "There is only one agent session open: yours."
	return _coordinator.describe(caller, _model_of)


func _send_to_session(caller: String, to: String, message: String) -> String:
	# El oráculo lee el proyecto (texto que puede traer instrucciones plantadas) y session_send es del
	# grupo read: sin esto le escribiría al agente de una pestaña sin sobre ni permiso (m11-28).
	if caller == SecondOpinion.SESSION_ID:
		return "The second opinion is read only: it can't send messages to other sessions."
	if _coordinator == null:
		return "There is only one agent session open."
	var target := _coordinator.find_by_label(to, caller)
	if target.is_empty():
		return "There is no other session called «%s»: godot.sessions lists them." % to
	var dock: Control = _tabs.dock(target) if _tabs else null
	var text := "[Message from «%s», another agent session open in this editor]\n%s" % [_coordinator.label(caller), message]
	if dock == null or not dock.call(&"deliver_message", text):
		return "«%s» is not connected to its agent: the message was not delivered." % to
	_model_of(target).add_notice(I18n.t("Message from «%s»: %s") % [_coordinator.label(caller), message.left(200)])
	_log.add(AgentLog.CH_MCP, "message %s → %s (%d characters)" % [_coordinator.label(caller), _coordinator.label(target), message.length()])
	return ""


## Avisos de una vez por proyecto (adapter.notice_after_session, m18-03): en los metadatos del
## proyecto del editor (.godot/, no se commitea).
func _notice_seen(key: String) -> bool:
	var settings := EditorInterface.get_editor_settings()
	var seen: Array = settings.get_project_metadata("godot_agent", "notices_seen", [])
	if key in seen:
		return true
	seen.append(key)
	settings.set_project_metadata("godot_agent", "notices_seen", seen)
	return false
