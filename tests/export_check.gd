extends SceneTree
## Verifica que nada del addon llegue a un export (spec §2, M0).
##
## Uso: godot --headless --path <repo> --script tests/export_check.gd
## Arma proyectos temporales en user://export_check/ con una copia del addon, exporta cada uno con
## --export-pack (mismo binario que corre este script), abre el .zip con ZIPReader y revisa:
## - ningún archivo bajo addons/godot_agent/,
## - el autoload de playtest no está en project.binary,
## - ninguna clase del addon en global_script_class_cache.cfg.
## Advierte (no falla) si uid_cache.bin conserva rutas del addon (4.4, docs/decisions.md D8).

const ADDON_SRC := "res://addons/godot_agent"
const WORK_DIR := "user://export_check"
const PRESET := "ExportCheck"
const ADDON_PATH_MARK := "addons/godot_agent/"
const AUTOLOAD_NAME := "GodotAgentPlaytest"
const AUTOLOAD_SCRIPT := "res://addons/godot_agent/playtest/runtime/playtest_probe.gd"
const PLUGIN_CFG := "res://addons/godot_agent/plugin.cfg"
const FILTER := "addons/godot_agent/*"
const KEEP_ORPHAN_ENV := "GODOT_AGENT_TEST_KEEP_ORPHAN_AUTOLOAD"
const ORPHAN_ERROR_MARK := "was still registered at export time"

## Cada escenario: plugin habilitado, filtro en el preset, autoload huérfano y si se espera que pase.
const SCENARIOS: Array[Dictionary] = [
	{ "name": "plugin_on_sin_filtro", "plugin": true, "filter": false, "orphan": false, "expect_clean": true },
	{ "name": "plugin_off_con_filtro", "plugin": false, "filter": true, "orphan": false, "expect_clean": true },
	{ "name": "plugin_on_autoload_huerfano", "plugin": true, "filter": false, "orphan": true, "expect_clean": true },
	# Control: sin plugin ni filtro el addon TIENE que aparecer; si no, el detector no sirve.
	{ "name": "control_plugin_off_sin_filtro", "plugin": false, "filter": false, "orphan": false, "expect_clean": false },
]


func _init() -> void:
	var failures: int = 0
	for scenario: Dictionary in SCENARIOS:
		if not _run_scenario(scenario):
			failures += 1
	var version: String = Engine.get_version_info().string
	if failures == 0:
		print("export_check: PASS (%s)" % version)
		quit(0)
	else:
		print("export_check: FAIL, %d escenario(s) (%s)" % [failures, version])
		quit(1)


func _run_scenario(scenario: Dictionary) -> bool:
	var name: String = scenario.name
	var project_dir := "%s/%s" % [WORK_DIR, name]
	var abs_dir := ProjectSettings.globalize_path(project_dir)
	_remove_dir(project_dir)
	DirAccess.make_dir_recursive_absolute(abs_dir)
	_copy_dir(ADDON_SRC, project_dir + "/addons/godot_agent")
	_write(project_dir + "/project.godot", _project_godot(scenario, false))
	_write(project_dir + "/export_presets.cfg", _export_presets(scenario))
	_write(project_dir + "/main.tscn", '[gd_scene format=3]\n\n[node name="Main" type="Node"]\n')

	var zip_path := abs_dir + "/export.zip"
	_godot(["--headless", "--path", abs_dir, "--import"])
	# El huérfano se escribe después del import (al cerrar, el plugin lo limpiaría) y, con el env,
	# el plugin no lo limpia al arrancar el export: así se prueba el guard de _export_begin.
	if scenario.orphan:
		_write(project_dir + "/project.godot", _project_godot(scenario, true))
		OS.set_environment(KEEP_ORPHAN_ENV, "1")
	var export_output := _godot(["--headless", "--path", abs_dir, "--export-pack", PRESET, zip_path])
	if scenario.orphan:
		OS.unset_environment(KEEP_ORPHAN_ENV)

	var leaks: PackedStringArray = []
	var warnings: PackedStringArray = []
	if not FileAccess.file_exists(zip_path):
		print("[%s] FAIL: no se generó %s\n%s" % [name, zip_path, export_output])
		return false
	_inspect_zip(zip_path, leaks, warnings)

	var ok: bool
	if scenario.expect_clean:
		ok = leaks.is_empty()
		if scenario.orphan and not export_output.contains(ORPHAN_ERROR_MARK):
			ok = false
			leaks.append("el export no mostró el error de autoload huérfano")
	else:
		ok = not leaks.is_empty()
		if not ok:
			leaks.append("el control no detectó el addon: el chequeo no está mirando lo correcto")

	print("[%s] %s" % [name, "PASS" if ok else "FAIL"])
	for leak: String in leaks:
		print("    %s %s" % ["-" if scenario.expect_clean else "(esperado)", leak])
	for warning: String in warnings:
		print("    aviso: " + warning)
	return ok


