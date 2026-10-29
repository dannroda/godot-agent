@tool
extends VBoxContainer
## Dock "Agent" (spec §9.1, mockup pantalla 1): header con perfil, título y acciones; selector de
## modo; conversación; composer. Solo habla con SessionModel (estado) y SessionController (comandos).

## `seq`: la línea del Agent Log a mostrar (0 = solo abrir el panel, m12-36).
signal show_log_requested(seq: int)
## Abrir el diálogo de Settings (lo maneja el plugin: necesita la config del proyecto y el server MCP).
signal settings_requested
## Agregar un agente sugerido desde el registro de ACP, filtrado por `query` (m12-15).
signal registry_requested(query: String)
## «+ › Nueva pestaña» (m12-14): otra sesión al lado; `in_copy`, en una copia aparte del proyecto.
signal new_tab_requested(in_copy: bool)
## Abrir la ventana Extensions: plugins, marketplaces y MCP servers (m7-37).
signal extensions_requested
## Acciones de avisos que resuelve otro módulo (conflictos de sync, recargar escena…).
signal action_forwarded(action: String, payload: Variant)

const SessionModel := preload("../../session/session_model.gd")
const SuggestedAgents := preload("../../core/suggested_agents.gd")
const SessionController := preload("../../session/session_controller.gd")
const ChatEntry := preload("../../session/chat_entry.gd")
const HarnessSettings := preload("../../core/harness_settings.gd")
const HISTORY_MENU_SIZE := 30
## Ids de los menús del header (m12-14).
const AGENT_MENU_MANAGE := 1000
const NEW_MENU_SESSION := 0
const NEW_MENU_TAB := 1
const NEW_MENU_TAB_COPY := 2
const MORE_EXTENSIONS := 0
const MORE_SETTINGS := 1
const MORE_REMOTE := 2
const MORE_LOGOUT := 3
## Sesiones anteriores en el dock vacío (m12-12).
const RECENT_SESSIONS := 5
const AgentProfile := preload("../../core/agent_profile.gd")
const AgentLog := preload("../../core/agent_log.gd")
const AgentTheme := preload("../agent_theme.gd")
const EditorContext := preload("../editor_context.gd")
const ExportPresetsPatcher := preload("../../export/export_presets_patcher.gd")
const ConversationView := preload("conversation_view.gd")
const Composer := preload("composer.gd")
const PromptQueue := preload("../../session/prompt_queue.gd")
const PromptQueueView := preload("prompt_queue_view.gd")
const ReviewPanel := preload("review_panel.gd")
const GithubReviews := preload("../../core/github_reviews.gd")
const QuotaRing := preload("quota_ring.gd")
const QrView := preload("qr_view.gd")
const QuotaMonitor := preload("../../core/quota_monitor.gd")
const ReviewStore := preload("../../review/review_store.gd")
const I18n := preload("../../core/i18n.gd")
const MarkdownBBCode := preload("../markdown/markdown_bbcode.gd")
const ImageViewer := preload("../image_viewer.gd")

## export_presets.cfg no pasa por EditorFileSystem: se mira su fecha de modificación cada tanto.
const PRESETS_POLL_INTERVAL_S := 2.0
const CHIP_SCENE := "scene"
const CHIP_SELECTION := "selection"
const CHIP_IMAGE_PREFIX := "image:"
const CHIP_FILE_PREFIX := "file:"
const ADD_CONTEXT_SCRIPT := 0
const ADD_CONTEXT_FILE := 1
const ADD_CONTEXT_SCREENSHOT := 2
const ADD_CONTEXT_GAME := 3
## Menciones que se convierten en contexto al enviar (m11-08): `@errors`, `@output`, `@game` y
## `@docs:Clase`. El texto lo trae `context_provider`.
const SPECIAL_MENTIONS: PackedStringArray = ["errors", "output", "game", "docs:"]
## Imágenes adjuntas por prompt.
const MAX_IMAGES := 6
const IMAGE_EXTENSIONS: PackedStringArray = ["png", "jpg", "jpeg", "webp", "bmp", "tga", "svg"]
## Acciones de la revisión que resuelve el plugin (junto con las de las tarjetas del Script Editor).
const ACTION_REVIEW_FOCUS := "review_focus"
const ACTION_REVIEW_FIX_ALL := "review_fix_all"
## Un link a .godot_agent/oneshot/… (spec, progreso, QA): lo muestra la pantalla One-shot.
const ACTION_OPEN_RUN_FILE := "open_run_file"
## Tooltips de los botones de modo (las reglas que lee el agente están en SessionController.MODE_RULES).
const MODE_TOOLTIPS: Dictionary = {
	SessionModel.HarnessMode.ASK: "Only answers questions: does not modify files, scenes or settings, and does not run commands.",  # i18n
	SessionModel.HarnessMode.REVIEW: "Read-only review: the agent reports findings without modifying anything.",  # i18n
	SessionModel.HarnessMode.BUILD: "The agent can edit scenes and scripts; you approve the changes.",  # i18n
	SessionModel.HarnessMode.AUTO: "The agent edits scenes, scripts and settings and runs the game without asking. Shell commands on the allowlist run on their own; any other asks (Settings → Permissions).",  # i18n
	SessionModel.HarnessMode.ONESHOT: "The agent works autonomously until the goal is met, verifying after each task.",  # i18n
}
## Prompts enviados en este proyecto (flechas en el composer). Datos del usuario, fuera del repo.
const PROMPT_HISTORY_PATH := "user://godot_agent/prompt_history.json"

## (texto) -> bool: si devuelve true, el texto del composer ya se manejó (p. ej. guía del One-shot).
var submit_interceptor: Callable
## «Reintentar» de un aviso de error: si devuelve true, otro se ocupó (el One-shot retoma su run).
var retry_interceptor: Callable
## () -> bool: si se puede cambiar de sesión (no con un One-shot en curso). Sin asignar: siempre.
var can_switch_session: Callable
## () -> Variant (async): el frame del juego en ejecución como Image, o el motivo (String) si no hay.
var game_capture: Callable
## `(kind: String, arg: String) -> String`: el texto de una mención especial (m11-08); lo pone el plugin.
var context_provider: Callable
## false en las sesiones extra (m7-44): el One-shot corre solo en la primera.
var allow_oneshot: bool = true

var _model: SessionModel
## Hay un One-shot activo (corriendo o en pausa): el botón de la vista vacía lo retoma.
var _oneshot_active := false
var _controller: SessionController
var _settings: HarnessSettings
var _profiles: Array[AgentProfile] = []
var _accent: Color = HarnessSettings.DEFAULT_ACCENT
var _presets_mtime: int = -1
var _pending_prompt: String = ""
var _conversation: ConversationView
var _composer: Composer
## Prompts escritos mientras el agente trabaja: salen de a uno al terminar cada turno.
var _queue := PromptQueue.new()
var _queue_view: PromptQueueView
## Se canceló el turno para mandar un prompt de la cola con «Enviar ahora» (m7-33).
var _interrupt_for_queue: bool = false
## Chips de contexto actuales: id -> {label, tooltip, block}
var _chips: Dictionary = {}
var _dismissed_chips: Dictionary = {}  # "id|valor" -> true
## Imágenes adjuntas para el próximo prompt: chip id -> {label, tooltip, block}.
var _images: Dictionary = {}
var _image_serial: int = 0
## Archivos agregados con "+ contexto" para el próximo prompt (res_path, en orden).
var _extra_files: PackedStringArray = []
var _add_context_menu: PopupMenu
var _file_dialog: EditorFileDialog
var _review_panel: ReviewPanel
var _quota_ring: QuotaRing
## Remote Control (m7-21): botón de la línea de estado y franja con el link mientras está prendido.
var _remote_button: Button
var _logout_button: Button
## Header de una fila (m12-14): el chip del agente con su estado (elige el perfil), el título, el
## historial, «+» (sesión o pestaña) y «⋯» (extensiones, ajustes, Remote Control, cerrar sesión).
var _agent_chip: Button
var _agent_menu: PopupMenu
var _new_menu: PopupMenu
var _more_button: MenuButton
var _logout_dialog: ConfirmationDialog
var _remote_banner: FoldableContainer
var _remote_link: Button
var _remote_qr_button: Button
var _remote_qr: QrView
var _quota_timer: Timer
var _quota_state: int = QuotaMonitor.QuotaState.UNKNOWN
var _export_dialog: ConfirmationDialog
var _delete_session_dialog: ConfirmationDialog
var _export_preview: TextEdit
## Para pegar el código de la página de login (se arma la primera vez).
var _login_code_dialog: ConfirmationDialog
var _login_code_input: LineEdit
var _history_menu: PopupMenu
var _history_delete_menu: PopupMenu
var _history_items: Array[Dictionary] = []

