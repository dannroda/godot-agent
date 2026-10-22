@tool
extends VBoxContainer
## Pantalla principal "Agent" para One-shot (spec §9.2, §10.1; docs/design pantalla 2):
## - sin One-shot en curso: formulario con objetivo, presupuestos y checkpoints;
## - en curso: barra superior (objetivo, fase, presupuestos con barras, regla de cuota, cuenta
##   regresiva, Pausar/Detener), banner de cuota, columnas Plan · Actividad · Playtest/
##   Verificaciones/Checkpoints y barra inferior con el resumen de cambios.
## Solo lee el estado de OneShotRun y llama a sus métodos públicos.

signal diff_requested(title: String, old_label: String, old_text: String, new_label: String, new_text: String)

const OneShotRun := preload("../../oneshot/oneshot_run.gd")
const QuotaMonitor := preload("../../core/quota_monitor.gd")
const AgentTheme := preload("../agent_theme.gd")
const MarkdownBBCode := preload("../markdown/markdown_bbcode.gd")
const RunReport := preload("../../oneshot/run_report.gd")

const BUDGET_KEYS: PackedStringArray = [OneShotRun.BUDGET_TIME, OneShotRun.BUDGET_TOKENS, OneShotRun.BUDGET_PLAYTESTS]
const ACTIVITY_COLORS: Dictionary = {
	"tool": Color("#b493ff"),
	"playtest": Color("#7fd98b"),
	"checkpoint": Color("#6cb4ff"),
	"cuota": Color("#f2d16b"),
	"presupuesto": Color("#f5c26b"),
	"aviso": Color("#ff7a7a"),
	"loop": Color("#ff9f5a"),
}
const SUMMARY_INTERVAL_S := 2.0
const SCENE_EXTENSIONS: PackedStringArray = ["tscn", "scn"]
const SCRIPT_EXTENSIONS: PackedStringArray = ["gd", "cs", "gdshader"]

var _run: OneShotRun
var _accent: Color = Color("#f0a85a")
## Valores iniciales del formulario: {time, tokens, playtests, checkpoints}.
var _defaults: Dictionary = {}
## Se vuelve al formulario aunque el One-shot anterior haya terminado.
var _show_form: bool = true

var _banner: PanelContainer
var _banner_label: Label
# Formulario
var _form: Control
var _goal_edit: TextEdit
var _budget_spins: Dictionary = {}
var _checkpoints_check: CheckBox
var _form_rule: Label
var _start_button: Button
# Vista del One-shot
var _run_view: Control
var _phase_label: Label
var _goal_label: Label
var _quota_row: Dictionary = {}
var _budget_rows: Dictionary = {}
var _rule_label: Label
var _countdown_label: Label
var _pause_button: Button
var _stop_button: Button
var _new_button: Button
var _plan_list: VBoxContainer
var _plan_edit: TextEdit
var _plan_edit_bar: HBoxContainer
var _plan_edit_button: Button
var _activity_text: RichTextLabel
var _guide_edit: LineEdit
var _capture_rect: TextureRect
var _capture_caption: Label
var _checks_list: VBoxContainer
var _checkpoints_list: VBoxContainer
var _summary_label: Label
var _diffstat_label: RichTextLabel
var _review_button: Button
var _accept_button: Button
var _report_button: Button
var _report_dialog: AcceptDialog
var _report_text: RichTextLabel
# Diálogos
var _wip_dialog: ConfirmationDialog
var _no_git_dialog: ConfirmationDialog
var _restore_dialog: ConfirmationDialog
var _accept_dialog: ConfirmationDialog
var _changes_dialog: AcceptDialog
var _changes_list: ItemList
var _error_dialog: AcceptDialog

var _plan_signature: String = ""
var _checks_signature: String = ""
var _checkpoints_signature: String = ""
var _capture_shown: Image
var _pending_restore: Dictionary = {}
var _summary: Dictionary = {}
var _summary_dirty: bool = false
var _summary_running: bool = false
var _summary_timer: Timer


func setup(run: OneShotRun, accent: Color, defaults: Dictionary) -> void:
	_run = run
	_accent = accent
	_defaults = defaults


## Defaults nuevos desde Settings: se ven en el formulario de inicio (no cambian un run en curso).
func set_defaults(defaults: Dictionary) -> void:
	_defaults = defaults
	for key: String in _budget_spins:
		(_budget_spins[key] as SpinBox).value = float(_defaults.get(key, 0))
	if _checkpoints_check:
		_checkpoints_check.button_pressed = bool(_defaults.get("checkpoints", true))


func _ready() -> void:
	if _run == null:
		return
	for child: Node in get_children():
		child.queue_free()
	add_theme_constant_override(&"separation", 0)
	_build_banner()
	_build_form()
	_build_run_view()
	_build_dialogs()
	_summary_timer = Timer.new()
	_summary_timer.wait_time = SUMMARY_INTERVAL_S
	_summary_timer.autostart = true
	_summary_timer.timeout.connect(_on_summary_timer)
	add_child(_summary_timer)
	_run.changed.connect(_refresh)
	_run.activity_added.connect(_on_activity_added)
	_run.restored.connect(_on_restored)
	_run.quota.changed.connect(_refresh)
	_run.model.plan_changed.connect(func(_plan: Array) -> void: _refresh())
	visibility_changed.connect(func() -> void:
		if is_visible_in_tree():
			_summary_dirty = true
			_refresh())
	_refresh()


