extends "test_case.gd"
## Tools del Asset Store y de plugins (m7-39): addons_list, plugin_enable (sin tocar el harness),
## el informe de asset_install y los permisos.

const AssetTools := preload("res://addons/godot_agent/mcp/tools/asset_tools.gd")
const AddonUpdater := preload("res://addons/godot_agent/core/addon_updater.gd")
const PermissionPolicy := preload("res://addons/godot_agent/session/permission_policy.gd")
const SessionModel := preload("res://addons/godot_agent/session/session_model.gd")
const GodotAddonsTab := preload("res://addons/godot_agent/ui/extensions/godot_addons_tab.gd")


func test_tools_and_groups() -> void:
	var groups := {}
	for tool: Variant in AssetTools.new().tools():
		groups[tool.name] = tool.group
	assert_eq(groups, {
		"asset_search": "read", "asset_details": "read", "asset_install": "addons", "addons_list": "read", "plugin_enable": "project",
	}, "grupos")
	var policy := PermissionPolicy.new()
	for mode: SessionModel.HarnessMode in [SessionModel.HarnessMode.BUILD, SessionModel.HarnessMode.ONESHOT, SessionModel.HarnessMode.AUTO]:
		assert_eq(policy.decide(PermissionPolicy.GROUP_ADDONS, mode), PermissionPolicy.ASK, "instalar pregunta en %d" % mode)
	assert_eq(policy.decide(PermissionPolicy.GROUP_ADDONS, SessionModel.HarnessMode.ASK), PermissionPolicy.DENY, "Preguntar no instala")


func test_addons_list_and_enable() -> void:
	var root := _clean("asset_tools_plugins")
	_write(root.path_join("addons/dialogue/plugin.cfg"), "[plugin]\nname=\"Dialogue\"\nversion=\"4.1\"\n")
	_write(root.path_join("addons/godot_agent/plugin.cfg"), "[plugin]\nname=\"Harness\"\n")
	var state := {}
	var tools := AssetTools.new()
	tools.addons_dir = root.path_join("addons")
	tools.is_enabled = func(path: String) -> bool: return state.get(path, false)
	tools.set_enabled = func(path: String, on: bool) -> void: state[path] = on
	var listed := _text(await tools._addons_list({}))
	assert_true(listed.contains("- dialogue: Dialogue 4.1, disabled"), "lista: %s" % listed)
	var result: Dictionary = tools._plugin_enable({"plugin": "dialogue", "enabled": true})
	assert_false(result.isError, "activa: %s" % _text(result))
	assert_true(state.get(root.path_join("addons/dialogue/plugin.cfg"), false), "por la ruta de su plugin.cfg")
	assert_true(_text(await tools._addons_list({})).contains("enabled"), "ahora activo")
	assert_true(tools._plugin_enable({"plugin": "godot_agent", "enabled": false}).isError, "el harness no se toca")
	assert_true(tools._plugin_enable({"plugin": "nope", "enabled": true}).isError, "uno que no está")
	tools.set_enabled = func(_path: String, _on: bool) -> void: pass
	assert_true(tools._plugin_enable({"plugin": "addons/dialogue", "enabled": false}).isError, "Godot no lo cambió")


func test_install_report_and_summary() -> void:
	var plan := {
		"files": [{"zip": "a", "target": "res://addons/thing/plugin.cfg"}, {"zip": "b", "target": "res://addons/thing/a.gd"}],
		"conflicts": ["res://addons/thing/old.gd"], "other": ["res://README.md"],
		"plugins": ["res://addons/thing/plugin.cfg", "res://addons/thing/sub/plugin.cfg"],
	}
	var report := AssetTools.install_report("me/thing", {"version": "v1.0"}, plan, {"written": 2, "enabled": ["res://addons/thing/plugin.cfg"]})
	assert_true(report.begins_with("Installed me/thing v1.0: 2 files."), "encabezado: %s" % report)
	assert_true(report.contains("Where: addons/thing"), "dónde")
	assert_true(report.contains("Not overwritten (already existed): res://addons/thing/old.gd"), "conflictos")
	assert_true(report.contains("Left out"), "lo de afuera")
	assert_true(report.contains("res://addons/thing/sub/plugin.cfg: not enabled"), "plugin sin activar")
	var summary := GodotAddonsTab.install_summary("Thing", "v1.0", plan)
	assert_true(summary.contains("2 files in: addons/thing"), "resumen: %s" % summary)
	assert_true(summary.contains("1 already exist"), "conflictos en el diálogo")


func test_addons_list_with_updates() -> void:
	var root := _clean("asset_tools_updates")
	_write(root.path_join("addons/thing/plugin.cfg"), "[plugin]\nname=\"Thing\"\nversion=\"1.0\"\n")
	var store := FakeStore.new()
	var tools := AssetTools.new()
	tools.store = store
	tools.addons_dir = root.path_join("addons")
	tools.is_enabled = func(_path: String) -> bool: return true
	var listed := _text(await tools._addons_list({"check_updates": true}))
	assert_true(listed.contains("update available: 1.0 → v2.0 (asset_install asset=me/thing update=true; matched by name)"), "avisa: %s" % listed)
	assert_true(listed.contains("1 updates"), "resumen")
	assert_false(_text(await tools._addons_list({})).contains("update"), "sin check_updates no pregunta")
	store.free()


func test_update_summary() -> void:
	var plan := {"files": [{"target": "res://addons/thing/a.gd", "replaces": true}, {"target": "res://addons/thing/b.gd", "replaces": false}],
		"conflicts": [], "other": [], "plugins": ["res://addons/thing/plugin.cfg"], "stale": ["res://addons/thing/gone.gd"]}
	var summary := GodotAddonsTab.install_summary("Thing", "v2.0", plan, true)
	assert_true(summary.begins_with("Update Thing to v2.0?"), "título: %s" % summary)
	assert_true(summary.contains("1 replace the installed version"), "reemplazos")
	assert_true(summary.contains("1 files of the old version are removed"), "lo que se borra")
	var report := AssetTools.install_report("me/thing", {"version": "v2.0"}, plan, {"written": 2, "removed": 1, "enabled": ["res://addons/thing/plugin.cfg"]})
	assert_true(report.begins_with("Updated me/thing v2.0: 2 files (1 replaced, 1 old ones removed)."), "informe: %s" % report)


class FakeStore extends "res://addons/godot_agent/core/asset_store.gd":
	func check_updates(plugins: Array[Dictionary]) -> Dictionary:
		var updates: Array[Dictionary] = []
		for plugin: Dictionary in plugins:
			updates.append({"folder": plugin.folder, "name": plugin.name, "asset_id": "me/thing", "installed": plugin.version, "latest": "v2.0", "guessed": true})
		return {"updates": updates, "checked": plugins.size(), "error": ""}


func _text(result: Dictionary) -> String:
	return str(result.content[0].text)


func _clean(name: String) -> String:
	var path := ProjectSettings.globalize_path("user://unit_tests/%s" % name)
	AddonUpdater._remove_tree(path)
	DirAccess.make_dir_recursive_absolute(path)
	return path


func _write(path: String, text: String) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()
