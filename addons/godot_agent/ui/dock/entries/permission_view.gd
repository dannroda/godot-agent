@tool
extends "entry_view.gd"
## Tarjeta de permiso (mockup: borde y fondo de acento, escudo + "Permiso: …", descripción y las
## opciones del agente como botones). Cuando se resuelve, queda una línea con el resultado.

const PermissionRequest := preload("../../../session/permission_request.gd")
const PermissionPolicy := preload("../../../session/permission_policy.gd")
const DiffCard := preload("diff_card.gd")
## Orden de los botones sin importar cómo los mande el agente (m12-10): primero lo seguro.
const KIND_ORDER: PackedStringArray = [PermissionRequest.KIND_ALLOW_ONCE, PermissionRequest.KIND_REJECT_ONCE, PermissionRequest.KIND_ALLOW_ALWAYS, PermissionRequest.KIND_REJECT_ALWAYS]

## `(id: String) -> ToolCall`: si la herramienta del pedido ya muestra su diff, acá queda plegado.
var tool_call_lookup: Callable

var _panel: PanelContainer
var _title: Label
var _description: Label
var _diff_slot: VBoxContainer
var _buttons: HFlowContainer
## Modo Auto (D57): patrón editable + «Permitir siempre», que lo agrega a la allowlist.
var _rule_row: HBoxContainer
var _rule_edit: LineEdit
## MCP server de terceros (m7-35): «Permitir siempre en este proyecto» para el modo actual.
var _persist: Button
var _result: Label
var _focused_once: bool = false
## «Denegar con motivo…» (m11-48 (2), en m11-22): el motivo sale como prompt al terminar el turno.
var _reason_row: HBoxContainer
var _reason_edit: LineEdit
## Un comando largo (un heredoc de cientos de líneas) dejaba los botones fuera de la vista (m17-26):
## el título va en una línea y el texto entero, plegado, en una caja con scroll.
var _full_toggle: Button
var _full_box: ScrollContainer
var _full_text: Label
const TITLE_MAX_CHARS := 140
const FULL_MAX_HEIGHT_PX := 220


func _build() -> void:
	_panel = PanelContainer.new()
	add_child(_panel)
	var column := VBoxContainer.new()
	_panel.add_child(column)
	var header := HBoxContainer.new()
	column.add_child(header)
	var shield := TextureRect.new()
	shield.texture = AgentTheme.icon(&"Lock")
	shield.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	shield.modulate = accent
	header.add_child(shield)
	_title = Label.new()
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title.add_theme_color_override(&"font_color", accent)
	header.add_child(_title)
	_description = Label.new()
	_description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_description.add_theme_color_override(&"font_color", AgentTheme.MUTED)
	column.add_child(_description)
	_full_toggle = Button.new()
	_full_toggle.flat = true
	_full_toggle.toggle_mode = true
	_full_toggle.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_full_toggle.add_theme_color_override(&"font_color", AgentTheme.MUTED)
	column.add_child(_full_toggle)
	_full_box = ScrollContainer.new()
	_full_box.visible = false
	_full_box.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_full_box.custom_minimum_size.y = AgentTheme.px(FULL_MAX_HEIGHT_PX)
	column.add_child(_full_box)
	_full_text = Label.new()
	_full_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_full_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_full_text.add_theme_font_override(&"font", AgentTheme.mono_font())
	_full_text.add_theme_font_size_override(&"font_size", AgentTheme.mono_font_size())
	_full_box.add_child(_full_text)
	_full_toggle.toggled.connect(func(open: bool) -> void:
		_full_box.visible = open
		_refresh_full_toggle())
	_diff_slot = VBoxContainer.new()
	column.add_child(_diff_slot)
	_buttons = HFlowContainer.new()
	column.add_child(_buttons)
	_rule_row = HBoxContainer.new()
	column.add_child(_rule_row)
	_rule_edit = LineEdit.new()
	_rule_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rule_edit.tooltip_text = I18n.t("Pattern for the Auto mode allowlist: * matches anything. You can review the lists in Settings → Permissions.")
	_rule_row.add_child(_rule_edit)
	var always := Button.new()
	always.text = I18n.t("Always allow")
	always.tooltip_text = _rule_edit.tooltip_text
	always.pressed.connect(_on_always_allow)
	_rule_row.add_child(always)
	_persist = Button.new()
	# Recortado: el dock puede tener 220 px (m7-23); el texto entero queda en el tooltip.
	_persist.clip_text = true
	_persist.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_persist.pressed.connect(_on_persist_allow)
	column.add_child(_persist)
	_reason_row = HBoxContainer.new()
	_reason_row.visible = false
	column.add_child(_reason_row)
	_reason_edit = LineEdit.new()
	_reason_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_reason_edit.placeholder_text = I18n.t("Why? The agent gets it right away")
	_reason_edit.text_submitted.connect(func(_text: String) -> void: _on_send_reason())
	_reason_edit.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
			_close_reason()
			_reason_edit.accept_event())
	_reason_row.add_child(_reason_edit)
	var send_reason := Button.new()
	send_reason.text = I18n.t("Deny")
	send_reason.add_theme_color_override(&"font_color", AgentTheme.ERROR)
	send_reason.pressed.connect(_on_send_reason)
	_reason_row.add_child(send_reason)
	_result = Label.new()
	_result.add_theme_color_override(&"font_color", AgentTheme.MUTED)
	_result.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_result)
	var request: PermissionRequest = entry.permission
	_rule_edit.text = request.rule_pattern
	if not request.diff.is_empty():
		var card := DiffCard.new()
		card.setup_diff(request.diff, accent)
		card.open_requested.connect(func(path: String, line: int) -> void: action_requested.emit("open_location", {"path": path, "line": line}))
		_diff_slot.add_child(card)
		# El mismo diff ya se ve en la tarjeta de la herramienta: acá plegado, a pedido.
		if _tool_shows_diff(request):
			card.visible = false
			var toggle := Button.new()
			toggle.flat = true
			toggle.alignment = HORIZONTAL_ALIGNMENT_LEFT
			toggle.text = I18n.t("Show the change")
			toggle.pressed.connect(func() -> void:
				card.visible = not card.visible
				toggle.text = I18n.t("Hide the change") if card.visible else I18n.t("Show the change"))
			_diff_slot.add_child(toggle)
			_diff_slot.move_child(toggle, 0)


