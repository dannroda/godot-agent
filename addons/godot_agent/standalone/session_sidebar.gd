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

var _tabs: SessionTabs
var _list: VBoxContainer
var _refresh_queued := false


func setup(tabs: SessionTabs) -> void:
	_tabs = tabs
	_tabs.sessions_changed.connect(refresh)
	custom_minimum_size.x = AgentTheme.px(WIDTH)
	add_theme_stylebox_override(&"panel", AgentTheme.panel(AgentTheme.dark_color(), Color.TRANSPARENT, 0.0, 8.0))
	var column := VBoxContainer.new()
	column.add_theme_constant_override(&"separation", AgentTheme.px(6))
	add_child(column)
	var title := Label.new()
	title.text = I18n.t("Sessions")
	title.modulate = Color(1, 1, 1, 0.6)
	column.add_child(title)
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
	if state.closable:
		var close := Button.new()
		close.flat = true
		close.text = "×"
		close.tooltip_text = I18n.t("Close session")
		close.focus_mode = Control.FOCUS_NONE
		close.pressed.connect(func() -> void: close_requested.emit(id))
		top.add_child(close)
	lines.add_child(_label(str(info.get("agent", "")), 0.65))
	var status_label := _label(status.text + (" · " + str(info.mode) if not str(info.get("mode", "")).is_empty() else ""), 1.0)
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
