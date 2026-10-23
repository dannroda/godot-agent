@tool
extends VBoxContainer
## Composer del dock: chips de contexto, texto con autocompletado (`/` comandos del agente,
## `@` archivos y nodos), medidor de contexto, selector de modelo y enviar/detener.
## Enter envía (con un turno en curso, el dock lo deja en cola), Ctrl+Enter o Shift+Enter bajan de
## línea y Esc cancela el turno. Flecha arriba en la primera línea y abajo en la última recorren los
## prompts enviados, como en una terminal. Ctrl+V con una imagen (o archivos copiados) en el
## portapapeles la adjunta en lugar de pegar texto; los archivos arrastrados desde el FileSystem
## también se adjuntan.

signal submitted(text: String)
signal cancel_requested
signal model_selected(value: String)
signal screenshot_requested
signal context_chip_removed(chip_id: String)
signal image_pasted(image: Image)
## Rutas absolutas o res:// pegadas o arrastradas.
signal files_attached(paths: PackedStringArray)

const AgentTheme := preload("../agent_theme.gd")
const SuggestionList := preload("suggestion_list.gd")
const I18n := preload("../../core/i18n.gd")

const PLACEHOLDER := "Ask for something… @ for nodes and files, / for commands"  # i18n
const PLACEHOLDER_BUSY := "The agent is working: Enter queues the message"  # i18n
const PLACEHOLDER_ONESHOT := "One-shot running: write to the agent; it gets it when the turn ends"  # i18n
const SCREENSHOT_TOOLTIP := "Attach a viewport screenshot (Ctrl+V pastes an image)"  # i18n
## Prompts que se recuerdan (los más viejos se descartan).
const HISTORY_LIMIT := 100
## Filas que se cargan en la lista (se ven hasta SuggestionList.MAX_ROWS, el resto con scroll).
const LIST_LIMIT := 200
## Más líneas que esto en el portapapeles no es una lista de archivos copiados.
const PASTED_FILES_LIMIT := 20

## Callable() -> Array[Dictionary] `{label, insert}` para `@`.
var mention_provider: Callable
## Archivo JSON con los prompts enviados ("" = solo en memoria). Lo fija el dock antes de agregarlo.
var history_path: String = ""

var _accent: Color
var _chips: HFlowContainer
var _suggestions: SuggestionList
## Opciones de `@` mientras la lista está abierta (se piden una vez al abrirla).
var _mention_cache: Array = []
## Columna de la palabra donde se cerró la lista con Esc: no se vuelve a abrir mientras siga.
var _dismissed_at: int = -1
## Prompts enviados, del más viejo al más nuevo.
var _history: PackedStringArray = []
## Posición al recorrer el historial (-1 = editando el borrador) y el borrador guardado.
var _history_index: int = -1
var _draft: String = ""
var _recalling: bool = false
var _input: CodeEdit
var _meter: Label
var _model_button: OptionButton
var _send_button: Button
var _screenshot_button: Button
var _busy: bool = false
var _oneshot_active: bool = false
## Motivo del bloqueo del envío (límite del plan, con la cuenta regresiva); "" = sin bloqueo.
var _lock_text: String = ""
var _lock_tooltip: String = ""
var _commands: Array = []
var _model_values: PackedStringArray = []


func setup(accent: Color) -> void:
	_accent = accent


