@tool
extends VBoxContainer
## Settings del completado (spec §16.10), como sección del diálogo de Settings: on/off, modo,
## fuentes locales, perfiles LLM (sin keys: solo el nombre de la variable de entorno) y los
## contadores por fuente de la sesión. Se edita una copia y se guarda con el resto del diálogo.

const HarnessSettings := preload("../../core/harness_settings.gd")
const I18n := preload("../../core/i18n.gd")
const ProjectConfig := preload("../../config/project_config.gd")
const LlmProfile := preload("../../completion/llm/llm_profile.gd")
const AgentTheme := preload("../agent_theme.gd")

const MODE_LABELS: PackedStringArray = [
	"Local only (no AI)",  # i18n
	"Hybrid: local first, LLM if there's nothing",  # i18n
	"LLM only",  # i18n
]
const SOURCE_LABELS: Dictionary = {
	"rule": "Godot rules",  # i18n
	"retrieval": "Project lines",  # i18n
	"ngram": "N-gram model",  # i18n
	"history": "Typed this session",  # i18n
}
const ENV_NAME := "^[A-Za-z_][A-Za-z0-9_]*$"

## () -> Array[Dictionary]: CompletionMetrics.summary() de la sesión.
var metrics_provider: Callable
## () -> void: reinicia los contadores.
var metrics_reset: Callable

var _settings: HarnessSettings
var _config: ProjectConfig
var _profiles: Array[LlmProfile] = []
var _active_id: String = ""
var _editing: int = -1
var _env_name := RegEx.create_from_string(ENV_NAME)

var _enabled_check: CheckBox
var _project_check: CheckBox
var _mode_option: OptionButton
var _source_checks: Dictionary = {}
var _threshold_spin: SpinBox
var _margin_spin: SpinBox
var _debounce_spin: SpinBox
var _multiline_check: CheckBox
var _max_lines_spin: SpinBox
var _corpus_edit: TextEdit
var _exclude_edit: TextEdit
var _profile_list: VBoxContainer
var _kind_option: OptionButton
var _form: GridContainer
var _form_fields: Dictionary = {}
var _form_warning: Label
var _llm_debounce_spin: SpinBox
var _prefix_spin: SpinBox
var _suffix_spin: SpinBox
var _context_spin: SpinBox
var _marker_check: CheckBox
var _raw_check: CheckBox
var _metrics_grid: GridContainer


func _init() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_theme_constant_override(&"separation", AgentTheme.px(8))
	_build()


