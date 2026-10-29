@tool
extends Node
## Chat en línea en el Script Editor (m11-05), como Ctrl+I de Copilot: Alt+I (o el menú contextual
## del código) abre un campo junto al caret; el pedido va a la sesión activa del dock con el archivo,
## las líneas y el código seleccionado, y el agente contesta solo con el código nuevo. La propuesta se
## muestra como diff junto al código: «Aceptar» reemplaza la selección (o inserta en el caret) en un
## solo paso de Ctrl+Z, sin tocar el disco; si el código cambió mientras tanto, no se aplica.

const I18n := preload("../core/i18n.gd")
const AgentTheme := preload("../ui/agent_theme.gd")
const DiffDialog := preload("../ui/diff_dialog.gd")

const SPINNER: PackedStringArray = ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"]

## `(prompt: String) -> Dictionary`: lo manda a la sesión activa y espera el turno. Devuelve
## `{text, error, no_session}`: lo que contestó el agente o por qué no se pudo (`no_session` si no
## hay sesión abierta). Lo pone el plugin.
var ask: Callable
## `() -> void`: cancela el turno de la sesión activa. Lo pone el plugin.
var cancel: Callable
## `() -> bool`: abre la sesión de la pestaña activa del dock; true si quedó conectada. Lo pone el plugin.
var start_session: Callable
## `() -> String`: el nombre del agente de la sesión activa ("" si no hay). Lo pone el plugin.
var agent_name: Callable

var _attached: Dictionary = {}  # CodeEdit -> el Callable conectado a su gui_input
var _field_popup: PopupPanel
var _field: LineEdit
var _proposal_popup: PopupPanel
var _proposal_text: RichTextLabel
var _proposal_status: Label
var _request_label: Label
var _dismiss: Button
var _start: Button
var _accept: Button
var _waiting: bool = false
## Esperando: indicador animado y segundos desde el pedido (m12-08).
var _wait_timer: Timer
var _wait_started_msec: int = 0
var _wait_frame: int = 0
## El pedido en curso: {code_edit, path, from_line, from_column, to_line, to_column, original, code}.
var _pending: Dictionary = {}


func _ready() -> void:
	_field_popup = PopupPanel.new()
	_field = LineEdit.new()
	_field.custom_minimum_size.x = AgentTheme.px(380)
	_field.placeholder_text = I18n.t("Ask the agent to change this code…")
	_field.text_submitted.connect(_on_submitted)
	_field_popup.add_child(_field)
	add_child(_field_popup)
	_proposal_popup = PopupPanel.new()
	var column := VBoxContainer.new()
	column.custom_minimum_size.x = AgentTheme.px(520)
	_proposal_popup.add_child(column)
	_request_label = Label.new()
	_request_label.add_theme_color_override(&"font_color", AgentTheme.MUTED)
	_request_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	column.add_child(_request_label)
	_proposal_status = Label.new()
	_proposal_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_proposal_status)
	_proposal_text = RichTextLabel.new()
	_proposal_text.bbcode_enabled = true
	_proposal_text.selection_enabled = true
	_proposal_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_proposal_text.add_theme_font_override(&"normal_font", AgentTheme.mono_font())
	_proposal_text.add_theme_font_size_override(&"normal_font_size", AgentTheme.mono_font_size())
	column.add_child(_proposal_text)
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_END
	column.add_child(buttons)
	_dismiss = Button.new()
	_dismiss.pressed.connect(_on_dismiss)
	buttons.add_child(_dismiss)
	_start = Button.new()
	_start.text = I18n.t("Start session")
	_start.pressed.connect(_on_start_session)
	buttons.add_child(_start)
	_accept = Button.new()
	_accept.text = I18n.t("Accept")
	_accept.pressed.connect(_on_accept)
	buttons.add_child(_accept)
	add_child(_proposal_popup)
	_wait_timer = Timer.new()
	_wait_timer.wait_time = 0.15
	_wait_timer.timeout.connect(_on_wait_tick)
	add_child(_wait_timer)
	if Engine.is_editor_hint():
		EditorInterface.get_script_editor().editor_script_changed.connect(_on_script_changed)
		_attach_current.call_deferred()


func _exit_tree() -> void:
	for code_edit: Variant in _attached:
		if is_instance_valid(code_edit) and (code_edit as CodeEdit).gui_input.is_connected(_attached[code_edit]):
			(code_edit as CodeEdit).gui_input.disconnect(_attached[code_edit])
	_attached.clear()


