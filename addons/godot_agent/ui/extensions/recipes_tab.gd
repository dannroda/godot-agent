@tool
extends MarginContainer
## Pestaña «Recipes» de Extensions (m11-30): las recetas de la carpeta del proyecto, con su estado
## (✓ o cuántos errores), y el .json de la elegida en un editor que valida mientras se escribe. «New»
## copia una plantilla (core/recipe_templates.gd); «Use» la abre en el dock. Los comandos de los
## checks igual piden aprobación por máquina la primera vez que corren.

signal status_changed(text: String, color: Color)
## «Use»: abrir el formulario de la receta en el dock.
signal use_requested(slug: String)

const I18n := preload("../../core/i18n.gd")
const AgentTheme := preload("../agent_theme.gd")
const ExtensionsUi := preload("extensions_ui.gd")
const Recipes := preload("../../core/recipes.gd")
const RecipeTemplates := preload("../../core/recipe_templates.gd")
const VALIDATE_DELAY_S := 0.3

## () -> String: la carpeta de recetas (res://… o absoluta).
var dir_provider: Callable

var _list: ItemList
var _editor: CodeEdit
var _path_label: Label
var _problems: Label
var _save_button: Button
var _revert_button: Button
var _use_button: Button
var _new_menu: MenuButton
var _validate_timer: Timer
var _loaded: Array[Dictionary] = []
## La ruta del .json abierto en el editor ("" sin ninguno) y su texto guardado.
var _path: String = ""
var _saved_text: String = ""
var _filling: bool = false


func _init() -> void:
	name = "Recipes"
	for side: String in ["left", "right", "top", "bottom"]:
		add_theme_constant_override("margin_" + side, AgentTheme.px(6))
	var page := VBoxContainer.new()
	page.add_theme_constant_override(&"separation", AgentTheme.px(6))
	add_child(page)
	page.add_child(ExtensionsUi.muted(I18n.t("Reusable requests with parameters and checks the result must pass. One .json per recipe in the project's recipes folder, shared through git. Launch them from the composer's + or with /recipe. A check's command runs only after you approve it on this machine.")))
	var split := HBoxContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.add_theme_constant_override(&"separation", AgentTheme.px(8))
	page.add_child(split)
	var left := VBoxContainer.new()
	left.custom_minimum_size.x = AgentTheme.px(220)
	split.add_child(left)
	_list = ItemList.new()
	_list.name = "RecipeList"
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.item_selected.connect(_on_selected)
	left.add_child(_list)
	var left_bar := HBoxContainer.new()
	left.add_child(left_bar)
	_new_menu = MenuButton.new()
	_new_menu.name = "NewRecipe"
	_new_menu.text = I18n.t("New")
	_new_menu.flat = false
	_new_menu.tooltip_text = I18n.t("A new recipe from a template, saved in the recipes folder.")
	var popup := _new_menu.get_popup()
	var templates := RecipeTemplates.all()
	for i in templates.size():
		popup.add_item(I18n.t(templates[i].label), i)
	popup.id_pressed.connect(func(id: int) -> void: create_from_template(str(RecipeTemplates.all()[id].id)))
	left_bar.add_child(_new_menu)
	var reload := Button.new()
	reload.text = I18n.t("Reload")
	reload.pressed.connect(refresh)
	left_bar.add_child(reload)
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.add_child(right)
	_path_label = ExtensionsUi.muted("")
	right.add_child(_path_label)
	_editor = CodeEdit.new()
	_editor.name = "RecipeJson"
	_editor.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_editor.gutters_draw_line_numbers = true
	_editor.indent_use_spaces = false
	_editor.auto_brace_completion_enabled = true
	_editor.editable = false
	_editor.text_changed.connect(func() -> void:
		if not _filling:
			_update_buttons()
			_validate_timer.start())
	right.add_child(_editor)
	_problems = Label.new()
	_problems.name = "RecipeProblems"
	_problems.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	right.add_child(_problems)
	var right_bar := HBoxContainer.new()
	right.add_child(right_bar)
	_save_button = Button.new()
	_save_button.text = I18n.t("Save")
	_save_button.pressed.connect(save)
	right_bar.add_child(_save_button)
	_revert_button = Button.new()
	_revert_button.text = I18n.t("Revert")
	_revert_button.pressed.connect(func() -> void: _open(_path))
	right_bar.add_child(_revert_button)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_bar.add_child(spacer)
	_use_button = Button.new()
	_use_button.text = I18n.t("Use in the dock")
	_use_button.tooltip_text = I18n.t("Open the recipe's form in the agent dock.")
	_use_button.pressed.connect(func() -> void:
		if not _path.is_empty():
			use_requested.emit(_path.get_file().get_basename()))
	right_bar.add_child(_use_button)
	_validate_timer = Timer.new()
	_validate_timer.one_shot = true
	_validate_timer.wait_time = VALIDATE_DELAY_S
	_validate_timer.timeout.connect(validate)
	add_child(_validate_timer)
	_update_buttons()


func recipes_dir() -> String:
	return str(dir_provider.call()) if dir_provider.is_valid() else Recipes.DEFAULT_DIR


