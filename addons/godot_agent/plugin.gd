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
const I18n := preload("core/i18n.gd")
const SessionHistory := preload("session/session_history.gd")
const SessionModel := preload("session/session_model.gd")
const SessionController := preload("session/session_controller.gd")
const EditorContext := preload("ui/editor_context.gd")
const EditorSync := preload("editor/editor_sync.gd")
const FsHandler := preload("acp/fs_handler.gd")
const PermissionPolicy := preload("session/permission_policy.gd")
const ProjectConfig := preload("config/project_config.gd")
const ChatEntry := preload("session/chat_entry.gd")
const ToolCall := preload("session/tool_call.gd")
const DiffDialog := preload("ui/diff_dialog.gd")
const McpServer := preload("mcp/mcp_server.gd")
const ToolRegistry := preload("mcp/tool_registry.gd")
const ReadTools := preload("mcp/tools/read_tools.gd")
const ApiTools := preload("mcp/tools/api_tools.gd")
const ProjectTools := preload("mcp/tools/project_tools.gd")
const FileTools := preload("mcp/tools/file_tools.gd")
const ResourceTools := preload("mcp/tools/resource_tools.gd")
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

const PLUGIN_NAME := "Agent"
const DOCK_TITLE := "Agent"
const LOG_PANEL_TITLE := "Agent Log"
## Runs del One-shot (D37): datos del usuario, fuera del repo.
const ONESHOT_STORE_DIR := "user://godot_agent/oneshot"
const ICON_NAME := &"Script"

var _export_plugin: AgentExportPlugin
var _surfaces: EditorSurfaces
var _settings: HarnessSettings
var _log: AgentLog
var _model: SessionModel
var _controller: SessionController
var _project_config: ProjectConfig
var _sync: EditorSync
var _diff_dialog: DiffDialog
var _mcp_server: McpServer
var _errors: ErrorCollector
var _playtest_debugger: PlaytestDebugger
var _run_tools: RunTools
var _pending_undo: Array[Dictionary] = []  # {tool, args, info, time}
var _review_annotations: ReviewAnnotations
var _oneshot: OneShotRun
var _settings_dialog: SettingsDialog
var _main_screen: Control
var _fs: FsHandler
var _registry: ToolRegistry
var _completion: CompletionService


