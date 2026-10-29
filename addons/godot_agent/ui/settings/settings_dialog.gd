@tool
extends ConfirmationDialog
## Settings del harness (spec §9.5, docs/design pantalla 4). Diálogo propio: una sección en Project
## Settings escribiría en project.godot. Dos destinos:
## - por usuario (EditorSettings `godot_agent/`): perfiles, puerto MCP, cuota, color y dock;
## - por proyecto (`project_config.tres`): permisos, presupuestos, checkpoints y herramientas.
## Se edita una copia y se guarda todo junto al aceptar, después de validar.

signal saved

const HarnessSettings := preload("../../core/harness_settings.gd")
const I18n := preload("../../core/i18n.gd")
const AgentProfile := preload("../../core/agent_profile.gd")
const AcpRegistryDialog := preload("acp_registry_dialog.gd")
const ProjectConfig := preload("../../config/project_config.gd")
const PermissionPolicy := preload("../../session/permission_policy.gd")
const SessionModel := preload("../../session/session_model.gd")
const ExportPresetsPatcher := preload("../../export/export_presets_patcher.gd")
const AgentTheme := preload("../agent_theme.gd")
const CompletionSettingsPage := preload("completion_settings_page.gd")
const AutoRulesPage := preload("auto_rules_page.gd")
const McpServersPage := preload("mcp_servers_page.gd")
const GameCriteria := preload("../../oneshot/game_criteria.gd")
const AddonVersion := preload("../../core/addon_version.gd")
const SuggestedAgents := preload("../../core/suggested_agents.gd")

enum SettingsSection { AGENTS, PERMISSIONS, MCP, ONESHOT, QUOTA, COMPLETION, INTERFACE, EXPORT }
const SECTION_LABELS: PackedStringArray = [
	"Agents",  # i18n
	"Permissions",  # i18n
	"MCP servers",  # i18n
	"One-shot",  # i18n
	"Plan quota",  # i18n
	"Completion",  # i18n
	"Interface",  # i18n
	"Export",  # i18n
]
const DECISIONS: PackedStringArray = [PermissionPolicy.ALLOW, PermissionPolicy.ASK, PermissionPolicy.DENY]
const DECISION_LABELS: Dictionary = {
	PermissionPolicy.ALLOW: "Allow",  # i18n
	PermissionPolicy.ASK: "Ask",  # i18n
	PermissionPolicy.DENY: "Deny",  # i18n
}
## Celdas de la matriz (m12-22): un ícono y un color por decisión.
const DECISION_MARKS: Dictionary = {PermissionPolicy.ALLOW: "✓", PermissionPolicy.ASK: "?", PermissionPolicy.DENY: "✕"}
const MODES: Array[SessionModel.HarnessMode] = [SessionModel.HarnessMode.ASK, SessionModel.HarnessMode.REVIEW, SessionModel.HarnessMode.BUILD, SessionModel.HarnessMode.AUTO, SessionModel.HarnessMode.ONESHOT]
const CONFIG_PROPERTIES: PackedStringArray = ["permissions", "subagent_limits", "permission_timeout_s", "auto_shell_rules", "max_output_chars", "max_image_side", "playtest_on_manual_runs", "compact_tools", "verify_after_turn", "turn_snapshots", "github_pull_requests", "extra_fs_roots", "mcp_servers", "budget_minutes", "budget_tokens", "budget_playtests", "checkpoints_enabled", "spec_review", "loop_repeats", "qa_rounds", "criteria", "completion_enabled", "completion_exclude"]
const DOCK_SLOT_LABELS: PackedStringArray = [
	"Top right",  # i18n
	"Bottom right",  # i18n
	"Top left",  # i18n
	"Bottom left",  # i18n
]

## () -> String: URL actual del server MCP ("" si no escucha).
var mcp_url_provider: Callable
## () -> void: reinicia el server MCP con un token nuevo.
var regenerate_token: Callable
## () -> Array[Dictionary] y () -> void: contadores del completado (sección Completado).
var completion_metrics_provider: Callable
var completion_metrics_reset: Callable
## () -> PackedStringArray: MCP servers de terceros que ya pidieron permiso en la sesión (m7-35).
var seen_mcp_servers_provider: Callable

var _settings: HarnessSettings
var _config: ProjectConfig
var _secret_name := RegEx.create_from_string("(?i)(key|token|secret|password|passwd)")

var _nav: ItemList
var _pages: Array[Control] = []
## Lo que tenía cada sección al abrir (m12-26): la que cambió lleva «•» en la lista de la izquierda.
var _baseline: PackedStringArray = []
var _dirty_timer: Timer
var _error_label: Label
# Agentes
var _profiles: Array[AgentProfile] = []
var _profile_list: VBoxContainer
var _suggested_box: VBoxContainer
var _profile_form: GridContainer
var _registry_dialog: AcpRegistryDialog
var _editing: int = -1
var _form_fields: Dictionary = {}  # nombre -> control
# Permisos
var _matrix: Dictionary = {}  # grupo -> {modo -> OptionButton}
var _subagent_spins: Dictionary = {}  # modo -> SpinBox
var _timeout_spin: SpinBox
var _auto_rules_page: AutoRulesPage
## Filas de la matriz para los MCP servers de terceros (m7-35): se rearman con la lista.
var _mcp_grid: GridContainer
# MCP
var _port_spin: SpinBox
var _url_label: Label
var _roots_edit: TextEdit
var _max_output_spin: SpinBox
var _max_image_spin: SpinBox
var _manual_runs_check: CheckBox
var _verify_check: CheckBox
var _snapshots_check: CheckBox
var _github_pr_check: CheckBox
var _compact_tools_check: CheckBox
var _mcp_servers_page: McpServersPage
# One-shot y cuota
var _budget_spins: Dictionary = {}
var _loop_spin: SpinBox
var _qa_spin: SpinBox
var _spec_review_check: CheckBox
## id -> {weight: SpinBox, threshold: SpinBox}
var _criteria_spins: Dictionary = {}
var _checkpoints_check: CheckBox
var _warn_spin: SpinBox
var _pause_spin: SpinBox
var _pause_check: CheckBox
var _resume_option: OptionButton
# Completado
var _completion_page: CompletionSettingsPage
# Interfaz y export
var _accent_picker: ColorPickerButton
var _dock_option: OptionButton
var _language_option: OptionButton
var _on_open_option: OptionButton
var _update_check: CheckBox
var _update_status: Label
var _update_button: Button
## «Buscar ahora» (m7-38): el plugin busca un release nuevo (y si hay, muestra el aviso en el dock);
## devuelve el texto para mostrar acá. Corrutina: `func() -> String`.
var update_checker: Callable
var _export_label: Label
var _export_button: Button
var _export_confirm: ConfirmationDialog


