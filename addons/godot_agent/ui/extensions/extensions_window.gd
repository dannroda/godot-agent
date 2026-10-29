@tool
extends AcceptDialog
## Ventana Extensions (m7-37), desde el header del dock: plugins y marketplaces de Claude Code,
## todos los MCP servers que ve el agente con su estado, las skills (m7-36, SkillsTab) y los addons
## de Godot del proyecto y del Asset Store (m7-39, GodotAddonsTab). Los cambios se aplican al toque por el CLI
## (ClaudeExtensions); los de plugins valen desde la próxima sesión, y la franja de arriba lo dice
## con un botón para abrir una.

## «Nueva sesión» de la franja: los plugins se cargan al abrir la sesión.
signal new_session_requested
## Las skills apagadas en el proyecto cambiaron (la pestaña Skills).
signal disabled_skills_changed(names: PackedStringArray)
## «Agregar server» de la pestaña MCP: los servers del addon se editan en Settings.
signal mcp_settings_requested
## «Configurar un agente…» cuando no hay ninguno (m12-30): abrir Ajustes › Agentes.
signal agents_requested

const I18n := preload("../../core/i18n.gd")
const AgentTheme := preload("../agent_theme.gd")
const ClaudeExtensions := preload("../../extensions/claude_extensions.gd")
const ExtensionsUi := preload("extensions_ui.gd")
const GodotAddonsTab := preload("godot_addons_tab.gd")
const SkillsTab := preload("skills_tab.gd")
const InstructionsTab := preload("instructions_tab.gd")
const SkillCatalog := preload("../../extensions/skill_catalog.gd")

enum ExtensionsTab { PLUGINS, MARKETPLACES, MCP, SKILLS, GODOT_ADDONS, INSTRUCTIONS }
const AVAILABLE_LIMIT := 30
const MCP_ORIGIN_ORDER: PackedStringArray = ["addon", "user", "project", "local", "claude.ai", "plugin", "other"]
const MCP_ORIGIN_LABELS: Dictionary = {
	"addon": "This addon (Settings → MCP servers)",  # i18n
	"user": "User",  # i18n
	"project": "Project (.mcp.json)",  # i18n
	"local": "Local (this project, only you)",  # i18n
	"claude.ai": "claude.ai",  # i18n
	"plugin": "From plugins",  # i18n
	"other": "Other",  # i18n
}
const STATUS_LABELS: Dictionary = {
	ClaudeExtensions.MCP_CONNECTED: "✓ Connected",  # i18n
	ClaudeExtensions.MCP_NEEDS_AUTH: "⚠ Needs auth",  # i18n
	ClaudeExtensions.MCP_FAILED: "✗ Failed",  # i18n
	ClaudeExtensions.MCP_PENDING: "Pending approval",  # i18n
	ClaudeExtensions.MCP_DISABLED: "Disabled",  # i18n
	ClaudeExtensions.MCP_NOT_CONFIGURED: "Not configured",  # i18n
	ClaudeExtensions.MCP_UNKNOWN: "Unknown",  # i18n
}
const SCOPE_LABELS: Dictionary = {
	"user": "User (all projects)",  # i18n
	"project": "Project (shared, .claude/settings.json)",  # i18n
	"local": "Local (this project, only you)",  # i18n
}

var extensions: ClaudeExtensions
## () -> Array: los MCP servers de terceros del addon (Settings), para la pestaña MCP.
var addon_servers_provider: Callable
## () -> bool: el perfil activo es Claude Code (plugins y marketplaces son de Claude Code).
var is_claude_provider: Callable
## () -> bool: hay algún perfil de agente configurado.
var has_agent_provider: Callable
## () -> String: familia del perfil activo (`claude`, `codex`, `antigravity`, `copilot`, `cursor`, `opencode`, `other`).
var agent_kind_provider: Callable
## El cliente del Asset Store, para la pestaña de addons de Godot.
var asset_store: Node
## Skills apagadas en el proyecto (ProjectConfig.disabled_skills), para la pestaña Skills.
var disabled_skills: PackedStringArray = []

