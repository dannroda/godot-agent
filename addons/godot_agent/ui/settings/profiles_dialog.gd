@tool
extends ConfirmationDialog
## Editor de perfiles de agentes (M1: JSON editable; el diálogo completo de Settings llega en M7).

const HarnessSettings := preload("../../core/harness_settings.gd")
const AgentProfile := preload("../../core/agent_profile.gd")
const AgentTheme := preload("../agent_theme.gd")

var _settings: HarnessSettings
var _editor: CodeEdit
var _error: Label


func setup(settings: HarnessSettings) -> void:
	_settings = settings


func _ready() -> void:
	title = "Perfiles de agentes"
	ok_button_text = "Guardar"
	min_size = Vector2i(AgentTheme.px(560), AgentTheme.px(420))
	var column := VBoxContainer.new()
	add_child(column)
	var help := Label.new()
	help.text = "Cada perfil: id, display_name, command, args[], env{} y default. En env, \"$VAR\" toma el valor de VAR del entorno del editor (no se guardan claves)."
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(help)
	_editor = CodeEdit.new()
	_editor.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_editor.add_theme_font_override(&"font", AgentTheme.mono_font())
	_editor.gutters_draw_line_numbers = true
	column.add_child(_editor)
	_error = Label.new()
	_error.add_theme_color_override(&"font_color", AgentTheme.ERROR)
	_error.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_error)
	var reset := Button.new()
	reset.text = "Restaurar perfiles por defecto"
	reset.flat = true
	reset.pressed.connect(func() -> void: _editor.text = JSON.stringify(AgentProfile.defaults(), "\t"))
	column.add_child(reset)
	get_ok_button().pressed.connect(_on_save)
	about_to_popup.connect(_load)


func _load() -> void:
	_error.text = ""
	var data: Array = []
	for profile: AgentProfile in _settings.profiles():
		data.append(profile.to_dict())
	_editor.text = JSON.stringify(data, "\t")


func _on_save() -> void:
	var json := JSON.new()
	if json.parse(_editor.text) != OK or not json.data is Array:
		_error.text = "JSON inválido (línea %d): %s" % [json.get_error_line(), json.get_error_message()]
		popup_centered.call_deferred()
		return
	var profiles: Array[AgentProfile] = []
	var ids: Dictionary = {}
	for item: Variant in json.data:
		if not item is Dictionary:
			continue
		var profile: AgentProfile = AgentProfile.from_dict(item)
		if profile.id.is_empty() or ids.has(profile.id):
			_error.text = "Cada perfil necesita un id único."
			popup_centered.call_deferred()
			return
		ids[profile.id] = true
		profiles.append(profile)
	_settings.save_profiles(profiles)