func _build() -> void:
	add_child(_title(I18n.t("Inline completion")))
	_enabled_check = _check(I18n.t("Enabled (for you, in every project)"))
	_project_check = _check(I18n.t("Enabled in this project"))
	_mode_option = _option_row(I18n.t("Mode"), MODE_LABELS)
	add_child(_hint(I18n.t("Shortcuts: Tab accepts, Ctrl+→ accepts one word, Esc dismisses, Alt+\\ asks for a suggestion (in hybrid mode, from the LLM), Alt+Shift+\\ turns it on or off.")))

	add_child(_title(I18n.t("Local")))
	for source: String in HarnessSettings.COMPLETION_SOURCES:
		_source_checks[source] = _check(I18n.t(SOURCE_LABELS[source]) if SOURCE_LABELS.has(source) else source)
	_threshold_spin = _spin_row(I18n.t("Ranker threshold"), 0.05, 1.0, 0.01, "")
	_margin_spin = _spin_row(I18n.t("Margin over the runner-up"), 0.0, 0.5, 0.01, "")
	_debounce_spin = _spin_row(I18n.t("Local debounce"), 0, 200, 1, "ms")
	_multiline_check = _check(I18n.t("Multi-line suggestions"))
	_max_lines_spin = _spin_row(I18n.t("Max lines per block"), 1, 16, 1, "")
	add_child(_hint(I18n.t("Extra corpus: folders from your other projects that only train the n-gram (absolute paths, one per line).")))
	_corpus_edit = _text_edit()
	add_child(_hint(I18n.t("Excluded from the corpus in this project (paths relative to res://, one per line):")))
	_exclude_edit = _text_edit()

	add_child(_title(I18n.t("LLM (optional)")))
	add_child(_hint(I18n.t("Keys are not saved: each profile has the name of the editor environment variable that holds it.")))
	_profile_list = VBoxContainer.new()
	add_child(_profile_list)
	var add_row := HBoxContainer.new()
	_kind_option = OptionButton.new()
	for kind: String in LlmProfile.KINDS:
		_kind_option.add_item(I18n.t(LlmProfile.KIND_LABELS[kind]))
	add_row.add_child(_kind_option)
	var add := Button.new()
	add.text = I18n.t("+ Add profile")
	add.pressed.connect(func() -> void:
		var profile: LlmProfile = LlmProfile.make(LlmProfile.KINDS[_kind_option.selected], _free_id(LlmProfile.KINDS[_kind_option.selected]))
		_profiles.append(profile)
		_edit_profile(_profiles.size() - 1))
	add_row.add_child(add)
	add_child(add_row)
	_form = GridContainer.new()
	_form.columns = 2
	_form.visible = false
	add_child(_form)
	for field: Array in [["id", I18n.t("ID")], ["display_name", I18n.t("Name")], ["url", "URL"], ["model", I18n.t("Model")], ["api_key_env", I18n.t("Key variable")],
			["fim_template", I18n.t("FIM template ({prefix}, {suffix}; empty = the endpoint's FIM)")], ["stops", I18n.t("Stops (one per line, \\n = newline)")],
			["temperature", I18n.t("Temperature")], ["max_tokens", I18n.t("Max tokens")]]:
		var label := Label.new()
		label.text = field[1]
		_form.add_child(label)
		var control: Control
		if field[0] == "stops":
			control = _text_edit(false)
		elif field[0] == "temperature":
			control = _spin(0.0, 2.0, 0.05, "")
		elif field[0] == "max_tokens":
			control = _spin(8, 1024, 1, "")
		else:
			control = LineEdit.new()
		control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_form.add_child(control)
		_form_fields[field[0]] = control
	_form.add_child(Control.new())
	_form_warning = _hint("")
	_form_warning.add_theme_color_override(&"font_color", AgentTheme.WARNING)
	_form.add_child(_form_warning)
	_form.add_child(Control.new())
	var apply := Button.new()
	apply.text = I18n.t("Done")
	apply.size_flags_horizontal = Control.SIZE_SHRINK_END
	apply.pressed.connect(apply_form)
	_form.add_child(apply)
	_llm_debounce_spin = _spin_row(I18n.t("LLM debounce"), 75, 1000, 1, "ms")
	_prefix_spin = _spin_row(I18n.t("Prefix (characters before the caret)"), 200, 32000, 100, "")
	_suffix_spin = _spin_row(I18n.t("Suffix (characters after)"), 0, 16000, 100, "")
	_context_spin = _spin_row(I18n.t("Project context (estimated tokens)"), 0, 16000, 50, "")
	_marker_check = _check(I18n.t("Mark LLM suggestions (a dot at the end)"))
	_raw_check = _check(I18n.t("\"Raw\" log: include the suggestions' code in the Agent Log"))

	add_child(_title(I18n.t("This session, by source")))
	_metrics_grid = GridContainer.new()
	_metrics_grid.columns = 6
	_metrics_grid.add_theme_constant_override(&"h_separation", AgentTheme.px(14))
	add_child(_metrics_grid)
	var reset := Button.new()
	reset.text = I18n.t("Reset counters")
	reset.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	reset.pressed.connect(func() -> void:
		if metrics_reset.is_valid():
			metrics_reset.call()
		refresh_metrics())
	add_child(reset)


# --- carga, validación y guardado ----------------------------------------------------------------