func setup(settings: HarnessSettings, config: ProjectConfig) -> void:
	_settings = settings
	_config = config


func _ready() -> void:
	_build()


## Arma la UI una vez (también fuera del árbol, para los tests).
func _build() -> void:
	if _nav:
		return
	title = "Agent Harness · Settings"
	ok_button_text = I18n.t("Save")
	cancel_button_text = I18n.t("Cancel")
	dialog_hide_on_ok = false
	min_size = Vector2i(AgentTheme.px(820), AgentTheme.px(560))
	confirmed.connect(_on_save)
	var root := VBoxContainer.new()
	add_child(root)
	var split := HBoxContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.add_theme_constant_override(&"separation", AgentTheme.px(12))
	root.add_child(split)
	_nav = ItemList.new()
	_nav.custom_minimum_size.x = AgentTheme.px(170)
	for label: String in SECTION_LABELS:
		_nav.add_item(I18n.t(label))
	_nav.item_selected.connect(_show_section)
	split.add_child(_nav)
	var pages := MarginContainer.new()
	pages.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.add_child(pages)
	for builder: Callable in [_build_agents, _build_permissions, _build_mcp, _build_oneshot, _build_quota, _build_completion, _build_interface, _build_export]:
		var scroll := ScrollContainer.new()
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		var page := VBoxContainer.new()
		page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		page.add_theme_constant_override(&"separation", AgentTheme.px(8))
		scroll.add_child(page)
		builder.call(page)
		pages.add_child(scroll)
		_pages.append(scroll)
	_error_label = Label.new()
	_error_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_error_label.add_theme_color_override(&"font_color", AgentTheme.ERROR)
	root.add_child(_error_label)
	_group_buttons()
	_dirty_timer = Timer.new()
	_dirty_timer.wait_time = 0.3
	_dirty_timer.timeout.connect(_refresh_dirty)
	add_child(_dirty_timer)
	visibility_changed.connect(func() -> void:
		if visible:
			_dirty_timer.start()
		else:
			_dirty_timer.stop())
	_show_section(SettingsSection.AGENTS)


## Guardar y Cancelar juntos a la derecha (m12-26): el diálogo los separa con espaciadores que se
## estiran; se dejan fijos y uno solo, al principio, empuja los botones al borde.
func _group_buttons() -> void:
	var box := get_ok_button().get_parent() as BoxContainer
	if box == null:
		return
	for child: Node in box.get_children():
		if child is Control and not child is BaseButton:
			(child as Control).size_flags_horizontal = Control.SIZE_FILL
			(child as Control).custom_minimum_size.x = AgentTheme.px(8)
	var push := Control.new()
	push.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(push)
	box.move_child(push, 0)


## Un resumen de los valores de una sección, para saber si cambió.
func section_state(index: int) -> String:
	var parts: PackedStringArray = []
	match index:
		SettingsSection.AGENTS:
			parts.append(JSON.stringify(_profiles.map(func(profile: AgentProfile) -> Dictionary: return profile.to_dict())))
		SettingsSection.MCP:
			parts.append(JSON.stringify(_mcp_servers_page.get(&"_servers")))
	for node: Node in _pages[index].find_children("*", "Control", true, false):
		if node is SpinBox:
			parts.append(str((node as SpinBox).value))
		elif node is CheckBox or node is CheckButton:
			parts.append(str((node as BaseButton).button_pressed))
		elif node is OptionButton:
			parts.append(str((node as OptionButton).selected))
		elif node is ColorPickerButton:
			parts.append((node as ColorPickerButton).color.to_html())
		elif node is LineEdit and not node.get_parent() is SpinBox:
			parts.append((node as LineEdit).text)
		elif node is TextEdit:
			parts.append((node as TextEdit).text)
	return "\n".join(parts)


func _snapshot_sections() -> void:
	_baseline.clear()
	for i in _pages.size():
		_baseline.append(section_state(i))
	_refresh_dirty()


func _refresh_dirty() -> void:
	for i in mini(_pages.size(), _baseline.size()):
		var changed := section_state(i) != _baseline[i]
		_nav.set_item_text(i, ("• " if changed else "") + I18n.t(SECTION_LABELS[i]))
		_nav.set_item_tooltip(i, I18n.t("Changed: not saved yet") if changed else "")


## El registro de ACP, encima de Ajustes (también para reinstalar un agente que falla, m12-13).
## `query` lo abre filtrado (un agente sugerido, m12-21).
func open_registry(query: String = "") -> void:
	if _registry_dialog == null:
		_registry_dialog = AcpRegistryDialog.new()
		_registry_dialog.profile_added.connect(_add_registry_profile)
		_registry_dialog.added_ids = func() -> PackedStringArray:
			return PackedStringArray(_profiles.map(func(profile: AgentProfile) -> String: return profile.id))
		add_child(_registry_dialog)
	_registry_dialog.open(query)


## Carga los valores actuales y abre el diálogo.
func open(section: SettingsSection = SettingsSection.AGENTS) -> void:
	_load()
	_show_section(section)
	popup_centered_clamped(Vector2i(AgentTheme.px(880), AgentTheme.px(620)), 0.9)


func _show_section(index: int) -> void:
	_nav.select(index)
	for i in _pages.size():
		_pages[i].visible = i == index
	if index == SettingsSection.EXPORT:
		_refresh_export()


# --- secciones -----------------------------------------------------------------------------------

