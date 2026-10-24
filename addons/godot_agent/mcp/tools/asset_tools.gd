@tool
extends RefCounted
## Godot Asset Store y plugins del proyecto (m7-39): asset_search, asset_details y addons_list
## (grupo read), asset_install (grupo addons: pregunta en todos los modos que lo permiten, incluso
## Auto, porque baja código de terceros al proyecto) y plugin_enable (grupo project).

const McpTool := preload("../mcp_tool.gd")
const AssetStore := preload("../../core/asset_store.gd")
const PermissionPolicy := preload("../../session/permission_policy.gd")

## Plugins que el agente no puede apagar: el propio harness.
const PROTECTED_FOLDERS: PackedStringArray = ["godot_agent", "godot_agent_dev"]

var store: AssetStore
## (path: String) -> bool, y (path: String, enabled: bool). Por defecto, los del editor.
var is_enabled: Callable = func(path: String) -> bool: return EditorInterface.is_plugin_enabled(path)
var set_enabled: Callable = func(path: String, enabled: bool) -> void: EditorInterface.set_plugin_enabled(path, enabled)
var addons_dir: String = "res://addons"


func tools() -> Array:
	var read := PermissionPolicy.GROUP_READ
	var install := McpTool.create("asset_install", PermissionPolicy.GROUP_ADDONS,
		"Downloads an asset from the Godot Asset Store and installs it in the project (always asks the user). Only files under addons/ are installed unless include_other_files is true (zips often carry demos, READMEs and even a project.godot); existing files are never overwritten (they're listed as conflicts). Its plugins are enabled unless enable_plugins is false. Use the id from asset_search.",
		{
			"asset": {"type": "string", "description": "publisher/slug"},
			"version": {"type": "string", "description": "A release from asset_details; default the newest stable one for this Godot version"},
			"include_other_files": {"type": "boolean"},
			"enable_plugins": {"type": "boolean", "description": "Default true"},
		}, ["asset"], _install)
	install.describer = func(args: Dictionary) -> String:
		var version := McpTool.str_arg(args, "version")
		return "%s%s" % [McpTool.str_arg(args, "asset"), " " + version if not version.is_empty() else ""]
	var enable := McpTool.create("plugin_enable", PermissionPolicy.GROUP_PROJECT,
		"Enables or disables an editor plugin of the project (as in Project Settings → Plugins). `plugin` is its folder under addons/ (from addons_list) or the res:// path of its plugin.cfg.",
		{"plugin": {"type": "string"}, "enabled": {"type": "boolean"}}, ["plugin", "enabled"], _plugin_enable)
	enable.describer = func(args: Dictionary) -> String:
		return "%s %s" % ["enable" if args.get("enabled", true) else "disable", McpTool.str_arg(args, "plugin")]
	return [
		McpTool.create("asset_search", read,
			"Searches the Godot Asset Store (store.godotengine.org) for assets compatible with this Godot version: addons, tools, shaders, art packs… Use it to suggest a plugin before writing one from scratch. Returns ids (publisher/slug) for asset_details and asset_install.",
			{
				"query": {"type": "string", "description": "Words to search; empty lists the most relevant"},
				"page": {"type": "integer", "description": "From 1; 24 per page"},
				"sort": {"type": "string", "enum": Array(AssetStore.SORTS)},
			}, [], _search),
		McpTool.create("asset_details", read,
			"The Asset Store page of an asset: description, license, tags, source repository and the releases that work with this Godot version.",
			{"asset": {"type": "string", "description": "publisher/slug"}}, ["asset"], _details),
		install,
		McpTool.create("addons_list", read,
			"Lists the editor plugins in the project's addons/ folder with their version and whether they're enabled.",
			{}, [], _addons_list),
		enable,
	]


func _search(args: Dictionary) -> Dictionary:
	if not is_instance_valid(store):
		return McpTool.error("The Asset Store is not available.")
	var page := maxi(1, McpTool.int_arg(args, "page", 1))
	var result: Dictionary = await store.search(McpTool.str_arg(args, "query"), page, McpTool.str_arg(args, "sort", "relevance"))
	if not result.error.is_empty():
		return McpTool.error(result.error)
	if result.assets.is_empty():
		return McpTool.text("No assets found for this Godot version.")
	var installed := _installed_folders()
	var lines: PackedStringArray = ["%d results (page %d of %d):" % [result.count, page, result.pages]]
	for asset: Dictionary in result.assets:
		var notes: PackedStringArray = []
		if not asset.license.is_empty():
			notes.append(asset.license)
		if asset.score > 0:
			notes.append("score %d" % asset.score)
		if asset.price_cent > 0:
			notes.append("PAID: buy it on the store website, it can't be installed from here")
		if str(asset.id).get_slice("/", 1).replace("-", "_") in installed:
			notes.append("maybe installed")
		lines.append("- %s — %s by %s (%s): %s" % [asset.id, asset.name, asset.publisher, ", ".join(notes), asset.description])
	return McpTool.text("\n".join(lines))


