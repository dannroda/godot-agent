@tool
extends VBoxContainer
## Checks del proyecto al terminar el turno (m11-31) en Settings: una fila por check, con presets.
## Se edita una copia que se guarda con el resto del diálogo.
##
## Aprobación por máquina: un comando escrito o cambiado acá cuenta como aprobado (lo vio quien lo
## escribió). Uno que vino en el archivo del proyecto y no está aprobado muestra un aviso y una casilla
## «Allow on this machine»; guardar sin marcarla no lo aprueba.

const I18n := preload("../../core/i18n.gd")
const TurnChecks := preload("../../core/turn_checks.gd")
const AgentTheme := preload("../agent_theme.gd")

var _list: VBoxContainer
var _add_menu: MenuButton
## Una fila por check: `{check, loaded_command, approved, controls…}`.
var _rows: Array[Dictionary] = []
var _is_approved: Callable
var _project_dir := ""


func _init() -> void:
	add_theme_constant_override(&"separation", AgentTheme.px(6))
	var title := Label.new()
	title.text = I18n.t("Project checks after each turn")
	title.add_theme_font_size_override(&"font_size", AgentTheme.px(15))
	add_child(title)
	add_child(_hint(I18n.t("In Build and Auto, after a turn that changes files the harness runs these checks. If one fails, the agent gets its output to fix it (sharing the 2-turn limit of the script check). They live in the project's settings, so they travel with the project; a command only runs on a machine where it was approved.")))
	_list = VBoxContainer.new()
	_list.add_theme_constant_override(&"separation", AgentTheme.px(8))
	add_child(_list)
	_add_menu = MenuButton.new()
	_add_menu.text = I18n.t("+ Add check")
	_add_menu.flat = false
	_add_menu.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	for i in TurnChecks.PRESETS.size():
		_add_menu.get_popup().add_item(I18n.t(TurnChecks.PRESETS[i].label), i)
	_add_menu.get_popup().id_pressed.connect(_on_preset)
	add_child(_add_menu)


## `is_approved(key) -> bool` mira la tienda de esta máquina; `project_dir` arma la clave.
func load_from(checks: Array, is_approved: Callable, project_dir: String) -> void:
	_is_approved = is_approved
	_project_dir = project_dir
	for row: Dictionary in _rows:
		row.box.queue_free()
	_rows.clear()
	for check: Dictionary in TurnChecks.normalize_list(checks):
		_add_row(check, true)


## Los checks como quedan en project_config.tres.
func checks() -> Array:
	var result: Array = []
	for row: Dictionary in _rows:
		result.append(_read(row))
	return result


## El primer problema de la lista, o "".
func validate() -> String:
	for row: Dictionary in _rows:
		var check := _read(row)
		if check.kind != TurnChecks.KIND_COMMAND:
			continue
		var parsed := TurnChecks.parse_command(check.command)
		if not str(parsed.error).is_empty():
			return I18n.t("Project check «%s»: %s") % [check.name, I18n.t(parsed.error)]
	return ""


## Las claves de aprobación que deja este guardado: comandos escritos o cambiados en el diálogo y los
## que se marcaron «Allow on this machine».
func keys_to_approve() -> PackedStringArray:
	var keys := PackedStringArray()
	for row: Dictionary in _rows:
		var check := _read(row)
		if check.kind != TurnChecks.KIND_COMMAND or check.command.is_empty():
			continue
		var edited: bool = check.command != row.loaded_command
		if edited or (row.allow as CheckBox).button_pressed:
			keys.append(TurnChecks.approval_key(_project_dir, check.command))
	return keys


func row_count() -> int:
	return _rows.size()


func _on_preset(index: int) -> void:
	var preset: Dictionary = TurnChecks.PRESETS[index]
	_add_row(TurnChecks.make(preset.kind, str(preset.name), str(preset.command)), false)