func _ready() -> void:
	_load_history()
	add_theme_constant_override(&"separation", AgentTheme.px(4))
	_suggestions = SuggestionList.new()
	_suggestions.picked.connect(_on_suggestion_picked)
	add_child(_suggestions)
	_chips = HFlowContainer.new()
	_chips.visible = false
	add_child(_chips)

	_input = CodeEdit.new()
	_input.placeholder_text = I18n.t(PLACEHOLDER)
	_input.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_input.custom_minimum_size.y = AgentTheme.px(72)
	_input.scroll_fit_content_height = false
	_input.gutters_draw_line_numbers = false
	_input.auto_brace_completion_enabled = false
	_input.indent_automatic = false
	# La lista de `/` y `@` es propia (SuggestionList): la del CodeEdit se dibuja dentro del texto,
	# que tiene 72 px de alto, y mostraba una sola fila.
	_input.code_completion_enabled = false
	_input.highlight_current_line = false
	_input.caret_blink = true
	_input.gui_input.connect(_on_input_gui_input)
	_input.text_changed.connect(_update_send_button)
	_input.text_changed.connect(_refresh_suggestions)
	_input.text_changed.connect(func() -> void:
		if not _recalling:
			_history_index = -1)
	_input.caret_changed.connect(_refresh_suggestions)
	_input.focus_exited.connect(func() -> void: _close_suggestions())
	# El TextEdit consulta primero el forwarding: el texto arrastrado lo sigue manejando él.
	_input.set_drag_forwarding(Callable(), _can_drop_files, _drop_files)
	add_child(_input)

	var row := HBoxContainer.new()
	add_child(row)
	row.add_child(_icon_button("@", I18n.t("Mention a node or file"), _insert_prefix.bind("@")))
	_screenshot_button = _icon_button("", I18n.t(SCREENSHOT_TOOLTIP), func() -> void: screenshot_requested.emit())
	_screenshot_button.icon = AgentTheme.icon(&"Image")
	if _screenshot_button.icon == null:
		_screenshot_button.text = "▣"
	row.add_child(_screenshot_button)
	row.add_child(_icon_button("/", I18n.t("Agent commands"), _insert_prefix.bind("/")))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)
	_meter = Label.new()
	_meter.add_theme_color_override(&"font_color", AgentTheme.MUTED)
	_meter.tooltip_text = I18n.t("Context used")
	row.add_child(_meter)
	_model_button = OptionButton.new()
	_model_button.flat = true
	_model_button.fit_to_longest_item = false
	_model_button.tooltip_text = I18n.t("Model")
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


## Pone `text` en el composer para seguir editándolo (después de lo que ya haya escrito).
func insert_text(text: String) -> void:
	_input.text = text if _input.text.strip_edges().is_empty() else _input.text.rstrip("\n") + "\n" + text
	_input.set_caret_line(_input.get_line_count() - 1)
	_input.set_caret_column(_input.get_line(_input.get_line_count() - 1).length())
	_input.grab_focus()
	_update_send_button()


func focus() -> void:
	_input.grab_focus()


## `busy`: hay un turno en curso (el botón pasa a Detener).
func set_busy(busy: bool) -> void:
	_busy = busy
	_update_placeholder()
	_update_send_button()


## Con un One-shot en curso, lo que se escribe guía al agente del run.
func set_oneshot_active(active: bool) -> void:
	if active == _oneshot_active:
		return
	_oneshot_active = active
	_update_placeholder()


func _update_placeholder() -> void:
	_input.placeholder_text = I18n.t(PLACEHOLDER_ONESHOT) if _oneshot_active else (I18n.t(PLACEHOLDER_BUSY) if _busy else I18n.t(PLACEHOLDER))


func set_enabled(enabled: bool) -> void:
	_input.editable = enabled
	_update_send_button()


## Bloquea el envío mientras dure el límite del plan (spec §10.1). `text` va en el botón.
func set_locked(text: String, tooltip: String = "") -> void:
	_lock_text = text
	_lock_tooltip = tooltip
	_update_send_button()


## Un indicador más en la fila de abajo, antes del medidor de contexto (la cuota del plan).
func add_status_control(control: Control) -> void:
	_meter.get_parent().add_child(control)
	_meter.get_parent().move_child(control, _meter.get_index())


func set_commands(commands: Array) -> void:
	_commands = commands


func set_screenshot_available(available: bool) -> void:
	_screenshot_button.disabled = not available
	_screenshot_button.tooltip_text = I18n.t(SCREENSHOT_TOOLTIP) if available else I18n.t("The agent does not accept images")


