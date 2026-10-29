@tool
extends RefCounted
## Settings por usuario (spec §11): perfiles de agentes, color de acento y demás, en EditorSettings
## con el prefijo `godot_agent/`. Sin EditorSettings (tests headless) guarda en memoria.

signal changed(key: String)

const AgentProfile := preload("agent_profile.gd")
const LlmProfile := preload("../completion/llm/llm_profile.gd")
const ExternalMcpServers := preload("../mcp/external_mcp_servers.gd")

const PREFIX := "godot_agent/"
const KEY_PROFILES := "agents/profiles"
const KEY_ACCENT := "ui/accent_color"
const KEY_LAST_PROFILE := "agents/last_profile"
## Ya se quitaron los presets viejos (m12-37).
const KEY_PRESETS_RETIRED := "agents/presets_retired"
## Perfiles que se preseteaban hasta 0.1.7 y ya no sirven: Gemini CLI se discontinuó (lo reemplaza
## Antigravity) y el Codex venía sin comando. Sin `default`: no cuenta para comparar.
const RETIRED_PRESETS: Array[Dictionary] = [
	{"id": "gemini-cli", "display_name": "Gemini CLI", "command": "gemini", "args": [], "env": {}},
	{"id": "codex", "display_name": "Codex", "command": "", "args": [], "env": {}},
]
## Puerto del server MCP (0 = aleatorio en cada arranque).
const KEY_MCP_PORT := "mcp/port"
## MCP servers de terceros para todos los proyectos del usuario (m7-34), JSON.
const KEY_MCP_SERVERS := "mcp/servers"
## Cuota del plan (spec §10.1, §9.5): umbrales en %, pausa del One-shot y qué hacer al reiniciarse.
const KEY_QUOTA_WARN := "quota/warn_percent"
const KEY_QUOTA_PAUSE := "quota/pause_percent"
const KEY_QUOTA_PAUSE_ENABLED := "quota/pause_enabled"
const KEY_QUOTA_RESUME := "quota/resume_mode"
const RESUME_AUTO := 0
const RESUME_CONFIRM := 1
const KEY_DOCK_SLOT := "ui/dock_slot"
## Al abrir el editor (m12-12): el dock muestra las sesiones anteriores o continúa la última.
const KEY_ON_OPEN := "ui/on_open"
const ON_OPEN_LIST := 0
const ON_OPEN_CONTINUE := 1
## Idioma de la interfaz (D46): "auto" (el del editor), "en", "es".
const KEY_LANGUAGE := "ui/language"
## Actualizaciones del addon (m7-38): buscar al abrir el editor (una vez por día), cuándo se buscó
## por última vez (unix) y la versión a la que se le dijo «Después».
const KEY_UPDATE_CHECK := "update/check_on_start"
const KEY_UPDATE_LAST_CHECK := "update/last_check"
const KEY_UPDATE_DISMISSED := "update/dismissed_version"
## Completado predictivo (spec §16.10): on/off global, debounce local y umbral/margen del ranker.
const KEY_COMPLETION_ENABLED := "completion/enabled"
const KEY_COMPLETION_DEBOUNCE := "completion/local_debounce_ms"
const KEY_COMPLETION_THRESHOLD := "completion/threshold"
const KEY_COMPLETION_MARGIN := "completion/margin"
## Sugerencias de varias líneas y su máximo; fuentes locales activas; carpetas de corpus extra
## (otros proyectos propios) para el n-gram.
const KEY_COMPLETION_MULTILINE := "completion/multiline"
const KEY_COMPLETION_MAX_LINES := "completion/max_lines"
const KEY_COMPLETION_SOURCE_PREFIX := "completion/sources/"
const COMPLETION_SOURCES: PackedStringArray = ["rule", "retrieval", "ngram", "history"]
const KEY_COMPLETION_EXTRA_CORPUS := "completion/extra_corpus"
## Modo (spec §16.1): solo local, híbrido o solo LLM. Perfiles LLM (JSON, sin keys), el activo y
## los parámetros del pedido (§16.10). `llm_marker`: matiz para distinguir las sugerencias del LLM.
## `log_raw`: el log incluye el código (apagado: nunca se loguea código).
const KEY_COMPLETION_MODE := "completion/mode"
const COMPLETION_MODES: PackedStringArray = ["local", "hybrid", "llm"]
const KEY_COMPLETION_LLM_PROFILES := "completion/llm/profiles"
const KEY_COMPLETION_LLM_ACTIVE := "completion/llm/active"
const KEY_COMPLETION_LLM_DEBOUNCE := "completion/llm/debounce_ms"
const KEY_COMPLETION_LLM_PREFIX := "completion/llm/prefix_chars"
const KEY_COMPLETION_LLM_SUFFIX := "completion/llm/suffix_chars"
const KEY_COMPLETION_LLM_CONTEXT := "completion/llm/context_tokens"
const KEY_COMPLETION_LLM_MARKER := "completion/llm/marker"
const KEY_COMPLETION_LOG_RAW := "completion/log_raw"
## Nombres de las constantes de slot (iguales en EditorPlugin y EditorDock), en el orden del setting.
const DOCK_SLOTS: PackedStringArray = ["DOCK_SLOT_RIGHT_UL", "DOCK_SLOT_RIGHT_BL", "DOCK_SLOT_LEFT_UL", "DOCK_SLOT_LEFT_BL"]

