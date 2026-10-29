@tool
extends EditorPlugin
## Raíz de composición del addon: crea los servicios y la UI, y los desarma al deshabilitar.

const AgentExportPlugin := preload("export/agent_export_plugin.gd")
const PlaytestAutoload := preload("playtest/playtest_autoload.gd")
const EditorSurfaces := preload("ui/editor_surfaces.gd")
const AgentDockScene := preload("ui/dock/agent_dock.tscn")
const AgentMainScreenScene := preload("ui/main_screen/agent_main_screen.tscn")
const AgentLogPanelScene := preload("ui/log_panel/agent_log_panel.tscn")
const AgentLog := preload("core/agent_log.gd")
const HarnessSettings := preload("core/harness_settings.gd")
const SettingsDialog := preload("ui/settings/settings_dialog.gd")
const ExtensionsWindow := preload("ui/extensions/extensions_window.gd")
const ClaudeExtensions := preload("extensions/claude_extensions.gd")
const SkillCatalog := preload("extensions/skill_catalog.gd")
const I18n := preload("core/i18n.gd")
const SessionHistory := preload("session/session_history.gd")
const SessionModel := preload("session/session_model.gd")
const SessionController := preload("session/session_controller.gd")
const EditorContext := preload("ui/editor_context.gd")
const EditorSync := preload("editor/editor_sync.gd")
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
const TurnSnapshots := preload("session/turn_snapshots.gd")
const InlineEdit := preload("editor/inline_edit.gd")
## Lo que trae @output: el final del panel Output.
const OUTPUT_MENTION_CHARS := 4000
const TurnReport := preload("session/turn_report.gd")
const WorktreeSession := preload("session/worktree_session.gd")
const GithubReviews := preload("core/github_reviews.gd")
const InlineEditMenu := preload("editor/inline_edit_menu.gd")
const McpServer := preload("mcp/mcp_server.gd")
const ToolRegistry := preload("mcp/tool_registry.gd")
const ReadTools := preload("mcp/tools/read_tools.gd")
const ApiTools := preload("mcp/tools/api_tools.gd")
const ProjectTools := preload("mcp/tools/project_tools.gd")
const AssetTools := preload("mcp/tools/asset_tools.gd")
const AssetStore := preload("core/asset_store.gd")
const FileTools := preload("mcp/tools/file_tools.gd")
const ResourceTools := preload("mcp/tools/resource_tools.gd")
const TilemapTools := preload("mcp/tools/tilemap_tools.gd")
const AnimationTools := preload("mcp/tools/animation_tools.gd")
const DiagnosticTools := preload("mcp/tools/diagnostic_tools.gd")
const SceneEditTools := preload("mcp/tools/scene_edit_tools.gd")
const RunTools := preload("mcp/tools/run_tools.gd")
const PlaytestDebugger := preload("playtest/playtest_debugger.gd")
const EditorUndo := preload("editor/editor_undo.gd")
const StdioShimInstaller := preload("mcp/stdio_shim_installer.gd")
const ErrorCollector := preload("core/error_collector.gd")
const ReviewAnnotations := preload("review/review_annotations.gd")
const ReviewStore := preload("review/review_store.gd")
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

const ACTION_CONFLICT_DIFF := "conflict_diff"
const ACTION_CONFLICT_USE_AGENT := "conflict_use_agent"
const ACTION_CONFLICT_KEEP_MINE := "conflict_keep_mine"
const ACTION_RELOAD_SCENE := "reload_scene"
const ACTION_UNDO_TOOL_CALL := "undo_tool_call"
const ACTION_ONESHOT_RESUME := "oneshot_resume"
const ACTION_ONESHOT_SHOW := "oneshot_show"
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

var _export_plugin: AgentExportPlugin
var _surfaces: EditorSurfaces
var _settings: HarnessSettings
var _log: AgentLog
var _model: SessionModel
var _controller: SessionController
var _project_config: ProjectConfig
var _sync: EditorSync
var _remote_activity: RemoteActivity
var _diff_dialog: DiffDialog
var _turn_dialog: TurnChangesDialog
## Snapshots por turno de todas las sesiones (m11-01); `available` queda en false sin git.
var _turn_snapshots: TurnSnapshots
var _mcp_server: McpServer
var _errors: ErrorCollector
var _diagnostics: DiagnosticTools
var _playtest_debugger: PlaytestDebugger
var _run_tools: RunTools
var _pending_undo: Array[Dictionary] = []  # {tool, args, info, time}
var _review_annotations: ReviewAnnotations
var _oneshot: OneShotRun
var _settings_dialog: SettingsDialog
var _extensions_window: ExtensionsWindow
var _main_screen: Control
var _fs: FsHandler
var _registry: ToolRegistry
var _completion: CompletionService
## Chat en línea en el Script Editor (m11-05).
var _inline_edit: InlineEdit
var _inline_menu: InlineEditMenu
var _updater: AddonUpdater
var _store: AssetStore
var _update_banner: UpdateBanner
## Varias sesiones a la vez (m7-44). La primera es `_model`/`_controller` (PRIMARY_SESSION), la del One-shot,
## la revisión y Remote Control; las otras: id -> {model, controller}.
var _coordinator: SessionCoordinator
var _tabs: SessionTabs
var _extra_sessions: Dictionary = {}
var _session_serial: int = 1


