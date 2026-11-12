@tool
extends Node
## Los trozos del último turno en el Script Editor (m11-66, seguimiento de m11-34): en un gutter propio,
## una barra en las líneas que cambió cada trozo y, en su primera línea, ✓ y ✗ para conservarlo o
## rechazarlo sin abrir «Ver cambios». Clic en ✓ marca o desmarca; clic en ✗ lo rechaza o, si ya se
## rechazó, lo vuelve a aplicar. Todo pasa por TurnChanges, así que valen sus mismas reglas: un trozo
## cuyas líneas cambiaron después no se toca, ni un archivo con cambios sin guardar o que otra sesión
## edita. Lo que pasa se lee en una banda en la barra de estado del editor de código.
##
## Las posiciones salen del texto del final del turno llevado al texto actual del editor (LineDiff), así
## siguen bien si el usuario escribió arriba. Un trozo rechazado ya no tiene líneas: su ✗ queda donde
## estaba. Solo la pestaña activa y solo archivos del proyecto abierto (no los de una copia aparte).

const TurnChanges := preload("../ui/turn_changes.gd")
const TurnSnapshots := preload("../session/turn_snapshots.gd")
const LineDiff := preload("../core/line_diff.gd")
const AgentTheme := preload("../ui/agent_theme.gd")
const I18n := preload("../core/i18n.gd")

const GUTTER_NAME := "godot_agent_turn"
const BAND_NAME := "GodotAgentTurnBand"
const BAR_WIDTH := 3
const LINE_ALPHA := 0.07

var turn_changes: TurnChanges
## () -> Dictionary: lo que cambió el último turno de la pestaña activa (SessionController.last_turn_changes), o {}.
var data_provider: Callable
var _accent: Color = Color("#f0a640")
## CodeEdit -> {path, rel, data, items, end_text, lines: {línea 0-based: {index, first}}, generation,
## band, message, glyph_x: [inicio del ✓, inicio del ✗, fin]}
var _editors: Dictionary = {}


func setup(changes: TurnChanges, provider: Callable, accent: Color) -> void:
	turn_changes = changes
	data_provider = provider
	_accent = accent


func _ready() -> void:
	turn_changes.hunks_changed.connect(_on_hunks_changed)
	EditorInterface.get_script_editor().editor_script_changed.connect(_on_editor_script_changed)
	_attach_current.call_deferred()


func _exit_tree() -> void:
	var script_editor := EditorInterface.get_script_editor()
	if script_editor.editor_script_changed.is_connected(_on_editor_script_changed):
		script_editor.editor_script_changed.disconnect(_on_editor_script_changed)
	if turn_changes and turn_changes.hunks_changed.is_connected(_on_hunks_changed):
		turn_changes.hunks_changed.disconnect(_on_hunks_changed)
	for code_edit: Variant in _editors.keys():
		if is_instance_valid(code_edit):
			_detach(code_edit)
	_editors.clear()


## Otro turno terminó, cambió la pestaña activa o se tocaron trozos: se vuelven a leer.
func refresh() -> void:
	for code_edit: Variant in _editors.keys():
		if is_instance_valid(code_edit):
			_load(code_edit)
		else:
			_editors.erase(code_edit)
	_attach_current()


## Para los tests: el CodeEdit marcado que muestra `path`, sus líneas marcadas y la banda.
func editor_for(path: String) -> CodeEdit:
	for code_edit: Variant in _editors:
		if is_instance_valid(code_edit) and _editors[code_edit].path == path:
			return code_edit
	return null


func marked_lines(path: String) -> Dictionary:
	var code_edit := editor_for(path)
	return _editors[code_edit].lines if code_edit else {}


func band_text(path: String) -> String:
	var code_edit := editor_for(path)
	return (_editors[code_edit].band as Label).text if code_edit and (_editors[code_edit].band as Label).visible else ""


## Los trozos que se ven en `path`: [{index, state, stale, blocked, line (0-based de su ✓ ✗)}].
func hunks_shown(path: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var code_edit := editor_for(path)
	if code_edit == null:
		return result
	var state: Dictionary = _editors[code_edit]
	for line: int in state.lines:
		var mark: Dictionary = state.lines[line]
		if mark.first:
			var item: Dictionary = _item(state, int(mark.index))
			result.append({"index": item.index, "state": item.state, "stale": item.stale, "blocked": item.blocked, "line": line})
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.line < b.line)
	return result


