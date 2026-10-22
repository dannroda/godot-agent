@tool
extends ConfirmationDialog
## Settings del harness (spec §9.5, docs/design pantalla 4). Diálogo propio: una sección en Project
## Settings escribiría en project.godot. Dos destinos:
## - por usuario (EditorSettings `godot_agent/`): perfiles, puerto MCP, cuota, color y dock;
## - por proyecto (`project_config.tres`): permisos, presupuestos, checkpoints y herramientas.
## Se edita una copia y se guarda todo junto al aceptar, después de validar.

signal saved

const HarnessSettings := preload("../../core/harness_settings.gd")
const AgentProfile := preload("../../core/agent_profile.gd")
const ProjectConfig := preload("../../config/project_config.gd")
const PermissionPolicy := preload("../../session/permission_policy.gd")
const SessionModel := preload("../../session/session_model.gd")
const ExportPresetsPatcher := preload("../../export/export_presets_patcher.gd")
const AgentTheme := preload("../agent_theme.gd")
const CompletionSettingsPage := preload("completion_settings_page.gd")
const GameCriteria := preload("../../oneshot/game_criteria.gd")

enum Section { AGENTS, PERMISSIONS, MCP, ONESHOT, COMPLETION, INTERFACE, EXPORT }
const SECTION_LABELS: PackedStringArray = ["Agentes", "Permisos", "Servidor MCP", "One-shot y cuota", "Completado", "Interfaz", "Export"]
const DECISIONS: PackedStringArray = [PermissionPolicy.ALLOW, PermissionPolicy.ASK, PermissionPolicy.DENY]
const DECISION_LABELS: Dictionary = {PermissionPolicy.ALLOW: "sí", PermissionPolicy.ASK: "preguntar", PermissionPolicy.DENY: "no"}
const MODES: Array[SessionModel.HarnessMode] = [SessionModel.HarnessMode.ASK, SessionModel.HarnessMode.REVIEW, SessionModel.HarnessMode.BUILD, SessionModel.HarnessMode.ONESHOT]
const CONFIG_PROPERTIES: PackedStringArray = ["permissions", "permission_timeout_s", "max_output_chars", "max_image_side", "playtest_on_manual_runs", "extra_fs_roots", "budget_minutes", "budget_tokens", "budget_playtests", "checkpoints_enabled", "loop_repeats", "criteria", "completion_enabled", "completion_exclude"]
const DOCK_SLOT_LABELS: PackedStringArray = ["Derecha, arriba", "Derecha, abajo", "Izquierda, arriba", "Izquierda, abajo"]

## () -> String: URL actual del server MCP ("" si no escucha).
var mcp_url_provider: Callable
## () -> void: reinicia el server MCP con un token nuevo.
var regenerate_token: Callable
## () -> Array[Dictionary] y () -> void: contadores del completado (sección Completado).
var completion_metrics_provider: Callable
var completion_metrics_reset: Callable

var _settings: HarnessSettings
var _config: ProjectConfig
var _secret_name := RegEx.create_from_string("(?i)(key|token|secret|password|passwd)")

var _nav: ItemList
var _pages: Array[Control] = []
var _error_label: Label
# Agentes
var _profiles: Array[AgentProfile] = []
var _profile_list: VBoxContainer
var _profile_form: GridContainer
var _editing: int = -1
var _form_fields: Dictionary = {}  # nombre -> control
# Permisos
var _matrix: Dictionary = {}  # grupo -> {modo -> OptionButton}
var _timeout_spin: SpinBox
# MCP
var _port_spin: SpinBox
var _url_label: Label
var _roots_edit: TextEdit
var _max_output_spin: SpinBox
var _max_image_spin: SpinBox
var _manual_runs_check: CheckBox
# One-shot y cuota
var _budget_spins: Dictionary = {}
var _loop_spin: SpinBox
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
	ok_button_text = "Guardar"
	cancel_button_text = "Cancelar"
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
		_nav.add_item(label)
	_nav.item_selected.connect(_show_section)
	split.add_child(_nav)
	var pages := MarginContainer.new()
	pages.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.add_child(pages)
	for builder: Callable in [_build_agents, _build_permissions, _build_mcp, _build_oneshot, _build_completion, _build_interface, _build_export]:
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
	_show_section(Section.AGENTS)