## Abre el campo para pedir un cambio en `code_edit` (el atajo y el menú contextual).
func open_for(code_edit: CodeEdit) -> void:
	var script := EditorInterface.get_script_editor().get_current_script()
	var span := selection_range(code_edit)
	_pending = span
	_pending.code_edit = code_edit
	_pending.path = script.resource_path if script else ""
	_proposal_popup.hide()
	_field.text = ""
	_field_popup.popup(Rect2i(Vector2i(code_edit.get_screen_position() + code_edit.get_caret_draw_pos()), Vector2i.ZERO))
	_field.grab_focus()


## La selección (o el caret, sin selección): `{from_line, from_column, to_line, to_column, original}`.
static func selection_range(code_edit: CodeEdit) -> Dictionary:
	if code_edit.has_selection():
		return {"from_line": code_edit.get_selection_from_line(), "from_column": code_edit.get_selection_from_column(),
			"to_line": code_edit.get_selection_to_line(), "to_column": code_edit.get_selection_to_column(), "original": code_edit.get_selected_text()}
	var line := code_edit.get_caret_line()
	var column := code_edit.get_caret_column()
	return {"from_line": line, "from_column": column, "to_line": line, "to_column": column, "original": ""}


## El prompt para el agente: qué cambiar, dónde y cómo contestar.
static func build_prompt(path: String, span: Dictionary, instruction: String) -> String:
	var where := "lines %d–%d" % [int(span.from_line) + 1, int(span.to_line) + 1] if not str(span.original).is_empty() else "line %d (insert at the cursor)" % (int(span.from_line) + 1)
	var lines: PackedStringArray = [
		"[Inline edit from the Script Editor] File: %s, %s." % [path, where],
		"Instruction: %s" % instruction,
		"Answer with ONLY the new code for that spot in one ```gdscript block, keeping the file's indentation. Don't edit files or call editing tools: the user reviews your code as a diff in the editor and applies it. You can read the file for context.",
	]
	if not str(span.original).is_empty():
		lines.append("Selected code (it will be replaced by yours):\n```gdscript\n%s\n```" % span.original)
	return "\n".join(lines)


## El primer bloque de código de la respuesta, sin las líneas ``` ("" si no hay).
static func extract_code(text: String) -> String:
	var regex := RegEx.create_from_string("```[a-zA-Z0-9_+-]*[ \\t]*\\n([\\s\\S]*?)\\n?```")
	var found := regex.search(text)
	return found.get_string(1) if found else ""


## Reemplaza el rango por `code` en un solo paso de deshacer. false si el texto del rango ya no es el
## que se le mostró al agente.
static func apply(code_edit: CodeEdit, span: Dictionary, code: String) -> bool:
	if _text_in(code_edit, span) != str(span.original):
		return false
	code_edit.begin_complex_operation()
	code_edit.remove_text(int(span.from_line), int(span.from_column), int(span.to_line), int(span.to_column))
	code_edit.set_caret_line(int(span.from_line))
	code_edit.set_caret_column(int(span.from_column))
	code_edit.insert_text_at_caret(code)
	code_edit.end_complex_operation()
	return true


static func _text_in(code_edit: CodeEdit, span: Dictionary) -> String:
	var from_line := int(span.from_line)
	var to_line := int(span.to_line)
	if from_line >= code_edit.get_line_count() or to_line >= code_edit.get_line_count():
		return "\u0000"  # el rango ya no existe
	if from_line == to_line:
		return code_edit.get_line(from_line).substr(int(span.from_column), int(span.to_column) - int(span.from_column))
	var parts: PackedStringArray = [code_edit.get_line(from_line).substr(int(span.from_column))]
	for line in range(from_line + 1, to_line):
		parts.append(code_edit.get_line(line))
	parts.append(code_edit.get_line(to_line).left(int(span.to_column)))
	return "\n".join(parts)


func _on_submitted(instruction: String) -> void:
	_field_popup.hide()
	if instruction.strip_edges().is_empty() or not ask.is_valid():
		_pending = {}
		return
	var request := _pending
	request.instruction = instruction.strip_edges()
	var agent := str(agent_name.call()) if agent_name.is_valid() else ""
	_request_label.text = request_label(request.instruction, agent, request)
	_request_label.tooltip_text = request.instruction
	_waiting = true
	_wait_started_msec = Time.get_ticks_msec()
	_wait_frame = 0
	_show_proposal(waiting_status(0, 0), "", false)
	_wait_timer.start()
	var answer: Dictionary = await ask.call(build_prompt(request.path, request, request.instruction))
	if _pending != request:
		return  # se rechazó o se pidió otra cosa mientras tanto
	_waiting = false
	_wait_timer.stop()
	if not str(answer.error).is_empty():
		_show_proposal(str(answer.error), "", false, bool(answer.get("no_session", false)))
		return
	var code := extract_code(str(answer.text))
	if code.is_empty():
		_show_proposal(I18n.t("The agent didn't answer with a code block: its reply is in the chat."), "", false)
		return
	request.code = code
	_show_proposal(I18n.t("The agent's proposal: accept it to apply it (Ctrl+Z undoes it), or reject it."), DiffDialog.diff_bbcode(I18n.t("now"), str(request.original), I18n.t("proposal"), code), true)


