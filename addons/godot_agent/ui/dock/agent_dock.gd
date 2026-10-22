@tool
extends VBoxContainer
## Dock "Agent" (spec §9.1, mockup pantalla 1): header con perfil, título y acciones; selector de
## modo; conversación; composer. Solo habla con SessionModel (estado) y SessionController (comandos).

signal show_log_requested
## Abrir el diálogo de Settings (lo maneja el plugin: necesita la config del proyecto y el server MCP).
signal settings_requested
## Acciones de avisos que resuelve otro módulo (conflictos de sync, recargar escena…).
signal action_forwarded(action: String, payload: Variant)

const SessionModel := preload("../../session/session_model.gd")
const SessionController := preload("../../session/session_controller.gd")
const ChatEntry := preload("../../session/chat_entry.gd")
const HarnessSettings := preload("../../core/harness_settings.gd")
const HISTORY_MENU_SIZE := 30
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
const QuotaMeter := preload("quota_meter.gd")
const QuotaMonitor := preload("../../core/quota_monitor.gd")
const ReviewStore := preload("../../review/review_store.gd")
const I18n := preload("../../core/i18n.gd")

## export_presets.cfg no pasa por EditorFileSystem: se mira su fecha de modificación cada tanto.
const PRESETS_POLL_INTERVAL_S := 2.0
const CHIP_SCENE := "scene"
const CHIP_SELECTION := "selection"
const CHIP_SCREENSHOT := "screenshot"
const CHIP_FILE_PREFIX := "file:"
const ADD_CONTEXT_SCRIPT := 0
const ADD_CONTEXT_FILE := 1
const ADD_CONTEXT_SCREENSHOT := 2
## Acciones de la revisión que resuelve el plugin (junto con las de las tarjetas del Script Editor).
const ACTION_REVIEW_FOCUS := "review_focus"
const ACTION_REVIEW_FIX_ALL := "review_fix_all"
## Un link a .godot_agent/oneshot/… (spec, progreso, QA): lo muestra la pantalla Agent.
const ACTION_OPEN_RUN_FILE := "open_run_file"
## Tooltips de los botones de modo (las reglas que lee el agente están en SessionController.MODE_RULES).
const MODE_TOOLTIPS: Dictionary = {
	SessionModel.HarnessMode.ASK: "Only answers questions: does not modify files, scenes or settings, and does not run commands.",  # i18n
	SessionModel.HarnessMode.REVIEW: "Read-only review: the agent reports findings without modifying anything.",  # i18n
	SessionModel.HarnessMode.BUILD: "The agent can edit scenes and scripts; you approve the changes.",  # i18n
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

var _model: SessionModel
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
var _mode_buttons: Dictionary = {}  # HarnessMode -> Button
## Chips de contexto actuales: id -> {label, tooltip, block}
var _chips: Dictionary = {}
var _dismissed_chips: Dictionary = {}  # "id|valor" -> true
var _screenshot_block: Dictionary = {}
## Archivos agregados con "+ contexto" para el próximo prompt (res_path, en orden).
var _extra_files: PackedStringArray = []
var _add_context_menu: PopupMenu
var _file_dialog: EditorFileDialog
var _review_panel: ReviewPanel
var _quota_meter: QuotaMeter
var _quota_timer: Timer
var _quota_state: int = QuotaMonitor.QuotaState.UNKNOWN
var _export_dialog: ConfirmationDialog
var _export_preview: TextEdit
## Para pegar el código de la página de login (se arma la primera vez).
var _login_code_dialog: ConfirmationDialog
var _login_code_input: LineEdit
var _history_menu: PopupMenu
var _history_items: Array[Dictionary] = []

@onready var _profile_button: OptionButton = %ProfileButton
@onready var _title_label: Label = %TitleLabel
@onready var _history_button: Button = %HistoryButton
@onready var _new_session_button: Button = %NewSessionButton
@onready var _settings_button: Button = %SettingsButton
@onready var _mode_bar: HBoxContainer = %ModeBar
@onready var _status_label: Label = %StatusLabel
@onready var _body: VBoxContainer = %Body
@onready var _empty_state: VBoxContainer = %EmptyState
@onready var _empty_command: Label = %EmptyCommand
@onready var _start_button: Button = %StartButton
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
	_build_mode_bar()
	_conversation = ConversationView.new()
	_conversation.setup(_model, _accent)
	_conversation.action_requested.connect(_on_action_requested)
	_body.add_child(_conversation)
	_composer = Composer.new()
	_composer.setup(_accent)
	_composer.history_path = PROMPT_HISTORY_PATH
	_composer.mention_provider = EditorContext.mention_options
	_composer.submitted.connect(_on_submitted)
	_composer.cancel_requested.connect(_on_cancel_requested)
	_composer.model_selected.connect(func(value: String) -> void: _controller.set_config_option("model", value))
	_composer.screenshot_requested.connect(_on_screenshot_requested)
	_composer.context_chip_removed.connect(_on_chip_removed)
	var composer_column := VBoxContainer.new()
	composer_column.add_theme_constant_override(&"separation", AgentTheme.px(4))
	_composer_slot.add_child(composer_column)
	_queue_view = PromptQueueView.new()
	_queue_view.setup(_queue)
	_queue_view.edit_requested.connect(_composer.insert_text)
	_queue_view.send_now_requested.connect(_send_next_queued.bind(true))
	composer_column.add_child(_queue_view)
	composer_column.add_child(_composer)
	_build_review_panel()
	_build_quota_meter()
	_settings.changed.connect(func(key: String) -> void:
		if key == HarnessSettings.KEY_PROFILES:
			_reload_profiles())

	_translate_scene_texts()
	_start_button.pressed.connect(_start_session)
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
	_model.title_changed.connect(func(_title: String) -> void: _refresh_title())
	_model.usage_changed.connect(_composer.set_usage)
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
	_history_button.pressed.connect(_show_history_menu)
	_new_session_button.icon = AgentTheme.icon(&"Add")
	_new_session_button.pressed.connect(_on_new_session_pressed)
	_settings_button.icon = AgentTheme.icon(&"Tools")
	_settings_button.pressed.connect(func() -> void: settings_requested.emit())
	_profile_button.item_selected.connect(_on_profile_selected)
	_title_label.add_theme_color_override(&"font_color", AgentTheme.MUTED)


func _build_mode_bar() -> void:
	var group := ButtonGroup.new()
	_mode_bar.add_theme_constant_override(&"separation", 0)
	for mode: SessionModel.HarnessMode in SessionModel.HARNESS_MODE_LABELS:
		var button := Button.new()
		button.text = I18n.t(SessionModel.HARNESS_MODE_LABELS[mode])
		button.toggle_mode = true
		button.button_group = group
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.clip_text = true
		button.add_theme_font_size_override(&"font_size", AgentTheme.px(12))
		button.add_theme_stylebox_override(&"pressed", AgentTheme.panel(Color(_accent, 0.2), _accent, 3, 3))
		button.add_theme_stylebox_override(&"normal", AgentTheme.panel(Color(1, 1, 1, 0.04), Color(1, 1, 1, 0.08), 3, 3))
		button.add_theme_stylebox_override(&"hover", AgentTheme.panel(Color(1, 1, 1, 0.08), Color(1, 1, 1, 0.12), 3, 3))
		button.add_theme_color_override(&"font_pressed_color", _accent)
		button.tooltip_text = I18n.t(MODE_TOOLTIPS[mode])
		button.pressed.connect(func() -> void: _model.set_harness_mode(mode))
		_mode_bar.add_child(button)
		_mode_buttons[mode] = button


func _refresh_modes() -> void:
	for mode: SessionModel.HarnessMode in _mode_buttons:
		(_mode_buttons[mode] as Button).set_pressed_no_signal(mode == _model.harness_mode)
	if _review_panel:
		_review_panel.visible = _model.harness_mode == SessionModel.HarnessMode.REVIEW


# --- cuota del plan -------------------------------------------------------------------------------

func _build_quota_meter() -> void:
	_quota_meter = QuotaMeter.new()
	_quota_meter.setup(_controller.quota, _accent)
	add_child(_quota_meter)
	move_child(_quota_meter, _status_label.get_index() + 1)
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
	_composer.set_usage_hint("" if quota.has_data() else I18n.t("The agent does not report the plan quota."))
	_on_quota_tick()
	if quota.is_limited() or quota.has_data():
		_quota_timer.start()
	else:
		_quota_timer.stop()


func _on_quota_tick() -> void:
	var quota := _controller.quota
	_quota_meter.refresh()
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
		SessionModel.SessionState.CANCELLING:
			text = I18n.t("● %s · cancelling…") % name
			color = AgentTheme.WARNING
		SessionModel.SessionState.FAILED:
			text = I18n.t("✗ %s · error") % name
			color = AgentTheme.ERROR
	_status_label.text = text
	_status_label.tooltip_text = _model.failure_message
	_status_label.add_theme_color_override(&"font_color", color)
	_composer.set_busy(_model.is_busy())
	_composer.set_enabled(_model.state != SessionModel.SessionState.STARTING)
	_composer.set_screenshot_available(_model.session_id.is_empty() or _model.supports_image())
	_new_session_button.disabled = _model.state == SessionModel.SessionState.STARTING or _model.is_busy()
	_refresh_title()
	_refresh_empty_state()


func _refresh_empty_state() -> void:
	if _empty_state == null or _conversation == null:
		return
	var empty := _model.entries().is_empty() and _model.state in [SessionModel.SessionState.DISCONNECTED, SessionModel.SessionState.FAILED]
	_empty_state.visible = empty
	_conversation.visible = not empty
	var profile := _settings.active_profile()
	_empty_command.text = profile.command_line() if profile else I18n.t("No profiles: set them up in the settings.")
	_empty_command.add_theme_color_override(&"font_color", AgentTheme.MUTED)
	_start_button.disabled = profile == null or _model.state == SessionModel.SessionState.STARTING


# --- sesión --------------------------------------------------------------------------------------

func _start_session() -> void:
	var profile := _settings.active_profile()
	if profile == null:
		settings_requested.emit()
		return
	var started: bool = await _controller.start(profile)
	if started:
		_warn_api_key(profile)
		_composer.focus()
		if not _pending_prompt.is_empty():
			var text := _pending_prompt
			_pending_prompt = ""
			_send(text)


func _warn_api_key(profile: AgentProfile) -> void:
	if profile.command_line().contains("claude") and (OS.has_environment("ANTHROPIC_API_KEY") or profile.env.has("ANTHROPIC_API_KEY")):
		_model.add_notice(
			I18n.t("There is an ANTHROPIC_API_KEY in the environment: Claude Code may bill through the API instead of using your subscription."),
			ChatEntry.NoticeLevel.WARNING
		)


## Sesiones de este proyecto, la más reciente primero (spec §11).
func _show_history_menu() -> void:
	_history_menu.clear()
	_history_items = []
	if _controller.history:
		_history_items = _controller.history.list(_controller.cwd).slice(0, HISTORY_MENU_SIZE)
	if _history_items.is_empty():
		_history_menu.add_item(I18n.t("No saved sessions for this project"))
		_history_menu.set_item_disabled(0, true)
	for i in _history_items.size():
		var item := _history_items[i]
		var title := str(item.get("title", "")) if not str(item.get("title", "")).is_empty() else I18n.t("(untitled)")
		var when := Time.get_datetime_string_from_unix_time(int(item.get("updated", 0)) + _timezone_bias_s(), true).substr(5, 11).replace("-", "/")
		_history_menu.add_item("%s · %s · %s" % [when, title, item.get("agent", "")], i)
		_history_menu.set_item_tooltip(_history_menu.item_count - 1, I18n.t("%d turns · %s") % [int(item.get("turns", 0)), item.get("id", "")])
		if item.get("id") == _model.session_id:
			_history_menu.set_item_disabled(_history_menu.item_count - 1, true)
	var busy := _model.state in [SessionModel.SessionState.STARTING, SessionModel.SessionState.PROMPTING, SessionModel.SessionState.CANCELLING]
	for i in _history_menu.item_count:
		_history_menu.set_item_disabled(i, _history_menu.is_item_disabled(i) or busy)
	var below: Vector2 = _history_button.get_screen_position() + Vector2(0, _history_button.size.y)
	_history_menu.popup(Rect2i(Vector2i(below), Vector2i.ZERO))


## Muestra la sesión y la reanuda con session/load si el agente lo soporta (si no, solo lectura).
func open_history_session(id: String) -> bool:
	var record: Dictionary = _controller.history.load_record(id) if _controller.history else {}
	if record.is_empty():
		_model.add_notice(I18n.t("Could not read session %s from the history.") % id, ChatEntry.NoticeLevel.WARNING)
		return false
	var profile := _settings.profile(str(record.get("profile_id", "")))
	if profile == null:
		profile = _settings.active_profile()
	if profile == null:
		return false
	return await _controller.start(profile, record)


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
	_controller.send_prompt(text, _take_context_blocks())


## El contexto adjunto para un prompt; la captura y los archivos agregados se usan una sola vez.
func _take_context_blocks() -> Array:
	var blocks := _context_blocks()
	_screenshot_block = {}
	_extra_files.clear()
	_refresh_chips()
	return blocks


# --- cola de prompts -----------------------------------------------------------------------------

## Con end_turn sale el próximo de la cola; si el turno terminó de otra forma, la cola espera al
## usuario (lo que había pedido puede ya no tener sentido).
func _on_turn_finished(stop_reason: String) -> void:
	if _queue.is_empty():
		return
	if stop_reason == "end_turn":
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
		_controller.send_prompt(str(item.text), item.blocks)


func _on_cancel_requested() -> void:
	_controller.cancel()


func _on_action_requested(action: String, payload: Variant) -> void:
	match action:
		SessionController.ACTION_RETRY:
			if retry_interceptor.is_valid() and retry_interceptor.call():
				return
			_start_session()
		SessionController.ACTION_SHOW_LOG:
			show_log_requested.emit()
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
			else:
				_open_path(url.trim_prefix("file://"), 0)
		"open_location":
			var location: Dictionary = payload
			_open_path(str(location.path), int(location.get("line", 0)))
		_:
			action_forwarded.emit(action, payload)


## Un archivo del chat: escenas y scripts en el editor; spec y progreso del One-shot en la pantalla
## Agent; el resto de los archivos de texto (.md, .txt…), que Godot no carga, con el programa del
## sistema.
func set_oneshot_active(active: bool) -> void:
	_composer.set_oneshot_active(active)


func _open_path(path: String, line: int) -> void:
	var absolute := path
	if path.begins_with("res://"):
		absolute = ProjectSettings.globalize_path(path)
	elif not path.is_absolute_path():
		absolute = ProjectSettings.globalize_path("res://").path_join(path.trim_prefix("./"))
	absolute = absolute.simplify_path()
	if absolute.contains("/.godot_agent/oneshot/"):
		action_forwarded.emit(ACTION_OPEN_RUN_FILE, {"path": absolute})
		return
	if EditorContext.open_location(absolute, line):
		return
	if FileAccess.file_exists(absolute):
		OS.shell_open(absolute)
		return
	_model.add_notice(I18n.t("Could not open %s.") % path, ChatEntry.NoticeLevel.WARNING)


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
	if not _screenshot_block.is_empty():
		chips[CHIP_SCREENSHOT] = {"label": "▣ " + I18n.t("screenshot"), "tooltip": I18n.t("Viewport screenshot (click to remove it)"), "block": _screenshot_block}
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
		CHIP_SCREENSHOT:
			_screenshot_block = {}
		_:
			var index := _extra_files.find(chip_id.trim_prefix(CHIP_FILE_PREFIX))
			if index >= 0:
				_extra_files.remove_at(index)
	_refresh_chips()


## "+ contexto": script actual, un archivo del proyecto o una captura del viewport.
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


## Agrega archivos del proyecto (res://) como resource_link para el próximo prompt.
func add_context_files(paths: PackedStringArray) -> void:
	for path: String in paths:
		var res_path := path if path.begins_with("res://") else EditorContext.to_res_path(path)
		if not res_path.is_empty() and not res_path in _extra_files:
			_extra_files.append(res_path)
	_refresh_chips()


func _context_blocks() -> Array:
	var blocks: Array = []
	for id: String in _chips:
		blocks.append(_chips[id].block)
	return blocks


func _on_screenshot_requested() -> void:
	var block := EditorContext.capture_viewport_block()
	if block.is_empty():
		_model.add_notice(I18n.t("Could not capture the viewport."), ChatEntry.NoticeLevel.WARNING)
		return
	_screenshot_block = block
	_refresh_chips()


# --- presets de export (M0) ----------------------------------------------------------------------

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
