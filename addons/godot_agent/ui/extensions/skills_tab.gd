@tool
extends MarginContainer
## Pestaña «Skills» de Extensions (m7-36): las skills de Claude Code del proyecto, del usuario y de
## los plugins, con un interruptor por proyecto para las de usuario y proyecto (las apagadas no
## llegan al agente desde la próxima sesión, ver SkillCatalog.session_settings; las de plugins van
## con su plugin). Crea una skill nueva con su plantilla, importa una
## carpeta o un zip, copia una del usuario al proyecto y sugiere las skills de Godot del marketplace
## godot-agent.

## Texto para la línea de estado de la ventana.
signal status_changed(text: String, color: Color)
## Cambió algo que el agente ve recién en una sesión nueva.
signal next_session_changed
## Las skills apagadas en el proyecto, para guardarlas en la configuración.
signal disabled_changed(names: PackedStringArray)
## Agregar el marketplace sugerido e instalar sus plugins (lo corre la ventana, con el CLI).
signal suggested_install_requested

const I18n := preload("../../core/i18n.gd")
const AgentTheme := preload("../agent_theme.gd")
const SkillCatalog := preload("../../extensions/skill_catalog.gd")
const ExtensionsUi := preload("extensions_ui.gd")

## Marketplace con las skills de Godot del proyecto (m7-40) y los plugins que se instalan.
const SUGGESTED_MARKETPLACE := "dannroda/godot-agent-plugins"
const SUGGESTED_MARKETPLACE_NAME := "godot-agent"
const SUGGESTED_PLUGINS: PackedStringArray = ["gdscript@godot-agent", "shaders@godot-agent"]
const ORIGIN_LABELS: Dictionary = {
	SkillCatalog.ORIGIN_PROJECT: "Project (.claude/skills)",  # i18n
	SkillCatalog.ORIGIN_USER: "User (all projects)",  # i18n
	SkillCatalog.ORIGIN_PLUGIN: "From plugins",  # i18n
}
const ORIGIN_PROJECT_AGENTS := "Project (.agents/skills)"  # i18n
const SCOPE_ALL := 0
const SCOPE_PROJECT := 1
const SCOPE_USER := 2
const SCOPE_PLUGINS := 3
const SCOPE_ORIGINS: Dictionary = {SCOPE_PROJECT: SkillCatalog.ORIGIN_PROJECT, SCOPE_USER: SkillCatalog.ORIGIN_USER, SCOPE_PLUGINS: SkillCatalog.ORIGIN_PLUGIN}
const ADD_NEW_PROJECT := 0
const ADD_NEW_USER := 1
const ADD_IMPORT_PROJECT := 2
const ADD_IMPORT_USER := 3
const MENU_OPEN := 0
const MENU_SHOW := 1
const MENU_COPY := 2
const MENU_DELETE := 3

var project_path: String = ""
var claude_config_dir: String = ""
var agent_kind: String = "claude"
var agent_env: Dictionary = {}
var disabled: PackedStringArray = []
## true si el perfil activo es Claude Code (habilita el marketplace sugerido y apagar skills por sesión).
var is_claude: bool = true
## Abre un archivo con la app del sistema (los checks lo reemplazan).
var open_file: Callable = func(path: String) -> void: OS.shell_open(path)

var _filter: LineEdit
## Filtro por alcance (m12-29): todas, del proyecto, del usuario o de plugins.
var _scope_filter: OptionButton
## Dónde van «Nueva» e «Importar»: 0 = este proyecto, 1 = todos mis proyectos (lo elige el menú «+»).
var _target_scope: int = 0
var _box: VBoxContainer
var _hint: Label
var _new_dialog: ConfirmationDialog
var _new_name: LineEdit
var _new_description: LineEdit
var _confirm: ConfirmationDialog
var _confirm_action: Callable
var _file_dialog: FileDialog
var _skills: Array[Dictionary] = []