@onready var _profile_button: OptionButton = %ProfileButton
@onready var _title_label: Label = %TitleLabel
@onready var _history_button: Button = %HistoryButton
@onready var _new_session_button: Button = %NewSessionButton
@onready var _settings_button: Button = %SettingsButton
@onready var _status_label: Label = %StatusLabel
@onready var _body: VBoxContainer = %Body
@onready var _empty_state: VBoxContainer = %EmptyState
@onready var _empty_command: Label = %EmptyCommand
@onready var _start_button: Button = %StartButton
## Debajo de «Nueva sesión»: las últimas sesiones del proyecto con «Continuar» (m12-12).
var _recent_box: VBoxContainer
## Sin agentes: los sugeridos con lo que piden y «Agregar» (m12-15).
var _suggested_box: VBoxContainer
var _recent_signature: String = ""
@onready var _composer_slot: MarginContainer = %ComposerSlot
@onready var _export_banner: PanelContainer = %ExportBanner
@onready var _export_banner_label: Label = %ExportBannerLabel
@onready var _add_filter_button: Button = %AddFilterButton
@onready var _confirm_dialog: ConfirmationDialog = %ConfirmPatchDialog
@onready var _result_dialog: AcceptDialog = %PatchResultDialog
@onready var _presets_poll_timer: Timer = %PresetsPollTimer
@onready var _context_poll_timer: Timer = %ContextPollTimer


## Inyección desde plugin.gd, antes de agregar el dock al editor.
func setup(model: SessionModel, controller: SessionController, settings: HarnessSettings) -> void:
	_model = model
	_controller = controller
	_settings = settings
	_accent = settings.accent_color()


func _ready() -> void:
	_build_header()
	_recent_box = VBoxContainer.new()
	_recent_box.name = "RecentSessions"
	_recent_box.add_theme_constant_override(&"separation", AgentTheme.px(6))
	_empty_state.add_child(_recent_box)
	_suggested_box = VBoxContainer.new()
	_suggested_box.name = "SuggestedAgents"
	_suggested_box.add_theme_constant_override(&"separation", AgentTheme.px(6))
	_empty_state.add_child(_suggested_box)
	_empty_state.move_child(_suggested_box, _start_button.get_index())
	for agent: Dictionary in SuggestedAgents.AGENTS:
		_suggested_box.add_child(_suggested_row(agent))
	_conversation = ConversationView.new()
	_conversation.setup(_model, _accent)
	_conversation.action_requested.connect(_on_action_requested)
	_body.add_child(_conversation)
	_composer = Composer.new()
	_composer.setup(_accent)
	_composer.history_path = PROMPT_HISTORY_PATH
	_composer.mention_provider = func() -> Array[Dictionary]:
		var options := special_mention_options()
		options.append_array(EditorContext.mention_options())
		return options
	_composer.submitted.connect(_on_submitted)
	_composer.cancel_requested.connect(_on_cancel_requested)
	_composer.model_selected.connect(func(value: String) -> void: _controller.set_config_option("model", value))
	_build_mode_selector()
	_composer.screenshot_requested.connect(_on_screenshot_requested)
	_composer.image_pasted.connect(func(image: Image) -> void: attach_image(image, I18n.t("pasted image")))
	_composer.files_attached.connect(add_context_files)
	_composer.context_chip_removed.connect(_on_chip_removed)
	var composer_column := VBoxContainer.new()
	composer_column.add_theme_constant_override(&"separation", AgentTheme.px(4))
	_composer_slot.add_child(composer_column)
	_queue_view = PromptQueueView.new()
	_queue_view.setup(_queue)
	_queue_view.edit_requested.connect(_composer.insert_text)
	_queue_view.send_now_requested.connect(_send_next_queued.bind(true))
	_queue_view.send_item_now_requested.connect(_send_queued_now)
	composer_column.add_child(_queue_view)
	composer_column.add_child(_composer)
	_build_review_panel()
	_build_quota_ring()
	_build_remote_control()
	_settings.changed.connect(func(key: String) -> void:
		if key == HarnessSettings.KEY_PROFILES:
			_reload_profiles())

	_translate_scene_texts()
	_start_button.pressed.connect(_on_start_pressed)
	_start_button.add_theme_color_override(&"font_color", _accent)
	_add_filter_button.pressed.connect(_on_add_filter_pressed)
	_confirm_dialog.confirmed.connect(_on_patch_confirmed)
	visibility_changed.connect(refresh_export_banner)
	_presets_poll_timer.wait_time = PRESETS_POLL_INTERVAL_S
	_presets_poll_timer.timeout.connect(_on_presets_poll)
	_context_poll_timer.timeout.connect(_refresh_chips)

	# Pull del estado actual y después push por señales.
	_model.state_changed.connect(func(state: SessionModel.SessionState) -> void:
		_refresh_state()
		_queue_view.set_send_available(state == SessionModel.SessionState.READY)
		if state in [SessionModel.SessionState.DISCONNECTED, SessionModel.SessionState.FAILED]:
			_queue.pause(I18n.t("the session closed")))
	_model.turn_finished.connect(_on_turn_finished)
	# Los subagentes en curso se cuentan en la línea de estado (m7-43).
	_model.tool_call_changed.connect(func(call: SessionModel.ToolCall, _group: ChatEntry) -> void:
		if call.is_subagent():
			_refresh_state())
	_model.title_changed.connect(func(_title: String) -> void: _refresh_title())
	_model.account_changed.connect(_refresh_state)
	_model.usage_changed.connect(_composer.set_usage)
	_model.usage_changed.connect(func(used: int, total: int) -> void:
		if _quota_ring:
			_quota_ring.set_context(used, total))
	_model.commands_changed.connect(_composer.set_commands)
	_model.config_options_changed.connect(func(_options: Array) -> void: _composer.set_model_option(_model.config_option("model")))
	_model.harness_mode_changed.connect(func(_mode: SessionModel.HarnessMode) -> void: _refresh_modes())
	_model.entries_cleared.connect(_refresh_state)
	_model.entries_cleared.connect(func() -> void: _queue.pause(I18n.t("another session started")))
	_model.entry_added.connect(func(_entry: ChatEntry) -> void: _refresh_empty_state())
	_reload_profiles()
	_refresh_modes()
	_refresh_state()
	_queue_view.set_send_available(_model.state == SessionModel.SessionState.READY)
	_refresh_title()
	_composer.set_usage(_model.usage_used, _model.usage_size)
	_quota_ring.set_context(_model.usage_used, _model.usage_size)
	_composer.set_model_option(_model.config_option("model"))
	_refresh_chips()
	refresh_export_banner()


# --- header y modos ------------------------------------------------------------------------------

## Los textos del .tscn están en inglés: el dock no usa la traducción automática del editor.
func _translate_scene_texts() -> void:
	_profile_button.tooltip_text = I18n.t("Agent profile")
	_new_session_button.tooltip_text = I18n.t("New session")
	_settings_button.tooltip_text = I18n.t("Harness settings")
	_add_filter_button.text = I18n.t("Add to the presets")
	(_empty_state.get_node("EmptyTitle") as Label).text = I18n.t("No session")
	_start_button.text = I18n.t("Start session")
	_confirm_dialog.title = I18n.t("Add filter to the presets")
	_confirm_dialog.cancel_button_text = I18n.t("Cancel")
	_confirm_dialog.ok_button_text = I18n.t("Add")


