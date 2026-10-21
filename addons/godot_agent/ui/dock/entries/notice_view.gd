@tool
extends "entry_view.gd"
## Aviso del harness (cancelación, errores de transporte…) con acciones concretas (spec §15).

var _panel: PanelContainer
var _label: Label
var _actions: HBoxContainer


func _build() -> void:
	_panel = PanelContainer.new()
	add_child(_panel)
	var column := VBoxContainer.new()
	_panel.add_child(column)
	_label = Label.new()
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_label)
	_actions = HBoxContainer.new()
	_actions.alignment = BoxContainer.ALIGNMENT_END
	column.add_child(_actions)


func refresh() -> void:
	var color := AgentTheme.MUTED
	match entry.level:
		ChatEntry.Level.WARNING:
			color = AgentTheme.WARNING
		ChatEntry.Level.ERROR:
			color = AgentTheme.ERROR
	var bg := Color(color, 0.08) if entry.level != ChatEntry.Level.INFO else Color.TRANSPARENT
	_panel.add_theme_stylebox_override(&"panel", AgentTheme.panel(bg, Color(color, 0.5) if bg.a > 0.0 else Color.TRANSPARENT, 6, 6))
	_label.text = entry.text
	_label.add_theme_color_override(&"font_color", color if entry.level != ChatEntry.Level.INFO else AgentTheme.MUTED)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER if entry.level == ChatEntry.Level.INFO else HORIZONTAL_ALIGNMENT_LEFT
	for child: Node in _actions.get_children():
		child.queue_free()
	for action: Dictionary in entry.actions:
		var button := Button.new()
		button.text = str(action.get("label", action.get("id", "")))
		button.pressed.connect(func() -> void: action_requested.emit(str(action.id), entry))
		_actions.add_child(button)
	_actions.visible = not entry.actions.is_empty()
