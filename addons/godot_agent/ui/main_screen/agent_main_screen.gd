@tool
extends VBoxContainer
## Pantalla principal "Agent" para One-shot (spec §9.2, §10.1; docs/design pantalla 2):
## - sin One-shot en curso: formulario con objetivo, presupuestos y checkpoints;
## - en curso: barra superior (objetivo, fase, presupuestos con barras, regla de cuota, cuenta
##   regresiva, Pausar/Detener), banner de cuota, columnas Plan · Actividad · Playtest/
##   Verificaciones/Checkpoints y barra inferior con el resumen de cambios.
## Solo lee el estado de OneShotRun y llama a sus métodos públicos.

signal diff_requested(title: String, old_label: String, old_text: String, new_label: String, new_text: String)
## «Configurar un agente…» del formulario: abrir Ajustes › Agentes.
signal settings_requested

const OneShotRun := preload("../../oneshot/oneshot_run.gd")
const QuotaMonitor := preload("../../core/quota_monitor.gd")
const AgentTheme := preload("../agent_theme.gd")
const MarkdownBBCode := preload("../markdown/markdown_bbcode.gd")
const ImageViewer := preload("../image_viewer.gd")
const RunReport := preload("../../oneshot/run_report.gd")
const I18n := preload("../../core/i18n.gd")

const BUDGET_KEYS: PackedStringArray = [OneShotRun.BUDGET_TIME, OneShotRun.BUDGET_TOKENS, OneShotRun.BUDGET_PLAYTESTS]
const ACTIVITY_COLORS: Dictionary = {
	"tool": Color("#b493ff"),
	"playtest": Color("#7fd98b"),
	"checkpoint": Color("#6cb4ff"),
	"quota": Color("#f2d16b"),
	"budget": Color("#f5c26b"),
	"warning": Color("#ff7a7a"),
	"loop": Color("#ff9f5a"),
	"spec": Color("#8fd3c7"),
	"guide": Color("#ffd479"),
	"turn": Color("#9aa7b8"),
	"qa": Color("#c49bff"),
}
## Tipo de entrada de la actividad (`kind`) -> cómo se muestra (traducido).
const ACTIVITY_KIND_LABELS: Dictionary = {
	"tool": "tool",  # i18n
	"playtest": "playtest",  # i18n
	"checkpoint": "checkpoint",  # i18n
	"quota": "quota",  # i18n
	"budget": "budget",  # i18n
	"warning": "warning",  # i18n
	"loop": "loop",  # i18n
	"spec": "spec",  # i18n
	"guide": "guide",  # i18n
	"turn": "turn",  # i18n
	"qa": "QA",  # i18n
	"session": "session",  # i18n
	"status": "status",  # i18n
	"agent": "agent",  # i18n
	"plan": "plan",  # i18n
}
const SUMMARY_INTERVAL_S := 2.0
const ACCOUNT_ALREADY_SWITCHED := 1000
## El formulario crece con la pantalla (m6-13): ancho y alto del objetivo, en px sin escalar.
const FORM_MIN_WIDTH := 640
## Ancho al que se achica el formulario cuando el centro es angosto.
const FORM_NARROW_WIDTH := 280
const FORM_MAX_WIDTH := 1400
const FORM_WIDTH_RATIO := 0.62
const GOAL_MIN_HEIGHT := 110
const GOAL_HEIGHT_RATIO := 0.4
## Dos columnas (m12-34): objetivo a la izquierda; agente, presupuestos y opciones a la derecha.
## Por debajo de este ancho del formulario se apilan.
const FORM_COLUMNS_MIN_WIDTH := 820
const SIDE_COLUMN_WIDTH := 320
const GOAL_EXAMPLES: PackedStringArray = [
	"2-player Pong with score, serve and restart",  # i18n
	"Top-down shooter: the player dodges and shoots waves of enemies",  # i18n
	"Platformer with three short levels, coins and a goal flag",  # i18n
]
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
var _spec_check: CheckBox
var _spec_button: Button
## Spec, progreso y QA del run (D41): el spec se edita, el resto se lee.
var _files_dialog: ConfirmationDialog
var _files_tabs: TabContainer
var _files_path_label: Label
var _spec_edit: TextEdit
var _files_paths: PackedStringArray = []
var _plan_title: Label
var _budgets_button: Button
## «Cambiar de cuenta» (m6-15): login con otra cuenta o «ya cambié», y retoma la misma sesión.
var _account_button: MenuButton
var _budgets_dialog: ConfirmationDialog
## clave de presupuesto -> SpinBox del diálogo
var _budgets_edit: Dictionary = {}
var _plan_note: Label
var _spec_view: RichTextLabel
var _spec_bar: HBoxContainer
var _spec_shown: String = ""
var _form_rule: Label
var _form_columns: BoxContainer
var _side_column: VBoxContainer
## Con qué agente corre el One-shot y, junto a «Iniciar», qué falta para arrancar (m12-33).
var _agent_label: Label
var _setup_agent_button: Button
var _start_hint: Label
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
## Tarea del plan -> Label con su duración; se actualiza en cada refresco sin rearmar la lista (m6-16).
var _plan_times: Dictionary = {}
var _checks_signature: String = ""
var _checkpoints_signature: String = ""
var _capture_shown: Image
var _pending_restore: Dictionary = {}
var _summary: Dictionary = {}
var _summary_dirty: bool = false
var _summary_running: bool = false
var _summary_timer: Timer


## Nombre del agente con que corre el One-shot ("" = no hay ninguno configurado). Lo pone el plugin.
var agent_name: Callable = func() -> String: return ""


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
		_spec_check.button_pressed = bool(_defaults.get("spec_review", false))