func _enter_tree() -> void:
	PlaytestAutoload.remove_orphan(self)

	_export_plugin = AgentExportPlugin.new()
	_export_plugin.setup(_remove_playtest_autoload)
	add_export_plugin(_export_plugin)

	_settings = HarnessSettings.new(EditorInterface.get_editor_settings())
	I18n.setup(_settings.language())
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
	scene_saved.connect(_sync.note_scene_saved)
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
	scene_saved.connect(_remote_activity.note_saved)
	resource_saved.connect(func(resource: Resource) -> void:
		if _remote_activity:
			_remote_activity.note_saved(resource.resource_path))
	_diff_dialog = DiffDialog.new()
	_diff_dialog.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	EditorInterface.get_base_control().add_child(_diff_dialog)
	_turn_dialog = TurnChangesDialog.new()
	_turn_dialog.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_turn_dialog.diff_requested.connect(_show_turn_diff)
	_turn_dialog.revert_requested.connect(func(data: Dictionary, path: String) -> void: _restore_turn(data, PackedStringArray([path])))
	EditorInterface.get_base_control().add_child(_turn_dialog)
	_playtest_debugger = PlaytestDebugger.new()
	# El juego ya leyó project.godot cuando su sesión de debug arranca: el autoload se quita ahí.
	_playtest_debugger.session_started.connect(_remove_playtest_autoload)
	_playtest_debugger.session_stopped.connect(_remove_playtest_autoload)
	add_debugger_plugin(_playtest_debugger)
	_start_mcp_server()

	_review_annotations = ReviewAnnotations.new()
	_review_annotations.setup(_controller.review, _model, _settings.accent_color())
	_review_annotations.action_requested.connect(_on_review_action)
	add_child(_review_annotations)

	_oneshot = OneShotRun.new()
	_oneshot.setup(_controller, EditorContext.project_path())
	_oneshot.after_restore = _after_oneshot_restore
	_oneshot.restart_session = func(lost_id: String) -> bool:
		var profile := _settings.active_profile()
		return profile != null and await _controller.reopen(profile, lost_id)
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
		_settings_dialog.open()
		_settings_dialog.open_registry(query))
	dock.extensions_requested.connect(_open_extensions)
	dock.action_forwarded.connect(_on_dock_action)
	dock.submit_interceptor = _intercept_dock_prompt
	dock.retry_interceptor = _intercept_dock_retry
	_controller.after_login = _after_agent_login
	dock.can_switch_session = func() -> bool: return not _oneshot.is_active()
	dock.game_capture = _capture_game_for_dock
	dock.context_provider = _context_for_mention
	_oneshot.changed.connect(func() -> void:
		if is_instance_valid(dock):
			dock.set_oneshot_active(_oneshot.is_active()))
	var log_panel := AgentLogPanelScene.instantiate()
	log_panel.setup(_log)
	_tabs = SessionTabs.new()
	_tabs.name = dock.name  # con la API vieja de docks, el título de la pestaña es el nombre del nodo
	_tabs.add_session(PRIMARY_SESSION, dock, _model, I18n.t("Session 1"))
	_tabs.new_session_requested.connect(_open_session_tab)
	_tabs.close_requested.connect(_close_session_tab)
	_tabs.rename_requested.connect(_rename_session)
	# Los textos ya vienen traducidos por I18n: que el editor no los vuelva a traducir con los suyos.
	for surface: Node in [_tabs, log_panel]:
		surface.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED

	_surfaces = EditorSurfaces.new(self)
	_surfaces.side_slot = HarnessSettings.DOCK_SLOTS[_settings.dock_slot()]
	_surfaces.add(EditorSurfaces.EditorSurface.SIDE, _tabs, DOCK_TITLE, "godot_agent_dock")
	_surfaces.add(EditorSurfaces.EditorSurface.BOTTOM, log_panel, LOG_PANEL_TITLE, "godot_agent_log")
	_main_screen = AgentMainScreenScene.instantiate()
	_main_screen.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_main_screen.setup(_oneshot, _settings.accent_color(), _oneshot_defaults())
	_main_screen.diff_requested.connect(_diff_dialog.show_diff)
	_main_screen.settings_requested.connect(_open_settings)
	_main_screen.agent_name = func() -> String:
		var profile := _settings.active_profile()
		return profile.display_name if profile else ""
	_settings.changed.connect(func(key: String) -> void:
		if _main_screen and key in [HarnessSettings.KEY_PROFILES, HarnessSettings.KEY_LAST_PROFILE]:
			_main_screen.refresh_agent())
	_surfaces.add(EditorSurfaces.EditorSurface.MAIN_SCREEN, _main_screen, PLUGIN_NAME, "godot_agent_main", _get_plugin_icon())
	_restore_oneshot.call_deferred()
	_continue_last_session.call_deferred(dock)

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
	EditorInterface.get_base_control().add_child(_settings_dialog)

	_extensions_window = ExtensionsWindow.new()
	_extensions_window.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_extensions_window.addon_servers_provider = _external_mcp_servers
	_extensions_window.asset_store = _asset_store()
	_extensions_window.is_claude_provider = func() -> bool:
		var profile := _settings.active_profile()
		return profile != null and ClaudeExtensions.is_claude_profile(profile.command, profile.args)
	_extensions_window.has_agent_provider = func() -> bool: return _settings.active_profile() != null
	_extensions_window.agents_requested.connect(func() -> void:
		_extensions_window.hide()
		_settings_dialog.open(SettingsDialog.SettingsSection.AGENTS))
	_extensions_window.agent_kind_provider = func() -> String:
		var profile := _settings.active_profile()
		return ClaudeExtensions.agent_kind(profile.command, profile.args, profile.id) if profile != null else ClaudeExtensions.AGENT_CLAUDE
	_extensions_window.new_session_requested.connect(func() -> void:
		if is_instance_valid(dock):
			dock.call(&"_on_new_session_pressed"))
	_extensions_window.disabled_skills_changed.connect(func(names: PackedStringArray) -> void:
		_project_config.disabled_skills = names
		_save_project_config())
	_extensions_window.mcp_settings_requested.connect(func() -> void: _settings_dialog.open(SettingsDialog.SettingsSection.MCP))
	EditorInterface.get_base_control().add_child(_extensions_window)

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
	add_context_menu_plugin(EditorContextMenuPlugin.CONTEXT_SLOT_SCRIPT_EDITOR_CODE, _inline_menu)


