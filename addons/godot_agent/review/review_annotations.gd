@tool
extends Node
## Hallazgos de la revisión en el Script Editor (spec §9.4):
## - marca ● en un gutter propio y fondo de la línea según la severidad (se dibujan desde el gutter:
##   el Script Editor borra los colores de fondo de línea cada vez que valida el script);
## - tarjeta del hallazgo bajo la línea, al hacer clic en la marca o al elegirlo en el dock;
## - banda "Revisión del agente" en la barra de estado del editor de código (o arriba a la derecha).
## Las líneas son las del texto revisado; si el archivo cambia, se vuelve a revisar (D23).

signal action_requested(action: String, finding: Dictionary)

const ReviewStore := preload("review_store.gd")
const SessionModel := preload("../session/session_model.gd")
const AgentTheme := preload("../ui/agent_theme.gd")
const EditorContext := preload("../ui/editor_context.gd")

const ACTION_APPLY := "review_apply"
const ACTION_ASK := "review_ask"
const ACTION_DISMISS := "review_dismiss"
const GUTTER_NAME := "godot_agent_review"
const SEVERITY_ORDER: PackedStringArray = ["bug", "order", "perf", "style"]
const LINE_ALPHA := 0.13

var _store: ReviewStore
var _model: SessionModel
var _accent: Color = Color("#f0a640")
## CodeEdit -> {path, lines: {línea 0-based: Array de ids}, band: Label, card: PanelContainer, card_line: int}
var _editors: Dictionary = {}


func setup(store: ReviewStore, model: SessionModel, accent: Color) -> void:
	_store = store
	_model = model
	_accent = accent


func _ready() -> void:
	_store.changed.connect(refresh)
	_model.harness_mode_changed.connect(_on_harness_mode_changed)
	EditorInterface.get_script_editor().editor_script_changed.connect(_on_editor_script_changed)
	_attach_current.call_deferred()


func _exit_tree() -> void:
	var script_editor := EditorInterface.get_script_editor()
	if script_editor.editor_script_changed.is_connected(_on_editor_script_changed):
		script_editor.editor_script_changed.disconnect(_on_editor_script_changed)
	for code_edit: Variant in _editors.keys():
		if is_instance_valid(code_edit):
			_detach(code_edit)
	_editors.clear()


func refresh() -> void:
	for code_edit: Variant in _editors.keys():
		if is_instance_valid(code_edit):
			_apply(code_edit)
		else:
			_editors.erase(code_edit)
	_attach_current()


## Abre el script en la línea del hallazgo y muestra su tarjeta.
func focus_finding(id: int) -> bool:
	var finding := _store.get_finding(id)
	if finding.is_empty() or not EditorContext.open_location(str(finding.path), int(finding.line)):
		return false
	_show_card_when_open.call_deferred(str(finding.path), int(finding.line) - 1)
	return true


## CodeEdit anotado que muestra `path` (para los tests), o null.
func editor_for(path: String) -> CodeEdit:
	for code_edit: Variant in _editors:
		if is_instance_valid(code_edit) and _editors[code_edit].path == path:
			return code_edit
	return null


## Líneas anotadas (0-based) → ids, del editor que muestra `path`.
func annotated_lines(path: String) -> Dictionary:
	var code_edit := editor_for(path)
	return _editors[code_edit].lines if code_edit else {}


func band_for(path: String) -> Label:
	var code_edit := editor_for(path)
	return _editors[code_edit].band if code_edit else null


func card_for(path: String) -> PanelContainer:
	var code_edit := editor_for(path)
	return _editors[code_edit].card if code_edit else null


func _on_editor_script_changed(_script: Script) -> void:
	_attach_current.call_deferred()


func _on_harness_mode_changed(_mode: SessionModel.HarnessMode) -> void:
	refresh()


func _attach_current() -> void:
	var script_editor := EditorInterface.get_script_editor()
	var current := script_editor.get_current_editor()
	var script := script_editor.get_current_script()
	if current == null or script == null:
		return
	var code_edit := current.get_base_editor() as CodeEdit
	if code_edit == null:
		return
	if not _editors.has(code_edit):
		_attach(code_edit)
	_editors[code_edit].path = script.resource_path
	_apply(code_edit)