const DEFAULT_ACCENT := Color("#f0a85a")

var _editor_settings: EditorSettings
var _memory: Dictionary = {}


func _init(editor_settings: EditorSettings = null) -> void:
	_editor_settings = editor_settings
	if _editor_settings:
		_declare(KEY_ACCENT, DEFAULT_ACCENT, TYPE_COLOR)
		_declare(KEY_PROFILES, "[]", TYPE_STRING, PROPERTY_HINT_MULTILINE_TEXT)
		_declare(KEY_LAST_PROFILE, "", TYPE_STRING)
		_declare(KEY_PRESETS_RETIRED, false, TYPE_BOOL)
		_declare(KEY_MCP_PORT, 0, TYPE_INT, PROPERTY_HINT_RANGE, "0,65535,1")
		_declare(KEY_MCP_SERVERS, "[]", TYPE_STRING, PROPERTY_HINT_MULTILINE_TEXT)
		_declare(KEY_QUOTA_WARN, 75, TYPE_INT, PROPERTY_HINT_RANGE, "1,100,1,suffix:%")
		_declare(KEY_QUOTA_PAUSE, 90, TYPE_INT, PROPERTY_HINT_RANGE, "1,100,1,suffix:%")
		_declare(KEY_QUOTA_PAUSE_ENABLED, true, TYPE_BOOL)
		_declare(KEY_QUOTA_RESUME, RESUME_AUTO, TYPE_INT, PROPERTY_HINT_ENUM, "Resume automatically,Wait for confirmation")
		_declare(KEY_LANGUAGE, "auto", TYPE_STRING, PROPERTY_HINT_ENUM, "auto,en,es")
		_declare(KEY_UPDATE_CHECK, true, TYPE_BOOL)
		_declare(KEY_UPDATE_LAST_CHECK, 0, TYPE_INT)
		_declare(KEY_UPDATE_DISMISSED, "", TYPE_STRING)
		_declare(KEY_DOCK_SLOT, 0, TYPE_INT, PROPERTY_HINT_ENUM, "Right top,Right bottom,Left top,Left bottom")
		_declare(KEY_ON_OPEN, ON_OPEN_LIST, TYPE_INT, PROPERTY_HINT_ENUM, "Show the previous sessions,Continue the last session")
		_declare(KEY_COMPLETION_ENABLED, true, TYPE_BOOL)
		_declare(KEY_COMPLETION_DEBOUNCE, 30, TYPE_INT, PROPERTY_HINT_RANGE, "0,200,1,suffix:ms")
		_declare(KEY_COMPLETION_THRESHOLD, 0.5, TYPE_FLOAT, PROPERTY_HINT_RANGE, "0.05,1,0.01")
		_declare(KEY_COMPLETION_MARGIN, 0.12, TYPE_FLOAT, PROPERTY_HINT_RANGE, "0,0.5,0.01")
		_declare(KEY_COMPLETION_MULTILINE, true, TYPE_BOOL)
		_declare(KEY_COMPLETION_MAX_LINES, 8, TYPE_INT, PROPERTY_HINT_RANGE, "1,16,1")
		for source: String in COMPLETION_SOURCES:
			_declare(KEY_COMPLETION_SOURCE_PREFIX + source, true, TYPE_BOOL)
		_declare(KEY_COMPLETION_EXTRA_CORPUS, PackedStringArray(), TYPE_PACKED_STRING_ARRAY, PROPERTY_HINT_TYPE_STRING, "%d/%d:" % [TYPE_STRING, PROPERTY_HINT_GLOBAL_DIR])
		_declare(KEY_COMPLETION_MODE, 0, TYPE_INT, PROPERTY_HINT_ENUM, "Local only,Hybrid,LLM only")
		_declare(KEY_COMPLETION_LLM_PROFILES, JSON.stringify(LlmProfile.defaults()), TYPE_STRING, PROPERTY_HINT_MULTILINE_TEXT)
		_declare(KEY_COMPLETION_LLM_ACTIVE, "", TYPE_STRING)
		_declare(KEY_COMPLETION_LLM_DEBOUNCE, 200, TYPE_INT, PROPERTY_HINT_RANGE, "75,1000,1,suffix:ms")
		_declare(KEY_COMPLETION_LLM_PREFIX, 4000, TYPE_INT, PROPERTY_HINT_RANGE, "200,32000,100")
		_declare(KEY_COMPLETION_LLM_SUFFIX, 1000, TYPE_INT, PROPERTY_HINT_RANGE, "0,16000,100")
		_declare(KEY_COMPLETION_LLM_CONTEXT, 2000, TYPE_INT, PROPERTY_HINT_RANGE, "0,16000,50")
		_declare(KEY_COMPLETION_LLM_MARKER, true, TYPE_BOOL)
		_declare(KEY_COMPLETION_LOG_RAW, false, TYPE_BOOL)


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
		return result
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