func _ready() -> void:
	if _run == null:
		var empty := get_node_or_null(^"EmptyState") as Label
		if empty:
			empty.text = I18n.t("One-shot: no task running yet.")
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
	# Con el centro angosto (dock ancho) el formulario se achica y scrollea en vez de cortarse (m12-09).
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	_form = scroll
	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(center)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override(&"panel", AgentTheme.panel(AgentTheme.dark_color(), Color(1, 1, 1, 0.08), 8, 20))
	center.add_child(panel)
	scroll.resized.connect(_fit_form.bind(scroll, panel))
	var box := VBoxContainer.new()
	box.add_theme_constant_override(&"separation", AgentTheme.px(10))
	panel.add_child(box)
	var title := Label.new()
	title.text = "One-shot"
	title.add_theme_font_size_override(&"font_size", AgentTheme.px(20))
	box.add_child(title)
	var intro := Label.new()
	intro.text = I18n.t("The agent makes a plan and carries it out on its own: after each task it runs the scene, captures a frame and checks the errors. You can pause it, guide it or go back to a checkpoint at any time.")
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	intro.add_theme_color_override(&"font_color", AgentTheme.MUTED)
	box.add_child(intro)
	_form_columns = BoxContainer.new()
	_form_columns.add_theme_constant_override(&"separation", AgentTheme.px(24))
	box.add_child(_form_columns)
	var goal_column := VBoxContainer.new()
	goal_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	goal_column.add_theme_constant_override(&"separation", AgentTheme.px(10))
	_form_columns.add_child(goal_column)
	_side_column = VBoxContainer.new()
	_side_column.add_theme_constant_override(&"separation", AgentTheme.px(10))
	_form_columns.add_child(_side_column)
	var agent_row := HBoxContainer.new()
	agent_row.add_theme_constant_override(&"separation", AgentTheme.px(8))
	_side_column.add_child(agent_row)
	_agent_label = Label.new()
	_agent_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_agent_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	agent_row.add_child(_agent_label)
	_setup_agent_button = Button.new()
	_setup_agent_button.text = I18n.t("Set up an agent…")
	_setup_agent_button.pressed.connect(func() -> void: settings_requested.emit())
	agent_row.add_child(_setup_agent_button)
	goal_column.add_child(_heading(I18n.t("Goal")))
	_goal_edit = TextEdit.new()
	_goal_edit.placeholder_text = I18n.t("E.g.: 2-player Pong with score, serve and restart. Use the assets in res://assets and follow CLAUDE.md.")
	_goal_edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_goal_edit.custom_minimum_size.y = AgentTheme.px(GOAL_MIN_HEIGHT)
	_goal_edit.text_changed.connect(_refresh_form)
	goal_column.add_child(_goal_edit)
	var examples := VBoxContainer.new()
	examples.add_theme_constant_override(&"separation", AgentTheme.px(4))
	var examples_label := Label.new()
	examples_label.text = I18n.t("Examples:")
	examples_label.add_theme_color_override(&"font_color", AgentTheme.MUTED)
	examples.add_child(examples_label)
	for example: String in GOAL_EXAMPLES:
		var link := LinkButton.new()
		link.text = "· " + I18n.t(example)
		link.tooltip_text = I18n.t("Use it as the goal")
		link.pressed.connect(func() -> void:
			_goal_edit.text = I18n.t(example)
			_refresh_form())
		examples.add_child(link)
	goal_column.add_child(examples)
	_side_column.add_child(_heading(I18n.t("Budgets (0 = unlimited)")))
	# Etiqueta y valor en dos columnas (m12-34): antes eran tres columnas de 290 px para valores como «8».
	var budgets := GridContainer.new()
	budgets.columns = 2
	budgets.add_theme_constant_override(&"h_separation", AgentTheme.px(12))
	_side_column.add_child(budgets)
	var specs: Array[Dictionary] = [
		{"key": OneShotRun.BUDGET_TIME, "suffix": "min", "max": 600, "step": 1},
		{"key": OneShotRun.BUDGET_TOKENS, "suffix": "", "max": 20000000, "step": 10000},
		{"key": OneShotRun.BUDGET_PLAYTESTS, "suffix": "", "max": 100, "step": 1},
	]
	for spec: Dictionary in specs:
		var label := Label.new()
		label.text = I18n.t(OneShotRun.BUDGET_LABELS[spec.key])
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.add_theme_color_override(&"font_color", AgentTheme.MUTED)
		budgets.add_child(label)
		var spin := SpinBox.new()
		spin.max_value = spec.max
		spin.step = spec.step
		spin.suffix = spec.suffix
		spin.value = float(_defaults.get(spec.key, 0))
		spin.select_all_on_focus = true
		spin.custom_minimum_size.x = AgentTheme.px(130)  # «1500000» entero
		budgets.add_child(spin)
		_budget_spins[spec.key] = spin
	_checkpoints_check = CheckBox.new()
	_checkpoints_check.text = I18n.t("Create a git checkpoint before each task (branch agent/<date>; never merges or pushes)")
	_checkpoints_check.button_pressed = bool(_defaults.get("checkpoints", true))
	_checkpoints_check.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_side_column.add_child(_checkpoints_check)
	_spec_check = CheckBox.new()
	_spec_check.text = I18n.t("Review the spec before building (the agent writes it and waits for “Approve spec”)")
	_spec_check.button_pressed = bool(_defaults.get("spec_review", false))
	_spec_check.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_side_column.add_child(_spec_check)
	_form_rule = Label.new()
	_form_rule.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_form_rule.add_theme_color_override(&"font_color", AgentTheme.MUTED)
	_side_column.add_child(_form_rule)
	var actions := HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_END
	actions.add_theme_constant_override(&"separation", AgentTheme.px(10))
	_side_column.add_child(actions)
	_start_hint = Label.new()
	_start_hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_start_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_start_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_start_hint.add_theme_color_override(&"font_color", AgentTheme.MUTED)
	actions.add_child(_start_hint)
	_start_button = _accent_button(I18n.t("Start One-shot"))
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
	header.add_child(_heading(I18n.t("Goal · one-shot")))
	_phase_label = Label.new()
	_phase_label.add_theme_color_override(&"font_color", _accent)
	_phase_label.add_theme_font_size_override(&"font_size", AgentTheme.px(12))
	_phase_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(_phase_label)
	_budgets_button = Button.new()
	_budgets_button.text = I18n.t("Budgets")
	_budgets_button.tooltip_text = I18n.t("Change the budgets while the run is going (0 = unlimited).")
	_budgets_button.pressed.connect(_show_budgets)
	header.add_child(_budgets_button)
	_account_button = MenuButton.new()
	_account_button.text = I18n.t("Switch account")
	_account_button.flat = false
	_account_button.tooltip_text = I18n.t("Continue with another agent account without waiting for the quota to reset: the agent restarts and resumes the same session.")
	_account_button.about_to_popup.connect(_fill_account_menu)
	_account_button.get_popup().id_pressed.connect(_on_account_menu)
	header.add_child(_account_button)
	_spec_button = Button.new()
	_spec_button.text = I18n.t("Spec")
	_spec_button.tooltip_text = I18n.t("The spec the agent wrote (.godot_agent/oneshot/<id>/spec.md): you can read and edit it.")
	_spec_button.pressed.connect(func() -> void: _show_files())
	header.add_child(_spec_button)
	_pause_button = Button.new()
	_pause_button.pressed.connect(_on_pause_pressed)
	header.add_child(_pause_button)
	_stop_button = Button.new()
	_stop_button.text = I18n.t("Stop")
	_stop_button.add_theme_color_override(&"font_color", AgentTheme.ERROR)
	_stop_button.pressed.connect(func() -> void: _run.stop())
	header.add_child(_stop_button)
	_new_button = _accent_button(I18n.t("New One-shot"))
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
	_quota_row = _budget_bar(bars, I18n.t("Quota"))
	for key: String in BUDGET_KEYS:
		_budget_rows[key] = _budget_bar(bars, I18n.t(OneShotRun.BUDGET_LABELS[key]))
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
	var title := _heading(I18n.t("Plan"))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	_plan_title = title
	_plan_edit_button = Button.new()
	_plan_edit_button.text = I18n.t("Edit")
	_plan_edit_button.flat = true
	_plan_edit_button.tooltip_text = I18n.t("Edit the plan: the text is sent to the agent when the current turn ends.")
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
	# Mientras se revisa el spec, la columna lo muestra en lugar del plan (que todavía no existe).
	_spec_view = RichTextLabel.new()
	_spec_view.bbcode_enabled = true
	_spec_view.selection_enabled = true
	_spec_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_spec_view.visible = false
	column.add_child(_spec_view)
	_spec_bar = HBoxContainer.new()
	_spec_bar.alignment = BoxContainer.ALIGNMENT_END
	_spec_bar.visible = false
	column.add_child(_spec_bar)
	var edit_spec := Button.new()
	edit_spec.text = I18n.t("Edit")
	edit_spec.pressed.connect(func() -> void: _show_files(_run.files.spec_path()))
	_spec_bar.add_child(edit_spec)
	var approve := _accent_button(I18n.t("Approve spec"))
	approve.pressed.connect(func() -> void: _run.approve_spec())
	_spec_bar.add_child(approve)
	_plan_edit = TextEdit.new()
	_plan_edit.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_plan_edit.visible = false
	column.add_child(_plan_edit)
	_plan_edit_bar = HBoxContainer.new()
	_plan_edit_bar.alignment = BoxContainer.ALIGNMENT_END
	_plan_edit_bar.visible = false
	column.add_child(_plan_edit_bar)
	var cancel := Button.new()
	cancel.text = I18n.t("Cancel")
	cancel.pressed.connect(func() -> void: _set_plan_editing(false))
	_plan_edit_bar.add_child(cancel)
	var send := _accent_button(I18n.t("Send to the agent"))
	send.pressed.connect(func() -> void:
		_run.edit_plan(_plan_edit.text.split("\n"))
		_set_plan_editing(false))
	_plan_edit_bar.add_child(send)
	_plan_note = Label.new()
	_plan_note.text = I18n.t("You can edit the plan while it runs: the agent rereads it when the turn ends.")
	_plan_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_plan_note.add_theme_color_override(&"font_color", AgentTheme.MUTED)
	_plan_note.add_theme_font_size_override(&"font_size", AgentTheme.px(11))
	column.add_child(_plan_note)
	return column.get_parent()


