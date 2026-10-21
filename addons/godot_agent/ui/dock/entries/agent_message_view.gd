@tool
extends "entry_view.gd"
## Texto del agente (Markdown → BBCode, sin burbuja). Los thoughts se muestran colapsados.
## El streaming refresca muchas veces por segundo: la conversión se agrupa una vez por frame.

var _toggle: Button
var _label: RichTextLabel
var _dirty: bool = false


func _build() -> void:
	if entry.kind == ChatEntry.Kind.THOUGHT:
		_toggle = Button.new()
		_toggle.flat = true
		_toggle.toggle_mode = true
		_toggle.alignment = HORIZONTAL_ALIGNMENT_LEFT
		_toggle.add_theme_color_override(&"font_color", AgentTheme.MUTED)
		_toggle.toggled.connect(func(open: bool) -> void:
			_label.visible = open
			_update_toggle_text()
		)
		add_child(_toggle)
	_label = make_rich_label()
	_label.meta_clicked.connect(_on_meta_clicked)
	if entry.kind == ChatEntry.Kind.THOUGHT:
		_label.visible = false
		_label.add_theme_color_override(&"default_color", AgentTheme.MUTED)
	add_child(_label)


func refresh() -> void:
	if _dirty:
		return
	_dirty = true
	_flush.call_deferred()


func _flush() -> void:
	_dirty = false
	if not is_instance_valid(_label):
		return
	_label.text = markdown.convert(entry.text)
	if _toggle:
		_update_toggle_text()


func _update_toggle_text() -> void:
	var first_line := entry.text.strip_edges().get_slice("\n", 0).left(60)
	_toggle.text = ("▾ " if _toggle.button_pressed else "▸ ") + "Pensamiento" + ("" if _toggle.button_pressed else ": " + first_line)


func _on_meta_clicked(meta: Variant) -> void:
	action_requested.emit("open_link", str(meta))