## Sin agentes, los sugeridos con lo que piden; con agentes, la lista a la izquierda y el
## formulario del elegido a la derecha (m12-21).
func _build_agents(page: VBoxContainer) -> void:
	page.add_child(_title(I18n.t("Agents · ACP protocol over stdio")))
	_suggested_box = VBoxContainer.new()
	_suggested_box.add_theme_constant_override(&"separation", AgentTheme.px(6))
	page.add_child(_suggested_box)
	_suggested_box.add_child(_hint(I18n.t("No agents yet. Add one of these, or any other from the ACP registry:")))
	for agent: Dictionary in SuggestedAgents.AGENTS:
		_suggested_box.add_child(_suggested_card(agent))
	var split := HBoxContainer.new()
	split.add_theme_constant_override(&"separation", AgentTheme.px(12))
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.add_child(split)
	var left := VBoxContainer.new()
	left.custom_minimum_size.x = AgentTheme.px(240)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_stretch_ratio = 0.8
	split.add_child(left)
	_profile_list = VBoxContainer.new()
	left.add_child(_profile_list)
	var add := Button.new()
	add.text = I18n.t("+ Add agent")
	add.tooltip_text = I18n.t("A profile you fill in by hand: command, arguments and environment.")
	add.pressed.connect(func() -> void:
		var profile: AgentProfile = AgentProfile.new()
		profile.id = "agente-%d" % (_profiles.size() + 1)
		profile.display_name = I18n.t("New agent")
		_profiles.append(profile)
		_edit_profile(_profiles.size() - 1))
	var from_registry := Button.new()
	from_registry.text = I18n.t("+ From the ACP registry…")
	from_registry.tooltip_text = I18n.t("Claude, Codex, Copilot, Cursor, Google Antigravity and dozens more: pick one and the harness sets up its profile.")
	from_registry.pressed.connect(func() -> void: open_registry())
	var add_row := HFlowContainer.new()
	add_row.add_child(add)
	add_row.add_child(from_registry)
	left.add_child(add_row)
	_profile_form = GridContainer.new()
	_profile_form.columns = 2
	_profile_form.visible = false
	_profile_form.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_profile_form.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	split.add_child(_profile_form)
	for field: Array in [["id", I18n.t("ID")], ["display_name", I18n.t("Name")], ["command", I18n.t("Command")], ["args", I18n.t("Arguments (one per line)")], ["env", I18n.t("Environment (KEY=value or KEY=$VAR)")]]:
		var label := Label.new()
		label.text = field[1]
		label.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		_profile_form.add_child(label)
		var control: Control
		if field[0] in ["args", "env"]:
			var text := TextEdit.new()
			text.custom_minimum_size.y = AgentTheme.px(70)
			text.add_theme_font_override(&"font", AgentTheme.mono_font())
			control = text
		else:
			control = LineEdit.new()
		control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if field[0] == "env":
			# La nota de $VAR va junto al campo que la usa.
			var column := VBoxContainer.new()
			column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			column.add_child(control)
			column.add_child(_hint(I18n.t("In env, \"$VAR\" takes the value of VAR from the editor's environment when the agent is launched: keys are not saved.")))
			_profile_form.add_child(column)
		else:
			_profile_form.add_child(control)
		_form_fields[field[0]] = control
	_profile_form.add_child(Control.new())
	var apply := Button.new()
	apply.text = I18n.t("Done")
	apply.size_flags_horizontal = Control.SIZE_SHRINK_END
	apply.pressed.connect(_apply_profile_form)
	_profile_form.add_child(apply)


## Un agente sugerido: nombre, lo que pide y «Agregar».
func _suggested_card(agent: Dictionary) -> Control:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override(&"panel", AgentTheme.panel(Color(1, 1, 1, 0.04), Color(1, 1, 1, 0.1), 6, 8))
	var row := HBoxContainer.new()
	card.add_child(row)
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(info)
	var name_label := Label.new()
	name_label.text = str(agent.name)
	info.add_child(name_label)
	var needs := _hint(I18n.t(str(agent.needs)))
	info.add_child(needs)
	var add := Button.new()
	add.text = I18n.t("Add")
	add.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	add.pressed.connect(func() -> void: add_suggested(agent))
	row.add_child(add)
	return card


## Agrega un agente sugerido: Claude Code directo; los demás, desde el registro filtrado.
func add_suggested(agent: Dictionary) -> void:
	var data := SuggestedAgents.profile_of(agent)
	if data.is_empty():
		open_registry(str(agent.get("registry_query", "")))
		return
	data["default"] = _profiles.is_empty()
	_add_registry_profile(data)


func _build_completion(page: VBoxContainer) -> void:
	_completion_page = CompletionSettingsPage.new()
	page.add_child(_completion_page)


func _build_permissions(page: VBoxContainer) -> void:
	page.add_child(_title(I18n.t("Permissions by mode")))
	page.add_child(_hint(I18n.t("godot.* tools are authorized in the MCP server; the agent's own tools (shell, file editing) when the agent asks for permission. \"Ask\" shows a card in the chat.")))
	var grid := GridContainer.new()
	grid.columns = MODES.size() + 1
	grid.add_theme_constant_override(&"h_separation", AgentTheme.px(10))
	page.add_child(grid)
	grid.add_child(_hint(I18n.t("Group")))
	for mode: SessionModel.HarnessMode in MODES:
		# Encabezado de la columna con «↺»: vuelve esa columna a los valores de la spec (m12-22).
		var header := HBoxContainer.new()
		# Sin autowrap: dentro de un HBox un Label que parte palabras se dibuja en vertical.
		var mode_label := _hint(I18n.t(SessionModel.HARNESS_MODE_LABELS[mode]))
		mode_label.autowrap_mode = TextServer.AUTOWRAP_OFF
		header.add_child(mode_label)
		var reset := Button.new()
		reset.flat = true
		reset.text = "↺"
		reset.tooltip_text = I18n.t("Restore this column to the defaults")
		reset.pressed.connect(_reset_matrix_column.bind(mode))
		header.add_child(reset)
		grid.add_child(header)
	for group: String in PermissionPolicy.GROUPS:
		var label := Label.new()
		label.text = PermissionPolicy.group_label(group)
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(label)
		_matrix[group] = {}
		for mode: SessionModel.HarnessMode in MODES:
			var option := _matrix_cell(group, mode)
			if group == PermissionPolicy.GROUP_SHELL and mode == SessionModel.HarnessMode.AUTO:
				option.tooltip_text = I18n.t("In Auto mode, \"Ask\" lets the lists of the Auto mode section decide first: commands on the allowlist run without a card.")
			grid.add_child(option)
			_matrix[group][mode] = option
	var limit_label := Label.new()
	limit_label.text = I18n.t("Subagents at once (0 = no limit)")
	limit_label.tooltip_text = I18n.t("How many subagents Claude Code can run at the same time in each mode; one more is rejected with a notice in the chat. 0 = no limit of the harness.")
	limit_label.mouse_filter = Control.MOUSE_FILTER_PASS
	grid.add_child(limit_label)
	for mode: SessionModel.HarnessMode in MODES:
		var spin := SpinBox.new()
		spin.min_value = 0
		spin.max_value = 20
		spin.tooltip_text = limit_label.tooltip_text
		grid.add_child(spin)
		_subagent_spins[mode] = spin
	page.add_child(_hint(I18n.t("A highlighted cell differs from the defaults.")))
	page.add_child(_hint(I18n.t("MCP servers of other programs: their tools ask unless you allow them here. Servers the agent loads from its own configuration show up after they first ask.")))
	_mcp_grid = GridContainer.new()
	_mcp_grid.columns = MODES.size() + 1
	_mcp_grid.add_theme_constant_override(&"h_separation", AgentTheme.px(10))
	page.add_child(_mcp_grid)
	var defaults := Button.new()
	defaults.text = I18n.t("Reset to the spec defaults")
	defaults.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	defaults.pressed.connect(func() -> void:
		_load_matrix({})
		_load_subagent_limits({}))
	page.add_child(defaults)
	_timeout_spin = _spin_row(page, I18n.t("Wait for an answer before denying"), 10, 3600, 1, "s")
	page.add_child(HSeparator.new())
	_auto_rules_page = AutoRulesPage.new()
	page.add_child(_auto_rules_page)


