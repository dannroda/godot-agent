extends Control
## El dock fuera del editor (m20-04): las mismas pestañas de sesión en una ventana propia, cada una con
## su agente y su cuenta. Se abre con el binario del editor, sin --editor:
##   godot --path <proyecto> res://addons/godot_agent/standalone/main.tscn [-- --project=<carpeta>]
## o exportada con una plantilla, sin las clases del editor (m20-07): tests/standalone_export_check.sh.
## Con el editor abierto en la carpeta, sus tools godot.* por el MCP de la app (m20-05, m20-06); si no, el agente usa sus tools de
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
const EditorBridge := preload("editor_bridge.gd")
const AgentTheme := preload("../ui/agent_theme.gd")
const SessionSidebar := preload("session_sidebar.gd")
const TurnPanel := preload("turn_panel.gd")
const ProjectModes := preload("../core/project_modes.gd")

## Al lado de los datos del editor, compartido por todos los proyectos que se abran así; los perfiles
## del editor viven en EditorSettings y no se comparten.
const SETTINGS_FILE := "godot_agent/standalone.cfg"
## Cada cuánto se mira si el editor sigue (o ya está) abierto: un connect a 127.0.0.1, que contesta enseguida.
const EDITOR_CHECK_S := 3.0
const EDITOR_ON_COLOR := Color("#4fc1a6")
const EDITOR_OFF_COLOR := Color("#8a93a0")
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
var _mcp: McpServer
var _bridge: EditorBridge
var _sessions: Dictionary = {}  # id → {model, controller}
## La píldora de arriba (m21-01): si hay un editor abierto en la carpeta, y con él las tools godot.*.
var _editor_pill: PanelContainer
var _editor_dot: TextureRect
var _editor_label: Label
var _editor_open := false
var _sidebar: SessionSidebar
var _turn_panel: TurnPanel
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
	_snapshots.key_prefix = "app-"  # las pestañas del editor en la misma carpeta también son s1, s2…
	_snapshots.setup()
	_build_turn_changes()
	_start_mcp(root)
	var column := VBoxContainer.new()
	column.set_anchors_preset(Control.PRESET_FULL_RECT)
	column.add_theme_constant_override(&"separation", 0)
	add_child(column)
	column.add_child(_build_header(root))
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override(&"separation", 0)
	column.add_child(body)
	_tabs = SessionTabs.new()
	_tabs.accent = _settings.accent_color()
	_tabs.bar_hidden = true  # las sesiones van en la barra lateral (m21-04)
	_tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_sidebar = SessionSidebar.new()
	_sidebar.describe = _describe_session
	_sidebar.setup(_tabs)
	_sidebar.new_requested.connect(open_tab)
	_sidebar.close_requested.connect(close_tab)
	body.add_child(_sidebar)
	_tabs.new_session_requested.connect(func(_in_copy: bool) -> void: open_tab())
	_tabs.close_requested.connect(close_tab)
	_tabs.rename_requested.connect(_rename)
	body.add_child(_tabs)
	_turn_panel = TurnPanel.new()
	_turn_panel.counter = _turn_counter
	_turn_panel.coordinator = _coordinator
	_turn_panel.root = root
	_turn_panel.sessions = _tabs.ids
	_turn_panel.controller_of = func(id: String) -> SessionController: return _sessions[id].controller if _sessions.has(id) else null
	_turn_panel.open_turn = _turn_changes.dialog.show_turn
	_tabs.active_changed.connect(_turn_panel.show_session)
	body.add_child(_turn_panel)
	open_tab()