func _exit_tree() -> void:
	if EditorInterface.get_editor_settings().settings_changed.is_connected(_on_editor_settings_changed):
		EditorInterface.get_editor_settings().settings_changed.disconnect(_on_editor_settings_changed)
	if _completion:
		remove_child(_completion)
		_completion.queue_free()
		_completion = null
	if _inline_menu:
		remove_context_menu_plugin(_inline_menu)
		_inline_menu = null
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
	if _settings_dialog:
		_settings_dialog.queue_free()
		_settings_dialog = null
	if _extensions_window:
		_extensions_window.queue_free()
		_extensions_window = null
	_main_screen = null
	_fs = null
	_registry = null
	_diagnostics = null
	if _playtest_debugger:
		remove_debugger_plugin(_playtest_debugger)
		_playtest_debugger = null
	_run_tools = null
	PlaytestAutoload.unregister(self)

	if _export_plugin:
		remove_export_plugin(_export_plugin)
		_export_plugin = null

	if _surfaces:
		_surfaces.remove_all()
		_surfaces = null


## «+ contexto → Captura del juego»: el frame como Image, o el motivo (traducido) si no se puede.
func _capture_game_for_dock() -> Variant:
	if not EditorInterface.is_playing_scene():
		return I18n.t("No game is running.")
	if _run_tools == null or not _playtest_debugger.has_probe():
		return I18n.t("This run has no playtest autoload, so it cannot be captured. Run it from the agent, or enable «Use the playtest autoload also when running the game manually» in Settings → MCP server.")
	var frame: Variant = await _run_tools.capture_frame()
	return frame if frame is Image else I18n.t("Could not capture the game frame.")


## Justo antes de correr el juego: alta del autoload de playtest si el run lo pidió el harness
## (run_scene) o si Settings lo activa también para los runs manuales (spec §6).
func _build() -> bool:
	var requested := _run_tools != null and _run_tools.harness_requested
	if requested or (_project_config and _project_config.playtest_on_manual_runs):
		PlaytestAutoload.register(self)
	return true


## Solo con la API vieja (4.6 y 4.7). En 4.8+ la main screen es un EditorDock (ver EditorSurfaces).
func _has_main_screen() -> bool:
	return not EditorSurfaces.uses_dock_api(EditorSurfaces.EditorSurface.MAIN_SCREEN)


func _make_visible(visible: bool) -> void:
	if _surfaces:
		_surfaces.set_legacy_main_screen_visible(visible)


func _get_plugin_name() -> String:
	return PLUGIN_NAME


