@tool
extends MarginContainer
## Pestaña «Instructions» de Extensions (m11-07): ver y editar las instrucciones del proyecto para
## los agentes (CLAUDE.md lo lee Claude Code; AGENTS.md, Codex y otros; GEMINI.md, Gemini CLI), y
## agregarles los datos del proyecto que el harness lee solo (ver ProjectFacts).

signal status_changed(text: String, color: Color)

const I18n := preload("../../core/i18n.gd")
const AgentTheme := preload("../agent_theme.gd")
const ProjectFacts := preload("../../core/project_facts.gd")
const ExtensionsUi := preload("extensions_ui.gd")

const FILES: PackedStringArray = ["CLAUDE.md", "AGENTS.md", "GEMINI.md"]
const READERS := {"CLAUDE.md": "Claude Code", "AGENTS.md": "Codex, Copilot, Cursor, OpenCode…", "GEMINI.md": "Gemini CLI"}

var project_path: String = ""
var _file: OptionButton
var _editor: TextEdit
var _readers: Label
var _current: String = ""
var _saved_text: String = ""


func _init() -> void:
	name = "Instructions"
	for side: String in ["left", "right", "top", "bottom"]:
		add_theme_constant_override("margin_" + side, AgentTheme.px(6))
	var page := VBoxContainer.new()
	page.add_theme_constant_override(&"separation", AgentTheme.px(6))
	add_child(page)
	page.add_child(ExtensionsUi.muted(I18n.t("What every agent session reads about this project: conventions, how to run and test it, what not to touch. Each agent reads its own file at the start of a session.")))
	var bar := HBoxContainer.new()
	page.add_child(bar)
	_file = OptionButton.new()
	_file.item_selected.connect(func(index: int) -> void: _switch_to(FILES[index]))
	bar.add_child(_file)
	_readers = ExtensionsUi.muted("")
	_readers.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(_readers)
	_editor = TextEdit.new()
	_editor.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_editor.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_editor.add_theme_font_override(&"font", AgentTheme.mono_font())
	_editor.placeholder_text = I18n.t("Empty: this file doesn't exist yet. Write here or add the project facts, then save.")
	page.add_child(_editor)
	var buttons := HBoxContainer.new()
	page.add_child(buttons)
	var facts := Button.new()
	facts.text = I18n.t("Add the project facts")
	facts.tooltip_text = I18n.t("Godot version, main scene, autoloads, named layers, input actions and folders, read from the project. It goes between markers: adding it again updates it without touching the rest.")
	facts.pressed.connect(_add_facts)
	buttons.add_child(facts)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	buttons.add_child(spacer)
	var save := Button.new()
	save.text = I18n.t("Save")
	save.pressed.connect(_save)
	buttons.add_child(save)


## Vuelve a leer el archivo elegido (o el primero que exista).
func refresh() -> void:
	if project_path.is_empty():
		project_path = ProjectSettings.globalize_path("res://")
	if _current.is_empty():
		_current = FILES[0]
		for file: String in FILES:
			if FileAccess.file_exists(project_path.path_join(file)):
				_current = file
				break
	_fill_options()
	_load(_current)


func _fill_options() -> void:
	_file.clear()
	for file: String in FILES:
		_file.add_item(file if FileAccess.file_exists(project_path.path_join(file)) else I18n.t("%s (new)") % file)
	_file.select(FILES.find(_current))
	_readers.text = I18n.t("Read by %s.") % READERS[_current]


func _load(file: String) -> void:
	var path := project_path.path_join(file)
	_saved_text = FileAccess.get_file_as_string(path) if FileAccess.file_exists(path) else ""
	_editor.text = _saved_text
	_editor.clear_undo_history()


## Cambiar de archivo guarda lo que se estaba editando, para no perderlo.
func _switch_to(file: String) -> void:
	if _editor.text != _saved_text:
		_save()
	_current = file
	_fill_options()
	_load(file)


func _add_facts() -> void:
	var facts := ProjectFacts.section(ProjectFacts.current_settings(), Engine.get_version_info().string, ProjectFacts.top_folders(project_path))
	_editor.text = ProjectFacts.merge(_editor.text, facts)
	status_changed.emit(I18n.t("Project facts added to %s: save to keep them.") % _current, AgentTheme.MUTED)


func _save() -> void:
	if _editor.text == _saved_text:
		return
	var file := FileAccess.open(project_path.path_join(_current), FileAccess.WRITE)
	if file == null:
		status_changed.emit(I18n.t("Could not save %s.") % _current, AgentTheme.ERROR)
		return
	file.store_string(_editor.text)
	file.close()
	_saved_text = _editor.text
	_fill_options()
	status_changed.emit(I18n.t("%s saved: agents read it from their next session.") % _current, AgentTheme.ADDED)