var _tabs: TabContainer
## Las secciones a la izquierda, como en Ajustes: seis pestañas no entraban en la ventana (m12-04).
var _nav: ItemList
var _banner: PanelContainer
var _status: Label
var _plugin_search: LineEdit
var _scope_option: OptionButton
var _plugins_box: VBoxContainer
var _market_source: LineEdit
var _markets_box: VBoxContainer
var _mcp_filter: LineEdit
var _mcp_box: VBoxContainer
var _addons_tab: GodotAddonsTab
var _skills_tab: SkillsTab
var _instructions_tab: InstructionsTab
var _confirm: ConfirmationDialog
var _confirm_action: Callable

var _installed: Array = []
var _available: Array = []
var _markets: Array = []
var _mcp: Array = []
var _plugins_error: String = ""
var _markets_error: String = ""
var _mcp_error: String = ""
var _loading: Dictionary = {}  # pestaña -> true mientras carga
var _busy: int = 0


func _ready() -> void:
	_build()


func _exit_tree() -> void:
	if extensions:
		extensions.cli.stop_all()


func _build() -> void:
	if _tabs:
		return
	title = I18n.t("Extensions")
	ok_button_text = I18n.t("Close")
	min_size = Vector2i(AgentTheme.px(720), AgentTheme.px(600))
	# Las listas se desplazan: que un texto con autowrap no agrande la ventana más allá de la pantalla.
	wrap_controls = false
	var root := VBoxContainer.new()
	root.add_theme_constant_override(&"separation", AgentTheme.px(6))
	add_child(root)
	_banner = PanelContainer.new()
	_banner.add_theme_stylebox_override(&"panel", AgentTheme.panel(Color(AgentTheme.WARNING, 0.12), Color(AgentTheme.WARNING, 0.5), 6, 8))
	_banner.visible = false
	var banner_row := HBoxContainer.new()
	_banner.add_child(banner_row)
	var banner_text := Label.new()
	banner_text.text = I18n.t("Plugin and skill changes apply when a new session opens.")
	banner_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	banner_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	banner_row.add_child(banner_text)
	var restart := Button.new()
	restart.text = I18n.t("New session")
	restart.pressed.connect(func() -> void:
		_banner.visible = false
		new_session_requested.emit())
	banner_row.add_child(restart)
	root.add_child(_banner)
	var split := HBoxContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(split)
	_nav = ItemList.new()
	_nav.custom_minimum_size.x = AgentTheme.px(170)
	_nav.item_selected.connect(func(index: int) -> void: _tabs.current_tab = index)
	split.add_child(_nav)
	_tabs = TabContainer.new()
	_tabs.tabs_visible = false
	_tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# Cada pestaña se mide la primera vez que se muestra: acomodar de nuevo al cambiar.
	_tabs.tab_changed.connect(func(tab: int) -> void:
		if tab < _nav.item_count:  # al agregar la primera pestaña la lista todavía está vacía
			_nav.select(tab)
		ExtensionsUi.refit_dialog(self))
	split.add_child(_tabs)
	_tabs.add_child(_build_plugins_tab())
	_tabs.add_child(_build_markets_tab())
	_tabs.add_child(_build_mcp_tab())
	_skills_tab = SkillsTab.new()
	_skills_tab.status_changed.connect(_set_status)
	_skills_tab.next_session_changed.connect(func() -> void: _banner.visible = true)
	_skills_tab.disabled_changed.connect(func(names: PackedStringArray) -> void:
		disabled_skills = names
		disabled_skills_changed.emit(names))
	_skills_tab.suggested_install_requested.connect(_install_suggested_skills)
	_tabs.add_child(_skills_tab)
	_addons_tab = GodotAddonsTab.new()
	_addons_tab.status_changed.connect(_set_status)
	_tabs.add_child(_addons_tab)
	_instructions_tab = InstructionsTab.new()
	_instructions_tab.status_changed.connect(_set_status)
	_tabs.add_child(_instructions_tab)
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.add_theme_color_override(&"font_color", AgentTheme.MUTED)
	root.add_child(_status)
	_confirm = ConfirmationDialog.new()
	_confirm.cancel_button_text = I18n.t("Cancel")
	_confirm.confirmed.connect(func() -> void:
		if _confirm_action.is_valid():
			_confirm_action.call())
	add_child(_confirm)
	_update_tab_titles()