func set_usage(used: int, total: int) -> void:
	if total <= 0:
		_meter.text = ""
		return
	_meter.text = "%s / %s" % [_short_number(used), _short_number(total)]
	var ratio := float(used) / float(total)
	_meter.tooltip_text = I18n.t("Context used: %d%%") % int(ratio * 100.0)
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
		var name := str(item.get("name", item.get("value", "")))
		var label := model_label(item, options)
		_model_button.add_item(label)
		# La opción por defecto conserva su nombre original en el tooltip («Default (recommended)»).
		_model_button.set_item_tooltip(_model_button.item_count - 1, name if label != name else str(item.get("description", "")))
		if str(item.get("value", "")) == current:
			_model_button.select(_model_button.item_count - 1)
	_model_button.visible = true


## Nombre de una opción del selector. La opción "default" de Claude Code se llama «Default
## (recommended)» y trae el modelo en la descripción: se muestra «Opus 5.5 (default)».
static func model_label(item: Dictionary, options: Array) -> String:
	var name := str(item.get("name", item.get("value", "")))
	if str(item.get("value", "")) != "default":
		return name
	var model := str(item.get("description", "")).strip_edges()
	for other: Variant in options:
		if other is Dictionary and other != item and str(other.get("name", "")) == model and not model.is_empty():
			return I18n.t("%s (default)") % model
	return name


## Chips de contexto: `[{id, label, tooltip}]`.
func set_chips(chips: Array[Dictionary], add_callback: Callable = Callable()) -> void:
	for child: Node in _chips.get_children():
		child.queue_free()
	for chip: Dictionary in chips:
		var button := Button.new()
		button.text = "%s  ✕" % chip.label
		button.tooltip_text = str(chip.get("tooltip", I18n.t("Remove from the context")))
		button.add_theme_stylebox_override(&"normal", AgentTheme.panel(Color(1, 1, 1, 0.06), Color(1, 1, 1, 0.12), 10, 3))
		button.add_theme_font_size_override(&"font_size", AgentTheme.px(12))
		button.pressed.connect(func() -> void: context_chip_removed.emit(str(chip.id)))
		_chips.add_child(button)
	if add_callback.is_valid():
		var add := Button.new()
		add.text = I18n.t("+ context")
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


func _on_send_pressed() -> void:
	if _busy:
		cancel_requested.emit()
	else:
		_submit()


func _submit() -> void:
	var value := _input.text.strip_edges()
	if value.is_empty() or not _lock_text.is_empty():
		return
	_remember(value)
	submitted.emit(value)


func _on_input_gui_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if _suggestions.is_open() and _handle_list_key(key):
		_input.accept_event()
		return
	var plain := not (key.is_command_or_control_pressed() or key.shift_pressed or key.alt_pressed)
	if plain and key.keycode == KEY_UP and _input.get_caret_line() == 0 and _recall(-1):
		_input.accept_event()
		return
	if plain and key.keycode == KEY_DOWN and _input.get_caret_line() == _input.get_line_count() - 1 and _recall(1):
		_input.accept_event()
		return
	if key.keycode == KEY_V and key.is_command_or_control_pressed() and not (key.shift_pressed or key.alt_pressed) and _paste_attachment():
		_input.accept_event()
		return
	if key.keycode in [KEY_ENTER, KEY_KP_ENTER]:
		_input.accept_event()
		if key.is_command_or_control_pressed() or key.shift_pressed:
			_input.insert_text_at_caret("\n")
		else:
			_submit()
	elif key.keycode == KEY_ESCAPE and _busy:
		_input.accept_event()
		cancel_requested.emit()


## Teclas de la lista abierta: flechas y páginas mueven, Enter o Tab eligen, Esc la cierra.
func _handle_list_key(key: InputEventKey) -> bool:
	var plain := not (key.is_command_or_control_pressed() or key.shift_pressed or key.alt_pressed)
	match key.keycode:
		KEY_UP:
			_suggestions.move(-1)
		KEY_DOWN:
			_suggestions.move(1)
		KEY_PAGEUP:
			_suggestions.move(-SuggestionList.MAX_ROWS)
		KEY_PAGEDOWN:
			_suggestions.move(SuggestionList.MAX_ROWS)
		KEY_ENTER, KEY_KP_ENTER, KEY_TAB:
			if not plain or not _suggestions.pick_selected():
				return false
		KEY_ESCAPE:
			_dismissed_at = int(_word_before_caret().start)
			_close_suggestions()
		_:
			return false
	return true


