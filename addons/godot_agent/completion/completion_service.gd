@tool
extends Node
## Completado predictivo en el Script Editor (spec §16): un CompletionController por CodeEdit de
## script, el ProjectContext compartido, el proveedor local y (M8c) un LlmProvider por editor según
## el modo. No usa ACP ni el agente; comparte Settings y el Agent Log (canal `cmp`, sin contenido de
## código salvo `completion/log_raw`). Indicador en la barra del Script Editor y atajo de on/off.

const AgentLog := preload("../core/agent_log.gd")
const HarnessSettings := preload("../core/harness_settings.gd")
const ProjectConfig := preload("../config/project_config.gd")
const ProjectContext := preload("project_context.gd")
const LocalProvider := preload("local/local_provider.gd")
const CompletionController := preload("completion_controller.gd")
const CompletionResult := preload("completion_result.gd")
const CompletionMetrics := preload("completion_metrics.gd")
const CompletionIndicator := preload("completion_indicator.gd")
const LlmProvider := preload("llm/llm_provider.gd")
const LlmProfile := preload("llm/llm_profile.gd")

const COMMENT_COLOR_SETTING := "text_editor/theme/highlighting/comment_color"
## Cada cuántas sugerencias mostradas se loguea el resumen de latencias por fuente.
const METRICS_LOG_EVERY := 10
const TOGGLE_SHORTCUT_TEXT := "Alt+Shift+\\"

var context: ProjectContext = ProjectContext.new()
var provider: LocalProvider = LocalProvider.new(context)
var _settings: HarnessSettings
var _config: ProjectConfig
var _log: AgentLog
## CodeEdit -> CompletionController
var _controllers: Dictionary = {}
## CompletionController -> LlmProvider (cada editor con su HTTPRequest).
var _llm_providers: Dictionary = {}
var _indexing: bool = false
var metrics: CompletionMetrics = CompletionMetrics.new()
var indicator: CompletionIndicator
var _shown_count: int = 0
var _llm_error: String = ""
var _llm_busy_count: int = 0


func setup(settings: HarnessSettings, config: ProjectConfig, agent_log: AgentLog) -> void:
	_settings = settings
	_config = config
	_log = agent_log


func _ready() -> void:
	context.exclude = _config.completion_exclude if _config else PackedStringArray()
	context.live_scene_provider = EditorInterface.get_edited_scene_root
	context.indexed.connect(_on_indexed)
	apply_settings()
	var script_editor := EditorInterface.get_script_editor()
	script_editor.editor_script_changed.connect(_on_editor_script_changed)
	var filesystem := EditorInterface.get_resource_filesystem()
	filesystem.filesystem_changed.connect(_on_filesystem_changed)
	filesystem.resources_reimported.connect(_on_resources_reimported)
	ProjectSettings.settings_changed.connect(context.settings_changed)
	indicator = CompletionIndicator.new()
	indicator.shortcut_text = TOGGLE_SHORTCUT_TEXT
	indicator.toggle_requested.connect(toggle_enabled)
	var bar := CompletionIndicator.menu_bar(script_editor)
	if bar:
		bar.add_child(indicator)
	_refresh_indicator()
	_attach_current.call_deferred()


func _exit_tree() -> void:
	var script_editor := EditorInterface.get_script_editor()
	if script_editor.editor_script_changed.is_connected(_on_editor_script_changed):
		script_editor.editor_script_changed.disconnect(_on_editor_script_changed)
	var filesystem := EditorInterface.get_resource_filesystem()
	if filesystem.filesystem_changed.is_connected(_on_filesystem_changed):
		filesystem.filesystem_changed.disconnect(_on_filesystem_changed)
	if filesystem.resources_reimported.is_connected(_on_resources_reimported):
		filesystem.resources_reimported.disconnect(_on_resources_reimported)
	if ProjectSettings.settings_changed.is_connected(context.settings_changed):
		ProjectSettings.settings_changed.disconnect(context.settings_changed)
	for controller: CompletionController in _controllers.values():
		_release(controller)
	_controllers.clear()
	if indicator and is_instance_valid(indicator):
		indicator.queue_free()
	indicator = null
	context.wait()


## Los controllers de CodeEdits liberados (pestaña cerrada) se sueltan acá: `tree_exiting` también
## llega cuando el Script Editor se hace flotante y el CodeEdit solo cambia de padre.
func _process(_delta: float) -> void:
	context.poll()
	var now := Time.get_ticks_msec()
	for code_edit: Variant in _controllers.keys():
		var controller: CompletionController = _controllers[code_edit]
		if is_instance_valid(code_edit) and controller.code_edit == code_edit:
			controller.tick(now)
		else:
			context.drop_buffer(controller.path)
			_release(controller)
			_controllers.erase(code_edit)


