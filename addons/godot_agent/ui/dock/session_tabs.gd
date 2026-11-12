@tool
extends VBoxContainer
## Varias sesiones del agente abiertas a la vez (m7-44): una pestaña por sesión, cada una con su
## dock completo, y «+» para abrir otra, como las pestañas de un navegador. La primera no se cierra:
## solo las demás llevan el botón de cerrar. Doble clic en una pestaña la renombra.

## «+»: otra sesión; `in_copy`, en una copia aparte del proyecto (git worktree, m11-09).
signal new_session_requested(in_copy: bool)
signal close_requested(id: String)
signal active_changed(id: String)
## El usuario escribió un nombre para la sesión ("" = volver al de por defecto). Lo aplica set_label().
signal rename_requested(id: String, name: String)

const NAME_MAX := 40
## Ícono del editor de la pestaña de una copia aparte (sin él, «⎘» delante del nombre).
const COPY_ICON := &"Duplicate"
## Ícono de la pestaña de la sesión principal, que no se cierra (m12-50).
const PIN_ICON := &"Pin"

const AgentTheme := preload("../agent_theme.gd")
const I18n := preload("../../core/i18n.gd")
const EditorWindows := preload("../editor_windows.gd")
const SessionModel := preload("../../session/session_model.gd")
const DesktopNotifier := preload("../../editor/desktop_notifier.gd")

var _bar: TabBar
## La fila de pestañas: solo con dos sesiones o más (m12-14); con una, el «+» del dock abre otra.
var _row: HBoxContainer
var _add_button: Button
var _new_menu: PopupMenu
## Los docks, uno encima del otro (se ve el de la pestaña activa); como contenedor, pide el mínimo
## del dock visible, igual que cuando el dock iba solo.
var _stack: MarginContainer
## Ids en el orden de las pestañas.
var _ids: PackedStringArray = []
var _docks: Dictionary = {}  # id -> dock
var _models: Dictionary = {}  # id -> SessionModel
var _labels: Dictionary = {}  # id -> nombre de la sesión («Session 2» o el que le puso el usuario)
var _defaults: Dictionary = {}  # id -> nombre por defecto («Session 2»)
## Las sesiones en una copia aparte: ícono en la pestaña y una línea en el tooltip (m12-45). Antes
## era el sufijo «(copy)», que en un dock angosto era lo primero que se cortaba.
var _copies: Dictionary = {}  # id -> línea del tooltip
## Sesiones que ya avisaron con un toast y siguen esperando: no se apila otro hasta que respondas.
var _toasted: Dictionary = {}  # id -> true
## Si se avisa fuera del editor (m11-40), Callable() -> bool; sin asignar, no se avisa.
var notify_outside_enabled: Callable
## Sesiones que ya avisaron fuera del editor que esperan: uno por espera.
var _outside_notified: Dictionary = {}  # id -> true
var _rename_popup: PopupPanel
var _rename_edit: LineEdit
var _renaming: String = ""