func _show_proposal(status: String, diff: String, can_accept: bool, can_start: bool = false) -> void:
	_proposal_status.text = status
	_proposal_text.text = diff
	_proposal_text.visible = not diff.is_empty()
	_proposal_text.custom_minimum_size.y = AgentTheme.px(200) if not diff.is_empty() else 0
	_accept.visible = can_accept
	_start.visible = can_start and start_session.is_valid()
	_dismiss.text = I18n.t("Cancel") if _waiting else (I18n.t("Reject") if can_accept else I18n.t("Close"))
	var code_edit: CodeEdit = _pending.get("code_edit")
	var at := Vector2i(code_edit.get_screen_position() + code_edit.get_caret_draw_pos()) if is_instance_valid(code_edit) else Vector2i.ZERO
	# Sin esto la ventana conserva el alto de la propuesta anterior (m12-06).
	_proposal_popup.reset_size()
	_proposal_popup.popup(Rect2i(at, Vector2i.ZERO))


## «“hacelo async” · Claude Code · líneas 15–16».
static func request_label(instruction: String, agent: String, span: Dictionary) -> String:
	var parts: PackedStringArray = ["“%s”" % instruction]
	if not agent.is_empty():
		parts.append(agent)
	parts.append(where_label(span))
	return " · ".join(parts)


## «⠋ Waiting for the answer · 4 s».
static func waiting_status(frame: int, elapsed_msec: int) -> String:
	return "%s %s · %s" % [SPINNER[frame % SPINNER.size()], I18n.t("Waiting for the agent's answer"), I18n.t("%d s") % int(elapsed_msec / 1000.0)]


func _on_wait_tick() -> void:
	if not _waiting:
		_wait_timer.stop()
		return
	_wait_frame += 1
	_proposal_status.text = waiting_status(_wait_frame, Time.get_ticks_msec() - _wait_started_msec)


## «líneas 15–16» o «línea 15» (insertar en el caret).
static func where_label(span: Dictionary) -> String:
	var from := int(span.from_line) + 1
	var to := int(span.to_line) + 1
	return I18n.t("line %d") % from if from == to else I18n.t("lines %d–%d") % [from, to]


## Esperando, cancela el turno; si no, descarta la propuesta o cierra el aviso.
func _on_dismiss() -> void:
	if _waiting and cancel.is_valid():
		cancel.call()
	_waiting = false
	_wait_timer.stop()
	_pending = {}
	_proposal_popup.hide()


## Sin sesión: la abre en el dock y manda el mismo pedido cuando conecta.
func _on_start_session() -> void:
	var request := _pending
	_waiting = false
	_show_proposal(I18n.t("Starting the session…"), "", false)
	_start.visible = false
	var connected: bool = await start_session.call()
	if _pending != request:
		return
	if not connected:
		_show_proposal(I18n.t("The session didn't start: look at the Agent dock."), "", false)
		return
	_on_submitted(str(request.instruction))


func _on_accept() -> void:
	var request := _pending
	_pending = {}
	_proposal_popup.hide()
	if not is_instance_valid(request.get("code_edit")):
		return
	if not apply(request.code_edit, request, str(request.code)):
		EditorInterface.get_editor_toaster().push_toast(I18n.t("The code changed while the agent was answering: the proposal was not applied."), EditorToaster.SEVERITY_WARNING)


func _on_script_changed(_script: Script) -> void:
	_attach_current.call_deferred()


func _attach_current() -> void:
	var current := EditorInterface.get_script_editor().get_current_editor()
	var code_edit := current.get_base_editor() as CodeEdit if current else null
	if code_edit and not _attached.has(code_edit):
		_attached[code_edit] = _on_gui_input.bind(code_edit)
		code_edit.gui_input.connect(_attached[code_edit])


func _on_gui_input(event: InputEvent, code_edit: CodeEdit) -> void:
	var key := event as InputEventKey
	if key and key.pressed and not key.echo and is_shortcut(key):
		code_edit.accept_event()
		open_for(code_edit)


## Atajo: Alt+I (Ctrl+I ya es «Indentar» en el Script Editor).
static func is_shortcut(key: InputEventKey) -> bool:
	return key.alt_pressed and not key.ctrl_pressed and not key.meta_pressed and not key.shift_pressed and key.keycode == KEY_I