# --- construcción --------------------------------------------------------------------------------

func _build_banner() -> void:
	_banner = PanelContainer.new()
	_banner_label = Label.new()
	_banner_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_banner.add_child(_banner_label)
	add_child(_banner)


func _build_form() -> void:
	var center := CenterContainer.new()
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(center)
	_form = center
	var panel := PanelContainer.new()
	panel.custom_minimum_size.x = AgentTheme.px(640)
	panel.add_theme_stylebox_override(&"panel", AgentTheme.panel(AgentTheme.dark_color(), Color(1, 1, 1, 0.08), 8, 20))
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override(&"separation", AgentTheme.px(10))
	panel.add_child(box)
	var title := Label.new()
	title.text = "One-shot"
	title.add_theme_font_size_override(&"font_size", AgentTheme.px(20))
	box.add_child(title)
	var intro := Label.new()
	intro.text = "El agente arma un plan y lo ejecuta solo: después de cada tarea corre la escena, captura un frame y revisa los errores. Podés pausarlo, guiarlo o volver a un checkpoint en cualquier momento."
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	intro.add_theme_color_override(&"font_color", AgentTheme.MUTED)
	box.add_child(intro)
	box.add_child(_heading("Objetivo"))
	_goal_edit = TextEdit.new()
	_goal_edit.placeholder_text = "Ej.: Pong de 2 jugadores con puntaje, saque y reinicio. Usar los assets de res://assets y respetar CLAUDE.md."
	_goal_edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_goal_edit.custom_minimum_size.y = AgentTheme.px(110)
	_goal_edit.text_changed.connect(_refresh_form)
	box.add_child(_goal_edit)
	box.add_child(_heading("Presupuestos (0 = sin límite)"))
	var budgets := HBoxContainer.new()
	budgets.add_theme_constant_override(&"separation", AgentTheme.px(12))
	box.add_child(budgets)
	var specs: Array[Dictionary] = [
		{"key": OneShotRun.BUDGET_TIME, "label": "Tiempo", "suffix": "min", "max": 600, "step": 1},
		{"key": OneShotRun.BUDGET_TOKENS, "label": "Tokens", "suffix": "", "max": 20000000, "step": 10000},
		{"key": OneShotRun.BUDGET_PLAYTESTS, "label": "Playtests", "suffix": "", "max": 100, "step": 1},
	]
	for spec: Dictionary in specs:
		var column := VBoxContainer.new()
		column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var label := Label.new()
		label.text = spec.label
		label.add_theme_color_override(&"font_color", AgentTheme.MUTED)
		column.add_child(label)
		var spin := SpinBox.new()
		spin.max_value = spec.max
		spin.step = spec.step
		spin.suffix = spec.suffix
		spin.value = float(_defaults.get(spec.key, 0))
		spin.select_all_on_focus = true
		column.add_child(spin)
		budgets.add_child(column)
		_budget_spins[spec.key] = spin
	_checkpoints_check = CheckBox.new()
	_checkpoints_check.text = "Crear un checkpoint git antes de cada tarea (rama agent/<fecha>; nunca hace merge ni push)"
	_checkpoints_check.button_pressed = bool(_defaults.get("checkpoints", true))
	box.add_child(_checkpoints_check)
	_form_rule = Label.new()
	_form_rule.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_form_rule.add_theme_color_override(&"font_color", AgentTheme.MUTED)
	box.add_child(_form_rule)
	var actions := HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_END
	box.add_child(actions)
	_start_button = _accent_button("Iniciar One-shot")
	_start_button.pressed.connect(_on_start_pressed)
	actions.add_child(_start_button)


func _build_run_view() -> void:
	_run_view = VBoxContainer.new()
	_run_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_run_view.add_theme_constant_override(&"separation", 0)
	add_child(_run_view)
	_run_view.add_child(_build_top_bar())
	var columns := HBoxContainer.new()
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	columns.add_theme_constant_override(&"separation", 0)
	_run_view.add_child(columns)
	columns.add_child(_build_plan_column())
	columns.add_child(VSeparator.new())
	columns.add_child(_build_activity_column())
	columns.add_child(VSeparator.new())
	columns.add_child(_build_side_column())
	_run_view.add_child(_build_bottom_bar())