func _build_header() -> void:
	_history_button.icon = AgentTheme.icon(&"History")
	_history_button.tooltip_text = I18n.t("Session history")
	_history_menu = PopupMenu.new()
	_history_menu.id_pressed.connect(_on_history_selected)
	add_child(_history_menu)
	_history_delete_menu = PopupMenu.new()
	_history_delete_menu.name = "DeleteSessionMenu"
	_history_delete_menu.id_pressed.connect(_on_history_delete_selected)
	_history_menu.add_child(_history_delete_menu)
	_history_button.pressed.connect(_show_history_menu)
	_new_session_button.icon = AgentTheme.icon(&"Add")
	_new_session_button.tooltip_text = I18n.t("New session or new tab")
	_new_session_button.pressed.connect(func() -> void:
		_new_menu.set_item_disabled(_new_menu.get_item_index(NEW_MENU_SESSION), _new_session_button.disabled)
		var below := _new_session_button.get_screen_position() + Vector2(0, _new_session_button.size.y)
		_new_menu.popup(Rect2i(Vector2i(below), Vector2i.ZERO)))
	var extensions := Button.new()
	extensions.name = "ExtensionsButton"
	extensions.flat = true
	# EditorPlugin (un enchufe) llena el cuadro como los otros íconos del header; AssetLib se veía diminuto.
	extensions.icon = AgentTheme.icon(&"EditorPlugin")
	if extensions.icon == null:
		extensions.text = "⧉"
	extensions.tooltip_text = I18n.t("Extensions: plugins, marketplaces and MCP servers")
	extensions.pressed.connect(func() -> void: extensions_requested.emit())
	_settings_button.add_sibling(extensions)
	_settings_button.get_parent().move_child(extensions, _settings_button.get_index())
	_settings_button.icon = AgentTheme.icon(&"Tools")
	_settings_button.pressed.connect(func() -> void: settings_requested.emit())
	_profile_button.item_selected.connect(_on_profile_selected)
	_title_label.add_theme_color_override(&"font_color", AgentTheme.MUTED)
	# Una fila (m12-14): ajustes y extensiones van al «⋯»; el selector de perfil, al chip del agente.
	# Los botones viejos quedan ocultos (los usan los checks del dev plugin).
	_profile_button.visible = false
	_settings_button.visible = false
	extensions.visible = false
	_agent_chip = Button.new()
	_agent_chip.name = "AgentChip"
	_agent_chip.flat = true
	_agent_chip.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_agent_chip.clip_text = true
	_agent_chip.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_agent_chip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_agent_chip.size_flags_stretch_ratio = 1.4
	_agent_chip.pressed.connect(_show_agent_menu)
	_profile_button.add_sibling(_agent_chip)
	_agent_menu = PopupMenu.new()
	_agent_menu.id_pressed.connect(func(id: int) -> void:
		if id == AGENT_MENU_MANAGE:
			settings_requested.emit()
		elif id >= 0 and id < _profiles.size():
			_profile_button.select(id)
			_on_profile_selected(id))
	add_child(_agent_menu)
	_new_menu = PopupMenu.new()
	_new_menu.add_item(I18n.t("New session"), NEW_MENU_SESSION)
	_new_menu.set_item_tooltip(0, I18n.t("Starts a new conversation in this tab."))
	_new_menu.add_item(I18n.t("New tab"), NEW_MENU_TAB)
	_new_menu.set_item_tooltip(1, I18n.t("Open another agent session alongside this one. Sessions don't step on each other: a file one is editing in its turn is off limits to the rest, and the game runs for one at a time."))
	_new_menu.add_item(I18n.t("New tab in a separate copy (git worktree)"), NEW_MENU_TAB_COPY)
	_new_menu.set_item_tooltip(2, I18n.t("The agent works in a copy of the project on a new branch, outside the project folder, without touching the open editor. When you close its tab you choose whether to apply its changes to the project."))
	_new_menu.id_pressed.connect(func(id: int) -> void:
		if id == NEW_MENU_SESSION:
			_on_new_session_pressed()
		else:
			new_tab_requested.emit(id == NEW_MENU_TAB_COPY))
	add_child(_new_menu)
	_more_button = MenuButton.new()
	_more_button.name = "MoreButton"
	_more_button.flat = true
	_more_button.text = "⋯"
	_more_button.tooltip_text = I18n.t("More: extensions, settings, Remote Control and the account")
	_more_button.about_to_popup.connect(_fill_more_menu)
	_more_button.get_popup().id_pressed.connect(_on_more_selected)
	_settings_button.add_sibling(_more_button)


## El modo va en un dropdown de la fila del composer, al lado del modelo (m7-32): los cinco botones
## ocupaban una o dos filas arriba de la conversación.
func _build_mode_selector() -> void:
	var modes: Array[Dictionary] = []
	for mode: SessionModel.HarnessMode in SessionModel.HARNESS_MODE_LABELS:
		if mode == SessionModel.HarnessMode.ONESHOT and not allow_oneshot:
			continue
		modes.append({"id": mode, "label": I18n.t(SessionModel.HARNESS_MODE_LABELS[mode]), "tooltip": I18n.t(MODE_TOOLTIPS[mode])})
	_composer.set_modes(modes)
	_composer.mode_selected.connect(func(mode: int) -> void: _model.set_harness_mode(mode as SessionModel.HarnessMode))


func _build_remote_control() -> void:
	_remote_button = Button.new()
	_remote_button.text = I18n.t("Remote")
	_remote_button.flat = true
	_remote_button.add_theme_font_size_override(&"font_size", AgentTheme.px(12))
	_remote_button.tooltip_text = I18n.t("Remote Control: continue this session from claude.ai/code or the Claude app on your phone.")
	_remote_button.pressed.connect(func() -> void: _on_submitted(_controller.remote_control_command(_model.remote_control_url.is_empty())))
	# Va a la derecha de la línea de estado: el encabezado ya llena un dock angosto.
	var status_row := HBoxContainer.new()
	add_child(status_row)
	move_child(status_row, _status_label.get_index())
	_status_label.reparent(status_row)
	_status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# Un Label ignora el mouse por defecto: sin esto su tooltip (cuenta, error, subagentes) no se ve.
	_status_label.mouse_filter = Control.MOUSE_FILTER_PASS
	status_row.add_child(_remote_button)
	# Cerrar sesión de la cuenta (ACP `logout`), para cualquier agente que lo anuncie.
	_logout_button = Button.new()
	_logout_button.text = I18n.t("Sign out")
	_logout_button.flat = true
	_logout_button.add_theme_font_size_override(&"font_size", AgentTheme.px(12))
	_logout_button.tooltip_text = I18n.t("Sign out of this agent's account: the next session asks you to sign in.")
	_logout_button.pressed.connect(_confirm_logout)
	status_row.add_child(_logout_button)
	# El estado va en el chip del header (m12-14); Remote Control y cerrar sesión, en «⋯».
	status_row.visible = false
	# Plegable (m7-26): el título y los botones quedan a la vista; el link, el QR y la aclaración se
	# pliegan. El estado se conserva mientras el editor está abierto.
	_remote_banner = FoldableContainer.new()
	_remote_banner.title = "● " + I18n.t("Remote Control on")
	_remote_banner.title_text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_remote_banner.tooltip_text = I18n.t("Click the title to fold or unfold.")
	var title_panel := AgentTheme.panel(Color(_accent, 0.08), Color(_accent, 0.5), 4, 6)
	for item: StringName in [&"title_panel", &"title_hover_panel", &"title_collapsed_panel", &"title_collapsed_hover_panel"]:
		_remote_banner.add_theme_stylebox_override(item, title_panel)
	_remote_banner.add_theme_stylebox_override(&"panel", AgentTheme.panel(Color(_accent, 0.05), Color(_accent, 0.5), 4, 6))
	for item: StringName in [&"font_color", &"hover_font_color", &"collapsed_font_color"]:
		_remote_banner.add_theme_color_override(item, _accent)
	var column := VBoxContainer.new()
	_remote_banner.add_child(column)
	_remote_qr_button = Button.new()
	_remote_qr_button.text = I18n.t("QR")
	_remote_qr_button.flat = true
	_remote_qr_button.toggle_mode = true
	_remote_qr_button.tooltip_text = I18n.t("Show a QR code of the link, to open the session on your phone.")
	_remote_qr_button.toggled.connect(func(on: bool) -> void:
		_remote_qr.visible = on
		if on:
			_remote_banner.expand())
	_remote_banner.add_title_bar_control(_remote_qr_button)
	var copy := Button.new()
	copy.text = I18n.t("Copy link")
	copy.flat = true
	copy.pressed.connect(func() -> void: DisplayServer.clipboard_set(_model.remote_control_url))
	_remote_banner.add_title_bar_control(copy)
	var off := Button.new()
	off.text = I18n.t("Turn off")
	off.flat = true
	off.add_theme_color_override(&"font_color", AgentTheme.ERROR)
	off.pressed.connect(func() -> void: _on_submitted(_controller.remote_control_command(false)))
	_remote_banner.add_title_bar_control(off)
	# Button y no LinkButton: LinkButton pide el ancho del link entero y ensancha el dock.
	_remote_link = Button.new()
	_remote_link.flat = true
	_remote_link.clip_text = true
	_remote_link.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_remote_link.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_remote_link.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_remote_link.add_theme_color_override(&"font_color", _accent)
	_remote_link.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_remote_link.pressed.connect(func() -> void: OS.shell_open(_model.remote_control_url))
	column.add_child(_remote_link)
	_remote_qr = QrView.new()
	_remote_qr.visible = false
	column.add_child(_remote_qr)
	var hint := Label.new()
	hint.text = I18n.t("What you write from the phone and its answers only show there. Here you see the tool calls that ask for permission, and you can answer them from either side.")
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_color_override(&"font_color", AgentTheme.MUTED)
	hint.add_theme_font_size_override(&"font_size", AgentTheme.px(11))
	column.add_child(hint)
	add_child(_remote_banner)
	move_child(_remote_banner, status_row.get_index() + 1)
	_model.remote_control_changed.connect(func(_url: String) -> void: _refresh_remote_control())
	_model.commands_changed.connect(func(_commands: Array) -> void: _refresh_remote_control())
	_model.harness_mode_changed.connect(func(_mode: SessionModel.HarnessMode) -> void: _refresh_remote_control())


## El botón aparece si el agente publica `/remote-control`, fuera de One-shot (sus turnos no
## pasarían por el run). La franja, mientras está prendido.
func _refresh_remote_control() -> void:
	if not _remote_button:
		return
	var on := not _model.remote_control_url.is_empty()
	_remote_button.visible = _model.supports_remote_control() and _model.harness_mode != SessionModel.HarnessMode.ONESHOT and not on
	_remote_button.disabled = _model.state != SessionModel.SessionState.READY
	_logout_button.visible = _model.supports_logout() and _controller.is_connected_to_agent()
	_logout_button.disabled = _model.state != SessionModel.SessionState.READY
	_remote_banner.visible = on
	_remote_link.text = _model.remote_control_url
	_remote_qr.set_text(_model.remote_control_url)
	_remote_link.tooltip_text = _model.remote_control_url