## Carga los valores actuales y abre el diálogo.
func open(section: Section = Section.AGENTS) -> void:
	_load()
	_show_section(section)
	popup_centered_clamped(Vector2i(AgentTheme.px(880), AgentTheme.px(620)), 0.9)


func _show_section(index: int) -> void:
	_nav.select(index)
	for i in _pages.size():
		_pages[i].visible = i == index
	if index == Section.EXPORT:
		_refresh_export()


# --- secciones -----------------------------------------------------------------------------------

func _build_agents(page: VBoxContainer) -> void:
	page.add_child(_title("Agentes · protocolo ACP sobre stdio"))
	page.add_child(_hint("En env, \"$VAR\" toma el valor de VAR del entorno del editor al lanzar el agente: las claves no se guardan."))
	_profile_list = VBoxContainer.new()
	page.add_child(_profile_list)
	var add := Button.new()
	add.text = "+ Agregar agente"
	add.pressed.connect(func() -> void:
		var profile: AgentProfile = AgentProfile.new()
		profile.id = "agente-%d" % (_profiles.size() + 1)
		profile.display_name = "Agente nuevo"
		_profiles.append(profile)
		_edit_profile(_profiles.size() - 1))
	page.add_child(add)
	_profile_form = GridContainer.new()
	_profile_form.columns = 2
	_profile_form.visible = false
	page.add_child(_profile_form)
	for field: Array in [["id", "Id"], ["display_name", "Nombre"], ["command", "Comando"], ["args", "Argumentos (uno por línea)"], ["env", "Entorno (CLAVE=valor o CLAVE=$VAR)"]]:
		var label := Label.new()
		label.text = field[1]
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
		_profile_form.add_child(control)
		_form_fields[field[0]] = control
	_profile_form.add_child(Control.new())
	var apply := Button.new()
	apply.text = "Listo"
	apply.size_flags_horizontal = Control.SIZE_SHRINK_END
	apply.pressed.connect(_apply_profile_form)
	_profile_form.add_child(apply)


func _build_completion(page: VBoxContainer) -> void:
	_completion_page = CompletionSettingsPage.new()
	page.add_child(_completion_page)


func _build_permissions(page: VBoxContainer) -> void:
	page.add_child(_title("Permisos por modo"))
	page.add_child(_hint("Las tools godot.* se autorizan en el server MCP; las del agente (shell, edición de archivos) cuando el agente pide permiso. \"Preguntar\" muestra una tarjeta en el chat."))
	var grid := GridContainer.new()
	grid.columns = 5
	grid.add_theme_constant_override(&"h_separation", AgentTheme.px(10))
	page.add_child(grid)
	grid.add_child(_hint("Grupo"))
	for mode: SessionModel.HarnessMode in MODES:
		grid.add_child(_hint(SessionModel.HARNESS_MODE_LABELS[mode]))
	for group: String in PermissionPolicy.GROUPS:
		var label := Label.new()
		label.text = PermissionPolicy.GROUP_LABELS[group]
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(label)
		_matrix[group] = {}
		for mode: SessionModel.HarnessMode in MODES:
			var option := OptionButton.new()
			for decision: String in DECISIONS:
				option.add_item(DECISION_LABELS[decision])
			grid.add_child(option)
			_matrix[group][mode] = option
	var defaults := Button.new()
	defaults.text = "Volver a los valores de la spec"
	defaults.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	defaults.pressed.connect(func() -> void: _load_matrix({}))
	page.add_child(defaults)
	_timeout_spin = _spin_row(page, "Espera de una pregunta antes de denegar", 10, 3600, 1, "s")


