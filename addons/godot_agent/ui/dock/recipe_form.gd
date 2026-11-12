@tool
extends ConfirmationDialog
## El formulario de una receta (m11-30), generado de sus parámetros: un control por tipo. «Usar» no
## manda nada: el dock pone el prompt expandido en el composer, con un chip que lleva los checks.

const I18n := preload("../../core/i18n.gd")
const Recipes := preload("../../core/recipes.gd")
const AgentTheme := preload("../agent_theme.gd")
const FORM_WIDTH := 420

## Los valores ya validados: `{key: value}`.
signal used(recipe: Dictionary, values: Dictionary)

## () -> PackedStringArray: los nodos de la escena abierta (rutas como las menciona el composer).
var node_options: Callable
## () -> PackedStringArray: las acciones de input del proyecto.
var input_actions: Callable

var _recipe: Dictionary = {}
## key -> el control del valor (LineEdit, TextEdit, OptionButton, SpinBox, CheckBox).
var _controls: Dictionary = {}
var _grid: GridContainer
var _error_label: Label
var _plan_check: CheckBox
var _file_dialog: Node


func _init() -> void:
	dialog_hide_on_ok = false
	ok_button_text = I18n.t("Use")
	confirmed.connect(_on_confirmed)


## Arma el formulario de `recipe` (de Recipes.parse, sin errores).
func open_recipe(recipe: Dictionary) -> void:
	_recipe = recipe
	title = I18n.t("Recipe: %s") % recipe.title
	for child: Node in get_children(true):
		if child is VBoxContainer and child.name == "Body":
			remove_child(child)
			child.queue_free()
	_controls.clear()
	var body := VBoxContainer.new()
	body.name = "Body"
	body.custom_minimum_size.x = AgentTheme.px(FORM_WIDTH)
	add_child(body)
	if not str(recipe.description).is_empty():
		var description := Label.new()
		description.text = recipe.description
		description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		description.custom_minimum_size.x = AgentTheme.px(FORM_WIDTH)  # con autowrap y sin ancho, mide un renglón por letra
		description.add_theme_color_override(&"font_color", AgentTheme.MUTED)
		body.add_child(description)
	_grid = GridContainer.new()
	_grid.columns = 2
	body.add_child(_grid)
	for parameter: Dictionary in recipe.parameters:
		var label := Label.new()
		label.text = str(parameter.label) + ("" if not parameter.required or parameter.type == "bool" else " *")
		_grid.add_child(label)
		var control := _control_for(parameter)
		control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_grid.add_child(control)
	_plan_check = CheckBox.new()
	_plan_check.name = "PlanFirst"
	_plan_check.text = I18n.t("Plan first")
	_plan_check.tooltip_text = I18n.t("The agent writes a plan in Ask mode and waits for «Approve and build». The checks start with the turn that builds.")
	_plan_check.button_pressed = bool(recipe.get("plan", false))
	body.add_child(_plan_check)
	var checks: Array = recipe.checks
	if not checks.is_empty():
		var info := Label.new()
		info.text = I18n.t("After each turn: %s (up to %d retries).") % [", ".join(Recipes.check_names(recipe)), int(recipe.max_retries)]
		info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		info.custom_minimum_size.x = AgentTheme.px(FORM_WIDTH)  # con autowrap y sin ancho, mide un renglón por letra
		info.add_theme_color_override(&"font_color", AgentTheme.MUTED)
		body.add_child(info)
	_error_label = Label.new()
	_error_label.add_theme_color_override(&"font_color", AgentTheme.WARNING)
	_error_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_error_label.custom_minimum_size.x = AgentTheme.px(FORM_WIDTH)  # con autowrap y sin ancho, mide un renglón por letra
	body.add_child(_error_label)


func recipe() -> Dictionary:
	return _recipe