func _show_agent_menu() -> void:
	_agent_menu.clear()
	var active := _settings.active_profile()
	for i in _profiles.size():
		_agent_menu.add_radio_check_item(_profiles[i].display_name, i)
		_agent_menu.set_item_checked(_agent_menu.item_count - 1, active != null and _profiles[i].id == active.id)
		_agent_menu.set_item_tooltip(_agent_menu.item_count - 1, _profiles[i].command_line())
	if not _profiles.is_empty():
		_agent_menu.add_separator()
	_agent_menu.add_item(I18n.t("Manage agents…"), AGENT_MENU_MANAGE)
	var below := _agent_chip.get_screen_position() + Vector2(0, _agent_chip.size.y)
	_agent_menu.popup(Rect2i(Vector2i(below), Vector2i.ZERO))


func _fill_more_menu() -> void:
	var popup := _more_button.get_popup()
	popup.clear()
	popup.add_icon_item(AgentTheme.icon(&"EditorPlugin"), I18n.t("Extensions…"), MORE_EXTENSIONS)
	popup.add_icon_item(AgentTheme.icon(&"Tools"), I18n.t("Settings…"), MORE_SETTINGS)
	if _remote_button.visible or _logout_button.visible:
		popup.add_separator()
	if _remote_button.visible:
		popup.add_item(I18n.t("Remote Control"), MORE_REMOTE)
		popup.set_item_tooltip(popup.item_count - 1, _remote_button.tooltip_text)
		popup.set_item_disabled(popup.item_count - 1, _remote_button.disabled)
	if _logout_button.visible:
		popup.add_item(I18n.t("Sign out"), MORE_LOGOUT)
		popup.set_item_tooltip(popup.item_count - 1, _logout_button.tooltip_text)
		popup.set_item_disabled(popup.item_count - 1, _logout_button.disabled)


func _on_more_selected(id: int) -> void:
	match id:
		MORE_EXTENSIONS:
			extensions_requested.emit()
		MORE_SETTINGS:
			settings_requested.emit()
		MORE_REMOTE:
			_remote_button.pressed.emit()
		MORE_LOGOUT:
			_confirm_logout()


func _confirm_logout() -> void:
	if _logout_dialog == null:
		_logout_dialog = ConfirmationDialog.new()
		_logout_dialog.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		_logout_dialog.title = I18n.t("Sign out")
		_logout_dialog.ok_button_text = I18n.t("Sign out")
		_logout_dialog.cancel_button_text = I18n.t("Cancel")
		_logout_dialog.confirmed.connect(func() -> void: _controller.logout())
		add_child(_logout_dialog)
	var profile := _controller.profile()
	var who := str(_model.account.get("email", ""))
	var name := profile.display_name if profile else I18n.t("Agent")
	_logout_dialog.dialog_text = (I18n.t("Sign out of %s (%s)?") % [name, who] if not who.is_empty() else I18n.t("Sign out of %s?") % name) + "\n" + I18n.t("The agent deletes its saved credentials; the session closes.")
	_logout_dialog.popup_centered()


func _refresh_modes() -> void:
	if _composer:
		_composer.set_current_mode(_model.harness_mode)
	if _review_panel:
		_review_panel.visible = _model.harness_mode == SessionModel.HarnessMode.REVIEW


# --- cuota del plan -------------------------------------------------------------------------------

func _build_quota_ring() -> void:
	_quota_ring = QuotaRing.new()
	_quota_ring.setup(_controller.quota, _accent)
	_composer.add_status_control(_quota_ring)
	_quota_timer = Timer.new()
	_quota_timer.wait_time = 1.0
	_quota_timer.timeout.connect(_on_quota_tick)
	add_child(_quota_timer)
	_controller.quota.changed.connect(_on_quota_changed)
	_quota_state = _controller.quota.state
	_on_quota_changed()


## Fuera de One-shot solo hay avisos (spec §10.1); en "limitado" se bloquea el envío.
func _on_quota_changed() -> void:
	var quota := _controller.quota
	if quota.state != _quota_state:
		match quota.state:
			QuotaMonitor.QuotaState.WARNING, QuotaMonitor.QuotaState.PAUSE_SCHEDULED:
				if _quota_state in [QuotaMonitor.QuotaState.UNKNOWN, QuotaMonitor.QuotaState.NORMAL]:
					_model.add_notice(I18n.t("Plan quota at %d %%.") % roundi(quota.max_utilization() * 100.0), ChatEntry.NoticeLevel.WARNING)
			QuotaMonitor.QuotaState.LIMITED:
				if quota.limited_until > 0:
					var wait := QuotaMonitor.format_duration(quota.limited_until - int(Time.get_unix_time_from_system()))
					_model.add_notice(I18n.t("Plan limit reached. It resets in %s.") % wait, ChatEntry.NoticeLevel.ERROR)
				else:
					_model.add_notice(I18n.t("Plan limit reached. The agent did not say when it resets."), ChatEntry.NoticeLevel.ERROR)
		_quota_state = quota.state
	_on_quota_tick()
	if quota.is_limited() or quota.has_data():
		_quota_timer.start()
	else:
		_quota_timer.stop()


func _on_quota_tick() -> void:
	var quota := _controller.quota
	_quota_ring.refresh()
	if quota.is_limited() and quota.seconds_until_retry() > 0:
		_composer.set_locked("⏳ %s" % QuotaMonitor.format_duration(quota.seconds_until_retry()), I18n.t("Plan limit reached: you can send again when the window resets"))
	else:
		_composer.set_locked("")


# --- revisión ------------------------------------------------------------------------------------

func _build_review_panel() -> void:
	_review_panel = ReviewPanel.new()
	_review_panel.setup(_controller.review, _accent)
	_review_panel.finding_selected.connect(func(id: int) -> void: action_forwarded.emit(ACTION_REVIEW_FOCUS, id))
	_review_panel.fix_all_requested.connect(func() -> void: action_forwarded.emit(ACTION_REVIEW_FIX_ALL, null))
	_review_panel.export_requested.connect(_on_review_export_requested)
	_review_panel.github_import_requested.connect(_on_github_import_requested)
	add_child(_review_panel)
	move_child(_review_panel, _body.get_index())
	_export_dialog = ConfirmationDialog.new()
	_export_dialog.cancel_button_text = I18n.t("Cancel")
	_export_dialog.title = I18n.t("Export to CLAUDE.md")
	_export_dialog.ok_button_text = I18n.t("Add to CLAUDE.md")
	_export_dialog.min_size = Vector2i(AgentTheme.px(560), AgentTheme.px(360))
	_export_preview = TextEdit.new()
	_export_preview.editable = true  # vista previa editable antes de agregar
	_export_preview.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_export_dialog.add_child(_export_preview)
	_export_dialog.confirmed.connect(_on_review_export_confirmed)
	add_child(_export_dialog)


func _on_review_export_requested() -> void:
	var review := _controller.review
	_export_preview.text = ReviewStore.claude_md_section(review.findings, Time.get_date_string_from_system())
	var exists := FileAccess.file_exists(ReviewStore.CLAUDE_MD_PATH)
	_export_dialog.title = I18n.t("Append to CLAUDE.md") if exists else I18n.t("Create CLAUDE.md")
	_export_dialog.popup_centered()


func _on_review_export_confirmed() -> void:
	var error := ReviewStore.append_to_claude_md(_export_preview.text)
	if not error.is_empty():
		_model.add_notice(I18n.t("Could not write CLAUDE.md: %s") % error, ChatEntry.NoticeLevel.ERROR)
		return
	EditorInterface.get_resource_filesystem().update_file(ReviewStore.CLAUDE_MD_PATH)
	_model.add_notice(I18n.t("Review conventions added to CLAUDE.md."))


func _reload_profiles() -> void:
	_profiles = _settings.profiles()
	_profile_button.clear()
	var active := _settings.active_profile()
	for profile: AgentProfile in _profiles:
		_profile_button.add_item("✦ " + profile.display_name)
		_profile_button.set_item_tooltip(_profile_button.item_count - 1, profile.command_line())
		if active and profile.id == active.id:
			_profile_button.select(_profile_button.item_count - 1)
	_refresh_empty_state()


func _on_profile_selected(index: int) -> void:
	if index < 0 or index >= _profiles.size():
		return
	_settings.set_active_profile(_profiles[index].id)
	_refresh_empty_state()
	var current := _controller.profile()
	if current and current.id != _profiles[index].id and _controller.is_connected_to_agent():
		_model.add_notice(I18n.t("The %s profile is used when you press \"New session\".") % _profiles[index].display_name)


func _refresh_title() -> void:
	_title_label.text = _model.title if not _model.title.is_empty() else (I18n.t("New session") if not _model.session_id.is_empty() else "")
	_title_label.tooltip_text = _title_label.text


## Tooltip de la cuenta: «Account: email», la organización y el plan.
static func account_summary(account: Dictionary) -> String:
	if str(account.get("email", "")).is_empty():
		return ""
	var lines: PackedStringArray = [I18n.t("Account: %s") % account.email]
	# En una cuenta personal la organización es «<email>'s Organization»: no suma nada.
	if not str(account.get("org", "")).is_empty() and not str(account.org).contains(account.email):
		lines.append(I18n.t("Organization: %s") % account.org)
	if not str(account.get("plan", "")).is_empty():
		lines.append(I18n.t("Plan: %s") % str(account.plan).capitalize())
	return "\n".join(lines)