func _build_mcp(page: VBoxContainer) -> void:
	page.add_child(_title("Herramientas del editor (servidor MCP del addon)"))
	_url_label = Label.new()
	_url_label.add_theme_font_override(&"font", AgentTheme.mono_font())
	page.add_child(_url_label)
	_port_spin = _spin_row(page, "Puerto (0 = uno libre al azar; se aplica al reabrir el editor)", 0, 65535, 1, "")
	var token := Button.new()
	token.text = "Regenerar token"
	token.tooltip_text = "Reinicia el server con un token nuevo. Las sesiones abiertas dejan de ver las tools godot.* hasta abrir una nueva."
	token.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	token.pressed.connect(func() -> void:
		if regenerate_token.is_valid():
			regenerate_token.call()
		_refresh_url())
	page.add_child(token)
	_max_output_spin = _spin_row(page, "Máximo de caracteres por resultado", 1000, 200000, 1000, "")
	_max_image_spin = _spin_row(page, "Lado máximo de las capturas", 256, 4096, 16, "px")
	_manual_runs_check = CheckBox.new()
	_manual_runs_check.text = "Usar el autoload de playtest también al correr el juego a mano"
	page.add_child(_manual_runs_check)
	page.add_child(_title("Carpetas fuera del proyecto"))
	page.add_child(_hint("fs/* del agente puede leer y escribir en estas carpetas además del proyecto (rutas absolutas, una por línea)."))
	_roots_edit = TextEdit.new()
	_roots_edit.custom_minimum_size.y = AgentTheme.px(70)
	page.add_child(_roots_edit)


func _build_oneshot(page: VBoxContainer) -> void:
	page.add_child(_title("Presupuestos default (por proyecto)"))
	_budget_spins["minutes"] = _spin_row(page, "Tiempo", 1, 600, 1, "min")
	_budget_spins["tokens"] = _spin_row(page, "Tokens", 10000, 20000000, 10000, "")
	_budget_spins["playtests"] = _spin_row(page, "Playtests", 1, 100, 1, "")
	_checkpoints_check = CheckBox.new()
	_checkpoints_check.text = "Crear un checkpoint git antes de cada tarea de One-shot"
	page.add_child(_checkpoints_check)
	_loop_spin = _spin_row(page, "Loop: repeticiones iguales", 2, 20, 1, "")
	_loop_spin.tooltip_text = "Un check que falla igual, una tool call que falla con los mismos argumentos o el mismo cambio repetido.\nLa primera vez se le pide otro enfoque al agente; si vuelve a pasar, el One-shot se pausa."
	page.add_child(_title("Criterios de evaluación del juego (por proyecto)"))
	page.add_child(_hint("Van en el prompt del agente y en la rúbrica del evaluador. Puntaje de 0 a 10: el juego pasa si cada criterio llega a su mínimo. Peso 0 = no se usa."))
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override(&"h_separation", AgentTheme.px(10))
	page.add_child(grid)
	for header: String in ["Criterio", "Peso", "Mínimo"]:
		grid.add_child(_hint(header))
	for criterion: Dictionary in GameCriteria.DEFAULTS:
		var label := Label.new()
		label.text = criterion.name
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
	page.add_child(_title("Cuota y límites (por usuario: la cuota es del plan, no del proyecto)"))
	_warn_spin = _spin_row(page, "Avisar al llegar a", 1, 100, 1, "%")
	_pause_check = CheckBox.new()
	_pause_check.text = "Pausar el One-shot en el próximo checkpoint al llegar al umbral"
	_pause_check.toggled.connect(func(on: bool) -> void: _pause_spin.editable = on)
	page.add_child(_pause_check)
	_pause_spin = _spin_row(page, "Umbral de pausa", 1, 100, 1, "%")
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = "Al reiniciarse la ventana"
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	_resume_option = OptionButton.new()
	_resume_option.add_item("Retomar solo", HarnessSettings.RESUME_AUTO)
	_resume_option.add_item("Esperar confirmación", HarnessSettings.RESUME_CONFIRM)
	row.add_child(_resume_option)
	page.add_child(row)


