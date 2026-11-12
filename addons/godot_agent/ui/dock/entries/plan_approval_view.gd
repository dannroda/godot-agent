@tool
extends "entry_view.gd"
## Tarjeta del plan que presenta el agente desde su modo plan (m11-22, ExitPlanMode): el plan en
## markdown y «Aprobar y construir» · «Editar» · «Seguir planeando…». Editar cambia la vista por el
## texto con un contador +N −M en vivo; lo editado y el motivo vuelven al agente al terminar el turno.
## No vence. Contestada, queda plegada con el resultado y el plan a pedido.
## Con criterios «WHEN …, THE GAME SHALL …» (m11-23), una casilla para verificarlos jugando al aprobar
## (un playtest por criterio) y, después, el estado de cada uno con lo que vio el playtest.

const PermissionRequest := preload("../../../session/permission_request.gd")
const PlanApproval := preload("../../../session/plan_approval.gd")
## Lo pide el dock: SessionController.approve_plan (pasa a Construir antes de contestar).
const ACTION_APPROVE_PLAN := "approve_plan"
## Segunda opinión sobre el plan (m11-28): el dock le suma la pestaña y la pasa al plugin.
const ACTION_SECOND_OPINION := "second_opinion"
const PLAN_MAX_HEIGHT_PX := 280
const EDITOR_HEIGHT_PX := 260

var _panel: PanelContainer
var _title: Label
var _plan_scroll: ScrollContainer
var _plan_label: RichTextLabel
var _plan_toggle: Button
var _buttons: HFlowContainer
var _approve: Button
var _edit_box: VBoxContainer
var _editor: CodeEdit
var _counts: Label
var _send_edit: Button
var _reason_row: HBoxContainer
var _reason_edit: LineEdit
var _result: Label
var _verify_box: VBoxContainer
var _verify_check: CheckBox
var _verify_cost: Label
var _criteria_box: VBoxContainer
var _expanded: bool = false
var _rendered_plan: String = ""
var _focused_once: bool = false