func _control_for(parameter: Dictionary) -> Control:
	var default: Variant = parameter.default
	var control: Control
	match str(parameter.type):
		"multiline":
			var edit := TextEdit.new()
			edit.custom_minimum_size.y = AgentTheme.px(70)
			edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
			edit.text = "" if default == null else str(default)
			control = edit
		"choice", "node", "input_action":
			var options := PackedStringArray(parameter.options)
			if parameter.type == "node" and node_options.is_valid():
				options = node_options.call()
			elif parameter.type == "input_action":
				options = input_actions.call() if input_actions.is_valid() else project_input_actions()
			var button := OptionButton.new()
			if not parameter.required:
				button.add_item("—")
				button.set_item_metadata(0, "")
			for option: String in options:
				button.add_item(option)
				button.set_item_metadata(button.item_count - 1, option)
			_select(button, "" if default == null else str(default))
			control = button
		"number":
			var spin := SpinBox.new()
			spin.allow_greater = true
			spin.allow_lesser = true
			spin.step = 0.01
			spin.value = float(default) if default != null and str(default).is_valid_float() else 0.0
			control = spin
		"bool":
			var check := CheckBox.new()
			check.button_pressed = default == true or str(default).to_lower() == "true"
			control = check
		"scene", "script", "resource", "path":
			var row := HBoxContainer.new()
			var edit := LineEdit.new()
			edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			edit.placeholder_text = "res://…"
			edit.text = "" if default == null else str(default)
			row.add_child(edit)
			var browse := Button.new()
			browse.text = "…"
			browse.tooltip_text = I18n.t("Pick a file of the project")
			browse.pressed.connect(_browse.bind(parameter, edit))
			row.add_child(browse)
			_controls[parameter.key] = edit
			return row
		_:
			var edit := LineEdit.new()
			edit.text = "" if default == null else str(default)
			control = edit
	_controls[parameter.key] = control
	return control


static func _select(button: OptionButton, value: String) -> void:
	for i in button.item_count:
		if str(button.get_item_metadata(i)) == value:
			button.select(i)
			return
	if button.item_count > 0:
		button.select(0)


## Las acciones de input del proyecto (Project Settings → Input Map), ordenadas.
static func project_input_actions() -> PackedStringArray:
	var result: PackedStringArray = []
	for property: Dictionary in ProjectSettings.get_property_list():
		var name := str(property.name)
		if name.begins_with("input/"):
			result.append(name.trim_prefix("input/"))
	result.sort()
	return result


func _browse(parameter: Dictionary, edit: LineEdit) -> void:
	if not Engine.is_editor_hint() or not ClassDB.class_exists(&"EditorFileDialog"):
		return
	if _file_dialog:
		_file_dialog.queue_free()
	var dialog: Variant = ClassDB.instantiate(&"EditorFileDialog")
	dialog.file_mode = 0  # FILE_MODE_OPEN_FILE
	dialog.access = 0  # ACCESS_RESOURCES
	for extension: String in Recipes.extensions_for(parameter):
		dialog.add_filter("*." + extension)
	dialog.file_selected.connect(func(path: String) -> void: edit.text = path)
	add_child(dialog)
	_file_dialog = dialog
	dialog.popup_file_dialog()


## Los valores del formulario: `{key: value}` (texto, número o bool según el tipo).
func values() -> Dictionary:
	var result := {}
	for parameter: Dictionary in _recipe.get("parameters", []):
		var control: Control = _controls.get(parameter.key)
		if control is LineEdit:
			result[parameter.key] = (control as LineEdit).text.strip_edges()
		elif control is TextEdit:
			result[parameter.key] = (control as TextEdit).text.strip_edges()
		elif control is OptionButton:
			var button := control as OptionButton
			result[parameter.key] = str(button.get_item_metadata(button.selected)) if button.selected >= 0 else ""
		elif control is SpinBox:
			result[parameter.key] = (control as SpinBox).value
		elif control is CheckBox:
			result[parameter.key] = (control as CheckBox).button_pressed
	return result


## «Planificar primero» marcado.
func plan_first() -> bool:
	return _plan_check != null and _plan_check.button_pressed


## Para las pruebas y el editor check: «Planificar primero».
func set_plan_first(on: bool) -> void:
	if _plan_check:
		_plan_check.button_pressed = on


## Para las pruebas y el editor check: pone un valor como si el usuario lo hubiera elegido.
func set_value(key: String, value: Variant) -> void:
	var control: Control = _controls.get(key)
	if control is LineEdit:
		(control as LineEdit).text = str(value)
	elif control is TextEdit:
		(control as TextEdit).text = str(value)
	elif control is OptionButton:
		_select(control as OptionButton, str(value))
	elif control is SpinBox:
		(control as SpinBox).value = float(value)
	elif control is CheckBox:
		(control as CheckBox).button_pressed = bool(value)


## «Usar»: con valores que sirven, emite `used` y cierra; si no, dice qué falta y queda abierto.
func _on_confirmed() -> void:
	var current := values()
	var errors := Recipes.values_errors(_recipe, current)
	if not errors.is_empty():
		_error_label.text = "\n".join(errors)
		return
	_error_label.text = ""
	hide()
	var chosen := _recipe.duplicate(true)
	chosen.plan = plan_first()
	used.emit(chosen, current)
