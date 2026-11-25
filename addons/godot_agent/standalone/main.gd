extends Control
## El dock fuera del editor (m20-04): las mismas pestañas de sesión en una ventana propia, cada una con
## su agente y su cuenta. Se abre con el binario del editor, sin --editor:
##   godot --path <proyecto> res://addons/godot_agent/standalone/main.tscn [-- --project=<carpeta>]
## Con el editor abierto en la carpeta, usa su MCP para leer (m20-05); si no, el agente usa sus tools de
## archivos y shell, con los permisos, las fotos por turno y los cambios del turno del harness.

const AcpRegistry := preload("../core/acp_registry.gd")
const AgentLog := preload("../core/agent_log.gd")
const HarnessSettings := preload("../core/harness_settings.gd")
const I18n := preload("../core/i18n.gd")
const AccountQuotaBook := preload("../core/account_quota_book.gd")
const ModeModels := preload("../core/mode_models.gd")
const ProjectConfig := preload("../config/project_config.gd")
const SessionModel := preload("../session/session_model.gd")
const SessionController := preload("../session/session_controller.gd")
const SessionCoordinator := preload("../session/session_coordinator.gd")
const SessionHistory := preload("../session/session_history.gd")
const PermissionPolicy := preload("../session/permission_policy.gd")
const TurnSnapshots := preload("../session/turn_snapshots.gd")
const FsHandler := preload("../acp/fs_handler.gd")
const TerminalHandler := preload("../acp/terminal_handler.gd")
const EditorContext := preload("../ui/editor_context.gd")
const SessionTabs := preload("../ui/dock/session_tabs.gd")
const SettingsDialog := preload("../ui/settings/settings_dialog.gd")
const DiffDialog := preload("../ui/diff_dialog.gd")
const TurnChangesDialog := preload("../ui/turn_changes_dialog.gd")
const TurnChanges := preload("../ui/turn_changes.gd")
const TurnCounter := preload("../ui/turn_counter.gd")
const ToolCall := preload("../session/tool_call.gd")
const AgentDockScene := preload("../ui/dock/agent_dock.tscn")
const McpServer := preload("../mcp/mcp_server.gd")
const McpPublication := preload("../mcp/mcp_publication.gd")
const StdioShimInstaller := preload("../mcp/stdio_shim_installer.gd")

## Al lado de los datos del editor, compartido por todos los proyectos que se abran así; los perfiles
## del editor viven en EditorSettings y no se comparten.
const SETTINGS_FILE := "godot_agent/standalone.cfg"
const KEY_LAST_PROJECT := "standalone_last_project"

var _settings: HarnessSettings
var _log: AgentLog
var _config: ProjectConfig
var _coordinator: SessionCoordinator
var _snapshots: TurnSnapshots
var _tabs: SessionTabs
var _settings_dialog: SettingsDialog
var _turn_changes: TurnChanges
var _turn_counter: TurnCounter
var _sessions: Dictionary = {}  # id → {model, controller}
var _serial := 0


func _ready() -> void:
	# Diálogos y menús en ventanas del sistema, como en el editor; un juego los embebe por defecto.
	get_window().gui_embed_subwindows = false
	_settings =HarnessSettings.new(null, settings_path())
	I18n.setup(_settings.language(), "")
	EditorContext.project_root = project_from_args(OS.get_cmdline_user_args(), str(_settings.get_value(KEY_LAST_PROJECT, "")))
	var root := EditorContext.project_path()
	_settings.set_value(KEY_LAST_PROJECT, root)
	get_window().title = "Godot Agent · %s" % root.get_file()
	_log = AgentLog.new()
	# shortcut: los permisos y reglas del proyecto se leen de res://; con --project a otra carpeta, los de por defecto.
	_config = ProjectConfig.load_or_default() if root == ProjectSettings.globalize_path("res://").trim_suffix("/") else ProjectConfig.new()
	_coordinator = SessionCoordinator.new()
	_coordinator.is_game_running = func() -> bool: return false
	_snapshots = TurnSnapshots.new(root)
	_snapshots.setup()
	_build_turn_changes()
	_tabs = SessionTabs.new()
	_tabs.set_anchors_preset(Control.PRESET_FULL_RECT)
	_tabs.new_session_requested.connect(func(_in_copy: bool) -> void: open_tab())
	_tabs.close_requested.connect(close_tab)
	_tabs.rename_requested.connect(_rename)
	add_child(_tabs)
	open_tab()