func _enter_tree() -> void:
	PlaytestAutoload.remove_orphan(self)

	_export_plugin = AgentExportPlugin.new()
	_export_plugin.setup(_remove_playtest_autoload)
	add_export_plugin(_export_plugin)

	_settings = HarnessSettings.new(EditorInterface.get_editor_settings())
	I18n.setup(_settings.language())
	_log = AgentLog.new()
	_model = SessionModel.new()
	_controller = SessionController.new()
	_controller.setup(_model, _log, EditorContext.project_path())
	_controller.prompt_variables_provider = _prompt_variables
	_controller.history = SessionHistory.new()
	_project_config = ProjectConfig.load_or_default()
	_controller.policy = PermissionPolicy.new(_project_config.permissions)
	_apply_quota_settings()
	EditorInterface.get_editor_settings().settings_changed.connect(_on_editor_settings_changed)

	_sync = EditorSync.new()
	_sync.setup(_log)
	_sync.conflict_detected.connect(_on_conflict_detected)
	_sync.open_scene_modified.connect(_on_open_scene_modified)
	add_child(_sync)
	scene_saved.connect(_sync.note_scene_saved)
	_fs = FsHandler.new()
	_fs.setup(EditorContext.project_path(), _log)
	_fs.extra_roots = _project_config.extra_fs_roots
	_fs.buffer_reader = _sync.buffer_text
	_fs.after_write = _sync.after_agent_write
	_controller.set_fs_handler(_fs)
	_model.tool_call_changed.connect(_on_tool_call_changed)
	_diff_dialog = DiffDialog.new()
	_diff_dialog.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	EditorInterface.get_base_control().add_child(_diff_dialog)
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
	_oneshot.criteria = GameCriteria.resolve(_project_config.criteria)
	add_child(_oneshot)
	_model.harness_mode_changed.connect(_on_harness_mode_changed)

	var dock := AgentDockScene.instantiate()
	dock.setup(_model, _controller, _settings)
	dock.show_log_requested.connect(_show_log)
	dock.settings_requested.connect(_open_settings)
	dock.action_forwarded.connect(_on_dock_action)
	dock.submit_interceptor = _intercept_dock_prompt
	dock.retry_interceptor = _intercept_dock_retry
	_controller.after_login = _after_agent_login
	dock.can_switch_session = func() -> bool: return not _oneshot.is_active()
	dock.game_capture = _capture_game_for_dock
	_oneshot.changed.connect(func() -> void:
		if is_instance_valid(dock):
			dock.set_oneshot_active(_oneshot.is_active()))
	var log_panel := AgentLogPanelScene.instantiate()
	log_panel.setup(_log)
	# Los textos ya vienen traducidos por I18n: que el editor no los vuelva a traducir con los suyos.
	for surface: Node in [dock, log_panel]:
		surface.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED

	_surfaces = EditorSurfaces.new(self)
	_surfaces.side_slot = HarnessSettings.DOCK_SLOTS[_settings.dock_slot()]
	_surfaces.add(EditorSurfaces.EditorSurface.SIDE, dock, DOCK_TITLE, "godot_agent_dock")
	_surfaces.add(EditorSurfaces.EditorSurface.BOTTOM, log_panel, LOG_PANEL_TITLE, "godot_agent_log")
	_main_screen = AgentMainScreenScene.instantiate()
	_main_screen.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_main_screen.setup(_oneshot, _settings.accent_color(), _oneshot_defaults())
	_main_screen.diff_requested.connect(_diff_dialog.show_diff)
	_surfaces.add(EditorSurfaces.EditorSurface.MAIN_SCREEN, _main_screen, PLUGIN_NAME, "godot_agent_main", _get_plugin_icon())
	_restore_oneshot.call_deferred()

	_settings_dialog = SettingsDialog.new()
	_settings_dialog.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_settings_dialog.setup(_settings, _project_config)
	_settings_dialog.mcp_url_provider = func() -> String:
		return _mcp_server.url() if _mcp_server and _mcp_server.is_listening() else ""
	_settings_dialog.regenerate_token = _regenerate_mcp_token
	_settings_dialog.completion_metrics_provider = func() -> Array[Dictionary]:
		return _completion.metrics.summary() if _completion else ([] as Array[Dictionary])
	_settings_dialog.completion_metrics_reset = func() -> void:
		if _completion:
			_completion.metrics.clear()
	_settings_dialog.saved.connect(_on_settings_saved)
	EditorInterface.get_base_control().add_child(_settings_dialog)

	_completion = CompletionService.new()
	_completion.setup(_settings, _project_config, _log)
	add_child(_completion)


func _exit_tree() -> void:
	if EditorInterface.get_editor_settings().settings_changed.is_connected(_on_editor_settings_changed):
		EditorInterface.get_editor_settings().settings_changed.disconnect(_on_editor_settings_changed)
	if _completion:
		remove_child(_completion)
		_completion.queue_free()
		_completion = null
	if _oneshot:
		_oneshot.suspend()  # queda guardado para retomarlo al volver (D37)
		remove_child(_oneshot)
		_oneshot.queue_free()
		_oneshot = null
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
	if _settings_dialog:
		_settings_dialog.queue_free()
		_settings_dialog = null
	_main_screen = null
	_fs = null
	_registry = null
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
func _on_tool_call_changed(call: ToolCall, _group: ChatEntry) -> void:
	if _model.replaying:
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
		var call := _model.find_godot_tool_call(pending.tool, pending.args)
		if call:
			call.undo_info = pending.info
			_model.touch_tool_call(call)
			_pending_undo.erase(pending)
		elif now - int(pending.time) > PENDING_UNDO_TTL_MS:
			_pending_undo.erase(pending)


