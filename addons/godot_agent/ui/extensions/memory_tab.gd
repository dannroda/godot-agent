@tool
extends MarginContainer
## Pestaña «Memory» de Extensions (m11-36): todo lo que se recuerda del proyecto, junto y por entrada.
## - Recordado con /remember, en la sección del harness del archivo de instrucciones del agente
##   (editar, borrar, agregar).
## - Lo que aprendieron los playtests: notas (editar, borrar), hallazgos «no es un bug» (borrar),
##   scripts guardados (ver, borrar).
## - Traspasos y planes aprobados (ver, borrar).
## - Las memorias de Claude Code de este proyecto, de la cuenta de la pestaña activa (ver; borrar las
##   manda a la papelera). Se leen solo al mostrar la pestaña: nunca en segundo plano.

signal status_changed(text: String, color: Color)

const I18n := preload("../../core/i18n.gd")
const AgentTheme := preload("../agent_theme.gd")
const ExtensionsUi := preload("extensions_ui.gd")
const ProjectMemory := preload("../../core/project_memory.gd")
const PlaytestMemory := preload("../../review/playtest_memory.gd")
const InstructionsTab := preload("instructions_tab.gd")
const Handoff := preload("../../session/handoff.gd")
const PlanStore := preload("../../session/plan_store.gd")
const AgentProfile := preload("../../core/agent_profile.gd")

const KIND_REMEMBERED := "remembered"
const KIND_NOTE := "note"
const KIND_NOT_A_BUG := "not_a_bug"
const KIND_SCRIPT := "script"
const KIND_FILE := "file"
const KIND_CLAUDE := "claude"
const EDITABLE: PackedStringArray = [KIND_REMEMBERED, KIND_NOTE]

var project_path: String = ""
var agent_kind: String = "claude"
## El entorno del perfil de la pestaña activa (con su cuenta): de ahí sale la carpeta de Claude Code.
var agent_env: Dictionary = {}
## Para las pruebas: la carpeta del usuario y cómo se manda a la papelera.
var home: String = ""
var trash: Callable = Callable()
var playtests_dir: String = PlaytestMemory.DIR

var _tree: Tree
var _header: Label
var _editor: TextEdit
var _save_button: Button
var _delete_button: Button
var _new_line: LineEdit
var _confirm: ConfirmationDialog
var _selected: Dictionary = {}
var _filling: bool = false


func _init() -> void:
	name = "Memory"
	for side: String in ["left", "right", "top", "bottom"]:
		add_theme_constant_override("margin_" + side, AgentTheme.px(6))
	var page := VBoxContainer.new()
	page.add_theme_constant_override(&"separation", AgentTheme.px(6))
	add_child(page)
	page.add_child(ExtensionsUi.muted(I18n.t("What is remembered about this project: what you saved with /remember, what playtests learned, handoffs and plans, and the agent's own memory. Edit or delete each entry.")))
	var split := HBoxContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.add_theme_constant_override(&"separation", AgentTheme.px(8))
	page.add_child(split)
	var left := VBoxContainer.new()
	left.custom_minimum_size.x = AgentTheme.px(260)
	split.add_child(left)
	_tree = Tree.new()
	_tree.name = "MemoryEntries"
	_tree.hide_root = true
	_tree.select_mode = Tree.SELECT_ROW
	_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tree.item_selected.connect(func() -> void:
		if not _filling and _tree.get_selected():
			_show(_tree.get_selected().get_metadata(0)))
	left.add_child(_tree)
	var add_row := HBoxContainer.new()
	left.add_child(add_row)
	_new_line = LineEdit.new()
	_new_line.name = "RememberLine"
	_new_line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_new_line.placeholder_text = I18n.t("Something to remember…")
	_new_line.text_submitted.connect(func(_text: String) -> void: _add_remembered())
	add_row.add_child(_new_line)
	var add := Button.new()
	add.text = I18n.t("Remember")
	add.tooltip_text = I18n.t("Adds it to the harness section of the agent's instructions file, like /remember in the composer.")
	add.pressed.connect(_add_remembered)
	add_row.add_child(add)
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.add_child(right)
	_header = ExtensionsUi.muted("")
	_header.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	right.add_child(_header)
	_editor = TextEdit.new()
	_editor.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_editor.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_editor.add_theme_font_override(&"font", AgentTheme.mono_font())
	right.add_child(_editor)
	var buttons := HBoxContainer.new()
	right.add_child(buttons)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	buttons.add_child(spacer)
	_delete_button = Button.new()
	_delete_button.name = "DeleteMemoryButton"
	_delete_button.text = I18n.t("Delete")
	_delete_button.pressed.connect(_on_delete)
	buttons.add_child(_delete_button)
	_save_button = Button.new()
	_save_button.text = I18n.t("Save")
	_save_button.pressed.connect(_on_save)
	buttons.add_child(_save_button)
	_confirm = ConfirmationDialog.new()
	_confirm.name = "DeleteMemoryConfirm"
	_confirm.title = I18n.t("Delete memory")
	_confirm.ok_button_text = I18n.t("Move to trash")
	_confirm.cancel_button_text = I18n.t("Cancel")
	_confirm.confirmed.connect(_trash_selected)
	add_child(_confirm)
	_show({})


