@tool
extends VBoxContainer
## Varias sesiones del agente abiertas a la vez (m7-44): una pestaña por sesión, cada una con su
## dock completo, y «+» para abrir otra, como las pestañas de un navegador. La primera no se cierra:
## solo las demás llevan el botón de cerrar.

signal new_session_requested
signal close_requested(id: String)
signal active_changed(id: String)

const AgentTheme := preload("../agent_theme.gd")
const I18n := preload("../../core/i18n.gd")
const SessionModel := preload("../../session/session_model.gd")

var _bar: TabBar
var _add_button: Button
## Los docks, uno encima del otro (se ve el de la pestaña activa); como contenedor, pide el mínimo
## del dock visible, igual que cuando el dock iba solo.
var _stack: MarginContainer
## Ids en el orden de las pestañas.
var _ids: PackedStringArray = []
var _docks: Dictionary = {}  # id -> dock
var _models: Dictionary = {}  # id -> SessionModel
var _labels: Dictionary = {}  # id -> nombre por defecto («Session 2»)


func _init() -> void:
	add_theme_constant_override(&"separation", 0)
	var row := HBoxContainer.new()
	row.name = "SessionTabsRow"
	add_child(row)
	_bar = TabBar.new()
	_bar.name = "SessionTabBar"
	_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_bar.clip_tabs = true
	_bar.max_tab_width = AgentTheme.px(160)
	_bar.tab_close_display_policy = TabBar.CLOSE_BUTTON_SHOW_NEVER
	_bar.tab_changed.connect(_on_tab_changed)
	_bar.tab_button_pressed.connect(func(index: int) -> void:
		if index > 0 and index < _ids.size():
			close_requested.emit(_ids[index]))
	row.add_child(_bar)
	_add_button = Button.new()
	_add_button.name = "NewSessionTabButton"
	_add_button.flat = true
	_add_button.text = "+"
	_add_button.tooltip_text = I18n.t("Open another agent session alongside this one. Sessions don't step on each other: a file one is editing in its turn is off limits to the rest, and the game runs for one at a time.")
	_add_button.pressed.connect(func() -> void: new_session_requested.emit())
	row.add_child(_add_button)
	_stack = MarginContainer.new()
	_stack.size_flags_vertical = Control.SIZE_EXPAND_FILL
	for side: String in ["left", "top", "right", "bottom"]:
		_stack.add_theme_constant_override("margin_" + side, 0)
	add_child(_stack)


func add_session(id: String, dock: Control, model: SessionModel, label: String) -> void:
	_ids.append(id)
	_docks[id] = dock
	_models[id] = model
	_labels[id] = label
	_stack.add_child(dock)
	_bar.add_tab(label)
	if _ids.size() > 1:
		_bar.set_tab_button_icon(_ids.size() - 1, AgentTheme.icon(&"Close"))
	model.title_changed.connect(func(_title: String) -> void: _refresh_tab(id))
	model.state_changed.connect(func(_state: SessionModel.SessionState) -> void: _refresh_tab(id))
	_refresh_tab(id)
	select(id)


func remove_session(id: String) -> void:
	var index := _ids.find(id)
	if index <= 0:
		return
	var dock: Control = _docks[id]
	_ids.remove_at(index)
	_docks.erase(id)
	_models.erase(id)
	_labels.erase(id)
	_bar.remove_tab(index)
	_stack.remove_child(dock)
	dock.queue_free()
	_on_tab_changed(_bar.current_tab)


func select(id: String) -> void:
	var index := _ids.find(id)
	if index < 0:
		return
	if _bar.current_tab == index:
		_on_tab_changed(index)
	else:
		_bar.current_tab = index


func active_id() -> String:
	return _ids[_bar.current_tab] if _bar.current_tab >= 0 and _bar.current_tab < _ids.size() else ""


func dock(id: String) -> Control:
	return _docks.get(id)


func ids() -> PackedStringArray:
	return _ids


## Nombre visible de la sesión: el título que le puso el agente o «Session N».
func label(id: String) -> String:
	var model: SessionModel = _models.get(id)
	if model and not model.title.strip_edges().is_empty():
		return "%s · %s" % [_labels[id], model.title.strip_edges().left(40)]
	return str(_labels.get(id, id))


func _refresh_tab(id: String) -> void:
	var index := _ids.find(id)
	if index < 0:
		return
	var model: SessionModel = _models[id]
	var busy := model.is_busy()
	_bar.set_tab_title(index, ("● " if busy else "") + str(_labels[id]))
	_bar.set_tab_tooltip(index, label(id))


func _on_tab_changed(index: int) -> void:
	for i in _ids.size():
		(_docks[_ids[i]] as Control).visible = i == index
	if index >= 0 and index < _ids.size():
		active_changed.emit(_ids[index])
