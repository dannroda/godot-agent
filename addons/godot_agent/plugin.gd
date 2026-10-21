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
const DiagnosticTools := preload("mcp/tools/diagnostic_tools.gd")
const SceneEditTools := preload("mcp/tools/scene_edit_tools.gd")
const RunTools := preload("mcp/tools/run_tools.gd")
const PlaytestDebugger := preload("playtest/playtest_debugger.gd")
const EditorUndo := preload("editor/editor_undo.gd")
const StdioShimInstaller := preload("mcp/stdio_shim_installer.gd")
const ErrorCollector := preload("core/error_collector.gd")

const ACTION_CONFLICT_DIFF := "conflict_diff"
const ACTION_CONFLICT_USE_AGENT := "conflict_use_agent"
const ACTION_CONFLICT_KEEP_MINE := "conflict_keep_mine"
const ACTION_RELOAD_SCENE := "reload_scene"
const ACTION_UNDO_TOOL_CALL := "undo_tool_call"
## Acciones de edición del server MCP que todavía no se unieron a su tool call (llegan antes).
const PENDING_UNDO_TTL_MS := 60000
## Kinds de tool call que escriben archivos: al completarse se sincroniza el editor.
const WRITING_KINDS: PackedStringArray = ["edit", "delete", "move"]

const PLUGIN_NAME := "Agent"
const DOCK_TITLE := "Agent"
const LOG_PANEL_TITLE := "Agent Log"
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


func _enter_tree() -> void:
	PlaytestAutoload.remove_orphan(self)

	_export_plugin = AgentExportPlugin.new()
	_export_plugin.setup(_remove_playtest_autoload)
	add_export_plugin(_export_plugin)

	_settings = HarnessSettings.new(EditorInterface.get_editor_settings())
	_log = AgentLog.new()
	_model = SessionModel.new()
	_controller = SessionController.new()
	_controller.setup(_model, _log, EditorContext.project_path())
	_controller.prompt_variables_provider = _prompt_variables
	_project_config = ProjectConfig.load_or_default()
	_controller.policy = PermissionPolicy.new(_project_config.permissions)

	_sync = EditorSync.new()
	_sync.setup(_log)
	_sync.conflict_detected.connect(_on_conflict_detected)
	_sync.open_scene_modified.connect(_on_open_scene_modified)
	add_child(_sync)
	var fs := FsHandler.new()
	fs.setup(EditorContext.project_path(), _log)
	fs.extra_roots = _project_config.extra_fs_roots
	fs.buffer_reader = _sync.buffer_text
	fs.after_write = _sync.after_agent_write
	_controller.set_fs_handler(fs)
	_model.tool_call_changed.connect(_on_tool_call_changed)
	_diff_dialog = DiffDialog.new()
	EditorInterface.get_base_control().add_child(_diff_dialog)
	_playtest_debugger = PlaytestDebugger.new()
	# El juego ya leyó project.godot cuando su sesión de debug arranca: el autoload se quita ahí.
	_playtest_debugger.session_started.connect(_remove_playtest_autoload)
	_playtest_debugger.session_stopped.connect(_remove_playtest_autoload)
	add_debugger_plugin(_playtest_debugger)
	_start_mcp_server()

	var dock := AgentDockScene.instantiate()
	dock.setup(_model, _controller, _settings)
	dock.show_log_requested.connect(_show_log)
	dock.action_forwarded.connect(_on_dock_action)
	var log_panel := AgentLogPanelScene.instantiate()
	log_panel.setup(_log)

	_surfaces = EditorSurfaces.new(self)
	_surfaces.add(EditorSurfaces.Surface.SIDE, dock, DOCK_TITLE, "godot_agent_dock")
	_surfaces.add(EditorSurfaces.Surface.BOTTOM, log_panel, LOG_PANEL_TITLE, "godot_agent_log")
	_surfaces.add(
		EditorSurfaces.Surface.MAIN_SCREEN, AgentMainScreenScene.instantiate(), PLUGIN_NAME, "godot_agent_main", _get_plugin_icon()
	)


func _exit_tree() -> void:
	if _controller:
		_controller.stop()
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
	if _diff_dialog:
		_diff_dialog.queue_free()
		_diff_dialog = null
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


## Justo antes de correr el juego: alta del autoload de playtest si el run lo pidió el harness
## (run_scene) o si Settings lo activa también para los runs manuales (spec §6).
func _build() -> bool:
	var requested := _run_tools != null and _run_tools.harness_requested
	if requested or (_project_config and _project_config.playtest_on_manual_runs):
		PlaytestAutoload.register(self)
	return true


