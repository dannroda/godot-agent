@tool
extends "entry_view.gd"
## Tarjeta de permiso (mockup: borde y fondo de acento, escudo + "Permiso: …", descripción y las
## opciones del agente como botones). Cuando se resuelve, queda una línea con el resultado.

const PermissionRequest := preload("../../../session/permission_request.gd")
const PermissionPolicy := preload("../../../session/permission_policy.gd")
const DiffCard := preload("diff_card.gd")

var _panel: PanelContainer
var _title: Label
var _description: Label
var _diff_slot: VBoxContainer
var _buttons: HFlowContainer
var _result: Label


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
	_diff_slot = VBoxContainer.new()
	column.add_child(_diff_slot)
	_buttons = HFlowContainer.new()
	column.add_child(_buttons)
	_result = Label.new()
	_result.add_theme_color_override(&"font_color", AgentTheme.MUTED)
	column.add_child(_result)
	var request: PermissionRequest = entry.permission
	if not request.diff.is_empty():
		var card := DiffCard.new()
		card.setup_diff(request.diff, accent)
		card.open_requested.connect(func(path: String, line: int) -> void: action_requested.emit("open_location", {"path": path, "line": line}))
		_diff_slot.add_child(card)


func refresh() -> void:
	var request: PermissionRequest = entry.permission
	var pending := request.is_pending()
	_panel.add_theme_stylebox_override(&"panel", AgentTheme.panel(
		Color(accent, 0.10 if pending else 0.03), Color(accent, 0.8 if pending else 0.25), 6, 8
	))
	var group_label: String = PermissionPolicy.GROUP_LABELS.get(request.group, request.group)
	_title.text = "Permiso: %s" % request.title
	_title.tooltip_text = "Grupo: %s" % group_label
	_description.text = request.description
	_description.visible = not request.description.is_empty() and request.description != request.title
	for child: Node in _buttons.get_children():
		child.queue_free()
	_buttons.visible = pending
	_result.visible = not pending
	if not pending:
		_result.text = _result_text(request)
		return
	for option: Variant in request.options:
		if option is Dictionary:
			_buttons.add_child(_option_button(request, option))


func _option_button(request: PermissionRequest, option: Dictionary) -> Button:
	var button := Button.new()
	var kind := str(option.get("kind", ""))
	button.text = _option_label(option)
	match kind:
		PermissionRequest.KIND_ALLOW_ONCE:
			button.add_theme_stylebox_override(&"normal", AgentTheme.panel(accent, Color.TRANSPARENT, 4, 5))
			button.add_theme_stylebox_override(&"hover", AgentTheme.panel(accent.lightened(0.15), Color.TRANSPARENT, 4, 5))
			button.add_theme_color_override(&"font_color", Color("#1d1d1d"))
			button.add_theme_color_override(&"font_hover_color", Color("#1d1d1d"))
		PermissionRequest.KIND_REJECT_ONCE, PermissionRequest.KIND_REJECT_ALWAYS:
			button.flat = true
			button.add_theme_color_override(&"font_color", AgentTheme.ERROR)
	button.pressed.connect(func() -> void: request.select(str(option.get("optionId", ""))))
	return button


## Nombres del mockup para las opciones típicas; si no, el nombre que mandó el agente.
static func _option_label(option: Dictionary) -> String:
	match str(option.get("kind", "")):
		PermissionRequest.KIND_ALLOW_ONCE:
			return "Permitir una vez"
		PermissionRequest.KIND_ALLOW_ALWAYS:
			return "Siempre en esta sesión"
		PermissionRequest.KIND_REJECT_ONCE:
			return "Denegar"
	return str(option.get("name", option.get("optionId", "?")))


static func _result_text(request: PermissionRequest) -> String:
	if request.outcome.get("outcome") != "selected":
		return "⊘ Permiso cancelado"
	match request.chosen_kind:
		PermissionRequest.KIND_ALLOW_ONCE:
			return "✓ Permitido una vez"
		PermissionRequest.KIND_ALLOW_ALWAYS:
			return "✓ Permitido en esta sesión"
	return "✗ Denegado"
