@tool
extends PanelContainer
## Panel de la revisión en el dock (modo Revisar, spec §9.4): alcance, aviso de solo lectura,
## contadores por severidad, lista `archivo:línea` y las acciones sobre toda la revisión.
## Plegado muestra una fila con el alcance y los contadores, para no quitarle alto al chat (m12-03).

signal finding_selected(id: int)
signal fix_all_requested
## Un aviso para el chat (exportar a CLAUDE.md, importar de GitHub).
signal notice_requested(text: String, level: ChatEntry.NoticeLevel)
## Repetir los playtests guardados, sin agente (m16-06).
signal regressions_requested
## Un prompt para mandar al agente (el de un playtest, m14-03).
signal prompt_requested(text: String)

const ReviewStore := preload("../../review/review_store.gd")
const ChatEntry := preload("../../session/chat_entry.gd")
const GithubReviews := preload("../../core/github_reviews.gd")
const EditorContext := preload("../editor_context.gd")
const AgentTheme := preload("../agent_theme.gd")
const I18n := preload("../../core/i18n.gd")
const PlaytestMemory := preload("../../review/playtest_memory.gd")
const PlaytestRegressions := preload("../../review/playtest_regressions.gd")
const FindingLocator := preload("finding_locator.gd")

const LIST_MAX_HEIGHT := 180
const PLAYTEST_MINUTES_KEY := "playtest_minutes"
const PLAYTEST_MINUTES_DEFAULT := 15
const PLAYTEST_MINUTES_MAX := 600
const COUNTER_LABELS: Dictionary = {
	"bug": "bug",  # i18n
	"order": "order",  # i18n
	"perf": "perf",  # i18n
	"style": "style",  # i18n
}

var _store: ReviewStore
var _accent: Color
var _fold: FoldableContainer
var _counters: HBoxContainer
var _list: VBoxContainer
var _scroll: ScrollContainer
var _empty: Label
var _export_button: Button
var _fix_button: Button
var _export_dialog: ConfirmationDialog
var _export_preview: TextEdit
var _run_again: Button
var _regressions_button: Button
## El último playtest pedido, para repetirlo tal cual (m15-17): {goal, record, minutes}.
var _last_playtest: Dictionary = {}


func setup(store: ReviewStore, accent: Color) -> void:
	_store = store
	_accent = accent


