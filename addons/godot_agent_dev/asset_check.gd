@tool
extends RefCounted
## m7-39 de punta a punta, con red y en una copia del proyecto (tests/asset_check.sh): la pestaña
## «Godot addons» de Extensions busca en el Asset Store, instala un plugin chico (Simple TODO, solo
## GDScript) con el diálogo y lo deja activo; después las tools del agente lo listan, lo apagan y lo
## prenden, y volver a instalarlo no pisa nada. Por último, con la versión anotada vuelta atrás, la
## pestaña ofrece actualizarlo y la actualización lo deja activo y borra lo que la versión nueva no
## trae; y sin la anotación (instalado a mano), addons_list lo encuentra por el nombre. Guarda
## capturas en `<prefijo>_*.png`.

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
	# La búsqueda está detrás de «Buscar en el Asset Store…» (m12-31): la primera vez trae los más relevantes.
	tab.call(&"show_search")
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
	if not tab.find_children("*", "Button", true, false).any(func(button: Button) -> bool: return button.text == "Installed" and button.disabled):
		failures.append("el resultado del store no dice que ya está instalado")
	window.hide()
	failures.append_array(await _check_tools(plugin_cfg))
	failures.append_array(await _check_update(window, tab, plugin_cfg, prefix))
	return failures


## Una versión vieja anotada: la pestaña la detecta, Actualizar reemplaza la carpeta, borra lo viejo
## y deja el plugin activo.
func _check_update(window: AcceptDialog, tab: Control, plugin_cfg: String, prefix: String) -> PackedStringArray:
	var failures: PackedStringArray = []
	var manifest := AssetStore.read_manifest(AssetStore.MANIFEST_PATH)
	if not manifest.has(ASSET_ID):
		return ["la instalación no quedó anotada en %s" % AssetStore.MANIFEST_PATH]
	var latest := str(manifest[ASSET_ID].version)
	var stale := plugin_cfg.get_base_dir().path_join("removed_in_new_version.gd")
	var file := FileAccess.open(stale, FileAccess.WRITE)
	file.store_string("extends Node\n")
	file.close()
	manifest[ASSET_ID].version = "v0.1"
	(manifest[ASSET_ID].files as Array).append(stale)
	AssetStore.write_manifest(AssetStore.MANIFEST_PATH, manifest)
	window.popup_centered()
	tab.call(&"check_updates")
	if not await _until(func() -> bool: return not tab.get(&"_checking")):
		return ["la búsqueda de actualizaciones no terminó"]
	var folder := plugin_cfg.get_base_dir().get_file()
	var update: Dictionary = (tab.get(&"_updates") as Dictionary).get(folder, {})
	if update.is_empty() or update.latest != latest or update.guessed:
		return ["no ofreció actualizar %s: %s" % [folder, tab.get(&"_updates")]]
	await _tree.create_timer(0.5).timeout
	window.get_texture().get_image().save_png("%s_update.png" % prefix)
	tab.call(&"_prepare_update", update)
	var dialog: ConfirmationDialog = tab.get(&"_dialog")
	if not await _until(func() -> bool: return dialog.visible):
		return ["el diálogo de actualización no apareció"]
	var text := (tab.get(&"_dialog_text") as Label).text
	if not text.contains("removed") or not text.contains("replace"):
		failures.append("el diálogo no dice qué reemplaza y qué borra: %s" % text)
	dialog.get_texture().get_image().save_png("%s_update_dialog.png" % prefix)
	dialog.get_ok_button().pressed.emit()
	var status: Label = window.get(&"_status")
	if not await _until(func() -> bool: return status.text.contains("updated") or status.text.contains("failed")):
		return failures + PackedStringArray(["la actualización no terminó (%s)" % status.text])
	if not status.text.contains("updated"):
		failures.append("la actualización falló: %s" % status.text)
	if FileAccess.file_exists(stale):
		failures.append("no borró el archivo que la versión nueva no trae")
	if not EditorInterface.is_plugin_enabled(plugin_cfg):
		failures.append("después de actualizar, el plugin quedó apagado")
	if str(AssetStore.read_manifest(AssetStore.MANIFEST_PATH)[ASSET_ID].version) != latest:
		failures.append("la anotación no tiene la versión nueva")
	window.hide()
	# Instalado a mano: sin anotación y con un plugin.cfg de versión vieja, se lo busca por el nombre.
	DirAccess.remove_absolute(AssetStore.MANIFEST_PATH)
	var config := ConfigFile.new()
	config.load(plugin_cfg)
	config.set_value("plugin", "version", "0.1")
	config.save(plugin_cfg)
	var store := AssetStore.new()
	EditorInterface.get_base_control().add_child(store)
	var tools := AssetTools.new()
	tools.store = store
	var listed := _text(await tools._addons_list({"check_updates": true}))
	if not listed.contains("update available: 0.1 → %s (asset_install asset=%s update=true; matched by name)" % [latest, ASSET_ID]):
		failures.append("addons_list no encontró la actualización por el nombre: %s" % listed)
	store.queue_free()
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
	if not _text(await tools._addons_list({})).contains("%s:" % folder):
		failures.append("addons_list no lo lista: %s" % _text(await tools._addons_list({})))
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