func _build_interface(page: VBoxContainer) -> void:
	page.add_child(_title("Interfaz"))
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = "Color de acento"
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
	label.text = "Ubicación del dock"
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	_dock_option = OptionButton.new()
	for slot: String in DOCK_SLOT_LABELS:
		_dock_option.add_item(slot)
	row.add_child(_dock_option)
	page.add_child(row)
	page.add_child(_hint("Se aplican al reabrir el editor. La ubicación es la inicial: si después movés el dock, el editor recuerda dónde lo dejaste."))


func _build_export(page: VBoxContainer) -> void:
	page.add_child(_title("Export"))
	page.add_child(_hint("El addon nunca llega a un juego exportado: un export plugin lo saltea. Además, cada preset debería excluir addons/godot_agent/* en su filtro, por si el addon se deshabilita antes de exportar."))
	_export_label = Label.new()
	_export_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	page.add_child(_export_label)
	_export_button = Button.new()
	_export_button.text = "Agregar el filtro a los presets"
	_export_button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_export_confirm = ConfirmationDialog.new()
	_export_confirm.dialog_text = "Se agrega addons/godot_agent/* al filtro de exclusión de los presets que no lo tienen, en export_presets.cfg. ¿Seguir?"
	_export_confirm.confirmed.connect(func() -> void:
		var patched := ExportPresetsPatcher.patch_presets()
		_refresh_export()
		_export_label.text = "Filtro agregado a: " + ", ".join(patched) if not patched.is_empty() else "No hubo que cambiar nada.")
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
	_load_matrix(_config.permissions)
	_timeout_spin.value = _config.permission_timeout_s
	_port_spin.value = _settings.mcp_port()
	_refresh_url()
	_max_output_spin.value = _config.max_output_chars
	_max_image_spin.value = _config.max_image_side
	_manual_runs_check.button_pressed = _config.playtest_on_manual_runs
	_roots_edit.text = "\n".join(_config.extra_fs_roots)
	_budget_spins.minutes.value = _config.budget_minutes
	_budget_spins.tokens.value = _config.budget_tokens
	_budget_spins.playtests.value = _config.budget_playtests
	_checkpoints_check.button_pressed = _config.checkpoints_enabled
	_loop_spin.value = _config.loop_repeats
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
	_completion_page.metrics_provider = completion_metrics_provider
	_completion_page.metrics_reset = completion_metrics_reset
	_completion_page.load_from(_settings, _config)


func _load_matrix(overrides: Dictionary) -> void:
	var policy := PermissionPolicy.new(overrides)
	for group: String in _matrix:
		for mode: SessionModel.HarnessMode in _matrix[group]:
			(_matrix[group][mode] as OptionButton).select(DECISIONS.find(policy.matrix_value(group, mode)))


func _on_save() -> void:
	if _profile_form.visible:
		_apply_profile_form()
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
	_settings.set_value(HarnessSettings.KEY_QUOTA_WARN, int(_warn_spin.value))
	_settings.set_value(HarnessSettings.KEY_QUOTA_PAUSE, int(_pause_spin.value))
	_settings.set_value(HarnessSettings.KEY_QUOTA_PAUSE_ENABLED, _pause_check.button_pressed)
	_settings.set_value(HarnessSettings.KEY_QUOTA_RESUME, _resume_option.get_selected_id())
	_settings.set_value(HarnessSettings.KEY_ACCENT, _accent_picker.color)
	_settings.set_value(HarnessSettings.KEY_DOCK_SLOT, _dock_option.selected)
	_completion_page.save_to(_settings, _config)
	# La config es la que usa el plugin: si no se puede guardar, vuelve a como estaba.
	_config.permissions = matrix_overrides()
	_config.permission_timeout_s = int(_timeout_spin.value)
	_config.max_output_chars = int(_max_output_spin.value)
	_config.max_image_side = int(_max_image_spin.value)
	_config.playtest_on_manual_runs = _manual_runs_check.button_pressed
	_config.extra_fs_roots = _lines(_roots_edit.text)
	_config.budget_minutes = int(_budget_spins.minutes.value)
	_config.budget_tokens = int(_budget_spins.tokens.value)
	_config.budget_playtests = int(_budget_spins.playtests.value)
	_config.checkpoints_enabled = _checkpoints_check.button_pressed
	_config.loop_repeats = int(_loop_spin.value)
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
		_error_label.text = "No se pudo guardar %s: %s" % [ProjectConfig.PATH, error_string(result)]
		return
	hide()
	saved.emit()