## Quita una sola vez los presets viejos que siguen tal como venían (uno editado se queda).
## Devuelve los nombres quitados, para el log.
func retire_old_presets() -> PackedStringArray:
	var removed: PackedStringArray = []
	if bool(get_value(KEY_PRESETS_RETIRED, false)):
		return removed
	var kept: Array[AgentProfile] = []
	for candidate: AgentProfile in profiles():
		if _is_retired_preset(candidate):
			removed.append(candidate.display_name)
			if str(get_value(KEY_LAST_PROFILE, "")) == candidate.id:
				set_value(KEY_LAST_PROFILE, "")
		else:
			kept.append(candidate)
	if not removed.is_empty():
		save_profiles(kept)
	set_value(KEY_PRESETS_RETIRED, true)
	return removed


static func _is_retired_preset(candidate: AgentProfile) -> bool:
	var data := candidate.to_dict()
	data.erase("default")
	for preset: Dictionary in RETIRED_PRESETS:
		if data == preset:
			return true
	return false


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


func mcp_port() -> int:
	return clampi(int(get_value(KEY_MCP_PORT, 0)), 0, 65535)


func mcp_servers() -> Array:
	var raw: Variant = get_value(KEY_MCP_SERVERS, "")
	return ExternalMcpServers.normalize_list(JSON.parse_string(raw) if raw is String and not raw.is_empty() else [])


func save_mcp_servers(list: Array) -> void:
	set_value(KEY_MCP_SERVERS, JSON.stringify(list, "\t"))


func quota_warn() -> float:
	return clampi(int(get_value(KEY_QUOTA_WARN, 75)), 1, 100) / 100.0


func quota_pause() -> float:
	return clampi(int(get_value(KEY_QUOTA_PAUSE, 90)), 1, 100) / 100.0


func quota_pause_enabled() -> bool:
	return bool(get_value(KEY_QUOTA_PAUSE_ENABLED, true))


func quota_resume_auto() -> bool:
	return int(get_value(KEY_QUOTA_RESUME, RESUME_AUTO)) == RESUME_AUTO


## Índice en DOCK_SLOTS.
func language() -> String:
	return str(get_value(KEY_LANGUAGE, "auto"))


func update_check_on_start() -> bool:
	return bool(get_value(KEY_UPDATE_CHECK, true))


func continue_on_open() -> bool:
	return int(get_value(KEY_ON_OPEN, ON_OPEN_LIST)) == ON_OPEN_CONTINUE