# --- adjuntos --------------------------------------------------------------------------------------

## Ctrl+V: una imagen o archivos copiados en el portapapeles se adjuntan. false = pegar texto.
func _paste_attachment() -> bool:
	if DisplayServer.clipboard_has_image():
		var image := DisplayServer.clipboard_get_image()
		if image and not image.is_empty():
			image_pasted.emit(image)
			return true
	var paths := clipboard_file_paths(DisplayServer.clipboard_get())
	if paths.is_empty():
		return false
	files_attached.emit(paths)
	return true


## Las rutas de archivos copiados en un gestor de archivos (`file:///…` o rutas absolutas, una por
## línea). Vacío si alguna línea no es un archivo existente: entonces es texto para pegar.
static func clipboard_file_paths(text: String) -> PackedStringArray:
	var paths: PackedStringArray = []
	var lines := text.strip_edges().split("\n", false)
	if lines.is_empty() or lines.size() > PASTED_FILES_LIMIT:
		return paths
	for line: String in lines:
		var path := line.strip_edges()
		if path.begins_with("file://"):
			path = path.trim_prefix("file://").uri_decode()
		if not path.is_absolute_path() or path.begins_with("res://") or not FileAccess.file_exists(path):
			return PackedStringArray()
		paths.append(path)
	return paths


func _can_drop_files(_position: Vector2, data: Variant) -> bool:
	return data is Dictionary and data.get("type") in ["files", "files_and_dirs"] and data.get("files") is PackedStringArray


## El TextEdit llama a esto con cualquier dato que se suelte (también texto, que después inserta él).
func _drop_files(position: Vector2, data: Variant) -> void:
	if not _can_drop_files(position, data):
		return
	var files: PackedStringArray = data.files
	var paths: PackedStringArray = []
	for path: String in files:
		if not path.ends_with("/"):
			paths.append(path)
	if not paths.is_empty():
		files_attached.emit(paths)


# --- historial de prompts ------------------------------------------------------------------------

## `direction` -1: uno más viejo; 1: uno más nuevo (después del más nuevo, el borrador). false si no
## hay a dónde ir (la flecha mueve el caret como siempre).
func _recall(direction: int) -> bool:
	if _history.is_empty():
		return false
	var index := _history_index
	if direction < 0:
		if index == 0:
			return false
		if index == -1:
			_draft = _input.text
			index = _history.size()
		index -= 1
	else:
		if index == -1:
			return false
		index += 1
		if index >= _history.size():
			index = -1
	_history_index = index
	_recalling = true
	_input.text = _history[index] if index >= 0 else _draft
	_recalling = false
	_input.set_caret_line(_input.get_line_count() - 1)
	_input.set_caret_column(_input.get_line(_input.get_line_count() - 1).length())
	_update_send_button()
	return true


func _remember(value: String) -> void:
	_history_index = -1
	_draft = ""
	if not _history.is_empty() and _history[_history.size() - 1] == value:
		return
	_history.append(value)
	if _history.size() > HISTORY_LIMIT:
		_history = _history.slice(_history.size() - HISTORY_LIMIT)
	_save_history()


func _load_history() -> void:
	if history_path.is_empty() or not FileAccess.file_exists(history_path):
		return
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(history_path))
	if data is Array:
		for item: Variant in data:
			if item is String and not (item as String).is_empty():
				_history.append(item)
		if _history.size() > HISTORY_LIMIT:
			_history = _history.slice(_history.size() - HISTORY_LIMIT)


func _save_history() -> void:
	if history_path.is_empty():
		return
	DirAccess.make_dir_recursive_absolute(history_path.get_base_dir())
	var file := FileAccess.open(history_path, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(Array(_history)))
		file.close()


