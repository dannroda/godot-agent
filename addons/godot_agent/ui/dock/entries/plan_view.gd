@tool
extends "entry_view.gd"
## Plan del agente, colapsable: ✓ hechas, ● en curso, ○ pendientes.

const STATUS_ICONS: Dictionary = {"completed": "✓", "in_progress": "●", "pending": "○"}

var _header: Button
var _list: RichTextLabel


func _build() -> void:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override(&"panel", AgentTheme.panel(Color(AgentTheme.dark_color(), 0.6), Color(1, 1, 1, 0.08), 6, 6))
	add_child(panel)
	var column := VBoxContainer.new()
	panel.add_child(column)
	_header = Button.new()
	_header.flat = true
	_header.toggle_mode = true
	_header.button_pressed = true
	_header.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_header.toggled.connect(func(open: bool) -> void:
		_list.visible = open
		refresh()
	)
	column.add_child(_header)
	_list = make_rich_label()
	column.add_child(_list)


func refresh() -> void:
	if _header == null:
		return
	var done := 0
	var lines: PackedStringArray = []
	for item: Variant in entry.plan:
		if not item is Dictionary:
			continue
		var status := str(item.get("status", "pending"))
		if status == "completed":
			done += 1
		var icon: String = STATUS_ICONS.get(status, "○")
		var text := MarkdownBBCode.escape(str(item.get("content", "")))
		match status:
			"completed":
				lines.append("[color=%s]%s[/color] [color=#8a8f98]%s[/color]" % [AgentTheme.color_hex(AgentTheme.ADDED), icon, text])
			"in_progress":
				lines.append("[color=%s]%s[/color] [b]%s[/b]" % [AgentTheme.color_hex(accent), icon, text])
			_:
				lines.append("[color=#8a8f98]%s[/color] %s" % [icon, text])
	_header.text = "%s Plan · %d/%d" % ["▾" if _header.button_pressed else "▸", done, lines.size()]
	_list.text = "\n".join(lines)