func _refresh_state() -> void:
	var profile := _controller.profile() if _controller.profile() else _settings.active_profile()
	var name := profile.display_name if profile else I18n.t("Agent")
	var text := ""
	var color := AgentTheme.MUTED
	match _model.state:
		SessionModel.SessionState.DISCONNECTED:
			text = I18n.t("○ %s · not started") % name
		SessionModel.SessionState.STARTING:
			text = I18n.t("◌ %s · connecting…") % name
			color = _accent
		SessionModel.SessionState.READY:
			text = I18n.t("● %s · ready") % name
			color = AgentTheme.ADDED
		SessionModel.SessionState.PROMPTING:
			text = I18n.t("● %s · working…") % name
			color = _accent
			var subagents := _model.running_subagents()
			if not subagents.is_empty():
				text += " · " + (I18n.t("%d subagent") if subagents.size() == 1 else I18n.t("%d subagents")) % subagents.size()
		SessionModel.SessionState.CANCELLING:
			text = I18n.t("● %s · cancelling…") % name
			color = AgentTheme.WARNING
		SessionModel.SessionState.FAILED:
			if _model.login_required:
				text = I18n.t("○ %s · sign-in needed") % name
			else:
				text = I18n.t("✗ %s · error") % name
				color = AgentTheme.ERROR
	var email := str(_model.account.get("email", ""))
	if not email.is_empty() and _model.state != SessionModel.SessionState.DISCONNECTED:
		text += " · " + email
	_status_label.text = text
	_status_label.tooltip_text = _model.failure_message if not _model.failure_message.is_empty() else account_summary(_model.account)
	if _model.state == SessionModel.SessionState.PROMPTING:
		var names := _model.running_subagents().map(func(call: SessionModel.ToolCall) -> String: return "• " + call.display_name())
		if not names.is_empty():
			_status_label.tooltip_text = I18n.t("Subagents running:") + "\n" + "\n".join(names)
	_status_label.add_theme_color_override(&"font_color", color)
	if _agent_chip:
		_agent_chip.text = text
		_agent_chip.tooltip_text = (_status_label.tooltip_text + "\n" if not _status_label.tooltip_text.is_empty() else "") + I18n.t("Click to choose the agent")
		for item: StringName in [&"font_color", &"font_hover_color", &"font_pressed_color", &"font_focus_color"]:
			_agent_chip.add_theme_color_override(item, color)
	_composer.set_busy(_model.is_busy())
	_composer.set_enabled(_model.state != SessionModel.SessionState.STARTING)
	_composer.set_screenshot_available(_model.session_id.is_empty() or _model.supports_image())
	_new_session_button.disabled = _model.state == SessionModel.SessionState.STARTING or _model.is_busy()
	_refresh_remote_control()
	_refresh_title()
	_refresh_empty_state()


func _refresh_empty_state() -> void:
	if _empty_state == null or _conversation == null:
		return
	var entries := _model.entries()
	var only_notices := entries.all(func(entry: ChatEntry) -> bool: return entry.kind == ChatEntry.EntryKind.NOTICE)
	# Sin sesión y con solo avisos (p. ej. el del One-shot a medias al reabrir el editor), el botón
	# para arrancar sigue a la vista debajo de los avisos.
	var idle := _model.state == SessionModel.SessionState.DISCONNECTED or (entries.is_empty() and _model.state == SessionModel.SessionState.FAILED)
	_empty_state.visible = idle and only_notices
	_conversation.visible = not entries.is_empty()
	var profile := _settings.active_profile()
	# Primer arranque: no hay agentes preseteados y el botón lleva a elegir uno (Settings → Agentes).
	# Un One-shot a medias se retoma con el agente del run, aunque no haya perfiles guardados.
	if _oneshot_active:
		_start_button.text = I18n.t("Resume One-shot")
	elif profile == null:
		_start_button.text = I18n.t("Other agents…")
	else:
		_start_button.text = I18n.t("Start session")
	_suggested_box.visible = profile == null and not _oneshot_active
	_composer.set_unavailable(I18n.t("Add an agent to start") if profile == null and _controller.profile() == null else "")
	_empty_command.text = profile.command_line() if profile else I18n.t("Add an agent to start:")
	_empty_command.add_theme_color_override(&"font_color", AgentTheme.MUTED)
	_start_button.disabled = _model.state == SessionModel.SessionState.STARTING
	var recent: Array[Dictionary] = []
	if _empty_state.visible and profile != null and not _oneshot_active and _controller.history:
		recent = _controller.history.list(_controller.cwd).slice(0, RECENT_SESSIONS)
	if not recent.is_empty() and _start_button.text == I18n.t("Start session"):
		_start_button.text = I18n.t("New session")
	_refresh_recent(recent)


func _refresh_recent(items: Array[Dictionary]) -> void:
	var signature := ",".join(items.map(func(item: Dictionary) -> String: return "%s:%s" % [item.get("id", ""), item.get("updated", 0)]))
	_recent_box.visible = not items.is_empty()
	if signature == _recent_signature:
		return
	_recent_signature = signature
	for child: Node in _recent_box.get_children():
		_recent_box.remove_child(child)
		child.queue_free()
	if items.is_empty():
		return
	var heading := Label.new()
	heading.text = I18n.t("Previous sessions")
	heading.add_theme_color_override(&"font_color", AgentTheme.MUTED)
	_recent_box.add_child(heading)
	for item: Dictionary in items:
		_recent_box.add_child(_recent_row(item))


## Un agente sugerido (m12-15): nombre, lo que pide y «Agregar». Claude Code se guarda directo; los
## demás abren el registro de ACP filtrado, desde Ajustes.
func _suggested_row(agent: Dictionary) -> Control:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override(&"panel", AgentTheme.panel(Color(1, 1, 1, 0.04), Color(1, 1, 1, 0.1), 6, 8))
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", AgentTheme.px(8))
	card.add_child(row)
	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.add_theme_constant_override(&"separation", 0)
	row.add_child(text)
	var name_label := Label.new()
	name_label.text = str(agent.name)
	text.add_child(name_label)
	var needs := Label.new()
	needs.text = I18n.t(str(agent.needs))
	needs.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	needs.add_theme_color_override(&"font_color", AgentTheme.MUTED)
	text.add_child(needs)
	var add := Button.new()
	add.text = I18n.t("Add")
	add.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	add.pressed.connect(func() -> void: add_suggested_agent(agent))
	row.add_child(add)
	return card


func add_suggested_agent(agent: Dictionary) -> void:
	var data := SuggestedAgents.profile_of(agent)
	if data.is_empty():
		registry_requested.emit(str(agent.get("registry_query", "")))
		return
	var list := _settings.profiles()
	data["default"] = list.is_empty()
	list.append(AgentProfile.from_dict(data))
	_settings.save_profiles(list)
	_settings.set_active_profile(str(data.id))


## Una sesión anterior: título, «agente · cuándo · N turnos» y «Continuar».
func _recent_row(item: Dictionary) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", AgentTheme.px(8))
	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.add_theme_constant_override(&"separation", 0)
	row.add_child(text)
	var title := Label.new()
	title.text = str(item.get("title", "")) if not str(item.get("title", "")).is_empty() else I18n.t("(untitled)")
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title.clip_text = true
	title.tooltip_text = title.text
	text.add_child(title)
	var meta := Label.new()
	meta.text = recent_meta(item, _timezone_bias_s())
	meta.add_theme_color_override(&"font_color", AgentTheme.MUTED)
	meta.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	meta.clip_text = true
	text.add_child(meta)
	var resume := Button.new()
	resume.text = I18n.t("Continue")
	resume.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var id := str(item.get("id", ""))
	resume.pressed.connect(func() -> void:
		if _model.state in [SessionModel.SessionState.DISCONNECTED, SessionModel.SessionState.FAILED]:
			open_history_session(id))
	row.add_child(resume)
	return row


## «Claude Code · 29/10 03:56 · 4 turns».
static func recent_meta(item: Dictionary, bias_s: int = 0) -> String:
	var parts: PackedStringArray = []
	if not str(item.get("agent", "")).is_empty():
		parts.append(str(item.agent))
	var updated := int(item.get("updated", 0))
	if updated > 0:
		var stamp := Time.get_datetime_string_from_unix_time(updated + bias_s, true)
		parts.append("%s/%s %s" % [stamp.substr(8, 2), stamp.substr(5, 2), stamp.substr(11, 5)])
	var turns := int(item.get("turns", 0))
	if turns > 0:
		parts.append((I18n.t("%d turn") if turns == 1 else I18n.t("%d turns")) % turns)
	return " · ".join(parts)


## Al abrir el editor con «Continuar la última sesión» (m12-12). false si no había ninguna.
func continue_last_session() -> bool:
	if _controller.history == null or _model.state != SessionModel.SessionState.DISCONNECTED or _oneshot_active:
		return false
	var items: Array[Dictionary] = _controller.history.list(_controller.cwd)
	if items.is_empty() or _settings.active_profile() == null:
		return false
	return await open_history_session(str(items[0].get("id", "")))