func _build_mcp(page: VBoxContainer) -> void:
	_mcp_servers_page = McpServersPage.new()
	_mcp_servers_page.servers_changed.connect(func() -> void: _rebuild_mcp_matrix(matrix_overrides()))
	page.add_child(_mcp_servers_page)
	page.add_child(HSeparator.new())
	# Lo del servidor del editor, las comprobaciones de cada turno y las carpetas: en «Avanzado»,
	# plegado (m12-23). La página queda para los servidores de otros programas.
	var advanced := FoldableContainer.new()
	advanced.name = "AdvancedMcp"
	advanced.title = I18n.t("Advanced: the editor's MCP server, checks after each turn and folders")
	advanced.folded = true
	page.add_child(advanced)
	page = VBoxContainer.new()
	page.add_theme_constant_override(&"separation", AgentTheme.px(6))
	advanced.add_child(page)
	page.add_child(_title(I18n.t("Editor tools (the addon's MCP server)")))
	_url_label = Label.new()
	_url_label.add_theme_font_override(&"font", AgentTheme.mono_font())
	page.add_child(_url_label)
	_port_spin = _spin_row(page, I18n.t("Port (0 = a random free one; applies when the editor is reopened)"), 0, 65535, 1, "")
	var token := Button.new()
	token.text = I18n.t("Regenerate token")
	token.tooltip_text = I18n.t("Restarts the server with a new token. Open sessions stop seeing the godot.* tools until a new one is opened.")
	token.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	token.pressed.connect(func() -> void:
		if regenerate_token.is_valid():
			regenerate_token.call()
		_refresh_url())
	page.add_child(token)
	_max_output_spin = _spin_row(page, I18n.t("Max characters per result"), 1000, 200000, 1000, "")
	_max_image_spin = _spin_row(page, I18n.t("Max screenshot side"), 256, 4096, 16, "px")
	_manual_runs_check = CheckBox.new()
	_manual_runs_check.text = I18n.t("Use the playtest autoload also when running the game manually")
	page.add_child(_manual_runs_check)
	_compact_tools_check = CheckBox.new()
	_compact_tools_check.text = I18n.t("Compact tool list: the agent finds the extra godot tools with godot.methods")
	_compact_tools_check.tooltip_text = I18n.t("The tool list keeps reading, scene editing and running the game; tilemaps, animation, resources, files, project settings, API docs and the live game go through godot.methods and godot.run. Saves context on every turn. Applies from the next session.")
	page.add_child(_compact_tools_check)
	_verify_check = CheckBox.new()
	_verify_check.text = I18n.t("Check the scripts after each turn")
	_verify_check.tooltip_text = I18n.t("In Build and Auto, when a turn ends the harness validates the scripts that changed. If one doesn't parse, the agent gets the errors to fix them (up to 2 turns in a row); then they stay as a notice in the chat.")
	page.add_child(_verify_check)
	_snapshots_check = CheckBox.new()
	_snapshots_check.text = I18n.t("Keep a snapshot of the project on each turn (git)")
	_snapshots_check.tooltip_text = I18n.t("In Build and Auto, each turn ends with a notice of the files it changed, to see their diff and go back. The snapshots are git commits outside your branches (refs/godot-agent/turns); your branch, index and stash are not touched.")
	page.add_child(_snapshots_check)
	_github_pr_check = CheckBox.new()
	_github_pr_check.text = I18n.t("Offer to push and open a GitHub pull request when closing a separate copy")
	_github_pr_check.tooltip_text = I18n.t("Uses git push and the gh CLI. Off by default: otherwise the harness never pushes.")
	page.add_child(_github_pr_check)
	page.add_child(_title(I18n.t("Folders outside the project")))
	page.add_child(_hint(I18n.t("The agent's fs/* can read and write in these folders besides the project (absolute paths, one per line).")))
	_roots_edit = TextEdit.new()
	_roots_edit.custom_minimum_size.y = AgentTheme.px(70)
	page.add_child(_roots_edit)


## Los valores con que arranca el formulario de la pantalla One-shot (m12-25): allá se cambian para
## una corrida; acá, para todas las del proyecto.
func _build_oneshot(page: VBoxContainer) -> void:
	page.add_child(_title(I18n.t("Starting values for each One-shot (per project)")))
	page.add_child(_hint(I18n.t("The One-shot screen starts with these; you can still change them there before starting a run.")))
	_budget_spins["minutes"] = _spin_row(page, I18n.t("Time"), 1, 600, 1, "min")
	_budget_spins["tokens"] = _spin_row(page, I18n.t("Tokens"), 10000, 20000000, 10000, "")
	_budget_spins["playtests"] = _spin_row(page, I18n.t("Playtests"), 1, 100, 1, "")
	_checkpoints_check = CheckBox.new()
	_checkpoints_check.text = I18n.t("Create a git checkpoint before each One-shot task")
	page.add_child(_checkpoints_check)
	_spec_review_check = CheckBox.new()
	_spec_review_check.text = I18n.t("Review the spec before building (the agent writes it and waits for “Approve spec”)")
	page.add_child(_spec_review_check)
	_loop_spin = _spin_row(page, I18n.t("Loop: identical repetitions"), 2, 20, 1, "")
	_loop_spin.tooltip_text = I18n.t("A check that fails the same way, a tool call that fails with the same arguments, or the same change repeated.\nThe first time, the agent is asked for another approach; if it happens again, the One-shot pauses.")
	_qa_spin = _spin_row(page, I18n.t("QA rounds"), 0, 5, 1, "")
	_qa_spin.tooltip_text = I18n.t("When the agent says the game is done, a separate agent evaluates it (without the builder's context and without editing) and decides the checks. If it doesn't pass, its findings go back to the builder for another round.\n0 = no evaluator: the checks the agent reports count.")
	page.add_child(_title(I18n.t("Game evaluation criteria (per project)")))
	page.add_child(_hint(I18n.t("They go into the agent's prompt and the evaluator's rubric. Scores go from 0 to 10: the game passes if every criterion reaches its minimum. Weight 0 = not used.")))
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override(&"h_separation", AgentTheme.px(10))
	page.add_child(grid)
	for header: String in [I18n.t("Criterion"), I18n.t("Weight"), I18n.t("Minimum")]:
		grid.add_child(_hint(header))
	for criterion: Dictionary in GameCriteria.DEFAULTS:
		var label := Label.new()
		label.text = I18n.t(str(criterion.name))
		label.tooltip_text = criterion.description
		label.mouse_filter = Control.MOUSE_FILTER_PASS
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(label)
		var spins := {}
		for key: String in ["weight", "threshold"]:
			var spin := SpinBox.new()
			spin.min_value = 0
			spin.max_value = 10
			spin.custom_minimum_size.x = AgentTheme.px(90)
			grid.add_child(spin)
			spins[key] = spin
		_criteria_spins[criterion.id] = spins