func _get_plugin_icon() -> Texture2D:
	return EditorInterface.get_editor_theme().get_icon(ICON_NAME, &"EditorIcons")


func _show_log() -> void:
	if _surfaces:
		_surfaces.make_visible(EditorSurfaces.EditorSurface.BOTTOM)


## Un tool call que escribió archivos terminó: el editor se pone al día (spec §8.1).
func _on_tool_call_changed(call: ToolCall, _group: ChatEntry, model: SessionModel = null) -> void:
	if (model if model else _model).replaying:
		return
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
		SessionController.ACTION_REINSTALL_AGENT:
			_settings_dialog.open()
			_settings_dialog.open_registry()
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
		SessionController.ACTION_TURN_RESTORE:
			_confirm_turn_restore(payload)
		SessionController.ACTION_TURN_REPORT:
			_save_turn_report(payload)
		RemoteActivity.ACTION_DIFF:
			var texts := _remote_activity.diff_texts(int(payload))
			_diff_dialog.show_diff(I18n.t("Changes from Remote Control"), I18n.t("before"), texts[0], I18n.t("now"), texts[1])
		RemoteActivity.ACTION_UNDO:
			_remote_activity.undo(int(payload))
		ACTION_ONESHOT_RESUME:
			_intercept_dock_retry()
		ACTION_ONESHOT_SHOW:
			if _surfaces:
				_surfaces.make_visible(EditorSurfaces.EditorSurface.MAIN_SCREEN)
		AgentDock.ACTION_REVIEW_FOCUS:
			if not _review_annotations.focus_finding(int(payload)):
				_model.add_notice(I18n.t("Could not open the finding."), ChatEntry.NoticeLevel.WARNING)
		AgentDock.ACTION_REVIEW_FIX_ALL:
			_fix_review_findings(_controller.review.findings.duplicate())
		AgentDock.ACTION_OPEN_RUN_FILE:
			if _surfaces:
				_surfaces.make_visible(EditorSurfaces.EditorSurface.MAIN_SCREEN)
			_main_screen.call(&"show_run_file", path)


## Botones de la tarjeta de un hallazgo en el Script Editor (spec §9.4).
func _on_review_action(action: String, finding: Dictionary) -> void:
	match action:
		ReviewAnnotations.ACTION_DISMISS:
			_controller.review.dismiss(int(finding.id))
		ReviewAnnotations.ACTION_ASK:
			if _can_send():
				_controller.send_prompt(ReviewStore.question_prompt(finding), [], false)
		ReviewAnnotations.ACTION_APPLY:
			var list: Array[Dictionary] = [finding]
			_fix_review_findings(list)


## Pasa a Construir y pide los arreglos; si el turno termina bien, esos hallazgos salen de la revisión.
func _fix_review_findings(list: Array[Dictionary]) -> void:
	if list.is_empty() or not _can_send():
		return
	var stop_reason := await _controller.send_in_mode(SessionModel.HarnessMode.BUILD, ReviewStore.fix_prompt(list))
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
			call = model.find_godot_tool_call(pending.tool, pending.args)
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
	registry.register_provider(ReadTools.new())
	var api_tools := ApiTools.new()
	api_tools.doc_cache_path = ApiTools.editor_doc_cache_path()
	registry.register_provider(api_tools, true)
	_diagnostics = DiagnosticTools.new()
	_diagnostics.setup(_errors, EditorContext.project_path())
	registry.register_provider(_diagnostics)
	var edit_tools := SceneEditTools.new()
	edit_tools.on_action = _on_mcp_edit_action
	registry.register_provider(edit_tools)
	registry.register_provider(ProjectTools.new(), true)
	var asset_tools := AssetTools.new()
	asset_tools.store = _asset_store()
	registry.register_provider(asset_tools, true)
	var file_tools := FileTools.new()
	file_tools.on_file_written = _sync.after_agent_write
	file_tools.unsaved_buffer = _sync.buffer_text
	registry.register_provider(file_tools, true)
	registry.register_provider(ResourceTools.new(), true)
	var tilemap_tools := TilemapTools.new()
	tilemap_tools.on_action = _on_mcp_edit_action
	registry.register_provider(tilemap_tools, true)
	var animation_tools := AnimationTools.new()
	animation_tools.on_action = _on_mcp_edit_action
	registry.register_provider(animation_tools, true)
	_run_tools = RunTools.new()
	_run_tools.setup(_errors, _playtest_debugger)
	_run_tools.max_image_side = _project_config.max_image_side
	_run_tools.cleanup = _remove_playtest_autoload
	registry.register_provider(_run_tools)
	registry.mark_extended(RunTools.GAME_TOOLS)
	var session_tools := SessionTools.new()
	# Por el campo y no por `registry`: el registro guarda la tool y la lambda no puede guardarlo a él.
	session_tools.caller = func() -> String: return _session_of(_registry.current_caller if _registry else "")
	session_tools.describe = _describe_sessions
	session_tools.send = _send_to_session
	registry.register_provider(session_tools, true)
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
		if model.supports_http_mcp():
			result.append(_mcp_server.http_server_entry(token))
		else:
			var entry := StdioShimInstaller.server_entry(McpServer.SERVER_NAME, _mcp_server.url(), token)
			if entry.is_empty():
				_log.add(AgentLog.CH_MCP, "could not prepare the stdio shim in user://: the agent will not have the godot.* tools")
			else:
				result.append(entry)
	for server: Dictionary in _external_mcp_servers():
		if not bool(server.enabled):
			continue
		var entry := ExternalMcpServers.to_acp(server, model.supports_http_mcp())
		if entry.is_empty():
			_log.add(AgentLog.CH_MCP, "%s left out: the agent doesn't take HTTP MCP servers" % server.name)
			model.add_notice(I18n.t("The MCP server «%s» was left out: this agent only takes stdio servers.") % server.name, ChatEntry.NoticeLevel.WARNING)
			continue
		for secret: String in ExternalMcpServers.secret_values(server):
			_log.add_secret(secret)
		result.append(entry)
	return result