func _init() -> void:
	name = "Skills"
	for side: String in ["left", "right", "top", "bottom"]:
		add_theme_constant_override("margin_" + side, AgentTheme.px(6))
	var page := VBoxContainer.new()
	page.add_theme_constant_override(&"separation", AgentTheme.px(6))
	add_child(page)
	var bar := HBoxContainer.new()
	page.add_child(bar)
	_filter = LineEdit.new()
	_filter.placeholder_text = I18n.t("Filter skills…")
	_filter.clear_button_enabled = true
	_filter.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_filter.text_changed.connect(func(_text: String) -> void: _rebuild())
	bar.add_child(_filter)
	_scope_filter = OptionButton.new()
	_scope_filter.add_item(I18n.t("All"), SCOPE_ALL)
	_scope_filter.add_item(I18n.t("This project"), SCOPE_PROJECT)
	_scope_filter.add_item(I18n.t("All my projects"), SCOPE_USER)
	_scope_filter.add_item(I18n.t("From plugins"), SCOPE_PLUGINS)
	_scope_filter.tooltip_text = I18n.t("Show the skills of…")
	_scope_filter.item_selected.connect(func(_index: int) -> void: _rebuild())
	bar.add_child(_scope_filter)
	var add := MenuButton.new()
	add.name = "AddSkillMenu"
	add.flat = false
	add.text = I18n.t("+ Skill")
	add.tooltip_text = I18n.t("Create or import a skill, here or for all your projects")
	var add_popup := add.get_popup()
	add_popup.add_item(I18n.t("New skill in this project"), ADD_NEW_PROJECT)
	add_popup.add_item(I18n.t("New skill for all my projects"), ADD_NEW_USER)
	add_popup.add_separator()
	add_popup.add_item(I18n.t("Import a folder or zip into this project…"), ADD_IMPORT_PROJECT)
	add_popup.add_item(I18n.t("Import a folder or zip for all my projects…"), ADD_IMPORT_USER)
	add_popup.id_pressed.connect(func(id: int) -> void:
		_target_scope = 1 if id in [ADD_NEW_USER, ADD_IMPORT_USER] else 0
		if id in [ADD_NEW_PROJECT, ADD_NEW_USER]:
			_open_new_dialog()
		else:
			_open_import())
	bar.add_child(add)
	bar.add_child(ExtensionsUi.icon_button(&"Reload", I18n.t("Read the skills again"), refresh))
	_box = ExtensionsUi.scroll_list(page)
	_hint = ExtensionsUi.muted(I18n.t("A skill turned off here is hidden from the agent in this project from the next session."))
	page.add_child(_hint)
	_build_dialogs()


func _build_dialogs() -> void:
	_new_dialog = ConfirmationDialog.new()
	_new_dialog.title = I18n.t("New skill")
	_new_dialog.ok_button_text = I18n.t("Create")
	_new_dialog.cancel_button_text = I18n.t("Cancel")
	var column := VBoxContainer.new()
	_new_dialog.add_child(column)
	_new_name = LineEdit.new()
	_new_name.placeholder_text = I18n.t("Name (lowercase and dashes, e.g. level-design)")
	_new_name.custom_minimum_size.x = AgentTheme.px(380)
	column.add_child(_new_name)
	_new_description = LineEdit.new()
	_new_description.placeholder_text = I18n.t("When the agent should use it")
	column.add_child(_new_description)
	_new_dialog.confirmed.connect(_create_skill)
	add_child(_new_dialog)
	_confirm = ConfirmationDialog.new()
	_confirm.cancel_button_text = I18n.t("Cancel")
	_confirm.confirmed.connect(func() -> void:
		if _confirm_action.is_valid():
			_confirm_action.call())
	add_child(_confirm)
	_file_dialog = FileDialog.new()
	_file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_ANY
	_file_dialog.title = I18n.t("Import a skill folder or zip")
	_file_dialog.filters = PackedStringArray(["*.zip"])
	_file_dialog.file_selected.connect(_import)
	_file_dialog.dir_selected.connect(_import)
	add_child(_file_dialog)


## Vuelve a leer las skills del disco.
func refresh() -> void:
	var kind := "claude" if is_claude else (agent_kind if not agent_kind.is_empty() else "other")
	_skills = SkillCatalog.scan(claude_config_dir, project_path, kind, agent_env)
	_rebuild()