func _build_top_bar() -> Control:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override(&"panel", AgentTheme.panel(AgentTheme.dark_color(), Color.TRANSPARENT, 0, 12))
	var box := VBoxContainer.new()
	box.add_theme_constant_override(&"separation", AgentTheme.px(6))
	panel.add_child(box)

	var header := HBoxContainer.new()
	header.add_theme_constant_override(&"separation", AgentTheme.px(12))
	box.add_child(header)
	header.add_child(_heading("Objetivo · one-shot"))
	_phase_label = Label.new()
	_phase_label.add_theme_color_override(&"font_color", _accent)
	_phase_label.add_theme_font_size_override(&"font_size", AgentTheme.px(12))
	_phase_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(_phase_label)
	_pause_button = Button.new()
	_pause_button.pressed.connect(_on_pause_pressed)
	header.add_child(_pause_button)
	_stop_button = Button.new()
	_stop_button.text = "Detener"
	_stop_button.add_theme_color_override(&"font_color", AgentTheme.ERROR)
	_stop_button.pressed.connect(func() -> void: _run.stop())
	header.add_child(_stop_button)
	_new_button = _accent_button("Nuevo One-shot")
	_new_button.pressed.connect(func() -> void:
		_show_form = true
		_goal_edit.text = _run.goal
		_refresh())
	header.add_child(_new_button)

	_goal_label = Label.new()
	_goal_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_goal_label.max_lines_visible = 3
	_goal_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	box.add_child(_goal_label)

	# Cuota, tiempo, tokens y playtests: 4 columnas, o 2 si la pantalla es angosta.
	var bars := GridContainer.new()
	bars.columns = 4
	bars.add_theme_constant_override(&"h_separation", AgentTheme.px(16))
	bars.add_theme_constant_override(&"v_separation", AgentTheme.px(6))
	bars.resized.connect(func() -> void: bars.columns = 4 if bars.size.x >= AgentTheme.px(560) else 2)
	box.add_child(bars)
	_quota_row = _budget_bar(bars, "Cuota")
	for key: String in BUDGET_KEYS:
		_budget_rows[key] = _budget_bar(bars, OneShotRun.BUDGET_LABELS[key])
	var rule_row := HBoxContainer.new()
	rule_row.add_theme_constant_override(&"separation", AgentTheme.px(16))
	box.add_child(rule_row)
	_rule_label = Label.new()
	_rule_label.add_theme_color_override(&"font_color", AgentTheme.MUTED)
	_rule_label.add_theme_font_size_override(&"font_size", AgentTheme.px(11))
	rule_row.add_child(_rule_label)
	_countdown_label = Label.new()
	_countdown_label.add_theme_color_override(&"font_color", AgentTheme.WARNING)
	_countdown_label.add_theme_font_size_override(&"font_size", AgentTheme.px(12))
	_countdown_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_countdown_label.clip_text = true
	_countdown_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	rule_row.add_child(_countdown_label)
	return panel


func _build_plan_column() -> Control:
	var column := _column(1.0)
	var header := HBoxContainer.new()
	column.add_child(header)
	var title := _heading("Plan")
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	_plan_edit_button = Button.new()
	_plan_edit_button.text = "Editar"
	_plan_edit_button.flat = true
	_plan_edit_button.tooltip_text = "Editá el plan: el texto se manda al agente al terminar el turno actual."
	_plan_edit_button.pressed.connect(_on_plan_edit_pressed)
	header.add_child(_plan_edit_button)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	_plan_list = VBoxContainer.new()
	_plan_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_plan_list.add_theme_constant_override(&"separation", AgentTheme.px(2))
	scroll.add_child(_plan_list)
	_plan_edit = TextEdit.new()
	_plan_edit.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_plan_edit.visible = false
	column.add_child(_plan_edit)
	_plan_edit_bar = HBoxContainer.new()
	_plan_edit_bar.alignment = BoxContainer.ALIGNMENT_END
	_plan_edit_bar.visible = false
	column.add_child(_plan_edit_bar)
	var cancel := Button.new()
	cancel.text = "Cancelar"
	cancel.pressed.connect(func() -> void: _set_plan_editing(false))
	_plan_edit_bar.add_child(cancel)
	var send := _accent_button("Mandar al agente")
	send.pressed.connect(func() -> void:
		_run.edit_plan(_plan_edit.text.split("\n"))
		_set_plan_editing(false))
	_plan_edit_bar.add_child(send)
	var note := Label.new()
	note.text = "Podés editar el plan mientras corre: el agente lo relee al terminar el turno."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.add_theme_color_override(&"font_color", AgentTheme.MUTED)
	note.add_theme_font_size_override(&"font_size", AgentTheme.px(11))
	column.add_child(note)
	return column.get_parent()


func _build_activity_column() -> Control:
	var column := _column(1.4)
	column.add_child(_heading("Actividad"))
	_activity_text = RichTextLabel.new()
	_activity_text.bbcode_enabled = true
	_activity_text.scroll_following = true
	_activity_text.selection_enabled = true
	_activity_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_activity_text.add_theme_font_override(&"mono_font", AgentTheme.mono_font())
	column.add_child(_activity_text)
	var guide := HBoxContainer.new()
	column.add_child(guide)
	_guide_edit = LineEdit.new()
	_guide_edit.placeholder_text = "Guiar al agente…"
	_guide_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_guide_edit.tooltip_text = "Se manda como un mensaje más al terminar el turno actual."
	_guide_edit.text_submitted.connect(func(_text: String) -> void: _on_guide_pressed())
	guide.add_child(_guide_edit)
	var send := Button.new()
	send.text = "Enviar"
	send.pressed.connect(_on_guide_pressed)
	guide.add_child(send)
	return column.get_parent()


