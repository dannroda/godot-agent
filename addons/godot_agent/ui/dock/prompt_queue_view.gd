@tool
extends PanelContainer
## Prompts en cola, arriba del composer: "En cola (N)", una fila por prompt (editar o quitar) y,
## si la cola está en pausa, el motivo con «Enviar ahora». Solo muestra y edita la PromptQueue; el
## envío lo decide el dock.

## El usuario quiere seguir editando un prompt encolado (ya salió de la cola).
signal edit_requested(text: String)
signal send_now_requested

const AgentTheme := preload("../agent_theme.gd")
const PromptQueue := preload("../../session/prompt_queue.gd")

## Caracteres de cada fila (el texto completo va en el tooltip).
const ROW_CHARS := 120

var _queue: PromptQueue
var _title: Label
var _reason: Label
var _send_now: Button
var _rows: VBoxContainer


func setup(queue: PromptQueue) -> void:
	_queue = queue


func _ready() -> void:
	visible = false
	add_theme_stylebox_override(&"panel", AgentTheme.panel(Color(1, 1, 1, 0.04), Color(1, 1, 1, 0.12), 6, 4))
	var column := VBoxContainer.new()
	column.add_theme_constant_override(&"separation", AgentTheme.px(2))
	add_child(column)
	var header := HBoxContainer.new()
	column.add_child(header)
	_title = Label.new()
	_title.add_theme_color_override(&"font_color", AgentTheme.MUTED)
	_title.add_theme_font_size_override(&"font_size", AgentTheme.px(12))
	header.add_child(_title)
	_reason = _row_label(AgentTheme.WARNING)
	_reason.add_theme_font_size_override(&"font_size", AgentTheme.px(12))
	header.add_child(_reason)
	_send_now = _small_button("Enviar ahora", "Retomar la cola: manda el próximo prompt")
	_send_now.pressed.connect(func() -> void: send_now_requested.emit())
	header.add_child(_send_now)
	var discard := _small_button("Descartar", "Vaciar la cola")
	discard.pressed.connect(func() -> void: _queue.clear())
	header.add_child(discard)
	_rows = VBoxContainer.new()
	_rows.add_theme_constant_override(&"separation", 0)
	column.add_child(_rows)
	_queue.changed.connect(_refresh)
	_refresh()


## «Enviar ahora» solo con una sesión lista (si la sesión se cerró, primero hay que abrir otra).
func set_send_available(available: bool) -> void:
	_send_now.disabled = not available
	_send_now.tooltip_text = "Retomar la cola: manda el próximo prompt" if available else "Hace falta una sesión lista: abrí una nueva o reintentá"


func _refresh() -> void:
	visible = not _queue.is_empty()
	_title.text = "En cola (%d)" % _queue.size()
	_reason.text = "· en pausa: %s" % _queue.pause_reason if _queue.paused else ""
	_reason.tooltip_text = _queue.pause_reason
	_send_now.visible = _queue.paused
	for child: Node in _rows.get_children():
		child.queue_free()
	for i in _queue.size():
		var text := str(_queue.items[i].text)
		var row := HBoxContainer.new()
		_rows.add_child(row)
		var label := _row_label(AgentTheme.font_color())
		label.text = text.replace("\n", " ⏎ ").left(ROW_CHARS)
		label.tooltip_text = text
		label.mouse_filter = Control.MOUSE_FILTER_PASS
		row.add_child(label)
		var edit := _small_button("✎", "Editar: vuelve al composer")
		edit.pressed.connect(_on_edit.bind(i))
		row.add_child(edit)
		var remove := _small_button("✕", "Quitar de la cola")
		remove.pressed.connect(func() -> void: _queue.remove_at(i))
		row.add_child(remove)


func _on_edit(index: int) -> void:
	var item := _queue.remove_at(index)
	if not item.is_empty():
		edit_requested.emit(str(item.text))


## Una línea que se recorta con "…" en lugar de agrandar el dock (sin autowrap: ver MinSizeGuard).
static func _row_label(color: Color) -> Label:
	var label := Label.new()
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.clip_text = true
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.add_theme_color_override(&"font_color", color)
	return label


static func _small_button(text: String, tooltip: String) -> Button:
	var button := Button.new()
	button.flat = true
	button.text = text
	button.tooltip_text = tooltip
	button.add_theme_font_size_override(&"font_size", AgentTheme.px(12))
	return button
