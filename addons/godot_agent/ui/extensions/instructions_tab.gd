@tool
extends MarginContainer
## Pestaña «Instructions» de Extensions (m11-07, m11-19): ver y editar las instrucciones, reglas y
## workflows del proyecto para cada agente (`CLAUDE.md`, `AGENTS.md`, `GEMINI.md`,
## `.github/copilot-instructions.md`, `.cursorrules`, `.agents/rules/*.md`, `.agents/workflows/*.md`,
## `.claude/rules/*.md`, `.cursor/rules/*.mdc`…), y agregarles los datos del proyecto (ProjectFacts).

signal status_changed(text: String, color: Color)

const I18n := preload("../../core/i18n.gd")
const AgentTheme := preload("../agent_theme.gd")
const ProjectFacts := preload("../../core/project_facts.gd")
const ExtensionsUi := preload("extensions_ui.gd")

const FILES: PackedStringArray = [
	"CLAUDE.md",
	"AGENTS.md",
	"GEMINI.md",
	".github/copilot-instructions.md",
	".cursorrules",
]
const READERS := {
	"CLAUDE.md": "Claude Code",
	"AGENTS.md": "Codex, Antigravity, Copilot, Cursor, OpenCode…",
	"GEMINI.md": "Google Antigravity",
	".github/copilot-instructions.md": "GitHub Copilot",
	".cursorrules": "Cursor",
}
## Carpetas de reglas y workflows que leen los agentes (m11-19).
const EXTRA_DIRS: Array[Dictionary] = [
	{"dir": ".agents/rules", "ext": "md", "reader": "Google Antigravity, Codex…"},
	{"dir": ".agent/rules", "ext": "md", "reader": "Google Antigravity"},
	{"dir": ".agents/workflows", "ext": "md", "reader": "Google Antigravity"},
	{"dir": ".agent/workflows", "ext": "md", "reader": "Google Antigravity"},
	{"dir": ".claude/rules", "ext": "md", "reader": "Claude Code"},
	{"dir": ".cursor/rules", "ext": "mdc", "reader": "Cursor"},
	{"dir": ".github/instructions", "ext": "md", "reader": "GitHub Copilot"},
]
const NEW_RULE_DIRS: Array[Dictionary] = [
	{"dir": ".agents/rules", "ext": ".md", "label": "Rule (.agents/rules/*.md)"},  # i18n
	{"dir": ".agents/workflows", "ext": ".md", "label": "Workflow (.agents/workflows/*.md)"},  # i18n
	{"dir": ".claude/rules", "ext": ".md", "label": "Claude rule (.claude/rules/*.md)"},  # i18n
	{"dir": ".cursor/rules", "ext": ".mdc", "label": "Cursor rule (.cursor/rules/*.mdc)"},  # i18n
]

var project_path: String = ""
var agent_kind: String = "claude"
## Los archivos a la izquierda con quién lee cada uno (m12-32); el editor del elegido a la derecha.
var _files: Tree
var _filling: bool = false
var _editor: TextEdit
var _readers: Label
var _new_dialog: ConfirmationDialog
var _new_kind: OptionButton
var _new_name: LineEdit
var _listed_files: PackedStringArray = []
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
	var split := HBoxContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.add_theme_constant_override(&"separation", AgentTheme.px(8))
	page.add_child(split)
	var left := VBoxContainer.new()
	left.custom_minimum_size.x = AgentTheme.px(250)
	split.add_child(left)
	_files = Tree.new()
	_files.name = "InstructionFiles"
	_files.columns = 1
	_files.hide_root = true
	_files.select_mode = Tree.SELECT_ROW
	_files.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_files.item_selected.connect(func() -> void:
		var item := _files.get_selected()
		if item and not _filling:
			_switch_to(str(item.get_metadata(0))))
	left.add_child(_files)
	var add := Button.new()
	add.text = I18n.t("+ Rule or workflow")
	add.tooltip_text = I18n.t("New rule or workflow file")
	add.pressed.connect(_open_new_dialog)
	left.add_child(add)
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.add_child(right)
	_readers = ExtensionsUi.muted("")
	right.add_child(_readers)
	_editor = TextEdit.new()
	_editor.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_editor.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_editor.add_theme_font_override(&"font", AgentTheme.mono_font())
	_editor.placeholder_text = I18n.t("Empty: this file doesn't exist yet. Write here or add the project facts, then save.")
	right.add_child(_editor)
	var buttons := HBoxContainer.new()
	right.add_child(buttons)
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
	_build_new_dialog()


func _build_new_dialog() -> void:
	_new_dialog = ConfirmationDialog.new()
	_new_dialog.title = I18n.t("New rule or workflow file")
	_new_dialog.ok_button_text = I18n.t("Create")
	_new_dialog.cancel_button_text = I18n.t("Cancel")
	var column := VBoxContainer.new()
	column.add_theme_constant_override(&"separation", AgentTheme.px(6))
	_new_dialog.add_child(column)
	_new_kind = OptionButton.new()
	for item: Dictionary in NEW_RULE_DIRS:
		_new_kind.add_item(I18n.t(item.label))
	column.add_child(_new_kind)
	_new_name = LineEdit.new()
	_new_name.placeholder_text = I18n.t("File name (e.g. coding-style)")
	_new_name.custom_minimum_size.x = AgentTheme.px(360)
	column.add_child(_new_name)
	_new_dialog.confirmed.connect(_create_rule_file)
	add_child(_new_dialog)