## Abre la ventana y vuelve a leer todo (el estado de los MCP tarda unos segundos).
func open(tab: ExtensionsTab = ExtensionsTab.PLUGINS) -> void:
	_build()
	_tabs.current_tab = tab
	_nav.select(tab)
	popup_centered_clamped(Vector2i(AgentTheme.px(820), AgentTheme.px(760)), 0.9)
	ExtensionsUi.refit_dialog(self)
	refresh()


func refresh() -> void:
	_addons_tab.store = asset_store
	_addons_tab.refresh()
	_instructions_tab.agent_kind = _agent_kind()
	if extensions and not extensions.cli.cwd.is_empty():
		_instructions_tab.project_path = extensions.cli.cwd
	_instructions_tab.refresh()
	_refresh_skills()
	if not _is_claude():
		_mcp_error = ""
		_mcp = ClaudeExtensions.agent_mcp_servers(_agent_kind(), extensions.cli.cwd if extensions else "", extensions.cli.env if extensions else {})
		_rebuild_all()
		return
	if extensions == null or not extensions.cli.is_available():
		_plugins_error = I18n.t("The Claude Code CLI (claude) was not found in the PATH or next to the ACP adapter. Open a Claude Code session once (npx downloads it) or install Claude Code.")
		_markets_error = _plugins_error
		_mcp_error = _plugins_error
		_rebuild_all()
		return
	_load_plugins(true)
	_load_markets()
	_load_mcp()


# --- pestañas ------------------------------------------------------------------------------------

func _build_plugins_tab() -> Control:
	var page := ExtensionsUi.tab_page("Plugins")
	var bar := HBoxContainer.new()
	page.add_child(bar)
	_plugin_search = LineEdit.new()
	_plugin_search.placeholder_text = I18n.t("Search plugins…")
	_plugin_search.clear_button_enabled = true
	_plugin_search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_plugin_search.text_changed.connect(func(_text: String) -> void: _rebuild_plugins())
	bar.add_child(_plugin_search)
	_scope_option = OptionButton.new()
	for scope: String in ClaudeExtensions.SCOPES:
		_scope_option.add_item(I18n.t(SCOPE_LABELS[scope]))
	_scope_option.tooltip_text = I18n.t("Where Install puts a new plugin.")
	bar.add_child(_scope_option)
	_plugins_box = ExtensionsUi.scroll_list(page)
	return page.get_parent()


func _build_markets_tab() -> Control:
	var page := ExtensionsUi.tab_page("Marketplaces")
	var bar := HBoxContainer.new()
	page.add_child(bar)
	_market_source = LineEdit.new()
	_market_source.placeholder_text = I18n.t("GitHub repo (owner/repo), URL or path…")
	_market_source.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_market_source.text_submitted.connect(func(_text: String) -> void: _on_add_market())
	bar.add_child(_market_source)
	var add := Button.new()
	add.text = I18n.t("Add")
	add.pressed.connect(_on_add_market)
	bar.add_child(add)
	_markets_box = ExtensionsUi.scroll_list(page)
	return page.get_parent()


func _build_mcp_tab() -> Control:
	var page := ExtensionsUi.tab_page("MCP servers")
	var bar := HBoxContainer.new()
	page.add_child(bar)
	_mcp_filter = LineEdit.new()
	_mcp_filter.placeholder_text = I18n.t("Filter servers…")
	_mcp_filter.clear_button_enabled = true
	_mcp_filter.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_mcp_filter.text_changed.connect(func(_text: String) -> void: _rebuild_mcp())
	bar.add_child(_mcp_filter)
	var reload := Button.new()
	reload.icon = AgentTheme.icon(&"Reload")
	reload.tooltip_text = I18n.t("Check the servers again")
	reload.pressed.connect(func() -> void: _load_mcp())
	bar.add_child(reload)
	_mcp_box = ExtensionsUi.scroll_list(page)
	var hint := ExtensionsUi.muted(I18n.t("In a session, /mcp in the chat reconnects or turns off a server (/mcp reconnect <name>, /mcp disable <name>)."))
	page.add_child(hint)
	var add := Button.new()
	add.text = I18n.t("Add server")
	add.tooltip_text = I18n.t("Servers for the agent are added in Settings → MCP servers.")
	add.pressed.connect(func() -> void:
		hide()
		mcp_settings_requested.emit())
	page.add_child(add)
	return page.get_parent()


