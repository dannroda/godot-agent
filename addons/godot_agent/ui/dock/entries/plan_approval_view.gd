@tool
extends "entry_view.gd"
## Tarjeta del plan que presenta el agente desde su modo plan (m11-22, ExitPlanMode): el plan en
## markdown y «Aprobar y construir» · «Editar» · «Seguir planeando…». Editar cambia la vista por el
## texto con un contador +N −M en vivo; lo editado y el motivo vuelven al agente al terminar el turno.
## No vence. Contestada, queda plegada con el resultado y el plan a pedido.

const PermissionRequest := preload("../../../session/permission_request.gd")
const PlanApproval := preload("../../../session/plan_approval.gd")
## Lo pide el dock: SessionController.approve_plan (pasa a Construir antes de contestar).
const ACTION_APPROVE_PLAN := "approve_plan"
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

	_result = Label.new()
	_result.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_result.add_theme_color_override(&"font_color", AgentTheme.MUTED)
	column.add_child(_result)


func request() -> PermissionRequest:
	return entry.permission


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
		return "✓ " + (I18n.t("Approved · building in Build mode") if req.plan_approved else I18n.t("Approved"))
	if not req.edited_plan.is_empty():
		var counts := PlanApproval.change_counts(req.plan_text, req.edited_plan)
		return "✎ " + I18n.t("Edited (+%d −%d): the agent gets your changes when this turn ends") % [counts.added, counts.removed]
	if not req.deny_reason.is_empty():
		return "↺ " + I18n.t("Keep planning: %s") % req.deny_reason
	return "✗ " + I18n.t("Not approved")