func _root() -> String:
	return project_path if not project_path.is_empty() else ProjectSettings.globalize_path("res://")


func _home() -> String:
	return home if not home.is_empty() else AgentProfile.home_dir()


func instructions_file() -> String:
	return InstructionsTab.default_file_for(agent_kind, _root())


## La carpeta de memorias de Claude Code de este proyecto con la cuenta de la pestaña ("" con otro agente).
func claude_memory_dir() -> String:
	if agent_kind != "claude":
		return ""
	return ProjectMemory.claude_memory_dir(ProjectMemory.claude_config_dir(agent_env, _home()), _root())


## Vuelve a leer todo. Solo la llama la ventana con esta pestaña a la vista.
func refresh() -> void:
	var keep := _selected.duplicate()
	_filling = true
	_tree.clear()
	var root := _tree.create_item()
	var file := instructions_file()
	var group := _group(root, I18n.t("Remembered · %s") % file, I18n.t("Read by %s at the start of each session.") % InstructionsTab.reader_of(file))
	var remembered := ProjectMemory.read_remembered(_root().path_join(file))
	for line: String in remembered:
		_entry(group, line, {"kind": KIND_REMEMBERED, "file": file, "line": line})
	if remembered.is_empty():
		_placeholder(group, I18n.t("Nothing yet: use /remember in the composer or the field below."))
	var memory := PlaytestMemory.new(playtests_dir)
	group = _group(root, I18n.t("What playtests learned"), I18n.t("Facts the agent verified while playing; it reads them before each playtest."))
	for note: String in memory.notes():
		_entry(group, note, {"kind": KIND_NOTE, "note": note})
	for signature: String in memory.not_a_bug():
		_entry(group, I18n.t("Not a bug: %s") % signature, {"kind": KIND_NOT_A_BUG, "signature": signature})
	for path: String in memory.scripts():
		_entry(group, I18n.t("Script: %s") % path.get_file(), {"kind": KIND_SCRIPT, "path": path})
	if group.get_child_count() == 0:
		_placeholder(group, I18n.t("No playtests yet."))
	group = _group(root, I18n.t("Handoffs and plans"), I18n.t("Handoffs between sessions and approved plans, in .godot_agent/."))
	for item: Dictionary in Handoff.list(_root()):
		_entry(group, I18n.t("Handoff · %s") % (str(item.title) if not str(item.title).is_empty() else str(item.path).get_file()), {"kind": KIND_FILE, "path": str(item.path)})
	var plans_dir := _root().path_join(PlanStore.DIR)
	if DirAccess.dir_exists_absolute(plans_dir):
		var names := Array(DirAccess.get_files_at(plans_dir)).filter(func(n: String) -> bool: return n.get_extension() == "md")
		names.sort()
		names.reverse()
		for plan_name: String in names:
			_entry(group, I18n.t("Plan · %s") % plan_name.get_basename(), {"kind": KIND_FILE, "path": plans_dir.path_join(plan_name)})
	if group.get_child_count() == 0:
		_placeholder(group, I18n.t("None yet."))
	var claude_dir := claude_memory_dir()
	if claude_dir.is_empty():
		group = _group(root, I18n.t("The agent's own memory"), "")
		_placeholder(group, I18n.t("The harness can't read this agent's own memory."))
	else:
		group = _group(root, I18n.t("Claude Code's memory"), I18n.t("Read only from %s, when this tab is shown.") % claude_dir)
		for item: Dictionary in ProjectMemory.claude_memories(claude_dir):
			var label := I18n.t("Index (MEMORY.md)") if item.index else str(item.name)
			_entry(group, label, {"kind": KIND_CLAUDE, "path": item.path, "dir": claude_dir, "index": item.index, "description": item.description, "text": item.text})
		if group.get_child_count() == 0:
			_placeholder(group, I18n.t("Claude Code hasn't saved memories for this project with this account."))
	_filling = false
	_reselect(keep)