## La cuota del plan, en su propia sección (m12-25): es del usuario y vale fuera del One-shot también.
func _build_quota(page: VBoxContainer) -> void:
	page.add_child(_title(I18n.t("Quota and limits (per user: the quota belongs to the plan, not the project)")))
	page.add_child(_hint(I18n.t("The ring next to the composer shows it. Warnings apply to every session; the pause, to the One-shot.")))
	_warn_spin = _spin_row(page, I18n.t("Warn at"), 1, 100, 1, "%")
	_pause_check = CheckBox.new()
	_pause_check.text = I18n.t("Pause the One-shot at the threshold (when the current task or turn ends)")
	_pause_check.toggled.connect(func(on: bool) -> void: _pause_spin.editable = on)
	page.add_child(_pause_check)
	_pause_spin = _spin_row(page, I18n.t("Pause threshold"), 1, 100, 1, "%")
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = I18n.t("When the window resets")
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	_resume_option = OptionButton.new()
	_resume_option.add_item(I18n.t("Resume automatically"), HarnessSettings.RESUME_AUTO)
	_resume_option.add_item(I18n.t("Wait for confirmation"), HarnessSettings.RESUME_CONFIRM)
	row.add_child(_resume_option)
	page.add_child(row)


func _build_interface(page: VBoxContainer) -> void:
	page.add_child(_title(I18n.t("Interface")))
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = I18n.t("Accent color")
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	_accent_picker = ColorPickerButton.new()
	_accent_picker.custom_minimum_size = Vector2(AgentTheme.px(80), AgentTheme.px(28))
	_accent_picker.edit_alpha = false
	row.add_child(_accent_picker)
	page.add_child(row)
	var presets := HBoxContainer.new()
	for hex: String in ["#f0a85a", "#d97757", "#6cb4ff", "#7fd98b"]:
		var swatch := Button.new()
		swatch.custom_minimum_size = Vector2(AgentTheme.px(28), AgentTheme.px(22))
		swatch.add_theme_stylebox_override(&"normal", AgentTheme.panel(Color(hex), Color.TRANSPARENT, 3, 0))
		swatch.add_theme_stylebox_override(&"hover", AgentTheme.panel(Color(hex).lightened(0.15), Color.TRANSPARENT, 3, 0))
		swatch.tooltip_text = hex
		swatch.pressed.connect(func() -> void: _accent_picker.color = Color(hex))
		presets.add_child(swatch)
	page.add_child(presets)
	row = HBoxContainer.new()
	label = Label.new()
	label.text = I18n.t("Dock position")
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	_dock_option = OptionButton.new()
	for slot: String in DOCK_SLOT_LABELS:
		_dock_option.add_item(I18n.t(slot))
	row.add_child(_dock_option)
	page.add_child(row)
	row = HBoxContainer.new()
	label = Label.new()
	label.text = I18n.t("Language")
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	_language_option = OptionButton.new()
	for language: Dictionary in I18n.LANGUAGES:
		_language_option.add_item(I18n.t(language.name))
	row.add_child(_language_option)
	page.add_child(row)
	page.add_child(_hint(I18n.t("These apply when the editor is reopened. The position is the initial one: if you move the dock later, the editor remembers where you left it.")))
	row = HBoxContainer.new()
	label = Label.new()
	label.text = I18n.t("When the editor opens")
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	_on_open_option = OptionButton.new()
	_on_open_option.add_item(I18n.t("Show the previous sessions"), HarnessSettings.ON_OPEN_LIST)
	_on_open_option.add_item(I18n.t("Continue the last session"), HarnessSettings.ON_OPEN_CONTINUE)
	row.add_child(_on_open_option)
	page.add_child(row)
	page.add_child(_title(I18n.t("Updates")))
	_update_check = CheckBox.new()
	_update_check.text = I18n.t("Check for a new version when the editor opens (once a day)")
	page.add_child(_update_check)
	row = HBoxContainer.new()
	_update_status = Label.new()
	_update_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_update_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.add_child(_update_status)
	_update_button = Button.new()
	_update_button.text = I18n.t("Check now")
	_update_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_update_button.pressed.connect(_on_check_update)
	row.add_child(_update_button)
	page.add_child(row)


func _on_check_update() -> void:
	if not update_checker.is_valid():
		return
	_update_button.disabled = true
	_update_status.text = I18n.t("Checking…")
	var status: String = await update_checker.call()
	if is_instance_valid(_update_button):
		_update_button.disabled = false
		_update_status.text = status


func _build_export(page: VBoxContainer) -> void:
	page.add_child(_title(I18n.t("Export")))
	page.add_child(_hint(I18n.t("The addon never ends up in an exported game: an export plugin skips it. Also, each preset should exclude addons/godot_agent/* in its filter, in case the addon is disabled before exporting.")))
	_export_label = Label.new()
	_export_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	page.add_child(_export_label)
	_export_button = Button.new()
	_export_button.text = I18n.t("Add the filter to the presets")
	_export_button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_export_confirm = ConfirmationDialog.new()
	_export_confirm.cancel_button_text = I18n.t("Cancel")
	_export_confirm.dialog_text = I18n.t("addons/godot_agent/* will be added to the exclusion filter of the presets that don't have it, in export_presets.cfg. Continue?")
	_export_confirm.confirmed.connect(func() -> void:
		var patched := ExportPresetsPatcher.patch_presets()
		_refresh_export()
		_export_label.text = I18n.t("Filter added to: %s") % ", ".join(patched) if not patched.is_empty() else I18n.t("Nothing needed to change."))
	add_child(_export_confirm)
	_export_button.pressed.connect(func() -> void: _export_confirm.popup_centered())
	page.add_child(_export_button)


# --- carga y guardado ----------------------------------------------------------------------------