func _attach(code_edit: CodeEdit) -> void:
	var gutter := code_edit.get_gutter_count()
	code_edit.add_gutter()
	code_edit.set_gutter_name(gutter, GUTTER_NAME)
	code_edit.set_gutter_type(gutter, TextEdit.GUTTER_TYPE_CUSTOM)
	code_edit.set_gutter_width(gutter, AgentTheme.px(14))
	code_edit.set_gutter_clickable(gutter, true)
	code_edit.set_gutter_custom_draw(gutter, _draw_gutter.bind(code_edit))
	code_edit.gutter_clicked.connect(_on_gutter_clicked.bind(code_edit))
	code_edit.get_v_scroll_bar().value_changed.connect(_on_scrolled.bind(code_edit))
	code_edit.resized.connect(_layout.bind(code_edit))
	# Una tarjeta armada antes de que el CodeEdit acomode el texto ve la línea fuera de pantalla; si
	# después el scroll no cambia, ni `resized` ni `value_changed` la vuelven a ubicar. `draw` sí.
	code_edit.draw.connect(_layout.bind(code_edit))

	var band := Label.new()
	band.name = "GodotAgentReviewBand"
	band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	band.add_theme_color_override(&"font_color", _accent.lightened(0.35))
	band.add_theme_font_size_override(&"font_size", AgentTheme.px(11))
	var status_bar := _status_bar(code_edit)
	if status_bar:
		status_bar.add_child(band)
		status_bar.move_child(band, mini(1, status_bar.get_child_count() - 1))
	else:
		band.add_theme_stylebox_override(&"normal", AgentTheme.panel(Color(AgentTheme.dark_color(), 0.92), Color(_accent, 0.5), 4, 4))
		code_edit.add_child(band)
	var card := PanelContainer.new()
	card.name = "GodotAgentReviewCard"
	card.visible = false
	code_edit.add_child(card)
	_editors[code_edit] = {"path": "", "lines": {}, "band": band, "card": card, "card_line": -1, "card_layout": []}


## Barra de estado de CodeTextEditor: el HBoxContainer hermano que sigue al CodeEdit (4.4–4.8).
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
	for connection: Dictionary in code_edit.gutter_clicked.get_connections() + code_edit.resized.get_connections() + code_edit.draw.get_connections() + code_edit.get_v_scroll_bar().value_changed.get_connections():
		var callable: Callable = connection.callable
		if callable.get_object() == self:
			(connection.signal as Signal).disconnect(callable)
	var state: Dictionary = _editors[code_edit]
	for key: String in ["band", "card"]:
		if is_instance_valid(state[key]):
			(state[key] as Node).queue_free()
	code_edit.queue_redraw()


func _apply(code_edit: CodeEdit) -> void:
	var state: Dictionary = _editors[code_edit]
	var lines: Dictionary = {}
	var findings := _store.for_path(state.path)
	for finding: Dictionary in findings:
		var line := int(finding.line) - 1
		if line >= 0 and line < code_edit.get_line_count():
			if not lines.has(line):
				lines[line] = []
			(lines[line] as Array).append(int(finding.id))
	state.lines = lines
	var band: Label = state.band
	band.visible = not findings.is_empty()
	band.text = "●  Revisión del agente%s · %d hallazgo%s" % [
		" · solo lectura" if _model.harness_mode == SessionModel.HarnessMode.REVIEW else "",
		findings.size(), "" if findings.size() == 1 else "s"]
	if int(state.card_line) >= 0:
		if lines.has(state.card_line):
			_build_card(code_edit, state.card_line)
		else:
			_hide_card(code_edit)
	code_edit.queue_redraw()
	_layout(code_edit)


func _draw_gutter(line: int, _gutter: int, rect: Rect2, code_edit: CodeEdit) -> void:
	var state: Variant = _editors.get(code_edit)
	if state == null or not (state.lines as Dictionary).has(line):
		return
	var color: Color = AgentTheme.SEVERITY_COLORS[_top_severity(state.lines[line])]
	var text_left := rect.end.x
	code_edit.draw_rect(Rect2(text_left, rect.position.y, code_edit.size.x - text_left, rect.size.y), Color(color, LINE_ALPHA))
	code_edit.draw_circle(rect.get_center(), minf(rect.size.x, rect.size.y) * 0.26, color)


func _top_severity(ids: Array) -> String:
	var best := SEVERITY_ORDER.size() - 1
	for id: int in ids:
		best = mini(best, maxi(SEVERITY_ORDER.find(str(_store.get_finding(id).get("severity", "style"))), 0))
	return SEVERITY_ORDER[best]


func _on_gutter_clicked(line: int, gutter: int, code_edit: CodeEdit) -> void:
	if code_edit.get_gutter_name(gutter) != GUTTER_NAME or not (_editors[code_edit].lines as Dictionary).has(line):
		return
	if int(_editors[code_edit].card_line) == line:
		_hide_card(code_edit)
	else:
		_build_card(code_edit, line)


func _show_card_when_open(path: String, line: int) -> void:
	_attach_current()
	var code_edit := editor_for(path)
	if code_edit and (_editors[code_edit].lines as Dictionary).has(line):
		_build_card(code_edit, line)


func _hide_card(code_edit: CodeEdit) -> void:
	var state: Dictionary = _editors[code_edit]
	state.card_line = -1
	state.card_layout = []
	(state.card as Control).visible = false