## Lo mismo que un clic en el ✓ (`keep`) o el ✗ de un trozo. Devuelve "" o por qué no se pudo.
func act(path: String, index: int, keep: bool) -> String:
	var code_edit := editor_for(path)
	if code_edit == null:
		return "not shown"
	return await _act(code_edit, index, keep)


func _on_editor_script_changed(_script: Script) -> void:
	_attach_current.call_deferred()


func _on_hunks_changed(_data: Dictionary, path: String) -> void:
	for code_edit: Variant in _editors.keys():
		if is_instance_valid(code_edit) and _editors[code_edit].rel == path:
			_load(code_edit)


func _attach_current() -> void:
	var script_editor := EditorInterface.get_script_editor()
	var current := script_editor.get_current_editor()
	var script := script_editor.get_current_script()
	if current == null or script == null:
		return
	var code_edit := current.get_base_editor() as CodeEdit
	if code_edit == null:
		return
	var fresh := not _editors.has(code_edit)
	if fresh:
		_attach(code_edit)
	if fresh or _editors[code_edit].path != script.resource_path:
		_editors[code_edit].path = script.resource_path
		_load(code_edit)


func _attach(code_edit: CodeEdit) -> void:
	var gutter := code_edit.get_gutter_count()
	code_edit.add_gutter()
	code_edit.set_gutter_name(gutter, GUTTER_NAME)
	code_edit.set_gutter_type(gutter, TextEdit.GUTTER_TYPE_CUSTOM)
	code_edit.set_gutter_width(gutter, AgentTheme.px(30))
	code_edit.set_gutter_clickable(gutter, true)
	code_edit.set_gutter_custom_draw(gutter, _draw_gutter.bind(code_edit))
	code_edit.gutter_clicked.connect(_on_gutter_clicked.bind(code_edit))
	code_edit.text_changed.connect(_on_text_changed.bind(code_edit))
	var band := Label.new()
	band.name = BAND_NAME
	band.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	band.visible = false
	band.add_theme_color_override(&"font_color", _accent.lightened(0.35))
	band.add_theme_font_size_override(&"font_size", AgentTheme.px(11))
	var status_bar := _status_bar(code_edit)
	if status_bar:
		status_bar.add_child(band)
		status_bar.move_child(band, mini(1, status_bar.get_child_count() - 1))
	else:
		code_edit.add_child(band)
	_editors[code_edit] = {"path": "", "rel": "", "data": {}, "items": [], "end_text": "", "lines": {}, "generation": 0,
		"band": band, "message": "", "glyph_x": [], "place_queued": false}


## Barra de estado de CodeTextEditor: el HBoxContainer hermano que sigue al CodeEdit (4.6–4.8).
static func _status_bar(code_edit: CodeEdit) -> HBoxContainer:
	var parent := code_edit.get_parent()
	if parent == null:
		return null
	for i in range(code_edit.get_index() + 1, parent.get_child_count()):
		if parent.get_child(i) is HBoxContainer:
			return parent.get_child(i)
	return null


func _detach(code_edit: CodeEdit) -> void:
	for i in range(code_edit.get_gutter_count() - 1, -1, -1):
		if code_edit.get_gutter_name(i) == GUTTER_NAME:
			code_edit.remove_gutter(i)
	for connection: Dictionary in code_edit.gutter_clicked.get_connections() + code_edit.text_changed.get_connections():
		var callable: Callable = connection.callable
		if callable.get_object() == self:
			(connection.signal as Signal).disconnect(callable)
	var band: Variant = _editors[code_edit].band
	if is_instance_valid(band):
		(band as Node).queue_free()
	code_edit.queue_redraw()


## Lee los trozos del archivo en el último turno (git) y los ubica.
func _load(code_edit: CodeEdit) -> void:
	var state: Dictionary = _editors[code_edit]
	state.generation = int(state.generation) + 1
	var generation: int = state.generation
	var data: Dictionary = data_provider.call() if data_provider.is_valid() else {}
	var rel := _relative(data, str(state.path))
	if rel.is_empty():
		_clear(code_edit)
		return
	var session := str(data.get("session", turn_changes.primary_session))
	var snapshots: TurnSnapshots = turn_changes._snapshots_of(session)
	var items: Array[Dictionary] = await turn_changes.file_hunks(data, rel)
	var end_text := await snapshots.text_at(str(data.end), rel) if not items.is_empty() else ""
	if not is_instance_valid(code_edit) or not _editors.has(code_edit) or int(state.generation) != generation:
		return
	state.data = data
	state.rel = rel
	state.items = items
	state.end_text = end_text
	_place(code_edit)