func _init() -> void:
	add_theme_constant_override(&"separation", 0)
	var row := HBoxContainer.new()
	row.name = "SessionTabsRow"
	row.visible = false
	_row = row
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
	_bar.gui_input.connect(_on_bar_input)
	row.add_child(_bar)
	_add_button = Button.new()
	_add_button.name = "NewSessionTabButton"
	_add_button.flat = true
	# Ícono y no el texto «+»: el glifo salía de la mitad del tamaño de los íconos del header.
	_add_button.icon = AgentTheme.icon(&"Add")
	if _add_button.icon == null:
		_add_button.text = "+"
	_add_button.custom_minimum_size = Vector2.ONE * AgentTheme.px(28)
	_add_button.tooltip_text = I18n.t("Open another agent session alongside this one. Sessions don't step on each other: a file one is editing in its turn is off limits to the rest, and the game runs for one at a time.")
	_new_menu = PopupMenu.new()
	_new_menu.add_item(I18n.t("New session"), 0)
	_new_menu.add_item(I18n.t("New session in a separate copy (git worktree)"), 1)
	_new_menu.set_item_tooltip(1, I18n.t("The agent works in a copy of the project on a new branch, outside the project folder, without touching the open editor. When you close its tab you choose whether to apply its changes to the project."))
	_new_menu.id_pressed.connect(func(id: int) -> void: new_session_requested.emit(id == 1))
	_add_button.add_child(_new_menu)
	_add_button.pressed.connect(func() -> void:
		var rect := _add_button.get_global_rect()
		_new_menu.popup(Rect2i(Vector2i(_add_button.get_screen_position() + Vector2(0, rect.size.y)), Vector2i.ZERO)))
	row.add_child(_add_button)
	_rename_popup = PopupPanel.new()
	_rename_edit = LineEdit.new()
	_rename_edit.max_length = NAME_MAX
	_rename_edit.custom_minimum_size.x = AgentTheme.px(180)
	_rename_edit.text_submitted.connect(func(text: String) -> void:
		_rename_popup.hide()
		rename_requested.emit(_renaming, text.strip_edges()))
	_rename_popup.add_child(_rename_edit)
	add_child(_rename_popup)
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
	_defaults[id] = label
	_stack.add_child(dock)
	_bar.add_tab(label)
	_row.visible = _ids.size() > 1
	if _ids.size() > 1:
		_bar.set_tab_button_icon(_ids.size() - 1, AgentTheme.icon(&"Close"))
		_refresh_tab(_ids[0])  # con la segunda pestaña, la principal muestra que es fija
	model.title_changed.connect(func(_title: String) -> void: _refresh_tab(id))
	model.state_changed.connect(func(_state: SessionModel.SessionState) -> void: _refresh_tab(id))
	model.permission_requested.connect(func(request: RefCounted) -> void:
		request.resolved.connect(func(_outcome: Dictionary) -> void: _refresh_tab(id), CONNECT_ONE_SHOT)
		_refresh_tab(id)
		_notify_waiting(id)
		_notify_outside(id, I18n.t("«%s» is waiting for your permission."), true))
	model.elicitation_requested.connect(func(request: RefCounted) -> void:
		request.resolved.connect(func(_response: Dictionary) -> void: _refresh_tab(id), CONNECT_ONE_SHOT)
		_refresh_tab(id)
		_notify_waiting(id, I18n.t("«%s» is waiting for your answer."))
		_notify_outside(id, I18n.t("«%s» is waiting for your answer."), true))
	model.turn_finished.connect(func(stop_reason: String) -> void:
		if stop_reason != "cancelled":
			_notify_outside(id, I18n.t("«%s» finished its turn.")))
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
	_copies.erase(id)
	_defaults.erase(id)
	_toasted.erase(id)
	_outside_notified.erase(id)
	_bar.remove_tab(index)
	_row.visible = _ids.size() > 1
	_refresh_tab(_ids[0])
	EditorWindows.rescue_progress(dock)
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


func default_label(id: String) -> String:
	return str(_defaults.get(id, id))


## Pone el nombre de la sesión; "" vuelve al de por defecto.
func set_label(id: String, name: String) -> void:
	if not _labels.has(id):
		return
	_labels[id] = name if not name.is_empty() else _defaults[id]
	_refresh_tab(id)


## Abre el campo para renombrar la sesión, debajo de su pestaña.
func start_rename(id: String) -> void:
	var index := _ids.find(id)
	if index < 0:
		return
	_renaming = id
	_rename_edit.text = _labels[id]
	_rename_edit.placeholder_text = _defaults[id]
	var rect := _bar.get_tab_rect(index)
	_rename_popup.popup(Rect2i(Vector2i(_bar.get_screen_position() + rect.position + Vector2(0, rect.size.y)), Vector2i.ZERO))
	_rename_edit.grab_focus()
	_rename_edit.select_all()