func _build_activity_column() -> Control:
	var column := _column(1.4)
	column.add_child(_heading(I18n.t("Activity")))
	_activity_text = RichTextLabel.new()
	_activity_text.bbcode_enabled = true
	_activity_text.scroll_following = true
	_activity_text.selection_enabled = true
	_activity_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_activity_text.add_theme_font_override(&"mono_font", AgentTheme.mono_font())
	column.add_child(_activity_text)
	var hint := Label.new()
	hint.text = I18n.t("To guide the agent, write to it in the dock chat: while the One-shot is running, the message reaches it when the turn ends.")
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_color_override(&"font_color", AgentTheme.MUTED)
	hint.add_theme_font_size_override(&"font_size", AgentTheme.px(11))
	column.add_child(hint)
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
	box.add_child(_heading(I18n.t("Last playtest")))
	_capture_rect = TextureRect.new()
	_capture_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_capture_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_capture_rect.custom_minimum_size.y = AgentTheme.px(170)
	ImageViewer.attach(_capture_rect, func() -> Image: return _capture_shown)
	box.add_child(_capture_rect)
	_capture_caption = Label.new()
	_capture_caption.add_theme_color_override(&"font_color", AgentTheme.MUTED)
	_capture_caption.add_theme_font_size_override(&"font_size", AgentTheme.px(11))
	box.add_child(_capture_caption)
	box.add_child(_heading(I18n.t("Checks")))
	_checks_list = VBoxContainer.new()
	box.add_child(_checks_list)
	box.add_child(_heading(I18n.t("Checkpoints")))
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
	_review_button.text = I18n.t("Review changes")
	_review_button.pressed.connect(_on_review_pressed)
	row.add_child(_review_button)
	_report_button = Button.new()
	_report_button.text = I18n.t("Report")
	_report_button.tooltip_text = I18n.t("Run metrics: duration per task, tools, checks, permissions and events.")
	_report_button.pressed.connect(_show_report)
	row.add_child(_report_button)
	_accept_button = _accent_button(I18n.t("Accept all"))
	_accept_button.pressed.connect(func() -> void:
		_accept_dialog.dialog_text = I18n.t("A final commit is made in %s with everything the agent did.\nThe harness never merges or pushes: the branch is left ready for you to merge.") % _run.git.agent_branch
		_accept_dialog.popup_centered())
	row.add_child(_accept_button)
	return panel