func _undo_tool_call(call_id: String) -> void:
	var call := _model.tool_call(call_id)
	if call == null or not call.can_undo():
		return
	var reason := EditorUndo.undo(call.undo_info)
	if reason.is_empty():
		call.undo_done = true
		_model.touch_tool_call(call)
		_log.add(AgentLog.CH_MCP, "undone: %s" % call.undo_info.get("action", ""))
	else:
		_model.add_notice(I18n.t("Could not undo «%s»: %s") % [call.undo_info.get("action", ""), reason], ChatEntry.NoticeLevel.WARNING)


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
	registry.authorizer = func(group: String, title: String, description: String) -> bool:
		return await _controller.authorize(group, title, description, {}, _project_config.permission_timeout_s)
	registry.register_provider(ReadTools.new())
	var api_tools := ApiTools.new()
	api_tools.doc_cache_path = ApiTools.editor_doc_cache_path()
	registry.register_provider(api_tools)
	var diagnostics := DiagnosticTools.new()
	diagnostics.setup(_errors, EditorContext.project_path())
	registry.register_provider(diagnostics)
	var edit_tools := SceneEditTools.new()
	edit_tools.on_action = _on_mcp_edit_action
	registry.register_provider(edit_tools)
	registry.register_provider(ProjectTools.new())
	var file_tools := FileTools.new()
	file_tools.on_file_written = _sync.after_agent_write
	file_tools.unsaved_buffer = _sync.buffer_text
	registry.register_provider(file_tools)
	registry.register_provider(ResourceTools.new())
	_run_tools = RunTools.new()
	_run_tools.setup(_errors, _playtest_debugger)
	_run_tools.max_image_side = _project_config.max_image_side
	_run_tools.cleanup = _remove_playtest_autoload
	registry.register_provider(_run_tools)
	_mcp_server = McpServer.new()
	_mcp_server.registry = registry
	_mcp_server.agent_log = _log
	add_child(_mcp_server)
	if _mcp_server.start(_settings.mcp_port()) == OK:
		_log.add_secret(_mcp_server.token)
	_controller.mcp_servers_provider = _mcp_servers


## Entradas `mcpServers` para session/new: HTTP si el agente lo soporta; si no, el shim stdio.
func _mcp_servers() -> Array:
	if _mcp_server == null or not _mcp_server.is_listening():
		return []
	if _model.supports_http_mcp():
		return [_mcp_server.http_server_entry()]
	var entry := StdioShimInstaller.server_entry(McpServer.SERVER_NAME, _mcp_server.url(), _mcp_server.token)
	if entry.is_empty():
		_log.add(AgentLog.CH_MCP, "could not prepare the stdio shim in user://: the agent will not have the godot.* tools")
		return []
	return [entry]


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


func _open_settings() -> void:
	_settings_dialog.open()


## La config del proyecto se aplica en caliente; los settings de usuario llegan por settings_changed.
func _on_settings_saved() -> void:
	_controller.policy.overrides = _project_config.permissions
	_fs.extra_roots = _project_config.extra_fs_roots
	_registry.max_output_chars = _project_config.max_output_chars
	_registry.max_image_side = _project_config.max_image_side
	_run_tools.max_image_side = _project_config.max_image_side
	_main_screen.call(&"set_defaults", _oneshot_defaults())
	_oneshot.loops.repeats = _project_config.loop_repeats
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
	_controller.quota.configure(_settings.quota_warn(), _settings.quota_pause(), _settings.quota_pause_enabled())


func _on_editor_settings_changed() -> void:
	if _completion and EditorInterface.get_editor_settings().check_changed_settings_in_group(HarnessSettings.PREFIX + "completion"):
		_completion.apply_settings()
	if _controller and EditorInterface.get_editor_settings().check_changed_settings_in_group(HarnessSettings.PREFIX + "quota"):
		_apply_quota_settings()
		if _oneshot:
			_oneshot.resume_auto = _settings.quota_resume_auto()


# --- One-shot ------------------------------------------------------------------------------------

## Elegir One-shot en el dock abre la pantalla Agent (ahí se escribe el objetivo).
func _on_harness_mode_changed(mode: SessionModel.HarnessMode) -> void:
	if mode == SessionModel.HarnessMode.ONESHOT and _oneshot and not _oneshot.is_active() and _surfaces:
		_surfaces.make_visible(EditorSurfaces.EditorSurface.MAIN_SCREEN)


## Un One-shot que quedó a medias (el editor se cerró o se cayó) vuelve en pausa.
func _restore_oneshot() -> void:
	if _oneshot == null or not _oneshot.restore_interrupted():
		return
	_model.add_notice(I18n.t("There is an unfinished One-shot: «%s». It is paused; «Resume One-shot» reopens the agent session.") % _oneshot.goal.left(80), ChatEntry.NoticeLevel.WARNING, [
		{"id": ACTION_ONESHOT_RESUME, "label": I18n.t("Resume One-shot")},
		{"id": ACTION_ONESHOT_SHOW, "label": I18n.t("Open Agent screen")},
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
		_model.add_notice(I18n.t("The One-shot is still running: pause or stop it from the Agent screen."), ChatEntry.NoticeLevel.INFO)
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


func _remove_playtest_autoload() -> void:
	PlaytestAutoload.unregister(self)
