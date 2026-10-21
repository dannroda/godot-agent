@tool
extends RefCounted
## Settings por usuario (spec §11): perfiles de agentes, color de acento y demás, en EditorSettings
## con el prefijo `godot_agent/`. Sin EditorSettings (tests headless) guarda en memoria.

signal changed(key: String)

const AgentProfile := preload("agent_profile.gd")

const PREFIX := "godot_agent/"
const KEY_PROFILES := "agents/profiles"
const KEY_ACCENT := "ui/accent_color"
const KEY_LAST_PROFILE := "agents/last_profile"

const DEFAULT_ACCENT := Color("#f0a85a")

var _editor_settings: EditorSettings
var _memory: Dictionary = {}


func _init(editor_settings: EditorSettings = null) -> void:
	_editor_settings = editor_settings
	if _editor_settings:
		_declare(KEY_ACCENT, DEFAULT_ACCENT, TYPE_COLOR)
		_declare(KEY_PROFILES, JSON.stringify(AgentProfile.defaults()), TYPE_STRING, PROPERTY_HINT_MULTILINE_TEXT)
		_declare(KEY_LAST_PROFILE, "", TYPE_STRING)


func get_value(key: String, default_value: Variant = null) -> Variant:
	if _editor_settings:
		var full := PREFIX + key
		return _editor_settings.get_setting(full) if _editor_settings.has_setting(full) else default_value
	return _memory.get(key, default_value)


func set_value(key: String, value: Variant) -> void:
	if _editor_settings:
		_editor_settings.set_setting(PREFIX + key, value)
	else:
		_memory[key] = value
	changed.emit(key)


func accent_color() -> Color:
	var value: Variant = get_value(KEY_ACCENT, DEFAULT_ACCENT)
	return value if value is Color else DEFAULT_ACCENT


func profiles() -> Array[AgentProfile]:
	var result: Array[AgentProfile] = []
	var raw: Variant = get_value(KEY_PROFILES, "")
	var data: Variant = JSON.parse_string(raw) if raw is String and not raw.is_empty() else null
	if not data is Array:
		data = AgentProfile.defaults()
	for item: Variant in data:
		if item is Dictionary:
			var profile: AgentProfile = AgentProfile.from_dict(item)
			if not profile.id.is_empty():
				result.append(profile)
	return result


func save_profiles(list: Array[AgentProfile]) -> void:
	var data: Array = []
	for profile: AgentProfile in list:
		data.append(profile.to_dict())
	set_value(KEY_PROFILES, JSON.stringify(data, "\t"))


func profile(id: String) -> AgentProfile:
	for candidate: AgentProfile in profiles():
		if candidate.id == id:
			return candidate
	return null


## El último usado, si sigue existiendo; si no, el marcado como default; si no, el primero.
func active_profile() -> AgentProfile:
	var list := profiles()
	var last := str(get_value(KEY_LAST_PROFILE, ""))
	for candidate: AgentProfile in list:
		if candidate.id == last:
			return candidate
	for candidate: AgentProfile in list:
		if candidate.is_default:
			return candidate
	return list[0] if not list.is_empty() else null


func set_active_profile(id: String) -> void:
	set_value(KEY_LAST_PROFILE, id)


func _declare(key: String, default_value: Variant, type: Variant.Type, hint: PropertyHint = PROPERTY_HINT_NONE) -> void:
	var full := PREFIX + key
	if not _editor_settings.has_setting(full):
		_editor_settings.set_setting(full, default_value)
	_editor_settings.set_initial_value(full, default_value, false)
	_editor_settings.add_property_info({"name": full, "type": type, "hint": hint})