func _build() -> void:
	_panel = PanelContainer.new()
	add_child(_panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override(&"separation", AgentTheme.px(6))
	_panel.add_child(column)
	var header := HBoxContainer.new()
	column.add_child(header)
	var icon := TextureRect.new()
	icon.texture = AgentTheme.icon(&"FileList")
	icon.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	icon.modulate = accent
	header.add_child(icon)
	_title = Label.new()
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title.add_theme_color_override(&"font_color", accent)
	header.add_child(_title)

	_plan_scroll = ScrollContainer.new()
	_plan_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(_plan_scroll)
	_plan_label = make_rich_label()
	_plan_label.resized.connect(_fit_plan)
	_plan_scroll.add_child(_plan_label)
	_plan_toggle = Button.new()
	_plan_toggle.flat = true
	_plan_toggle.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_plan_toggle.add_theme_color_override(&"font_color", AgentTheme.MUTED)
	_plan_toggle.pressed.connect(func() -> void:
		_expanded = not _expanded
		_fit_plan())
	column.add_child(_plan_toggle)

	_edit_box = VBoxContainer.new()
	_edit_box.visible = false
	column.add_child(_edit_box)
	_counts = Label.new()
	_counts.add_theme_color_override(&"font_color", AgentTheme.MUTED)
	_edit_box.add_child(_counts)
	_editor = CodeEdit.new()
	_editor.custom_minimum_size.y = AgentTheme.px(EDITOR_HEIGHT_PX)
	_editor.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_editor.add_theme_font_override(&"font", AgentTheme.mono_font())
	_editor.add_theme_font_size_override(&"font_size", AgentTheme.mono_font_size())
	_editor.text_changed.connect(_refresh_counts)
	_edit_box.add_child(_editor)
	var edit_buttons := HFlowContainer.new()
	_edit_box.add_child(edit_buttons)
	_send_edit = Button.new()
	_send_edit.text = I18n.t("Send changes")
	_send_edit.tooltip_text = I18n.t("The agent gets the changed lines and the whole plan, and presents it again.")
	AgentTheme.style_accent_button(_send_edit, accent)
	_send_edit.pressed.connect(_on_send_edit)
	edit_buttons.add_child(_send_edit)
	var cancel_edit := Button.new()
	cancel_edit.text = I18n.t("Cancel")
	cancel_edit.flat = true
	cancel_edit.pressed.connect(_close_editor)
	edit_buttons.add_child(cancel_edit)

	_reason_row = HBoxContainer.new()
	_reason_row.visible = false
	column.add_child(_reason_row)
	_reason_edit = LineEdit.new()
	_reason_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_reason_edit.placeholder_text = I18n.t("What should change in the plan?")
	_reason_edit.text_submitted.connect(func(_text: String) -> void: _on_send_reason())
	_reason_edit.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
			_reason_row.visible = false
			_buttons.visible = true
			_reason_edit.accept_event())
	_reason_row.add_child(_reason_edit)
	var send_reason := Button.new()
	send_reason.text = I18n.t("Send")
	send_reason.pressed.connect(_on_send_reason)
	_reason_row.add_child(send_reason)

	_verify_box = VBoxContainer.new()
	_verify_box.add_theme_constant_override(&"separation", 0)
	column.add_child(_verify_box)
	_verify_check = CheckBox.new()
	_verify_check.name = "VerifyCriteria"
	_verify_check.toggled.connect(func(on: bool) -> void:
		if request().is_pending():
			request().verify_criteria = 1 if on else 0
			_refresh_cost())
	_verify_box.add_child(_verify_check)
	_verify_cost = Label.new()
	_verify_cost.name = "VerifyCost"
	_verify_cost.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_verify_cost.add_theme_color_override(&"font_color", AgentTheme.MUTED)
	_verify_box.add_child(_verify_cost)
	_criteria_box = VBoxContainer.new()
	_criteria_box.name = "CriteriaResults"
	_criteria_box.add_theme_constant_override(&"separation", AgentTheme.px(2))
	column.add_child(_criteria_box)

	_buttons = HFlowContainer.new()
	column.add_child(_buttons)
	_approve = Button.new()
	_approve.text = I18n.t("Approve and build")
	_approve.tooltip_text = I18n.t("Switches to Build mode: the agent starts implementing, and its edits ask for permission as usual in Build.")
	AgentTheme.style_accent_button(_approve, accent)
	_approve.pressed.connect(func() -> void:
		if request().is_pending():
			action_requested.emit(ACTION_APPROVE_PLAN, request()))
	_buttons.add_child(_approve)
	var edit := Button.new()
	edit.text = I18n.t("Edit")
	edit.tooltip_text = I18n.t("Change the plan yourself; the agent gets your changes and presents it again.")
	edit.pressed.connect(_open_editor)
	_buttons.add_child(edit)
	var keep := Button.new()
	keep.text = I18n.t("Keep planning…")
	keep.tooltip_text = I18n.t("Don't approve: tell the agent what to change, and it keeps planning.")
	keep.flat = true
	keep.pressed.connect(func() -> void:
		_buttons.visible = false
		_reason_row.visible = true
		_reason_edit.grab_focus())
	_buttons.add_child(keep)
	var second := Button.new()
	second.name = "SecondOpinion"
	second.text = I18n.t("Second opinion…")
	second.tooltip_text = I18n.t("Another agent reviews this plan, read only and without this conversation. The card keeps waiting.")
	second.flat = true
	second.pressed.connect(func() -> void:
		if request().is_pending():
			action_requested.emit(ACTION_SECOND_OPINION, {"plan": request().plan_text}))
	_buttons.add_child(second)

	_result = Label.new()
	_result.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_result.add_theme_color_override(&"font_color", AgentTheme.MUTED)
	column.add_child(_result)


func request() -> PermissionRequest:
	return entry.permission


func _ready() -> void:
	super()
	if not request().changed.is_connected(refresh):
		request().changed.connect(refresh)