func _build_dialogs() -> void:
	_wip_dialog = ConfirmationDialog.new()
	_wip_dialog.cancel_button_text = I18n.t("Cancel")
	_wip_dialog.title = I18n.t("Uncommitted changes")
	_wip_dialog.dialog_text = I18n.t("There are uncommitted changes in the project.\nThey are saved in a “WIP before the one-shot” commit on the agent's new branch; your current branch is not touched.")
	_wip_dialog.ok_button_text = I18n.t("Commit as WIP and start")
	_wip_dialog.confirmed.connect(_start_run)
	add_child(_wip_dialog)
	_no_git_dialog = ConfirmationDialog.new()
	_no_git_dialog.cancel_button_text = I18n.t("Cancel")
	_no_git_dialog.title = I18n.t("No checkpoints")
	_no_git_dialog.ok_button_text = I18n.t("Continue without checkpoints")
	_no_git_dialog.confirmed.connect(func() -> void:
		_checkpoints_check.button_pressed = false
		_start_run())
	add_child(_no_git_dialog)
	_restore_dialog = ConfirmationDialog.new()
	_restore_dialog.cancel_button_text = I18n.t("Cancel")
	_restore_dialog.title = I18n.t("Go back to a checkpoint")
	_restore_dialog.ok_button_text = I18n.t("Restore here")
	_restore_dialog.confirmed.connect(_on_restore_confirmed)
	add_child(_restore_dialog)
	_accept_dialog = ConfirmationDialog.new()
	_accept_dialog.cancel_button_text = I18n.t("Cancel")
	_accept_dialog.title = I18n.t("Accept all")
	_accept_dialog.ok_button_text = I18n.t("Accept all")
	_accept_dialog.confirmed.connect(_on_accept_confirmed)
	add_child(_accept_dialog)
	_changes_dialog = AcceptDialog.new()
	_changes_dialog.title = I18n.t("One-shot changes")
	_changes_dialog.ok_button_text = I18n.t("Close")
	_changes_dialog.min_size = Vector2i(AgentTheme.px(560), AgentTheme.px(380))
	_changes_dialog.exclusive = false  # el diff se abre encima
	var box := VBoxContainer.new()
	_changes_dialog.add_child(box)
	var hint := Label.new()
	hint.text = I18n.t("Double-click a file to see the diff against the state before the One-shot.")
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
	_budgets_dialog = ConfirmationDialog.new()
	_budgets_dialog.cancel_button_text = I18n.t("Cancel")
	_budgets_dialog.title = I18n.t("One-shot budgets")
	_budgets_dialog.ok_button_text = I18n.t("Apply")
	_budgets_dialog.add_button(I18n.t("Unlimited"), false, "unlimited")
	_budgets_dialog.custom_action.connect(func(action: StringName) -> void:
		if action == &"unlimited":
			for key: String in _budgets_edit:
				(_budgets_edit[key] as SpinBox).value = 0
			_apply_budgets()
			_budgets_dialog.hide())
	_budgets_dialog.confirmed.connect(_apply_budgets)
	var budgets_box := VBoxContainer.new()
	_budgets_dialog.add_child(budgets_box)
	var budgets_hint := Label.new()
	budgets_hint.text = I18n.t("0 = unlimited. If the run was about to close because of a budget and now there is enough, it continues.")
	budgets_hint.add_theme_color_override(&"font_color", AgentTheme.MUTED)
	budgets_box.add_child(budgets_hint)
	var budgets_grid := GridContainer.new()
	budgets_grid.columns = 2
	budgets_box.add_child(budgets_grid)
	for spec: Array in [[OneShotRun.BUDGET_TIME, "min", 600, 1], [OneShotRun.BUDGET_TOKENS, "", 20000000, 10000], [OneShotRun.BUDGET_PLAYTESTS, "", 100, 1]]:
		var label := Label.new()
		label.text = I18n.t(OneShotRun.BUDGET_LABELS[spec[0]])
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		budgets_grid.add_child(label)
		var spin := SpinBox.new()
		spin.max_value = spec[2]
		spin.step = spec[3]
		spin.suffix = spec[1]
		spin.select_all_on_focus = true
		spin.custom_minimum_size.x = AgentTheme.px(160)
		budgets_grid.add_child(spin)
		_budgets_edit[spec[0]] = spin
	add_child(_budgets_dialog)
	_files_dialog = ConfirmationDialog.new()
	_files_dialog.title = I18n.t("One-shot spec and progress")
	_files_dialog.min_size = Vector2i(AgentTheme.px(760), AgentTheme.px(560))
	_files_dialog.cancel_button_text = I18n.t("Close")
	_files_dialog.add_button(I18n.t("Show in folder"), false, "folder")
	_files_dialog.add_button(I18n.t("Open in external editor"), false, "external")
	_files_dialog.custom_action.connect(_on_files_action)
	_files_dialog.confirmed.connect(_on_files_confirmed)
	var files_box := VBoxContainer.new()
	_files_dialog.add_child(files_box)
	_files_path_label = Label.new()
	_files_path_label.add_theme_color_override(&"font_color", AgentTheme.MUTED)
	_files_path_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	files_box.add_child(_files_path_label)
	_files_tabs = TabContainer.new()
	_files_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_files_tabs.tab_changed.connect(func(_tab: int) -> void: _refresh_files_path())
	files_box.add_child(_files_tabs)
	_spec_edit = TextEdit.new()
	_spec_edit.name = "Spec"
	_spec_edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_files_tabs.add_child(_spec_edit)
	add_child(_files_dialog)
	_report_dialog = AcceptDialog.new()
	_report_dialog.title = I18n.t("One-shot report")
	_report_dialog.ok_button_text = I18n.t("Close")
	_report_dialog.min_size = Vector2i(AgentTheme.px(620), AgentTheme.px(480))
	_report_dialog.add_button(I18n.t("Copy Markdown"), false, "copy")
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