func _build_side_column() -> Control:
	var column := _column(1.0)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override(&"separation", AgentTheme.px(8))
	scroll.add_child(box)
	box.add_child(_heading("Último playtest"))
	_capture_rect = TextureRect.new()
	_capture_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_capture_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_capture_rect.custom_minimum_size.y = AgentTheme.px(170)
	box.add_child(_capture_rect)
	_capture_caption = Label.new()
	_capture_caption.add_theme_color_override(&"font_color", AgentTheme.MUTED)
	_capture_caption.add_theme_font_size_override(&"font_size", AgentTheme.px(11))
	box.add_child(_capture_caption)
	box.add_child(_heading("Verificaciones"))
	_checks_list = VBoxContainer.new()
	box.add_child(_checks_list)
	box.add_child(_heading("Checkpoints"))
	_checkpoints_list = VBoxContainer.new()
	box.add_child(_checkpoints_list)
	return column.get_parent()


func _build_bottom_bar() -> Control:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override(&"panel", AgentTheme.panel(AgentTheme.dark_color(), Color.TRANSPARENT, 0, 10))
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", AgentTheme.px(14))
	panel.add_child(row)
	_summary_label = Label.new()
	row.add_child(_summary_label)
	_diffstat_label = RichTextLabel.new()
	_diffstat_label.bbcode_enabled = true
	_diffstat_label.fit_content = true
	_diffstat_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	_diffstat_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_diffstat_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_diffstat_label)
	_review_button = Button.new()
	_review_button.text = "Revisar cambios"
	_review_button.pressed.connect(_on_review_pressed)
	row.add_child(_review_button)
	_report_button = Button.new()
	_report_button.text = "Informe"
	_report_button.tooltip_text = "Métricas del run: duración por tarea, tools, checks, permisos y eventos (D39)."
	_report_button.pressed.connect(_show_report)
	row.add_child(_report_button)
	_accept_button = _accent_button("Aceptar todo")
	_accept_button.pressed.connect(func() -> void:
		_accept_dialog.dialog_text = "Se hace un commit final en %s con todo lo que hizo el agente.\nEl harness nunca hace merge ni push: la rama queda lista para que la mergees vos." % _run.git.agent_branch
		_accept_dialog.popup_centered())
	row.add_child(_accept_button)
	return panel


func _build_dialogs() -> void:
	_wip_dialog = ConfirmationDialog.new()
	_wip_dialog.title = "Cambios sin commitear"
	_wip_dialog.dialog_text = "Hay cambios sin commitear en el proyecto.\nSe guardan en un commit «WIP antes del one-shot» en la rama nueva del agente; tu rama actual no se toca."
	_wip_dialog.ok_button_text = "Commitear como WIP y empezar"
	_wip_dialog.confirmed.connect(_start_run)
	add_child(_wip_dialog)
	_no_git_dialog = ConfirmationDialog.new()
	_no_git_dialog.title = "Sin checkpoints"
	_no_git_dialog.ok_button_text = "Seguir sin checkpoints"
	_no_git_dialog.confirmed.connect(func() -> void:
		_checkpoints_check.button_pressed = false
		_start_run())
	add_child(_no_git_dialog)
	_restore_dialog = ConfirmationDialog.new()
	_restore_dialog.title = "Volver a un checkpoint"
	_restore_dialog.ok_button_text = "Volver acá"
	_restore_dialog.confirmed.connect(_on_restore_confirmed)
	add_child(_restore_dialog)
	_accept_dialog = ConfirmationDialog.new()
	_accept_dialog.title = "Aceptar todo"
	_accept_dialog.ok_button_text = "Aceptar todo"
	_accept_dialog.confirmed.connect(_on_accept_confirmed)
	add_child(_accept_dialog)
	_changes_dialog = AcceptDialog.new()
	_changes_dialog.title = "Cambios del One-shot"
	_changes_dialog.ok_button_text = "Cerrar"
	_changes_dialog.min_size = Vector2i(AgentTheme.px(560), AgentTheme.px(380))
	_changes_dialog.exclusive = false  # el diff se abre encima
	var box := VBoxContainer.new()
	_changes_dialog.add_child(box)
	var hint := Label.new()
	hint.text = "Doble clic en un archivo para ver el diff contra el estado de antes del One-shot."
	hint.add_theme_color_override(&"font_color", AgentTheme.MUTED)
	box.add_child(hint)
	_changes_list = ItemList.new()
	_changes_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_changes_list.item_activated.connect(_on_change_activated)
	box.add_child(_changes_list)
	add_child(_changes_dialog)
	_error_dialog = AcceptDialog.new()
	_error_dialog.title = "One-shot"
	add_child(_error_dialog)
	_report_dialog = AcceptDialog.new()
	_report_dialog.title = "Informe del One-shot"
	_report_dialog.ok_button_text = "Cerrar"
	_report_dialog.min_size = Vector2i(AgentTheme.px(620), AgentTheme.px(480))
	_report_dialog.add_button("Copiar Markdown", false, "copy")
	_report_dialog.custom_action.connect(func(action: StringName) -> void:
		if action == &"copy":
			DisplayServer.clipboard_set(RunReport.to_markdown(_run.last_report)))
	_report_text = RichTextLabel.new()
	_report_text.bbcode_enabled = true
	_report_text.selection_enabled = true
	_report_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_report_dialog.add_child(_report_text)
	add_child(_report_dialog)