func _rebuild() -> void:
	ExtensionsUi.clear(_box)
	if _hint:
		_hint.text = I18n.t("A skill turned off here is hidden from the agent in this project from the next session.") if is_claude else I18n.t("Skills are folders with a SKILL.md file (.agents/skills in the project, or in your user folder). Changes apply from the next session.")
	var query := _filter.text.strip_edges().to_lower()
	if is_claude and not _has_suggested() and query.is_empty():
		_box.add_child(_suggested_card())
	var scope := _scope_filter.get_selected_id() if _scope_filter else SCOPE_ALL
	for origin: String in SkillCatalog.ORIGINS:
		if scope != SCOPE_ALL and SCOPE_ORIGINS[scope] != origin:
			continue
		var skills := _skills.filter(func(skill: Dictionary) -> bool:
			return skill.origin == origin and (query.is_empty() or str(skill.id).to_lower().contains(query) or str(skill.description).to_lower().contains(query)))
		if skills.is_empty():
			continue
		var origin_label: String = ORIGIN_LABELS[origin]
		if origin == SkillCatalog.ORIGIN_PROJECT and not is_claude:
			origin_label = ORIGIN_PROJECT_AGENTS
		_box.add_child(ExtensionsUi.section("%s (%d)" % [I18n.t(origin_label), skills.size()]))
		for skill: Dictionary in skills:
			_box.add_child(_skill_card(skill))
	if _skills.is_empty():
		_box.add_child(ExtensionsUi.muted(I18n.t("No skills yet. Create one, import one, or install a plugin that brings skills.")))


func _skill_card(skill: Dictionary) -> Control:
	var id := str(skill.id)
	var card := ExtensionsUi.card()
	var column := VBoxContainer.new()
	card.add_child(column)
	var row := HBoxContainer.new()
	column.add_child(row)
	var label := Label.new()
	label.text = id
	label.add_theme_font_override(&"font", AgentTheme.mono_font())
	label.clip_text = true
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.tooltip_text = str(skill.path)
	label.mouse_filter = Control.MOUSE_FILTER_PASS
	row.add_child(label)
	var skill_file := str(skill.path).path_join(SkillCatalog.SKILL_FILE)
	# Las acciones con su nombre en un «⋯» (m12-29), no cuatro íconos sueltos.
	var more := MenuButton.new()
	more.name = "SkillMenu"
	more.flat = true
	more.text = "⋯"
	more.tooltip_text = I18n.t("Actions for this skill")
	var popup := more.get_popup()
	popup.add_icon_item(AgentTheme.icon(&"Edit"), I18n.t("Open SKILL.md"), MENU_OPEN)
	popup.add_icon_item(AgentTheme.icon(&"Folder"), I18n.t("Show in the file manager"), MENU_SHOW)
	if skill.origin == SkillCatalog.ORIGIN_USER:
		popup.add_icon_item(AgentTheme.icon(&"Duplicate"), I18n.t("Copy to this project"), MENU_COPY)
	if skill.origin != SkillCatalog.ORIGIN_PLUGIN:
		popup.add_separator()
		popup.add_icon_item(AgentTheme.icon(&"Remove"), I18n.t("Delete…"), MENU_DELETE)
	popup.id_pressed.connect(_on_skill_action.bind(skill))
	row.add_child(more)
	if is_claude and skill.origin != SkillCatalog.ORIGIN_PLUGIN:
		var toggle := CheckButton.new()
		toggle.button_pressed = not disabled.has(id)
		toggle.tooltip_text = I18n.t("Use in this project")
		toggle.toggled.connect(_set_enabled.bind(id))
		row.add_child(toggle)
	var description := str(skill.description)
	if not description.is_empty():
		var text := ExtensionsUi.muted(description)
		text.max_lines_visible = 3
		text.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		text.tooltip_text = description
		text.mouse_filter = Control.MOUSE_FILTER_PASS
		column.add_child(text)
	if not str(skill.plugin).is_empty():
		column.add_child(ExtensionsUi.muted(I18n.t("Plugin %s: it turns on and off with its plugin (Plugins tab).") % skill.plugin))
	return card


func _suggested_card() -> Control:
	var card := ExtensionsUi.card()
	var row := HBoxContainer.new()
	card.add_child(row)
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(column)
	var title := Label.new()
	title.text = I18n.t("Godot skills")
	column.add_child(title)
	var text := ExtensionsUi.muted(I18n.t("Architecture, signals and autoloads, gameplay patterns, data and saves, code review and shaders for Godot 4, from the %s marketplace.") % SUGGESTED_MARKETPLACE)
	column.add_child(text)
	var install := Button.new()
	install.text = I18n.t("Install")
	install.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	install.pressed.connect(func() -> void: suggested_install_requested.emit())
	row.add_child(install)
	return card