func _load() -> void:
	_build()
	_error_label.text = ""
	_profiles = _settings.profiles()
	_editing = -1
	_profile_form.visible = false
	_rebuild_profiles()
	_mcp_servers_page.load_from(_settings.mcp_servers(), _config.mcp_servers)
	_rebuild_mcp_matrix(_config.permissions)
	_load_matrix(_config.permissions)
	_load_subagent_limits(_config.subagent_limits)
	_timeout_spin.value = _config.permission_timeout_s
	_auto_rules_page.load_from(_config.auto_shell_rules)
	_port_spin.value = _settings.mcp_port()
	_refresh_url()
	_max_output_spin.value = _config.max_output_chars
	_max_image_spin.value = _config.max_image_side
	_manual_runs_check.button_pressed = _config.playtest_on_manual_runs
	_compact_tools_check.button_pressed = _config.compact_tools
	_verify_check.button_pressed = _config.verify_after_turn
	_snapshots_check.button_pressed = _config.turn_snapshots
	_github_pr_check.button_pressed = _config.github_pull_requests
	_roots_edit.text = "\n".join(_config.extra_fs_roots)
	_budget_spins.minutes.value = _config.budget_minutes
	_budget_spins.tokens.value = _config.budget_tokens
	_budget_spins.playtests.value = _config.budget_playtests
	_checkpoints_check.button_pressed = _config.checkpoints_enabled
	_loop_spin.value = _config.loop_repeats
	_qa_spin.value = _config.qa_rounds
	_spec_review_check.button_pressed = _config.spec_review
	for criterion: Dictionary in GameCriteria.resolve(_config.criteria):
		_criteria_spins[criterion.id].weight.value = criterion.weight
		_criteria_spins[criterion.id].threshold.value = criterion.threshold
	_warn_spin.value = roundi(_settings.quota_warn() * 100.0)
	_pause_spin.value = roundi(_settings.quota_pause() * 100.0)
	_pause_check.button_pressed = _settings.quota_pause_enabled()
	_pause_spin.editable = _pause_check.button_pressed
	_resume_option.select(_resume_option.get_item_index(HarnessSettings.RESUME_AUTO if _settings.quota_resume_auto() else HarnessSettings.RESUME_CONFIRM))
	_accent_picker.color = _settings.accent_color()
	_dock_option.select(clampi(_settings.dock_slot(), 0, DOCK_SLOT_LABELS.size() - 1))
	var language_codes: Array = I18n.LANGUAGES.map(func(language: Dictionary) -> String: return language.code)
	_language_option.select(maxi(language_codes.find(_settings.language()), 0))
	_update_check.button_pressed = _settings.update_check_on_start()
	_on_open_option.select(_on_open_option.get_item_index(HarnessSettings.ON_OPEN_CONTINUE if _settings.continue_on_open() else HarnessSettings.ON_OPEN_LIST))
	_update_status.text = I18n.t("Installed version: %s") % AddonVersion.version()
	_completion_page.metrics_provider = completion_metrics_provider
	_completion_page.metrics_reset = completion_metrics_reset
	_completion_page.load_from(_settings, _config)
	_snapshot_sections()


func _load_matrix(overrides: Dictionary) -> void:
	var policy := PermissionPolicy.new(overrides)
	for group: String in _matrix:
		for mode: SessionModel.HarnessMode in _matrix[group]:
			(_matrix[group][mode] as OptionButton).select(DECISIONS.find(policy.matrix_value(group, mode)))
			_style_matrix_cell(_matrix[group][mode], group, mode)


func _load_subagent_limits(limits: Dictionary) -> void:
	var policy := PermissionPolicy.new()
	policy.subagent_limits = limits
	for mode: SessionModel.HarnessMode in _subagent_spins:
		(_subagent_spins[mode] as SpinBox).value = policy.subagent_limit(mode)


## Límites de subagentes de la UI: mode_key -> int, sin los modos en 0.
func subagent_limits() -> Dictionary:
	var limits := {}
	for mode: SessionModel.HarnessMode in _subagent_spins:
		var value := int((_subagent_spins[mode] as SpinBox).value)
		if value > 0:
			limits[PermissionPolicy.MODE_KEYS[mode]] = value
	return limits


func _on_save() -> void:
	if _profile_form.visible:
		_apply_profile_form()
	_mcp_servers_page.apply_pending()
	var error := validate()
	_error_label.text = error.message if not error.is_empty() else ""
	if not error.is_empty():
		_show_section(error.section)
		return
	var before: Dictionary = {}
	for property: String in CONFIG_PROPERTIES:
		before[property] = _config.get(property)
	_settings.save_profiles(_profiles)
	_settings.set_value(HarnessSettings.KEY_MCP_PORT, int(_port_spin.value))
	_settings.save_mcp_servers(_mcp_servers_page.user_servers())
	_settings.set_value(HarnessSettings.KEY_QUOTA_WARN, int(_warn_spin.value))
	_settings.set_value(HarnessSettings.KEY_QUOTA_PAUSE, int(_pause_spin.value))
	_settings.set_value(HarnessSettings.KEY_QUOTA_PAUSE_ENABLED, _pause_check.button_pressed)
	_settings.set_value(HarnessSettings.KEY_QUOTA_RESUME, _resume_option.get_selected_id())
	_settings.set_value(HarnessSettings.KEY_ACCENT, _accent_picker.color)
	_settings.set_value(HarnessSettings.KEY_DOCK_SLOT, _dock_option.selected)
	_settings.set_value(HarnessSettings.KEY_LANGUAGE, I18n.LANGUAGES[_language_option.selected].code)
	_settings.set_value(HarnessSettings.KEY_UPDATE_CHECK, _update_check.button_pressed)
	_settings.set_value(HarnessSettings.KEY_ON_OPEN, _on_open_option.get_selected_id())
	_completion_page.save_to(_settings, _config)
	# La config es la que usa el plugin: si no se puede guardar, vuelve a como estaba.
	_config.permissions = matrix_overrides()
	_config.subagent_limits = subagent_limits()
	_config.permission_timeout_s = int(_timeout_spin.value)
	_config.auto_shell_rules = _auto_rules_page.rules()
	_config.max_output_chars = int(_max_output_spin.value)
	_config.max_image_side = int(_max_image_spin.value)
	_config.playtest_on_manual_runs = _manual_runs_check.button_pressed
	_config.compact_tools = _compact_tools_check.button_pressed
	_config.verify_after_turn = _verify_check.button_pressed
	_config.turn_snapshots = _snapshots_check.button_pressed
	_config.github_pull_requests = _github_pr_check.button_pressed
	_config.extra_fs_roots = _lines(_roots_edit.text)
	_config.mcp_servers = _mcp_servers_page.project_servers()
	_config.budget_minutes = int(_budget_spins.minutes.value)
	_config.budget_tokens = int(_budget_spins.tokens.value)
	_config.budget_playtests = int(_budget_spins.playtests.value)
	_config.checkpoints_enabled = _checkpoints_check.button_pressed
	_config.loop_repeats = int(_loop_spin.value)
	_config.qa_rounds = int(_qa_spin.value)
	_config.spec_review = _spec_review_check.button_pressed
	var criteria := {}
	for criterion: Dictionary in GameCriteria.DEFAULTS:
		var spins: Dictionary = _criteria_spins[criterion.id]
		if int(spins.weight.value) != int(criterion.weight) or int(spins.threshold.value) != int(criterion.threshold):
			criteria[criterion.id] = {"weight": int(spins.weight.value), "threshold": int(spins.threshold.value)}
	_config.criteria = criteria
	var result := _config.save_to_project()
	if result != OK:
		for property: String in before:
			_config.set(property, before[property])
		_error_label.text = I18n.t("Could not save %s: %s") % [ProjectConfig.PATH, error_string(result)]
		return
	hide()
	saved.emit()


