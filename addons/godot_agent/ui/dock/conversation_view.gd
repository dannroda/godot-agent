@tool
extends ScrollContainer
## Lista de mensajes del dock. Lee las entradas del SessionModel al conectarse (pull) y después
## escucha sus señales (push). Para sesiones largas mantiene un máximo de vistas vivas (las viejas
## se cargan bajo demanda con "Mostrar anteriores") y refresca cada vista a lo sumo una vez por frame.

## Acción de una entrada (ver EntryView.action_requested).
signal action_requested(action: String, payload: Variant)

const SessionModel := preload("../../session/session_model.gd")
const ChatEntry := preload("../../session/chat_entry.gd")
const ToolCall := preload("../../session/tool_call.gd")
const I18n := preload("../../core/i18n.gd")
const AgentTheme := preload("../agent_theme.gd")
const MarkdownBBCode := preload("../markdown/markdown_bbcode.gd")
const EntryView := preload("entries/entry_view.gd")
const UserMessageView := preload("entries/user_message_view.gd")
const AgentMessageView := preload("entries/agent_message_view.gd")
const NoticeView := preload("entries/notice_view.gd")
const ToolGroupView := preload("entries/tool_group_view.gd")
const PlanView := preload("entries/plan_view.gd")
const PermissionView := preload("entries/permission_view.gd")
const ElicitationView := preload("entries/elicitation_view.gd")

## Vistas vivas como máximo; las más viejas se descartan (siguen en el modelo).
const MAX_VIEWS := 250
## Entradas que agrega cada "Mostrar anteriores".
const SHOW_OLDER_STEP := 50
## Tiempo de un frame para armar vistas nuevas; el resto queda para el siguiente.
const BUILD_BUDGET_USEC := 8000
## Distancia al fondo (px) dentro de la cual se sigue el streaming automáticamente.
const STICK_THRESHOLD := 48.0

## Callable(entry: ChatEntry) -> EntryView para tipos que arma otro módulo (p. ej. permisos, M2).
var extra_view_factory: Callable

var _model: SessionModel
var _accent: Color
var _markdown := MarkdownBBCode.new()
var _list: VBoxContainer
var _show_older: Button
var _views: Dictionary = {}  # entry id -> EntryView
var _order: Array[int] = []
var _hidden_count: int = 0
## Máximo actual: MAX_VIEWS más lo que el usuario pidió ver con "Mostrar anteriores".
var _limit: int = MAX_VIEWS
var _pending_refresh: Dictionary = {}  # entry id -> ChatEntry
## Entradas nuevas que todavía no tienen vista (se arman por tandas en _build_pending).
var _pending_add: Array[ChatEntry] = []
var _stick_to_bottom: bool = true
var _scroll_pending: bool = false


func setup(model: SessionModel, accent: Color) -> void:
	_model = model
	set_accent(accent)


func set_accent(accent: Color) -> void:
	_accent = accent
	_markdown.code_color = AgentTheme.color_hex(accent)
	_markdown.muted_color = "#8a8f98"
	_markdown.code_bg_color = "#" + Color(0, 0, 0, 0.25).to_html(true)
	_markdown.highlighter.use_editor_colors()


func _ready() -> void:
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, AgentTheme.px(6))
	add_child(margin)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override(&"separation", AgentTheme.px(10))
	margin.add_child(_list)
	_show_older = Button.new()
	_show_older.flat = true
	_show_older.add_theme_color_override(&"font_color", AgentTheme.MUTED)
	_show_older.visible = false
	_show_older.pressed.connect(show_older)
	_list.add_child(_show_older)
	get_v_scroll_bar().value_changed.connect(_on_scrolled)
	get_v_scroll_bar().changed.connect(_on_scroll_range_changed)
	if _model:
		_model.entry_added.connect(_add_view)
		_model.entry_updated.connect(_refresh_view)
		_model.entry_removed.connect(_remove_view)
		_model.entries_cleared.connect(_clear)
		_model.tool_call_changed.connect(_on_tool_call_changed)
		for entry: ChatEntry in _model.entries():
			_add_view(entry)


func entry_count() -> int:
	return _views.size()


## Hay entradas esperando su vista (ráfaga en curso).
func is_building() -> bool:
	return not _pending_add.is_empty()


func hidden_count() -> int:
	return _hidden_count


## Las vistas se arman por tandas con un presupuesto por frame. Si en una ráfaga llegan más
## entradas que el tope, las que quedarían ocultas ni se arman.
func _add_view(entry: ChatEntry) -> void:
	if _pending_add.is_empty():
		_build_pending.call_deferred()
	_pending_add.append(entry)


func _build_pending() -> void:
	if not is_inside_tree():
		if not tree_entered.is_connected(_build_pending):
			tree_entered.connect(_build_pending, CONNECT_ONE_SHOT)
		return
	var overflow := _pending_add.size() - _limit
	if overflow > 0:
		_hidden_count += overflow
		_pending_add = _pending_add.slice(overflow)
		# Las vistas que había ya quedan más viejas que todo lo pendiente.
		while not _order.is_empty():
			_drop_oldest()
	var started := Time.get_ticks_usec()
	while not _pending_add.is_empty():
		var entry: ChatEntry = _pending_add.pop_front()
		var view := _make_view(entry)
		if view:
			_track(entry, view)
			_order.append(entry.id)
			_list.add_child(view)
		if Time.get_ticks_usec() - started > BUILD_BUDGET_USEC:
			break
	_trim()
	_request_scroll()
	if not _pending_add.is_empty() and not get_tree().process_frame.is_connected(_build_pending):
		get_tree().process_frame.connect(_build_pending, CONNECT_ONE_SHOT)