## Archivos de reglas y workflows existentes en las carpetas del proyecto (`.agents/rules`, `.cursor/rules`, etc.).
static func discover_extra_files(root_path: String) -> PackedStringArray:
	var found: PackedStringArray = []
	if root_path.is_empty():
		return found
	for entry: Dictionary in EXTRA_DIRS:
		var folder := root_path.path_join(str(entry.dir))
		if not DirAccess.dir_exists_absolute(folder):
			continue
		var files := DirAccess.get_files_at(folder)
		files.sort()
		for fname: String in files:
			var ext := fname.get_extension().to_lower()
			if ext in ["md", "mdc"]:
				var rel := str(entry.dir).path_join(fname)
				if not rel in found:
					found.append(rel)
	return found


## Quién lee un archivo de instrucciones, regla o workflow.
static func reader_of(file: String) -> String:
	if READERS.has(file):
		return str(READERS[file])
	for entry: Dictionary in EXTRA_DIRS:
		if file.begins_with(str(entry.dir) + "/"):
			return str(entry.reader)
	return "AGENTS.md"


## Archivo inicial sugerido según el agente activo y lo que ya exista en el proyecto.
static func default_file_for(kind: String, root_path: String) -> String:
	var preferred: PackedStringArray = ["CLAUDE.md"]
	match kind:
		"codex", "opencode", "other":
			preferred = ["AGENTS.md"]
		"antigravity":
			preferred = ["GEMINI.md", "AGENTS.md"]
		"copilot":
			preferred = [".github/copilot-instructions.md", "AGENTS.md"]
		"cursor":
			preferred = [".cursorrules", "AGENTS.md"]
	for candidate: String in preferred:
		if not root_path.is_empty() and FileAccess.file_exists(root_path.path_join(candidate)):
			return candidate
	for file: String in FILES:
		if not root_path.is_empty() and FileAccess.file_exists(root_path.path_join(file)):
			return file
	return preferred[0]


## Vuelve a leer el archivo elegido (o el primero que corresponda).
func refresh() -> void:
	if project_path.is_empty():
		project_path = ProjectSettings.globalize_path("res://")
	if _current.is_empty():
		_current = default_file_for(agent_kind, project_path)
	_fill_options()
	_load(_current)


func _fill_options() -> void:
	_listed_files = FILES.duplicate()
	for extra: String in discover_extra_files(project_path):
		if not extra in _listed_files:
			_listed_files.append(extra)
	if not _current.is_empty() and not _current in _listed_files:
		_listed_files.append(_current)
	_filling = true
	_files.clear()
	var root := _files.create_item()
	for file: String in _listed_files:
		var exists := FileAccess.file_exists(project_path.path_join(file))
		var item := _files.create_item(root)
		# Dos líneas: el archivo y quién lo lee, para ver de un vistazo qué lee cada agente.
		item.set_text(0, "%s\n%s" % [file if exists else I18n.t("%s (new)") % file, reader_of(file)])
		item.set_metadata(0, file)
		item.set_tooltip_text(0, I18n.t("Read by %s.") % reader_of(file))
		if not exists:
			item.set_custom_color(0, AgentTheme.MUTED)
		if file == _current:
			item.select(0)
	_filling = false
	_readers.text = "%s · %s" % [_current, I18n.t("Read by %s.") % reader_of(_current)]


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


func _open_new_dialog() -> void:
	_new_name.text = ""
	if agent_kind == "cursor":
		_new_kind.select(3)
	elif agent_kind == "claude":
		_new_kind.select(2)
	else:
		_new_kind.select(0)
	_new_dialog.popup_centered()
	_new_name.grab_focus()


func _create_rule_file() -> void:
	var raw := _new_name.text.strip_edges().get_file().get_basename()
	var slug := RegEx.create_from_string("[^a-zA-Z0-9._-]").sub(raw, "-", true).trim_prefix("-").trim_suffix("-")
	if slug.is_empty():
		status_changed.emit(I18n.t("Enter a valid file name."), AgentTheme.ERROR)
		return
	var spec: Dictionary = NEW_RULE_DIRS[clampi(_new_kind.selected, 0, NEW_RULE_DIRS.size() - 1)]
	var rel := "%s/%s%s" % [spec.dir, slug, spec.ext]
	_switch_to(rel)


func _add_facts() -> void:
	var facts := ProjectFacts.section(ProjectFacts.current_settings(), Engine.get_version_info().string, ProjectFacts.top_folders(project_path))
	_editor.text = ProjectFacts.merge(_editor.text, facts)
	status_changed.emit(I18n.t("Project facts added to %s: save to keep them.") % _current, AgentTheme.MUTED)


func _save() -> void:
	if _editor.text == _saved_text:
		return
	var full_path := project_path.path_join(_current)
	DirAccess.make_dir_recursive_absolute(full_path.get_base_dir())
	var file := FileAccess.open(full_path, FileAccess.WRITE)
	if file == null:
		status_changed.emit(I18n.t("Could not save %s.") % _current, AgentTheme.ERROR)
		return
	file.store_string(_editor.text)
	file.close()
	_saved_text = _editor.text
	_fill_options()
	status_changed.emit(I18n.t("%s saved: agents read it from their next session.") % _current, AgentTheme.ADDED)