func _has_suggested() -> bool:
	for skill: Dictionary in _skills:
		if str(skill.plugin).ends_with("@" + SUGGESTED_MARKETPLACE_NAME):
			return true
	return false


func _set_enabled(on: bool, id: String) -> void:
	if on:
		var index := disabled.find(id)
		if index >= 0:
			disabled.remove_at(index)
	elif not disabled.has(id):
		disabled.append(id)
	disabled_changed.emit(disabled)
	next_session_changed.emit()
	status_changed.emit((I18n.t("%s turned on in this project.") if on else I18n.t("%s turned off in this project.")) % id, AgentTheme.MUTED)


func _on_skill_action(action: int, skill: Dictionary) -> void:
	var skill_file := str(skill.path).path_join(SkillCatalog.SKILL_FILE)
	match action:
		MENU_OPEN:
			open_file.call(skill_file)
		MENU_SHOW:
			OS.shell_show_in_file_manager(skill_file)
		MENU_COPY:
			_copy_to_project(skill)
		MENU_DELETE:
			_ask(I18n.t("Move the skill %s to the trash?") % skill.id, I18n.t("Delete"), _delete.bind(skill))


func _target_dir() -> String:
	var kind := "claude" if is_claude else (agent_kind if not agent_kind.is_empty() else "other")
	return SkillCatalog.project_dir(project_path, kind) if _target_scope == 0 else SkillCatalog.user_dir(claude_config_dir, kind, agent_env)


func _open_new_dialog() -> void:
	_new_name.text = ""
	_new_description.text = ""
	_new_dialog.popup_centered()
	_new_name.grab_focus()


func _create_skill() -> void:
	var skill_name := _new_name.text.strip_edges()
	if not SkillCatalog.is_valid_name(skill_name):
		status_changed.emit(I18n.t("A skill name is lowercase letters, digits and dashes: «%s» is not valid.") % skill_name, AgentTheme.ERROR)
		return
	var file := SkillCatalog.create(_target_dir(), skill_name, _new_description.text)
	if file.is_empty():
		status_changed.emit(I18n.t("Could not create %s: a skill with that name may already exist.") % skill_name, AgentTheme.ERROR)
		return
	refresh()
	next_session_changed.emit()
	status_changed.emit(I18n.t("Created %s.") % file, AgentTheme.ADDED)
	open_file.call(file)


func _open_import() -> void:
	_file_dialog.popup_centered_ratio(0.6)


func _import(path: String) -> void:
	var result := SkillCatalog.import_path(path, _target_dir())
	refresh()
	if not str(result.error).is_empty():
		status_changed.emit(I18n.t("Could not import: %s") % result.error, AgentTheme.ERROR)
		return
	var parts: PackedStringArray = []
	if not result.imported.is_empty():
		parts.append(I18n.t("Imported: %s.") % ", ".join(result.imported))
		next_session_changed.emit()
	if not result.skipped.is_empty():
		parts.append(I18n.t("Already there, left as they were: %s.") % ", ".join(result.skipped))
	status_changed.emit(" ".join(parts), AgentTheme.ADDED if not result.imported.is_empty() else AgentTheme.WARNING)


func _copy_to_project(skill: Dictionary) -> void:
	var kind := "claude" if is_claude else (agent_kind if not agent_kind.is_empty() else "other")
	var error := SkillCatalog.copy_skill(str(skill.path), SkillCatalog.project_dir(project_path, kind))
	refresh()
	if not error.is_empty():
		status_changed.emit(I18n.t("Could not copy %s: %s") % [skill.id, error], AgentTheme.ERROR)
		return
	next_session_changed.emit()
	status_changed.emit(I18n.t("%s copied to %s: commit it so your team gets it too.") % [skill.id, SkillCatalog.project_relative_dir(kind)], AgentTheme.ADDED)


func _delete(skill: Dictionary) -> void:
	var ok := SkillCatalog.remove_skill(str(skill.path))
	refresh()
	if ok:
		next_session_changed.emit()
	status_changed.emit(I18n.t("%s moved to the trash.") % skill.id if ok else I18n.t("Could not move %s to the trash.") % skill.id, AgentTheme.MUTED if ok else AgentTheme.ERROR)


func _ask(text: String, ok_text: String, action: Callable) -> void:
	_confirm.dialog_text = text
	_confirm.ok_button_text = ok_text
	_confirm_action = action
	_confirm.popup_centered()
