@tool
extends MarginContainer
## Pestaña «Godot addons» de Extensions (m7-39): los plugins de addons/ del proyecto, con su
## interruptor, y la búsqueda en el Asset Store. Instalar baja la release, muestra qué archivos
## escribe (lo que ya existe no se pisa; lo de afuera de addons/ queda afuera salvo que se pida) y
## después activa sus plugins.

## Texto para la línea de estado de la ventana.
signal status_changed(text: String, color: Color)

const I18n := preload("../../core/i18n.gd")
const AgentTheme := preload("../agent_theme.gd")
const AssetStore := preload("../../core/asset_store.gd")
const AssetTools := preload("../../mcp/tools/asset_tools.gd")
const ExtensionsUi := preload("extensions_ui.gd")

const SORT_LABELS: Dictionary = {
	"relevance": "Most relevant",  # i18n
	"updated_desc": "Recently updated",  # i18n
	"reviews_desc": "Best reviewed",  # i18n
	"created_desc": "Newest",  # i18n
}

var store: AssetStore
## Plugins del proyecto: (path) -> bool y (path, enabled). Por defecto, los del editor.
var is_plugin_enabled: Callable = func(path: String) -> bool: return EditorInterface.is_plugin_enabled(path)
var set_plugin_enabled: Callable = func(path: String, enabled: bool) -> void: EditorInterface.set_plugin_enabled(path, enabled)
var addons_dir: String = "res://addons"

var _query: LineEdit
var _sort: OptionButton
var _box: VBoxContainer
var _pager: HBoxContainer
var _dialog: ConfirmationDialog
var _dialog_text: Label
var _include_other: CheckBox
var _enable_plugins: CheckBox

var _assets: Array[Dictionary] = []
var _error: String = ""
var _searched: bool = false
var _searching: bool = false
var _page: int = 1
var _pages: int = 0
var _count: int = 0
var _busy: bool = false
## Lo que devolvió AssetStore.prepare() más `name`, mientras se confirma la instalación.
var _pending: Dictionary = {}


func _init() -> void:
	name = "Godot addons"
	for side: String in ["left", "right", "top", "bottom"]:
		add_theme_constant_override("margin_" + side, AgentTheme.px(6))
	var page := VBoxContainer.new()
	page.add_theme_constant_override(&"separation", AgentTheme.px(6))
	add_child(page)
	var bar := HBoxContainer.new()
	page.add_child(bar)
	_query = LineEdit.new()
	_query.placeholder_text = I18n.t("Search the Godot Asset Store…")
	_query.clear_button_enabled = true
	_query.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_query.text_submitted.connect(func(_text: String) -> void: search(1))
	bar.add_child(_query)
	_sort = OptionButton.new()
	for sort: String in AssetStore.SORTS:
		_sort.add_item(I18n.t(SORT_LABELS[sort]))
	_sort.item_selected.connect(func(_index: int) -> void: search(1))
	bar.add_child(_sort)
	bar.add_child(ExtensionsUi.icon_button(&"Search", I18n.t("Search the Asset Store"), func() -> void: search(1)))
	_box = ExtensionsUi.scroll_list(page)
	_pager = HBoxContainer.new()
	_pager.alignment = BoxContainer.ALIGNMENT_CENTER
	page.add_child(_pager)
	page.add_child(ExtensionsUi.muted(I18n.t("Assets for this Godot version from store.godotengine.org. Install never overwrites a file of the project. The agent can also search and suggest them.")))
	_build_dialog()


func _build_dialog() -> void:
	_dialog = ConfirmationDialog.new()
	_dialog.title = I18n.t("Install from the Asset Store")
	_dialog.ok_button_text = I18n.t("Install")
	_dialog.cancel_button_text = I18n.t("Cancel")
	var column := VBoxContainer.new()
	_dialog.add_child(column)
	_dialog_text = Label.new()
	_dialog_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_dialog_text.custom_minimum_size.x = AgentTheme.px(420)
	column.add_child(_dialog_text)
	_include_other = CheckBox.new()
	_include_other.text = I18n.t("Also install the files outside addons/ (demos, README…)")
	_include_other.toggled.connect(func(on: bool) -> void:
		if not _pending.is_empty():
			_pending.plan = AssetStore.plan_install(_pending.zip, not on)
			_update_dialog())
	column.add_child(_include_other)
	_enable_plugins = CheckBox.new()
	_enable_plugins.text = I18n.t("Enable its plugins")
	column.add_child(_enable_plugins)
	_dialog.confirmed.connect(_finish_install)
	_dialog.canceled.connect(func() -> void:
		if not _pending.is_empty():
			DirAccess.remove_absolute(_pending.zip)
			status_changed.emit(I18n.t("Install canceled."), AgentTheme.MUTED)
		_pending = {})
	add_child(_dialog)