# --- carga ---------------------------------------------------------------------------------------

func _load_plugins(with_available: bool) -> void:
	_loading[ExtensionsTab.PLUGINS] = true
	_rebuild_plugins()
	var data: Dictionary = await extensions.plugins(with_available)
	_loading.erase(ExtensionsTab.PLUGINS)
	_plugins_error = data.error
	_installed = data.installed
	if with_available or not data.available.is_empty():
		_available = data.available
	_rebuild_plugins()


func _load_markets() -> void:
	_loading[ExtensionsTab.MARKETPLACES] = true
	_rebuild_markets()
	var data: Dictionary = await extensions.marketplaces()
	_loading.erase(ExtensionsTab.MARKETPLACES)
	_markets_error = data.error
	_markets = data.marketplaces
	_rebuild_markets()


func _load_mcp() -> void:
	if not _is_claude():
		_mcp_error = ""
		_mcp = ClaudeExtensions.agent_mcp_servers(_agent_kind(), extensions.cli.cwd if extensions else "", extensions.cli.env if extensions else {})
		_rebuild_mcp()
		return
	_loading[ExtensionsTab.MCP] = true
	_rebuild_mcp()
	var data: Dictionary = await extensions.mcp_servers()
	_loading.erase(ExtensionsTab.MCP)
	_mcp_error = data.error
	_mcp = data.servers
	_rebuild_mcp()
	_rebuild_plugins()  # los chips de los servers de cada plugin toman su estado


# --- listas --------------------------------------------------------------------------------------

func _rebuild_all() -> void:
	_rebuild_plugins()
	_rebuild_markets()
	_rebuild_mcp()


func _rebuild_plugins() -> void:
	ExtensionsUi.clear(_plugins_box)
	_update_tab_titles()
	if not _has_agent():
		_plugins_box.add_child(_no_agent_card())
		return
	if not _is_claude():
		_plugins_box.add_child(ExtensionsUi.muted(I18n.t("Plugins and marketplaces belong to Claude Code, and the active agent profile is another agent.")))
		return
	if not _plugins_error.is_empty():
		_plugins_box.add_child(ExtensionsUi.error_label(_plugins_error))
	if _loading.has(ExtensionsTab.PLUGINS) and _installed.is_empty():
		_plugins_box.add_child(ExtensionsUi.skeleton(I18n.t("Loading…")))
		return
	var query := _plugin_search.text.strip_edges().to_lower()
	var installed := _installed.filter(func(plugin: Variant) -> bool: return plugin is Dictionary and (query.is_empty() or str(plugin.get("id", "")).to_lower().contains(query)))
	_plugins_box.add_child(ExtensionsUi.section(I18n.t("Installed (%d)") % installed.size()))
	for plugin: Dictionary in installed:
		_plugins_box.add_child(_installed_card(plugin))
	var available := ClaudeExtensions.filter_available(_available, _installed, query, AVAILABLE_LIMIT)
	_plugins_box.add_child(ExtensionsUi.section(I18n.t("Available (%d)") % available.total))
	for plugin: Dictionary in available.items:
		_plugins_box.add_child(_available_card(plugin))
	if available.total > available.items.size():
		_plugins_box.add_child(ExtensionsUi.muted(I18n.t("Showing the %d most installed. Search to find the others.") % available.items.size()))


