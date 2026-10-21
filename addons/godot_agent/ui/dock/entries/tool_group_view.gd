@tool
extends "entry_view.gd"
## Grupo colapsable de tool calls consecutivos: "4 herramientas · 1,2 s", cada fila con estado,
## nombre (las tools `godot.*` en violeta), resumen y ubicaciones. Los diffs van en tarjetas.

const ToolCall := preload("../../../session/tool_call.gd")
const DiffCard := preload("diff_card.gd")

const STATUS_ICONS: Dictionary = {
	ToolCall.STATUS_PENDING: "○",
	ToolCall.STATUS_IN_PROGRESS: "◐",
	ToolCall.STATUS_COMPLETED: "✓",
	ToolCall.STATUS_FAILED: "✗",
	ToolCall.STATUS_CANCELLED: "⊘",
}
const SPINNER := ["◐", "◓", "◑", "◒"]
const SUMMARY_MAX := 80
const OUTPUT_PREVIEW_LINES := 40
const OUTPUT_PREVIEW_CHARS := 4000
const IMAGE_MAX_HEIGHT := 160

## Callable(id: String) -> ToolCall, inyectado por la ConversationView.
var tool_call_lookup: Callable

var _header: Button
var _body: VBoxContainer
var _rows: Dictionary = {}  # toolCallId -> {row, status, name, summary, extra}
var _spinner_timer: Timer
var _spinner_frame: int = 0


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
	_header.add_theme_color_override(&"font_color", AgentTheme.MUTED)
	_header.toggled.connect(func(open: bool) -> void:
		_body.visible = open
		refresh()
	)
	column.add_child(_header)
	_body = VBoxContainer.new()
	column.add_child(_body)
	_spinner_timer = Timer.new()
	_spinner_timer.wait_time = 0.15
	_spinner_timer.timeout.connect(_on_spinner)
	add_child(_spinner_timer)


func refresh() -> void:
	if _header == null:
		return
	var calls := _calls()
	var running := false
	var total_msec := 0
	var failed := 0
	for call: ToolCall in calls:
		_refresh_row(call)
		running = running or not call.is_finished()
		total_msec += call.duration_msec()
		if call.status == ToolCall.STATUS_FAILED:
			failed += 1
	var noun := "herramienta" if calls.size() == 1 else "herramientas"
	var text := "%s %d %s · %s" % ["▾" if _header.button_pressed else "▸", calls.size(), noun, _format_duration(total_msec)]
	if failed > 0:
		text += " · %d con error" % failed
	_header.text = text
	if running and _spinner_timer.is_inside_tree() and _spinner_timer.is_stopped():
		_spinner_timer.start()
	elif not running:
		_spinner_timer.stop()


func _calls() -> Array[ToolCall]:
	var result: Array[ToolCall] = []
	if not tool_call_lookup.is_valid():
		return result
	for id: String in entry.tool_call_ids:
		var call: ToolCall = tool_call_lookup.call(id)
		if call:
			result.append(call)
	return result


func _refresh_row(call: ToolCall) -> void:
	var parts: Dictionary = _rows.get(call.id, {})
	if parts.is_empty():
		parts = _make_row(call)
		_rows[call.id] = parts
	var status_label: Label = parts.status
	status_label.text = SPINNER[_spinner_frame % SPINNER.size()] if call.status == ToolCall.STATUS_IN_PROGRESS else STATUS_ICONS.get(call.status, "·")
	var status_color := AgentTheme.MUTED
	match call.status:
		ToolCall.STATUS_COMPLETED:
			status_color = AgentTheme.ADDED
		ToolCall.STATUS_FAILED:
			status_color = AgentTheme.ERROR
		ToolCall.STATUS_IN_PROGRESS:
			status_color = accent
	status_label.add_theme_color_override(&"font_color", status_color)
	var name_label: Label = parts.name
	name_label.text = _short_name(call)
	name_label.add_theme_color_override(&"font_color", AgentTheme.GODOT_TOOL if call.is_godot_tool() else AgentTheme.font_color())
	var summary_label: Label = parts.summary
	summary_label.text = _summary(call)
	_refresh_extra(call, parts.extra)


func _make_row(call: ToolCall) -> Dictionary:
	var block := VBoxContainer.new()
	_body.add_child(block)
	var row := HBoxContainer.new()
	block.add_child(row)
	var status := Label.new()
	status.custom_minimum_size.x = AgentTheme.px(14)
	row.add_child(status)
	var name_label := Label.new()
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.size_flags_stretch_ratio = 0.6
	name_label.clip_text = true
	row.add_child(name_label)
	var summary := Label.new()
	summary.add_theme_color_override(&"font_color", AgentTheme.MUTED)
	summary.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	summary.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	summary.clip_text = true
	row.add_child(summary)
	var undo := Button.new()
	undo.flat = true
	undo.text = "↶ undo"
	undo.visible = false
	undo.tooltip_text = "Deshacer en el editor (Ctrl+Z)"
	undo.pressed.connect(func() -> void: action_requested.emit("undo_tool_call", call.id))
	row.add_child(undo)
	var extra := VBoxContainer.new()
	block.add_child(extra)
	return {"row": row, "status": status, "name": name_label, "summary": summary, "extra": extra, "undo": undo}


