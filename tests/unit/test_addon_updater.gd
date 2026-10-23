extends "test_case.gd"
## Updater del addon (m7-38): versiones, elección del release, extracción del zip e instalación.

const AddonUpdater := preload("res://addons/godot_agent/core/addon_updater.gd")


func test_compare_versions() -> void:
	assert_eq(AddonUpdater.compare_versions("0.1.3", "0.1.2"), 1, "patch")
	assert_eq(AddonUpdater.compare_versions("v0.2.0", "0.10.0"), -1, "numérico, no texto")
	assert_eq(AddonUpdater.compare_versions("1.0", "1.0.0"), 0, "faltan partes")
	assert_eq(AddonUpdater.compare_versions("0.2.0-beta.1", "0.2.0"), -1, "pre-release antes del final")
	assert_eq(AddonUpdater.compare_versions("0.2.0-beta.2", "0.2.0-beta.1"), 1, "entre pre-releases")
	assert_eq(AddonUpdater.compare_versions("0.2.0", "0.1.9-rc.1"), 1, "final contra pre-release viejo")


func test_pick_release() -> void:
	var list := [
		_release("v0.1.3", false, true),
		_release("v0.2.0-beta.1", true, true),
		_release("v0.1.9", false, false),  # sin zip
		{"tag_name": "v9.0.0", "draft": true, "assets": [{"name": "x.zip", "browser_download_url": "u"}]},
	]
	var stable := AddonUpdater.pick_release(list, false)
	assert_eq(stable.version, "0.1.3", "sin pre-releases, borradores ni releases sin zip")
	assert_eq(stable.zip_url, "https://example.com/v0.1.3.zip", "url del zip")
	assert_eq(stable.notes, "notes v0.1.3", "notas")
	assert_eq(AddonUpdater.pick_release(list, true).version, "0.2.0-beta.1", "con pre-releases")
	assert_eq(AddonUpdater.pick_release([], false), {}, "lista vacía")


func test_extract_and_validate() -> void:
	var root := _clean("updater_extract")
	var zip := root.path_join("addon.zip")
	_zip(zip, {
		"addons/godot_agent/plugin.cfg": "[plugin]\nversion=\"0.2.0\"\n",
		"addons/godot_agent/core/a.gd": "extends Node\n",
		"README.md": "fuera del addon",
		"addons/godot_agent/../../evil.gd": "no",
	})
	var result := AddonUpdater.extract(zip, root.path_join("out"), "0.2.0")
	assert_true(result.ok, "extrae: %s" % result.error)
	assert_true(FileAccess.file_exists(root.path_join("out/core/a.gd")), "archivo del addon")
	assert_false(FileAccess.file_exists(root.path_join("out/README.md")), "lo de afuera del addon no")
	assert_false(FileAccess.file_exists(root.path_join("evil.gd")), "sin rutas con ..")
	var wrong := AddonUpdater.extract(zip, root.path_join("out2"), "0.3.0")
	assert_false(wrong.ok, "versión distinta a la anunciada")
	assert_true(wrong.error.contains("0.2.0"), "el error dice la versión del zip")
	_zip(root.path_join("other.zip"), {"something/else.txt": "x"})
	assert_false(AddonUpdater.extract(root.path_join("other.zip"), root.path_join("out3"), "0.2.0").ok, "zip sin el addon")
	_write(root.path_join("bad.zip"), "not a zip")
	assert_false(AddonUpdater.extract(root.path_join("bad.zip"), root.path_join("out4"), "0.2.0").ok, "zip roto")


func test_install() -> void:
	var root := _clean("updater_install")
	var staged := root.path_join("staged")
	var target := root.path_join("target")
	var backup := root.path_join("backup")
	_write(staged.path_join("plugin.cfg"), "new cfg")
	_write(staged.path_join("core/a.gd"), "new a")
	_write(staged.path_join("config/system_prompt.md"), "new prompt")
	_write(staged.path_join("config/quota_patterns.txt"), "same")
	_write(target.path_join("plugin.cfg"), "old cfg")
	_write(target.path_join("core/a.gd"), "old a")
	_write(target.path_join("core/gone.gd"), "old")
	_write(target.path_join("core/gone.gd.uid"), "uid://x")
	_write(target.path_join("icon.png"), "user file")
	_write(target.path_join("config/project_config.tres"), "mine")
	_write(target.path_join("config/system_prompt.md"), "my prompt")
	_write(target.path_join("config/quota_patterns.txt"), "same")
	var result := AddonUpdater.install(staged, target, backup)
	assert_true(result.ok, "instala: %s" % result.error)
	assert_eq(FileAccess.get_file_as_string(target.path_join("core/a.gd")), "new a", "pisa los archivos")
	assert_eq(FileAccess.get_file_as_string(target.path_join("config/project_config.tres")), "mine", "la config del proyecto queda")
	assert_eq(Array(result.removed), ["core/gone.gd", "core/gone.gd.uid"], "borra lo que ya no viene")
	assert_true(FileAccess.file_exists(target.path_join("icon.png")), "un archivo de otro tipo queda")
	assert_eq(Array(result.backed_up), ["config/system_prompt.md"], "respalda solo lo editado que cambia")
	assert_eq(FileAccess.get_file_as_string(backup.path_join("config/system_prompt.md")), "my prompt", "el respaldo es la versión del usuario")
	assert_false(AddonUpdater.install(root.path_join("nada"), target, backup).ok, "sin plugin.cfg no toca nada")


func test_is_dev_copy() -> void:
	# En el repo está el plugin de dev al lado: es una copia de desarrollo.
	assert_true(AddonUpdater.is_dev_copy(), "repo con godot_agent_dev")


func _release(tag: String, prerelease: bool, with_zip: bool) -> Dictionary:
	var assets := [{"name": "godot-agent-harness-%s.zip" % tag, "browser_download_url": "https://example.com/%s.zip" % tag}] if with_zip else []
	return {"tag_name": tag, "prerelease": prerelease, "draft": false, "body": "notes %s" % tag, "html_url": "https://example.com/%s" % tag, "assets": assets}


func _clean(name: String) -> String:
	var path := ProjectSettings.globalize_path("user://unit_tests/%s" % name)
	AddonUpdater._remove_tree(path)
	DirAccess.make_dir_recursive_absolute(path)
	return path


func _zip(path: String, files: Dictionary) -> void:
	var packer := ZIPPacker.new()
	packer.open(path)
	for name: String in files:
		packer.start_file(name)
		packer.write_file(str(files[name]).to_utf8_buffer())
		packer.close_file()
	packer.close()


func _write(path: String, text: String) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()