## La ruta relativa del script si el turno lo cambió y es del proyecto abierto; "" si no hay nada que marcar.
func _relative(data: Dictionary, res_path: String) -> String:
	if data.is_empty() or str(data.get("end", "")).is_empty() or not res_path.begins_with("res://") or turn_changes == null:
		return ""
	var session := str(data.get("session", turn_changes.primary_session))
	if turn_changes._snapshots_of(session) != turn_changes.project_snapshots or turn_changes.project_snapshots == null:
		return ""
	var rel := res_path.trim_prefix("res://")
	if TurnChanges.is_scene(rel):
		return ""
	for file: Dictionary in data.get("files", []):
		if str(file.get("path", "")) == rel:
			return rel
	return ""


func _clear(code_edit: CodeEdit) -> void:
	var state: Dictionary = _editors[code_edit]
	state.items = []
	state.lines = {}
	state.rel = ""
	state.message = ""
	(state.band as Label).visible = false
	code_edit.queue_redraw()


func _on_text_changed(code_edit: CodeEdit) -> void:
	var state: Dictionary = _editors.get(code_edit, {})
	if state.is_empty() or (state.items as Array).is_empty() or state.place_queued:
		return
	state.place_queued = true
	_place_later.call_deferred(code_edit)


func _place_later(code_edit: CodeEdit) -> void:
	if is_instance_valid(code_edit) and _editors.has(code_edit):
		_editors[code_edit].place_queued = false
		_place(code_edit)


## Ubica cada trozo en el texto actual del editor: sus líneas del final del turno, llevadas al texto de
## ahora; uno rechazado, o uno que solo borró, en la línea donde estaba.
func _place(code_edit: CodeEdit) -> void:
	var state: Dictionary = _editors[code_edit]
	var mapping := line_mapping(str(state.end_text), code_edit.text)
	var lines := {}
	for item: Dictionary in state.items:
		var changed := TurnSnapshots.changed_lines(item.hunk)
		var shown: Array[int] = []
		if item.state != TurnChanges.REJECTED:
			for end_line: int in range(int(changed.new_first), int(changed.new_last) + 1):
				if mapping.has(end_line):
					shown.append(int(mapping[end_line]) - 1)
		if shown.is_empty():
			shown.append(anchor_line(mapping, int(changed.new_first)) - 1)
		var first := true
		for line: int in shown:
			if line < 0 or line >= code_edit.get_line_count() or lines.has(line):
				continue
			lines[line] = {"index": int(item.index), "first": first}
			first = false
	state.lines = lines
	_update_band(code_edit)
	code_edit.queue_redraw()


## Línea del texto del final del turno (1-based) → línea del texto actual, para las que siguen iguales.
static func line_mapping(end_text: String, current: String) -> Dictionary:
	var mapping := {}
	var old_line := 0
	for op: Dictionary in LineDiff.diff(end_text, current):
		match int(op.kind):
			LineDiff.EQUAL:
				old_line += 1
				mapping[old_line] = int(op.new_line)
			LineDiff.REMOVE:
				old_line += 1
	return mapping


## Dónde quedaría hoy la línea `end_line` del final del turno si ya no está: debajo de la última línea
## anterior que sigue igual.
static func anchor_line(mapping: Dictionary, end_line: int) -> int:
	for line: int in range(end_line - 1, 0, -1):
		if mapping.has(line):
			return int(mapping[line]) + 1
	return 1


func _item(state: Dictionary, index: int) -> Dictionary:
	for item: Dictionary in state.items:
		if int(item.index) == index:
			return item
	return {}


func _update_band(code_edit: CodeEdit) -> void:
	var state: Dictionary = _editors[code_edit]
	var band: Label = state.band
	var items: Array = state.items
	band.visible = not items.is_empty()
	if items.is_empty():
		return
	var counts := {"": 0, TurnChanges.KEPT: 0, TurnChanges.REJECTED: 0}
	for item: Dictionary in items:
		counts[str(item.state)] = int(counts.get(str(item.state), 0)) + 1
	var text := "◆  " + I18n.t("Agent's last turn: %d to review · %d kept · %d rejected · ✓ keep, ✗ reject") % [counts[""], counts[TurnChanges.KEPT], counts[TurnChanges.REJECTED]]
	if not str(state.message).is_empty():
		text += "  —  " + str(state.message)
	band.text = text
	band.tooltip_text = text
	if band.get_parent() == code_edit:
		band.reset_size()
		band.position = Vector2(code_edit.size.x - band.size.x - AgentTheme.px(24), AgentTheme.px(4))