## La primera línea, hasta TITLE_MAX_CHARS, con «…» si se cortó.
static func short_text(text: String) -> String:
	var clean := text.strip_edges()
	var first := clean.get_slice("\n", 0)
	if first.length() > TITLE_MAX_CHARS:
		return first.left(TITLE_MAX_CHARS).strip_edges() + "…"
	return first + (" …" if first != clean else "")


func _refresh_full_toggle() -> void:
	var lines := _full_text.text.count("\n") + 1
	var label := I18n.t("Show all (1 line)") if lines == 1 else I18n.t("Show all (%d lines)") % lines
	_full_toggle.text = ("▾ " if _full_toggle.button_pressed else "▸ ") + label


func refresh() -> void:
	var request: PermissionRequest = entry.permission
	var pending := request.is_pending()
	_panel.add_theme_stylebox_override(&"panel", AgentTheme.panel(
		Color(accent, 0.10 if pending else 0.03), Color(accent, 0.8 if pending else 0.25), 6, 8
	))
	var group_label := PermissionPolicy.group_label(request.group)
	_title.text = I18n.t("Permission: %s") % short_text(request.title)
	_title.tooltip_text = I18n.t("Group: %s") % group_label
	_description.text = short_text(request.description)
	_description.visible = not request.description.is_empty() and request.description != request.title
	# Lo que no entró en el título o la descripción va entero, plegado.
	var full := request.title if short_text(request.title) != request.title else ""
	if short_text(request.description) != request.description and request.description != request.title:
		full = (full + "\n\n" if not full.is_empty() else "") + request.description
	_full_text.text = full
	_full_toggle.visible = not full.is_empty()
	if full.is_empty():
		_full_box.visible = false
	_refresh_full_toggle()
	for child: Node in _buttons.get_children():
		child.queue_free()
	_buttons.visible = pending and not _reason_row.visible
	if not pending:
		_reason_row.visible = false
	_rule_row.visible = pending and not request.rule_pattern.is_empty()
	_persist.visible = pending and not request.persist_label.is_empty()
	_persist.text = request.persist_label
	_persist.tooltip_text = "%s\n%s" % [request.persist_label, I18n.t("Saved in the permission matrix of this project: you can change it in Settings → Permissions.")]
	_result.visible = not pending
	if not pending:
		_result.text = _result_text(request)
		return
	for option: Dictionary in sorted_options(request.options):
		_buttons.add_child(_option_button(request, option))
	if not request.option_id_for([PermissionRequest.KIND_REJECT_ONCE, PermissionRequest.KIND_REJECT_ALWAYS]).is_empty():
		var with_reason := Button.new()
		with_reason.text = I18n.t("Deny with reason…")
		with_reason.tooltip_text = I18n.t("Deny and tell the agent why: the turn stops and your reason is sent right away.")
		with_reason.flat = true
		with_reason.add_theme_color_override(&"font_color", AgentTheme.MUTED)
		with_reason.pressed.connect(_open_reason)
		_buttons.add_child(with_reason)
	_focus_primary.call_deferred()


func _open_reason() -> void:
	_buttons.visible = false
	_reason_row.visible = true
	_reason_edit.grab_focus()


func _close_reason() -> void:
	_reason_row.visible = false
	_buttons.visible = (entry.permission as PermissionRequest).is_pending()


