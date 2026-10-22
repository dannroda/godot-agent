@tool
extends RefCounted
## Lee y parchea el exclude_filter de export_presets.cfg (red de seguridad, spec §2).

const PRESETS_PATH := "res://export_presets.cfg"
const FILTER := "addons/godot_agent/*"
const _ACCEPTED_FILTERS: PackedStringArray = [
	"addons/godot_agent/*",
	"addons/godot_agent/**",
	"res://addons/godot_agent/*",
	"res://addons/godot_agent/**",
]


static func presets_file_exists() -> bool:
	return FileAccess.file_exists(PRESETS_PATH)


## Nombres de los presets cuyo exclude_filter no excluye el addon.
static func presets_missing_filter(path: String = PRESETS_PATH) -> PackedStringArray:
	var missing: PackedStringArray = []
	var cfg := ConfigFile.new()
	if cfg.load(path) != OK:
		return missing
	for section: String in _preset_sections(cfg):
		var filter: String = str(cfg.get_value(section, "exclude_filter", ""))
		if not filter_excludes_addon(filter):
			missing.append(str(cfg.get_value(section, "name", section)))
	return missing


static func filter_excludes_addon(filter: String) -> bool:
	for token: String in filter.split(",", false):
		if token.strip_edges() in _ACCEPTED_FILTERS:
			return true
	return false


static func add_filter(filter: String) -> String:
	if filter_excludes_addon(filter):
		return filter
	if filter.strip_edges().is_empty():
		return FILTER
	return "%s, %s" % [filter.strip_edges(), FILTER]


## Agrega el filtro a todos los presets que no lo tienen. Devuelve los nombres parcheados.
static func patch_presets(path: String = PRESETS_PATH) -> PackedStringArray:
	var patched: PackedStringArray = []
	var cfg := ConfigFile.new()
	var err := cfg.load(path)
	if err != OK:
		push_error("Godot Agent: could not read %s (%s)." % [path, error_string(err)])
		return patched
	for section: String in _preset_sections(cfg):
		var filter: String = str(cfg.get_value(section, "exclude_filter", ""))
		if filter_excludes_addon(filter):
			continue
		cfg.set_value(section, "exclude_filter", add_filter(filter))
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