## Servers de terceros del usuario y del proyecto (si se llaman igual, gana el del proyecto).
func _external_mcp_servers() -> Array:
	return ExternalMcpServers.merge(_settings.mcp_servers(), ExternalMcpServers.normalize_list(_project_config.mcp_servers))


func _external_mcp_names() -> PackedStringArray:
	var names: PackedStringArray = []
	for server: Dictionary in _external_mcp_servers():
		if bool(server.enabled):
			names.append(server.name)
	return names


func _prompt_variables() -> Dictionary:
	return {
		"project_name": str(ProjectSettings.get_setting("application/config/name", "")),
		"project_path": EditorContext.project_path(),
		"godot_version": Engine.get_version_info().string,
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


## `_meta` de session/new y session/load para Claude Code: las skills apagadas en el proyecto
## (m7-36) y que pida permiso para cada subagente, así el modo decide y se cuentan (m7-43).
func _session_meta(controller: SessionController = null) -> Dictionary:
	var profile := (controller if controller else _controller).profile()
	if profile == null or not ClaudeExtensions.is_claude_profile(profile.command, profile.args):
		return {}
	var settings := SkillCatalog.session_settings(_project_config.disabled_skills)
	settings["permissions"] = {"ask": Array(PermissionPolicy.SUBAGENT_ASK_RULES)}
	return {"claudeCode": {"options": {"settings": settings}}}


## El CLI corre con el entorno del perfil activo (CLAUDE_CONFIG_DIR y demás), como el agente.
func _open_extensions() -> void:
	var profile := _settings.active_profile()
	_extensions_window.extensions = ClaudeExtensions.new(EditorContext.project_path(), profile.resolved_env() if profile else {})
	_extensions_window.disabled_skills = _project_config.disabled_skills
	_extensions_window.open()


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
			confirm.queue_free.call_deferred())
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
	EditorInterface.save_all_scenes()
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


func _open_settings() -> void:
	_settings_dialog.open()


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


func _restore_oneshot() -> void:
	if _oneshot == null or not _oneshot.restore_interrupted():
		return
	_model.add_notice(I18n.t("There is an unfinished One-shot: «%s». It is paused; «Resume One-shot» reopens the agent session.") % _oneshot.goal.left(80), ChatEntry.NoticeLevel.WARNING, [
		{"id": ACTION_ONESHOT_RESUME, "label": I18n.t("Resume One-shot")},
		{"id": ACTION_ONESHOT_SHOW, "label": I18n.t("Open One-shot screen")},
	])


## Con un One-shot en curso, lo que se escribe en el dock guía al agente del run (oneshot.guide).
func _intercept_dock_prompt(text: String) -> bool:
	if _oneshot == null or not _oneshot.is_active():
		return false
	_oneshot.guide(text)
	return true


## Con un One-shot en curso, «Reintentar» retoma el run en su sesión en lugar de abrir una en blanco.
func _intercept_dock_retry() -> bool:
	if _oneshot == null or not _oneshot.is_active():
		return false
	if _oneshot.can_resume():
		_oneshot.resume()
	else:
		_model.add_notice(I18n.t("The One-shot is still running: pause or stop it from the One-shot screen."), ChatEntry.NoticeLevel.INFO)
	return true