func _installed_card(plugin: Dictionary) -> Control:
	var id := str(plugin.get("id", ""))
	var scope := str(plugin.get("scope", "user"))
	var enabled := bool(plugin.get("enabled", false))
	var card := ExtensionsUi.card()
	var column := VBoxContainer.new()
	card.add_child(column)
	var row := HBoxContainer.new()
	column.add_child(row)
	var dot := Label.new()
	dot.text = "●"
	dot.add_theme_color_override(&"font_color", AgentTheme.ADDED if enabled else AgentTheme.MUTED)
	row.add_child(dot)
	var name := Label.new()
	name.text = id
	name.clip_text = true
	name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name.tooltip_text = "%s\n%s" % [id, plugin.get("version", "")]
	name.mouse_filter = Control.MOUSE_FILTER_PASS
	row.add_child(name)
	var toggle := CheckButton.new()
	toggle.button_pressed = enabled
	toggle.tooltip_text = I18n.t("Enable or disable")
	toggle.toggled.connect(func(on: bool) -> void:
		_run(I18n.t("Enabling %s…") % id if on else I18n.t("Disabling %s…") % id, extensions.set_plugin_enabled.bind(id, on, scope), true))
	row.add_child(toggle)
	row.add_child(ExtensionsUi.icon_button(&"Reload", I18n.t("Update"), func() -> void:
		_run(I18n.t("Updating %s…") % id, extensions.update_plugin.bind(id, scope), true, func(sha: String) -> Callable: return extensions.update_plugin.bind(id, scope, sha))))
	row.add_child(ExtensionsUi.icon_button(&"Remove", I18n.t("Uninstall"), func() -> void:
		_ask(I18n.t("Uninstall %s?") % id, I18n.t("Uninstall"), func() -> void:
			_run(I18n.t("Uninstalling %s…") % id, extensions.uninstall_plugin.bind(id, scope), true))))
	column.add_child(ExtensionsUi.muted(I18n.t("Scope: %s") % scope))
	var servers: Variant = plugin.get("mcpServers")
	if servers is Dictionary and not (servers as Dictionary).is_empty():
		var chips := HFlowContainer.new()
		for server: Variant in servers:
			chips.add_child(_chip(str(server), _plugin_server_status(id, str(server))))
		column.add_child(chips)
	return card


func _available_card(plugin: Dictionary) -> Control:
	var id := str(plugin.get("pluginId", ""))
	var card := ExtensionsUi.card()
	var column := VBoxContainer.new()
	card.add_child(column)
	var row := HBoxContainer.new()
	column.add_child(row)
	var name := Label.new()
	name.text = str(plugin.get("name", id))
	name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name)
	var count := int(plugin.get("installCount", 0))
	if count > 0:
		var installs := ExtensionsUi.muted(I18n.t("%s installs") % _short_count(count))
		installs.autowrap_mode = TextServer.AUTOWRAP_OFF
		row.add_child(installs)
	var install := Button.new()
	install.text = I18n.t("Install")
	install.pressed.connect(func() -> void:
		var scope: String = ClaudeExtensions.SCOPES[_scope_option.selected]
		_run(I18n.t("Installing %s…") % id, extensions.install_plugin.bind(id, scope), true, func(sha: String) -> Callable: return extensions.install_plugin.bind(id, scope, sha)))
	row.add_child(install)
	var description := str(plugin.get("description", ""))
	if not description.is_empty():
		var text := Label.new()
		text.text = description
		text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		column.add_child(text)
	var from := I18n.t("from %s") % plugin.get("marketplaceName", "?")
	var source := _source_link(plugin.get("source"))
	if not source.is_empty():
		from += " · " + source
	column.add_child(ExtensionsUi.muted(from))
	return card


func _rebuild_markets() -> void:
	ExtensionsUi.clear(_markets_box)
	_update_tab_titles()
	if not _has_agent():
		_markets_box.add_child(_no_agent_card())
		return
	if not _is_claude():
		_markets_box.add_child(ExtensionsUi.muted(I18n.t("Plugins and marketplaces belong to Claude Code, and the active agent profile is another agent.")))
		return
	if not _markets_error.is_empty():
		_markets_box.add_child(ExtensionsUi.error_label(_markets_error))
	if _loading.has(ExtensionsTab.MARKETPLACES) and _markets.is_empty():
		_markets_box.add_child(ExtensionsUi.skeleton(I18n.t("Loading…")))
		return
	for market: Variant in _markets:
		if not market is Dictionary:
			continue
		var name := str(market.get("name", ""))
		var card := ExtensionsUi.card()
		var row := HBoxContainer.new()
		card.add_child(row)
		var column := VBoxContainer.new()
		column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(column)
		var label := Label.new()
		label.text = name
		column.add_child(label)
		var where := _source_link(market)
		if not where.is_empty():
			column.add_child(ExtensionsUi.muted(where))
		row.add_child(ExtensionsUi.icon_button(&"Reload", I18n.t("Update"), func() -> void:
			_run(I18n.t("Updating %s…") % name, extensions.update_marketplace.bind(name), false, Callable(), true)))
		row.add_child(ExtensionsUi.icon_button(&"Remove", I18n.t("Remove"), func() -> void:
			_ask(I18n.t("Remove the marketplace %s? Its plugins stay installed until you uninstall them.") % name, I18n.t("Remove"), func() -> void:
				_run(I18n.t("Removing %s…") % name, extensions.remove_marketplace.bind(name), false, Callable(), true))))
		_markets_box.add_child(card)
	if _markets.is_empty() and _markets_error.is_empty():
		_markets_box.add_child(ExtensionsUi.muted(I18n.t("No marketplaces yet.")))