# --- sesión --------------------------------------------------------------------------------------

## Con un One-shot activo, el botón lo retoma en su sesión (como «Reintentar», D45).
func _on_start_pressed() -> void:
	if _oneshot_active and retry_interceptor.is_valid() and retry_interceptor.call():
		return
	_start_session()


func _start_session() -> void:
	var profile := _settings.active_profile()
	if profile == null:
		settings_requested.emit()
		return
	var started: bool = await _controller.start(profile)
	if not is_inside_tree():  # se cerró la pestaña o el plugin mientras esperaba
		return
	if started:
		_warn_api_key(profile)
		_composer.focus()
		if not _pending_prompt.is_empty():
			var text := _pending_prompt
			_pending_prompt = ""
			_send(text)


func _warn_api_key(profile: AgentProfile) -> void:
	var key := _controller.adapter.api_key_variable()
	if not key.is_empty() and (OS.has_environment(key) or profile.env.has(key)):
		_model.add_notice(
			I18n.t("There is an ANTHROPIC_API_KEY in the environment: Claude Code may bill through the API instead of using your subscription."),
			ChatEntry.NoticeLevel.WARNING
		)


## Sesiones de este proyecto, la más reciente primero (spec §11 y session/list de m11-16).
func _show_history_menu() -> void:
	_history_menu.clear()
	_history_delete_menu.clear()
	var local_items: Array[Dictionary] = _controller.history.list(_controller.cwd) if _controller.history else []
	_history_items = SessionController.merge_session_lists(local_items, _controller.agent_sessions, HISTORY_MENU_SIZE)
	if _controller.is_connected_to_agent() and _model.supports_list_sessions():
		_controller.list_agent_sessions(_controller.cwd)
	if _history_items.is_empty():
		_history_menu.add_item(I18n.t("No saved sessions for this project"))
		_history_menu.set_item_disabled(0, true)
	for i in _history_items.size():
		var item := _history_items[i]
		var title := str(item.get("title", "")) if not str(item.get("title", "")).is_empty() else I18n.t("(untitled)")
		var updated := int(item.get("updated", 0))
		var when := Time.get_datetime_string_from_unix_time(updated + _timezone_bias_s(), true).substr(5, 11).replace("-", "/") if updated > 0 else "—"
		var label := "%s · %s · %s" % [when, title, item.get("agent", "")]
		_history_menu.add_item(label, i)
		var turns := int(item.get("turns", 0))
		_history_menu.set_item_tooltip(_history_menu.item_count - 1, (I18n.t("%d turns · %s") % [turns, item.get("id", "")]) if turns > 0 else str(item.get("id", "")))
		if item.get("id") == _model.session_id:
			_history_menu.set_item_disabled(_history_menu.item_count - 1, true)
		else:
			_history_delete_menu.add_item(label, i)
	if _history_delete_menu.item_count > 0:
		_history_menu.add_separator()
		_history_menu.add_submenu_node_item(I18n.t("Delete session"), _history_delete_menu)
	var busy := _model.state in [SessionModel.SessionState.STARTING, SessionModel.SessionState.PROMPTING, SessionModel.SessionState.CANCELLING]
	for i in _history_menu.item_count:
		_history_menu.set_item_disabled(i, _history_menu.is_item_disabled(i) or busy)
	var below: Vector2 = _history_button.get_screen_position() + Vector2(0, _history_button.size.y)
	_history_menu.popup(Rect2i(Vector2i(below), Vector2i.ZERO))


## Muestra la sesión y la reanuda con session/load o session/resume si el agente lo soporta.
func open_history_session(id: String) -> bool:
	var record: Dictionary = _controller.history.load_record(id) if _controller.history else {}
	if record.is_empty():
		for item: Dictionary in _controller.agent_sessions:
			if str(item.get("id", "")) == id:
				record = item.duplicate()
				break
	if record.is_empty():
		_model.add_notice(I18n.t("Could not read session %s from the history.") % id, ChatEntry.NoticeLevel.WARNING)
		return false
	var profile := _settings.profile(str(record.get("profile_id", "")))
	if profile == null:
		profile = _settings.active_profile()
	if profile == null:
		return false
	return await _controller.start(profile, record)


func _on_history_delete_selected(index: int) -> void:
	if index < 0 or index >= _history_items.size():
		return
	var item := _history_items[index]
	var id := str(item.get("id", ""))
	if id.is_empty() or id == _model.session_id:
		return
	if _delete_session_dialog == null:
		_delete_session_dialog = ConfirmationDialog.new()
		_delete_session_dialog.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		_delete_session_dialog.title = I18n.t("Delete session")
		_delete_session_dialog.ok_button_text = I18n.t("Delete")
		_delete_session_dialog.cancel_button_text = I18n.t("Cancel")
		add_child(_delete_session_dialog)
	var title := str(item.get("title", "")) if not str(item.get("title", "")).is_empty() else I18n.t("(untitled)")
	_delete_session_dialog.dialog_text = I18n.t("Delete «%s»? It cannot be undone; if the agent keeps it too, it is deleted there as well.") % title
	for connection: Dictionary in _delete_session_dialog.confirmed.get_connections():
		_delete_session_dialog.confirmed.disconnect(connection.callable)
	_delete_session_dialog.confirmed.connect(func() -> void:
		_controller.delete_session(id, str(item.get("profile_id", ""))), CONNECT_ONE_SHOT)
	_delete_session_dialog.popup_centered()


func _on_history_selected(index: int) -> void:
	if index < 0 or index >= _history_items.size():
		return
	# El estado pudo cambiar con el menú abierto.
	if _model.state in [SessionModel.SessionState.STARTING, SessionModel.SessionState.PROMPTING, SessionModel.SessionState.CANCELLING]:
		return
	if can_switch_session.is_valid() and not can_switch_session.call():
		_model.add_notice(I18n.t("A One-shot is running: stop it before opening another session."), ChatEntry.NoticeLevel.WARNING)
		return
	open_history_session(str(_history_items[index].get("id", "")))


static func _timezone_bias_s() -> int:
	return int(Time.get_time_zone_from_system().get("bias", 0)) * 60


func _on_new_session_pressed() -> void:
	var active := _settings.active_profile()
	var current := _controller.profile()
	if _controller.is_connected_to_agent() and current and active and current.id == active.id:
		_controller.open_session()
	else:
		_start_session()


func _on_submitted(text: String) -> void:
	_composer.clear()
	if submit_interceptor.is_valid() and submit_interceptor.call(text):
		return
	if _model.is_busy() or (_model.state == SessionModel.SessionState.STARTING and not _pending_prompt.is_empty()):
		_queue.add(text, _take_context_blocks())
		return
	match _model.state:
		SessionModel.SessionState.READY:
			_send(text)
		SessionModel.SessionState.STARTING:
			_pending_prompt = text
		SessionModel.SessionState.DISCONNECTED, SessionModel.SessionState.FAILED:
			_pending_prompt = text
			_start_session()


func _send(text: String) -> void:
	# Un comando con / va solo: los adjuntos quedan para el próximo mensaje (ver send_prompt).
	if SessionController.is_slash_command(text):
		_controller.send_prompt(text)
		return
	_send_with_mentions(text, _take_context_blocks())


## Manda el prompt con el contexto de sus menciones especiales (@errors, @game…) agregado.
func _send_with_mentions(text: String, blocks: Array) -> void:
	var expanded := blocks.duplicate()
	for mention: Dictionary in special_mentions_in(text):
		var found: String = await context_provider.call(mention.kind, mention.arg) if context_provider.is_valid() else ""
		if not is_inside_tree():  # se cerró la pestaña o el plugin mientras esperaba
			return
		expanded.append({"type": "text", "text": "Context the user attached with @%s:\n%s" % [mention.token, found if not found.strip_edges().is_empty() else "(nothing)"]})
	_controller.send_prompt(text, expanded)