func _inspect_zip(zip_path: String, leaks: PackedStringArray, warnings: PackedStringArray) -> void:
	var zip := ZIPReader.new()
	if zip.open(zip_path) != OK:
		leaks.append("no se pudo abrir el zip")
		return
	for file: String in zip.get_files():
		if file.contains(ADDON_PATH_MARK):
			leaks.append("archivo exportado: " + file)
		var data := zip.read_file(file)
		if file.ends_with("project.binary"):
			if _bytes_contain(data, AUTOLOAD_NAME) or _bytes_contain(data, AUTOLOAD_SCRIPT):
				leaks.append("autoload de playtest en project.binary")
			if _bytes_contain(data, PLUGIN_CFG):
				warnings.append("project.binary conserva editor_plugins/enabled con la ruta del plugin")
		elif file.ends_with("global_script_class_cache.cfg"):
			if _bytes_contain(data, ADDON_PATH_MARK):
				leaks.append("clases del addon en global_script_class_cache.cfg")
		elif file.ends_with("uid_cache.bin"):
			if _bytes_contain(data, ADDON_PATH_MARK):
				warnings.append("uid_cache.bin conserva rutas del addon (D8)")
		elif file.ends_with(".remap") and _bytes_contain(data, ADDON_PATH_MARK):
			leaks.append("remap apunta al addon: " + file)
	zip.close()


func _project_godot(scenario: Dictionary, with_orphan: bool) -> String:
	var text := 'config_version=5\n\n[application]\n\nconfig/name="export_check_%s"\nrun/main_scene="res://main.tscn"\n' % scenario.name
	if with_orphan:
		text += '\n[autoload]\n\n%s="*%s"\n' % [AUTOLOAD_NAME, AUTOLOAD_SCRIPT]
	if scenario.plugin:
		text += '\n[editor_plugins]\n\nenabled=PackedStringArray("%s")\n' % PLUGIN_CFG
	return text


func _export_presets(scenario: Dictionary) -> String:
	return (
		'[preset.0]\n\nname="%s"\nplatform="Linux"\nrunnable=true\nexport_filter="all_resources"\ninclude_filter=""\nexclude_filter="%s"\nexport_path=""\n\n[preset.0.options]\n\nbinary_format/embed_pck=false\n'
		% [PRESET, FILTER if scenario.filter else ""]
	)


func _godot(args: PackedStringArray) -> String:
	var output: Array = []
	OS.execute(OS.get_executable_path(), args, output, true)
	return "\n".join(output)


func _bytes_contain(data: PackedByteArray, needle: String) -> bool:
	var pattern := needle.to_utf8_buffer()
	if pattern.is_empty():
		return false
	var first: int = pattern[0]
	var at := data.find(first)
	while at != -1 and at + pattern.size() <= data.size():
		if data.slice(at, at + pattern.size()) == pattern:
			return true
		at = data.find(first, at + 1)
	return false


func _copy_dir(from: String, to: String) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(to))
	for file: String in DirAccess.get_files_at(from):
		DirAccess.copy_absolute(ProjectSettings.globalize_path(from + "/" + file), ProjectSettings.globalize_path(to + "/" + file))
	for dir: String in DirAccess.get_directories_at(from):
		_copy_dir(from + "/" + dir, to + "/" + dir)


func _remove_dir(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		return
	for file: String in DirAccess.get_files_at(path):
		DirAccess.remove_absolute(path + "/" + file)
	for dir: String in DirAccess.get_directories_at(path):
		_remove_dir(path + "/" + dir)
	DirAccess.remove_absolute(path)


func _write(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