## Ancho del formulario y alto del objetivo según el espacio disponible. El resto del formulario
## mide unos 330 px; el objetivo se queda con hasta el 40 % del alto.
func _fit_form(area: Control, panel: Control) -> void:
	var width := clampf(area.size.x * FORM_WIDTH_RATIO, AgentTheme.px(FORM_MIN_WIDTH), maxf(AgentTheme.px(FORM_MAX_WIDTH), AgentTheme.px(FORM_MIN_WIDTH)))
	# Nunca más ancho que el área: angosto, el formulario se achica hasta FORM_NARROW_WIDTH.
	panel.custom_minimum_size.x = clampf(width, AgentTheme.px(FORM_NARROW_WIDTH), maxf(area.size.x - AgentTheme.px(32), AgentTheme.px(FORM_NARROW_WIDTH)))
	var columns := panel.custom_minimum_size.x >= AgentTheme.px(FORM_COLUMNS_MIN_WIDTH)
	_form_columns.vertical = not columns
	_side_column.custom_minimum_size.x = AgentTheme.px(SIDE_COLUMN_WIDTH) if columns else 0.0
	_goal_edit.custom_minimum_size.y = maxf(AgentTheme.px(GOAL_MIN_HEIGHT), area.size.y * GOAL_HEIGHT_RATIO)


func _heading(text: String) -> Label:
	var label := Label.new()
	label.text = text.to_upper()
	label.add_theme_font_size_override(&"font_size", AgentTheme.px(11))
	label.add_theme_color_override(&"font_color", Color(1, 1, 1, 0.66))
	return label


func _accent_button(text: String) -> Button:
	var button := Button.new()
	button.text = text
	AgentTheme.style_accent_button(button, _accent, 4, 6)
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
	_form_rule.text = I18n.t("Plan quota: %s") % _run.quota.rule_text().to_lower() if _run.quota.has_data() else I18n.t("The agent hasn't reported the plan quota yet: the One-shot pauses for quota only if it does.")
	var agent := str(agent_name.call())
	if agent.is_empty():
		_agent_label.text = I18n.t("No agent set up yet: the One-shot needs one.")
		_agent_label.add_theme_color_override(&"font_color", AgentTheme.WARNING)
	else:
		_agent_label.text = I18n.t("Runs with %s (the agent selected in the dock).") % agent
		_agent_label.add_theme_color_override(&"font_color", AgentTheme.MUTED)
	_setup_agent_button.visible = agent.is_empty()
	var missing := start_blocker(agent, _goal_edit.text, _run.is_active())
	_start_hint.text = missing
	_start_button.disabled = not missing.is_empty()
	_start_button.tooltip_text = missing


## Qué falta para poder iniciar ("" = nada).
static func start_blocker(agent: String, goal: String, active: bool) -> String:
	if active:
		return I18n.t("A One-shot is already running.")
	if agent.is_empty():
		return I18n.t("Set up an agent first.")
	if goal.strip_edges().is_empty():
		return I18n.t("Write the goal first.")
	return ""


## Se cambió el agente del dock o se agregó uno en Ajustes.
func refresh_agent() -> void:
	if _run != null and is_instance_valid(_start_button):
		_refresh_form()


