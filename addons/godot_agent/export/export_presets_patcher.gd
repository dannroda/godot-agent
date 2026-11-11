@tool
extends RefCounted
## Lee y parchea el exclude_filter de export_presets.cfg (red de seguridad, spec §2).

const ProjectConfig := preload("../config/project_config.gd")
const ProjectToolLoader := preload("../mcp/project_tool_loader.gd")

const PRESETS_PATH := "res://export_presets.cfg"
const FILTER := "addons/godot_agent/*"
const _ACCEPTED_FILTERS: PackedStringArray = [
	"addons/godot_agent/*",
	"addons/godot_agent/**",
	"res://addons/godot_agent/*",
	"res://addons/godot_agent/**",
]


## Lo que cada preset tiene que excluir: el addon y, si existe, la carpeta de las tools del proyecto
## (m11-46): extienden un script del addon, así que en un juego exportado no cargan.
static func wanted_filters() -> PackedStringArray:
	var result := PackedStringArray([FILTER])
	var tools_dir := ProjectToolLoader.resolve_dir(str(ProjectConfig.load_or_default().get(&"project_tools_dir")))
	if DirAccess.dir_exists_absolute(tools_dir):
		result.append(ProjectToolLoader.export_filter(tools_dir))
	return result


## Los filtros para los mensajes: «addons/godot_agent/*, agent_tools/*».
static func filters_text() -> String:
	return ", ".join(wanted_filters())


static func presets_file_exists() -> bool:
	return FileAccess.file_exists(PRESETS_PATH)


## Nombres de los presets cuyo exclude_filter no excluye el addon.
static func presets_missing_filter(path: String = PRESETS_PATH, wanted: PackedStringArray = wanted_filters()) -> PackedStringArray:
	var missing: PackedStringArray = []
	var cfg := ConfigFile.new()
	if cfg.load(path) != OK:
		return missing
	for section: String in _preset_sections(cfg):
		var filter: String = str(cfg.get_value(section, "exclude_filter", ""))
		if not filter_excludes_addon(filter) or not _missing_extras(filter, wanted).is_empty():
			missing.append(str(cfg.get_value(section, "name", section)))
	return missing


static func filter_excludes_addon(filter: String) -> bool:
	for token: String in filter.split(",", false):
		if token.strip_edges() in _ACCEPTED_FILTERS:
			return true
	return false


static func add_filter(filter: String, wanted: PackedStringArray = [FILTER]) -> String:
	var tokens: PackedStringArray = []
	if not filter.strip_edges().is_empty():
		tokens.append(filter.strip_edges())
	if not filter_excludes_addon(filter):
		tokens.append(FILTER)
	tokens.append_array(_missing_extras(filter, wanted))
	return ", ".join(tokens)


## Los filtros de `wanted` (salvo el del addon) que `filter` no tiene, con o sin res:// y con * o **.
static func _missing_extras(filter: String, wanted: PackedStringArray) -> PackedStringArray:
	var present: Dictionary = {}
	for token: String in filter.split(",", false):
		present[token.strip_edges().trim_prefix("res://").trim_suffix("*").trim_suffix("*")] = true
	var result: PackedStringArray = []
	for extra: String in wanted:
		if extra != FILTER and not present.has(extra.trim_suffix("*")):
			result.append(extra)
	return result


## Agrega el filtro a todos los presets que no lo tienen. Devuelve los nombres parcheados.
static func patch_presets(path: String = PRESETS_PATH, wanted: PackedStringArray = wanted_filters()) -> PackedStringArray:
	var patched: PackedStringArray = []
	var cfg := ConfigFile.new()
	var err := cfg.load(path)
	if err != OK:
		push_error("Godot Agent: could not read %s (%s)." % [path, error_string(err)])
		return patched
	for section: String in _preset_sections(cfg):
		var filter: String = str(cfg.get_value(section, "exclude_filter", ""))
		if filter_excludes_addon(filter) and _missing_extras(filter, wanted).is_empty():
			continue
		cfg.set_value(section, "exclude_filter", add_filter(filter, wanted))
		patched.append(str(cfg.get_value(section, "name", section)))
	if patched.is_empty():
		return patched
	err = cfg.save(path)
	if err != OK:
		push_error("Godot Agent: could not save %s (%s)." % [path, error_string(err)])
		return PackedStringArray()
	return patched


## Secciones "preset.N" (no "preset.N.options").
static func _preset_sections(cfg: ConfigFile) -> PackedStringArray:
	var sections: PackedStringArray = []
	for section: String in cfg.get_sections():
		if section.begins_with("preset.") and section.count(".") == 1:
			sections.append(section)
	return sections