func load_from(settings: HarnessSettings, config: ProjectConfig) -> void:
	_settings = settings
	_config = config
	_enabled_check.button_pressed = settings.completion_enabled()
	_project_check.button_pressed = config.completion_enabled
	_mode_option.select(maxi(0, HarnessSettings.COMPLETION_MODES.find(settings.completion_mode())))
	var sources := settings.completion_sources()
	for source: String in _source_checks:
		(_source_checks[source] as CheckBox).button_pressed = bool(sources.get(source, true))
	_threshold_spin.value = settings.completion_threshold()
	_margin_spin.value = settings.completion_margin()
	_debounce_spin.value = settings.completion_debounce_ms()
	_multiline_check.button_pressed = bool(settings.get_value(HarnessSettings.KEY_COMPLETION_MULTILINE, true))
	_max_lines_spin.value = clampi(int(settings.get_value(HarnessSettings.KEY_COMPLETION_MAX_LINES, 8)), 1, 16)
	_corpus_edit.text = "\n".join(settings.completion_extra_corpus())
	_exclude_edit.text = "\n".join(config.completion_exclude)
	_profiles = settings.llm_profiles()
	var active := settings.active_llm_profile()
	_active_id = active.id if active else ""
	_editing = -1
	_form.visible = false
	_rebuild_profiles()
	_llm_debounce_spin.value = settings.llm_debounce_ms()
	_prefix_spin.value = settings.llm_prefix_chars()
	_suffix_spin.value = settings.llm_suffix_chars()
	_context_spin.value = settings.llm_context_tokens()
	_marker_check.button_pressed = settings.llm_marker()
	_raw_check.button_pressed = settings.completion_log_raw()
	refresh_metrics()


## El primer problema, o "".
func validate() -> String:
	if _form.visible:
		apply_form()
	var ids: Dictionary = {}
	for profile: LlmProfile in _profiles:
		if profile.id.is_empty():
			return I18n.t("Each LLM profile needs an ID (%s).") % profile.display_name
		if ids.has(profile.id):
			return I18n.t("Two LLM profiles have the ID \"%s\".") % profile.id
		ids[profile.id] = true
		if profile.needs_key() and profile.api_key_env.is_empty():
			return I18n.t("%s: needs the name of the environment variable that holds the key.") % profile.display_name
		if not profile.api_key_env.is_empty() and (_env_name.search(profile.api_key_env) == null or _looks_like_key(profile.api_key_env)):
			return I18n.t("%s: \"Key variable\" takes the name of an environment variable (for example MISTRAL_API_KEY), not the key.") % profile.display_name
		if not (profile.url.begins_with("http://") or profile.url.begins_with("https://")):
			return I18n.t("%s: the URL must start with http:// or https://.") % profile.display_name
	if _mode_option.selected > 0 and _profiles.is_empty():
		return I18n.t("The hybrid and LLM-only modes need an LLM profile.")
	for root: String in _lines(_corpus_edit.text):
		if not root.is_absolute_path():
			return I18n.t("Extra corpus: \"%s\" is not an absolute path.") % root
	return ""


## Escribe lo de usuario en EditorSettings y lo del proyecto en `config` (el diálogo guarda el
## archivo del proyecto y lo revierte si falla).
func save_to(settings: HarnessSettings, config: ProjectConfig) -> void:
	settings.set_value(HarnessSettings.KEY_COMPLETION_ENABLED, _enabled_check.button_pressed)
	settings.set_value(HarnessSettings.KEY_COMPLETION_MODE, _mode_option.selected)
	for source: String in _source_checks:
		settings.set_value(HarnessSettings.KEY_COMPLETION_SOURCE_PREFIX + source, (_source_checks[source] as CheckBox).button_pressed)
	settings.set_value(HarnessSettings.KEY_COMPLETION_THRESHOLD, _threshold_spin.value)
	settings.set_value(HarnessSettings.KEY_COMPLETION_MARGIN, _margin_spin.value)
	settings.set_value(HarnessSettings.KEY_COMPLETION_DEBOUNCE, int(_debounce_spin.value))
	settings.set_value(HarnessSettings.KEY_COMPLETION_MULTILINE, _multiline_check.button_pressed)
	settings.set_value(HarnessSettings.KEY_COMPLETION_MAX_LINES, int(_max_lines_spin.value))
	settings.set_value(HarnessSettings.KEY_COMPLETION_EXTRA_CORPUS, _lines(_corpus_edit.text))
	settings.save_llm_profiles(_profiles)
	settings.set_value(HarnessSettings.KEY_COMPLETION_LLM_ACTIVE, _active_id)
	settings.set_value(HarnessSettings.KEY_COMPLETION_LLM_DEBOUNCE, int(_llm_debounce_spin.value))
	settings.set_value(HarnessSettings.KEY_COMPLETION_LLM_PREFIX, int(_prefix_spin.value))
	settings.set_value(HarnessSettings.KEY_COMPLETION_LLM_SUFFIX, int(_suffix_spin.value))
	settings.set_value(HarnessSettings.KEY_COMPLETION_LLM_CONTEXT, int(_context_spin.value))
	settings.set_value(HarnessSettings.KEY_COMPLETION_LLM_MARKER, _marker_check.button_pressed)
	settings.set_value(HarnessSettings.KEY_COMPLETION_LOG_RAW, _raw_check.button_pressed)
	config.completion_enabled = _project_check.button_pressed
	config.completion_exclude = _lines(_exclude_edit.text)


