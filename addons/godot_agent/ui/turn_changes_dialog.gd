@tool
extends AcceptDialog
## Los archivos que cambió un turno (m11-02): cada uno con su diff y «Volver atrás», que lo deja
## como estaba antes del turno. Un archivo de texto se abre en sus trozos (m11-34): cada uno se
## conserva o se rechaza, y un rechazo se deshace; «Rechazar todo» rechaza los que se puede.

## Pide el diff de un archivo (el plugin lo muestra en el DiffDialog).
signal diff_requested(data: Dictionary, path: String)
## Pide volver atrás un archivo; el plugin llama a mark_reverted() cuando terminó.
signal revert_requested(data: Dictionary, path: String)
## Pide los trozos de un archivo; el plugin responde con set_hunks().
signal hunks_requested(data: Dictionary, path: String)
## Una acción sobre un trozo: "keep", "unkeep", "reject" o "undo".
signal hunk_action(data: Dictionary, path: String, index: int, action: String)
## Rechazar todos los trozos que se puede de un archivo.
signal reject_file_requested(data: Dictionary, path: String)

const I18n := preload("../core/i18n.gd")
const AgentTheme := preload("agent_theme.gd")
const ExtensionsUi := preload("extensions/extensions_ui.gd")
const MarkdownBBCode := preload("markdown/markdown_bbcode.gd")
const TurnSnapshots := preload("../session/turn_snapshots.gd")

## Líneas de un trozo que se muestran; las demás, en el diff completo.
const HUNK_MAX_LINES := 40
## Los binarios no tienen trozos. Una .tscn se abre por nodo (SceneRevert).
const NO_HUNKS_EXTENSIONS: PackedStringArray = ["scn", "res", "png", "jpg", "jpeg", "webp", "svg", "wav", "ogg", "mp3", "glb", "ttf", "otf"]
const MAX_VALUE := 80

var _box: VBoxContainer
var _data: Dictionary = {}
var _reverted: Dictionary = {}
## ruta -> los trozos que mandó el plugin (o [] mientras se cargan).
var _expanded: Dictionary = {}
## ruta -> por qué no se pudo la última acción.
var _errors: Dictionary = {}


func _init() -> void:
	title = I18n.t("Changes of the turn")
	ok_button_text = I18n.t("Close")
	var page := VBoxContainer.new()
	page.custom_minimum_size = Vector2(AgentTheme.px(560), AgentTheme.px(360))
	add_child(page)
	page.add_child(ExtensionsUi.muted(I18n.t("What the agent changed in the project during that turn. Open a file to keep or reject each change; «Go back» leaves the whole file as it was before the turn.")))
	_box = ExtensionsUi.scroll_list(page)


func show_turn(data: Dictionary) -> void:
	_data = data
	_reverted.clear()
	_expanded.clear()
	_errors.clear()
	_rebuild()
	popup_centered()


func mark_reverted(path: String) -> void:
	_reverted[path] = true
	_expanded.erase(path)
	_rebuild()


## Los trozos de un archivo abierto (ver TurnChanges.file_hunks()).
func set_hunks(data: Dictionary, path: String, items: Array[Dictionary]) -> void:
	if data != _data or not _expanded.has(path):
		return
	_expanded[path] = items
	_rebuild()


## Por qué no se pudo la última acción en un archivo ("" la borra).
func set_error(data: Dictionary, path: String, text: String) -> void:
	if data != _data:
		return
	if text.is_empty():
		if not _errors.has(path):
			return
		_errors.erase(path)
	else:
		_errors[path] = text
	_rebuild()


## Algo cambió en un archivo: si está abierto, se vuelven a pedir sus trozos.
func refresh_file(data: Dictionary, path: String) -> void:
	if data == _data and _expanded.has(path):
		hunks_requested.emit(_data, path)


static func has_hunks(path: String) -> bool:
	return not path.get_extension().to_lower() in NO_HUNKS_EXTENSIONS


func _rebuild() -> void:
	ExtensionsUi.clear(_box)
	for file: Dictionary in _data.get("files", []):
		var path := str(file.path)
		_box.add_child(_file_row(file))
		if _expanded.has(path):
			_box.add_child(_hunks_box(path, _expanded[path]))