func _refresh_banner() -> void:
	var quota := _run.quota
	var text := ""
	var color := AgentTheme.WARNING
	match quota.state:
		QuotaMonitor.QuotaState.WARNING:
			text = I18n.t("Plan quota at %d %% · %s") % [roundi(quota.max_utilization() * 100.0), quota.rule_text().to_lower()]
		QuotaMonitor.QuotaState.PAUSE_SCHEDULED:
			text = _run.quota_pause_text()
			if text.is_empty():
				text = quota.rule_text()
		QuotaMonitor.QuotaState.LIMITED:
			color = AgentTheme.ERROR
			var wait := quota.seconds_until_retry()
			text = I18n.t("Plan limit reached · you can try again in %s") % QuotaMonitor.format_duration(wait) if wait > 0 else I18n.t("Plan limit reached · you can retry now")
	if text.is_empty() and _run.phase == OneShotRun.RunPhase.SPEC_REVIEW:
		text = I18n.t("The agent wrote the spec: it's in the left column. Approve it so the agent starts building, or tell it in the chat what to change (it revises it and waits again).") if _run.files.has_spec() else I18n.t("The agent didn't write the spec. Ask it in the chat to write it, or approve to continue without a spec.")
	if text.is_empty() and _run.phase == OneShotRun.RunPhase.PAUSED and not _run.pause_note.is_empty():
		text = _run.pause_note
	if text.is_empty() and _run.recovered and _run.phase == OneShotRun.RunPhase.PAUSED:
		text = I18n.t("The One-shot was left unfinished because the editor closed. “Resume” reopens the agent's session and continues; “Stop” ends it.")
	if text.is_empty() and _run.phase == OneShotRun.RunPhase.FINISHED and not _show_form:
		text = _run.finish_reason
		color = _accent
	_banner.visible = not text.is_empty()
	_banner_label.text = text
	_banner_label.add_theme_color_override(&"font_color", color)
	_banner.add_theme_stylebox_override(&"panel", AgentTheme.panel(Color(color, 0.12), Color(color, 0.5), 0, 8))


func _refresh_top_bar() -> void:
	var position := _run.plan_position()
	_phase_label.text = _run.phase_label() + (" · " + position if not position.is_empty() and _run.phase != OneShotRun.RunPhase.FINISHED else "")
	var phase_color := _accent
	match _run.phase:
		OneShotRun.RunPhase.LIMITED:
			phase_color = AgentTheme.ERROR
		OneShotRun.RunPhase.PAUSED, OneShotRun.RunPhase.PAUSED_QUOTA, OneShotRun.RunPhase.WAITING_CONFIRM, OneShotRun.RunPhase.SPEC_REVIEW:
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
		(_quota_row.label as Label).tooltip_text = I18n.t("The agent doesn't report the plan quota.")
	for key: String in BUDGET_KEYS:
		var ratio := _run.budget_ratio(key)
		var color := AgentTheme.ERROR if ratio >= 1.0 else (AgentTheme.WARNING if ratio >= OneShotRun.WARN_RATIO else _accent)
		_set_bar(_budget_rows[key], _budget_text(key), minf(ratio, 1.0), color)
	_rule_label.text = quota.rule_text()

	var countdown := ""
	var now := int(Time.get_unix_time_from_system())
	match _run.phase:
		OneShotRun.RunPhase.LIMITED:
			var wait := quota.seconds_until_retry()
			countdown = ("⏳ " + I18n.t("Resets in %s") % QuotaMonitor.format_duration(wait)) if wait > 0 else "⏳ " + I18n.t("Retrying…")
		OneShotRun.RunPhase.PAUSED_QUOTA:
			if _run.quota_resume_at > now:
				countdown = "⏸ " + I18n.t("Paused for quota before “%s” · resumes in %s") % [_run.resume_task, QuotaMonitor.format_duration(_run.quota_resume_at - now)]
			else:
				countdown = "⏸ " + I18n.t("Paused for quota before “%s”") % _run.resume_task
		OneShotRun.RunPhase.WAITING_CONFIRM:
			countdown = I18n.t("The quota is free again: press Resume to continue from “%s”") % _run.resume_task
		OneShotRun.RunPhase.PAUSED:
			if not _run.resume_task.is_empty():
				countdown = I18n.t("Resumes from “%s”") % _run.resume_task
	_countdown_label.text = countdown
	_countdown_label.visible = not countdown.is_empty()

	var finished := _run.phase == OneShotRun.RunPhase.FINISHED
	_pause_button.visible = not finished
	_stop_button.visible = not finished
	_new_button.visible = finished
	var can_resume := _run.can_resume()
	_account_button.visible = _run.is_active() and can_resume
	_pause_button.text = I18n.t("Resume") if can_resume else I18n.t("Pause")
	_pause_button.disabled = not (can_resume or _run.phase in [OneShotRun.RunPhase.RUNNING, OneShotRun.RunPhase.EVALUATING])
	_pause_button.tooltip_text = I18n.t("Retries now, without waiting for the window to reset.") if _run.phase == OneShotRun.RunPhase.LIMITED else ""
	_stop_button.disabled = not _run.is_active()
	_spec_button.visible = _run.files.has_spec() or _run.phase == OneShotRun.RunPhase.SPEC_REVIEW
	_budgets_button.visible = _run.is_active()
	_spec_button.text = I18n.t("Review spec") if _run.phase == OneShotRun.RunPhase.SPEC_REVIEW else I18n.t("Spec and progress")


