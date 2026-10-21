@tool
extends ScrollContainer
## Lista de mensajes del dock. Lee las entradas del SessionModel al conectarse (pull) y después
## escucha sus señales (push). Mantiene un máximo de vistas para sesiones largas.

## Acción de una entrada (ver EntryView.action_requested).
signal action_requested(action: String, payload: Variant)

const SessionModel := preload("../../session/session_model.gd")
const ChatEntry := preload("../../session/chat_entry.gd")
const ToolCall := preload("../../session/tool_call.gd")
const AgentTheme := preload("../agent_theme.gd")
const MarkdownBBCode := preload("../markdown/markdown_bbcode.gd")
const EntryView := preload("entries/entry_view.gd")
const UserMessageView := preload("entries/user_message_view.gd")
const AgentMessageView := preload("entries/agent_message_view.gd")
const NoticeView := preload("entries/notice_view.gd")
const ToolGroupView := preload("entries/tool_group_view.gd")
const PlanView := preload("entries/plan_view.gd")

## Vistas vivas como máximo; las más viejas se descartan (siguen en el modelo).
const MAX_VIEWS := 250
## Distancia al fondo (px) dentro de la cual se sigue el streaming automáticamente.
const STICK_THRESHOLD := 48.0

## Callable(entry: ChatEntry) -> EntryView para tipos que arma otro módulo (p. ej. permisos, M2).
var extra_view_factory: Callable

var _model: SessionModel
var _accent: Color
var _markdown := MarkdownBBCode.new()
var _list: VBoxContainer
var _hidden_label: Label
var _views: Dictionary = {}  # entry id -> EntryView
var _order: Array[int] = []
var _hidden_count: int = 0
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
	_hidden_label = Label.new()
	_hidden_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hidden_label.add_theme_color_override(&"font_color", AgentTheme.MUTED)
	_hidden_label.visible = false
	_list.add_child(_hidden_label)
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


func _add_view(entry: ChatEntry) -> void:
	var view := _make_view(entry)
	if view == null:
		return
	view.action_requested.connect(func(action: String, payload: Variant) -> void: action_requested.emit(action, payload))
	_views[entry.id] = view
	_order.append(entry.id)
	_list.add_child(view)
	_trim()
	_request_scroll()


func _make_view(entry: ChatEntry) -> EntryView:
	var view: EntryView
	match entry.kind:
		ChatEntry.Kind.USER:
			view = UserMessageView.new()
		ChatEntry.Kind.AGENT, ChatEntry.Kind.THOUGHT:
			view = AgentMessageView.new()
		ChatEntry.Kind.NOTICE:
			view = NoticeView.new()
		ChatEntry.Kind.TOOL_GROUP:
			var group := ToolGroupView.new()
			group.tool_call_lookup = _model.tool_call
			view = group
		ChatEntry.Kind.PLAN:
			view = PlanView.new()
		_:
			if extra_view_factory.is_valid():
				view = extra_view_factory.call(entry)
	if view:
		view.setup(entry, _accent, _markdown)
	return view


func _refresh_view(entry: ChatEntry) -> void:
	var view: EntryView = _views.get(entry.id)
	if view and view.is_node_ready():
		view.refresh()
		_request_scroll()


func _on_tool_call_changed(_call: ToolCall, group: ChatEntry) -> void:
	if group:
		_refresh_view(group)


func _remove_view(entry: ChatEntry) -> void:
	var view: EntryView = _views.get(entry.id)
	if view:
		_views.erase(entry.id)
		_order.erase(entry.id)
		view.queue_free()


func _clear() -> void:
	for id: int in _views:
		(_views[id] as Node).queue_free()
	_views.clear()
	_order.clear()
	_hidden_count = 0
	_hidden_label.visible = false
	_stick_to_bottom = true


func _trim() -> void:
	while _order.size() > MAX_VIEWS:
		var id: int = _order.pop_front()
		var view: EntryView = _views.get(id)
		_views.erase(id)
		if view:
			view.queue_free()
		_hidden_count += 1
	_hidden_label.visible = _hidden_count > 0
	_hidden_label.text = "%d entradas anteriores ocultas" % _hidden_count


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