func _build_card(code_edit: CodeEdit, line: int) -> void:
	var state: Dictionary = _editors[code_edit]
	var card: PanelContainer = state.card
	state.card_layout = []
	for child: Node in card.get_children():
		card.remove_child(child)
		child.queue_free()
	var ids: Array = state.lines[line]
	var severity := _top_severity(ids)
	card.add_theme_stylebox_override(&"panel", AgentTheme.panel(AgentTheme.SEVERITY_BG[severity], Color(AgentTheme.SEVERITY_COLORS[severity], 0.6), 6, 10))
	var column := VBoxContainer.new()
	column.add_theme_constant_override(&"separation", AgentTheme.px(6))
	card.add_child(column)
	for id: int in ids:
		var finding := _store.get_finding(id)
		if not finding.is_empty():
			column.add_child(_finding_view(finding, code_edit))
	state.card_line = line
	card.visible = true
	_layout(code_edit)


func _finding_view(finding: Dictionary, code_edit: CodeEdit) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override(&"separation", AgentTheme.px(4))
	var header := HBoxContainer.new()
	var tag := Label.new()
	tag.text = ReviewStore.SEVERITY_SHORT.get(finding.severity, "?")
	tag.add_theme_font_size_override(&"font_size", AgentTheme.px(10))
	tag.add_theme_color_override(&"font_color", AgentTheme.SEVERITY_COLORS[finding.severity].lightened(0.4))
	tag.add_theme_stylebox_override(&"normal", AgentTheme.panel(Color(AgentTheme.SEVERITY_COLORS[finding.severity], 0.3), Color.TRANSPARENT, 3, 2))
	header.add_child(tag)
	var title := Label.new()
	title.text = finding.title
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	header.add_child(title)
	var close := Button.new()
	close.flat = true
	close.icon = AgentTheme.icon(&"Close")
	close.text = "" if close.icon else "✕"
	close.tooltip_text = "Cerrar"
	close.pressed.connect(_hide_card.bind(code_edit))
	header.add_child(close)
	box.add_child(header)
	if not str(finding.body).is_empty():
		var body := Label.new()
		body.text = finding.body
		body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		body.add_theme_color_override(&"font_color", AgentTheme.font_color().darkened(0.1))
		box.add_child(body)
	if not str(finding.suggestion).is_empty():
		var suggestion := Label.new()
		suggestion.text = finding.suggestion
		suggestion.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
		suggestion.add_theme_font_override(&"font", AgentTheme.mono_font())
		suggestion.add_theme_font_size_override(&"font_size", AgentTheme.mono_font_size())
		suggestion.add_theme_color_override(&"font_color", AgentTheme.ADDED)
		suggestion.add_theme_stylebox_override(&"normal", AgentTheme.panel(Color(0, 0, 0, 0.3), Color.TRANSPARENT, 4, 6))
		box.add_child(suggestion)
	var actions := HBoxContainer.new()
	var apply := _action_button("Aplicar arreglo", ACTION_APPLY, finding)
	apply.add_theme_color_override(&"font_color", _accent)
	apply.tooltip_text = "Pasa a modo Construir y le pide al agente este arreglo"
	actions.add_child(apply)
	actions.add_child(_action_button("Preguntar", ACTION_ASK, finding))
	actions.add_child(_action_button("Descartar", ACTION_DISMISS, finding))
	box.add_child(actions)
	return box


func _action_button(label: String, action: String, finding: Dictionary) -> Button:
	var button := Button.new()
	button.text = label
	button.pressed.connect(func() -> void: action_requested.emit(action, finding))
	return button


func _on_scrolled(_value: float, code_edit: CodeEdit) -> void:
	_layout(code_edit)


func _layout(code_edit: CodeEdit) -> void:
	var state: Variant = _editors.get(code_edit)
	if state == null:
		return
	var scroll_width := code_edit.get_v_scroll_bar().size.x if code_edit.get_v_scroll_bar().visible else 0.0
	var band: Label = state.band
	if band.visible and band.get_parent() == code_edit:
		band.reset_size()
		band.position = Vector2(code_edit.size.x - band.size.x - scroll_width - AgentTheme.px(8), AgentTheme.px(4))
	var card: PanelContainer = state.card
	if int(state.card_line) < 0:
		return
	var rect := code_edit.get_rect_at_line_column(state.card_line, 0)
	var on_screen := rect.position.y >= 0 and rect.end.y < code_edit.size.y
	# Desde `draw` se llama en cada redibujo: sin cambios, no se toca nada.
	var layout_key: Array = [state.card_line, rect, code_edit.size, scroll_width, card.get_child_count()]
	if card.visible == on_screen and state.card_layout == layout_key:
		return
	state.card_layout = layout_key
	card.visible = on_screen
	if on_screen:
		var left := float(rect.position.x)
		var width := maxf(code_edit.size.x - left - scroll_width - AgentTheme.px(12), AgentTheme.px(200))
		card.custom_minimum_size = Vector2(width, 0)
		card.reset_size()
		card.position = Vector2(left, rect.end.y + AgentTheme.px(2))
		# Las etiquetas con autowrap recalculan su alto con el ancho final recién en el frame siguiente.
		card.reset_size.call_deferred()