## Solo con la API vieja (4.4–4.7). En 4.8+ la main screen es un EditorDock (ver EditorSurfaces).
func _has_main_screen() -> bool:
	return not EditorSurfaces.uses_dock_api(EditorSurfaces.Surface.MAIN_SCREEN)


func _make_visible(visible: bool) -> void:
	if _surfaces:
		_surfaces.set_legacy_main_screen_visible(visible)


func _get_plugin_name() -> String:
	return PLUGIN_NAME


func _get_plugin_icon() -> Texture2D:
	return EditorInterface.get_editor_theme().get_icon(ICON_NAME, &"EditorIcons")


func _show_log() -> void:
	if _surfaces:
		_surfaces.make_visible(EditorSurfaces.Surface.BOTTOM)


## Un tool call que escribió archivos terminó: el editor se pone al día (spec §8.1).
func _on_tool_call_changed(call: ToolCall, _group: ChatEntry) -> void:
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
		"%s tiene cambios sin guardar y el agente lo modificó en disco. No se pisó nada." % res_path,
		ChatEntry.Level.WARNING,
		[
			{"id": ACTION_CONFLICT_DIFF, "label": "Ver diff", "data": data},
			{"id": ACTION_CONFLICT_USE_AGENT, "label": "Usar la del agente", "data": data},
			{"id": ACTION_CONFLICT_KEEP_MINE, "label": "Mantener la mía", "data": data},
		]
	)


func _on_open_scene_modified(res_path: String) -> void:
	_model.add_notice(
		"El agente modificó en disco la escena abierta %s. Para escenas abiertas debería usar las tools godot.*." % res_path,
		ChatEntry.Level.WARNING,
		[{"id": ACTION_RELOAD_SCENE, "label": "Recargar escena", "data": {"path": res_path}}]
	)


func _on_dock_action(action: String, payload: Variant) -> void:
	var path := str(payload.get("path", "")) if payload is Dictionary else ""
	match action:
		ACTION_CONFLICT_DIFF:
			var buffer: Variant = _sync.buffer_text(ProjectSettings.globalize_path(path))
			_diff_dialog.show_diff("Conflicto: " + path.get_file(), "tu versión", str(buffer) if buffer != null else "", "versión del agente", _sync.conflict_disk_text(path))
		ACTION_CONFLICT_USE_AGENT:
			_sync.resolve_use_disk(path)
		ACTION_CONFLICT_KEEP_MINE:
			_sync.resolve_keep_buffer(path)
		ACTION_RELOAD_SCENE:
			_sync.reload_scene(path)
		ACTION_UNDO_TOOL_CALL:
			_undo_tool_call(str(payload))


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
		_log.add(AgentLog.CH_MCP, "deshecho: %s" % call.undo_info.get("action", ""))
	else:
		_model.add_notice("No se pudo deshacer «%s»: %s" % [call.undo_info.get("action", ""), reason], ChatEntry.Level.WARNING)


## Server MCP con las tools godot.* (spec §5). La política de permisos se aplica del lado del server
## con el modo actual del harness; "ask" muestra una tarjeta y vence a los permission_timeout_s.
func _start_mcp_server() -> void:
	_errors = ErrorCollector.new()
	_errors.start()
	var registry := ToolRegistry.new()
	registry.agent_log = _log
	registry.max_output_chars = _project_config.max_output_chars
	registry.max_image_side = _project_config.max_image_side
	registry.authorizer = func(group: String, title: String, description: String) -> bool:
		return await _controller.authorize(group, title, description, {}, _project_config.permission_timeout_s)
	registry.register_provider(ReadTools.new())
	var diagnostics := DiagnosticTools.new()
	diagnostics.setup(_errors, EditorContext.project_path())
	registry.register_provider(diagnostics)
	var edit_tools := SceneEditTools.new()
	edit_tools.on_action = _on_mcp_edit_action
	registry.register_provider(edit_tools)
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
		_log.add(AgentLog.CH_MCP, "no se pudo preparar el shim stdio en user://: el agente no tendrá las tools godot.*")
		return []
	return [entry]


func _prompt_variables() -> Dictionary:
	return {
		"project_name": str(ProjectSettings.get_setting("application/config/name", "")),
		"project_path": EditorContext.project_path(),
		"godot_version": Engine.get_version_info().string,
	}


func _remove_playtest_autoload() -> void:
	PlaytestAutoload.unregister(self)