## {section, message} del primer problema, o {}.
func validate() -> Dictionary:
	var ids: Dictionary = {}
	var defaults := 0
	for profile: AgentProfile in _profiles:
		# Sin comando vale: queda listado pero no arranca.
		if profile.id.strip_edges().is_empty():
			return {"section": SettingsSection.AGENTS, "message": I18n.t("Each agent needs an ID (%s).") % profile.display_name}
		if ids.has(profile.id):
			return {"section": SettingsSection.AGENTS, "message": I18n.t("Two agents have the ID \"%s\".") % profile.id}
		ids[profile.id] = true
		defaults += 1 if profile.is_default else 0
		for key: String in profile.env:
			var value: String = profile.env[key]
			if _secret_name.search(key) and not value.is_empty() and not value.begins_with("$"):
				return {"section": SettingsSection.AGENTS, "message": I18n.t("%s: %s looks like a secret. Use $VARIABLE from the environment: the harness doesn't store keys.") % [profile.display_name, key]}
	if defaults > 1:
		return {"section": SettingsSection.AGENTS, "message": I18n.t("Only one agent can be the default.")}
	if _pause_check.button_pressed and _pause_spin.value <= _warn_spin.value:
		return {"section": SettingsSection.QUOTA, "message": I18n.t("The pause threshold must be higher than the warning threshold.")}
	for root: String in _lines(_roots_edit.text):
		if not root.is_absolute_path():
			return {"section": SettingsSection.MCP, "message": I18n.t("\"%s\" is not an absolute path.") % root}
	var mcp_error := _mcp_servers_page.validate()
	if not mcp_error.is_empty():
		return {"section": SettingsSection.MCP, "message": mcp_error}
	var rules_error := _auto_rules_page.validate()
	if not rules_error.is_empty():
		return {"section": SettingsSection.PERMISSIONS, "message": rules_error}
	var completion_error := _completion_page.validate()
	if not completion_error.is_empty():
		return {"section": SettingsSection.COMPLETION, "message": completion_error}
	return {}


## Una fila por MCP server de terceros: los de la lista, los que ya pidieron permiso y los que
## tienen valores guardados. `overrides` da los valores de las filas.
func _rebuild_mcp_matrix(overrides: Dictionary) -> void:
	for group: String in _matrix.keys():
		if PermissionPolicy.is_mcp_group(group):
			_matrix.erase(group)
	for child: Node in _mcp_grid.get_children():
		_mcp_grid.remove_child(child)
		child.queue_free()
	var names: Dictionary = {}
	for name: String in _mcp_servers_page.server_names():
		names[name] = true
	if seen_mcp_servers_provider.is_valid():
		for name: String in seen_mcp_servers_provider.call():
			names[name] = true
	for group: String in overrides:
		if PermissionPolicy.is_mcp_group(group):
			names[group.trim_prefix(PermissionPolicy.GROUP_MCP_PREFIX)] = true
	var sorted := names.keys()
	sorted.sort()
	_mcp_grid.visible = not sorted.is_empty()
	var policy := PermissionPolicy.new(overrides)
	for name: String in sorted:
		var group := PermissionPolicy.mcp_group(name)
		var label := Label.new()
		label.text = PermissionPolicy.group_label(group)
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_mcp_grid.add_child(label)
		_matrix[group] = {}
		for mode: SessionModel.HarnessMode in MODES:
			var option := _matrix_cell(group, mode)
			option.select(DECISIONS.find(policy.matrix_value(group, mode)))
			_style_matrix_cell(option, group, mode)
			_mcp_grid.add_child(option)
			_matrix[group][mode] = option


## Una celda: «✓ Permitir», «? Preguntar», «✕ Denegar», con su color y resaltada si no es el default.
func _matrix_cell(group: String, mode: SessionModel.HarnessMode) -> OptionButton:
	var option := OptionButton.new()
	for decision: String in DECISIONS:
		option.add_item("%s %s" % [DECISION_MARKS[decision], I18n.t(DECISION_LABELS[decision])])
	option.item_selected.connect(func(_index: int) -> void: _style_matrix_cell(option, group, mode))
	return option


func _style_matrix_cell(option: OptionButton, group: String, mode: SessionModel.HarnessMode) -> void:
	var decision: String = DECISIONS[maxi(option.selected, 0)]
	var color: Color = {PermissionPolicy.ALLOW: AgentTheme.ADDED, PermissionPolicy.ASK: AgentTheme.WARNING, PermissionPolicy.DENY: AgentTheme.ERROR}[decision]
	for item: StringName in [&"font_color", &"font_hover_color", &"font_pressed_color", &"font_focus_color"]:
		option.add_theme_color_override(item, color)
	var differs := decision != PermissionPolicy.new({}).matrix_value(group, mode)
	option.tooltip_text = I18n.t("Changed: the default is %s") % I18n.t(DECISION_LABELS[PermissionPolicy.new({}).matrix_value(group, mode)]) if differs else ""
	if differs:
		var box := AgentTheme.panel(Color(color, 0.12), Color(_accent_picker.color if _accent_picker else color, 0.9), 4, 4)
		option.add_theme_stylebox_override(&"normal", box)
	else:
		option.remove_theme_stylebox_override(&"normal")


func _reset_matrix_column(mode: SessionModel.HarnessMode) -> void:
	var defaults := PermissionPolicy.new({})
	for group: String in _matrix:
		var option: OptionButton = (_matrix[group] as Dictionary).get(mode)
		if option:
			option.select(DECISIONS.find(defaults.matrix_value(group, mode)))
			_style_matrix_cell(option, group, mode)
	var spin: SpinBox = _subagent_spins.get(mode)
	if spin:
		spin.value = PermissionPolicy.new().subagent_limit(mode)  # sin límites guardados: 0


## Solo lo que difiere de la spec: así un cambio de defaults en el addon llega a los proyectos.
func matrix_overrides() -> Dictionary:
	var defaults := PermissionPolicy.new({})
	var result: Dictionary = {}
	for group: String in _matrix:
		for mode: SessionModel.HarnessMode in _matrix[group]:
			var value: String = DECISIONS[(_matrix[group][mode] as OptionButton).selected]
			if value != defaults.matrix_value(group, mode):
				if not result.has(group):
					result[group] = {}
				result[group][PermissionPolicy.MODE_KEYS[mode]] = value
	return result