## La carpeta de `--project=<carpeta>`; si no, la última abierta si todavía existe; si no, res://.
static func project_from_args(args: PackedStringArray, last: String) -> String:
	for arg: String in args:
		if arg.begins_with("--project="):
			var path := absolute_path(arg.trim_prefix("--project="), OS.get_environment("HOME"), OS.get_environment("PWD"))
			if DirAccess.dir_exists_absolute(path):
				return path
			push_error("Godot Agent: --project=%s is not a folder; using %s" % [path, last if DirAccess.dir_exists_absolute(last) else "res://"])
	return last if not last.is_empty() and DirAccess.dir_exists_absolute(last) else ""


## `~` y rutas relativas a la carpeta desde donde se lanzó: el shell no expande `~` después de `=`
## (zsh sin magic_equal_subst), y el agente rechaza un cwd que no sea absoluto.
static func absolute_path(path: String, home: String, cwd: String) -> String:
	if path == "~" or path.begins_with("~/"):
		path = home.path_join(path.trim_prefix("~").trim_prefix("/"))
	elif not path.is_absolute_path() and not cwd.is_empty():
		path = cwd.path_join(path)
	return path.simplify_path().trim_suffix("/")


static func settings_path() -> String:
	return AcpRegistry.editor_data_dir().path_join(SETTINGS_FILE)


func open_tab() -> String:
	_serial += 1
	var id := "s%d" % _serial
	var label := I18n.t("Session %d") % _serial
	var model := SessionModel.new()
	var controller := _make_controller(model, id)
	_sessions[id] = {"model": model, "controller": controller}
	_coordinator.register(id, label)
	var dock := AgentDockScene.instantiate()
	dock.setup(model, controller, _settings)
	dock.settings_requested.connect(_open_settings)
	dock.new_tab_requested.connect(func(_in_copy: bool = false) -> void: open_tab())
	dock.action_forwarded.connect(_on_dock_action)
	dock.turn_changes_requested.connect(func() -> void: _turn_counter.open(id))
	model.state_changed.connect(func(state: SessionModel.SessionState) -> void: _turn_counter.on_state(id, state))
	model.tool_call_changed.connect(func(call: ToolCall, _group: Variant) -> void:
		if call.status == ToolCall.STATUS_COMPLETED:
			_turn_counter.note_activity(id))
	dock.registry_requested.connect(func(query: String) -> void:
		_open_settings()
		_settings_dialog.open_registry(query))
	_tabs.add_session(id, dock, model, label)
	_tabs.select(id)
	return id


func close_tab(id: String) -> void:
	var session: Dictionary = _sessions.get(id, {})
	if session.is_empty():
		return
	var controller: SessionController = session.controller
	controller.stop()
	if controller.history:
		controller.history.flush()
	_coordinator.unregister(id)
	_turn_counter.clear(id)
	_sessions.erase(id)
	_tabs.remove_session(id)
	if _sessions.is_empty():
		open_tab()


func _make_controller(model: SessionModel, id: String) -> SessionController:
	var root := EditorContext.project_path()
	var controller := SessionController.new()
	controller.setup(model, _log, root)
	controller.session_key = id
	controller.history = SessionHistory.new()
	controller.account_quota = AccountQuotaBook.new()
	controller.policy = PermissionPolicy.new(_config.permissions)
	controller.policy.subagent_limits = _config.subagent_limits
	controller.shell_rules = _config.auto_shell_rules
	controller.quota.configure(_settings.quota_warn(), _settings.quota_pause(), _settings.quota_pause_enabled())
	controller.mode_models = ModeModels.new(_settings)
	controller.is_command_approved = _settings.is_command_approved
	controller.approve_command = _settings.approve_command
	# Dos pestañas sobre la misma carpeta no editan el mismo archivo a la vez (como en el editor).
	controller.file_guard = func(paths: PackedStringArray) -> String: return _coordinator.claim_label(id, paths)
	controller.snapshots = _snapshots if _config.turn_snapshots else null
	var fs := FsHandler.new()
	fs.setup(root, _log)
	fs.extra_roots = _config.extra_fs_roots
	controller.set_fs_handler(fs)
	var terminal := TerminalHandler.new()
	terminal.setup(root, _log)
	terminal.extra_roots = _config.extra_fs_roots
	controller.set_terminal_handler(terminal)
	# Por id: un lambda que capture el controller que lo guarda es un ciclo y no se libera nunca.
	controller.mcp_servers_provider = func() -> Array: return _editor_mcp(_sessions[id].controller, _sessions[id].model) if _sessions.has(id) else []
	return controller