func _refresh_plan() -> void:
	var reviewing := _run.phase == OneShotRun.RunPhase.SPEC_REVIEW
	_plan_title.text = I18n.t("Spec").to_upper() if reviewing else I18n.t("Plan").to_upper()
	(_plan_list.get_parent() as Control).visible = not reviewing and not _plan_edit.visible
	_plan_edit_button.visible = not reviewing and not _plan_edit.visible
	_plan_note.visible = not reviewing
	_spec_view.visible = reviewing
	_spec_bar.visible = reviewing
	if reviewing:
		var spec := _run.files.read(_run.files.spec_path())
		if spec != _spec_shown or _spec_view.text.is_empty():
			_spec_shown = spec
			_spec_view.text = MarkdownBBCode.new().convert(spec) if not spec.is_empty() else "[color=#9aa0a6]%s[/color]" % I18n.t("The agent didn't write the spec. Ask it in the chat to write it, or approve to continue without a spec.")
		return
	var plan: Array = _run.current_plan()
	var signature := JSON.stringify(plan) + ("|fin" if plan.is_empty() and _run.phase == OneShotRun.RunPhase.FINISHED else "")
	if signature == _plan_signature:
		_refresh_plan_times()
		return
	_plan_signature = signature
	_plan_times.clear()
	_plan_edit_button.disabled = plan.is_empty()
	for child: Node in _plan_list.get_children():
		child.queue_free()
	if plan.is_empty():
		_plan_list.add_child(_muted_label(I18n.t("The agent didn't report a plan: progress comes from the playtests and the checks.") if _run.phase == OneShotRun.RunPhase.FINISHED else I18n.t("The agent hasn't made the plan yet.")))
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
		var time := Label.new()
		time.add_theme_color_override(&"font_color", AgentTheme.MUTED)
		time.add_theme_font_size_override(&"font_size", AgentTheme.px(11))
		time.tooltip_text = I18n.t("How long the task has been running (or how long it took, if it's done).")
		row.add_child(time)
		_plan_times[str(entry.get("content", ""))] = time
		var holder := PanelContainer.new()
		holder.add_theme_stylebox_override(&"panel", AgentTheme.panel(Color(_accent, 0.1) if status == "in_progress" else Color.TRANSPARENT, Color.TRANSPARENT, 5, 6))
		holder.add_child(row)
		_plan_list.add_child(holder)
	_refresh_plan_times()


func _refresh_plan_times() -> void:
	var now := _run.elapsed_ms()
	for content: String in _plan_times:
		var ms := _run.report.task_ms(content, now)
		(_plan_times[content] as Label).text = RunReport.format_duration(roundi(ms / 1000.0)) if ms >= 0 else ""


func _refresh_side() -> void:
	if _run.last_capture != _capture_shown:
		_capture_shown = _run.last_capture
		_capture_rect.texture = ImageTexture.create_from_image(_capture_shown) if _capture_shown else null
	_capture_caption.text = _run.last_capture_caption if _capture_shown else I18n.t("No captures yet.")

	var signature := JSON.stringify(_run.checks)
	if signature != _checks_signature:
		_checks_signature = signature
		for child: Node in _checks_list.get_children():
			child.queue_free()
		if _run.checks.is_empty():
			_checks_list.add_child(_muted_label(I18n.t("The agent reports the checks when it finishes each task.")))
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
			_checkpoints_list.add_child(_muted_label(I18n.t("Checkpoints turned off.")))
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
			back.text = I18n.t("Restore here")
			back.flat = true
			back.add_theme_color_override(&"font_color", Color("#6cb4ff"))
			back.pressed.connect(_on_restore_pressed.bind(cp))
			row.add_child(back)
			_checkpoints_list.add_child(row)


func _refresh_bottom_bar() -> void:
	_report_button.visible = not _run.last_report.is_empty() and _run.phase == OneShotRun.RunPhase.FINISHED and not _show_form
	var enabled := _run.checkpoints_enabled
	_review_button.disabled = not enabled or _summary.get("files", []).is_empty()
	_accept_button.disabled = not enabled or _run.phase == OneShotRun.RunPhase.PREPARING
	if not enabled:
		_summary_label.text = I18n.t("No checkpoints: no change summary and no agent branch.")
		_diffstat_label.text = ""
		return
	var files: Array = _summary.get("files", [])
	var scenes := files.filter(func(file: Dictionary) -> bool: return str(file.path).get_extension() in SCENE_EXTENSIONS).size()
	var scripts := files.filter(func(file: Dictionary) -> bool: return str(file.path).get_extension() in SCRIPT_EXTENSIONS).size()
	var parts: PackedStringArray = [
		(I18n.t("%d file changed") if files.size() == 1 else I18n.t("%d files changed")) % files.size(),
		(I18n.t("%d scene") if scenes == 1 else I18n.t("%d scenes")) % scenes,
		(I18n.t("%d script") if scripts == 1 else I18n.t("%d scripts")) % scripts,
	]
	_summary_label.text = " · ".join(parts)
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
			return "%d / %d min" % [minutes, limit] if limit > 0 else "%d min / ∞" % minutes
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
	if not start_blocker(str(agent_name.call()), _goal_edit.text, _run.is_active()).is_empty():
		return
	_start_button.disabled = true
	var check: Dictionary = await _run.preflight(_checkpoints_check.button_pressed)
	_start_button.disabled = false
	if not str(check.warning).is_empty():
		# Sin git o sin commits no hay checkpoints: «Volver acá» no va a existir (D37).
		_no_git_dialog.dialog_text = I18n.t("%s\n\nWithout checkpoints you can't go back or review the One-shot's changes.") % check.warning
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
	var started: bool = await _run.start(goal, budgets, _checkpoints_check.button_pressed, _spec_check.button_pressed)
	if started:
		_goal_edit.text = ""
	_summary_dirty = true
	_refresh()