## Abre, filtra o cierra la lista según la palabra que se está escribiendo: `/` al comienzo del
## mensaje (comandos del agente) o `@` (nodos de la escena y archivos).
func _refresh_suggestions() -> void:
	var word := _word_before_caret()
	var text: String = word.text
	var is_command: bool = text.begins_with("/") and word.start == 0 and _input.get_caret_line() == 0
	var is_mention := text.begins_with("@")
	if not (is_command or is_mention) or not _input.has_focus():
		_dismissed_at = -1
		_close_suggestions()
		return
	if int(word.start) == _dismissed_at:
		return
	var query := text.substr(1).to_lower()
	if is_command:
		var items: Array[Dictionary] = []
		for command: Variant in _commands:
			if command is Dictionary:
				var name := str(command.get("name", ""))
				items.append({"label": "/" + name, "detail": str(command.get("description", "")), "insert": "/" + name, "key": name.to_lower()})
		_suggestions.show_items(I18n.t("Commands"), _filter(items, query),
			"" if not _commands.is_empty() else I18n.t("The agent publishes its commands when the session starts."))
	else:
		if not _suggestions.is_open() or _mention_cache.is_empty():
			_mention_cache = mention_provider.call() if mention_provider.is_valid() else []
		var items: Array[Dictionary] = []
		for option: Variant in _mention_cache:
			if option is Dictionary:
				items.append({"label": str(option.label), "insert": "@" + str(option.insert), "key": str(option.label).to_lower()})
		_suggestions.show_items(I18n.t("Nodes and files"), _filter(items, query))


## Los que empiezan con `query` primero, después los que la contienen.
static func _filter(items: Array[Dictionary], query: String) -> Array[Dictionary]:
	if query.is_empty():
		return items.slice(0, LIST_LIMIT)
	var starts: Array[Dictionary] = []
	var contains: Array[Dictionary] = []
	for item: Dictionary in items:
		var key: String = item.key
		if key.begins_with(query) or key.get_file().begins_with(query):
			starts.append(item)
		elif key.contains(query):
			contains.append(item)
	return (starts + contains).slice(0, LIST_LIMIT)


## Reemplaza la palabra (`/co`, `@pla`) por la opción y un espacio, en un solo paso de deshacer.
func _on_suggestion_picked(item: Dictionary) -> void:
	var word := _word_before_caret()
	var line := _input.get_caret_line()
	var column := _input.get_caret_column()
	_input.begin_complex_operation()
	_input.remove_text(line, int(word.start), line, column)
	_input.set_caret_column(int(word.start))
	_input.insert_text_at_caret(str(item.insert) + " ")
	_input.end_complex_operation()
	_close_suggestions()


func _close_suggestions() -> void:
	_mention_cache = []
	if _suggestions and _suggestions.is_open():
		_suggestions.close()


## {text, start}: la palabra entre el último espacio y el caret.
func _word_before_caret() -> Dictionary:
	var line := _input.get_line(_input.get_caret_line()).left(_input.get_caret_column())
	var start := maxi(line.rfind(" "), line.rfind("\t")) + 1
	return {"text": line.substr(start), "start": start}


func _update_send_button() -> void:
	if _send_button == null:
		return
	if _busy:
		_send_button.text = "■ " + I18n.t("Stop")
		_send_button.tooltip_text = I18n.t("Stop the turn (Esc). Enter queues what you typed.")
		_send_button.disabled = false
	elif not _lock_text.is_empty():
		_send_button.text = _lock_text
		_send_button.tooltip_text = _lock_tooltip
		_send_button.disabled = true
	else:
		_send_button.text = I18n.t("Send") + " ➤"
		_send_button.tooltip_text = I18n.t("Send (Enter; Ctrl+Enter adds a new line)")
		_send_button.disabled = not _input.editable or _input.text.strip_edges().is_empty()


static func _short_number(value: int) -> String:
	if value >= 1000000:
		var millions := ("%.1fM" % (value / 1000000.0)).replace(".0M", "M")
		return millions.replace(".", ",") if I18n.locale() == "es" else millions
	if value >= 1000:
		return "%dk" % int(round(value / 1000.0))
	return str(value)
