extends PanelContainer
## Las sesiones de la app aparte en una lista a la izquierda (m21-04), en vez de la fila de pestañas:
## cada una con su nombre, su agente y cuenta, su modo y su estado. Es otra vista de SessionTabs, que
## sigue mandando (cuál está activa, nombres, cerrar); el dock del editor sigue con pestañas.

signal new_requested
signal close_requested(id: String)

const AgentTheme := preload("../ui/agent_theme.gd")
const I18n := preload("../core/i18n.gd")
const SessionTabs := preload("../ui/dock/session_tabs.gd")

const WIDTH := 250
const IDLE_COLOR := Color("#8a93a0")

## `(id) -> {agent, mode}`: lo que la barra no sabe de la sesión (perfil del agente y nombre del modo).
var describe: Callable
## `() -> Array`: las cuentas con cuota anotada, `{label, used (0..1, -1 sin dato), limited, text}`.
var accounts: Callable

var _tabs: SessionTabs
var _list: VBoxContainer
var _accounts_box: VBoxContainer
var _count: Label
var _refresh_queued := false


func setup(tabs: SessionTabs) -> void:
	_tabs = tabs
	_tabs.sessions_changed.connect(refresh)
	custom_minimum_size.x = AgentTheme.px(WIDTH)
	add_theme_stylebox_override(&"panel", AgentTheme.panel(AgentTheme.dark_color(), Color.TRANSPARENT, 0.0, 8.0))
	var column := VBoxContainer.new()
	column.add_theme_constant_override(&"separation", AgentTheme.px(6))
	add_child(column)
	var title_row := HBoxContainer.new()
	var title := Label.new()
	title.text = I18n.t("Sessions")
	title.modulate = Color(1, 1, 1, 0.6)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(title)
	_count = Label.new()
	_count.name = "OpenCount"
	_count.modulate = Color(1, 1, 1, 0.45)
	title_row.add_child(_count)
	column.add_child(title_row)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override(&"separation", AgentTheme.px(4))
	scroll.add_child(_list)
	var add := Button.new()
	add.name = "NewSessionButton"
	add.text = "+ " + I18n.t("New session")
	add.custom_minimum_size.y = AgentTheme.px(36)
	add.pressed.connect(func() -> void: new_requested.emit())
	column.add_child(add)
	_accounts_box = VBoxContainer.new()
	_accounts_box.name = "Accounts"
	_accounts_box.add_theme_constant_override(&"separation", AgentTheme.px(4))
	column.add_child(_accounts_box)
	refresh()


## Se arma de nuevo en el próximo frame: un turno cambia el estado varias veces seguidas.
func refresh() -> void:
	if _refresh_queued or _list == null:
		return
	_refresh_queued = true
	_rebuild.call_deferred()


func _rebuild() -> void:
	_refresh_queued = false
	for child: Node in _list.get_children():
		_list.remove_child(child)
		child.queue_free()
	for id: String in _tabs.ids():
		_list.add_child(_row(id))
	_count.text = I18n.t("%d open") % _tabs.ids().size()
	_fill_accounts()


## La cuota de cada cuenta que se usó (m21-04): la última anotada, compartida por todas las sesiones.
func _fill_accounts() -> void:
	for child: Node in _accounts_box.get_children():
		_accounts_box.remove_child(child)
		child.queue_free()
	var known: Array = accounts.call() if accounts.is_valid() else []
	_accounts_box.visible = not known.is_empty()
	if known.is_empty():
		return
	_accounts_box.add_child(HSeparator.new())
	var title := _label(I18n.t("Accounts"), 0.6)
	_accounts_box.add_child(title)
	for account: Dictionary in known:
		var line := HBoxContainer.new()
		line.add_child(_label(str(account.label), 1.0, true))
		var amount := _label(str(account.text), 0.65)
		amount.clip_text = false
		amount.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING  # cortando, no pide ancho y no se ve
		line.add_child(amount)
		_accounts_box.add_child(line)
		var bar := ProgressBar.new()
		bar.show_percentage = false
		bar.custom_minimum_size.y = AgentTheme.px(4)
		bar.max_value = 1.0
		bar.value = 1.0 if account.limited else maxf(0.0, float(account.used))
		var fill := _tabs.accent if account.limited or float(account.used) >= 0.8 else SessionTabs.BUSY_COLOR
		bar.add_theme_stylebox_override(&"background", AgentTheme.panel(Color(1, 1, 1, 0.1), Color.TRANSPARENT, 2.0, 0.0))
		bar.add_theme_stylebox_override(&"fill", AgentTheme.panel(fill, Color.TRANSPARENT, 2.0, 0.0))
		bar.tooltip_text = "%s: %s" % [account.label, account.text]
		_accounts_box.add_child(bar)


