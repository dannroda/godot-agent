@tool
extends "entry_view.gd"
## Texto del agente (Markdown → BBCode, sin burbuja). Los bloques de código van en su propia caja
## (con copiar), entre los tramos de texto. Los thoughts se muestran colapsados, en un solo label.
## El streaming refresca muchas veces por segundo: la conversión se agrupa una vez por frame y los
## controles de cada tramo se reusan mientras no cambie de tipo. En Revisar, el bloque `findings`
## que el harness ya leyó va plegado detrás de una línea con la cantidad (m12-38).

const CodeBlockView := preload("../../markdown/code_block_view.gd")
const FindingsParser := preload("../../../review/findings_parser.gd")

enum SegmentKind { TEXT, CODE, FINDINGS }

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
	# Sin caja (m12-17): el texto del agente se lee como texto; las cajas quedan para el código,
	# las herramientas y las tarjetas que piden algo.
	var frame := PanelContainer.new()
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
		var kind := SegmentKind.TEXT
		if block.has("code"):
			kind = SegmentKind.FINDINGS if entry.findings_count >= 0 and FindingsParser.is_findings_block(block.code) else SegmentKind.CODE
		var child: Control = _segments.get_child(i) if i < _segments.get_child_count() else null
		if child != null and _kind_of(child) != kind:
			_segments.remove_child(child)
			child.queue_free()
			child = null
		if child == null:
			match kind:
				SegmentKind.CODE:
					child = CodeBlockView.new()
				SegmentKind.FINDINGS:
					child = _make_findings_fold()
				_:
					child = _make_text_label()
					child.add_theme_stylebox_override(&"normal", StyleBoxEmpty.new())
			_segments.add_child(child)
			_segments.move_child(child, i)
		match kind:
			SegmentKind.CODE:
				(child as CodeBlockView).set_code(block.code, block.language, markdown)
			SegmentKind.FINDINGS:
				_update_findings_fold(child, block)
			_:
				if (child as RichTextLabel).text != block.bbcode:
					(child as RichTextLabel).text = block.bbcode
	while _segments.get_child_count() > blocks.size():
		var extra := _segments.get_child(_segments.get_child_count() - 1)
		_segments.remove_child(extra)
		extra.queue_free()


func _kind_of(child: Control) -> SegmentKind:
	if child.has_meta(&"findings_fold"):
		return SegmentKind.FINDINGS
	return SegmentKind.CODE if child is CodeBlockView else SegmentKind.TEXT


## Una línea «▸ 2 findings · …» que abre el JSON en su caja de código.
func _make_findings_fold() -> VBoxContainer:
	var fold := VBoxContainer.new()
	fold.set_meta(&"findings_fold", true)
	var toggle := Button.new()
	toggle.flat = true
	toggle.toggle_mode = true
	toggle.alignment = HORIZONTAL_ALIGNMENT_LEFT
	toggle.clip_text = true
	toggle.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	toggle.tooltip_text = I18n.t("Show the JSON the agent wrote")
	toggle.add_theme_color_override(&"font_color", AgentTheme.MUTED)
	fold.add_child(toggle)
	var code := CodeBlockView.new()
	code.visible = false
	fold.add_child(code)
	toggle.toggled.connect(func(open: bool) -> void:
		code.visible = open
		toggle.text = _findings_fold_text(open))
	return fold


func _update_findings_fold(fold: Control, block: Dictionary) -> void:
	var toggle := fold.get_child(0) as Button
	toggle.text = _findings_fold_text(toggle.button_pressed)
	(fold.get_child(1) as CodeBlockView).set_code(block.code, block.language, markdown)


func _findings_fold_text(open: bool) -> String:
	var count := entry.findings_count
	var summary := (I18n.t("%d finding · in the Review panel and the Script Editor") if count == 1 else I18n.t("%d findings · in the Review panel and the Script Editor")) % count
	return ("▾ " if open else "▸ ") + summary


func _make_text_label() -> RichTextLabel:
	var label := make_rich_label()
	label.meta_clicked.connect(_on_meta_clicked)
	return label


func _update_toggle_text() -> void:
	var first_line := entry.text.strip_edges().get_slice("\n", 0).left(60)
	_toggle.text = ("▾ " if _toggle.button_pressed else "▸ ") + I18n.t("Thinking") + ("" if _toggle.button_pressed else ": " + first_line)


func _on_meta_clicked(meta: Variant) -> void:
	action_requested.emit("open_link", str(meta))