func _on_bar_input(event: InputEvent) -> void:
	var click := event as InputEventMouseButton
	if click and click.double_click and click.button_index == MOUSE_BUTTON_LEFT:
		var index := _bar.get_tab_idx_at_point(click.position)
		if index >= 0 and index < _ids.size():
			start_rename(_ids[index])


## Marca la pestaña de `id` como una copia aparte; `tooltip`: la línea que suma al tooltip.
func set_copy(id: String, tooltip: String) -> void:
	_copies[id] = tooltip
	_refresh_tab(id)


## La pestaña de la sesión principal se muestra fija (pin y tooltip) cuando hay más de una.
func is_pinned(id: String) -> bool:
	return _ids.size() > 1 and _ids.find(id) == 0


func is_copy(id: String) -> bool:
	return _copies.has(id)


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
	# «⚠»: espera un permiso o una respuesta del usuario (m11-03); pesa más que «●» (trabajando).
	var waiting := not model.pending_permissions.is_empty() or not model.pending_elicitations.is_empty()
	if not waiting:
		_toasted.erase(id)
		_outside_notified.erase(id)
	var mark := "⚠ " if waiting else ("● " if model.is_busy() else "")
	# La principal (sin X, m7-44) lleva un pin con otra pestaña al lado (m12-50); nunca es una copia.
	var pinned := is_pinned(id)
	var tab_icon := AgentTheme.icon(PIN_ICON) if pinned else (AgentTheme.icon(COPY_ICON) if _copies.has(id) else null)
	_bar.set_tab_icon(index, tab_icon)
	if tab_icon:
		_bar.set_tab_icon_max_width(index, AgentTheme.px(16))
	# Sin el ícono (fuera del editor), la copia conserva su «⎘»; el pin no tiene glifo: el tooltip alcanza.
	_bar.set_tab_title(index, mark + ("⎘ " if _copies.has(id) and tab_icon == null else "") + str(_labels[id]))
	var tooltip := label(id) + ("\n" + str(_copies[id]) if _copies.has(id) else "")
	if pinned:
		tooltip += "\n" + I18n.t("Main session: it can't be closed. Review marks and Remote Control use it. To start over: + → New session.")
	_bar.set_tab_tooltip(index, tooltip + "\n" + I18n.t("Double-click to rename"))


## Un pedido de permiso (o un formulario del agente) de una sesión que no está a la vista (otra pestaña, o el dock tapado por
## otro) también avisa con un toast del editor. Uno por sesión mientras siga esperando (m12-19): el
## toaster no deja actualizar ni quitar un toast, y la pestaña sigue con «⚠» hasta que respondas.
func _notify_waiting(id: String, message: String = "") -> void:
	var dock: Control = _docks.get(id)
	if dock == null or dock.is_visible_in_tree() or not Engine.is_editor_hint() or not _claim_toast(id):
		return
	var text := message if not message.is_empty() else I18n.t("«%s» is waiting for your permission.")
	EditorInterface.get_editor_toaster().push_toast(text % _labels[id], EditorToaster.SEVERITY_WARNING)


## Con la ventana del editor sin foco, avisa fuera del editor (m11-40). `waiting`: una espera, que
## avisa una vez hasta que se responde.
func _notify_outside(id: String, message: String, waiting: bool = false) -> void:
	if not notify_outside_enabled.is_valid() or not bool(notify_outside_enabled.call()):
		return
	if waiting and _outside_notified.has(id):
		return
	if DesktopNotifier.notify("Godot Agent", message % _labels[id]) and waiting:
		_outside_notified[id] = true


## true si la sesión todavía no avisó desde que empezó a esperar (y lo marca).
func _claim_toast(id: String) -> bool:
	if _toasted.has(id):
		return false
	_toasted[id] = true
	return true


func _on_tab_changed(index: int) -> void:
	for i in _ids.size():
		(_docks[_ids[i]] as Control).visible = i == index
	if index >= 0 and index < _ids.size():
		active_changed.emit(_ids[index])