func dock_slot() -> int:
	return clampi(int(get_value(KEY_DOCK_SLOT, 0)), 0, DOCK_SLOTS.size() - 1)


func completion_enabled() -> bool:
	return bool(get_value(KEY_COMPLETION_ENABLED, true))


func completion_debounce_ms() -> int:
	return clampi(int(get_value(KEY_COMPLETION_DEBOUNCE, 30)), 0, 200)


func completion_threshold() -> float:
	return clampf(float(get_value(KEY_COMPLETION_THRESHOLD, 0.5)), 0.05, 1.0)


func completion_margin() -> float:
	return clampf(float(get_value(KEY_COMPLETION_MARGIN, 0.12)), 0.0, 0.5)


## Máximo de líneas por sugerencia (1 si el multilínea está apagado).
func completion_max_lines() -> int:
	if not bool(get_value(KEY_COMPLETION_MULTILINE, true)):
		return 1
	return clampi(int(get_value(KEY_COMPLETION_MAX_LINES, 8)), 1, 16)


## Fuentes locales activas: {rule, retrieval, ngram, history: bool}.
func completion_sources() -> Dictionary:
	var out := {}
	for source: String in COMPLETION_SOURCES:
		out[source] = bool(get_value(KEY_COMPLETION_SOURCE_PREFIX + source, true))
	return out


func completion_extra_corpus() -> PackedStringArray:
	var value: Variant = get_value(KEY_COMPLETION_EXTRA_CORPUS, PackedStringArray())
	return PackedStringArray(value) if value is PackedStringArray or value is Array else PackedStringArray()


## "local", "hybrid" o "llm".
func completion_mode() -> String:
	return COMPLETION_MODES[clampi(int(get_value(KEY_COMPLETION_MODE, 0)), 0, COMPLETION_MODES.size() - 1)]


func llm_profiles() -> Array[LlmProfile]:
	var result: Array[LlmProfile] = []
	var raw: Variant = get_value(KEY_COMPLETION_LLM_PROFILES, "")
	var data: Variant = JSON.parse_string(raw) if raw is String and not raw.is_empty() else null
	if not data is Array:
		data = LlmProfile.defaults()
	for item: Variant in data:
		if item is Dictionary:
			var profile: LlmProfile = LlmProfile.from_dict(item)
			if profile and not profile.id.is_empty():
				result.append(profile)
	return result


func save_llm_profiles(list: Array[LlmProfile]) -> void:
	var data: Array = []
	for profile: LlmProfile in list:
		data.append(profile.to_dict())
	set_value(KEY_COMPLETION_LLM_PROFILES, JSON.stringify(data, "\t"))


## El perfil LLM activo (el elegido, o el primero), o null si no hay ninguno.
func active_llm_profile() -> LlmProfile:
	var list := llm_profiles()
	var active := str(get_value(KEY_COMPLETION_LLM_ACTIVE, ""))
	for profile: LlmProfile in list:
		if profile.id == active:
			return profile
	return list[0] if not list.is_empty() else null


func llm_debounce_ms() -> int:
	return clampi(int(get_value(KEY_COMPLETION_LLM_DEBOUNCE, 200)), 75, 1000)


func llm_prefix_chars() -> int:
	return clampi(int(get_value(KEY_COMPLETION_LLM_PREFIX, 4000)), 200, 32000)


func llm_suffix_chars() -> int:
	return clampi(int(get_value(KEY_COMPLETION_LLM_SUFFIX, 1000)), 0, 16000)


func llm_context_tokens() -> int:
	return clampi(int(get_value(KEY_COMPLETION_LLM_CONTEXT, 2000)), 0, 16000)


func llm_marker() -> bool:
	return bool(get_value(KEY_COMPLETION_LLM_MARKER, true))


func completion_log_raw() -> bool:
	return bool(get_value(KEY_COMPLETION_LOG_RAW, false))


func _declare(key: String, default_value: Variant, type: Variant.Type, hint: PropertyHint = PROPERTY_HINT_NONE, hint_string: String = "") -> void:
	var full := PREFIX + key
	if not _editor_settings.has_setting(full):
		_editor_settings.set_setting(full, default_value)
	_editor_settings.set_initial_value(full, default_value, false)
	_editor_settings.add_property_info({"name": full, "type": type, "hint": hint, "hint_string": hint_string})