func _details(args: Dictionary) -> Dictionary:
	if not is_instance_valid(store):
		return McpTool.error("The Asset Store is not available.")
	var asset_id := McpTool.str_arg(args, "asset").strip_edges()
	var data: Dictionary = await store.details(asset_id)
	if not data.error.is_empty():
		return McpTool.error(data.error)
	var asset: Dictionary = data.asset
	var lines: PackedStringArray = ["%s (%s) by %s" % [asset.name, asset.id, asset.publisher]]
	lines.append("License: %s%s" % [asset.license, " · PAID" if asset.price_cent > 0 else ""])
	if not asset.tags.is_empty():
		lines.append("Tags: %s" % ", ".join(asset.tags))
	if not asset.source.is_empty():
		lines.append("Source: %s" % asset.source)
	lines.append("Store page: %s" % asset.store_url)
	var listed: Dictionary = await store.releases(asset_id)
	if not listed.error.is_empty():
		lines.append("Releases: could not read them (%s)" % listed.error)
	elif listed.releases.is_empty():
		lines.append("Releases: none for this Godot version")
	else:
		lines.append("Releases for this Godot version (newest first):")
		for release: Dictionary in listed.releases.slice(0, 8):
			lines.append("- %s%s (%s, Godot %s–%s)" % [release.version, "" if release.stable else " (unstable)", release.date, release.min_godot if not release.min_godot.is_empty() else "?", release.max_godot])
	lines.append("")
	lines.append(asset.description)
	if not asset.body.is_empty():
		lines.append("")
		lines.append(asset.body)
	return McpTool.text("\n".join(lines))


func _install(args: Dictionary) -> Dictionary:
	if not is_instance_valid(store):
		return McpTool.error("The Asset Store is not available.")
	var asset_id := McpTool.str_arg(args, "asset").strip_edges()
	var details: Dictionary = await store.details(asset_id)
	if not details.error.is_empty():
		return McpTool.error(details.error)
	if int(details.asset.price_cent) > 0:
		return McpTool.error("%s is a paid asset: the user has to buy it on %s." % [asset_id, details.asset.store_url])
	var prepared: Dictionary = await store.prepare(asset_id, McpTool.str_arg(args, "version"), not bool(args.get("include_other_files", false)))
	if not prepared.ok:
		return McpTool.error(prepared.error)
	var plan: Dictionary = prepared.plan
	if plan.files.is_empty():
		DirAccess.remove_absolute(prepared.zip)
		return McpTool.error("Nothing to install: every file of %s %s already exists (%d conflicts). Nothing was changed." % [asset_id, prepared.release.version, plan.conflicts.size()])
	var done: Dictionary = await store.finish(prepared, bool(args.get("enable_plugins", true)))
	if not done.ok:
		return McpTool.error("Installing %s stopped after %d files: %s" % [asset_id, done.written, done.error])
	return McpTool.text(install_report(asset_id, prepared.release, plan, done))


static func install_report(asset_id: String, release: Dictionary, plan: Dictionary, done: Dictionary) -> String:
	var lines: PackedStringArray = ["Installed %s %s: %d files." % [asset_id, release.version, done.written]]
	var folders := {}
	for entry: Dictionary in plan.files:
		var target: String = entry.target
		folders["/".join(target.trim_prefix("res://").split("/").slice(0, 2))] = true
	lines.append("Where: %s" % ", ".join(PackedStringArray(folders.keys())))
	if not plan.conflicts.is_empty():
		lines.append("Not overwritten (already existed): %s" % _short_list(plan.conflicts))
	if not plan.other.is_empty():
		lines.append("Left out (outside addons/; include_other_files installs them): %s" % _short_list(plan.other))
	if not plan.plugins.is_empty():
		var enabled: Array = Array(done.enabled)
		for path: String in plan.plugins:
			lines.append("Plugin %s: %s" % [path, "enabled" if path in enabled else "not enabled (plugin_enable enables it)"])
	return "\n".join(lines)


func _addons_list(_args: Dictionary) -> Dictionary:
	var plugins := AssetStore.project_plugins(addons_dir)
	if plugins.is_empty():
		return McpTool.text("The project has no editor plugins in addons/.")
	var lines: PackedStringArray = []
	for plugin: Dictionary in plugins:
		lines.append("- %s: %s%s, %s" % [plugin.folder, plugin.name, " " + plugin.version if not plugin.version.is_empty() else "",
			"enabled" if is_enabled.call(plugin.path) else "disabled"])
	return McpTool.text("\n".join(lines))


func _plugin_enable(args: Dictionary) -> Dictionary:
	var wanted := McpTool.str_arg(args, "plugin").strip_edges().trim_suffix("/")
	var enabled := bool(args.enabled)
	for plugin: Dictionary in AssetStore.project_plugins(addons_dir):
		if wanted in [plugin.folder, plugin.path, "addons/" + plugin.folder, plugin.path.trim_suffix("/plugin.cfg")]:
			if str(plugin.folder).get_slice("/", 0) in PROTECTED_FOLDERS:
				return McpTool.error("The agent can't enable or disable the harness itself.")
			set_enabled.call(plugin.path, enabled)
			if bool(is_enabled.call(plugin.path)) != enabled:
				return McpTool.error("Godot did not %s %s: look at the Output with godot.errors." % ["enable" if enabled else "disable", plugin.folder])
			return McpTool.text("%s %s." % [plugin.name, "enabled" if enabled else "disabled"])
	return McpTool.error("There is no plugin '%s' in addons/. addons_list lists them." % wanted)


func _installed_folders() -> Dictionary:
	var result := {}
	for plugin: Dictionary in AssetStore.project_plugins(addons_dir):
		result[str(plugin.folder).get_slice("/", 0)] = true
	return result


static func _short_list(paths: Array, limit: int = 8) -> String:
	var shown := PackedStringArray(paths.slice(0, limit))
	return ", ".join(shown) + (" and %d more" % (paths.size() - limit) if paths.size() > limit else "")
