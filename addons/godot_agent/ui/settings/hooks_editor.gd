@tool
extends VBoxContainer
## Hooks del proyecto (m11-24) en Settings, junto a los checks del turno: una fila por hook. Se edita
## una copia que se guarda con el resto del diálogo.
##
## Aprobación por máquina, como los checks: un hook agregado o cambiado acá cuenta como aprobado (lo vio
## quien lo escribió). Uno que vino en el archivo del proyecto, sin cambios y sin aprobar, muestra un
## aviso y «Allow on this machine»; guardar sin marcarla no lo aprueba.

const I18n := preload("../../core/i18n.gd")
const ProjectHooks := preload("../../core/project_hooks.gd")
const TurnChecks := preload("../../core/turn_checks.gd")
const AgentTheme := preload("../agent_theme.gd")

const EVENT_LABELS := {
	ProjectHooks.EVENT_SAVED: "A scene or script is saved",  # i18n
	ProjectHooks.EVENT_GAME_STOPPED: "A game ends",  # i18n
	ProjectHooks.EVENT_REGRESSIONS: "Playtest regressions finish",  # i18n
	ProjectHooks.EVENT_EXPORT: "An export starts",  # i18n
}
const BY_LABELS := {
	ProjectHooks.BY_USER: "by you",  # i18n
	ProjectHooks.BY_AGENT: "by the agent",  # i18n
	ProjectHooks.BY_ANY: "by anyone",  # i18n
}
const ACTION_LABELS := {
	ProjectHooks.ACTION_COMMAND: "Run a command",  # i18n
	ProjectHooks.ACTION_TOOL: "Run a godot.* tool",  # i18n
	ProjectHooks.ACTION_PROMPT: "Ask the agent",  # i18n
}

var _list: VBoxContainer
## Una fila por hook: `{hook, loaded_key, controls…}`.
var _rows: Array[Dictionary] = []
var _is_approved: Callable
var _project_dir := ""


func _init() -> void:
	add_theme_constant_override(&"separation", AgentTheme.px(6))
	var title := Label.new()
	title.text = I18n.t("Project hooks")
	title.add_theme_font_size_override(&"font_size", AgentTheme.px(15))
	add_child(title)
	add_child(_hint(I18n.t("Things to do on their own when something happens in the editor that the agent doesn't see: a scene saved, a game that ends, regressions that finish, an export. They never stop or change what happened. To check the agent's changes at the end of each turn, use the project checks above. Hooks live in the project's settings; one only runs on a machine where it was approved.")))
	_list = VBoxContainer.new()
	_list.add_theme_constant_override(&"separation", AgentTheme.px(8))
	add_child(_list)
	var add := Button.new()
	add.text = I18n.t("+ Add hook")
	add.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	add.pressed.connect(func() -> void: _add_row(ProjectHooks.make(), false))
	add_child(add)


## `is_approved(key) -> bool` mira la tienda de esta máquina; `project_dir` arma la clave.
func load_from(hooks: Array, is_approved: Callable, project_dir: String) -> void:
	_is_approved = is_approved
	_project_dir = project_dir
	for row: Dictionary in _rows:
		row.box.queue_free()
	_rows.clear()
	for hook: Dictionary in ProjectHooks.normalize_list(hooks):
		_add_row(hook, true)


## Los hooks como quedan en project_config.tres.
func hooks() -> Array:
	var result: Array = []
	for row: Dictionary in _rows:
		result.append(_read(row))
	return result


## El primer problema de la lista, o "".
func validate() -> String:
	for row: Dictionary in _rows:
		var hook := _read(row)
		match str(hook.action):
			ProjectHooks.ACTION_COMMAND:
				var parsed := TurnChecks.parse_command(hook.command)
				if not str(parsed.error).is_empty():
					return I18n.t("Project hook «%s»: %s") % [hook.name, I18n.t(parsed.error)]
			ProjectHooks.ACTION_TOOL:
				if str(hook.tool).is_empty():
					return I18n.t("Project hook «%s»: write the name of the tool.") % hook.name
				if not (row.args as LineEdit).text.strip_edges().is_empty() and not JSON.parse_string((row.args as LineEdit).text) is Dictionary:
					return I18n.t("Project hook «%s»: the arguments must be a JSON object.") % hook.name
			ProjectHooks.ACTION_PROMPT:
				if str(hook.prompt).is_empty():
					return I18n.t("Project hook «%s»: write what to ask the agent.") % hook.name
	return ""


## Las claves de aprobación que deja este guardado: hooks agregados o cambiados en el diálogo y los que
## se marcaron «Allow on this machine».
func keys_to_approve() -> PackedStringArray:
	var keys := PackedStringArray()
	for row: Dictionary in _rows:
		var key := ProjectHooks.approval_key(_project_dir, _read(row))
		if key != row.loaded_key or (row.allow as CheckBox).button_pressed:
			keys.append(key)
	return keys


func row_count() -> int:
	return _rows.size()


