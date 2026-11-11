@tool
extends ConfirmationDialog
## «Export session…» (m11-32): vista previa del session.md y qué sacar antes de guardar. Cada casilla
## dice cuánto encontró (rutas absolutas, emails, contenido de afuera, capturas) y la vista previa
## cambia al marcarla. Guardar escribe en .godot_agent/reports/<fecha>-session/.

const SessionExport := preload("../../session/session_export.gd")
const SessionModel := preload("../../session/session_model.gd")
const I18n := preload("../../core/i18n.gd")
const AgentTheme := preload("../agent_theme.gd")

signal saved(path: String)

const SHOWN_FOUND := 8

var root: String = SessionExport.DIR
var _model: SessionModel
var _context: Dictionary = {}
var _boxes: Dictionary = {}
var _preview: TextEdit
var _found: Dictionary = {}
var _image_count: int = 0


func _init() -> void:
	auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	title = I18n.t("Export session")
	ok_button_text = I18n.t("Save")
	cancel_button_text = I18n.t("Cancel")
	var column := VBoxContainer.new()
	column.add_theme_constant_override(&"separation", AgentTheme.px(6))
	add_child(column)
	var intro := Label.new()
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	intro.text = I18n.t("A Markdown file with the requests, the answers, the tool calls and the game captures, to share. Check what to take out; the preview shows what will be saved. Secrets such as the MCP token are always removed.")
	column.add_child(intro)
	for key: String in ["paths", "emails", "untrusted", "images"]:
		var box := CheckBox.new()
		box.name = "Option_" + key
		box.button_pressed = true
		box.toggled.connect(func(_on: bool) -> void: refresh())
		column.add_child(box)
		_boxes[key] = box
	_preview = TextEdit.new()
	_preview.name = "Preview"
	_preview.editable = false
	_preview.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_preview.custom_minimum_size = Vector2(AgentTheme.px(560), AgentTheme.px(340))
	_preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_preview.add_theme_font_override(&"font", AgentTheme.mono_font())
	_preview.add_theme_font_size_override(&"font_size", AgentTheme.mono_font_size())
	column.add_child(_preview)
	confirmed.connect(save)


## `context` como SessionExport.build (title, project, home, emails, redact).
func setup(model: SessionModel, context: Dictionary) -> void:
	_model = model
	_context = context
	var raw := SessionExport.build(model, context, {})
	_found = SessionExport.find(str(raw.raw), context)
	_image_count = (raw.images as Array).size()
	_label(&"paths", I18n.t("Remove absolute paths (%d)") % (_found.paths as PackedStringArray).size(), _found.paths)
	_label(&"emails", I18n.t("Remove email addresses (%d)") % (_found.emails as PackedStringArray).size(), _found.emails)
	_label(&"untrusted", I18n.t("Remove content from outside the project: game, scenes, web (%d)") % int(_found.untrusted), PackedStringArray())
	_boxes.untrusted.tooltip_text = I18n.t("What tools brought from the game, the project's scenes or the internet. It can carry names and text you didn't write.")
	_label(&"images", I18n.t("Remove the captures (%d)") % _image_count, PackedStringArray())
	_boxes.images.button_pressed = false  # las capturas son lo que hace útil el export: van salvo que se saquen
	refresh()


func options() -> Dictionary:
	var result := {}
	for key: String in _boxes:
		result[key] = (_boxes[key] as CheckBox).button_pressed
	return result


func preview_text() -> String:
	return _preview.text


func refresh() -> void:
	if _model:
		_preview.text = str(SessionExport.build(_model, _context, options()).markdown)


## Guarda con las opciones marcadas; emite `saved` con la ruta de session.md ("" si no se pudo).
func save() -> void:
	var stamp := Time.get_datetime_string_from_system().replace(":", "-").replace("T", "_")
	saved.emit(SessionExport.write(root, stamp, SessionExport.build(_model, _context, options())))


func _label(key: StringName, text: String, found: PackedStringArray) -> void:
	var box: CheckBox = _boxes[key]
	box.text = text
	if not found.is_empty():
		var shown := found.slice(0, SHOWN_FOUND)
		box.tooltip_text = "\n".join(shown) + ("\n… +%d" % (found.size() - SHOWN_FOUND) if found.size() > SHOWN_FOUND else "")
