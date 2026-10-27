extends "test_case.gd"
## Asset Store (m7-39): ruta de búsqueda, respuestas del store, releases compatibles, plan de
## instalación del zip, instalación y plugins del proyecto.

const AssetStore := preload("res://addons/godot_agent/core/asset_store.gd")
const AddonUpdater := preload("res://addons/godot_agent/core/addon_updater.gd")

const GODOT_472 := {"major": 4, "minor": 7, "patch": 2}


func test_ids() -> void:
	assert_true(AssetStore.is_valid_id("nathanhoad/dialogue-manager"), "publisher/slug")
	assert_false(AssetStore.is_valid_id("dialogue-manager"), "sin publisher")
	assert_false(AssetStore.is_valid_id("a/b/c"), "de más")
	assert_false(AssetStore.is_valid_id("../etc"), "sin ..")
	assert_false(AssetStore.is_valid_id("a b/c"), "sin espacios")


func test_search_path() -> void:
	assert_eq(AssetStore.search_path("Dialogue Box", 1, "relevance", GODOT_472),
		"search/query/?query=dialogue%20box&require_release=true&type=0&sort=relevance&compatibility=4.7.2", "como el editor")
	assert_eq(AssetStore.search_path("", 3, "nope", {"major": 4, "minor": 6, "patch": 0}),
		"search/query/?query=&require_release=true&type=0&sort=relevance&compatibility=4.6&page=3", "sin patch, orden inválido y página")


func test_parse_hits() -> void:
	var hits := AssetStore.parse_hits([
		{"asset": {"name": "Dialogue Manager", "slug": "dialogue-manager", "description": " Branching dialogue. ",
			"license_type": "MIT", "reviews_score": 58, "price_cent": 0, "store_url": "https://store/x",
			"publisher": {"name": "Nathan Hoad", "slug": "nathanhoad"}}},
		{"asset": {"name": "Paid", "slug": "paid", "price_cent": 500, "publisher": {"slug": "acme"}}},
		{"asset": {"name": "Broken", "slug": "../x", "publisher": {"slug": "acme"}}},
		{"asset": {"name": "New", "slug": "new", "reviews_score": null, "price_cent": null, "publisher": {"slug": "acme"}}},
		"basura",
	])
	assert_eq(hits.size(), 3, "descarta lo que no tiene un id válido")
	assert_eq(hits[0].id, "nathanhoad/dialogue-manager", "id")
	assert_eq(hits[0].publisher, "Nathan Hoad", "publisher")
	assert_eq(hits[0].description, "Branching dialogue.", "descripción sin espacios")
	assert_eq(hits[1].price_cent, 500, "precio")
	assert_eq([hits[2].score, hits[2].price_cent], [0, 0], "null del store como 0")
	assert_eq(AssetStore.parse_hits(null), [], "sin hits")


func test_details_and_bbcode() -> void:
	var asset := AssetStore.parse_details("a/b", {
		"name": "B", "body_bbcode": "[p]Hello [b]world[/b][/p]\n[ul][*]one[*]two[/ul]\n\n\n\n[url=https://x]link[/url]",
		"tags": [{"display_name": "2D"}, {"slug": "ui"}], "source": "https://github.com/a/b", "price_cent": "0",
		"publisher": {"name": "A"},
	})
	assert_eq(asset.body, "Hello world\n\n- one\n- two\n\nlink", "BBCode a texto")
	assert_eq(Array(asset.tags), ["2D", "ui"], "tags")
	assert_eq(asset.source, "https://github.com/a/b", "código fuente")
	assert_eq(asset.price_cent, 0, "precio como texto")


func test_compatible_releases() -> void:
	var list := [
		{"version": "v5.0.0", "stable": true, "min_godot_version": "4.8", "max_godot_version": null, "download_url": "u5"},
		{"version": "v4.1.0-beta", "stable": false, "min_godot_version": "4.6", "max_godot_version": null, "download_url": "u4b"},
		{"version": "v4.0.0", "stable": true, "min_godot_version": "4.6", "max_godot_version": "4.7", "download_url": "u4", "size": null},
		{"version": "v3.0.0", "stable": true, "min_godot_version": "4.2", "max_godot_version": "4.5", "download_url": "u3"},
		{"version": "v2.0.0", "stable": true, "download_url": ""},
	]
	var releases := AssetStore.compatible_releases(list, GODOT_472)
	assert_eq(releases.map(func(r: Dictionary) -> String: return r.version), ["v4.1.0-beta", "v4.0.0"], "4.7.2 entra en un máximo 4.7; sin url no")
	assert_eq(AssetStore.pick_release(releases).version, "v4.0.0", "la estable más nueva")
	assert_eq(releases[1].size_mb, 0.0, "size null")
	assert_eq(AssetStore.pick_release(releases, "4.1.0-beta").version, "v4.1.0-beta", "una versión pedida, sin v")
	assert_eq(AssetStore.pick_release(releases, "9.9"), {}, "una versión que no está")
	var only_beta := AssetStore.compatible_releases([list[1]], GODOT_472)
	assert_eq(AssetStore.pick_release(only_beta).version, "v4.1.0-beta", "sin estables, la más nueva")
	assert_eq(AssetStore.pick_release([]), {}, "sin releases")