func _rebuild_mcp() -> void:
	ExtensionsUi.clear(_mcp_box)
	_update_tab_titles()
	var query := _mcp_filter.text.strip_edges().to_lower()
	var groups: Dictionary = {}
	var addon: Array = addon_servers_provider.call() if addon_servers_provider.is_valid() else []
	for server: Dictionary in addon:
		var entry := {"name": server.name, "target": "", "status": "addon_on" if server.get("enabled", true) else "addon_off", "detail": "", "origin": "addon"}
		groups.get_or_add("addon", []).append(entry)
	for server: Dictionary in _mcp:
		groups.get_or_add(server.origin, []).append(server)
	if not _mcp_error.is_empty() and _is_claude():
		_mcp_box.add_child(ExtensionsUi.error_label(_mcp_error))
	if not _has_agent():
		_mcp_box.add_child(_no_agent_card())
	if _loading.has(ExtensionsTab.MCP) and _is_claude():
		_mcp_box.add_child(ExtensionsUi.skeleton(I18n.t("Checking the servers…"), 2))
	for origin: String in MCP_ORIGIN_ORDER:
		var servers: Array = groups.get(origin, []).filter(func(server: Dictionary) -> bool: return query.is_empty() or str(server.name).to_lower().contains(query))
		if servers.is_empty():
			continue
		_mcp_box.add_child(ExtensionsUi.section("%s (%d)" % [I18n.t(MCP_ORIGIN_LABELS[origin]), servers.size()]))
		for server: Dictionary in servers:
			_mcp_box.add_child(_mcp_row(server))


func _mcp_row(server: Dictionary) -> Control:
	var card := ExtensionsUi.card()
	var row := HBoxContainer.new()
	card.add_child(row)
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(column)
	var name := Label.new()
	name.text = str(server.name)
	name.add_theme_font_override(&"font", AgentTheme.mono_font())
	name.clip_text = true
	name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	column.add_child(name)
	if not str(server.target).is_empty():
		var target := ExtensionsUi.muted(str(server.target))
		target.autowrap_mode = TextServer.AUTOWRAP_OFF
		target.clip_text = true
		target.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		target.tooltip_text = str(server.target)
		target.mouse_filter = Control.MOUSE_FILTER_PASS
		column.add_child(target)
	if server.status == ClaudeExtensions.MCP_NEEDS_AUTH:
		var login := Button.new()
		login.text = I18n.t("Authenticate")
		login.tooltip_text = I18n.t("Claude Code opens the browser to sign in to this server.")
		login.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		login.pressed.connect(func() -> void:
			_run(I18n.t("Waiting for the sign-in in the browser (%s)…") % server.name, extensions.mcp_login.bind(str(server.name)), false, Callable(), false, true))
		row.add_child(login)
	var badge := _status_badge(str(server.status))
	if not str(server.detail).is_empty():
		badge.tooltip_text = str(server.detail)
	row.add_child(badge)
	return card


# --- acciones ------------------------------------------------------------------------------------