func _add_row(check: Dictionary, loaded: bool) -> void:
	var row := {"check": check, "loaded_command": str(check.command) if loaded else ""}
	var box := VBoxContainer.new()
	row.box = box
	var top := HBoxContainer.new()
	box.add_child(top)
	row.enabled = CheckBox.new()
	(row.enabled as CheckBox).button_pressed = bool(check.enabled)
	(row.enabled as CheckBox).tooltip_text = I18n.t("On")
	top.add_child(row.enabled)
	row.name = LineEdit.new()
	(row.name as LineEdit).text = str(check.name)
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
	row.command = LineEdit.new()
	(row.command as LineEdit).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if check.kind == TurnChecks.KIND_REGRESSIONS:
		(row.command as LineEdit).text = I18n.t("The playtest regressions saved in the project (Regressions tab)")
		(row.command as LineEdit).editable = false
	else:
		(row.command as LineEdit).text = str(check.command)
		(row.command as LineEdit).placeholder_text = "{godot} --headless --path {project} -s res://tests/run.gd"
		(row.command as LineEdit).tooltip_text = I18n.t("A program and its arguments, without a shell (no |, &&, ; or redirections). {godot} is this editor's binary and {project} the project folder.")
		(row.command as LineEdit).text_changed.connect(func(_text: String) -> void: _refresh_badge(row))
	grid.add_child(_label(I18n.t("Command")))
	grid.add_child(row.command)
	row.paths = LineEdit.new()
	(row.paths as LineEdit).text = ", ".join(check.paths)
	(row.paths as LineEdit).placeholder_text = I18n.t("any change")
	(row.paths as LineEdit).tooltip_text = I18n.t("Runs only when the turn changed a file matching one of these patterns, separated by commas (res://scripts/**, *.gd). Empty: after any change.")
	(row.paths as LineEdit).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_child(_label(I18n.t("When these change")))
	grid.add_child(row.paths)
	row.timeout = SpinBox.new()
	(row.timeout as SpinBox).min_value = 1
	(row.timeout as SpinBox).max_value = TurnChecks.MAX_TIMEOUT_S
	(row.timeout as SpinBox).value = int(check.timeout_s)
	(row.timeout as SpinBox).suffix = "s"
	(row.timeout as SpinBox).size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	grid.add_child(_label(I18n.t("Time limit")))
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
	(row.allow as CheckBox).tooltip_text = I18n.t("The command came with the project. Allow it only if you trust it; if it changes, it asks again.")
	badge.add_child(row.allow)
	box.add_child(HSeparator.new())
	_list.add_child(box)
	_rows.append(row)
	_refresh_badge(row)


## El aviso solo para un comando que vino en el archivo, sin cambios y sin aprobar acá.
func _refresh_badge(row: Dictionary) -> void:
	var check := _read(row)
	var show: bool = check.kind == TurnChecks.KIND_COMMAND and not check.command.is_empty() and check.command == row.loaded_command \
		and not (_is_approved.is_valid() and _is_approved.call(TurnChecks.approval_key(_project_dir, check.command)))
	(row.badge as Control).visible = show


func _remove(box: Control) -> void:
	for i in _rows.size():
		if _rows[i].box == box:
			_rows.remove_at(i)
			break
	box.queue_free()


func _read(row: Dictionary) -> Dictionary:
	var source: Dictionary = row.check
	var paths := PackedStringArray()
	for path: String in (row.paths as LineEdit).text.split(",", false):
		if not path.strip_edges().is_empty():
			paths.append(path.strip_edges())
	var check := TurnChecks.make(source.kind, (row.name as LineEdit).text.strip_edges(), "" if source.kind == TurnChecks.KIND_REGRESSIONS else (row.command as LineEdit).text.strip_edges())
	check.paths = paths
	check.timeout_s = int((row.timeout as SpinBox).value)
	check.enabled = (row.enabled as CheckBox).button_pressed
	return TurnChecks.normalize(check)


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