func _group(root: TreeItem, title: String, tooltip: String) -> TreeItem:
	var item := _tree.create_item(root)
	item.set_text(0, title)
	item.set_selectable(0, false)
	item.set_custom_color(0, AgentTheme.MUTED)
	item.set_tooltip_text(0, tooltip)
	return item


func _entry(group: TreeItem, text: String, data: Dictionary) -> void:
	var item := _tree.create_item(group)
	item.set_text(0, text.left(120))
	item.set_tooltip_text(0, text)
	item.set_metadata(0, data)


func _placeholder(group: TreeItem, text: String) -> void:
	var item := _tree.create_item(group)
	item.set_text(0, text)
	item.set_selectable(0, false)
	item.set_custom_color(0, AgentTheme.MUTED)


func _reselect(keep: Dictionary) -> void:
	var found: TreeItem = null
	if not keep.is_empty():
		for group: TreeItem in _tree.get_root().get_children():
			for item: TreeItem in group.get_children():
				var data: Variant = item.get_metadata(0)
				if data is Dictionary and _same(data, keep):
					found = item
	if found:
		found.select(0)
		_show(found.get_metadata(0))
	else:
		_show({})


static func _same(a: Dictionary, b: Dictionary) -> bool:
	for key: String in ["kind", "line", "note", "signature", "path"]:
		if a.get(key) != b.get(key):
			return false
	return true


## Las entradas del árbol como [{kind, text}] (para las pruebas y los checks).
func entries() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if _tree.get_root() == null:
		return result
	for group: TreeItem in _tree.get_root().get_children():
		for item: TreeItem in group.get_children():
			var data: Variant = item.get_metadata(0)
			if data is Dictionary:
				result.append({"kind": data.kind, "text": item.get_text(0), "data": data})
	return result


## Elige una entrada (para los checks): la primera de ese tipo cuyo texto contiene `text`.
func select_entry(kind: String, text: String) -> bool:
	for group: TreeItem in _tree.get_root().get_children():
		for item: TreeItem in group.get_children():
			var data: Variant = item.get_metadata(0)
			if data is Dictionary and data.kind == kind and item.get_text(0).contains(text):
				item.select(0)
				_show(data)
				return true
	return false


func _show(data: Variant) -> void:
	_selected = data if data is Dictionary else {}
	var kind := str(_selected.get("kind", ""))
	_editor.editable = kind in EDITABLE
	_save_button.visible = kind in EDITABLE
	_delete_button.visible = not kind.is_empty() and not bool(_selected.get("index", false))
	_delete_button.text = I18n.t("Move to trash…") if kind == KIND_CLAUDE else I18n.t("Delete")
	match kind:
		KIND_REMEMBERED:
			_header.text = I18n.t("In %s, between the harness markers. Edit the line or delete it.") % _selected.file
			_editor.text = str(_selected.line)
		KIND_NOTE:
			_header.text = I18n.t("Playtest note (.godot_agent/playtests/notes.md).")
			_editor.text = str(_selected.note)
		KIND_NOT_A_BUG:
			_header.text = I18n.t("A finding marked «not a bug»: neither the detectors nor the agent bring it up again. Delete it to see it again.")
			_editor.text = str(_selected.signature)
		KIND_SCRIPT, KIND_FILE:
			_header.text = str(_selected.path)
			_editor.text = FileAccess.get_file_as_string(str(_selected.path))
		KIND_CLAUDE:
			var head := str(_selected.path)
			if not str(_selected.description).is_empty():
				head += "\n" + str(_selected.description)
			_header.text = head + "\n" + (I18n.t("Claude Code keeps it up to date: the index can't be deleted from here.") if _selected.index else I18n.t("Claude Code keeps it up to date: it can't be edited from here, only moved to the trash."))
			_editor.text = str(_selected.text)
		_:
			_header.text = I18n.t("Choose an entry on the left.")
			_editor.text = ""
	_editor.clear_undo_history()


