@tool
extends "entry_view.gd"
## Texto del agente (Markdown → BBCode, sin burbuja). Los bloques de código van en su propia caja
## (con copiar), entre los tramos de texto. Los thoughts se muestran colapsados, en un solo label.
## El streaming refresca muchas veces por segundo: la conversión se agrupa una vez por frame y los
## controles de cada tramo se reusan mientras no cambie de tipo. En Revisar, el bloque `findings`
## que el harness ya leyó va plegado detrás de una línea con la cantidad (m12-38). En One-shot, el
## bloque de checks (y en QA puntajes y hallazgos) se pliega en un resumen legible (m17-20).

const CodeBlockView := preload("../../markdown/code_block_view.gd")
const FindingsParser := preload("../../../review/findings_parser.gd")

enum SegmentKind { TEXT, CODE, FINDINGS, CHECKS }

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
		var report: Dictionary = {}
		if block.has("code"):
			if entry.findings_count >= 0 and FindingsParser.is_findings_block(block.code):
				kind = SegmentKind.FINDINGS
			else:
				report = FindingsParser.report_block(block.code)
				kind = SegmentKind.CODE if report.is_empty() else SegmentKind.CHECKS
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
				SegmentKind.CHECKS:
					child = _make_report_fold()
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
			SegmentKind.CHECKS:
				_update_report_fold(child, block, report)
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
	if child.has_meta(&"report_fold"):
		return SegmentKind.CHECKS
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


## «▸ Checks: 6 ✓ · 1 ✗ · 2 sin verificar»: abre la lista legible; el JSON queda detrás de otro botón.
func _make_report_fold() -> VBoxContainer:
	var fold := VBoxContainer.new()
	fold.set_meta(&"report_fold", true)
	var toggle := _fold_button()
	toggle.tooltip_text = I18n.t("The checks the agent reported; the harness reads them for the One-shot")
	fold.add_child(toggle)
	var body := VBoxContainer.new()
	body.visible = false
	fold.add_child(body)
	var list := make_rich_label()
	list.add_theme_stylebox_override(&"normal", StyleBoxEmpty.new())
	body.add_child(list)
	var json_toggle := _fold_button()
	json_toggle.text = "▸ " + I18n.t("Show JSON")
	body.add_child(json_toggle)
	var code := CodeBlockView.new()
	code.visible = false
	body.add_child(code)
	toggle.toggled.connect(func(open: bool) -> void:
		body.visible = open
		toggle.text = ("▾ " if open else "▸ ") + str(fold.get_meta(&"summary", "")))
	json_toggle.toggled.connect(func(open: bool) -> void:
		code.visible = open
		json_toggle.text = ("▾ " if open else "▸ ") + I18n.t("Show JSON"))
	return fold


func _update_report_fold(fold: Control, block: Dictionary, report: Dictionary) -> void:
	var toggle := fold.get_child(0) as Button
	var body := fold.get_child(1) as Control
	var summary := report_summary(report)
	fold.set_meta(&"summary", summary)
	toggle.text = ("▾ " if toggle.button_pressed else "▸ ") + summary
	var list := body.get_child(0) as RichTextLabel
	var bbcode := report_bbcode(report)
	if list.text != bbcode:
		list.text = bbcode
	(body.get_child(2) as CodeBlockView).set_code(block.code, block.language, markdown)


## «Checks: 6 ✓ · 1 ✗ · 2 sin verificar · 4 puntajes · 3 hallazgos».
static func report_summary(report: Dictionary) -> String:
	var counts := {"pass": 0, "fail": 0, "pending": 0}
	for check: Dictionary in report.checks:
		counts[check.status] = int(counts.get(check.status, 0)) + 1
	var parts: PackedStringArray = []
	if not report.checks.is_empty():
		parts.append("%d ✓" % counts["pass"])
		parts.append("%d ✗" % counts["fail"])
		if counts["pending"] > 0:
			parts.append(I18n.t("%d unverified") % counts["pending"])
	if not report.scores.is_empty():
		parts.append(I18n.t("1 score") if report.scores.size() == 1 else I18n.t("%d scores") % report.scores.size())
	if not report.findings.is_empty():
		parts.append((I18n.t("%d finding") if report.findings.size() == 1 else I18n.t("%d findings")) % report.findings.size())
	return I18n.t("Checks: %s") % " · ".join(parts)


## La lista legible: una línea por check (con el detalle atenuado), por puntaje y por hallazgo.
static func report_bbcode(report: Dictionary) -> String:
	var muted := AgentTheme.MUTED.to_html(false)
	var lines: PackedStringArray = []
	for check: Dictionary in report.checks:
		var icon: String = {"pass": "[color=#5fb85f]✓[/color]", "fail": "[color=#e06c6c]✗[/color]"}.get(check.status, "[color=#%s]○[/color]" % muted)
		var line := "%s %s" % [icon, _escape(check.label)]
		if not str(check.detail).is_empty():
			line += " [color=#%s]— %s[/color]" % [muted, _escape(check.detail)]
		lines.append(line)
	if not report.scores.is_empty():
		lines.append("")
		for score: Dictionary in report.scores:
			var line := "[b]%s[/b] %s/10" % [_escape(score.criterion), String.num(score.score, 1).trim_suffix(".0")]
			if not str(score.reason).is_empty():
				line += " [color=#%s]— %s[/color]" % [muted, _escape(score.reason)]
			lines.append(line)
	if not report.findings.is_empty():
		lines.append("")
		for finding: Dictionary in report.findings:
			var where := str(finding.get("path", finding.get("node", "")))
			if int(finding.get("line", 0)) > 0:
				where += ":%d" % int(finding.line)
			var line := "• %s" % _escape(finding.title)
			if not where.is_empty():
				line += " [color=#%s](%s)[/color]" % [muted, _escape(where)]
			lines.append(line)
	return "\n".join(lines)


static func _escape(text: String) -> String:
	return text.replace("[", "[lb]")


func _fold_button() -> Button:
	var button := Button.new()
	button.flat = true
	button.toggle_mode = true
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.clip_text = true
	button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	button.add_theme_color_override(&"font_color", AgentTheme.MUTED)
	return button


func _make_text_label() -> RichTextLabel:
	var label := make_rich_label()
	label.meta_clicked.connect(_on_meta_clicked)
	return label


func _update_toggle_text() -> void:
	var first_line := entry.text.strip_edges().get_slice("\n", 0).left(60)
	_toggle.text = ("▾ " if _toggle.button_pressed else "▸ ") + I18n.t("Thinking") + ("" if _toggle.button_pressed else ": " + first_line)


func _on_meta_clicked(meta: Variant) -> void:
	action_requested.emit("open_link", str(meta))
