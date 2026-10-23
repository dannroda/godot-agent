@tool
extends "entry_view.gd"
## Texto del agente (Markdown → BBCode, sin burbuja). Los bloques de código van en su propia caja
## (con copiar), entre los tramos de texto. Los thoughts se muestran colapsados, en un solo label.
## El streaming refresca muchas veces por segundo: la conversión se agrupa una vez por frame y los
## controles de cada tramo se reusan mientras no cambie de tipo.

const CodeBlockView := preload("../../markdown/code_block_view.gd")

var _toggle: Button
var _label: RichTextLabel  # solo en los thoughts
var _segments: VBoxContainer
var _dirty: bool = false


func _build() -> void:
	if entry.kind == ChatEntry.EntryKind.THOUGHT:
		_toggle = Button.new()
		_toggle.flat = true
		_toggle.toggle_mode = true
		_toggle.alignment = HORIZONTAL_ALIGNMENT_LEFT
		# La primera línea del pensamiento se corta con «…»: sin esto el botón ensancha el chat.
		_toggle.clip_text = true
		_toggle.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		_toggle.add_theme_color_override(&"font_color", AgentTheme.MUTED)
		_toggle.toggled.connect(func(open: bool) -> void:
			_label.visible = open
			_update_toggle_text()
		)
		add_child(_toggle)
		_label = _make_text_label()
		_label.visible = false
		_label.add_theme_color_override(&"default_color", AgentTheme.MUTED)
		add_child(_label)
		return
	# Un solo recuadro (el estilo del RichTextLabel del editor) con los tramos adentro, sin fondo.
	var frame := PanelContainer.new()
	var theme := AgentTheme.editor_theme()
	if theme.has_stylebox(&"normal", &"RichTextLabel"):
		frame.add_theme_stylebox_override(&"panel", theme.get_stylebox(&"normal", &"RichTextLabel"))
	else:
		frame.add_theme_stylebox_override(&"panel", StyleBoxEmpty.new())
	add_child(frame)
	_segments = VBoxContainer.new()
	_segments.add_theme_constant_override(&"separation", AgentTheme.px(6))
	frame.add_child(_segments)


func refresh() -> void:
	if _dirty:
		return
	_dirty = true
	_flush.call_deferred()


func _flush() -> void:
	_dirty = false
	if _toggle:
		if is_instance_valid(_label):
			_label.text = markdown.convert(entry.text)
			_update_toggle_text()
		return
	if not is_instance_valid(_segments):
		return
	var blocks := markdown.blocks(entry.text)
	for i in blocks.size():
		var block: Dictionary = blocks[i]
		var is_code := block.has("code")
		var child: Control = _segments.get_child(i) if i < _segments.get_child_count() else null
		if child != null and (child is CodeBlockView) != is_code:
			_segments.remove_child(child)
			child.queue_free()
			child = null
		if child == null:
			child = CodeBlockView.new() if is_code else _make_text_label()
			if not is_code:
				child.add_theme_stylebox_override(&"normal", StyleBoxEmpty.new())
			_segments.add_child(child)
			_segments.move_child(child, i)
		if is_code:
			(child as CodeBlockView).set_code(block.code, block.language, markdown)
		elif (child as RichTextLabel).text != block.bbcode:
			(child as RichTextLabel).text = block.bbcode
	while _segments.get_child_count() > blocks.size():
		var extra := _segments.get_child(_segments.get_child_count() - 1)
		_segments.remove_child(extra)
		extra.queue_free()


func _make_text_label() -> RichTextLabel:
	var label := make_rich_label()
	label.meta_clicked.connect(_on_meta_clicked)
	return label


func _update_toggle_text() -> void:
	var first_line := entry.text.strip_edges().get_slice("\n", 0).left(60)
	_toggle.text = ("▾ " if _toggle.button_pressed else "▸ ") + I18n.t("Thinking") + ("" if _toggle.button_pressed else ": " + first_line)


func _on_meta_clicked(meta: Variant) -> void:
	action_requested.emit("open_link", str(meta))