## Corre una acción del CLI con el estado abajo. `plugins_changed` muestra la franja de la próxima
## sesión y vuelve a leer los plugins. `with_sha` arma la misma acción aceptando el comando que
## declara el plugin, si lo pide.
func _run(label: String, action: Callable, plugins_changed: bool, with_sha: Callable = Callable(), markets_changed: bool = false, mcp_changed: bool = false) -> void:
	_busy += 1
	_set_status(label, AgentTheme.MUTED)
	var result: Dictionary = await action.call()
	_busy -= 1
	if result.has("accept_command") and with_sha.is_valid():
		var command: Dictionary = result.accept_command
		_ask(I18n.t("This plugin runs a command of its marketplace to install:\n\n%s\n\nRun it?") % command.command, I18n.t("Run and install"), func() -> void:
			_run(label, with_sha.call(command.sha256), plugins_changed, Callable(), markets_changed, mcp_changed))
		_set_status(str(result.message), AgentTheme.WARNING)
		return
	_set_status(str(result.message), AgentTheme.ADDED if result.ok else AgentTheme.ERROR)
	if result.ok and plugins_changed:
		_banner.visible = true
	if plugins_changed or markets_changed:
		_load_plugins(markets_changed or _available.is_empty())
	if markets_changed:
		_load_markets()
	if mcp_changed or plugins_changed:
		_load_mcp()


func _refresh_skills() -> void:
	_skills_tab.is_claude = _is_claude()
	_skills_tab.agent_kind = _agent_kind()
	_skills_tab.agent_env = extensions.cli.env if extensions else {}
	_skills_tab.project_path = extensions.cli.cwd if extensions else ""
	_skills_tab.claude_config_dir = SkillCatalog.config_dir(extensions.cli.env if extensions else {})
	_skills_tab.disabled = disabled_skills.duplicate()
	_skills_tab.refresh()


## Agrega el marketplace de las skills de Godot (si falta) e instala sus plugins para el usuario.
func _install_suggested_skills() -> void:
	if not _markets.any(func(market: Variant) -> bool: return market is Dictionary and market.get("name") == SkillsTab.SUGGESTED_MARKETPLACE_NAME):
		await _run(I18n.t("Adding %s…") % SkillsTab.SUGGESTED_MARKETPLACE, extensions.add_marketplace.bind(SkillsTab.SUGGESTED_MARKETPLACE), false, Callable(), true)
	for id: String in SkillsTab.SUGGESTED_PLUGINS:
		await _run(I18n.t("Installing %s…") % id, extensions.install_plugin.bind(id, "user"), true)
	_refresh_skills()


func _on_add_market() -> void:
	var source := _market_source.text.strip_edges()
	if source.is_empty():
		return
	_market_source.text = ""
	_run(I18n.t("Adding %s…") % source, extensions.add_marketplace.bind(source), false, Callable(), true)


func _ask(text: String, ok_text: String, action: Callable) -> void:
	_confirm.dialog_text = text
	_confirm.ok_button_text = ok_text
	_confirm_action = action
	_confirm.popup_centered()


func _set_status(text: String, color: Color) -> void:
	_status.text = text
	_status.add_theme_color_override(&"font_color", color)


# --- auxiliares ----------------------------------------------------------------------------------

func _has_agent() -> bool:
	return has_agent_provider.call() if has_agent_provider.is_valid() else true


## Sin agentes: qué falta y cómo agregar uno (m12-30).
func _no_agent_card() -> Control:
	var card := ExtensionsUi.card()
	var row := HBoxContainer.new()
	card.add_child(row)
	var text := ExtensionsUi.muted(I18n.t("No agent set up yet. Plugins, marketplaces and the agent's own MCP servers depend on which one you use."))
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(text)
	var add := Button.new()
	add.text = I18n.t("Set up an agent…")
	add.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	add.pressed.connect(func() -> void: agents_requested.emit())
	row.add_child(add)
	return card


func _is_claude() -> bool:
	return is_claude_provider.call() if is_claude_provider.is_valid() else true


func _agent_kind() -> String:
	if agent_kind_provider.is_valid():
		return str(agent_kind_provider.call())
	return ClaudeExtensions.AGENT_CLAUDE if _is_claude() else ClaudeExtensions.AGENT_OTHER