func _column(ratio: float) -> VBoxContainer:
	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.size_flags_stretch_ratio = ratio
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, AgentTheme.px(10))
	var column := VBoxContainer.new()
	column.add_theme_constant_override(&"separation", AgentTheme.px(6))
	margin.add_child(column)
	return column


func _heading(text: String) -> Label:
	var label := Label.new()
	label.text = text.to_upper()
	label.add_theme_font_size_override(&"font_size", AgentTheme.px(11))
	label.add_theme_color_override(&"font_color", Color(1, 1, 1, 0.66))
	return label


func _accent_button(text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.add_theme_stylebox_override(&"normal", AgentTheme.panel(_accent, Color.TRANSPARENT, 4, 6))
	button.add_theme_stylebox_override(&"hover", AgentTheme.panel(_accent.lightened(0.12), Color.TRANSPARENT, 4, 6))
	button.add_theme_stylebox_override(&"pressed", AgentTheme.panel(_accent.darkened(0.12), Color.TRANSPARENT, 4, 6))
	button.add_theme_stylebox_override(&"disabled", AgentTheme.panel(Color(_accent, 0.35), Color.TRANSPARENT, 4, 6))
	for state: StringName in [&"font_color", &"font_hover_color", &"font_pressed_color", &"font_focus_color"]:
		button.add_theme_color_override(state, Color("#1b1b1b"))
	return button


func _budget_bar(parent: Control, title: String) -> Dictionary:
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override(&"separation", AgentTheme.px(3))
	parent.add_child(box)
	var label := Label.new()
	label.add_theme_font_size_override(&"font_size", AgentTheme.px(12))
	label.clip_text = true
	box.add_child(label)
	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.max_value = 1.0
	bar.custom_minimum_size.y = AgentTheme.px(5)
	bar.add_theme_stylebox_override(&"background", AgentTheme.panel(Color(1, 1, 1, 0.08), Color.TRANSPARENT, 2, 0))
	box.add_child(bar)
	return {"title": title, "label": label, "bar": bar}


# --- refresco ------------------------------------------------------------------------------------

func _refresh() -> void:
	if _run == null or _form == null:
		return
	var in_form := _show_form and not _run.is_active()
	if _run.is_active():
		_show_form = false
	_form.visible = in_form
	_run_view.visible = not in_form
	_refresh_banner()
	if in_form:
		_refresh_form()
		return
	_refresh_top_bar()
	_refresh_plan()
	_refresh_side()
	_refresh_bottom_bar()


func _refresh_form() -> void:
	_form_rule.text = "Cuota del plan: " + _run.quota.rule_text().to_lower() if _run.quota.has_data() else "El agente todavía no informó la cuota del plan: el One-shot se pausa por cuota solo si la informa."
	_start_button.disabled = _goal_edit.text.strip_edges().is_empty() or _run.is_active()


func _refresh_banner() -> void:
	var quota := _run.quota
	var text := ""
	var color := AgentTheme.WARNING
	match quota.state:
		QuotaMonitor.State.WARNING:
			text = "Cuota del plan al %d %% · %s" % [roundi(quota.max_utilization() * 100.0), quota.rule_text().to_lower()]
		QuotaMonitor.State.PAUSE_SCHEDULED:
			text = quota.rule_text()
		QuotaMonitor.State.LIMITED:
			color = AgentTheme.ERROR
			var wait := quota.seconds_until_retry()
			text = "Límite del plan alcanzado · " + ("se puede volver a intentar en %s" % QuotaMonitor.format_duration(wait) if wait > 0 else "ya se puede reintentar")
	if text.is_empty() and _run.phase == OneShotRun.Phase.PAUSED and not _run.pause_note.is_empty():
		text = _run.pause_note
	if text.is_empty() and _run.recovered and _run.phase == OneShotRun.Phase.PAUSED:
		text = "El One-shot quedó a medias porque el editor se cerró. «Retomar» reabre la sesión del agente y sigue; «Detener» lo da por terminado."
	if text.is_empty() and _run.phase == OneShotRun.Phase.FINISHED and not _show_form:
		text = _run.finish_reason
		color = _accent
	_banner.visible = not text.is_empty()
	_banner_label.text = text
	_banner_label.add_theme_color_override(&"font_color", color)
	_banner.add_theme_stylebox_override(&"panel", AgentTheme.panel(Color(color, 0.12), Color(color, 0.5), 0, 8))


func _refresh_top_bar() -> void:
	var position := _run.plan_position()
	_phase_label.text = _run.phase_label() + (" · " + position if not position.is_empty() and _run.phase != OneShotRun.Phase.FINISHED else "")
	var phase_color := _accent
	match _run.phase:
		OneShotRun.Phase.LIMITED:
			phase_color = AgentTheme.ERROR
		OneShotRun.Phase.PAUSED, OneShotRun.Phase.PAUSED_QUOTA, OneShotRun.Phase.WAITING_CONFIRM:
			phase_color = AgentTheme.WARNING
	_phase_label.add_theme_color_override(&"font_color", phase_color)
	_goal_label.text = _run.goal
	_goal_label.tooltip_text = _run.goal

	var quota := _run.quota
	var window := quota.utilization(QuotaMonitor.WINDOW_CURRENT)
	if window >= 0.0:
		_set_bar(_quota_row, "%d %%" % roundi(window * 100.0), window, _quota_color(window))
		(_quota_row.label as Label).tooltip_text = quota.describe_window(QuotaMonitor.WINDOW_CURRENT)
	else:
		_set_bar(_quota_row, "—", 0.0, _accent)
		(_quota_row.label as Label).tooltip_text = "El agente no informa la cuota del plan."
	for key: String in BUDGET_KEYS:
		var ratio := _run.budget_ratio(key)
		var color := AgentTheme.ERROR if ratio >= 1.0 else (AgentTheme.WARNING if ratio >= OneShotRun.WARN_RATIO else _accent)
		_set_bar(_budget_rows[key], _budget_text(key), minf(ratio, 1.0), color)
	_rule_label.text = quota.rule_text()

	var countdown := ""
	var now := int(Time.get_unix_time_from_system())
	match _run.phase:
		OneShotRun.Phase.LIMITED:
			var wait := quota.seconds_until_retry()
			countdown = ("⏳ Se reinicia en %s" % QuotaMonitor.format_duration(wait)) if wait > 0 else "⏳ Reintentando…"
		OneShotRun.Phase.PAUSED_QUOTA:
			countdown = "⏸ Pausado por cuota antes de «%s»" % _run.resume_task
			if _run.quota_resume_at > now:
				countdown += " · retoma en %s" % QuotaMonitor.format_duration(_run.quota_resume_at - now)
		OneShotRun.Phase.WAITING_CONFIRM:
			countdown = "La cuota se liberó: tocá Retomar para seguir desde «%s»" % _run.resume_task
		OneShotRun.Phase.PAUSED:
			if not _run.resume_task.is_empty():
				countdown = "Retoma desde «%s»" % _run.resume_task
	_countdown_label.text = countdown
	_countdown_label.visible = not countdown.is_empty()

	var finished := _run.phase == OneShotRun.Phase.FINISHED
	_pause_button.visible = not finished
	_stop_button.visible = not finished
	_new_button.visible = finished
	var can_resume := _run.phase in [OneShotRun.Phase.PAUSED, OneShotRun.Phase.PAUSED_QUOTA, OneShotRun.Phase.LIMITED, OneShotRun.Phase.WAITING_CONFIRM]
	_pause_button.text = "Retomar" if can_resume else "Pausar"
	_pause_button.disabled = not (can_resume or _run.phase == OneShotRun.Phase.RUNNING)
	_pause_button.tooltip_text = "Reintenta ya, sin esperar el reinicio de la ventana." if _run.phase == OneShotRun.Phase.LIMITED else ""
	_stop_button.disabled = not _run.is_active()


func _refresh_plan() -> void:
	var plan: Array = _run.current_plan()
	var signature := JSON.stringify(plan) + ("|fin" if plan.is_empty() and _run.phase == OneShotRun.Phase.FINISHED else "")
	if signature == _plan_signature:
		return
	_plan_signature = signature
	_plan_edit_button.disabled = plan.is_empty()
	for child: Node in _plan_list.get_children():
		child.queue_free()
	if plan.is_empty():
		_plan_list.add_child(_muted_label("El agente no informó un plan: el avance sale de los playtests y las verificaciones." if _run.phase == OneShotRun.Phase.FINISHED else "El agente todavía no armó el plan."))
		return
	for entry: Variant in plan:
		if not entry is Dictionary:
			continue
		var status := str(entry.get("status", "pending"))
		var row := HBoxContainer.new()
		row.add_theme_constant_override(&"separation", AgentTheme.px(8))
		var icon := Label.new()
		icon.custom_minimum_size.x = AgentTheme.px(14)
		var text := Label.new()
		text.text = str(entry.get("content", ""))
		text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		match status:
			"completed":
				icon.text = "✓"
				icon.add_theme_color_override(&"font_color", AgentTheme.ADDED)
				text.add_theme_color_override(&"font_color", AgentTheme.MUTED)
			"in_progress":
				icon.text = "●"
				icon.add_theme_color_override(&"font_color", _accent)
				text.add_theme_color_override(&"font_color", _accent)
			_:
				icon.text = "○"
				icon.add_theme_color_override(&"font_color", AgentTheme.MUTED)
		row.add_child(icon)
		row.add_child(text)
		var holder := PanelContainer.new()
		holder.add_theme_stylebox_override(&"panel", AgentTheme.panel(Color(_accent, 0.1) if status == "in_progress" else Color.TRANSPARENT, Color.TRANSPARENT, 5, 6))
		holder.add_child(row)
		_plan_list.add_child(holder)


func _refresh_side() -> void:
	if _run.last_capture != _capture_shown:
		_capture_shown = _run.last_capture
		_capture_rect.texture = ImageTexture.create_from_image(_capture_shown) if _capture_shown else null
	_capture_caption.text = _run.last_capture_caption if _capture_shown else "Todavía no hay capturas."

	var signature := JSON.stringify(_run.checks)
	if signature != _checks_signature:
		_checks_signature = signature
		for child: Node in _checks_list.get_children():
			child.queue_free()
		if _run.checks.is_empty():
			_checks_list.add_child(_muted_label("El agente reporta las verificaciones al terminar cada tarea."))
		for check: Dictionary in _run.checks:
			var label := Label.new()
			label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			var mark := {"pass": "✓", "fail": "✗"}.get(check.status, "○") as String
			label.text = "%s  %s" % [mark, check.label]
			label.tooltip_text = str(check.get("detail", ""))
			label.add_theme_color_override(&"font_color", {"pass": AgentTheme.font_color(), "fail": AgentTheme.ERROR}.get(check.status, AgentTheme.MUTED))
			_checks_list.add_child(label)

	var checkpoints: Array = _run.git.checkpoints if _run.checkpoints_enabled else []
	signature = JSON.stringify(checkpoints) + str(_run.checkpoints_enabled)
	if signature != _checkpoints_signature:
		_checkpoints_signature = signature
		for child: Node in _checkpoints_list.get_children():
			child.queue_free()
		if not _run.checkpoints_enabled:
			_checkpoints_list.add_child(_muted_label("Checkpoints desactivados."))
		for i in range(checkpoints.size() - 1, -1, -1):
			var cp: Dictionary = checkpoints[i]
			var row := HBoxContainer.new()
			var name_label := Label.new()
			name_label.text = cp.name
			name_label.add_theme_font_override(&"font", AgentTheme.mono_font())
			name_label.add_theme_color_override(&"font_color", _accent)
			row.add_child(name_label)
			var label := Label.new()
			label.text = cp.label
			label.clip_text = true
			label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
			label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			label.tooltip_text = "%s · %s" % [cp.label, str(cp.sha).left(10)]
			row.add_child(label)
			var back := Button.new()
			back.text = "Volver acá"
			back.flat = true
			back.add_theme_color_override(&"font_color", Color("#6cb4ff"))
			back.pressed.connect(_on_restore_pressed.bind(cp))
			row.add_child(back)
			_checkpoints_list.add_child(row)


func _refresh_bottom_bar() -> void:
	_report_button.visible = not _run.last_report.is_empty() and _run.phase == OneShotRun.Phase.FINISHED and not _show_form
	var enabled := _run.checkpoints_enabled
	_review_button.disabled = not enabled or _summary.get("files", []).is_empty()
	_accept_button.disabled = not enabled or _run.phase == OneShotRun.Phase.PREPARING
	if not enabled:
		_summary_label.text = "Sin checkpoints: no hay resumen de cambios ni rama del agente."
		_diffstat_label.text = ""
		return
	var files: Array = _summary.get("files", [])
	var scenes := files.filter(func(file: Dictionary) -> bool: return str(file.path).get_extension() in SCENE_EXTENSIONS).size()
	var scripts := files.filter(func(file: Dictionary) -> bool: return str(file.path).get_extension() in SCRIPT_EXTENSIONS).size()
	_summary_label.text = "%d %s · %d %s · %d %s" % [files.size(), "archivo cambiado" if files.size() == 1 else "archivos cambiados", scenes, "escena" if scenes == 1 else "escenas", scripts, "script" if scripts == 1 else "scripts"]
	_diffstat_label.text = "[color=%s]+%d[/color]  [color=%s]−%d[/color]" % [AgentTheme.color_hex(AgentTheme.ADDED), int(_summary.get("added", 0)), AgentTheme.color_hex(AgentTheme.REMOVED), int(_summary.get("removed", 0))]


func _set_bar(row: Dictionary, value_text: String, ratio: float, color: Color) -> void:
	(row.label as Label).text = "%s  %s" % [row.title, value_text]
	var bar: ProgressBar = row.bar
	bar.value = ratio
	bar.add_theme_stylebox_override(&"fill", AgentTheme.panel(color, Color.TRANSPARENT, 2, 0))


func _budget_text(key: String) -> String:
	var limit := int(_run.budgets.get(key, 0))
	match key:
		OneShotRun.BUDGET_TIME:
			var minutes := int(float(_run.used[key]) / 60.0)
			return "%d / %s" % [minutes, "%d min" % limit if limit > 0 else "∞"]
		OneShotRun.BUDGET_TOKENS:
			return "%s / %s" % [format_tokens(int(_run.used[key])), format_tokens(limit) if limit > 0 else "∞"]
	return "%d / %s" % [int(_run.used[key]), str(limit) if limit > 0 else "∞"]


## 412k, 1,5M (como el mockup).
static func format_tokens(value: int) -> String:
	if value >= 1000000:
		return ("%.1fM" % (value / 1000000.0)).replace(".0M", "M").replace(".", ",")
	if value >= 1000:
		return "%dk" % roundi(value / 1000.0)
	return str(value)


func _quota_color(used: float) -> Color:
	var quota := _run.quota
	if quota.is_limited() or used >= 1.0:
		return AgentTheme.ERROR
	if quota.pause_enabled and used >= quota.pause_threshold:
		return AgentTheme.ERROR.lerp(AgentTheme.WARNING, 0.5)
	if used >= quota.warn_threshold:
		return AgentTheme.WARNING
	return _accent


func _muted_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_color_override(&"font_color", AgentTheme.MUTED)
	return label


# --- eventos -------------------------------------------------------------------------------------

func _on_start_pressed() -> void:
	if _goal_edit.text.strip_edges().is_empty() or _run.is_active():
		return
	_start_button.disabled = true
	var check: Dictionary = await _run.preflight(_checkpoints_check.button_pressed)
	_start_button.disabled = false
	if not str(check.warning).is_empty():
		# Sin git o sin commits no hay checkpoints: «Volver acá» no va a existir (D37).
		_no_git_dialog.dialog_text = "%s\n\nSin checkpoints no se puede volver atrás ni revisar los cambios del One-shot." % check.warning
		_no_git_dialog.popup_centered()
		return
	if check.needs_wip_confirm:
		_wip_dialog.popup_centered()
		return
	_start_run()


func _start_run() -> void:
	var budgets: Dictionary = {}
	for key: String in _budget_spins:
		budgets[key] = int((_budget_spins[key] as SpinBox).value)
	_activity_text.clear()
	_summary = {}
	_plan_signature = ""
	_checkpoints_signature = ""
	_checks_signature = ""
	_show_form = false
	var goal := _goal_edit.text
	var started: bool = await _run.start(goal, budgets, _checkpoints_check.button_pressed)
	if started:
		_goal_edit.text = ""
	_summary_dirty = true
	_refresh()


func _on_pause_pressed() -> void:
	if _run.phase == OneShotRun.Phase.RUNNING:
		_run.pause()
	else:
		_run.resume()


func _on_guide_pressed() -> void:
	var text := _guide_edit.text.strip_edges()
	if text.is_empty():
		return
	_guide_edit.text = ""
	_run.guide(text)


func _on_plan_edit_pressed() -> void:
	var lines: PackedStringArray = []
	for entry: Variant in _run.current_plan():
		if entry is Dictionary:
			lines.append(str(entry.get("content", "")))
	_plan_edit.text = "\n".join(lines)
	_set_plan_editing(true)


func _set_plan_editing(editing: bool) -> void:
	_plan_edit.visible = editing
	_plan_edit_bar.visible = editing
	(_plan_list.get_parent() as Control).visible = not editing
	_plan_edit_button.visible = not editing


## Un run cargado de disco: se rearma la actividad y se muestra la vista del run.
func _on_restored() -> void:
	_activity_text.clear()
	for entry: Dictionary in _run.activity:
		_on_activity_added(entry)
	_plan_signature = ""
	_checks_signature = ""
	_checkpoints_signature = ""
	_capture_shown = null
	_show_form = false
	_summary_dirty = true
	_refresh()


func _on_activity_added(entry: Dictionary) -> void:
	var color: Color = ACTIVITY_COLORS.get(entry.kind, AgentTheme.font_color())
	var text := str(entry.text).replace("[", "[lb]")
	_activity_text.append_text("[color=%s][code]%s[/code][/color]  [color=%s]%s[/color]  %s\n" % [
		AgentTheme.color_hex(AgentTheme.MUTED), entry.time, AgentTheme.color_hex(color), entry.kind, text])
	if entry.kind in ["checkpoint", "tool", "playtest", "estado", "agente"]:
		_summary_dirty = true


func _on_restore_pressed(cp: Dictionary) -> void:
	_pending_restore = cp
	_restore_dialog.dialog_text = "¿Volver a %s (%s)?\nLa carpeta del proyecto queda como en ese checkpoint (se descartan los cambios posteriores) y el One-shot queda pausado." % [cp.name, cp.label]
	_restore_dialog.popup_centered()


func _on_restore_confirmed() -> void:
	if _pending_restore.is_empty():
		return
	var error: String = await _run.restore(_pending_restore)
	_pending_restore = {}
	_summary_dirty = true
	if not error.is_empty():
		_show_error("No se pudo volver al checkpoint: " + error)


func _on_accept_confirmed() -> void:
	var error: String = await _run.accept_all()
	_summary_dirty = true
	if not error.is_empty():
		_show_error("No se pudo aceptar: " + error)


func _on_review_pressed() -> void:
	_changes_list.clear()
	for file: Dictionary in _summary.get("files", []):
		var index := _changes_list.add_item("+%d −%d   %s" % [file.added, file.removed, file.path])
		_changes_list.set_item_metadata(index, file.path)
	_changes_dialog.popup_centered()


func _on_change_activated(index: int) -> void:
	var path := str(_changes_list.get_item_metadata(index))
	var old_text: String = await _run.git.base_text(path)
	var full := _run.git.root.path_join(path)
	var new_text := FileAccess.get_file_as_string(full) if FileAccess.file_exists(full) else ""
	diff_requested.emit("One-shot: " + path, "antes del One-shot", old_text, "ahora", new_text)


func _on_summary_timer() -> void:
	if not _summary_dirty or _summary_running or not is_visible_in_tree() or _run == null or not _run.checkpoints_enabled or _run.is_git_busy():
		return
	_summary_dirty = false
	_summary_running = true
	var summary: Dictionary = await _run.changes_summary()
	_summary_running = false
	if not is_instance_valid(self):
		return
	_summary = summary
	_refresh()


func _show_error(text: String) -> void:
	_error_dialog.dialog_text = text
	_error_dialog.popup_centered()


func _show_report() -> void:
	if _run.last_report.is_empty():
		return
	_report_text.text = MarkdownBBCode.new().convert(RunReport.to_markdown(_run.last_report))
	_report_dialog.popup_centered()