## Login hecho desde el dock o desde «Cambiar de cuenta»: si hay un One-shot esperando, retoma su
## sesión con la cuenta nueva (m6-15).
func _after_agent_login() -> bool:
	if _oneshot == null or not _oneshot.is_active() or not _oneshot.can_resume():
		return false
	_oneshot.switch_account()
	return true


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
			return text.right(OUTPUT_MENTION_CHARS).strip_edges()
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
	var reason: String = await controller.send_prompt(prompt)
	return {"text": controller.agent_text_since(first), "error": "" if reason == "end_turn" else I18n.t("The turn ended with «%s».") % reason}


## «Iniciar sesión» del Alt+I: la abre en la pestaña activa del dock, como su botón.
func _start_inline_session() -> bool:
	var id := _active_session_id()
	var dock: Control = _tabs.dock(id) if _tabs else null
	if dock == null:
		return false
	await dock.call(&"_start_session")
	var controller := _controller_of(id)
	return controller != null and controller.is_connected_to_agent()


# --- cambios por turno (m11-01, m11-02) ------------------------------------------------------------

func _show_turn_diff(data: Dictionary, path: String) -> void:
	var snapshots := _snapshots_of(str(data.get("session", PRIMARY_SESSION)))
	var before := await snapshots.text_at(str(data.start), path)
	var full := snapshots.git.root.path_join(path)
	var now := FileAccess.get_file_as_string(full) if FileAccess.file_exists(full) else ""
	_diff_dialog.show_diff(path, I18n.t("before the turn"), before, I18n.t("now"), now)


## Los snapshots de una sesión: los del proyecto, o los de su copia (m11-09).
func _snapshots_of(session: String) -> TurnSnapshots:
	var controller := _controller_of(session)
	return controller.snapshots if controller and controller.snapshots else _turn_snapshots


## Reporte del turno (m11-06) en res://.godot_agent/reports/<fecha>/, y se abre su carpeta.
func _save_turn_report(data: Dictionary) -> void:
	var model := _model_of(str(data.get("session", PRIMARY_SESSION)))
	if model == null:
		return
	var collected := TurnReport.collect(model, int(data.get("first_entry", 0)))
	var now := Time.get_datetime_string_from_system()
	var project := str(ProjectSettings.get_setting("application/config/name", EditorContext.project_path().get_file()))
	var path := TurnReport.write(TurnReport.DIR, now.replace(":", "-").replace("T", "_"), "Turn report · %s · %s" % [project, now.replace("T", " ")], collected, data.get("files", []))
	if path.is_empty():
		model.add_notice(I18n.t("Could not save the report in %s.") % TurnReport.DIR, ChatEntry.NoticeLevel.ERROR)
		return
	model.add_notice(I18n.t("Report saved in %s.") % path.get_base_dir())
	OS.shell_show_in_file_manager(ProjectSettings.globalize_path(path))


## Volver atrás todo un turno pisa también lo que vino después en esos archivos: se confirma. Deshacer
## una vuelta atrás (`undo` en data) no pregunta.
func _confirm_turn_restore(data: Dictionary) -> void:
	if data.get("undo", false):
		_restore_turn(data)
		return
	var confirm := ConfirmationDialog.new()
	confirm.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	confirm.title = I18n.t("Go back to before this turn")
	confirm.dialog_text = I18n.t("The project's files go back to how they were before this turn, including what changed after it (by the agent or by you). Files .gitignore leaves out are not touched. You can undo it from the chat.")
	confirm.ok_button_text = I18n.t("Go back")
	confirm.cancel_button_text = I18n.t("Cancel")
	confirm.confirmed.connect(_restore_turn.bind(data))
	confirm.visibility_changed.connect(func() -> void:
		if not confirm.visible:
			confirm.queue_free.call_deferred())
	EditorInterface.get_base_control().add_child(confirm)
	confirm.popup_centered()


## Deja los archivos (todos o `paths`) como en el snapshot `data.start`, recarga lo abierto, avisa en
## el chat de esa sesión (con «Deshacer») y le deja una nota al agente para su próximo turno.
func _restore_turn(data: Dictionary, paths: PackedStringArray = []) -> void:
	var session := str(data.get("session", PRIMARY_SESSION))
	var model := _model_of(session)
	var snapshots := _snapshots_of(session)
	var result: Dictionary = await snapshots.restore(session, str(data.start), paths)
	if result.is_empty():
		if model:
			model.add_notice(I18n.t("Could not go back: git failed."), ChatEntry.NoticeLevel.ERROR)
		return
	var changed: PackedStringArray = result.changed
	if snapshots == _turn_snapshots:  # en una copia no hay nada abierto en el editor
		_after_oneshot_restore(changed)
	if paths.size() == 1:
		_turn_dialog.mark_reverted(paths[0])
	if changed.is_empty() or model == null:
		return
	var names := ", ".join(changed)
	var undo := {"session": session, "start": result.before, "undo": true}
	model.add_notice(I18n.t("Went back: %s") % names, ChatEntry.NoticeLevel.INFO, [{"id": SessionController.ACTION_TURN_RESTORE, "label": I18n.t("Undo"), "data": undo}])
	var controller := _controller_of(session)
	if controller and not data.get("undo", false):
		controller.note_for_agent("[The user reverted these project files to how they were before one of your earlier turns: %s. Re-read them before editing them again.]" % names)