## Al abrir cada sesión (m20-05): el MCP del editor abierto en la carpeta, si lo publicó, solo para
## leer; si no, sin tools godot.* y con la guía de Godot headless, como una copia aparte.
func _editor_mcp(controller: SessionController, model: SessionModel) -> Array:
	var root := EditorContext.project_path()
	var editor := McpPublication.read(root)
	controller.permissions.editor_tools = not editor.is_empty()
	if editor.is_empty():
		controller.note_for_agent("[The Godot editor is not open: you work on the project at %s from a separate window of the harness, so the godot.* tools are not available to you. Edit files with your own tools. To check your work and build scenes, run Godot headless on the project (\"$GODOT\" --headless --path %s …) as this guide says:]\n\n%s" % [root, root, FileAccess.get_file_as_string(SessionController.HEADLESS_GUIDE_PATH)])
		return []
	controller.note_for_agent("[The Godot editor is open on this project, and you work on it from a separate window of the harness: the godot.* tools that read (scenes, find_in_files, get_errors…) work and see the editor's unsaved state, but the ones that change something are refused. Edit files with your own tools.]")
	_log.add_secret(editor.token)
	if model.supports_http_mcp():
		return [{"type": "http", "name": McpServer.SERVER_NAME, "url": editor.url, "headers": [{"name": "Authorization", "value": "Bearer " + editor.token}]}]
	var entry := StdioShimInstaller.server_entry(McpServer.SERVER_NAME, editor.url, editor.token)
	return [entry] if not entry.is_empty() else []


## Ver los cambios del turno y volver atrás (m20-09), como en el editor pero sin lo que solo existe
## ahí: escenas abiertas para recargar, buffers sin guardar y marcas en el Script Editor.
func _build_turn_changes() -> void:
	var diff_dialog := DiffDialog.new()
	add_child(diff_dialog)
	var dialog := TurnChangesDialog.new()
	add_child(dialog)
	_turn_changes = TurnChanges.new()
	_turn_changes.project_snapshots = _snapshots
	_turn_changes.diff_dialog = diff_dialog
	_turn_changes.dialog = dialog
	_turn_changes.controller_of = func(id: String) -> SessionController: return _sessions[id].controller if _sessions.has(id) else null
	_turn_changes.model_of = func(id: String) -> SessionModel: return _sessions[id].model if _sessions.has(id) else null
	_turn_changes.after_restore = func(_paths: PackedStringArray) -> void: pass  # nada abierto que recargar
	_turn_changes.holder_of = func(session: String, res_path: String) -> String:
		return _coordinator.holder_label(session, EditorContext.project_path().path_join(res_path.trim_prefix("res://")))
	dialog.diff_requested.connect(_turn_changes.show_diff)
	dialog.revert_requested.connect(func(data: Dictionary, path: String) -> void: _turn_changes.restore(data, PackedStringArray([path])))
	dialog.hunks_requested.connect(_turn_changes.show_hunks)
	dialog.hunk_action.connect(_turn_changes.on_hunk_action)
	dialog.reject_file_requested.connect(_turn_changes.on_reject_file)
	_turn_changes.hunks_changed.connect(dialog.refresh_file)
	_turn_counter = TurnCounter.new()
	_turn_counter.snapshots_of = _turn_changes._snapshots_of
	_turn_counter.model_of = _turn_changes.model_of
	_turn_counter.dock_of = func(id: String) -> Object: return _tabs.dock(id) if _tabs else null
	_turn_counter.open_dialog = dialog.show_turn
	add_child(_turn_counter)


func _on_dock_action(action: String, payload: Variant) -> void:
	match action:
		SessionController.ACTION_TURN_CHANGES:
			_turn_changes.dialog.show_turn(payload)
		SessionController.ACTION_TURN_RESTORE:
			_turn_changes.confirm_restore(payload)
		TurnChanges.ACTION_HUNK_UNDO:
			_turn_changes.undo_hunk(payload)
		SessionController.ACTION_TURN_REPORT:
			_turn_changes.save_report(payload)


func _rename(id: String, name: String) -> void:
	var label := name if not name.is_empty() else _tabs.default_label(id)
	if _coordinator.label_taken(label, id):
		return
	_coordinator.register(id, label)
	_tabs.set_label(id, label)


func _open_settings() -> void:
	if _settings_dialog == null:
		_settings_dialog = SettingsDialog.new()
		_settings_dialog.setup(_settings, _config)
		add_child(_settings_dialog)
	_settings_dialog.open()


## Con cualquier salida (cerrar la ventana o quit()): los agentes y sus hilos vivos al liberar tiran el proceso.
func _exit_tree() -> void:
	for id: String in _sessions.keys():
		var controller: SessionController = _sessions[id].controller
		controller.stop()
		if controller.history:
			controller.history.flush()
	_sessions.clear()