func test_plan_with_root_folder() -> void:
	var root := _clean("asset_plan_root")
	var zip := root.path_join("a.zip")
	_zip(zip, {
		"repo-1.0/addons/thing/plugin.cfg": "[plugin]\nname=\"Thing\"\n",
		"repo-1.0/addons/thing/thing.gd": "extends Node\n",
		"repo-1.0/README.md": "readme",
		"repo-1.0/project.godot": "no",
		"repo-1.0/../evil.gd": "no",
		"repo-1.0/addons/godot_agent/plugin.gd": "no",
	})
	var target := root.path_join("project")
	_write(target.path_join("addons/thing/thing.gd"), "mine")
	var plan := AssetStore.plan_install(zip, true, target)
	assert_eq(plan.error, "", "sin error")
	assert_eq(plan.files.map(func(f: Dictionary) -> String: return f.target.trim_prefix(target + "/")), ["addons/thing/plugin.cfg"], "saca la raíz; solo addons/")
	assert_eq(Array(plan.conflicts).map(func(p: String) -> String: return p.trim_prefix(target + "/")), ["addons/thing/thing.gd"], "lo que existe no se pisa")
	assert_eq(Array(plan.other).map(func(p: String) -> String: return p.trim_prefix(target + "/")), ["README.md", "project.godot"], "lo de afuera de addons/ queda afuera")
	assert_eq(Array(plan.plugins), [target.path_join("addons/thing/plugin.cfg")], "plugins")
	var all := AssetStore.plan_install(zip, false, target)
	assert_eq(all.files.size(), 3, "con todo: plugin.cfg, README y project.godot (en res:// ya existe: conflicto)")
	assert_true(AssetStore.install(zip, plan).ok, "instala")
	assert_eq(FileAccess.get_file_as_string(target.path_join("addons/thing/thing.gd")), "mine", "no pisó")
	assert_true(FileAccess.file_exists(target.path_join("addons/thing/plugin.cfg")), "escribió")
	assert_false(FileAccess.file_exists(root.path_join("evil.gd")), "sin rutas con ..")
	assert_false(all.files.any(func(f: Dictionary) -> bool: return "godot_agent" in f.target), "nunca dentro del harness")


func test_plan_without_addons() -> void:
	var root := _clean("asset_plan_flat")
	var zip := root.path_join("b.zip")
	# Raíz addons/: no se saca. Un zip sin addons/ instala todo aunque se pida solo addons/.
	_zip(zip, {"addons/x/plugin.cfg": "[plugin]\n", "addons/x/x.gd": ""})
	var plan := AssetStore.plan_install(zip, true, root.path_join("p"))
	assert_eq(plan.files.size(), 2, "raíz addons/ se conserva")
	_zip(root.path_join("c.zip"), {"pack/textures/a.png": "png", "pack/b.tres": "tres"})
	var flat := AssetStore.plan_install(root.path_join("c.zip"), true, root.path_join("p"))
	assert_eq(flat.files.map(func(f: Dictionary) -> String: return f.target.get_file()), ["a.png", "b.tres"], "sin addons/, todo")
	assert_eq(flat.plugins, [], "sin plugins")
	_write(root.path_join("bad.zip"), "not a zip")
	assert_false(AssetStore.plan_install(root.path_join("bad.zip")).error.is_empty(), "zip roto")


func test_one_line() -> void:
	assert_eq(AssetStore.one_line(" Inspired by\n\n\n\nA small  system. "), "Inspired by A small system.", "sin líneas en blanco")
	assert_eq(AssetStore.one_line("abcdefghij", 4), "abcd…", "recortada")


func test_what_the_editor_must_import() -> void:
	var root := _clean("asset_imports")
	_write(root.path_join("a.gd.uid"), "uid://bq4f2kq3s1hy\n")
	_write(root.path_join("icon.svg.import"), "[remap]\n\nimporter=\"texture\"\nuid=\"uid://s166pjhwlrpj\"\n\n[deps]\n\ndest_files=[\"res://.godot/imported/icon.svg-1.ctex\"]\n")
	_write(root.path_join("scene.tscn"), "[gd_scene format=3 uid=\"uid://c8x7d6e5f4g3\"]\n")
	_write(root.path_join("plain.gd"), "extends Node\n")
	var plan := {"files": ["a.gd.uid", "icon.svg.import", "scene.tscn", "plain.gd"].map(func(file: String) -> Dictionary: return {"zip": file, "target": root.path_join(file)})}
	assert_eq(AssetStore.expected_uids(plan).map(func(id: int) -> String: return ResourceUID.id_to_text(id)),
		["uid://bq4f2kq3s1hy", "uid://s166pjhwlrpj", "uid://c8x7d6e5f4g3"], "uids de .uid, .import y .tscn")
	assert_eq(Array(AssetStore.import_outputs(plan)), ["res://.godot/imported/icon.svg-1.ctex"], "lo que genera el import")