func _ready() -> void:
	add_theme_stylebox_override(&"panel", AgentTheme.panel(Color(1, 1, 1, 0.03), Color(1, 1, 1, 0.08), 6, 8))
	_fold = FoldableContainer.new()
	_fold.folded = true
	_fold.title_text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_fold.tooltip_text = I18n.t("Click the title to fold or unfold.")
	add_child(_fold)
	var column := VBoxContainer.new()
	column.add_theme_constant_override(&"separation", AgentTheme.px(6))
	_fold.add_child(column)
	var notice := Label.new()
	notice.text = I18n.t("Read-only: in this mode the agent does not modify anything.")
	notice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	notice.add_theme_color_override(&"font_color", AgentTheme.MUTED)
	notice.add_theme_font_size_override(&"font_size", AgentTheme.px(11))
	column.add_child(notice)

	_counters = HBoxContainer.new()
	_counters.add_theme_constant_override(&"separation", AgentTheme.px(4))
	column.add_child(_counters)

	_empty = Label.new()
	_empty.text = I18n.t("Ask the agent to review a script or a folder: the findings show up here and in the Script Editor.")
	_empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_empty.add_theme_color_override(&"font_color", AgentTheme.MUTED)
	column.add_child(_empty)
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(_scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override(&"separation", 0)
	_scroll.add_child(_list)

	var actions := HFlowContainer.new()  # en un dock angosto los botones bajan de línea
	_export_button = Button.new()
	_export_button.text = I18n.t("Export to CLAUDE.md")
	_export_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_export_button.tooltip_text = I18n.t("Adds the conventions from this review to CLAUDE.md (with a preview)")
	_export_button.pressed.connect(_on_export_requested)
	actions.add_child(_export_button)
	_fix_button = Button.new()
	_fix_button.text = I18n.t("Fix in Build mode")
	_fix_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_fix_button.tooltip_text = I18n.t("Switches to Build mode and asks the agent to fix all the findings")
	AgentTheme.style_accent_button(_fix_button, _accent, 3, 4)
	_fix_button.pressed.connect(fix_all_requested.emit)
	actions.add_child(_fix_button)
	var github := Button.new()
	github.text = I18n.t("From a GitHub PR…")
	github.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	github.tooltip_text = I18n.t("Brings the review comments of a pull request (with the gh CLI) as findings, with their file and line")
	github.pressed.connect(_on_github_import_requested)
	actions.add_child(github)
	var playtest := Button.new()
	playtest.text = I18n.t("Playtest…")
	playtest.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	playtest.tooltip_text = I18n.t("The agent plays the game to check something and answers passed, failed or could not test, with evidence and steps to reproduce. It does not change the project.")
	playtest.pressed.connect(_on_playtest_requested)
	actions.add_child(playtest)
	_run_again = Button.new()
	_run_again.text = I18n.t("Run the playtest again")
	_run_again.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_run_again.visible = false
	_run_again.pressed.connect(func() -> void: _start_playtest(_last_playtest.goal, _last_playtest.record, _last_playtest.minutes))
	actions.add_child(_run_again)
	_regressions_button = Button.new()
	_regressions_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_regressions_button.tooltip_text = I18n.t("Repeats the playtests that passed, without the agent and without using tokens.")
	_regressions_button.pressed.connect(regressions_requested.emit)
	actions.add_child(_regressions_button)
	column.add_child(actions)

	_export_dialog = ConfirmationDialog.new()
	_export_dialog.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_export_dialog.cancel_button_text = I18n.t("Cancel")
	_export_dialog.title = I18n.t("Export to CLAUDE.md")
	_export_dialog.ok_button_text = I18n.t("Add to CLAUDE.md")
	_export_dialog.min_size = Vector2i(AgentTheme.px(560), AgentTheme.px(360))
	_export_preview = TextEdit.new()
	_export_preview.editable = true  # vista previa editable antes de agregar
	_export_preview.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_export_dialog.add_child(_export_preview)
	_export_dialog.confirmed.connect(_on_export_confirmed)
	add_child(_export_dialog)
	_store.changed.connect(refresh)
	refresh()


func refresh() -> void:
	var findings := _store.findings
	var files := _store.paths().size()
	var title := I18n.t("Code review")
	if _store.reviewed_at != 0:
		title = (I18n.t("Review of %s · %d file") if files == 1 else I18n.t("Review of %s · %d files")) % [_store.scope_label(), files]
	for child: Node in _counters.get_children():
		child.queue_free()
	var counts := _store.counts()
	var summary: PackedStringArray = []
	for severity: String in COUNTER_LABELS:
		if counts[severity] > 0:
			summary.append("%d %s" % [counts[severity], I18n.t(COUNTER_LABELS[severity])])
		var chip := Label.new()
		chip.text = "%d %s" % [counts[severity], I18n.t(COUNTER_LABELS[severity])]
		chip.tooltip_text = I18n.t(ReviewStore.SEVERITY_LABELS[severity])
		chip.mouse_filter = Control.MOUSE_FILTER_PASS
		chip.add_theme_font_size_override(&"font_size", AgentTheme.px(11))
		chip.add_theme_color_override(&"font_color", AgentTheme.SEVERITY_COLORS[severity].lightened(0.35))
		chip.add_theme_stylebox_override(&"normal", AgentTheme.panel(AgentTheme.SEVERITY_BG[severity], Color.TRANSPARENT, 10, 3))
		_counters.add_child(chip)

	for child: Node in _list.get_children():
		_list.remove_child(child)
		child.queue_free()
	for finding: Dictionary in findings:
		_list.add_child(_row(finding))
	_empty.visible = findings.is_empty()
	if _store.reviewed_at != 0 and findings.is_empty():
		_empty.text = I18n.t("No pending findings.")
	_fold.title = " · ".join(PackedStringArray([title]) + summary)
	_scroll.visible = not findings.is_empty()
	# Con el alto real de una fila: con 26 px fijos se veía un hallazgo y medio.
	var row_height: float = (_list.get_child(0) as Control).get_combined_minimum_size().y if _list.get_child_count() > 0 else 0.0
	_scroll.custom_minimum_size.y = minf(AgentTheme.px(LIST_MAX_HEIGHT), findings.size() * row_height)
	_export_button.disabled = findings.is_empty()
	_fix_button.disabled = findings.is_empty()
	var saved := PlaytestRegressions.new().list().size()
	_regressions_button.visible = saved > 0
	_regressions_button.text = I18n.t("Run regressions (%d)") % saved


## Un hallazgo: su fila y, si salió de un playtest, qué hacer con él (m15-17, m15-18).
func _row(finding: Dictionary) -> Control:
	var row := _finding_button(finding)
	if not finding.get("playtest", false):
		return row
	var column := VBoxContainer.new()
	column.add_theme_constant_override(&"separation", 0)
	column.add_child(row)
	var actions := HFlowContainer.new()
	if finding.has("node") or finding.has("where"):
		actions.add_child(_small_button(I18n.t("Show in the scene"), _show_in_scene.bind(finding)))
	actions.add_child(_small_button(I18n.t("Verify a fix"), func() -> void: _start_playtest("Verify that this is fixed: %s. %s" % [finding.title, finding.body], false, _saved_minutes())))
	actions.add_child(_small_button(I18n.t("Not a bug"), _mark_not_a_bug.bind(finding)))
	column.add_child(actions)
	return column


static func _small_button(text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.flat = true
	button.add_theme_font_size_override(&"font_size", AgentTheme.px(11))
	button.pressed.connect(action)
	return button


func _show_in_scene(finding: Dictionary) -> void:
	var shown: Array = await FindingLocator.show(finding)
	if is_inside_tree():
		notice_requested.emit(shown[1], ChatEntry.NoticeLevel.INFO if shown[0] else ChatEntry.NoticeLevel.WARNING)


## Queda en la memoria del juego: ni los detectores ni el agente lo vuelven a traer.
func _mark_not_a_bug(finding: Dictionary) -> void:
	PlaytestMemory.new().mark_not_a_bug(str(finding.get("signature", finding.title)))
	_store.dismiss(int(finding.id))


func _on_finding_pressed(finding: Dictionary) -> void:
	if str(finding.path).is_empty():
		_show_in_scene(finding)
	else:
		finding_selected.emit(int(finding.id))


func _finding_button(finding: Dictionary) -> Button:
	var row := Button.new()
	row.flat = true
	row.alignment = HORIZONTAL_ALIGNMENT_LEFT
	row.clip_text = true
	row.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	row.text = "%s  ·  %s" % [ReviewStore.location(finding), finding.title]
	row.tooltip_text = "%s\n[%s] %s\n%s" % [ReviewStore.location(finding), I18n.t(ReviewStore.SEVERITY_LABELS[finding.severity]), finding.title, finding.body]
	row.icon = _dot(AgentTheme.SEVERITY_COLORS[finding.severity])
	row.pressed.connect(_on_finding_pressed.bind(finding))
	return row


static func _dot(color: Color) -> Texture2D:
	return AgentTheme.dot(color)


# --- exportar a CLAUDE.md ------------------------------------------------------------------------

func _on_export_requested() -> void:
	_export_preview.text = ReviewStore.claude_md_section(_store.findings, Time.get_date_string_from_system())
	var exists := FileAccess.file_exists(ReviewStore.CLAUDE_MD_PATH)
	_export_dialog.title = I18n.t("Append to CLAUDE.md") if exists else I18n.t("Create CLAUDE.md")
	_export_dialog.popup_centered()


func _on_export_confirmed() -> void:
	var error := ReviewStore.append_to_claude_md(_export_preview.text)
	if not error.is_empty():
		notice_requested.emit(I18n.t("Could not write CLAUDE.md: %s") % error, ChatEntry.NoticeLevel.ERROR)
		return
	EditorInterface.get_resource_filesystem().update_file(ReviewStore.CLAUDE_MD_PATH)
	notice_requested.emit(I18n.t("Review conventions added to CLAUDE.md."), ChatEntry.NoticeLevel.INFO)


# --- comentarios de un PR de GitHub como hallazgos (m11-10) -----------------------------------------

func _on_github_import_requested() -> void:
	var dialog := ConfirmationDialog.new()
	dialog.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	dialog.title = I18n.t("Review comments from GitHub")
	var column := VBoxContainer.new()
	var hint := Label.new()
	hint.text = I18n.t("Pull request number (empty: the one of the current branch). It needs the gh CLI signed in.")
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.custom_minimum_size.x = AgentTheme.px(320)
	column.add_child(hint)
	var number := LineEdit.new()
	number.placeholder_text = "123"
	column.add_child(number)
	dialog.add_child(column)
	dialog.ok_button_text = I18n.t("Import")
	dialog.cancel_button_text = I18n.t("Cancel")
	dialog.register_text_enter(number)
	dialog.confirmed.connect(func() -> void: _import_github_review(number.text))
	dialog.visibility_changed.connect(func() -> void:
		if not dialog.visible:
			dialog.queue_free.call_deferred())
	add_child(dialog)
	dialog.popup_centered()
	number.grab_focus()


func _import_github_review(pr: String) -> void:
	notice_requested.emit(I18n.t("Reading the pull request's review comments…"), ChatEntry.NoticeLevel.INFO)
	var result: Dictionary = await GithubReviews.new(EditorContext.project_path()).fetch_review(pr)
	if not is_inside_tree():  # se cerró la pestaña o el plugin mientras esperaba
		return
	if not str(result.error).is_empty():
		notice_requested.emit(str(result.error), ChatEntry.NoticeLevel.WARNING)
	elif result.findings.is_empty():
		notice_requested.emit(I18n.t("%s has no review comments on lines of this project's files.") % result.url, ChatEntry.NoticeLevel.INFO)
	else:
		var findings: Array[Dictionary] = []
		findings.assign(result.findings)
		_store.set_findings(findings)
		notice_requested.emit(I18n.t("%d review comments from %s are in the findings and the Script Editor.") % [findings.size(), result.url], ChatEntry.NoticeLevel.INFO)


# --- playtest (m14-03) ---------------------------------------------------------------------------

func _on_playtest_requested() -> void:
	var dialog := ConfirmationDialog.new()
	dialog.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	dialog.title = I18n.t("Playtest")
	var column := VBoxContainer.new()
	var hint := Label.new()
	hint.text = I18n.t("What should the agent check by playing? For example: the player can jump onto the second platform.")
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.custom_minimum_size.x = AgentTheme.px(360)
	column.add_child(hint)
	var goal := LineEdit.new()
	column.add_child(goal)
	var record := CheckBox.new()
	record.text = I18n.t("Record a video of the run (in res://.godot_agent/playtests/)")
	column.add_child(record)
	var limit := HBoxContainer.new()
	var limit_label := Label.new()
	limit_label.text = I18n.t("Time limit in minutes (0: none)")
	limit_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	limit.add_child(limit_label)
	var minutes := SpinBox.new()
	minutes.max_value = PLAYTEST_MINUTES_MAX
	minutes.value = _saved_minutes()
	limit.add_child(minutes)
	column.add_child(limit)
	dialog.add_child(column)
	dialog.ok_button_text = I18n.t("Start playtest")
	dialog.cancel_button_text = I18n.t("Cancel")
	dialog.register_text_enter(goal)
	dialog.confirmed.connect(func() -> void:
		if not goal.text.strip_edges().is_empty():
			_save_minutes(int(minutes.value))
			_start_playtest(goal.text, record.button_pressed, int(minutes.value)))
	dialog.visibility_changed.connect(func() -> void:
		if not dialog.visible:
			dialog.queue_free.call_deferred())
	add_child(dialog)
	dialog.popup_centered()
	goal.grab_focus()


func _start_playtest(goal: String, record: bool, minutes: int) -> void:
	_last_playtest = {"goal": goal, "record": record, "minutes": minutes}
	_run_again.visible = true
	prompt_requested.emit(ReviewStore.playtest_prompt(goal, record, minutes, PlaytestMemory.new().brief()))


## El tope de tiempo se recuerda por proyecto (m15-19).
static func _saved_minutes() -> int:
	if not AgentTheme.has_editor():
		return PLAYTEST_MINUTES_DEFAULT
	return int(EditorInterface.get_editor_settings().get_project_metadata("godot_agent", PLAYTEST_MINUTES_KEY, PLAYTEST_MINUTES_DEFAULT))


static func _save_minutes(minutes: int) -> void:
	if AgentTheme.has_editor():
		EditorInterface.get_editor_settings().set_project_metadata("godot_agent", PLAYTEST_MINUTES_KEY, minutes)