## Vuelve a leer los plugins del proyecto; la primera vez, busca los assets más relevantes.
func refresh() -> void:
	_rebuild()
	if not _searched:
		search(1)


func search(page: int) -> void:
	if store == null:
		_error = I18n.t("The Asset Store is not available.")
		_rebuild()
		return
	_searched = true
	_searching = true
	_rebuild()
	var sort: String = AssetStore.SORTS[maxi(0, _sort.selected)]
	var result: Dictionary = await store.search(_query.text, page, sort)
	_searching = false
	_error = "" if result.error.is_empty() else I18n.t("Could not search the Asset Store: %s") % result.error
	_assets = result.assets
	_page = page
	_pages = result.pages
	_count = result.count
	_rebuild()


func _rebuild() -> void:
	ExtensionsUi.clear(_box)
	ExtensionsUi.clear(_pager)
	var plugins := AssetStore.project_plugins(addons_dir)
	_box.add_child(ExtensionsUi.section(I18n.t("In this project (%d)") % plugins.size()))
	for plugin: Dictionary in plugins:
		_box.add_child(_plugin_row(plugin))
	if plugins.is_empty():
		_box.add_child(ExtensionsUi.muted(I18n.t("No editor plugins in addons/ yet.")))
	if not _error.is_empty():
		_box.add_child(ExtensionsUi.error_label(_error))
	if _searching:
		_box.add_child(ExtensionsUi.muted(I18n.t("Searching the Asset Store…")))
		return
	if not _searched:
		return
	_box.add_child(ExtensionsUi.section(I18n.t("Asset Store (%d)") % _count))
	for asset: Dictionary in _assets:
		_box.add_child(_asset_card(asset))
	if _assets.is_empty() and _error.is_empty():
		_box.add_child(ExtensionsUi.muted(I18n.t("Nothing found for this Godot version.")))
	if _pages > 1:
		_pager.add_child(_page_button("‹", I18n.t("Previous page"), _page - 1))
		var label := ExtensionsUi.muted(I18n.t("Page %d of %d") % [_page, _pages])
		label.autowrap_mode = TextServer.AUTOWRAP_OFF
		_pager.add_child(label)
		_pager.add_child(_page_button("›", I18n.t("Next page"), _page + 1))


func _page_button(text: String, tooltip: String, target: int) -> Button:
	var button := Button.new()
	button.text = text
	button.tooltip_text = tooltip
	button.disabled = target < 1 or target > _pages
	button.pressed.connect(search.bind(target))
	return button


func _plugin_row(plugin: Dictionary) -> Control:
	var card := ExtensionsUi.card()
	var row := HBoxContainer.new()
	card.add_child(row)
	var enabled := bool(is_plugin_enabled.call(plugin.path))
	var dot := Label.new()
	dot.text = "●"
	dot.add_theme_color_override(&"font_color", AgentTheme.ADDED if enabled else AgentTheme.MUTED)
	row.add_child(dot)
	var title := Label.new()
	title.text = str(plugin.name) if str(plugin.version).is_empty() else "%s %s" % [plugin.name, plugin.version]
	title.clip_text = true
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.tooltip_text = "addons/%s\n%s" % [plugin.folder, plugin.description]
	title.mouse_filter = Control.MOUSE_FILTER_PASS
	row.add_child(title)
	var folder := ExtensionsUi.muted("addons/%s" % plugin.folder)
	folder.autowrap_mode = TextServer.AUTOWRAP_OFF
	row.add_child(folder)
	# El harness no se apaga desde su propia ventana: sin interruptor.
	if str(plugin.folder).get_slice("/", 0) in AssetTools.PROTECTED_FOLDERS:
		return card
	var toggle := CheckButton.new()
	toggle.button_pressed = enabled
	toggle.tooltip_text = I18n.t("Enable or disable")
	toggle.toggled.connect(func(on: bool) -> void:
		set_plugin_enabled.call(plugin.path, on)
		if bool(is_plugin_enabled.call(plugin.path)) == on:
			status_changed.emit((I18n.t("%s enabled.") if on else I18n.t("%s disabled.")) % plugin.name, AgentTheme.ADDED)
		else:
			status_changed.emit(I18n.t("Godot could not change %s: look at the Output panel.") % plugin.name, AgentTheme.ERROR)
		_rebuild.call_deferred())
	row.add_child(toggle)
	return card