func _file_row(file: Dictionary) -> HBoxContainer:
	var path := str(file.path)
	var row := HBoxContainer.new()
	row.name = "File_" + path.validate_node_name()
	var open := Button.new()
	open.flat = true
	open.text = "▾" if _expanded.has(path) else "▸"
	open.tooltip_text = I18n.t("Show its changes one by one")
	open.disabled = not has_hunks(path) or file.status == "D" or _reverted.has(path)
	open.pressed.connect(func() -> void:
		if _expanded.has(path):
			_expanded.erase(path)
			_rebuild()
		else:
			_expanded[path] = []
			_rebuild()
			hunks_requested.emit(_data, path))
	row.add_child(open)
	var status := Label.new()
	status.text = {"A": "+", "D": "−"}.get(file.status, "~")
	status.add_theme_color_override(&"font_color", {"A": AgentTheme.ADDED, "D": AgentTheme.REMOVED}.get(file.status, AgentTheme.MUTED))
	row.add_child(status)
	var label := Label.new()
	label.text = path
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.clip_text = true
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.tooltip_text = path
	label.mouse_filter = Control.MOUSE_FILTER_PASS
	row.add_child(label)
	var counts := ExtensionsUi.muted("+%d −%d" % [file.added, file.removed])
	counts.autowrap_mode = TextServer.AUTOWRAP_OFF
	row.add_child(counts)
	var diff := Button.new()
	diff.text = I18n.t("Diff")
	diff.flat = true
	diff.pressed.connect(func() -> void: diff_requested.emit(_data, path))
	row.add_child(diff)
	var back := Button.new()
	back.text = I18n.t("Went back") if _reverted.has(path) else I18n.t("Go back")
	back.disabled = _reverted.has(path) or _data.get("live", false)
	back.pressed.connect(func() -> void:
		back.disabled = true
		revert_requested.emit(_data, path))
	row.add_child(back)
	return row


func _hunks_box(path: String, items: Array) -> MarginContainer:
	var margin := MarginContainer.new()
	margin.name = "Hunks_" + path.validate_node_name()
	margin.add_theme_constant_override(&"margin_left", AgentTheme.px(24))
	var box := VBoxContainer.new()
	margin.add_child(box)
	if items.is_empty():
		box.add_child(ExtensionsUi.muted(I18n.t("Loading…")))
		return margin
	if _errors.has(path):
		var error := ExtensionsUi.error_label(str(_errors[path]))
		error.name = "Error"
		box.add_child(error)
	var blocked := str(items[0].blocked)
	if not blocked.is_empty():
		var reason := ExtensionsUi.muted(blocked)
		reason.name = "Blocked"
		box.add_child(reason)
	var pending := 0
	for item: Dictionary in items:
		if item.state != "rejected" and not item.stale and (not item.has("scene") or item.scene.rejectable):
			pending += 1
		if box.get_child_count() > 0 and box.get_child(-1).name.begins_with("Hunk"):
			box.add_child(HSeparator.new())
		box.add_child(_hunk_card(path, item, blocked.is_empty()))
	var all := Button.new()
	all.name = "RejectAll"
	all.text = I18n.t("Reject all in this file")
	all.disabled = pending == 0 or not blocked.is_empty()
	all.size_flags_horizontal = Control.SIZE_SHRINK_END
	all.pressed.connect(func() -> void:
		all.disabled = true
		reject_file_requested.emit(_data, path))
	box.add_child(all)
	return margin


func _hunk_card(path: String, item: Dictionary, enabled: bool) -> VBoxContainer:
	var index := int(item.index)
	var scene: Dictionary = item.get("scene", {})
	var rejectable: bool = scene.is_empty() or scene.rejectable
	var card := VBoxContainer.new()
	card.name = "Hunk%d" % index
	var head := HBoxContainer.new()
	card.add_child(head)
	var where := Label.new()
	if not scene.is_empty():
		where.text = str(scene.label)
		where.clip_text = true
		where.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		where.tooltip_text = str(scene.label)
	else:
		var changed := TurnSnapshots.changed_lines(item.hunk)
		var first: int = changed.new_first
		var last: int = changed.new_last
		if last < first:
			where.text = I18n.t("Removed at line %d") % first
		else:
			where.text = I18n.t("Line %d") % first if last == first else I18n.t("Lines %d–%d") % [first, last]
	where.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(where)
	var state := ExtensionsUi.muted(_state_text(item))
	state.name = "State"
	state.autowrap_mode = TextServer.AUTOWRAP_OFF
	head.add_child(state)
	var keep := Button.new()
	keep.name = "Keep"
	keep.flat = true
	keep.toggle_mode = true
	keep.text = I18n.t("Keep")
	keep.button_pressed = item.state == "kept"
	keep.disabled = item.state == "rejected" or _data.get("live", false)
	keep.toggled.connect(func(on: bool) -> void: hunk_action.emit(_data, path, index, "keep" if on else "unkeep"))
	head.add_child(keep)
	var reject := Button.new()
	reject.name = "Reject"
	reject.flat = true
	var rejected: bool = item.state == "rejected"
	reject.text = I18n.t("Undo") if rejected else I18n.t("Reject")
	reject.disabled = not enabled or item.stale or not rejectable
	reject.tooltip_text = I18n.t("Put this change back in the file.") if rejected else I18n.t("Undo this change in the file. What changed elsewhere in the file stays.")
	if not rejectable:
		reject.tooltip_text = I18n.t("This scene change can't be rejected on its own (it is in a resource that other nodes use too): use «Go back» for the whole file.")
	reject.pressed.connect(func() -> void:
		reject.disabled = true
		hunk_action.emit(_data, path, index, "undo" if rejected else "reject"))
	head.add_child(reject)
	var text := RichTextLabel.new()
	text.name = "Lines"
	text.bbcode_enabled = true
	text.fit_content = true
	text.scroll_active = false
	text.selection_enabled = true
	text.add_theme_font_override(&"normal_font", AgentTheme.mono_font())
	text.add_theme_font_size_override(&"normal_font_size", AgentTheme.mono_font_size())
	text.text = hunk_bbcode(item.hunk) if scene.is_empty() else scene_bbcode(scene)
	if rejected:
		text.modulate.a = 0.5
	card.add_child(text)
	return card