func _row(id: String) -> Control:
	var state := _tabs.state_of(id)
	var info: Dictionary = describe.call(id) if describe.is_valid() else {}
	var active := id == _tabs.active_id()
	var row := Button.new()
	row.name = "Session_" + id
	row.toggle_mode = true
	row.button_pressed = active
	row.tooltip_text = I18n.t("Double-click to rename")
	var bg := Color(1, 1, 1, 0.08) if active else Color.TRANSPARENT
	var border := Color(1, 1, 1, 0.18) if active else Color.TRANSPARENT
	for style: StringName in [&"normal", &"pressed", &"focus"]:
		row.add_theme_stylebox_override(style, AgentTheme.panel(bg, border, 8.0, 8.0))
	row.add_theme_stylebox_override(&"hover", AgentTheme.panel(Color(1, 1, 1, 0.12), border, 8.0, 8.0))
	row.add_theme_stylebox_override(&"hover_pressed", AgentTheme.panel(Color(1, 1, 1, 0.12), border, 8.0, 8.0))
	row.pressed.connect(func() -> void: _tabs.select(id))
	row.gui_input.connect(func(event: InputEvent) -> void:
		var click := event as InputEventMouseButton
		if click and click.double_click and click.button_index == MOUSE_BUTTON_LEFT:
			_tabs.start_rename(id, row))
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side: String in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, AgentTheme.px(10))
	for side: String in ["top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, AgentTheme.px(6))
	row.add_child(margin)
	# Un botón no cuenta el alto de sus hijos: toma el de su contenido.
	margin.minimum_size_changed.connect(func() -> void: row.custom_minimum_size.y = margin.get_combined_minimum_size().y)
	var lines := VBoxContainer.new()
	lines.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lines.add_theme_constant_override(&"separation", 0)
	margin.add_child(lines)
	var top := HBoxContainer.new()
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lines.add_child(top)
	var status := _status(state)
	var dot := TextureRect.new()
	dot.texture = AgentTheme.dot(status.color)
	dot.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(dot)
	top.add_child(_label(("⚠ " if state.waiting else "") + str(state.label), 1.0, true))
	var mode := _label(str(info.get("mode", "")), 0.55)
	mode.clip_text = false
	mode.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
	top.add_child(mode)
	if state.closable:
		var close := Button.new()
		close.flat = true
		close.text = "×"
		close.tooltip_text = I18n.t("Close session")
		close.focus_mode = Control.FOCUS_NONE
		close.pressed.connect(func() -> void: close_requested.emit(id))
		top.add_child(close)
	lines.add_child(_label(str(info.get("agent", "")), 0.65))
	var status_label := _label(status.text, 1.0)
	status_label.add_theme_color_override(&"font_color", status.color if status.color != IDLE_COLOR else Color(AgentTheme.font_color(), 0.65))
	lines.add_child(status_label)
	return row


## El texto y el color del estado: te espera, trabajando, turno sin mirar, lista o sin empezar.
func _status(state: Dictionary) -> Dictionary:
	if state.waiting:
		return {"text": I18n.t("Waiting for you"), "color": _tabs.accent}
	if state.busy:
		return {"text": I18n.t("Working…"), "color": SessionTabs.BUSY_COLOR}
	if state.unread:
		return {"text": I18n.t("Finished a turn"), "color": SessionTabs.UNREAD_COLOR}
	var model: Object = state.model
	var started := model != null and int(model.get(&"state")) != 0  # SessionState.DISCONNECTED
	return {"text": I18n.t("Ready") if started else I18n.t("Not started"), "color": IDLE_COLOR}


func _label(text: String, alpha: float, expand := false) -> Label:
	var label := Label.new()
	label.text = text
	label.modulate = Color(1, 1, 1, alpha)
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.clip_text = true
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if expand:
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return label