## {section, message} del primer problema, o {}.
func validate() -> Dictionary:
	var ids: Dictionary = {}
	var defaults := 0
	for profile: AgentProfile in _profiles:
		# Sin comando vale: queda listado pero no arranca (el default de Codex viene así).
		if profile.id.strip_edges().is_empty():
			return {"section": Section.AGENTS, "message": "Cada agente necesita un id (%s)." % profile.display_name}
		if ids.has(profile.id):
			return {"section": Section.AGENTS, "message": "Hay dos agentes con el id «%s»." % profile.id}
		ids[profile.id] = true
		defaults += 1 if profile.is_default else 0
		for key: String in profile.env:
			var value: String = profile.env[key]
			if _secret_name.search(key) and not value.is_empty() and not value.begins_with("$"):
				return {"section": Section.AGENTS, "message": "%s: %s parece un secreto. Usá $VARIABLE del entorno: el harness no guarda claves." % [profile.display_name, key]}
	if _profiles.is_empty():
		return {"section": Section.AGENTS, "message": "Tiene que haber al menos un agente."}
	if defaults > 1:
		return {"section": Section.AGENTS, "message": "Solo un agente puede ser el predeterminado."}
	if _pause_check.button_pressed and _pause_spin.value <= _warn_spin.value:
		return {"section": Section.ONESHOT, "message": "El umbral de pausa tiene que ser mayor que el de aviso."}
	for root: String in _lines(_roots_edit.text):
		if not root.is_absolute_path():
			return {"section": Section.MCP, "message": "«%s» no es una ruta absoluta." % root}
	var completion_error := _completion_page.validate()
	if not completion_error.is_empty():
		return {"section": Section.COMPLETION, "message": completion_error}
	return {}


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
	for child: Node in _profile_list.get_children():
		child.queue_free()
	for i in _profiles.size():
		var profile := _profiles[i]
		var card := PanelContainer.new()
		card.add_theme_stylebox_override(&"panel", AgentTheme.panel(Color(1, 1, 1, 0.04), Color(1, 1, 1, 0.1), 6, 8))
		var row := HBoxContainer.new()
		card.add_child(row)
		var info := VBoxContainer.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(info)
		var name_label := Label.new()
		name_label.text = profile.display_name + (" · predeterminado" if profile.is_default else "")
		info.add_child(name_label)
		var command := Label.new()
		command.text = profile.command_line() if not profile.command.is_empty() else "sin comando: configuralo con Editar"
		command.clip_text = true
		command.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		command.add_theme_font_override(&"font", AgentTheme.mono_font())
		command.add_theme_color_override(&"font_color", AgentTheme.MUTED)
		info.add_child(command)
		for action: Array in [["Predeterminado", _make_default], ["Editar", _edit_profile], ["Quitar", _remove_profile]]:
			if action[0] == "Predeterminado" and profile.is_default:
				continue
			var button := Button.new()
			button.text = action[0]
			button.flat = true
			button.pressed.connect((action[1] as Callable).bind(i))
			row.add_child(button)
		_profile_list.add_child(card)


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
	_url_label.text = url if not url.is_empty() else "El server MCP no está escuchando."


func _refresh_export() -> void:
	if not ExportPresetsPatcher.presets_file_exists():
		_export_label.text = "El proyecto no tiene presets de export todavía."
		_export_button.disabled = true
		return
	var missing := ExportPresetsPatcher.presets_missing_filter()
	_export_button.disabled = missing.is_empty()
	if missing.is_empty():
		_export_label.text = "Todos los presets excluyen el addon."
	else:
		_export_label.text = "Presets sin el filtro: " + ", ".join(missing)


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