## Atajo global de on/off (Alt+Shift+\): antes que el CodeEdit, desde cualquier pantalla.
func _input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key and key.pressed and not key.echo and key.keycode == KEY_BACKSLASH and key.alt_pressed and key.shift_pressed and not (key.ctrl_pressed or key.meta_pressed):
		get_viewport().set_input_as_handled()
		toggle_enabled()


func toggle_enabled() -> void:
	if _settings:
		_settings.set_value(HarnessSettings.KEY_COMPLETION_ENABLED, not _settings.completion_enabled())
	apply_settings()
	if _log:
		_log.add(AgentLog.CH_CMP, "completado %s" % ("prendido" if is_enabled() else "apagado"))


func _release(controller: CompletionController) -> void:
	controller.detach()
	var llm: LlmProvider = _llm_providers.get(controller)
	if llm:
		llm.release()
	_llm_providers.erase(controller)


## Relee Settings de usuario y del proyecto (en caliente).
func apply_settings() -> void:
	var enabled := is_enabled()
	provider.threshold = _settings.completion_threshold() if _settings else provider.threshold
	provider.margin = _settings.completion_margin() if _settings else provider.margin
	if _settings:
		provider.max_lines = _settings.completion_max_lines()
		provider.sources = _settings.completion_sources()
		var extra := _settings.completion_extra_corpus()
		if extra != context.extra_corpus:
			context.extra_corpus = extra
			context.request_refresh()
	if _config and context.exclude != _config.completion_exclude:
		context.exclude = _config.completion_exclude
		context.request_refresh()
	# Apagado no indexa; al prenderlo arranca el primer build.
	_indexing = enabled
	if enabled and not context.has_built() and not context.is_building():
		context.start_build()
	var color := Color(EditorInterface.get_editor_settings().get_setting(COMMENT_COLOR_SETTING))
	var mode := _settings.completion_mode() if _settings else CompletionController.MODE_LOCAL
	var profile: LlmProfile = _settings.active_llm_profile() if _settings else null
	for controller: CompletionController in _controllers.values():
		controller.enabled = enabled
		controller.debounce_ms = _settings.completion_debounce_ms() if _settings else controller.debounce_ms
		controller.renderer.color = Color(color, color.a * CompletionController.GhostTextRenderer.DEFAULT_ALPHA)
		controller.cache.clear()  # otra configuración, otras sugerencias
		_configure_llm(controller, mode, profile)
		if not enabled:
			controller.dismiss("off")
	_llm_error = ""
	_refresh_indicator()


## Modo y proveedor LLM de un editor, en caliente: cambiar de modo o de perfil no pide reiniciar.
func _configure_llm(controller: CompletionController, mode: String, profile: LlmProfile) -> void:
	controller.dismiss("settings")
	controller.mode = mode if profile else CompletionController.MODE_LOCAL
	if controller.mode == CompletionController.MODE_LOCAL:
		controller.llm_provider = null
		return
	var llm: LlmProvider = _llm_providers.get(controller)
	if llm == null:
		llm = LlmProvider.new(self, profile, context)
		_llm_providers[controller] = llm
	llm.profile = profile
	if _settings:
		llm.prefix_chars = _settings.llm_prefix_chars()
		llm.suffix_chars = _settings.llm_suffix_chars()
		llm.context_budget = _settings.llm_context_tokens()
		llm.max_lines = _settings.completion_max_lines()
		controller.llm_debounce_ms = _settings.llm_debounce_ms()
		controller.llm_marker = _settings.llm_marker()
	controller.llm_provider = llm


## Estado y modo para el indicador del Script Editor.
func _refresh_indicator() -> void:
	if indicator == null:
		return
	var mode := _settings.completion_mode() if _settings else CompletionController.MODE_LOCAL
	var profile: LlmProfile = _settings.active_llm_profile() if _settings else null
	var label := "local"
	if mode != CompletionController.MODE_LOCAL and profile:
		label = "%s · %s" % ["híbrido" if mode == CompletionController.MODE_HYBRID else "LLM", profile.model if not profile.model.is_empty() else profile.kind]
	var state := CompletionIndicator.State.ACTIVE
	if not is_enabled():
		state = CompletionIndicator.State.OFF
	elif _llm_busy_count > 0:
		state = CompletionIndicator.State.THINKING
	elif not _llm_error.is_empty():
		state = CompletionIndicator.State.ERROR
	indicator.set_state(state, label, _llm_error)


func is_enabled() -> bool:
	return (_settings == null or _settings.completion_enabled()) and (_config == null or _config.completion_enabled)


## Controller del CodeEdit que muestra `path` (tests), o null.
func controller_for(path: String) -> CompletionController:
	for controller: CompletionController in _controllers.values():
		if controller.path == path and is_instance_valid(controller.code_edit):
			return controller
	return null