## Los criterios jugables del plan como se ve en la tarjeta.
func criteria() -> PackedStringArray:
	var req := request()
	return PlanApproval.criteria(req.edited_plan if not req.edited_plan.is_empty() else req.plan_text)


func _refresh_cost() -> void:
	var count := criteria().size()
	var limit := maxi(1, request().criteria_max)
	var played := mini(count, limit)
	var text := I18n.t("Each criterion is one playtest: after the build, an agent plays the game %d times.") % played if _verify_check.button_pressed else I18n.t("Each criterion would be one playtest after the build.")
	if count > limit:
		text += " " + I18n.t("Up to %d per plan (change it in Settings); the rest can be verified later.") % limit
	else:
		text += " " + I18n.t("Up to %d per plan; change it in Settings.") % limit
	_verify_cost.text = text


## Una línea por criterio verificado: marca, número y texto; lo que vio el playtest en el tooltip.
func _refresh_criteria() -> void:
	var results: Array = request().criteria_results
	_criteria_box.visible = not results.is_empty()
	while _criteria_box.get_child_count() < results.size():
		var label := Label.new()
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.mouse_filter = Control.MOUSE_FILTER_PASS
		_criteria_box.add_child(label)
	var number := 0
	for i: int in _criteria_box.get_child_count():
		var label: Label = _criteria_box.get_child(i)
		label.visible = i < results.size()
		if not label.visible:
			continue
		var item: Dictionary = results[i]
		var status := str(item.status)
		var name := I18n.t(str(item.name))
		if str(item.name).begins_with("Criterion "):
			number += 1
			name = I18n.t("Criterion %d") % number
		var state := criterion_state(status)
		label.text = "%s %s · %s%s" % [criterion_mark(status), name, item.goal, (" — " + state) if not state.is_empty() else ""]
		label.add_theme_color_override(&"font_color", {"pass": AgentTheme.ADDED, "fail": AgentTheme.REMOVED, "retest": AgentTheme.REMOVED}.get(status, AgentTheme.MUTED))
		var tip: PackedStringArray = []
		if not str(item.summary).is_empty():
			tip.append(str(item.summary))
		for evidence: Variant in item.get("evidence", []):
			tip.append("• " + str(evidence))
		label.tooltip_text = "\n".join(tip)


static func criterion_mark(status: String) -> String:
	return {"pass": "✓", "fail": "✗", "retest": "✗", "pending": "…", "skipped": "·"}.get(status, "⊘")


static func criterion_state(status: String) -> String:
	match status:
		"pending":
			return I18n.t("waiting to be played")
		"retest":
			return I18n.t("failed, being fixed and played again")
		"blocked":
			return I18n.t("couldn't be tested")
		"skipped":
			return I18n.t("not played (over the limit)")
	return ""


func refresh() -> void:
	var req := request()
	var pending := req.is_pending()
	_panel.add_theme_stylebox_override(&"panel", AgentTheme.panel(
		Color(accent, 0.10 if pending else 0.03), Color(accent, 0.8 if pending else 0.25), 6, 8))
	_title.text = I18n.t("Plan ready to build") if pending else I18n.t("Plan")
	var shown := req.edited_plan if not req.edited_plan.is_empty() else req.plan_text
	if shown != _rendered_plan:
		_rendered_plan = shown
		_plan_label.text = markdown.convert(shown) if markdown else shown
	var count := criteria().size()
	_verify_box.visible = pending and count > 0
	if _verify_box.visible:
		_verify_check.text = I18n.t("Verify the criteria by playing (%d)") % count
		_verify_check.set_pressed_no_signal(req.verify_criteria != 0)
		_verify_check.tooltip_text = I18n.t("After the build, an agent plays the game once per acceptance criterion («WHEN …, THE GAME SHALL …»). What fails goes back to the agent to fix, and is played again.")
		_refresh_cost()
	_refresh_criteria()
	if not pending:
		_edit_box.visible = false
		_reason_row.visible = false
		_buttons.visible = false
		if _expanded and not _result.visible:
			_expanded = false  # recién contestada: se pliega
		_result.visible = true
		_result.text = result_text(req)
	else:
		_result.visible = false
		_buttons.visible = not _edit_box.visible and not _reason_row.visible
		_approve.disabled = req.option_id_for([PermissionRequest.KIND_ALLOW_ONCE, PermissionRequest.KIND_ALLOW_ALWAYS]).is_empty()
		_focus_primary.call_deferred()
	_fit_plan()