func _asset_card(asset: Dictionary) -> Control:
	var card := ExtensionsUi.card()
	var column := VBoxContainer.new()
	card.add_child(column)
	var row := HBoxContainer.new()
	column.add_child(row)
	var title := Label.new()
	title.text = str(asset.name)
	title.clip_text = true
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(title)
	if not str(asset.store_url).is_empty():
		row.add_child(ExtensionsUi.icon_button(&"ExternalLink", I18n.t("Open its page on the store"), OS.shell_open.bind(str(asset.store_url))))
	var install := Button.new()
	if int(asset.price_cent) > 0:
		install.text = I18n.t("Paid")
		install.disabled = true
		install.tooltip_text = I18n.t("Paid assets are bought on the store website.")
	else:
		install.text = I18n.t("Install")
		install.pressed.connect(_prepare_install.bind(asset))
	row.add_child(install)
	if not str(asset.description).is_empty():
		var text := Label.new()
		text.text = str(asset.description)
		text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		column.add_child(text)
	var meta: PackedStringArray = [I18n.t("by %s") % asset.publisher]
	if not str(asset.license).is_empty():
		meta.append(str(asset.license))
	if int(asset.score) > 0:
		meta.append("★ %d" % int(asset.score))
	column.add_child(ExtensionsUi.muted(" · ".join(meta)))
	return card


## Baja la release y muestra qué se va a escribir antes de tocar el proyecto.
func _prepare_install(asset: Dictionary) -> void:
	if _busy or not _pending.is_empty():
		return
	_busy = true
	status_changed.emit(I18n.t("Downloading %s…") % asset.name, AgentTheme.MUTED)
	var prepared: Dictionary = await store.prepare(str(asset.id), "", true)
	_busy = false
	if not prepared.ok:
		status_changed.emit(I18n.t("Could not download %s: %s") % [asset.name, prepared.error], AgentTheme.ERROR)
		return
	_pending = prepared
	_pending.name = str(asset.name)
	_include_other.set_pressed_no_signal(false)
	_enable_plugins.button_pressed = true
	_update_dialog()
	status_changed.emit("", AgentTheme.MUTED)
	_dialog.popup_centered()


func _update_dialog() -> void:
	_dialog_text.text = install_summary(_pending.name, str(_pending.release.version), _pending.plan)
	_enable_plugins.visible = not _pending.plan.plugins.is_empty()
	_include_other.visible = _include_other.button_pressed or not _pending.plan.other.is_empty()
	_dialog.get_ok_button().disabled = _pending.plan.files.is_empty()
	_dialog.reset_size()


## Texto del diálogo de instalación: qué se escribe, qué ya existe y qué queda afuera.
static func install_summary(asset_name: String, version: String, plan: Dictionary) -> String:
	var lines: PackedStringArray = [I18n.t("Install %s %s in the project?") % [asset_name, version], ""]
	var folders := {}
	for entry: Dictionary in plan.files:
		folders["/".join(str(entry.target).trim_prefix("res://").split("/").slice(0, 2))] = true
	if plan.files.is_empty():
		lines.append(I18n.t("Nothing new to write."))
	else:
		lines.append(I18n.t("%d new files in: %s") % [plan.files.size(), ", ".join(PackedStringArray(folders.keys()))])
	if not plan.conflicts.is_empty():
		lines.append(I18n.t("%d already exist and are not overwritten.") % plan.conflicts.size())
	if not plan.other.is_empty():
		lines.append(I18n.t("%d files outside addons/ are left out.") % plan.other.size())
	if plan.plugins.is_empty():
		lines.append(I18n.t("It has no editor plugin to enable."))
	return "\n".join(lines)


func _finish_install() -> void:
	var prepared := _pending
	_pending = {}
	if prepared.is_empty():
		return
	_busy = true
	status_changed.emit(I18n.t("Installing %s…") % prepared.name, AgentTheme.MUTED)
	var done: Dictionary = await store.finish(prepared, _enable_plugins.button_pressed)
	_busy = false
	if not done.ok:
		status_changed.emit(I18n.t("Installing %s failed: %s") % [prepared.name, done.error], AgentTheme.ERROR)
	elif not done.enabled.is_empty():
		status_changed.emit(I18n.t("%s installed (%d files) and its plugins enabled.") % [prepared.name, done.written], AgentTheme.ADDED)
	else:
		status_changed.emit(I18n.t("%s installed (%d files).") % [prepared.name, done.written], AgentTheme.ADDED)
	_rebuild()