## Estado del server de un plugin según `claude mcp list` (`plugin:<plugin>:<server>`), o "".
func _plugin_server_status(plugin_id: String, server: String) -> String:
	var name := "plugin:%s:%s" % [plugin_id.get_slice("@", 0), server]
	for entry: Dictionary in _mcp:
		if entry.name == name:
			return entry.status
	return ""


func _update_tab_titles() -> void:
	if not _tabs:
		return
	_tabs.set_tab_title(ExtensionsTab.PLUGINS, I18n.t("Plugins (%d)") % _installed.size())
	_tabs.set_tab_title(ExtensionsTab.MARKETPLACES, I18n.t("Marketplaces (%d)") % _markets.size())
	_tabs.set_tab_title(ExtensionsTab.MCP, I18n.t("MCP servers"))
	_tabs.set_tab_title(ExtensionsTab.SKILLS, I18n.t("Skills"))
	_tabs.set_tab_title(ExtensionsTab.GODOT_ADDONS, I18n.t("Godot addons"))
	_tabs.set_tab_title(ExtensionsTab.INSTRUCTIONS, I18n.t("Instructions"))
	if _nav.item_count != _tabs.get_tab_count():
		_nav.clear()
		for i in _tabs.get_tab_count():
			_nav.add_item("")
	for i in _tabs.get_tab_count():
		_nav.set_item_text(i, _tabs.get_tab_title(i))
	_nav.select(_tabs.current_tab)


func _chip(text: String, status: String) -> Control:
	var chip := PanelContainer.new()
	chip.add_theme_stylebox_override(&"panel", AgentTheme.panel(Color(1, 1, 1, 0.06), Color.TRANSPARENT, 4, 3))
	var label := Label.new()
	label.text = "● " + text
	label.add_theme_font_size_override(&"font_size", AgentTheme.px(11))
	label.add_theme_color_override(&"font_color", _status_color(status) if not status.is_empty() else AgentTheme.MUTED)
	if not status.is_empty():
		label.tooltip_text = I18n.t(STATUS_LABELS.get(status, STATUS_LABELS[ClaudeExtensions.MCP_UNKNOWN]))
		label.mouse_filter = Control.MOUSE_FILTER_PASS
	chip.add_child(label)
	return chip


func _status_badge(status: String) -> Control:
	var badge := PanelContainer.new()
	var color := _status_color(status)
	badge.add_theme_stylebox_override(&"panel", AgentTheme.panel(Color(color, 0.85), Color.TRANSPARENT, 4, 4))
	var label := Label.new()
	match status:
		"addon_on":
			label.text = I18n.t("Passed to the agent")
		"addon_off":
			label.text = I18n.t("Off")
		_:
			label.text = I18n.t(STATUS_LABELS.get(status, STATUS_LABELS[ClaudeExtensions.MCP_UNKNOWN]))
	label.add_theme_font_size_override(&"font_size", AgentTheme.px(12))
	label.add_theme_color_override(&"font_color", Color("#1d1d1d"))
	badge.add_child(label)
	badge.mouse_filter = Control.MOUSE_FILTER_PASS
	badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return badge


static func _status_color(status: String) -> Color:
	match status:
		ClaudeExtensions.MCP_CONNECTED, "addon_on":
			return AgentTheme.ADDED
		ClaudeExtensions.MCP_NEEDS_AUTH, ClaudeExtensions.MCP_PENDING:
			return AgentTheme.WARNING
		ClaudeExtensions.MCP_FAILED:
			return AgentTheme.ERROR
	return AgentTheme.MUTED


## Texto del origen de un plugin o marketplace: `GitHub: owner/repo`, la URL o la ruta.
static func _source_link(source: Variant) -> String:
	if source is String:
		return source
	if not source is Dictionary:
		return ""
	var data: Dictionary = source
	if data.get("source") is Dictionary:
		data = data.source
	if data.get("repo") is String:
		return "GitHub: %s" % data.repo
	for key: String in ["url", "path", "installLocation"]:
		if data.get(key) is String and not str(data[key]).is_empty():
			return str(data[key])
	return ""


static func _short_count(count: int) -> String:
	if count >= 1000000:
		return "%.1fM" % (count / 1000000.0)
	if count >= 1000:
		return "%.1fk" % (count / 1000.0)
	return str(count)