## Las menciones especiales de `text`, sin repetir: `[{token, kind, arg}]` (`arg`: la clase de @docs:).
static func special_mentions_in(text: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var regex := RegEx.create_from_string("(?<![\\w@])@(errors|output|game|docs:([A-Za-z_@][A-Za-z0-9_]*))(?![\\w:])")
	var seen := {}
	for found: RegExMatch in regex.search_all(text):
		var token := found.get_string(1)
		if seen.has(token):
			continue
		seen[token] = true
		result.append({"token": token, "kind": "docs" if token.begins_with("docs:") else token, "arg": found.get_string(2)})
	return result


## Las menciones especiales para el menú de @ (van primero).
static func special_mention_options() -> Array[Dictionary]:
	return [
		{"label": "@errors · " + I18n.t("the editor's errors and warnings"), "insert": "errors"},
		{"label": "@output · " + I18n.t("the end of the Output panel"), "insert": "output"},
		{"label": "@game · " + I18n.t("the running game's node tree"), "insert": "game"},
		{"label": "@docs:Class · " + I18n.t("the API reference of a class"), "insert": "docs:"},
	]


## El contexto adjunto para un prompt; la captura y los archivos agregados se usan una sola vez.
func _take_context_blocks() -> Array:
	var blocks := _context_blocks()
	_images.clear()
	_extra_files.clear()
	_refresh_chips()
	return blocks


# --- cola de prompts -----------------------------------------------------------------------------

## Con end_turn sale el próximo de la cola; si el turno terminó de otra forma, la cola espera al
## usuario (lo que había pedido puede ya no tener sentido).
func _on_turn_finished(stop_reason: String) -> void:
	var interrupted := _interrupt_for_queue
	_interrupt_for_queue = false
	if _queue.is_empty():
		return
	if interrupted:
		_send_next_queued.call_deferred(true)
	elif stop_reason == "end_turn":
		_send_next_queued.call_deferred()
	else:
		_queue.pause(_pause_reason(stop_reason))


static func _pause_reason(stop_reason: String) -> String:
	match stop_reason:
		"cancelled":
			return I18n.t("the turn was cancelled")
		"error":
			return I18n.t("the turn ended with an error")
		"refusal":
			return I18n.t("the agent refused to continue")
		_:
			return I18n.t("the turn ended with «%s»") % stop_reason


## `resume`: el usuario pidió «Enviar ahora» (si no, solo sale si la cola no está en pausa).
func _send_next_queued(resume: bool = false) -> void:
	if _model.state != SessionModel.SessionState.READY or _queue.is_empty():
		return
	if resume:
		_queue.resume()
	if _queue.paused:
		return
	if can_switch_session.is_valid() and not can_switch_session.call():
		_queue.pause(I18n.t("a One-shot is running"))
		return
	var quota := _controller.quota
	if quota.is_limited() and quota.seconds_until_retry() > 0:
		_queue.pause(I18n.t("plan limit"))
		return
	var item := _queue.take_next()
	if not item.is_empty():
		_send_with_mentions(str(item.text), item.blocks)


## «Enviar ahora» de un prompt de la cola: pasa al frente y, si el agente está trabajando, se
## cancela el turno; sale apenas el agente confirma la cancelación. El resto de la cola sigue después.
func _send_queued_now(index: int) -> void:
	_queue.move_to_front(index)
	_queue.resume()
	if _model.is_busy():
		_interrupt_for_queue = true
		_controller.cancel()
	else:
		_send_next_queued(true)


## Un mensaje de otra sesión abierta en el editor (m7-44): sale como prompt apenas esta queda libre,
## detrás de lo que ya esperaba en la cola. false si la sesión no está conectada.
func deliver_message(text: String) -> bool:
	if not _controller.is_connected_to_agent():
		return false
	if _model.state == SessionModel.SessionState.READY and _queue.is_empty():
		_controller.send_prompt(text)
	else:
		_queue.add(text)
	return true


func _on_cancel_requested() -> void:
	_controller.cancel()


func _on_action_requested(action: String, payload: Variant) -> void:
	match action:
		SessionController.ACTION_RETRY:
			if retry_interceptor.is_valid() and retry_interceptor.call():
				return
			_start_session()
		SessionController.ACTION_SHOW_LOG:
			show_log_requested.emit(int(payload) if payload is int else 0)
		SessionController.ACTION_EDIT_AGENT:
			settings_requested.emit()
		SessionController.ACTION_LOGIN:
			_controller.login(str(payload))
		SessionController.ACTION_LOGIN_CODE:
			_ask_login_code()
		SessionController.ACTION_LOGIN_CANCEL:
			_controller.cancel_login()
		"open_link":
			var url := str(payload)
			if url.begins_with("http://") or url.begins_with("https://"):
				OS.shell_open(url)
				return
			var target := MarkdownBBCode.link_target(url)
			var absolute := _absolute_path(target.path)
			if absolute.get_extension().to_lower() in IMAGE_EXTENSIONS and FileAccess.file_exists(absolute):
				var image := Image.load_from_file(absolute)
				if image != null and not image.is_empty():
					ImageViewer.open(image, str(target.path).get_file(), self)
					return
			_open_path(target.path, target.line)
		"open_location":
			var location: Dictionary = payload
			_open_path(str(location.path), int(location.get("line", 0)))
		_:
			action_forwarded.emit(action, payload)


## Un archivo del chat: escenas y scripts en el editor; spec y progreso del One-shot en la pantalla
## Agent; el resto de los archivos de texto (.md, .txt…), que Godot no carga, con el programa del
## sistema.
func set_oneshot_active(active: bool) -> void:
	_oneshot_active = active
	_composer.set_oneshot_active(active)
	_refresh_empty_state()


func _open_path(path: String, line: int) -> void:
	var absolute := _absolute_path(path)
	if absolute.contains("/.godot_agent/oneshot/"):
		action_forwarded.emit(ACTION_OPEN_RUN_FILE, {"path": absolute})
		return
	if EditorContext.open_location(absolute, line):
		return
	if FileAccess.file_exists(absolute):
		OS.shell_open(absolute)
		return
	_model.add_notice(I18n.t("Could not open %s.") % path, ChatEntry.NoticeLevel.WARNING)


## Ruta de un link del chat: res://, absoluta o relativa al proyecto.
static func _absolute_path(path: String) -> String:
	var absolute := path
	if path.begins_with("res://"):
		absolute = ProjectSettings.globalize_path(path)
	elif not path.is_absolute_path():
		absolute = ProjectSettings.globalize_path("res://").path_join(path.trim_prefix("./"))
	return absolute.simplify_path()


func _ask_login_code() -> void:
	if _login_code_dialog == null:
		_login_code_dialog = ConfirmationDialog.new()
		_login_code_dialog.cancel_button_text = I18n.t("Cancel")
		_login_code_dialog.title = I18n.t("Sign-in code")
		_login_code_dialog.ok_button_text = I18n.t("Send")
		var column := VBoxContainer.new()
		var hint := Label.new()
		hint.text = I18n.t("Paste the code shown by the login page.")
		column.add_child(hint)
		_login_code_input = LineEdit.new()
		_login_code_input.secret = true
		_login_code_input.custom_minimum_size.x = AgentTheme.px(360)
		column.add_child(_login_code_input)
		_login_code_dialog.add_child(column)
		_login_code_dialog.register_text_enter(_login_code_input)
		_login_code_dialog.confirmed.connect(func() -> void:
			if not _controller.send_login_code(_login_code_input.text):
				_model.add_notice(I18n.t("No sign-in is waiting for a code."), ChatEntry.NoticeLevel.WARNING)
			_login_code_input.clear()
		)
		add_child(_login_code_dialog)
	_login_code_input.clear()
	_login_code_dialog.popup_centered()
	_login_code_input.grab_focus()


# --- contexto del prompt -------------------------------------------------------------------------

func _refresh_chips() -> void:
	if not is_visible_in_tree() and not _chips.is_empty():
		return
	var chips: Dictionary = {}
	var scene_path := EditorContext.current_scene_path()
	if not scene_path.is_empty() and not _dismissed_chips.has(CHIP_SCENE + "|" + scene_path):
		chips[CHIP_SCENE] = {
			"label": "🎬 " + scene_path.get_file(),
			"tooltip": I18n.t("Open scene: %s (click to remove it)") % scene_path,
			"block": {"type": "resource_link", "uri": EditorContext.file_uri(scene_path), "name": scene_path.get_file(), "mimeType": "text/plain"},
		}
	var selection := EditorContext.selection_description()
	if not selection.is_empty() and not _dismissed_chips.has(CHIP_SELECTION + "|" + selection):
		chips[CHIP_SELECTION] = {
			"label": I18n.t("Selection: %s") % ", ".join(EditorContext.selected_node_paths()).left(40),
			"tooltip": selection,
			"block": {"type": "text", "text": "Selection in the editor (scene %s): %s" % [scene_path, selection]},
		}
	chips.merge(_images)
	for res_path: String in _extra_files:
		chips[CHIP_FILE_PREFIX + res_path] = {
			"label": "📄 " + res_path.get_file(),
			"tooltip": I18n.t("%s (click to remove it)") % res_path,
			"block": {"type": "resource_link", "uri": EditorContext.file_uri(res_path), "name": res_path.get_file(), "mimeType": "text/plain"},
		}
	if _same_chips(chips) and _composer.has_chips():
		return
	_chips = chips
	var list: Array[Dictionary] = []
	for id: String in chips:
		list.append({"id": id, "label": chips[id].label, "tooltip": chips[id].tooltip})
	_composer.set_chips(list, _on_add_context_pressed)


func _same_chips(chips: Dictionary) -> bool:
	if chips.size() != _chips.size():
		return false
	for id: String in chips:
		if not _chips.has(id) or _chips[id].tooltip != chips[id].tooltip:
			return false
	return true


func _on_chip_removed(chip_id: String) -> void:
	match chip_id:
		CHIP_SCENE:
			_dismissed_chips[CHIP_SCENE + "|" + EditorContext.current_scene_path()] = true
		CHIP_SELECTION:
			_dismissed_chips[CHIP_SELECTION + "|" + EditorContext.selection_description()] = true
		_ when chip_id.begins_with(CHIP_IMAGE_PREFIX):
			_images.erase(chip_id)
		_:
			var index := _extra_files.find(chip_id.trim_prefix(CHIP_FILE_PREFIX))
			if index >= 0:
				_extra_files.remove_at(index)
	_refresh_chips()


## "+ contexto": script actual, un archivo del proyecto, una captura del viewport o del juego.
func _on_add_context_pressed() -> void:
	if _add_context_menu == null:
		_add_context_menu = PopupMenu.new()
		_add_context_menu.id_pressed.connect(_on_add_context_selected)
		add_child(_add_context_menu)
	_add_context_menu.clear()
	var script := EditorInterface.get_script_editor().get_current_script()
	if script and not script.resource_path.is_empty():
		_add_context_menu.add_item(I18n.t("Current script: %s") % script.resource_path.get_file(), ADD_CONTEXT_SCRIPT)
	_add_context_menu.add_item(I18n.t("Project file…"), ADD_CONTEXT_FILE)
	_add_context_menu.add_item(I18n.t("Viewport screenshot"), ADD_CONTEXT_SCREENSHOT)
	_add_context_menu.add_item(I18n.t("Game screenshot"), ADD_CONTEXT_GAME)
	if not EditorInterface.is_playing_scene():
		_add_context_menu.set_item_disabled(-1, true)
		_add_context_menu.set_item_tooltip(-1, I18n.t("No game is running."))
	_add_context_menu.reset_size()
	_add_context_menu.popup(Rect2i(Vector2i(get_screen_position() + get_local_mouse_position()), Vector2i.ZERO))


func _on_add_context_selected(id: int) -> void:
	match id:
		ADD_CONTEXT_SCRIPT:
			var script := EditorInterface.get_script_editor().get_current_script()
			if script:
				add_context_files([script.resource_path])
		ADD_CONTEXT_FILE:
			if _file_dialog == null:
				_file_dialog = EditorFileDialog.new()
				_file_dialog.file_mode = EditorFileDialog.FILE_MODE_OPEN_FILES
				_file_dialog.access = EditorFileDialog.ACCESS_RESOURCES
				_file_dialog.title = I18n.t("Add to the context")
				_file_dialog.files_selected.connect(add_context_files)
				add_child(_file_dialog)
			_file_dialog.popup_centered_ratio(0.6)
		ADD_CONTEXT_SCREENSHOT:
			_on_screenshot_requested()
		ADD_CONTEXT_GAME:
			_capture_game()


## Agrega archivos para el próximo prompt: las imágenes como imagen (de donde sean) y el resto, si
## es del proyecto, como resource_link.
func add_context_files(paths: PackedStringArray) -> void:
	var outside: PackedStringArray = []
	for path: String in paths:
		if path.get_extension().to_lower() in IMAGE_EXTENSIONS:
			var image := Image.load_from_file(path)
			if image == null or image.is_empty():
				_model.add_notice(I18n.t("Could not read the image %s.") % path.get_file(), ChatEntry.NoticeLevel.WARNING)
			else:
				attach_image(image, path.get_file(), path)
			continue
		var res_path := path if path.begins_with("res://") else EditorContext.to_res_path(path)
		if res_path.is_empty():
			outside.append(path.get_file())
		elif not res_path in _extra_files:
			_extra_files.append(res_path)
	if not outside.is_empty():
		_model.add_notice(I18n.t("Only images and project files can be attached: %s.") % ", ".join(outside), ChatEntry.NoticeLevel.WARNING)
	_refresh_chips()


## Adjunta `image` al próximo prompt (achicada a EditorContext.MAX_IMAGE_SIDE).
func attach_image(image: Image, label: String, tooltip: String = "") -> void:
	if not (_model.session_id.is_empty() or _model.supports_image()):
		_model.add_notice(I18n.t("The agent does not accept images"), ChatEntry.NoticeLevel.WARNING)
		return
	if _images.size() >= MAX_IMAGES:
		_model.add_notice(I18n.t("At most %d images per message.") % MAX_IMAGES, ChatEntry.NoticeLevel.WARNING)
		return
	var fitted := EditorContext.fit_image(image.duplicate() as Image, EditorContext.MAX_IMAGE_SIDE)
	_image_serial += 1
	_images[CHIP_IMAGE_PREFIX + str(_image_serial)] = {
		"label": "▣ " + label,
		"tooltip": I18n.t("%s (click to remove it)") % (tooltip if not tooltip.is_empty() else "%s, %dx%d" % [label, fitted.get_width(), fitted.get_height()]),
		"block": {"type": "image", "mimeType": "image/png", "data": Marshalls.raw_to_base64(fitted.save_png_to_buffer())},
	}
	_refresh_chips()


func _capture_game() -> void:
	if not game_capture.is_valid():
		return
	var frame: Variant = await game_capture.call()
	if not is_inside_tree():  # se cerró la pestaña o el plugin mientras esperaba
		return
	if frame is Image:
		attach_image(frame, I18n.t("game"))
	else:
		_model.add_notice(str(frame), ChatEntry.NoticeLevel.WARNING)


func _context_blocks() -> Array:
	var blocks: Array = []
	for id: String in _chips:
		blocks.append(_chips[id].block)
	return blocks


func _on_screenshot_requested() -> void:
	var image := EditorContext.capture_scene_viewport()
	if image == null:
		_model.add_notice(I18n.t("Could not capture the viewport."), ChatEntry.NoticeLevel.WARNING)
		return
	attach_image(image, I18n.t("viewport"))


# --- comentarios de un PR de GitHub como hallazgos (m11-10) -----------------------------------------

func _on_github_import_requested() -> void:
	var dialog := ConfirmationDialog.new()
	dialog.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	dialog.title = I18n.t("Review comments from GitHub")
	var column := VBoxContainer.new()
	var hint := Label.new()
	hint.text = I18n.t("Pull request number (empty: the one of the current branch). It needs the gh CLI signed in.")
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.custom_minimum_size.x = AgentTheme.px(320)
	column.add_child(hint)
	var number := LineEdit.new()
	number.placeholder_text = "123"
	column.add_child(number)
	dialog.add_child(column)
	dialog.ok_button_text = I18n.t("Import")
	dialog.cancel_button_text = I18n.t("Cancel")
	dialog.register_text_enter(number)
	dialog.confirmed.connect(func() -> void: _import_github_review(number.text))
	dialog.visibility_changed.connect(func() -> void:
		if not dialog.visible:
			dialog.queue_free.call_deferred())
	add_child(dialog)
	dialog.popup_centered()
	number.grab_focus()


func _import_github_review(pr: String) -> void:
	_model.add_notice(I18n.t("Reading the pull request's review comments…"))
	var result: Dictionary = await GithubReviews.new(EditorContext.project_path()).fetch_review(pr)
	if not is_inside_tree():  # se cerró la pestaña o el plugin mientras esperaba
		return
	if not str(result.error).is_empty():
		_model.add_notice(str(result.error), ChatEntry.NoticeLevel.WARNING)
	elif result.findings.is_empty():
		_model.add_notice(I18n.t("%s has no review comments on lines of this project's files.") % result.url)
	else:
		var findings: Array[Dictionary] = []
		findings.assign(result.findings)
		_controller.review.set_findings(findings)
		_model.add_notice(I18n.t("%d review comments from %s are in the findings and the Script Editor.") % [findings.size(), result.url])


# --- presets de export (M0) ----------------------------------------------------------------------

## Un aviso del plugin (por ejemplo el de versión nueva) debajo del de export.
func add_banner(banner: Control) -> void:
	add_child(banner)
	move_child(banner, _export_banner.get_index() + 1)


func refresh_export_banner() -> void:
	if not is_node_ready():
		return
	var missing := ExportPresetsPatcher.presets_missing_filter()
	_export_banner.visible = not missing.is_empty()
	if _export_banner.visible:
		_export_banner_label.text = (
			I18n.t("The export presets %s do not exclude '%s'. If you export with the plugin disabled, the addon ends up in the game.")
			% [", ".join(missing), ExportPresetsPatcher.FILTER]
		)


func _on_presets_poll() -> void:
	if not is_visible_in_tree():
		return
	var mtime: int = 0
	if ExportPresetsPatcher.presets_file_exists():
		mtime = FileAccess.get_modified_time(ExportPresetsPatcher.PRESETS_PATH)
	if mtime != _presets_mtime:
		_presets_mtime = mtime
		refresh_export_banner()


func _on_add_filter_pressed() -> void:
	var missing := ExportPresetsPatcher.presets_missing_filter()
	_confirm_dialog.dialog_text = (
		I18n.t("'%s' will be added to the exclude filter of these presets:\n\n• %s\n\nThis modifies %s.")
		% [ExportPresetsPatcher.FILTER, "\n• ".join(missing), ExportPresetsPatcher.PRESETS_PATH]
	)
	_confirm_dialog.popup_centered()


func _on_patch_confirmed() -> void:
	var patched := ExportPresetsPatcher.patch_presets()
	refresh_export_banner()
	if patched.is_empty():
		_result_dialog.dialog_text = I18n.t("No preset was modified. Check the Output panel.")
	else:
		_result_dialog.dialog_text = (
			I18n.t("Filter added to: %s.\n\nRestart the editor before opening the Export dialog: otherwise it may overwrite the change when it saves the presets.")
			% ", ".join(patched)
		)
	_result_dialog.popup_centered()
