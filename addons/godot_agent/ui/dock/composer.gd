@tool
extends VBoxContainer
## Composer del dock: chips de contexto, texto con autocompletado (`/` comandos del agente,
## `@` archivos y nodos), medidor de contexto, selector de modelo y enviar/detener.
## Enter envía, Ctrl+Enter o Shift+Enter bajan de línea y Esc cancela el turno.

signal submitted(text: String)
signal cancel_requested
signal model_selected(value: String)
signal screenshot_requested
signal context_chip_removed(chip_id: String)

const AgentTheme := preload("../agent_theme.gd")

const PLACEHOLDER := "Pedile algo… @ para nodos y archivos, / para comandos"
const MENTION_LIMIT := 400

## Callable() -> Array[Dictionary] `{label, insert}` para `@`.
var mention_provider: Callable

var _accent: Color
var _chips: HFlowContainer
var _input: CodeEdit
var _meter: Label
var _model_button: OptionButton
var _send_button: Button
var _screenshot_button: Button
var _busy: bool = false
## Motivo del bloqueo del envío (límite del plan, con la cuenta regresiva); "" = sin bloqueo.
var _lock_text: String = ""
var _lock_tooltip: String = ""
var _usage_hint: String = ""
var _commands: Array = []
var _model_values: PackedStringArray = []


func setup(accent: Color) -> void:
	_accent = accent


func _ready() -> void:
	add_theme_constant_override(&"separation", AgentTheme.px(4))
	_chips = HFlowContainer.new()
	_chips.visible = false
	add_child(_chips)

	_input = CodeEdit.new()
	_input.placeholder_text = PLACEHOLDER
	_input.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_input.custom_minimum_size.y = AgentTheme.px(72)
	_input.scroll_fit_content_height = false
	_input.gutters_draw_line_numbers = false
	_input.auto_brace_completion_enabled = false
	_input.indent_automatic = false
	_input.code_completion_enabled = true
	_input.code_completion_prefixes = PackedStringArray(["/", "@"])
	_input.highlight_current_line = false
	_input.caret_blink = true
	_input.code_completion_requested.connect(_on_completion_requested)
	_input.gui_input.connect(_on_input_gui_input)
	_input.text_changed.connect(_update_send_button)
	_input.text_changed.connect(_on_text_changed)
	add_child(_input)

	var row := HBoxContainer.new()
	add_child(row)
	row.add_child(_icon_button("@", "Mencionar un nodo o archivo", _insert_prefix.bind("@")))
	_screenshot_button = _icon_button("", "Adjuntar una captura del viewport", func() -> void: screenshot_requested.emit())
	_screenshot_button.icon = AgentTheme.icon(&"Image")
	if _screenshot_button.icon == null:
		_screenshot_button.text = "▣"
	row.add_child(_screenshot_button)
	row.add_child(_icon_button("/", "Comandos del agente", _insert_prefix.bind("/")))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)
	_meter = Label.new()
	_meter.add_theme_color_override(&"font_color", AgentTheme.MUTED)
	_meter.tooltip_text = "Contexto usado"
	row.add_child(_meter)
	_model_button = OptionButton.new()
	_model_button.flat = true
	_model_button.fit_to_longest_item = false
	_model_button.tooltip_text = "Modelo"
	_model_button.visible = false
	_model_button.item_selected.connect(func(index: int) -> void: model_selected.emit(_model_values[index]))
	row.add_child(_model_button)
	_send_button = Button.new()
	_send_button.pressed.connect(_on_send_pressed)
	_send_button.add_theme_stylebox_override(&"normal", AgentTheme.panel(_accent, Color.TRANSPARENT, 4, 4))
	_send_button.add_theme_stylebox_override(&"hover", AgentTheme.panel(_accent.lightened(0.15), Color.TRANSPARENT, 4, 4))
	_send_button.add_theme_stylebox_override(&"pressed", AgentTheme.panel(_accent.darkened(0.15), Color.TRANSPARENT, 4, 4))
	_send_button.add_theme_stylebox_override(&"disabled", AgentTheme.panel(Color(_accent, 0.35), Color.TRANSPARENT, 4, 4))
	_send_button.add_theme_color_override(&"font_color", Color("#1d1d1d"))
	_send_button.add_theme_color_override(&"font_hover_color", Color("#1d1d1d"))
	_send_button.add_theme_color_override(&"font_pressed_color", Color("#1d1d1d"))
	row.add_child(_send_button)
	set_usage(0, 0)
	_update_send_button()