func _add_row(hook: Dictionary, loaded: bool) -> void:
	var row := {"hook": hook, "loaded_key": ProjectHooks.approval_key(_project_dir, hook) if loaded else ""}
	var box := VBoxContainer.new()
	row.box = box
	var top := HBoxContainer.new()
	box.add_child(top)
	row.enabled = CheckBox.new()
	(row.enabled as CheckBox).button_pressed = bool(hook.enabled)
	(row.enabled as CheckBox).tooltip_text = I18n.t("On")
	top.add_child(row.enabled)
	row.name = LineEdit.new()
	(row.name as LineEdit).text = str(hook.name)
	(row.name as LineEdit).placeholder_text = I18n.t("Name")
	(row.name as LineEdit).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(row.name)
	var remove := Button.new()
	remove.text = I18n.t("Remove")
	remove.pressed.connect(_remove.bind(box))
	top.add_child(remove)
	var grid := GridContainer.new()
	grid.columns = 2
	box.add_child(grid)
	row.event = _options(EVENT_LABELS, str(hook.event))
	grid.add_child(_label(I18n.t("When")))
	grid.add_child(row.event)
	row.by = _options(BY_LABELS, str(hook.by))
	(row.by as OptionButton).tooltip_text = I18n.t("Who saved the file or launched the game or the regressions. «By the agent» includes what its file tools write.")
	grid.add_child(_label(I18n.t("Who")))
	grid.add_child(row.by)
	row.paths = LineEdit.new()
	(row.paths as LineEdit).text = ", ".join(hook.paths)
	(row.paths as LineEdit).placeholder_text = I18n.t("any file")
	(row.paths as LineEdit).tooltip_text = I18n.t("Only for these files, separated by commas (res://levels/**, *.gd). Empty: any.")
	(row.paths as LineEdit).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_child(_label(I18n.t("Files")))
	grid.add_child(row.paths)
	row.only_errors = CheckBox.new()
	(row.only_errors as CheckBox).text = I18n.t("Only if there were errors (or failed regressions)")
	(row.only_errors as CheckBox).button_pressed = bool(hook.only_errors)
	grid.add_child(_label(""))
	grid.add_child(row.only_errors)
	row.action = _options(ACTION_LABELS, str(hook.action))
	grid.add_child(_label(I18n.t("Do")))
	grid.add_child(row.action)
	row.command = LineEdit.new()
	(row.command as LineEdit).text = str(hook.command)
	(row.command as LineEdit).placeholder_text = "{godot} --headless --path {project} -s res://tests/level_check.gd -- {path}"
	(row.command as LineEdit).tooltip_text = I18n.t("A program and its arguments, without a shell. {godot} is this editor's binary, {project} the project folder, {path} the saved file and {event} the event; the program also gets them in GODOT_AGENT_* environment variables.")
	(row.command as LineEdit).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.command_label = _label(I18n.t("Command"))
	grid.add_child(row.command_label)
	grid.add_child(row.command)
	row.tool = LineEdit.new()
	(row.tool as LineEdit).text = str(hook.tool)
	(row.tool as LineEdit).placeholder_text = "validate_scripts"
	(row.tool as LineEdit).tooltip_text = I18n.t("A tool of the harness that reads, checks or runs the game (validate_scripts, run_regressions…), or one of the project tools approved on this machine. It runs without asking, so other tools that edit or use the shell are not allowed.")
	row.tool_label = _label(I18n.t("Tool"))
	grid.add_child(row.tool_label)
	grid.add_child(row.tool)
	row.args = LineEdit.new()
	(row.args as LineEdit).text = JSON.stringify(hook.args) if not (hook.args as Dictionary).is_empty() else ""
	(row.args as LineEdit).placeholder_text = "{}"
	row.args_label = _label(I18n.t("Arguments"))
	grid.add_child(row.args_label)
	grid.add_child(row.args)
	row.prompt = LineEdit.new()
	(row.prompt as LineEdit).text = str(hook.prompt)
	(row.prompt as LineEdit).placeholder_text = I18n.t("Review the level I just saved.")
	row.prompt_label = _label(I18n.t("Ask"))
	grid.add_child(row.prompt_label)
	grid.add_child(row.prompt)
	row.auto_send = CheckBox.new()
	(row.auto_send as CheckBox).text = I18n.t("Send it on its own")
	(row.auto_send as CheckBox).button_pressed = bool(hook.auto_send)
	row.auto_send_spacer = _label("")
	grid.add_child(row.auto_send_spacer)
	grid.add_child(row.auto_send)
	row.auto_send_hint = _hint(I18n.t("Off: the chat shows a notice with «Send to the agent», and nothing is sent until you press it. On: the prompt goes to the agent of the active tab right away and spends tokens without asking, up to %d hook prompts in a row without a message from you; after that it's a notice again. Never in One-shot.") % ProjectHooks.MAX_AUTO_PROMPTS)
	box.add_child(row.auto_send_hint)
	row.timeout = SpinBox.new()
	(row.timeout as SpinBox).min_value = 1
	(row.timeout as SpinBox).max_value = ProjectHooks.MAX_TIMEOUT_S
	(row.timeout as SpinBox).value = int(hook.timeout_s)
	(row.timeout as SpinBox).suffix = "s"
	(row.timeout as SpinBox).size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	row.timeout_label = _label(I18n.t("Time limit"))
	grid.add_child(row.timeout_label)
	grid.add_child(row.timeout)
	var badge := HBoxContainer.new()
	row.badge = badge
	box.add_child(badge)
	var warning := _hint(I18n.t("Not approved on this machine: it doesn't run until you allow it."))
	warning.add_theme_color_override(&"font_color", AgentTheme.WARNING)
	warning.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	badge.add_child(warning)
	row.allow = CheckBox.new()
	(row.allow as CheckBox).text = I18n.t("Allow on this machine")
	(row.allow as CheckBox).tooltip_text = I18n.t("The hook came with the project. Allow it only if you trust it; if it changes, it asks again.")
	badge.add_child(row.allow)
	box.add_child(HSeparator.new())
	for control: Control in [row.event, row.action]:
		(control as OptionButton).item_selected.connect(func(_index: int) -> void: _refresh(row))
	(row.auto_send as CheckBox).toggled.connect(func(_on: bool) -> void: _refresh(row))
	for control: Control in [row.command, row.tool, row.args, row.prompt, row.paths]:
		(control as LineEdit).text_changed.connect(func(_text: String) -> void: _refresh(row))
	_list.add_child(box)
	_rows.append(row)
	_refresh(row)