func _on_editor_script_changed(_script: Script) -> void:
	_attach_current.call_deferred()


func _attach_current() -> void:
	var script_editor := EditorInterface.get_script_editor()
	var current := script_editor.get_current_editor()
	var script := script_editor.get_current_script()
	if current == null or script == null:
		return
	var code_edit := current.get_base_editor() as CodeEdit
	if code_edit == null:
		return
	var controller: CompletionController = _controllers.get(code_edit)
	if controller and controller.code_edit != code_edit:
		_release(controller)
		_controllers.erase(code_edit)  # otro CodeEdit en la misma dirección de memoria
		controller = null
	if controller == null:
		controller = CompletionController.new()
		controller.provider = provider
		controller.history = provider.history
		controller.shown.connect(_on_shown)
		controller.finished.connect(_on_finished)
		controller.accepted_partial.connect(_on_accepted_partial)
		controller.buffer_idle.connect(_on_buffer_idle)
		controller.llm_started.connect(_on_llm_started)
		controller.llm_finished.connect(_on_llm_finished.bind(controller))
		controller.attach(code_edit, script.resource_path)
		_controllers[code_edit] = controller
		apply_settings()
	else:
		controller.path = script.resource_path


func _on_filesystem_changed() -> void:
	if _indexing:
		context.request_refresh()


func _on_resources_reimported(_resources: PackedStringArray) -> void:
	if _indexing:
		context.request_refresh()


func _on_buffer_idle(path: String, text: String, caret_line: int) -> void:
	if _indexing:
		context.update_buffer(path, text, caret_line)


func _on_indexed(build_usec: int) -> void:
	for controller: CompletionController in _controllers.values():
		controller.cache.clear()
	if _log:
		_log.add(AgentLog.CH_CMP, "índice: %d scripts, %d escenas, %d líneas únicas, %d tokens en %.0f ms" % [
			context.index.scripts.size(), context.index.scenes.size(), context.lines().size(), context.ngram().token_count, build_usec / 1000.0])


## Métricas sin contenido de código (spec §16.8), salvo con `completion/log_raw`.
func _on_shown(result: CompletionResult) -> void:
	metrics.record(result.source, "shown")
	if not result.cached and result.source != CompletionResult.SOURCE_LLM:
		metrics.record_latency(result.source, result.latency_usec / 1000.0)  # la del LLM, al terminar
	_shown_count += 1
	if _log:
		_log.add(AgentLog.CH_CMP, "shown %s %.2f ms score %.2f out %d líneas %d caché %s%s" % [
			result.source, result.latency_usec / 1000.0, result.score, result.text.length(), result.text.count("\n") + 1,
			"hit" if result.cached else "miss", _raw(result)])
		if _shown_count % METRICS_LOG_EVERY == 0:
			_log.add(AgentLog.CH_CMP, "latencias: " + metrics.format_line())


func _on_accepted_partial(result: CompletionResult) -> void:
	if result:
		metrics.record(result.source, "partial")
	if _log and result:
		_log.add(AgentLog.CH_CMP, "accepted_partial %s" % result.source)


func _on_finished(result: CompletionResult, outcome: String) -> void:
	if result and outcome == "accepted":
		metrics.record(result.source, "accepted")
	if _log and result:
		_log.add(AgentLog.CH_CMP, "%s %s" % [outcome, result.source])


func _on_llm_started() -> void:
	_llm_busy_count += 1
	_refresh_indicator()


## Un pedido al LLM terminó: latencia, tamaños (sin código) y estado del indicador.
func _on_llm_finished(state: String, result: CompletionResult, error: String, latency_ms: float, controller: CompletionController) -> void:
	_llm_busy_count = maxi(0, _llm_busy_count - 1)
	var llm: LlmProvider = _llm_providers.get(controller)
	if state == "error":
		_llm_error = error
		metrics.record(CompletionResult.SOURCE_LLM, "errors")
	elif state == "done":
		_llm_error = ""
	if state != "cancelled":
		metrics.record_latency(CompletionResult.SOURCE_LLM, latency_ms)
	if _log:
		var sizes := " in %d out %d" % [llm.last_input_chars, llm.last_output_chars] if llm else ""
		match state:
			"cancelled":
				_log.add(AgentLog.CH_CMP, "llm cancelled")
			"error":
				_log.add(AgentLog.CH_CMP, "llm error %.0f ms: %s" % [latency_ms, error])
			_:
				_log.add(AgentLog.CH_CMP, "llm %s %.0f ms%s" % ["sugerencia" if result else "sin sugerencia", latency_ms, sizes])
	_refresh_indicator()


func _raw(result: CompletionResult) -> String:
	return " «%s»" % result.text.c_escape() if _settings and _settings.completion_log_raw() else ""