func _remove_playtest_autoload() -> void:
	PlaytestAutoload.unregister(self)


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
	controller.permissions_changed.connect(func() -> void: _on_permissions_changed(_controller_of(id)))
	controller.external_mcp_names = _external_mcp_names()
	controller.quota.configure(_settings.quota_warn(), _settings.quota_pause(), _settings.quota_pause_enabled())
	var fs := FsHandler.new()
	fs.setup(root, _log)
	fs.extra_roots = _project_config.extra_fs_roots
	if copy == null:  # en una copia (m11-09) no hay buffers del editor que sincronizar
		fs.buffer_reader = _sync.buffer_text
		fs.after_write = _sync.after_agent_write
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
	controller.file_guard = func(paths: PackedStringArray) -> String: return _claim_files(id, paths)
	controller.snapshots = _turn_snapshots if _project_config.turn_snapshots else null
	controller.turn_verifier = func(since_unix: int) -> String:
		if _diagnostics == null or not _project_config.verify_after_turn:
			return ""
		return await _diagnostics.verify_changed_scripts(since_unix)
	return _finish_controller(controller, model, id)


func _finish_controller(controller: SessionController, model: SessionModel, id: String) -> SessionController:
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
	_session_serial += 1
	var id := "s%d" % _session_serial
	var pattern := I18n.t("Session %d (copy)") if copy else I18n.t("Session %d")
	var label := pattern % _session_serial
	while _label_taken(label, id):  # alguna otra se renombró así
		_session_serial += 1
		label = pattern % _session_serial
	var model := SessionModel.new()
	var controller := _make_controller(model, id, copy)
	_extra_sessions[id] = {"model": model, "controller": controller, "copy": copy}
	_coordinator.register(id, label)
	var dock := AgentDockScene.instantiate()
	dock.allow_oneshot = false
	dock.setup(model, controller, _settings)
	dock.show_log_requested.connect(_show_log)
	dock.settings_requested.connect(_open_settings)
	dock.new_tab_requested.connect(_open_session_tab)
	dock.extensions_requested.connect(_open_extensions)
	dock.action_forwarded.connect(_on_dock_action)
	dock.game_capture = _capture_game_for_dock
	dock.context_provider = _context_for_mention
	_tabs.add_session(id, dock, model, label)
	_log.add(AgentLog.CH_ACP, "%s opened" % label)
	if copy:
		model.add_notice(I18n.t("This session works in a separate copy of the project, %s, on the branch %s (from your last commit: uncommitted changes aren't in it). The open editor isn't touched. When you close the tab you choose whether to apply its changes to the project.") % [copy.info.project, copy.info.branch])
		controller.note_for_agent("[You work in a separate git worktree of the project at %s (branch %s), not in the project open in the editor. Edit files there with your own tools. The godot.* tools that edit scenes or files, change the project or run the game act on the editor's project, so they are not available to you. To check your work run Godot headless on your folder, for example: \"$GODOT\" --headless --path %s --quit (it imports the project and reports script errors).]" % [copy.info.project, copy.info.branch, copy.info.project])


## Cerrar una pestaña. Una sesión en una copia (m11-09) primero commitea lo suyo en su rama y, si
## cambió algo, pregunta qué hacer; `ask` en false (al apagar el plugin) cierra sin tocar la copia.
func _close_session_tab(id: String, ask: bool = true) -> void:
	var session: Dictionary = _extra_sessions.get(id, {})
	if session.is_empty():
		return
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
			dialog.queue_free.call_deferred())
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
	if _label_taken(label, id):
		_model_of(id).add_notice(I18n.t("There is already a session called «%s»: pick another name.") % label, ChatEntry.NoticeLevel.WARNING)
		return
	_coordinator.register(id, label)
	_tabs.set_label(id, label)


func _label_taken(label: String, except: String) -> bool:
	for other: String in _coordinator.sessions():
		if other != except and _coordinator.label(other).to_lower() == label.to_lower():
			return true
	return false


## La sesión de quien llama a una tool godot.*: el token principal ("") es el de la primera.
func _session_of(caller: String) -> String:
	return PRIMARY_SESSION if caller.is_empty() else caller


func _controller_of(id: String) -> SessionController:
	if id == PRIMARY_SESSION:
		return _controller
	var session: Dictionary = _extra_sessions.get(id, {})
	return session.get("controller")


func _model_of(id: String) -> SessionModel:
	if id == PRIMARY_SESSION:
		return _model
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


