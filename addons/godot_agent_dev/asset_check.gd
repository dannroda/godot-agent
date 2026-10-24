@tool
extends RefCounted
## m7-39 de punta a punta, con red y en una copia del proyecto (tests/asset_check.sh): la pestaña
## «Godot addons» de Extensions busca en el Asset Store, instala un plugin chico (Simple TODO, solo
## GDScript) con el diálogo y lo deja activo; después las tools del agente lo listan, lo apagan y lo
## prenden, y volver a instalarlo no pisa nada. Guarda capturas en `<prefijo>_*.png`.

const AssetStore := preload("res://addons/godot_agent/core/asset_store.gd")
const AssetTools := preload("res://addons/godot_agent/mcp/tools/asset_tools.gd")

const ASSET_ID := "kobewi/simple-todo"
const QUERY := "simple todo"
const TIMEOUT_MS := 90000

var _tree: SceneTree


func run(tree: SceneTree, dock: Control, prefix: String) -> PackedStringArray:
	_tree = tree
	var failures: PackedStringArray = []
	var button: Button = dock.get_node("Header").get_node_or_null("ExtensionsButton")
	if button == null:
		return ["el header no tiene el botón de Extensions"]
	button.pressed.emit()
	await tree.create_timer(0.5).timeout
	var window: AcceptDialog = null
	for node: Node in EditorInterface.get_base_control().get_children():
		if node is AcceptDialog and node.get(&"_addons_tab") != null:
			window = node
	if window == null or not window.visible:
		return ["el botón no abrió Extensions"]
	var tabs: TabContainer = window.get(&"_tabs")
	var tab: Control = window.get(&"_addons_tab")
	tabs.current_tab = tab.get_index()
	# Al abrir busca los más relevantes.
	if not await _until(func() -> bool: return not tab.get(&"_searching") and tab.get(&"_searched")):
		return ["la búsqueda inicial no terminó"]
	if not str(tab.get(&"_error")).is_empty():
		return ["la búsqueda inicial falló: %s" % tab.get(&"_error")]
	if (tab.get(&"_assets") as Array).is_empty():
		failures.append("la búsqueda inicial no trajo assets")
	(tab.get(&"_query") as LineEdit).text = QUERY
	tab.call(&"search", 1)
	await _until(func() -> bool: return not tab.get(&"_searching"))
	var asset: Dictionary = {}
	for item: Dictionary in tab.get(&"_assets"):
		if item.id == ASSET_ID:
			asset = item
	if asset.is_empty():
		failures.append("«%s» no trajo %s" % [QUERY, ASSET_ID])
		return failures
	await tree.create_timer(0.5).timeout
	window.get_texture().get_image().save_png("%s_search.png" % prefix)
	# Instalar: baja la release y muestra el diálogo con lo que escribe.
	tab.call(&"_prepare_install", asset)
	var dialog: ConfirmationDialog = tab.get(&"_dialog")
	if not await _until(func() -> bool: return dialog.visible):
		return failures + PackedStringArray(["el diálogo de instalación no apareció (%s)" % (window.get(&"_status") as Label).text])
	var plan: Dictionary = (tab.get(&"_pending") as Dictionary).plan
	if plan.plugins.is_empty():
		failures.append("el plan no tiene plugins: %s" % [plan])
	if plan.files.any(func(entry: Dictionary) -> bool: return not str(entry.target).begins_with("res://addons/")):
		failures.append("instalaría archivos fuera de addons/")
	await tree.create_timer(0.3).timeout
	dialog.get_texture().get_image().save_png("%s_dialog.png" % prefix)
	dialog.get_ok_button().pressed.emit()
	var status: Label = window.get(&"_status")
	if not await _until(func() -> bool: return status.text.contains("installed") or status.text.contains("failed")):
		return failures + PackedStringArray(["la instalación no terminó (%s)" % status.text])
	var plugin_cfg: String = plan.plugins[0] if not plan.plugins.is_empty() else ""
	if not status.text.contains("enabled"):
		failures.append("el estado no dice que activó el plugin: %s" % status.text)
	if plugin_cfg.is_empty() or not EditorInterface.is_plugin_enabled(plugin_cfg):
		failures.append("el plugin %s no quedó activo" % plugin_cfg)
	await tree.create_timer(0.5).timeout
	window.get_texture().get_image().save_png("%s_installed.png" % prefix)
	window.hide()
	failures.append_array(await _check_tools(plugin_cfg))
	return failures


## Las tools del agente sobre lo que quedó instalado.
func _check_tools(plugin_cfg: String) -> PackedStringArray:
	var failures: PackedStringArray = []
	var store := AssetStore.new()
	EditorInterface.get_base_control().add_child(store)
	var tools := AssetTools.new()
	tools.store = store
	var search: Dictionary = await tools._search({"query": "todo"})
	if search.isError or not _text(search).contains(ASSET_ID):
		failures.append("asset_search: %s" % _text(search))
	var details: Dictionary = await tools._details({"asset": ASSET_ID})
	if details.isError or not _text(details).contains("Releases for this Godot version"):
		failures.append("asset_details: %s" % _text(details).left(300))
	var folder := plugin_cfg.trim_prefix("res://addons/").get_base_dir()
	if not _text(tools._addons_list({})).contains("%s:" % folder):
		failures.append("addons_list no lo lista: %s" % _text(tools._addons_list({})))
	var off: Dictionary = tools._plugin_enable({"plugin": folder, "enabled": false})
	if off.isError or EditorInterface.is_plugin_enabled(plugin_cfg):
		failures.append("plugin_enable false: %s" % _text(off))
	var on: Dictionary = tools._plugin_enable({"plugin": folder, "enabled": true})
	if on.isError or not EditorInterface.is_plugin_enabled(plugin_cfg):
		failures.append("plugin_enable true: %s" % _text(on))
	if not tools._plugin_enable({"plugin": "godot_agent", "enabled": false}).isError:
		failures.append("plugin_enable dejó apagar el harness")
	var again: Dictionary = await tools._install({"asset": ASSET_ID})
	if not again.isError or not _text(again).contains("Nothing to install"):
		failures.append("reinstalar debería no pisar nada: %s" % _text(again))
	store.queue_free()
	return failures


func _until(condition: Callable) -> bool:
	var deadline := Time.get_ticks_msec() + TIMEOUT_MS
	while not condition.call():
		if Time.get_ticks_msec() > deadline:
			return false
		await _tree.create_timer(0.2).timeout
	return true


static func _text(result: Dictionary) -> String:
	return str(result.content[0].text)