func _track(entry: ChatEntry, view: EntryView) -> void:
	view.action_requested.connect(func(action: String, payload: Variant) -> void: action_requested.emit(action, payload))
	_views[entry.id] = view


## "Mostrar anteriores": vuelve a armar las SHOW_OLDER_STEP entradas previas a la primera visible.
func show_older() -> void:
	if _hidden_count <= 0 or _order.is_empty():
		return
	var entries := _model.entries()
	var first := -1
	for i in entries.size():
		if entries[i].id == _order[0]:
			first = i
			break
	if first <= 0:
		return
	var start := maxi(0, first - SHOW_OLDER_STEP)
	var position := 1  # después del botón
	var added := 0
	for i in range(start, first):
		var view := _make_view(entries[i])
		if view == null:
			continue
		_track(entries[i], view)
		_order.insert(added, entries[i].id)
		_list.add_child(view)
		_list.move_child(view, position + added)
		added += 1
	_hidden_count = maxi(0, _hidden_count - (first - start))
	_limit += first - start
	_stick_to_bottom = false
	_update_show_older()


func _make_view(entry: ChatEntry) -> EntryView:
	var view: EntryView
	match entry.kind:
		ChatEntry.EntryKind.USER:
			view = UserMessageView.new()
		ChatEntry.EntryKind.AGENT, ChatEntry.EntryKind.THOUGHT:
			view = AgentMessageView.new()
		ChatEntry.EntryKind.NOTICE:
			view = NoticeView.new()
		ChatEntry.EntryKind.TOOL_GROUP:
			var group := ToolGroupView.new()
			group.tool_call_lookup = _model.tool_call
			view = group
		ChatEntry.EntryKind.PLAN:
			view = PlanView.new()
		ChatEntry.EntryKind.PERMISSION:
			view = PermissionView.new()
		ChatEntry.EntryKind.ELICITATION:
			view = ElicitationView.new()
		_:
			if extra_view_factory.is_valid():
				view = extra_view_factory.call(entry)
	if view:
		view.setup(entry, _accent, _markdown)
	return view


## Los updates llegan en ráfagas (muchos por frame): cada vista se refresca una sola vez por frame.
func _refresh_view(entry: ChatEntry) -> void:
	if not _views.has(entry.id):
		return
	if _pending_refresh.is_empty():
		_flush_refreshes.call_deferred()
	_pending_refresh[entry.id] = entry


func _flush_refreshes() -> void:
	var pending := _pending_refresh
	_pending_refresh = {}  # lo que se encole mientras tanto va a la próxima tanda
	for id: int in pending:
		var view: EntryView = _views.get(id)
		if is_instance_valid(view) and view.is_node_ready():
			view.refresh()
	_request_scroll()


func _on_tool_call_changed(_call: ToolCall, group: ChatEntry) -> void:
	if group:
		_refresh_view(group)


func _remove_view(entry: ChatEntry) -> void:
	_pending_add.erase(entry)
	var view: EntryView = _views.get(entry.id)
	_pending_refresh.erase(entry.id)
	if view:
		_views.erase(entry.id)
		_order.erase(entry.id)
		view.queue_free()


func _clear() -> void:
	for id: int in _views:
		(_views[id] as Node).queue_free()
	_views.clear()
	_order.clear()
	_pending_refresh.clear()
	_pending_add.clear()
	_hidden_count = 0
	_limit = MAX_VIEWS
	_update_show_older()
	_stick_to_bottom = true


func _trim() -> void:
	while _order.size() > _limit:
		_drop_oldest()
	_update_show_older()


func _drop_oldest() -> void:
	var id: int = _order.pop_front()
	var view: EntryView = _views.get(id)
	_views.erase(id)
	_pending_refresh.erase(id)
	if view:
		view.queue_free()
	_hidden_count += 1


func _update_show_older() -> void:
	_show_older.visible = _hidden_count > 0
	_show_older.text = I18n.t("Show %d earlier (%d hidden)") % [mini(SHOW_OLDER_STEP, _hidden_count), _hidden_count]


func _on_scrolled(value: float) -> void:
	var bar := get_v_scroll_bar()
	_stick_to_bottom = value >= bar.max_value - bar.page - STICK_THRESHOLD


func _on_scroll_range_changed() -> void:
	if _stick_to_bottom:
		_request_scroll()


func _request_scroll() -> void:
	if not _stick_to_bottom or _scroll_pending:
		return
	_scroll_pending = true
	_scroll_to_bottom.call_deferred()


func _scroll_to_bottom() -> void:
	_scroll_pending = false
	var bar := get_v_scroll_bar()
	scroll_vertical = int(bar.max_value)
	_stick_to_bottom = true
