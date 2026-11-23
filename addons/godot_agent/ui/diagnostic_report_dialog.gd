@tool
extends ConfirmationDialog
## «Copy diagnostic report…» (m11-80): muestra el informe tal como se va a copiar, para pegarlo en un
## issue. Solo valores de listas cerradas (ver DiagnosticReport): el texto lo dice antes de copiar.

const DiagnosticReport := preload("../core/diagnostic_report.gd")
const I18n := preload("../core/i18n.gd")
const AgentTheme := preload("agent_theme.gd")

## Lo que se copió (para los tests y el check del dock).
signal copied(text: String)

var report: Dictionary = {}
var _preview: TextEdit


func setup(value: Dictionary) -> void:
	report = value
	title = I18n.t("Diagnostic report")
	ok_button_text = I18n.t("Copy")
	get_cancel_button().text = I18n.t("Close")
	var box := VBoxContainer.new()
	box.add_theme_constant_override(&"separation", 8)
	var note := Label.new()
	note.text = I18n.t("Paste this in a bug report. It has only versions, the operating system, the agent and how the connection and the last error went, as fixed values: no paths, file names, conversation text, email or account.")
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.custom_minimum_size.x = 420 * AgentTheme.editor_scale()
	box.add_child(note)
	_preview = TextEdit.new()
	_preview.name = "Preview"
	_preview.editable = false
	_preview.text = DiagnosticReport.serialize(report)
	_preview.custom_minimum_size = Vector2(420, 320) * AgentTheme.editor_scale()
	_preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_preview.add_theme_font_override(&"font", AgentTheme.mono_font())
	box.add_child(_preview)
	add_child(box)
	confirmed.connect(_copy)


func preview_text() -> String:
	return _preview.text if _preview else ""


func _copy() -> void:
	var text := DiagnosticReport.clipboard_text(report)
	DisplayServer.clipboard_set(text)
	copied.emit(text)