## La barra de arriba (m21-01): el proyecto, su carpeta y si hay un editor abierto en ella.
func _build_header(root: String) -> Control:
	var bar := PanelContainer.new()
	bar.add_theme_stylebox_override(&"panel", AgentTheme.panel(AgentTheme.dark_color(), Color.TRANSPARENT, 0.0, 6.0))
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", AgentTheme.px(10))
	bar.add_child(row)
	var project := Label.new()
	project.text = root.get_file()
	project.add_theme_color_override(&"font_color", AgentTheme.font_color())
	row.add_child(project)
	var path := Label.new()
	var home := OS.get_environment("HOME")
	path.text = ("~" + root.trim_prefix(home)) if not home.is_empty() and root.begins_with(home) else root
	path.tooltip_text = root
	path.mouse_filter = Control.MOUSE_FILTER_PASS
	path.modulate = Color(1, 1, 1, 0.6)
	path.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	path.clip_text = true
	path.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(path)
	_editor_pill = PanelContainer.new()
	var pill_row := HBoxContainer.new()
	pill_row.add_theme_constant_override(&"separation", AgentTheme.px(6))
	_editor_pill.add_child(pill_row)
	_editor_dot = TextureRect.new()
	_editor_dot.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	pill_row.add_child(_editor_dot)
	_editor_label = Label.new()
	pill_row.add_child(_editor_label)
	row.add_child(_editor_pill)
	var timer := Timer.new()
	timer.wait_time = EDITOR_CHECK_S
	timer.timeout.connect(refresh_editor_status)
	bar.add_child(timer)
	timer.autostart = true
	refresh_editor_status.call_deferred()
	return bar


## Mira si hay un editor abierto en la carpeta y pinta la píldora. Las sesiones toman el MCP al
## abrirse (_editor_mcp): el tooltip dice qué pasa con las que ya estaban.
func refresh_editor_status() -> void:
	var open := not McpPublication.read(EditorContext.project_path()).is_empty() and _mcp != null and _mcp.is_listening()
	if open == _editor_open and not _editor_label.text.is_empty():
		return
	_editor_open = open
	var color := EDITOR_ON_COLOR if open else EDITOR_OFF_COLOR
	_editor_pill.add_theme_stylebox_override(&"panel", AgentTheme.panel(Color(color, 0.14), Color(color, 0.5), 10.0, 4.0))
	_editor_dot.texture = AgentTheme.dot(color)
	_editor_label.text = I18n.t("Editor open · godot.* tools on") if open else I18n.t("No editor open")
	_editor_pill.tooltip_text = I18n.t("The Godot editor is open on this folder: new sessions use its godot.* tools, approved in each tab. Sessions opened before it don't have them: start a new one.") if open \
		else I18n.t("No Godot editor is open on this folder: agents edit files with their own tools and check them with Godot headless. Open the editor on this folder and start a new session to use its godot.* tools.")


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
	controller.turn_changes_reported.connect(func(_data: Dictionary) -> void: _turn_panel.refresh())
	for changed: Signal in [model.harness_mode_changed, model.project_mode_changed, model.account_changed]:
		changed.connect(func(_value: Variant = null) -> void: _sidebar.refresh())
	model.turn_finished.connect(func(_stop_reason: String) -> void: _coordinator.release_files(id))
	model.tool_call_changed.connect(func(call: ToolCall, _group: Variant) -> void:
		if call.status == ToolCall.STATUS_COMPLETED:
			_turn_counter.note_activity(id))
	dock.registry_requested.connect(func(query: String) -> void:
		_open_settings()
		_settings_dialog.open_registry(query))
	_tabs.add_session(id, dock, model, label)
	_tabs.select(id)
	return id


## Lo que la barra lateral muestra de la sesión `id` además del estado: el agente (con su cuenta) y el modo.
func _describe_session(id: String) -> Dictionary:
	if not _sessions.has(id):
		return {}
	var controller: SessionController = _sessions[id].controller
	var model: SessionModel = _sessions[id].model
	var dock: Object = _tabs.dock(id)
	var profile: Object = controller.profile() if controller.profile() else (dock.call(&"selected_profile") if dock else null)
	var mode := str(model.project_mode.get("name", "")) if not model.project_mode.is_empty() else I18n.t(SessionModel.HARNESS_MODE_LABELS.get(model.harness_mode, ""))
	return {"agent": profile.call(&"label") if profile else I18n.t("No agent"), "mode": mode}


func close_tab(id: String) -> void:
	var session: Dictionary = _sessions.get(id, {})
	if session.is_empty():
		return
	var controller: SessionController = session.controller
	controller.stop()
	if controller.history:
		controller.history.flush()
	_coordinator.unregister(id)
	_mcp.remove_session_token(id)
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
	controller.mcp_servers_provider = func() -> Array: return _editor_mcp(id) if _sessions.has(id) else []
	return controller