func current_text() -> String:
	return _input.text


func clear() -> void:
	_input.text = ""
	_update_send_button()


func focus() -> void:
	_input.grab_focus()


## `busy`: hay un turno en curso (el botón pasa a Detener).
func set_busy(busy: bool) -> void:
	_busy = busy
	_update_send_button()


func set_enabled(enabled: bool) -> void:
	_input.editable = enabled
	_update_send_button()


## Bloquea el envío mientras dure el límite del plan (spec §10.1). `text` va en el botón.
func set_locked(text: String, tooltip: String = "") -> void:
	_lock_text = text
	_lock_tooltip = tooltip
	_update_send_button()


## Texto extra del tooltip del medidor de contexto (por ejemplo, que el agente no informa la cuota).
func set_usage_hint(hint: String) -> void:
	_usage_hint = hint
	_meter.tooltip_text = _meter.tooltip_text.get_slice("\n", 0) + ("\n" + hint if not hint.is_empty() else "")


func set_commands(commands: Array) -> void:
	_commands = commands


func set_screenshot_available(available: bool) -> void:
	_screenshot_button.disabled = not available
	_screenshot_button.tooltip_text = "Adjuntar una captura del viewport" if available else "El agente no acepta imágenes"


func set_usage(used: int, total: int) -> void:
	if total <= 0:
		_meter.text = ""
		return
	_meter.text = "%s / %s" % [_short_number(used), _short_number(total)]
	var ratio := float(used) / float(total)
	_meter.tooltip_text = "Contexto usado: %d%%" % int(ratio * 100.0) + ("\n" + _usage_hint if not _usage_hint.is_empty() else "")
	_meter.add_theme_color_override(&"font_color", AgentTheme.WARNING if ratio >= 0.8 else AgentTheme.MUTED)


## `option` es la configOption "model" del agente (o {} para ocultar el selector).
func set_model_option(option: Dictionary) -> void:
	_model_button.clear()
	_model_values.clear()
	var options: Variant = option.get("options", [])
	if not options is Array or (options as Array).is_empty():
		_model_button.visible = false
		return
	var current := str(option.get("currentValue", ""))
	for item: Variant in options:
		if not item is Dictionary:
			continue
		_model_values.append(str(item.get("value", "")))
		_model_button.add_item(str(item.get("name", item.get("value", ""))))
		_model_button.set_item_tooltip(_model_button.item_count - 1, str(item.get("description", "")))
		if str(item.get("value", "")) == current:
			_model_button.select(_model_button.item_count - 1)
	_model_button.visible = true


## Chips de contexto: `[{id, label, tooltip}]`.
func set_chips(chips: Array[Dictionary], add_callback: Callable = Callable()) -> void:
	for child: Node in _chips.get_children():
		child.queue_free()
	for chip: Dictionary in chips:
		var button := Button.new()
		button.text = "%s  ✕" % chip.label
		button.tooltip_text = str(chip.get("tooltip", "Quitar del contexto"))
		button.add_theme_stylebox_override(&"normal", AgentTheme.panel(Color(1, 1, 1, 0.06), Color(1, 1, 1, 0.12), 10, 3))
		button.add_theme_font_size_override(&"font_size", AgentTheme.px(12))
		button.pressed.connect(func() -> void: context_chip_removed.emit(str(chip.id)))
		_chips.add_child(button)
	if add_callback.is_valid():
		var add := Button.new()
		add.text = "+ contexto"
		add.flat = true
		add.add_theme_font_size_override(&"font_size", AgentTheme.px(12))
		add.pressed.connect(add_callback)
		_chips.add_child(add)
	_chips.visible = _chips.get_child_count() > 0