func refresh_metrics() -> void:
	for child: Node in _metrics_grid.get_children():
		child.queue_free()
	var rows: Array = metrics_provider.call() if metrics_provider.is_valid() else []
	if rows.is_empty():
		# En una grilla, un label con autowrap queda del ancho de una letra si su columna no se expande.
		_metrics_grid.columns = 1
		var empty := _hint(I18n.t("No suggestions in this session yet."))
		empty.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_metrics_grid.add_child(empty)
		return
	_metrics_grid.columns = 6
	for header: String in [I18n.t("Source"), "p50", "p95", I18n.t("Shown"), I18n.t("Accepted"), I18n.t("Errors")]:
		var label := Label.new()
		label.text = header
		label.add_theme_color_override(&"font_color", AgentTheme.MUTED)
		_metrics_grid.add_child(label)
	for row: Dictionary in rows:
		for text: String in [str(row.source), "%.1f ms" % row.p50, "%.1f ms" % row.p95, str(row.shown),
				"%d (%.0f %%)" % [row.accepted, float(row.acceptance) * 100.0], str(row.errors)]:
			var label := Label.new()
			label.text = text
			_metrics_grid.add_child(label)


# --- perfiles LLM --------------------------------------------------------------------------------

func profiles() -> Array[LlmProfile]:
	return _profiles


func _rebuild_profiles() -> void:
	for child: Node in _profile_list.get_children():
		child.queue_free()
	if _profiles.is_empty():
		_profile_list.add_child(_hint(I18n.t("No profiles: completion is local only.")))
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
		var tags := PackedStringArray([profile.display_name, profile.model if not profile.model.is_empty() else I18n.t("(no model)")])
		if profile.id == _active_id:
			tags.append(I18n.t("active"))
		if profile.is_experimental():
			tags.append(I18n.t("experimental"))
		name_label.text = " · ".join(tags)
		info.add_child(name_label)
		var url := Label.new()
		url.text = I18n.t("%s · key in $%s") % [profile.url, profile.api_key_env] if not profile.api_key_env.is_empty() else profile.url
		url.clip_text = true
		url.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		url.add_theme_font_override(&"font", AgentTheme.mono_font())
		url.add_theme_color_override(&"font_color", AgentTheme.MUTED)
		info.add_child(url)
		if profile.is_remote():
			var warning := _hint(I18n.t("Remote: the project code around the cursor is sent to %s.") % profile.url.trim_prefix("https://").trim_prefix("http://").get_slice("/", 0))
			warning.add_theme_color_override(&"font_color", AgentTheme.WARNING)
			info.add_child(warning)
		for action: Array in [[I18n.t("Set active"), _make_active], [I18n.t("Edit"), _edit_profile], [I18n.t("Remove"), _remove_profile]]:
			if action[1] == _make_active and profile.id == _active_id:
				continue
			var button := Button.new()
			button.text = action[0]
			button.flat = true
			button.pressed.connect((action[1] as Callable).bind(i))
			row.add_child(button)
		_profile_list.add_child(card)


func _edit_profile(index: int) -> void:
	if _form.visible and _editing >= 0 and _editing != index:
		apply_form()
	_editing = index
	var profile := _profiles[index]
	for key: String in ["id", "display_name", "url", "model", "api_key_env", "fim_template"]:
		(_form_fields[key] as LineEdit).text = str(profile.get(key))
	var stops := PackedStringArray()
	for stop: String in profile.stops:
		stops.append(stop.c_escape())
	(_form_fields.stops as TextEdit).text = "\n".join(stops)
	(_form_fields.temperature as SpinBox).value = profile.temperature
	(_form_fields.max_tokens as SpinBox).value = profile.max_tokens
	_form_warning.text = I18n.t("Experimental: Gemini has no FIM, so the code is requested with an instruction; it's slower and less accurate.") if profile.is_experimental() else ""
	_form.visible = true
	_rebuild_profiles()