## Al abrir cada sesión (m20-05, m20-06): con el editor abierto en la carpeta, las godot.* por el MCP de
## la app, que autoriza cada llamada en la pestaña y la pasa al editor; si no, sin godot.* y con la guía
## de Godot headless, como una copia aparte.
func _editor_mcp(id: String) -> Array:
	var controller: SessionController = _sessions[id].controller
	var root := EditorContext.project_path()
	var open := not McpPublication.read(root).is_empty() and _mcp.is_listening()
	controller.permissions.editor_tools = open
	controller.fs.editor_tools = open
	if not open:
		controller.note_for_agent("[The Godot editor is not open: you work on the project at %s from a separate window of the harness, so the godot.* tools are not available to you. Edit files with your own tools. To check your work and build scenes, run Godot headless on the project (\"$GODOT\" --headless --path %s …) as this guide says:]\n\n%s" % [root, root, FileAccess.get_file_as_string(SessionController.HEADLESS_GUIDE_PATH)])
		return []
	controller.note_for_agent("[The Godot editor is open on this project and you work on it from a separate window of the harness: the godot.* tools act on that editor, with its unsaved state, as the harness instructions say. If the editor closes, they stop working.]")
	var token := _mcp.session_token(id)
	_log.add_secret(token)
	if _sessions[id].model.supports_http_mcp():
		return [_mcp.http_server_entry(token)]
	var entry := StdioShimInstaller.server_entry(McpServer.SERVER_NAME, _mcp.url(), token)
	return [entry] if not entry.is_empty() else []


## El MCP de la app para sus agentes (m20-06): un token por pestaña, y las tools son las del editor.
func _start_mcp(root: String) -> void:
	_bridge = EditorBridge.new()
	_bridge.project = root
	_bridge.authorize = _authorize_editor_tool
	add_child(_bridge)
	_mcp = McpServer.new()
	_mcp.registry = _bridge
	_mcp.agent_log = _log
	add_child(_mcp)
	if _mcp.start() == OK:
		_log.add_secret(_mcp.token)


## Una tool godot.* de la pestaña `id` antes de mandarla al editor, que confía en la app: como hace el
## editor con sus pestañas, el modo del proyecto (escribir fuera de sus archivos, o sin decir dónde, se
## rechaza sin tarjeta), los archivos que tiene otra pestaña y el permiso. "" si sigue; si no, el motivo.
func _authorize_editor_tool(id: String, info: Dictionary) -> String:
	if not _sessions.has(id):
		return "This tab of the harness is closed."
	var controller: SessionController = _sessions[id].controller
	var title := str(info.get("title", ""))
	var group := str(info.get("group", ""))
	var targets: Dictionary = info.get("targets") if info.get("targets") is Dictionary else {}
	var paths := PackedStringArray()
	for path: Variant in targets.get("paths", []) if targets.get("paths") is Array else []:
		paths.append(EditorContext.project_path().path_join(str(path).trim_prefix("res://")) if str(path).begins_with("res://") else str(path))
	if ProjectModes.limits_files(controller.model.project_mode):
		var refused := controller.permissions.mode_refused_write(paths) if bool(targets.get("declared", false)) else "?"
		if not refused.is_empty():
			return controller.permissions.notify_mode_refusal(title, refused)
	# shortcut: sin rutas, una tool de escena edita la escena abierta en el editor, que la app no ve: esa
	# queda sin lock entre pestañas; si choca seguido, que describe diga cuál es.
	if group in [PermissionPolicy.GROUP_EDIT_SCENE, PermissionPolicy.GROUP_EDIT_FILES, PermissionPolicy.GROUP_PROJECT]:
		if group == PermissionPolicy.GROUP_PROJECT:
			paths.append(EditorContext.project_path().path_join("project.godot"))
		var holder := _coordinator.claim_label(id, paths)
		if not holder.is_empty():
			return "%s is being edited by «%s» in its current turn. Don't touch it until that turn ends: work on something else meanwhile." % [paths[0], holder]
	if not await controller.authorize(group, title, str(info.get("description", "")), {}, _config.permission_timeout_s):
		return "Permission denied for %s (group %s) by the current mode or by the user. Do not retry: explain what you wanted to do and ask the user to change the mode if needed." % [title, group]
	return ""


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
	# En la app lo del turno va en el panel de al lado (m21-05), no en el contador sobre el composer.
	_turn_counter.dock_of = func(_id: String) -> Object: return null
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