func _draw_gutter(line: int, _gutter: int, rect: Rect2, code_edit: CodeEdit) -> void:
	var state: Variant = _editors.get(code_edit)
	if state == null or not (state.lines as Dictionary).has(line):
		return
	var mark: Dictionary = state.lines[line]
	var item := _item(state, int(mark.index))
	if item.is_empty():
		return
	var color := mark_color(item)
	var text_left := rect.end.x
	if item.state != TurnChanges.REJECTED:
		code_edit.draw_rect(Rect2(text_left, rect.position.y, code_edit.size.x - text_left, rect.size.y), Color(color, LINE_ALPHA))
	code_edit.draw_rect(Rect2(rect.end.x - AgentTheme.px(BAR_WIDTH), rect.position.y, AgentTheme.px(BAR_WIDTH), rect.size.y), color)
	if not mark.first:
		return
	var font := code_edit.get_theme_font(&"font")
	var font_size := code_edit.get_theme_font_size(&"font_size")
	var half := (rect.size.x - AgentTheme.px(BAR_WIDTH)) / 2.0
	state.glyph_x = [rect.position.x, rect.position.x + half, rect.position.x + half * 2.0]
	var baseline := rect.position.y + (rect.size.y + font.get_ascent(font_size) - font.get_descent(font_size)) / 2.0
	var kept: bool = item.state == TurnChanges.KEPT
	var rejected: bool = item.state == TurnChanges.REJECTED
	var can_touch: bool = not item.stale and str(item.blocked).is_empty()
	var keep_color := AgentTheme.ADDED if kept else Color(AgentTheme.MUTED, 0.9)
	var reject_color := AgentTheme.REMOVED if rejected else (Color(AgentTheme.MUTED, 0.9) if can_touch else Color(AgentTheme.MUTED, 0.35))
	if not rejected:
		code_edit.draw_string(font, Vector2(rect.position.x, baseline), "✓", HORIZONTAL_ALIGNMENT_CENTER, half, font_size, keep_color)
	code_edit.draw_string(font, Vector2(rect.position.x + half, baseline), "✗", HORIZONTAL_ALIGNMENT_CENTER, half, font_size, reject_color)


## El color de la barra: por revisar en el acento, conservado verde, rechazado rojo, cambiado después gris.
func mark_color(item: Dictionary) -> Color:
	if item.state == TurnChanges.KEPT:
		return AgentTheme.ADDED
	if item.state == TurnChanges.REJECTED:
		return AgentTheme.REMOVED
	return AgentTheme.MUTED if item.stale else _accent


func _on_gutter_clicked(line: int, gutter: int, code_edit: CodeEdit) -> void:
	if code_edit.get_gutter_name(gutter) != GUTTER_NAME:
		return
	var state: Dictionary = _editors[code_edit]
	var mark: Variant = (state.lines as Dictionary).get(line)
	if mark == null or not mark.first:
		return
	var x := code_edit.get_local_mouse_position().x
	var glyphs: Array = state.glyph_x
	var keep := glyphs.size() == 3 and x < float(glyphs[1])
	if _item(state, int(mark.index)).state == TurnChanges.REJECTED:
		keep = false  # sin ✓: el ✗ ocupa el lugar
	_act(code_edit, int(mark.index), keep)


func _act(code_edit: CodeEdit, index: int, keep: bool) -> String:
	var state: Dictionary = _editors[code_edit]
	var item := _item(state, index)
	if item.is_empty():
		return "no such change"
	var data: Dictionary = state.data
	var rel: String = state.rel
	var error := ""
	if keep:
		turn_changes.keep_hunk(data, rel, index, item.state != TurnChanges.KEPT)
	elif item.state == TurnChanges.REJECTED:
		error = await turn_changes.reject_hunk(data, rel, index, true)
	elif item.stale:
		error = I18n.t("Those lines changed after the turn: use «Go back» for the whole file.")
	elif not str(item.blocked).is_empty():
		error = str(item.blocked)
	else:
		error = await turn_changes.reject_hunk(data, rel, index)
	if is_instance_valid(code_edit) and _editors.has(code_edit):
		_editors[code_edit].message = error
		_update_band(code_edit)
	return error
