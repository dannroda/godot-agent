@tool
extends VBoxContainer
## La carpeta del proyecto de una pestaña de Extensions (recetas, modos, tools del proyecto) con
## «Cambiar…» (m12-58): antes se elegía en Ajustes → MCP → Avanzado, lejos de lo que guarda.

## La carpeta cambió (ya guardada en la config del proyecto).
signal changed

const I18n := preload("../../core/i18n.gd")
const AgentTheme := preload("../agent_theme.gd")
const ExtensionsUi := preload("extensions_ui.gd")

## () -> String: la carpeta actual (res://…).
var current: Callable
## (path: String) -> String: la guarda; devuelve el error para mostrar, o "".
var setter: Callable

var _label: Label
var _error: Label
var _dialog: EditorFileDialog


func _init(caption: String = "") -> void:
	add_theme_constant_override(&"separation", 0)
	var row := HBoxContainer.new()
	add_child(row)
	_label = ExtensionsUi.muted("")
	_label.name = "FolderLabel"
	_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_label.set_meta(&"caption", caption)
	row.add_child(_label)
	var change := Button.new()
	change.name = "ChangeFolder"
	change.text = I18n.t("Change folder…")
	change.tooltip_text = I18n.t("A folder inside the project, outside addons/godot_agent. Saved in the project's config, shared through git.")
	change.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	change.pressed.connect(_pick)
	row.add_child(change)
	_error = ExtensionsUi.error_label("")
	_error.visible = false
	add_child(_error)


func refresh() -> void:
	var path := str(current.call()) if current.is_valid() else ""
	_label.text = "%s %s" % [str(_label.get_meta(&"caption")), path]


## Guarda `path` como la carpeta (lo que hace el diálogo al elegir). Devuelve el error, o "".
func choose(path: String) -> String:
	var error: String = setter.call(path) if setter.is_valid() else ""
	_error.text = error
	_error.visible = not error.is_empty()
	if error.is_empty():
		refresh()
		changed.emit()
	return error


func _pick() -> void:
	if _dialog == null:
		_dialog = EditorFileDialog.new()
		_dialog.file_mode = EditorFileDialog.FILE_MODE_OPEN_DIR
		_dialog.access = EditorFileDialog.ACCESS_RESOURCES
		_dialog.dir_selected.connect(func(dir: String) -> void: choose(dir))
		add_child(_dialog)
	var path := str(current.call()) if current.is_valid() else "res://"
	_dialog.current_dir = path if DirAccess.dir_exists_absolute(path) else "res://"
	_dialog.popup_file_dialog()