func apply_form() -> void:
	if _editing < 0 or _editing >= _profiles.size():
		_form.visible = false
		return
	var profile := _profiles[_editing]
	var was_active := profile.id == _active_id
	profile.id = (_form_fields.id as LineEdit).text.strip_edges()
	profile.display_name = (_form_fields.display_name as LineEdit).text.strip_edges()
	profile.url = (_form_fields.url as LineEdit).text.strip_edges()
	profile.model = (_form_fields.model as LineEdit).text.strip_edges()
	profile.api_key_env = (_form_fields.api_key_env as LineEdit).text.strip_edges().trim_prefix("$")
	profile.fim_template = (_form_fields.fim_template as LineEdit).text
	profile.stops = PackedStringArray()
	for line: String in (_form_fields.stops as TextEdit).text.split("\n", false):
		if not line.is_empty():
			profile.stops.append(line.c_unescape())
	profile.temperature = (_form_fields.temperature as SpinBox).value
	profile.max_tokens = int((_form_fields.max_tokens as SpinBox).value)
	if was_active or _active_id.is_empty():
		_active_id = profile.id
	_editing = -1
	_form.visible = false
	_rebuild_profiles()


func _make_active(index: int) -> void:
	_active_id = _profiles[index].id
	_rebuild_profiles()


func _remove_profile(index: int) -> void:
	var removed := _profiles[index]
	_profiles.remove_at(index)
	if removed.id == _active_id:
		_active_id = _profiles[0].id if not _profiles.is_empty() else ""
	if _editing == index:
		_editing = -1
		_form.visible = false
	elif _editing > index:
		_editing -= 1
	_rebuild_profiles()


func _free_id(base: String) -> String:
	var used: Dictionary = {}
	for profile: LlmProfile in _profiles:
		used[profile.id] = true
	if not used.has(base):
		return base
	var i := 2
	while used.has("%s-%d" % [base, i]):
		i += 1
	return "%s-%d" % [base, i]


## Un nombre de variable válido que parece una key (largo, con minúsculas y dígitos): `AIzaSy…`.
static func _looks_like_key(text: String) -> bool:
	return text.length() >= 20 and text.to_upper() != text and text.to_lower() != text and RegEx.create_from_string("[0-9]").search(text) != null


# --- auxiliares ----------------------------------------------------------------------------------

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


func _check(text: String) -> CheckBox:
	var check := CheckBox.new()
	check.text = text
	add_child(check)
	return check


func _option_row(text: String, items: PackedStringArray) -> OptionButton:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = text
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	var option := OptionButton.new()
	for item: String in items:  # etiquetas de constantes, en inglés
		option.add_item(I18n.t(item))
	row.add_child(option)
	add_child(row)
	return option


func _spin(min_value: float, max_value: float, step: float, suffix: String) -> SpinBox:
	var spin := SpinBox.new()
	spin.min_value = min_value
	spin.max_value = max_value
	spin.step = step
	spin.suffix = suffix
	spin.custom_minimum_size.x = AgentTheme.px(140)
	return spin


func _spin_row(text: String, min_value: float, max_value: float, step: float, suffix: String) -> SpinBox:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = text
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	var spin := _spin(min_value, max_value, step, suffix)
	row.add_child(spin)
	add_child(row)
	return spin


func _text_edit(attach: bool = true) -> TextEdit:
	var text := TextEdit.new()
	text.custom_minimum_size.y = AgentTheme.px(60)
	text.add_theme_font_override(&"font", AgentTheme.mono_font())
	if attach:
		add_child(text)
	return text


static func _lines(text: String) -> PackedStringArray:
	var result: PackedStringArray = []
	for line: String in text.split("\n"):
		if not line.strip_edges().is_empty():
			result.append(line.strip_edges())
	return result
