@tool
extends FoldableContainer
## Remote Control (m7-21, m7-25, m7-26): la franja plegable con el link, el QR y «Apagar» mientras
## está prendido. El dock la ofrece en «⋯» (`can_turn_on`) y manda el comando que pide
## (`command_requested`) como un prompt.

signal command_requested(text: String)

const SessionModel := preload("../../session/session_model.gd")
const SessionController := preload("../../session/session_controller.gd")
const AgentTheme := preload("../agent_theme.gd")
const I18n := preload("../../core/i18n.gd")
const QrView := preload("qr_view.gd")

const TOOLTIP := "Remote Control: continue this session from claude.ai/code or the Claude app on your phone."  # i18n

## Button y no LinkButton: LinkButton pide el ancho del link entero y ensancha el dock.
var link: Button
var qr_button: Button
var qr: QrView
var _model: SessionModel
var _controller: SessionController


func setup(model: SessionModel, controller: SessionController, accent: Color) -> void:
	_model = model
	_controller = controller
	title = "● " + I18n.t("Remote Control on")
	title_text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	tooltip_text = I18n.t("Click the title to fold or unfold.")
	var title_panel := AgentTheme.panel(Color(accent, 0.08), Color(accent, 0.5), 4, 6)
	for item: StringName in [&"title_panel", &"title_hover_panel", &"title_collapsed_panel", &"title_collapsed_hover_panel"]:
		add_theme_stylebox_override(item, title_panel)
	add_theme_stylebox_override(&"panel", AgentTheme.panel(Color(accent, 0.05), Color(accent, 0.5), 4, 6))
	for item: StringName in [&"font_color", &"hover_font_color", &"collapsed_font_color"]:
		add_theme_color_override(item, accent)
	var column := VBoxContainer.new()
	add_child(column)
	qr_button = Button.new()
	qr_button.text = I18n.t("QR")
	qr_button.flat = true
	qr_button.toggle_mode = true
	qr_button.tooltip_text = I18n.t("Show a QR code of the link, to open the session on your phone.")
	qr_button.toggled.connect(func(on: bool) -> void:
		qr.visible = on
		if on:
			expand())
	add_title_bar_control(qr_button)
	var copy := Button.new()
	copy.text = I18n.t("Copy link")
	copy.flat = true
	copy.pressed.connect(func() -> void: DisplayServer.clipboard_set(_model.remote_control_url))
	add_title_bar_control(copy)
	var off := Button.new()
	off.text = I18n.t("Turn off")
	off.flat = true
	off.add_theme_color_override(&"font_color", AgentTheme.ERROR)
	off.pressed.connect(func() -> void: command_requested.emit(_controller.remote_control_command(false)))
	add_title_bar_control(off)
	link = Button.new()
	link.flat = true
	link.clip_text = true
	link.alignment = HORIZONTAL_ALIGNMENT_LEFT
	link.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	link.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	link.add_theme_color_override(&"font_color", accent)
	link.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	link.pressed.connect(func() -> void: OS.shell_open(_model.remote_control_url))
	column.add_child(link)
	qr = QrView.new()
	qr.visible = false
	column.add_child(qr)
	var hint := Label.new()
	hint.text = I18n.t("What you write from the phone and its answers only show there. Here you see the tool calls that ask for permission, and you can answer them from either side.")
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_color_override(&"font_color", AgentTheme.MUTED)
	hint.add_theme_font_size_override(&"font_size", AgentTheme.px(11))
	column.add_child(hint)
	_model.remote_control_changed.connect(func(_url: String) -> void: refresh())
	_model.commands_changed.connect(func(_commands: Array) -> void: refresh())
	_model.harness_mode_changed.connect(func(_mode: SessionModel.HarnessMode) -> void: refresh())
	refresh()


## Se ofrece si el agente publica `/remote-control` y está apagado, fuera de One-shot (sus turnos no
## pasarían por el run).
func can_turn_on() -> bool:
	return _model.supports_remote_control() and _model.harness_mode != SessionModel.HarnessMode.ONESHOT and _model.remote_control_url.is_empty()


func turn_on() -> void:
	command_requested.emit(_controller.remote_control_command(true))


## La franja, mientras está prendido.
func refresh() -> void:
	visible = not _model.remote_control_url.is_empty()
	link.text = _model.remote_control_url
	link.tooltip_text = _model.remote_control_url
	qr.set_text(_model.remote_control_url)