## Muestra los campos de la acción y el evento elegidos, la explicación de auto_send cuando está
## prendido y el aviso de un hook del archivo sin aprobar.
func _refresh(row: Dictionary) -> void:
	var hook := _read(row)
	var action := str(hook.action)
	for pair: Array in [[row.command, row.command_label, action == ProjectHooks.ACTION_COMMAND], [row.timeout, row.timeout_label, action == ProjectHooks.ACTION_COMMAND],
			[row.tool, row.tool_label, action == ProjectHooks.ACTION_TOOL], [row.args, row.args_label, action == ProjectHooks.ACTION_TOOL],
			[row.prompt, row.prompt_label, action == ProjectHooks.ACTION_PROMPT], [row.auto_send, row.auto_send_spacer, action == ProjectHooks.ACTION_PROMPT]]:
		(pair[0] as Control).visible = pair[2]
		(pair[1] as Control).visible = pair[2]
	(row.auto_send_hint as Control).visible = action == ProjectHooks.ACTION_PROMPT and (row.auto_send as CheckBox).button_pressed
	(row.paths as Control).editable = str(hook.event) == ProjectHooks.EVENT_SAVED
	(row.only_errors as Control).disabled = not str(hook.event) in [ProjectHooks.EVENT_GAME_STOPPED, ProjectHooks.EVENT_REGRESSIONS]
	(row.by as Control).disabled = str(hook.event) == ProjectHooks.EVENT_EXPORT
	var key := ProjectHooks.approval_key(_project_dir, hook)
	(row.badge as Control).visible = key == row.loaded_key and not (_is_approved.is_valid() and _is_approved.call(key))


func _remove(box: Control) -> void:
	for i in _rows.size():
		if _rows[i].box == box:
			_rows.remove_at(i)
			break
	box.queue_free()


func _read(row: Dictionary) -> Dictionary:
	var source: Dictionary = row.hook
	var paths := PackedStringArray()
	for path: String in (row.paths as LineEdit).text.split(",", false):
		if not path.strip_edges().is_empty():
			paths.append(path.strip_edges())
	var args: Variant = JSON.parse_string((row.args as LineEdit).text) if not (row.args as LineEdit).text.strip_edges().is_empty() else {}
	var data := {
		"name": (row.name as LineEdit).text.strip_edges(), "event": _selected(row.event), "by": _selected(row.by), "paths": paths,
		"only_errors": (row.only_errors as CheckBox).button_pressed, "action": _selected(row.action), "command": (row.command as LineEdit).text,
		"tool": (row.tool as LineEdit).text, "args": args if args is Dictionary else source.get("args", {}), "prompt": (row.prompt as LineEdit).text,
		"auto_send": (row.auto_send as CheckBox).button_pressed, "timeout_s": int((row.timeout as SpinBox).value), "enabled": (row.enabled as CheckBox).button_pressed,
	}
	return ProjectHooks.normalize(data)


func _options(labels: Dictionary, selected: String) -> OptionButton:
	var option := OptionButton.new()
	for value: String in labels:
		option.add_item(I18n.t(str(labels[value])))
		option.set_item_metadata(option.item_count - 1, value)
		if value == selected:
			option.select(option.item_count - 1)
	return option


static func _selected(option: Control) -> String:
	var button := option as OptionButton
	return str(button.get_item_metadata(button.selected)) if button.selected >= 0 else ""


func _label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	return label


func _hint(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_color_override(&"font_color", AgentTheme.MUTED)
	return label