## Pendiente: el plan en una caja de alto acotado con «Mostrar todo». Contestada: plegado, a pedido.
func _fit_plan() -> void:
	if not is_instance_valid(_plan_scroll) or _result == null:
		return
	var pending := request().is_pending()
	var editing := _edit_box.visible
	var content := _plan_label.get_content_height()
	var max_height := AgentTheme.px(PLAN_MAX_HEIGHT_PX)
	var overflows := content > max_height
	_plan_scroll.visible = not editing and (pending or _expanded)
	if _expanded or not overflows:
		_plan_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		_plan_scroll.custom_minimum_size.y = 0
	else:
		_plan_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
		_plan_scroll.custom_minimum_size.y = max_height
	var lines := _rendered_plan.strip_edges().count("\n") + 1
	if pending:
		_plan_toggle.visible = not editing and overflows
		_plan_toggle.text = ("▾ " + I18n.t("Show less")) if _expanded else ("▸ " + I18n.t("Show all (%d lines)") % lines)
	else:
		_plan_toggle.visible = true
		_plan_toggle.text = ("▾ " + I18n.t("Hide the plan")) if _expanded else ("▸ " + I18n.t("Show the plan (%d lines)") % lines)


func _focus_primary() -> void:
	if _focused_once or not is_inside_tree() or not _approve.is_visible_in_tree():
		return
	_focused_once = true
	var owner_focus := get_viewport().gui_get_focus_owner()
	if owner_focus is TextEdit or owner_focus is LineEdit:
		return
	_approve.grab_focus()


func _open_editor() -> void:
	if not request().is_pending():
		return
	_editor.text = request().plan_text
	_edit_box.visible = true
	_buttons.visible = false
	_refresh_counts()
	_fit_plan()
	_editor.grab_focus()


func _close_editor() -> void:
	_edit_box.visible = false
	_buttons.visible = request().is_pending()
	_fit_plan()


func _refresh_counts() -> void:
	var counts := PlanApproval.change_counts(request().plan_text, _editor.text)
	var changed: bool = counts.added > 0 or counts.removed > 0
	_counts.text = I18n.t("Your changes: +%d −%d") % [counts.added, counts.removed] if changed else I18n.t("No changes yet")
	_send_edit.disabled = not changed


func _on_send_edit() -> void:
	request().submit_edited_plan(_editor.text)


func _on_send_reason() -> void:
	request().deny_with_reason(_reason_edit.text)


static func result_text(req: PermissionRequest) -> String:
	if req.withdrawn:
		return "⇄ " + I18n.t("Answered elsewhere: from Remote Control, or no longer needed")
	if req.outcome.get("outcome") != "selected":
		return "⊘ " + I18n.t("Cancelled")
	if req.was_allowed():
		var approved := "✓ " + (I18n.t("Approved · building in Build mode") if req.plan_approved else I18n.t("Approved"))
		if req.plan_progress == PermissionRequest.PLAN_PROGRESS_NONE:
			approved += "\n" + I18n.t("Progress not tracked: the agent didn't send its task list while building.")
		return approved
	if not req.edited_plan.is_empty():
		var counts := PlanApproval.change_counts(req.plan_text, req.edited_plan)
		if req.from_block:
			return "✎ " + I18n.t("Edited (+%d −%d): sent to the agent") % [counts.added, counts.removed]
		return "✎ " + I18n.t("Edited (+%d −%d): the agent gets your changes when this turn ends") % [counts.added, counts.removed]
	if not req.deny_reason.is_empty():
		return "↺ " + I18n.t("Keep planning: %s") % req.deny_reason
	return "✗ " + I18n.t("Not approved")