## Vuelve a leer la carpeta. El .json abierto queda abierto (con lo que no se guardó).
func refresh() -> void:
	_loaded = Recipes.load_dir(recipes_dir())
	_filling = true
	_list.clear()
	for item: Dictionary in _loaded:
		var recipe: Dictionary = item.recipe
		var errors: PackedStringArray = item.errors
		var title := str(recipe.title) if not str(recipe.title).is_empty() else str(recipe.slug)
		var index := _list.add_item(("✓ " if errors.is_empty() else "⚠ ") + title)
		_list.set_item_metadata(index, recipe.path)
		_list.set_item_tooltip(index, str(recipe.path).get_file() + "\n" + (str(recipe.description) if errors.is_empty() else I18n.t("%d problems") % errors.size()))
		if not errors.is_empty():
			_list.set_item_custom_fg_color(index, AgentTheme.WARNING)
		if recipe.path == _path:
			_list.select(index)
	_filling = false
	if _loaded.is_empty():
		_path_label.text = I18n.t("No recipes in %s yet. «New» copies a template there.") % recipes_dir()
	elif _path.is_empty() or not FileAccess.file_exists(_path):
		_open(str(_loaded[0].recipe.path))
		_list.select(0)
	_update_buttons()


func recipe_count() -> int:
	return _loaded.size()


func _on_selected(index: int) -> void:
	if _filling:
		return
	var path := str(_list.get_item_metadata(index))
	if path == _path:
		return
	if is_dirty():
		status_changed.emit(I18n.t("Save or revert «%s» before opening another recipe.") % _path.get_file(), AgentTheme.WARNING)
		_select_path(_path)
		return
	_open(path)


func _select_path(path: String) -> void:
	_filling = true
	for i in _list.item_count:
		if str(_list.get_item_metadata(i)) == path:
			_list.select(i)
	_filling = false


func _open(path: String) -> void:
	_path = path
	_saved_text = FileAccess.get_file_as_string(path) if not path.is_empty() else ""
	_filling = true
	_editor.text = _saved_text
	_editor.editable = not path.is_empty()
	_editor.clear_undo_history()
	_filling = false
	_path_label.text = ProjectSettings.localize_path(path) if not path.is_empty() else ""
	validate()
	_update_buttons()


## Valida el texto del editor y muestra los problemas (o que está bien). Devuelve los errores.
func validate() -> PackedStringArray:
	if _path.is_empty():
		_problems.text = ""
		return PackedStringArray()
	var errors: PackedStringArray = Recipes.parse(_editor.text, _path).errors
	if errors.is_empty():
		_problems.text = I18n.t("✓ The recipe is valid.")
		_problems.add_theme_color_override(&"font_color", AgentTheme.ADDED)
	else:
		_problems.text = "\n".join(Array(errors).map(func(e: String) -> String: return "• " + e))
		_problems.add_theme_color_override(&"font_color", AgentTheme.WARNING)
	_update_buttons()
	return errors


func is_dirty() -> bool:
	return not _path.is_empty() and _editor.text != _saved_text


## Guarda el .json abierto (también con errores: se puede guardar a medias; «Use» espera a que sirva).
func save() -> Error:
	if _path.is_empty():
		return ERR_UNAVAILABLE
	var file := FileAccess.open(_path, FileAccess.WRITE)
	if file == null:
		var error := FileAccess.get_open_error()
		status_changed.emit(I18n.t("Could not save %s: %s") % [_path.get_file(), error_string(error)], AgentTheme.ERROR)
		return error
	file.store_string(_editor.text)
	file.close()
	_saved_text = _editor.text
	_scan(_path)
	status_changed.emit(I18n.t("Saved %s.") % _path.get_file(), AgentTheme.MUTED)
	refresh()
	return OK


## «New» con una plantilla: un .json nuevo en la carpeta (creándola si hace falta), abierto.
func create_from_template(id: String) -> String:
	if is_dirty():
		status_changed.emit(I18n.t("Save or revert «%s» before opening another recipe.") % _path.get_file(), AgentTheme.WARNING)
		return ""
	var dir := recipes_dir()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var slug := "recipe"
	for template: Dictionary in RecipeTemplates.all():
		if template.id == id:
			slug = str(template.data.title).to_snake_case().replace(" ", "_")
	var path := RecipeTemplates.free_path(dir, slug)
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		status_changed.emit(I18n.t("Could not save %s: %s") % [path.get_file(), error_string(FileAccess.get_open_error())], AgentTheme.ERROR)
		return ""
	file.store_string(RecipeTemplates.text(id))
	file.close()
	_scan(path)
	_open(path)
	refresh()
	status_changed.emit(I18n.t("Created %s from a template. Adjust it and save.") % path.get_file(), AgentTheme.MUTED)
	return path


## El editor (para las pruebas).
func editor() -> CodeEdit:
	return _editor


func problems_text() -> String:
	return _problems.text


func _update_buttons() -> void:
	if _save_button == null:
		return
	var dirty := is_dirty()
	_save_button.disabled = not dirty
	_revert_button.disabled = not dirty
	var valid: bool = not _path.is_empty() and not dirty and Recipes.parse(_saved_text, _path).errors.is_empty()
	_use_button.disabled = not valid
	_use_button.tooltip_text = I18n.t("Open the recipe's form in the agent dock.") if valid else I18n.t("Save a valid recipe first.")


## El FileSystem del editor se entera del archivo (el dock relee las recetas con filesystem_changed).
func _scan(path: String) -> void:
	if Engine.is_editor_hint() and path.begins_with("res://"):
		EditorInterface.get_resource_filesystem().update_file(path)
		EditorInterface.get_resource_filesystem().scan()