func _state_text(item: Dictionary) -> String:
	match str(item.state):
		"rejected":
			return I18n.t("Rejected") if not item.stale else I18n.t("Rejected · changed afterwards")
		"kept":
			return I18n.t("Kept") if not item.stale else I18n.t("Kept · changed afterwards")
	if item.has("scene") and not item.scene.rejectable:
		return I18n.t("Only with «Go back»")
	return I18n.t("Changed after the turn") if item.stale else ""


## Un cambio de escena: antes → después de una propiedad, o qué trae un nodo agregado.
static func scene_bbcode(change: Dictionary) -> String:
	var removed := AgentTheme.color_hex(AgentTheme.REMOVED)
	var added := AgentTheme.color_hex(AgentTheme.ADDED)
	if change.has("shown_before") or change.has("shown_after"):
		return "[color=%s]%s[/color] → [color=%s]%s[/color]" % [removed, _value(change.get("shown_before")), added, _value(change.get("shown_after"))]
	if change.get("kind") in ["added", "removed"]:
		var type := MarkdownBBCode.escape(str(change.get("type", "")))
		var children := int(change.get("children", 0))
		var below := "" if children == 0 else " · " + (I18n.t("with 1 node below") if children == 1 else I18n.t("with %d nodes below") % children)
		return "[color=%s]%s%s[/color]" % [added if change.kind == "added" else removed, type, below]
	return ""


static func _value(value: Variant) -> String:
	if value == null:
		return "[i]%s[/i]" % I18n.t("default")
	var text := str(value).replace("\n", " ")
	if text.length() > MAX_VALUE:
		text = text.substr(0, MAX_VALUE) + "…"
	return MarkdownBBCode.escape(text)


## Sin las líneas de contexto vacías del principio y del final (solo para mostrar; el parche las usa).
static func _trim_blank_context(lines: PackedStringArray) -> PackedStringArray:
	var first := 0
	var last := lines.size() - 1
	while first <= last and lines[first].strip_edges().is_empty():
		first += 1
	while last >= first and lines[last].strip_edges().is_empty():
		last -= 1
	return lines.slice(first, last + 1)


## Las líneas de un trozo en BBCode, hasta HUNK_MAX_LINES.
static func hunk_bbcode(hunk: Dictionary) -> String:
	var lines: PackedStringArray = []
	var all: PackedStringArray = _trim_blank_context(hunk.lines)
	for i in mini(all.size(), HUNK_MAX_LINES):
		var line: String = all[i]
		var text := MarkdownBBCode.escape(line.substr(1))
		if line.begins_with("+"):
			lines.append("[bgcolor=#%s]+ %s[/bgcolor]" % [AgentTheme.ADDED_BG.to_html(true), text])
		elif line.begins_with("-"):
			lines.append("[bgcolor=#%s]− %s[/bgcolor]" % [AgentTheme.REMOVED_BG.to_html(true), text])
		elif line.begins_with("\\"):
			continue  # «\ No newline at end of file»
		else:
			lines.append("[color=#8a8f98]  %s[/color]" % text)
	if all.size() > HUNK_MAX_LINES:
		lines.append("[color=#8a8f98]%s[/color]" % (I18n.t("… %d more lines in «Diff»") % (all.size() - HUNK_MAX_LINES)))
	return "\n".join(lines)