## "" si la sesión `id` puede escribir `paths` (quedan suyos en el turno); si no, el nombre de la
## que los está editando.
func _claim_files(id: String, paths: PackedStringArray) -> String:
	if _coordinator == null or not _coordinator.is_shared():
		return ""
	var taken := _coordinator.claim_files(id, paths)
	return "" if taken.is_empty() else _coordinator.label(str(taken.values()[0]))


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
	if _coordinator == null or not _coordinator.is_shared():
		return ""
	var caller := _session_of(mcp_caller)
	if tool_name == "run_scene":
		var holder: String = await _coordinator.acquire_game(caller)
		if not holder.is_empty():
			return "The game is in use by «%s»: it launched it and it's still running. Try again when it stops (godot.sessions shows it), or work on something else meanwhile." % _coordinator.label(holder)
		return ""
	if tool_name == "stop_scene" or tool_name == "capture_game_frame" or tool_name in RunTools.GAME_TOOLS:
		var owner := _coordinator.game_owner()
		if not owner.is_empty() and owner != caller:
			return "The running game belongs to «%s». Run your own with run_scene when it stops (godot.sessions shows it)." % _coordinator.label(owner)
		return ""
	var group := _registry.group_of(tool_name)
	if not group in [PermissionPolicy.GROUP_EDIT_SCENE, PermissionPolicy.GROUP_EDIT_FILES, PermissionPolicy.GROUP_PROJECT]:
		return ""
	var paths := SessionCoordinator.paths_in_args(args)
	if paths.is_empty() and group == PermissionPolicy.GROUP_EDIT_SCENE:
		var root := EditorInterface.get_edited_scene_root()
		if root and not root.scene_file_path.is_empty():
			paths.append(root.scene_file_path)
	if group == PermissionPolicy.GROUP_PROJECT:
		paths.append("res://project.godot")
	var taken := _coordinator.claim_files(caller, paths)
	if taken.is_empty():
		return ""
	var path: String = taken.keys()[0]
	return "%s is being edited by «%s» in its current turn. Don't touch it until that turn ends: work on something else, or coordinate with godot.session_send (godot.sessions lists who edits what)." % [path, _coordinator.label(str(taken[path]))]


## Lo que ve una sesión de las demás (godot.sessions).
func _describe_sessions(caller: String) -> String:
	if _coordinator == null or not _coordinator.is_shared():
		return "There is only one agent session open: yours."
	var lines: PackedStringArray = ["You are «%s». Other agent sessions open in this editor:" % _coordinator.label(caller)]
	for id: String in _coordinator.sessions():
		if id == caller:
			continue
		var model: SessionModel = _model if id == PRIMARY_SESSION else _extra_sessions[id].model
		var state := "working" if model.is_busy() else ("idle" if model.state == SessionModel.SessionState.READY else "not connected")
		var line := "- «%s» · %s mode · %s" % [_coordinator.label(id), SessionModel.HARNESS_MODE_LABELS[model.harness_mode], state]
		if not model.title.strip_edges().is_empty():
			line += " · on: " + model.title.strip_edges()
		var files := _coordinator.files_of(id)
		if not files.is_empty():
			line += "\n  editing: " + ", ".join(Array(files).map(func(path: String) -> String: return ProjectSettings.localize_path(path)))
		lines.append(line)
	var owner := _coordinator.game_owner()
	lines.append("Game: " + ("not running" if owner.is_empty() else "running for «%s»" % _coordinator.label(owner)))
	var mine := _coordinator.files_of(caller)
	if not mine.is_empty():
		lines.append("Files you hold in this turn: " + ", ".join(Array(mine).map(func(path: String) -> String: return ProjectSettings.localize_path(path))))
	return "\n".join(lines)


func _send_to_session(caller: String, to: String, message: String) -> String:
	if _coordinator == null:
		return "There is only one agent session open."
	var target := ""
	for id: String in _coordinator.sessions():
		if _coordinator.label(id).to_lower() == to.to_lower() and id != caller:
			target = id
	if target.is_empty():
		return "There is no other session called «%s»: godot.sessions lists them." % to
	var dock: Control = _tabs.dock(target) if _tabs else null
	var text := "[Message from «%s», another agent session open in this editor]\n%s" % [_coordinator.label(caller), message]
	if dock == null or not dock.call(&"deliver_message", text):
		return "«%s» is not connected to its agent: the message was not delivered." % to
	var model: SessionModel = _model if target == PRIMARY_SESSION else _extra_sessions[target].model
	model.add_notice(I18n.t("Message from «%s»: %s") % [_coordinator.label(caller), message.left(200)])
	_log.add(AgentLog.CH_MCP, "message %s → %s (%d characters)" % [_coordinator.label(caller), _coordinator.label(target), message.length()])
	return ""
