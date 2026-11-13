extends "test_case.gd"

const Patcher := preload("res://addons/godot_agent/export/export_presets_patcher.gd")

const PRESETS := """[preset.0]

name="Linux"
platform="Linux"
runnable=true
exclude_filter=""

[preset.0.options]

binary_format/embed_pck=false

[preset.1]

name="Web"
platform="Web"
runnable=false
exclude_filter="*.psd, docs/*"

[preset.1.options]

html/export_icon=true

[preset.2]

name="Windows"
platform="Windows Desktop"
runnable=true
exclude_filter="res://addons/godot_agent/**"

[preset.2.options]

application/modify_resources=true
"""


func _write_presets() -> String:
	var path := temp_dir("export_presets_patcher") + "/export_presets.cfg"
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(PRESETS)
	file.close()
	return path


func test_filter_detection() -> void:
	assert_false(Patcher.filter_excludes_addon(""), "vacío")
	assert_false(Patcher.filter_excludes_addon("addons/other/*"), "otro addon")
	assert_false(Patcher.filter_excludes_addon("addons/godot_agent_dev/*"), "prefijo parecido")
	assert_true(Patcher.filter_excludes_addon("*.psd,addons/godot_agent/*"), "sin espacio")
	assert_true(Patcher.filter_excludes_addon("*.psd, res://addons/godot_agent/**"), "con res:// y **")
	# m0-07: se evalúa como glob, igual que Godot, no por el texto literal.
	for filter: String in ["addons/*", "addons/**", "res://addons/*", "*/godot_agent/*", "res://*/godot_agent/*",
			"*.psd , addons/*", "docs/*,  res://addons/**", "ADDONS/*", "addons/godot_agent*", "*"]:
		assert_true(Patcher.filter_excludes_addon(filter), "«%s» deja afuera el addon" % filter)
	for filter: String in ["*.gd, *.cfg", "addons/godot_agent/*.gd", "addons/*.cfg", "addons/godot_agent/core/*", "godot_agent/*", ", ,"]:
		assert_false(Patcher.filter_excludes_addon(filter), "«%s» no deja afuera todo el addon" % filter)
	assert_eq(Patcher.add_filter("*.psd, addons/*"), "*.psd, addons/*", "con addons/* no agrega nada")
	assert_true(Patcher.filter_excludes_dir("addons/*, *_tools/*", "agent_tools"), "la carpeta de las tools, también con glob")
	assert_false(Patcher.filter_excludes_dir("addons/*", "agent_tools"), "addons/* no cubre agent_tools")


func test_add_filter() -> void:
	assert_eq(Patcher.add_filter(""), "addons/godot_agent/*", "vacío")
	assert_eq(Patcher.add_filter("*.psd"), "*.psd, addons/godot_agent/*", "agrega al final")
	assert_eq(Patcher.add_filter("addons/godot_agent/*"), "addons/godot_agent/*", "idempotente")


func test_missing_ignores_options_sections() -> void:
	var path := _write_presets()
	assert_eq(Patcher.presets_missing_filter(path), PackedStringArray(["Linux", "Web"]), "presets sin filtro")


func test_patch_presets() -> void:
	var path := _write_presets()
	assert_eq(Patcher.patch_presets(path), PackedStringArray(["Linux", "Web"]), "parcheados")
	assert_eq(Patcher.presets_missing_filter(path), PackedStringArray(), "ya no falta ninguno")

	var cfg := ConfigFile.new()
	cfg.load(path)
	assert_eq(cfg.get_value("preset.1", "exclude_filter"), "*.psd, docs/*, addons/godot_agent/*", "conserva el filtro previo")
	assert_eq(cfg.get_value("preset.2", "exclude_filter"), "res://addons/godot_agent/**", "no toca el que ya excluye")
	assert_eq(cfg.get_value("preset.0.options", "binary_format/embed_pck"), false, "conserva las opciones")
	assert_eq(cfg.get_value("preset.1", "platform"), "Web", "conserva el resto")

	assert_eq(Patcher.patch_presets(path), PackedStringArray(), "segunda vez no cambia nada")


func test_missing_file() -> void:
	assert_eq(Patcher.presets_missing_filter("user://no_existe/export_presets.cfg"), PackedStringArray(), "sin archivo")


## m11-46: con tools del proyecto, cada preset excluye también su carpeta.
func test_project_tools_filter() -> void:
	var wanted := PackedStringArray([Patcher.FILTER, "agent_tools/*"])
	assert_eq(Patcher.add_filter("res://addons/godot_agent/**", wanted), "res://addons/godot_agent/**, agent_tools/*", "agrega la carpeta aunque ya excluya el addon")
	assert_eq(Patcher.add_filter("res://agent_tools/**, addons/godot_agent/*", wanted), "res://agent_tools/**, addons/godot_agent/*", "con res:// y ** ya cuenta")
	var path := _write_presets()
	assert_eq(Patcher.presets_missing_filter(path, wanted), PackedStringArray(["Linux", "Web", "Windows"]), "a los tres les falta la carpeta")
	assert_eq(Patcher.patch_presets(path, wanted).size(), 3, "parchea los tres")
	assert_eq(Patcher.presets_missing_filter(path, wanted), PackedStringArray(), "ya no falta nada")
	var cfg := ConfigFile.new()
	cfg.load(path)
	assert_eq(cfg.get_value("preset.0", "exclude_filter"), "addons/godot_agent/*, agent_tools/*", "vacío: los dos")