func _on_save() -> void:
	var value := _editor.text
	match str(_selected.get("kind", "")):
		KIND_REMEMBERED:
			_report(ProjectMemory.replace(_root().path_join(str(_selected.file)), str(_selected.line), value), I18n.t("Saved in %s.") % _selected.file)
			_selected.line = ProjectMemory.clean_line(value)
		KIND_NOTE:
			var memory := PlaytestMemory.new(playtests_dir)
			var notes := memory.notes()
			var at := notes.find(str(_selected.note))
			var line := " ".join(value.strip_edges().split("\n", false))
			if at >= 0:
				if line.is_empty():
					notes.remove_at(at)
				else:
					notes[at] = line
				memory.set_notes(notes)
			_selected.note = line
			_report("", I18n.t("Playtest note saved."))
	refresh()


func _on_delete() -> void:
	match str(_selected.get("kind", "")):
		KIND_REMEMBERED:
			_report(ProjectMemory.forget(_root().path_join(str(_selected.file)), str(_selected.line)), I18n.t("Removed from %s.") % _selected.file)
		KIND_NOTE:
			var memory := PlaytestMemory.new(playtests_dir)
			var notes := memory.notes()
			var at := notes.find(str(_selected.note))
			if at >= 0:
				notes.remove_at(at)
				memory.set_notes(notes)
			_report("", I18n.t("Playtest note deleted."))
		KIND_NOT_A_BUG:
			PlaytestMemory.new(playtests_dir).unmark_not_a_bug(str(_selected.signature))
			_report("", I18n.t("The finding can show up again."))
		KIND_SCRIPT:
			PlaytestMemory.new(playtests_dir).remove_script(str(_selected.path))
			_report("", I18n.t("Script deleted."))
		KIND_FILE:
			var path := str(_selected.path)
			var removed := DirAccess.remove_absolute(path) if FileAccess.file_exists(path) else OK
			_report("" if removed == OK else error_string(removed), I18n.t("Deleted %s.") % path.get_file())
		KIND_CLAUDE:
			_confirm.dialog_text = I18n.t("Move «%s» to the trash? Claude Code stops reading it from its next session, and its line leaves MEMORY.md. You can restore it from the trash.") % str(_selected.path).get_file()
			_confirm.popup_centered()
			return
	_selected = {}
	refresh()


func _trash_selected() -> void:
	if str(_selected.get("kind", "")) != KIND_CLAUDE:
		return
	var error := ProjectMemory.trash_claude_memory(str(_selected.path), str(_selected.dir), trash)
	_report(error, I18n.t("Moved to the trash: %s.") % str(_selected.path).get_file())
	_selected = {}
	refresh()


func _add_remembered() -> void:
	var line := ProjectMemory.clean_line(_new_line.text)
	if line.is_empty():
		return
	var file := instructions_file()
	_report(ProjectMemory.remember(_root().path_join(file), line), I18n.t("Saved in %s.") % file)
	_new_line.clear()
	_selected = {"kind": KIND_REMEMBERED, "line": line}
	refresh()


func _report(error: String, done: String) -> void:
	if error.is_empty():
		status_changed.emit(done, AgentTheme.ADDED)
	else:
		status_changed.emit(I18n.t("Could not save: %s") % error, AgentTheme.ERROR)