# --- perfiles ------------------------------------------------------------------------------------

func _rebuild_profiles() -> void:
	_suggested_box.visible = _profiles.is_empty()
	for child: Node in _profile_list.get_children():
		_profile_list.remove_child(child)
		child.queue_free()
	for i in _profiles.size():
		var profile := _profiles[i]
		var selected := i == _editing and _profile_form.visible
		var card := PanelContainer.new()
		card.add_theme_stylebox_override(&"panel", AgentTheme.panel(Color(1, 1, 1, 0.07 if selected else 0.04), Color(_accent_picker.color if _accent_picker else AgentTheme.MUTED, 0.8) if selected else Color(1, 1, 1, 0.1), 6, 8))
		card.mouse_filter = Control.MOUSE_FILTER_STOP
		card.tooltip_text = I18n.t("Click to edit")
		card.gui_input.connect(func(event: InputEvent) -> void:
			if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
				_edit_profile(i))
		var row := HBoxContainer.new()
		card.add_child(row)
		# Estrella: el predeterminado (llena) o hacerlo predeterminado (vacía).
		var star := Button.new()
		star.flat = true
		star.text = "★" if profile.is_default else "☆"
		star.tooltip_text = I18n.t("Default agent") if profile.is_default else I18n.t("Set as default")
		star.add_theme_color_override(&"font_color", AgentTheme.WARNING if profile.is_default else AgentTheme.MUTED)
		star.pressed.connect(_make_default.bind(i))
		row.add_child(star)
		var info := VBoxContainer.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(info)
		var name_label := Label.new()
		name_label.text = profile.display_name
		name_label.clip_text = true
		name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		info.add_child(name_label)
		var command := Label.new()
		command.text = profile.command_line() if not profile.command.is_empty() else I18n.t("no command: click to set it up")
		command.clip_text = true
		command.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		command.add_theme_font_override(&"font", AgentTheme.mono_font())
		command.add_theme_color_override(&"font_color", AgentTheme.MUTED)
		info.add_child(command)
		var remove := Button.new()
		remove.flat = true
		remove.icon = AgentTheme.icon(&"Remove")
		if remove.icon == null:
			remove.text = "✕"
		remove.tooltip_text = I18n.t("Remove")
		remove.pressed.connect(_remove_profile.bind(i))
		row.add_child(remove)
		_profile_list.add_child(card)


## Un perfil del registro de ACP: reemplaza al de su mismo id (una versión nueva) o se agrega.
func _add_registry_profile(data: Dictionary) -> void:
	var profile: AgentProfile = AgentProfile.from_dict(data)
	for i in _profiles.size():
		if _profiles[i].id == profile.id:
			profile.is_default = _profiles[i].is_default
			_profiles[i] = profile
			_rebuild_profiles()
			return
	_profiles.append(profile)
	_rebuild_profiles()


func _edit_profile(index: int) -> void:
	if _profile_form.visible and _editing >= 0 and _editing != index:
		_apply_profile_form()  # no perder lo que se estaba editando en otro perfil
	_editing = index
	var profile := _profiles[index]
	(_form_fields.id as LineEdit).text = profile.id
	(_form_fields.display_name as LineEdit).text = profile.display_name
	(_form_fields.command as LineEdit).text = profile.command
	(_form_fields.args as TextEdit).text = "\n".join(profile.args)
	var env_lines: PackedStringArray = []
	for key: String in profile.env:
		env_lines.append("%s=%s" % [key, profile.env[key]])
	(_form_fields.env as TextEdit).text = "\n".join(env_lines)
	_profile_form.visible = true
	_rebuild_profiles()


func _apply_profile_form() -> void:
	if _editing < 0 or _editing >= _profiles.size():
		_profile_form.visible = false
		return
	var profile := _profiles[_editing]
	profile.id = (_form_fields.id as LineEdit).text.strip_edges()
	profile.display_name = (_form_fields.display_name as LineEdit).text.strip_edges()
	profile.command = (_form_fields.command as LineEdit).text.strip_edges()
	profile.args = _lines((_form_fields.args as TextEdit).text)
	profile.env = {}
	for line: String in _lines((_form_fields.env as TextEdit).text):
		var equals := line.find("=")
		if equals > 0:
			profile.env[line.left(equals).strip_edges()] = line.substr(equals + 1).strip_edges()
	_editing = -1
	_profile_form.visible = false
	_rebuild_profiles()


func _make_default(index: int) -> void:
	for i in _profiles.size():
		_profiles[i].is_default = i == index
	_rebuild_profiles()


func _remove_profile(index: int) -> void:
	_profiles.remove_at(index)
	if _editing == index:
		_editing = -1
		_profile_form.visible = false
	elif _editing > index:
		_editing -= 1
	_rebuild_profiles()


# --- auxiliares ----------------------------------------------------------------------------------

func _refresh_url() -> void:
	var url: String = mcp_url_provider.call() if mcp_url_provider.is_valid() else ""
	_url_label.text = url if not url.is_empty() else I18n.t("The MCP server is not listening.")


func _refresh_export() -> void:
	if not ExportPresetsPatcher.presets_file_exists():
		_export_label.text = I18n.t("The project has no export presets yet: create one first in Project → Export, then come back to add the filter.")
		_export_button.disabled = true
		_export_button.tooltip_text = I18n.t("Create an export preset first")
		return
	var missing := ExportPresetsPatcher.presets_missing_filter()
	_export_button.disabled = missing.is_empty()
	_export_button.tooltip_text = I18n.t("All presets already have the filter") if missing.is_empty() else ""
	if missing.is_empty():
		_export_label.text = I18n.t("All presets exclude the addon.")
	else:
		_export_label.text = I18n.t("Presets without the filter: %s") % ", ".join(missing)


func _title(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override(&"font_size", AgentTheme.px(15))
	return label


func _hint(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_color_override(&"font_color", AgentTheme.MUTED)
	return label


func _spin_row(page: VBoxContainer, text: String, min_value: float, max_value: float, step: float, suffix: String) -> SpinBox:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = text
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	var spin := SpinBox.new()
	spin.min_value = min_value
	spin.max_value = max_value
	spin.step = step
	spin.suffix = suffix
	spin.custom_minimum_size.x = AgentTheme.px(140)
	row.add_child(spin)
	page.add_child(row)
	return spin


static func _lines(text: String) -> PackedStringArray:
	var result: PackedStringArray = []
	for line: String in text.split("\n"):
		if not line.strip_edges().is_empty():
			result.append(line.strip_edges())
	return result