## Contenido del tool call: diffs como tarjetas, texto breve, terminal "no soportado", ubicaciones.
func _refresh_extra(call: ToolCall, extra: VBoxContainer) -> void:
	var signature := "%s|%d|%d" % [call.status, str(call.content).hash(), call.locations.size()]
	if extra.get_meta(&"signature", "") == signature:
		return
	extra.set_meta(&"signature", signature)
	for child: Node in extra.get_children():
		child.queue_free()
	for block: Variant in call.content:
		if not block is Dictionary:
			continue
		match str(block.get("type", "")):
			"diff":
				var card := DiffCard.new()
				card.setup_diff(block, accent)
				card.open_requested.connect(func(path: String, line: int) -> void: action_requested.emit("open_location", {"path": path, "line": line}))
				extra.add_child(card)
			"terminal":
				extra.add_child(_muted_label("Terminal: no soportado en v1."))
			"content":
				var inner: Variant = block.get("content")
				if not inner is Dictionary:
					continue
				match str(inner.get("type", "")):
					"text":
						var text := str(inner.get("text", ""))
						if call.status == ToolCall.STATUS_FAILED:
							extra.add_child(_muted_label(text.left(400), AgentTheme.ERROR))
						elif not text.strip_edges().is_empty():
							extra.add_child(_output_toggle(text))
					"image":
						extra.add_child(_image_preview(inner))
					"resource_link":
						extra.add_child(_muted_label("📎 " + str(inner.get("uri", ""))))
					"resource":
						var resource: Variant = inner.get("resource")
						extra.add_child(_muted_label("📎 " + (str(resource.get("uri", "")) if resource is Dictionary else "recurso")))
	var links := HFlowContainer.new()
	for location: Variant in call.locations:
		if location is Dictionary and location.get("path") is String:
			var path: String = location.path
			var line := int(location.get("line", 0)) if location.get("line") != null else 0
			var link := LinkButton.new()
			link.text = "%s%s" % [path.get_file(), ":%d" % line if line > 0 else ""]
			link.tooltip_text = path
			link.underline = LinkButton.UNDERLINE_MODE_ON_HOVER
			link.pressed.connect(func() -> void: action_requested.emit("open_location", {"path": path, "line": line}))
			links.add_child(link)
	if links.get_child_count() > 0:
		extra.add_child(links)
	else:
		links.free()


## Salida de texto plegada: "salida · N líneas" y, al abrirla, las primeras líneas en monoespaciada.
func _output_toggle(text: String) -> Control:
	var column := VBoxContainer.new()
	var lines := text.split("\n")
	var toggle := Button.new()
	toggle.flat = true
	toggle.toggle_mode = true
	toggle.alignment = HORIZONTAL_ALIGNMENT_LEFT
	toggle.text = "▸ salida · %d %s" % [lines.size(), "línea" if lines.size() == 1 else "líneas"]
	toggle.add_theme_color_override(&"font_color", AgentTheme.MUTED)
	column.add_child(toggle)
	var output := Label.new()
	output.visible = false
	output.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	output.add_theme_font_override(&"font", AgentTheme.mono_font())
	output.add_theme_font_size_override(&"font_size", AgentTheme.mono_font_size())
	output.add_theme_color_override(&"font_color", AgentTheme.MUTED)
	var shown := "\n".join(lines.slice(0, OUTPUT_PREVIEW_LINES)).left(OUTPUT_PREVIEW_CHARS)
	if shown.length() < text.length():
		shown += "\n…"
	output.text = shown
	column.add_child(output)
	toggle.toggled.connect(func(open: bool) -> void:
		output.visible = open
		toggle.text = ("▾" if open else "▸") + toggle.text.substr(1)
	)
	return column


static func _image_preview(block: Dictionary) -> Control:
	var image := decode_image(str(block.get("data", "")), str(block.get("mimeType", "")))
	if image == null:
		var label := Label.new()
		label.text = "[imagen]"
		label.add_theme_color_override(&"font_color", AgentTheme.MUTED)
		return label
	var rect := TextureRect.new()
	rect.texture = ImageTexture.create_from_image(image)
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
	var height := mini(image.get_height(), AgentTheme.px(IMAGE_MAX_HEIGHT))
	rect.custom_minimum_size = Vector2(0, height)
	return rect


## Imagen de un bloque ACP (base64 + mimeType), o null si no se puede decodificar.
static func decode_image(data: String, mime_type: String) -> Image:
	if data.is_empty():
		return null
	var bytes := Marshalls.base64_to_raw(data)
	if bytes.is_empty():
		return null
	var image := Image.new()
	var error := ERR_FILE_UNRECOGNIZED
	match mime_type:
		"image/png":
			error = image.load_png_from_buffer(bytes)
		"image/jpeg", "image/jpg":
			error = image.load_jpg_from_buffer(bytes)
		"image/webp":
			error = image.load_webp_from_buffer(bytes)
	return image if error == OK and not image.is_empty() else null


func _muted_label(text: String, color: Color = AgentTheme.MUTED) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_color_override(&"font_color", color)
	return label


func _on_spinner() -> void:
	_spinner_frame += 1
	for call: ToolCall in _calls():
		if call.status == ToolCall.STATUS_IN_PROGRESS and _rows.has(call.id):
			(_rows[call.id].status as Label).text = SPINNER[_spinner_frame % SPINNER.size()]


static func _short_name(call: ToolCall) -> String:
	var name := call.display_name()
	if name.begins_with("mcp__godot__"):
		return "godot." + name.trim_prefix("mcp__godot__")
	return name


static func _summary(call: ToolCall) -> String:
	if call.raw_input is Dictionary:
		var input: Dictionary = call.raw_input
		for key: String in ["file_path", "path", "command", "pattern", "query", "url", "node_path", "scene"]:
			if input.get(key) is String:
				return str(input[key]).left(SUMMARY_MAX)
	if not call.locations.is_empty() and call.locations[0] is Dictionary:
		return str(call.locations[0].get("path", "")).get_file()
	return call.kind


static func _format_duration(msec: int) -> String:
	if msec < 1000:
		return "%d ms" % msec
	return ("%.1f s" % (msec / 1000.0)).replace(".", ",")