func _on_send_reason() -> void:
	(entry.permission as PermissionRequest).deny_with_reason(_reason_edit.text)


## Las opciones en KIND_ORDER; las de kind desconocido, al final en el orden del agente.
static func sorted_options(options: Array) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for kind: String in KIND_ORDER:
		for option: Variant in options:
			if option is Dictionary and str(option.get("kind", "")) == kind:
				result.append(option)
	for option: Variant in options:
		if option is Dictionary and not str(option.get("kind", "")) in KIND_ORDER:
			result.append(option)
	return result


## Una vez, al aparecer: el foco va a «Permitir» (Enter lo acepta) salvo que se esté escribiendo.
## Esc deniega solo con el foco en la tarjeta: en el composer, Esc detiene el turno.
func _focus_primary() -> void:
	if _focused_once or _buttons.get_child_count() == 0 or not is_inside_tree():
		return
	_focused_once = true
	var owner_focus := get_viewport().gui_get_focus_owner()
	if owner_focus is TextEdit or owner_focus is LineEdit:
		return
	(_buttons.get_child(0) as Button).grab_focus()


func _tool_shows_diff(request: PermissionRequest) -> bool:
	if request.tool_call_id.is_empty() or not tool_call_lookup.is_valid():
		return false
	var call: Object = tool_call_lookup.call(request.tool_call_id)
	return call != null and not (call.call(&"diffs") as Array).is_empty()


func _on_always_allow() -> void:
	var request: PermissionRequest = entry.permission
	var pattern := _rule_edit.text.strip_edges()
	if pattern.is_empty() or not request.is_pending():
		return
	request.rule_to_add = {"pattern": pattern, "list": "allow"}
	request.select(request.option_id_for([PermissionRequest.KIND_ALLOW_ONCE]))


func _on_persist_allow() -> void:
	var request: PermissionRequest = entry.permission
	if not request.is_pending():
		return
	request.persist_allow = true
	request.select(request.option_id_for([PermissionRequest.KIND_ALLOW_ONCE, PermissionRequest.KIND_ALLOW_ALWAYS]))


func _option_button(request: PermissionRequest, option: Dictionary) -> Button:
	var button := Button.new()
	var kind := str(option.get("kind", ""))
	button.text = _option_label(option)
	match kind:
		PermissionRequest.KIND_ALLOW_ONCE:
			AgentTheme.style_accent_button(button, accent)
		PermissionRequest.KIND_REJECT_ONCE, PermissionRequest.KIND_REJECT_ALWAYS:
			button.flat = true
			button.add_theme_color_override(&"font_color", AgentTheme.ERROR)
			if kind == PermissionRequest.KIND_REJECT_ONCE:
				var shortcut := Shortcut.new()
				var esc := InputEventKey.new()
				esc.keycode = KEY_ESCAPE
				shortcut.events = [esc]
				button.shortcut = shortcut
				button.shortcut_context = _panel  # solo con el foco en la tarjeta
				button.shortcut_in_tooltip = true
		PermissionRequest.KIND_ALLOW_ALWAYS:
			button.flat = true
	button.pressed.connect(func() -> void: request.select(str(option.get("optionId", ""))))
	return button


## Nombres del mockup para las opciones típicas; si no, el nombre que mandó el agente.
static func _option_label(option: Dictionary) -> String:
	match str(option.get("kind", "")):
		PermissionRequest.KIND_ALLOW_ONCE:
			return I18n.t("Allow once")
		PermissionRequest.KIND_ALLOW_ALWAYS:
			return I18n.t("Always allow in this session")
		PermissionRequest.KIND_REJECT_ONCE:
			return I18n.t("Deny")
	return str(option.get("name", option.get("optionId", "?")))


static func _result_text(request: PermissionRequest) -> String:
	if request.withdrawn:
		return "⇄ " + I18n.t("Answered elsewhere: from Remote Control, or no longer needed")
	if request.outcome.get("outcome") != "selected":
		return "⊘ " + I18n.t("Permission cancelled")
	if request.persist_allow and request.was_allowed():
		return "✓ " + I18n.t("Allowed · saved in the permissions of this project")
	if not request.rule_to_add.is_empty() and request.was_allowed():
		return "✓ " + I18n.t("Allowed · «%s» added to the Auto allowlist") % str(request.rule_to_add.get("pattern", ""))
	match request.chosen_kind:
		PermissionRequest.KIND_ALLOW_ONCE:
			return "✓ " + I18n.t("Allowed once")
		PermissionRequest.KIND_ALLOW_ALWAYS:
			return "✓ " + I18n.t("Allowed in this session")
	if not request.deny_reason.is_empty():
		return "✗ " + I18n.t("Denied: %s") % request.deny_reason
	return "✗ " + I18n.t("Denied")
