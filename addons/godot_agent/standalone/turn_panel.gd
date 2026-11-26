extends PanelContainer
## «Este turno» al costado del chat de la app aparte (m21-05): los archivos que el turno de la sesión
## elegida lleva cambiados, en vivo (TurnCounter), o los del último turno cuando no hay uno en curso,
## con Ver cambios; y los archivos que tienen tomados las otras sesiones de la app. Reemplaza en la app
## al contador pegado al composer.

const AgentTheme := preload("../ui/agent_theme.gd")
const I18n := preload("../core/i18n.gd")
const TurnCounter := preload("../ui/turn_counter.gd")
const SessionCoordinator := preload("../session/session_coordinator.gd")

const WIDTH := 280
const BUSY_COLOR := Color("#4fc1a6")
const LOCK_ICON := '<rect x="5" y="11" width="14" height="9" rx="2"/><path d="M8 11V8a4 4 0 0 1 8 0v3"/>'
## Archivos que se listan; los demás se cuentan.
const MAX_FILES := 30

var counter: TurnCounter
var coordinator: SessionCoordinator
## `() -> PackedStringArray`: las sesiones abiertas. `(id) -> SessionController` o null.
var sessions: Callable
var controller_of: Callable
## `(data) -> void`: abre el diálogo de los cambios de un turno terminado.
var open_turn: Callable
## La carpeta del proyecto: las rutas se muestran relativas a ella.
var root: String = ""

var _session := ""
var _column: VBoxContainer
var _refresh_queued := false


func _ready() -> void:
	custom_minimum_size.x = AgentTheme.px(WIDTH)
	add_theme_stylebox_override(&"panel", AgentTheme.panel(AgentTheme.dark_color(), Color.TRANSPARENT, 0.0, 10.0))
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	_column = VBoxContainer.new()
	_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_column.add_theme_constant_override(&"separation", AgentTheme.px(6))
	scroll.add_child(_column)
	counter.updated.connect(func(session: String) -> void:
		if session == _session:
			refresh())
	coordinator.changed.connect(refresh)
	refresh()


## La sesión que se muestra (la elegida en la barra lateral).
func show_session(id: String) -> void:
	if id == _session:
		return
	_session = id
	refresh()


## Se arma de nuevo en el próximo frame: varias señales llegan juntas.
func refresh() -> void:
	if _refresh_queued or _column == null:
		return
	_refresh_queued = true
	_rebuild.call_deferred()


func _rebuild() -> void:
	_refresh_queued = false
	for child: Node in _column.get_children():
		_column.remove_child(child)
		child.queue_free()
	var live := counter.latest(_session) if not _session.is_empty() else {}
	var controller: Object = controller_of.call(_session) if controller_of.is_valid() and not _session.is_empty() else null
	var last: Dictionary = controller.get(&"last_turn_changes") if controller else {}
	var files: Array = live.get("files", []) if not live.is_empty() else last.get("files", [])
	var head := HBoxContainer.new()
	var title := _title(I18n.t("This turn") if not live.is_empty() else (I18n.t("Last turn") if not last.is_empty() else I18n.t("This turn")))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	if not live.is_empty():
		var badge := Label.new()
		badge.name = "LiveBadge"
		badge.text = I18n.t("live")
		badge.add_theme_color_override(&"font_color", BUSY_COLOR)
		badge.add_theme_stylebox_override(&"normal", AgentTheme.panel(Color(BUSY_COLOR, 0.14), Color.TRANSPARENT, 9.0, 3.0))
		head.add_child(badge)
	_column.add_child(head)
	if files.is_empty():
		_column.add_child(_note(I18n.t("Nothing changed yet. The files a turn changes show here while the agent writes them.")))
	else:
		_column.add_child(_note(I18n.t("Live, while the agent works") if not live.is_empty() else I18n.t("The turn is over: undo it from the chat")))
		for file: Dictionary in files.slice(0, MAX_FILES):
			_column.add_child(_file_row(file))
		if files.size() > MAX_FILES:
			_column.add_child(_note(I18n.t("and %d more") % (files.size() - MAX_FILES)))
	_column.add_child(HSeparator.new())
	_column.add_child(_title(I18n.t("Taken by other sessions")))
	var taken := 0
	for other: String in (sessions.call() if sessions.is_valid() else PackedStringArray()):
		if other == _session:
			continue
		for path: String in coordinator.files_of(other):
			_column.add_child(_taken_row(path, coordinator.label(other)))
			taken += 1
	if taken == 0:
		_column.add_child(_note(I18n.t("None: a file another session edits in its turn shows here, and is off limits to this one until that turn ends.")))
	if not files.is_empty():
		# Abajo de todo, como en el diseño: lo que se mira al final del turno.
		var spacer := Control.new()
		spacer.custom_minimum_size.y = AgentTheme.px(8)
		_column.add_child(spacer)
		var view := Button.new()
		view.name = "ViewChangesButton"
		view.text = I18n.t("View all the changes of the turn")
		view.custom_minimum_size.y = AgentTheme.px(34)
		view.pressed.connect(func() -> void:
			if not counter.latest(_session).is_empty():
				counter.open(_session)
			elif open_turn.is_valid() and not last.is_empty():
				open_turn.call(last))
		_column.add_child(view)


func _file_row(file: Dictionary) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", AgentTheme.px(6))
	var status := str(file.get("status", "M"))
	var badge := Label.new()
	badge.text = status
	badge.custom_minimum_size = Vector2.ONE * AgentTheme.px(20)
	badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var tint := AgentTheme.ADDED if status == "A" else (AgentTheme.REMOVED if status == "D" else AgentTheme.WARNING)
	badge.add_theme_color_override(&"font_color", tint)
	badge.add_theme_stylebox_override(&"normal", AgentTheme.panel(Color(tint, 0.16), Color.TRANSPARENT, 5.0, 0.0))
	badge.add_theme_font_override(&"font", AgentTheme.mono_font())
	badge.add_theme_font_size_override(&"font_size", AgentTheme.px(12))
	badge.tooltip_text = {"A": I18n.t("Added file"), "D": I18n.t("Deleted file")}.get(status, I18n.t("Modified file"))
	badge.mouse_filter = Control.MOUSE_FILTER_PASS
	row.add_child(badge)
	var path := _path_label(str(file.get("path", "")))
	row.add_child(path)
	if int(file.get("added", 0)) > 0:
		row.add_child(_count("+%d" % int(file.added), AgentTheme.ADDED))
	if int(file.get("removed", 0)) > 0:
		row.add_child(_count("−%d" % int(file.removed), AgentTheme.REMOVED))
	return row


func _taken_row(path: String, holder: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", AgentTheme.px(6))
	var lock := TextureRect.new()
	lock.texture = AgentTheme.stroke_icon(LOCK_ICON, AgentTheme.MUTED, 14.0)
	lock.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	row.add_child(lock)
	row.add_child(_path_label(path.trim_prefix(root.path_join(""))))
	var who := Label.new()
	who.text = holder
	who.modulate = Color(1, 1, 1, 0.65)
	row.add_child(who)
	return row


func _path_label(path: String) -> Label:
	var label := Label.new()
	label.text = path
	label.tooltip_text = path
	label.mouse_filter = Control.MOUSE_FILTER_PASS
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.clip_text = true
	return label


func _count(text: String, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_color_override(&"font_color", color)
	return label


func _title(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.modulate = Color(1, 1, 1, 0.6)
	return label


func _note(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.modulate = Color(1, 1, 1, 0.65)
	return label