## Un ítem por método de login del agente (corre el login y, al terminar, el run retoma con la
## cuenta nueva) y «ya cambié» para cuando se hizo en una terminal.
func _fill_account_menu() -> void:
	var popup := _account_button.get_popup()
	popup.clear()
	var methods := _run.controller.login_methods()
	for i in methods.size():
		popup.add_item(I18n.t("Sign in with another account · %s") % methods[i].label, i)
	if not methods.is_empty():
		popup.add_separator()
	popup.add_item(I18n.t("I already signed in with another account (in a terminal): restart the agent"), ACCOUNT_ALREADY_SWITCHED)


func _on_account_menu(id: int) -> void:
	if id == ACCOUNT_ALREADY_SWITCHED:
		_run.switch_account()
		return
	var methods := _run.controller.login_methods()
	if id >= 0 and id < methods.size():
		_run.controller.login(str(methods[id].id))


func _on_pause_pressed() -> void:
	if _run.phase in [OneShotRun.RunPhase.RUNNING, OneShotRun.RunPhase.EVALUATING]:
		_run.pause()
	else:
		_run.resume()


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
	var kind := I18n.t(ACTIVITY_KIND_LABELS[entry.kind]) if ACTIVITY_KIND_LABELS.has(entry.kind) else str(entry.kind)
	_activity_text.append_text("[color=%s][code]%s[/code][/color]  [color=%s]%s[/color]  %s\n" % [
		AgentTheme.color_hex(AgentTheme.MUTED), entry.time, AgentTheme.color_hex(color), kind, text])
	if entry.kind in ["checkpoint", "tool", "playtest", "status", "agent"]:
		_summary_dirty = true


func _on_restore_pressed(cp: Dictionary) -> void:
	_pending_restore = cp
	_restore_dialog.dialog_text = I18n.t("Go back to %s (%s)?\nThe project folder is left as it was at that checkpoint (later changes are discarded) and the One-shot is paused.") % [cp.name, cp.label]
	_restore_dialog.popup_centered()


func _on_restore_confirmed() -> void:
	if _pending_restore.is_empty():
		return
	var error: String = await _run.restore(_pending_restore)
	_pending_restore = {}
	_summary_dirty = true
	if not error.is_empty():
		_show_error(I18n.t("Couldn't go back to the checkpoint: %s") % error)


func _on_accept_confirmed() -> void:
	var error: String = await _run.accept_all()
	_summary_dirty = true
	if not error.is_empty():
		_show_error(I18n.t("Couldn't accept: %s") % error)


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
	diff_requested.emit("One-shot: " + path, I18n.t("before the One-shot"), old_text, I18n.t("now"), new_text)


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


func _show_budgets() -> void:
	for key: String in _budgets_edit:
		(_budgets_edit[key] as SpinBox).value = float(_run.budgets.get(key, 0))
	_budgets_dialog.popup_centered()


func _apply_budgets() -> void:
	var values := {}
	for key: String in _budgets_edit:
		values[key] = int((_budgets_edit[key] as SpinBox).value)
	_run.set_budgets(values)


## Un archivo de .godot_agent/oneshot/ (un link del chat): el del run se ve acá; otro, afuera.
func show_run_file(path: String) -> void:
	if _run and not _run.run_id.is_empty() and path.simplify_path().begins_with(_run.files.dir()):
		_show_files(path.simplify_path())
	elif FileAccess.file_exists(path):
		OS.shell_open(path)


## Spec (editable), progreso y los QA del run, en pestañas; `focus` elige la pestaña.
func _show_files(focus: String = "") -> void:
	for child: Node in _files_tabs.get_children():
		if child != _spec_edit:
			_files_tabs.remove_child(child)
			child.queue_free()
	_spec_edit.text = _run.files.read(_run.files.spec_path())
	_files_paths = [_run.files.spec_path()]
	var others: Array[Array] = [[I18n.t("Progress"), _run.files.progress_path()]]
	for path: String in _run.files.qa_files():
		others.append(["QA " + path.get_file().get_basename().trim_prefix("qa-"), path])
	for other: Array in others:
		var view := TextEdit.new()
		view.name = other[0]
		view.editable = false
		view.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
		var text := _run.files.read(other[1])
		view.text = text if not text.is_empty() else I18n.t("(doesn't exist yet)")
		_files_tabs.add_child(view)
		_files_paths.append(other[1])
	var index := _files_paths.find(focus)
	_files_tabs.current_tab = maxi(index, 0)
	var reviewing := _run.phase == OneShotRun.RunPhase.SPEC_REVIEW
	_files_dialog.ok_button_text = I18n.t("Approve spec") if reviewing else I18n.t("Save spec")
	_refresh_files_path()
	_files_dialog.popup_centered()


func _refresh_files_path() -> void:
	var tab := _files_tabs.current_tab
	_files_path_label.text = _files_paths[tab] if tab >= 0 and tab < _files_paths.size() else ""


func _on_files_action(action: StringName) -> void:
	match action:
		&"folder":
			_run.files.prepare()
			OS.shell_show_in_file_manager(_run.files.dir())
		&"external":
			var path := _files_path_label.text
			if FileAccess.file_exists(path):
				OS.shell_open(path)


func _on_files_confirmed() -> void:
	if _run.phase == OneShotRun.RunPhase.SPEC_REVIEW:
		_run.approve_spec(_spec_edit.text)
	elif _spec_edit.text != _run.files.read(_run.files.spec_path()):
		_run.files.write(_run.files.spec_path(), _spec_edit.text)