func has_chips() -> bool:
	return _chips.get_child_count() > 0


func _icon_button(text: String, tooltip: String, callback: Callable) -> Button:
	var button := Button.new()
	button.flat = true
	button.text = text
	button.tooltip_text = tooltip
	button.pressed.connect(callback)
	return button


func _insert_prefix(prefix: String) -> void:
	_input.grab_focus()
	_input.insert_text_at_caret(prefix)
	_input.request_code_completion(true)


func _on_send_pressed() -> void:
	if _busy:
		cancel_requested.emit()
	else:
		_submit()


func _submit() -> void:
	var value := _input.text.strip_edges()
	if value.is_empty() or _busy or not _lock_text.is_empty():
		return
	submitted.emit(value)


func _on_input_gui_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if key.keycode in [KEY_ENTER, KEY_KP_ENTER]:
		# Con el popup de / o @ abierto, Enter elige la opción (lo maneja el CodeEdit).
		if _input.get_code_completion_selected_index() >= 0:
			return
		_input.accept_event()
		if key.is_command_or_control_pressed() or key.shift_pressed:
			_input.insert_text_at_caret("\n")
		else:
			_submit()
	elif key.keycode == KEY_ESCAPE and _busy and _input.get_code_completion_selected_index() < 0:
		_input.accept_event()
		cancel_requested.emit()


## El CodeEdit no abre la lista solo al tipear un prefijo (en el Script Editor lo hace un timer del
## editor): se pide al escribir `/` al comienzo o `@`. Después, el CodeEdit la filtra mientras se
## escribe; elegir una opción no la vuelve a abrir.
func _on_text_changed() -> void:
	if _input.get_code_completion_selected_index() >= 0:
		return
	var word := _word_before_caret()
	if (word.text == "/" and word.start == 0) or word.text == "@":
		_input.request_code_completion(true)


## {text, start}: la palabra entre el último espacio y el caret.
func _word_before_caret() -> Dictionary:
	var line := _input.get_line(_input.get_caret_line()).left(_input.get_caret_column())
	var start := maxi(line.rfind(" "), line.rfind("\t")) + 1
	return {"text": line.substr(start), "start": start}


func _on_completion_requested() -> void:
	var before := _word_before_caret()
	var word: String = before.text
	var word_start: int = before.start
	if word.begins_with("/") and word_start == 0:
		for command: Variant in _commands:
			if command is Dictionary:
				var name := str(command.get("name", ""))
				# El CodeEdit reemplaza la `/` junto con la palabra (la `@` no): la opción la vuelve a poner.
				# Igual en 4.4.1, 4.7.2 y 4.8-beta1.
				_input.add_code_completion_option(CodeEdit.KIND_PLAIN_TEXT, "/%s — %s" % [name, command.get("description", "")], "/" + name)
	elif word.begins_with("@") and mention_provider.is_valid():
		var options: Array = mention_provider.call()
		for option: Variant in options.slice(0, MENTION_LIMIT):
			if option is Dictionary:
				_input.add_code_completion_option(CodeEdit.KIND_FILE_PATH, str(option.label), str(option.insert))
	_input.update_code_completion_options(true)


func _update_send_button() -> void:
	if _send_button == null:
		return
	if _busy:
		_send_button.text = "■ Detener"
		_send_button.tooltip_text = "Detener el turno (Esc)"
		_send_button.disabled = false
	elif not _lock_text.is_empty():
		_send_button.text = _lock_text
		_send_button.tooltip_text = _lock_tooltip
		_send_button.disabled = true
	else:
		_send_button.text = "Enviar ➤"
		_send_button.tooltip_text = "Enviar (Enter; Ctrl+Enter baja de línea)"
		_send_button.disabled = not _input.editable or _input.text.strip_edges().is_empty()


static func _short_number(value: int) -> String:
	if value >= 1000000:
		return ("%.1fM" % (value / 1000000.0)).replace(".0M", "M").replace(".", ",")
	if value >= 1000:
		return "%dk" % int(round(value / 1000.0))
	return str(value)