func test_update_plan_and_manifest() -> void:
	var root := _clean("asset_update")
	var target := root.path_join("project")
	var zip := root.path_join("v2.zip")
	_zip(zip, {
		"repo/addons/thing/plugin.cfg": "[plugin]\nversion=\"2.0\"\n",
		"repo/addons/thing/new.gd": "new",
		"repo/addons/thing/a.gd": "a v2",
	})
	_write(target.path_join("addons/thing/plugin.cfg"), "[plugin]\nversion=\"1.0\"\n")
	_write(target.path_join("addons/thing/a.gd"), "a v1")
	_write(target.path_join("addons/thing/gone.gd"), "old")
	_write(target.path_join("addons/thing/mine.txt"), "user file")
	var plain := AssetStore.plan_install(zip, true, target)
	assert_eq(plain.conflicts.size(), 2, "sin update, lo que existe es conflicto")
	var folders := AssetStore.addon_folders(plain)
	assert_eq(Array(folders), [target.path_join("addons/thing")], "carpeta del addon, con los conflictos")
	var plan := AssetStore.plan_install(zip, true, target, folders)
	assert_eq(plan.conflicts, [], "con update se pisa dentro de la carpeta")
	assert_eq(plan.files.filter(func(f: Dictionary) -> bool: return f.replaces).size(), 2, "dos reemplazan")
	var entry := {"version": "v1.0", "folders": [target.path_join("addons/thing")],
		"files": [target.path_join("addons/thing/plugin.cfg"), target.path_join("addons/thing/a.gd"), target.path_join("addons/thing/gone.gd"), target.path_join("elsewhere/x.gd")]}
	assert_eq(Array(AssetStore.stale_files(entry, plan)), [target.path_join("addons/thing/gone.gd")], "solo lo viejo de su carpeta; mine.txt no estaba anotado")
	assert_eq(AssetStore.stale_files({}, plan), PackedStringArray(), "instalado a mano: no se borra nada")
	var other := target.path_join("addons/other")
	assert_eq(Array(AssetStore.replace_folders({"folders": [other]}, plain)), [other], "anotado: solo sus carpetas, no las que trae el zip")
	assert_eq(AssetStore.replace_folders({}, plain), folders, "a mano: las del zip")
	assert_eq(AssetStore.plan_install(zip, true, target, [other]).conflicts.size(), 2, "lo de otra carpeta no se pisa")
	assert_true(AssetStore.install(zip, plan).ok, "actualiza")
	assert_eq(FileAccess.get_file_as_string(target.path_join("addons/thing/a.gd")), "a v2", "pisó")
	var recorded := AssetStore.manifest_entry("v2.0", plan)
	assert_eq(recorded.version, "v2.0", "versión")
	assert_eq(recorded.files.size(), 3, "archivos escritos")
	var path := root.path_join("assets.json")
	AssetStore.write_manifest(path, {"me/thing": recorded})
	var manifest := AssetStore.read_manifest(path)
	assert_eq(manifest["me/thing"].version, "v2.0", "se lee lo que se escribió")
	assert_eq(AssetStore.manifest_asset_for(manifest, "thing"), "me/thing", "carpeta → asset")
	assert_eq(AssetStore.manifest_asset_for(manifest, "other"), "", "carpeta sin anotar")
	assert_eq(AssetStore.read_manifest(root.path_join("nada.json")), {}, "sin archivo")
	AssetStore.write_manifest(path, {"me/thing": recorded, "me/gone": {"version": "1", "folders": [target.path_join("addons/gone")]}})
	assert_eq(AssetStore.installed_assets(path), {"me/thing": "v2.0"}, "sin las carpetas borradas a mano")


func test_match_asset() -> void:
	var hits: Array[Dictionary] = [
		{"id": "a/other", "name": "Other"},
		{"id": "kobewi/simple-todo", "name": "Simple TODO"},
	]
	assert_eq(AssetStore.match_asset({"name": "Simple TODO", "folder": "SimpleTODO"}, hits), "kobewi/simple-todo", "por nombre")
	assert_eq(AssetStore.match_asset({"name": "Todo board", "folder": "simple_todo"}, hits), "kobewi/simple-todo", "por carpeta y slug")
	assert_eq(AssetStore.match_asset({"name": "Nope", "folder": "nope"}, hits), "", "sin coincidencia")


func test_project_plugins() -> void:
	var root := _clean("asset_project_plugins")
	_write(root.path_join("addons/b_tool/plugin.cfg"), "[plugin]\nname=\"B Tool\"\nversion=\"1.2\"\nauthor=\"me\"\n")
	_write(root.path_join("addons/a_pack/inner/plugin.cfg"), "[plugin]\nname=\"Inner\"\n")
	_write(root.path_join("addons/assets_only/x.png"), "")
	var plugins := AssetStore.project_plugins(root.path_join("addons"))
	assert_eq(plugins.map(func(p: Dictionary) -> String: return p.folder), ["a_pack/inner", "b_tool"], "por carpeta, hasta dos niveles")
	assert_eq(plugins[1].version, "1.2", "versión")
	assert_eq(AssetStore.project_plugins(root.path_join("nada")), [], "sin addons/")


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
