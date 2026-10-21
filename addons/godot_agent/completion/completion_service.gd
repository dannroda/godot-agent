@tool
extends Node
## Completado predictivo en el Script Editor (spec §16): un CompletionController por CodeEdit de
## script, el ProjectContext compartido y el proveedor local. No usa ACP ni el agente; comparte
## Settings y el Agent Log (canal `cmp`, sin contenido de código).

const AgentLog := preload("../core/agent_log.gd")
const HarnessSettings := preload("../core/harness_settings.gd")
const ProjectConfig := preload("../config/project_config.gd")
const ProjectContext := preload("project_context.gd")
const LocalProvider := preload("local/local_provider.gd")
const CompletionController := preload("completion_controller.gd")
const CompletionResult := preload("completion_result.gd")

const COMMENT_COLOR_SETTING := "text_editor/theme/highlighting/comment_color"

var context: ProjectContext = ProjectContext.new()
var provider: LocalProvider = LocalProvider.new(context)
var _settings: HarnessSettings
var _config: ProjectConfig
var _log: AgentLog
## CodeEdit -> CompletionController
var _controllers: Dictionary = {}
var _indexing: bool = false


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
		controller.detach()
	_controllers.clear()
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
			controller.detach()
			_controllers.erase(code_edit)


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
	for controller: CompletionController in _controllers.values():
		controller.enabled = enabled
		controller.debounce_ms = _settings.completion_debounce_ms() if _settings else controller.debounce_ms
		controller.renderer.color = Color(color, color.a * CompletionController.GhostTextRenderer.DEFAULT_ALPHA)
		controller.cache.clear()  # otra configuración, otras sugerencias
		if not enabled:
			controller.dismiss("off")


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


## Métricas sin contenido de código (spec §16.8).
func _on_shown(result: CompletionResult) -> void:
	if _log:
		_log.add(AgentLog.CH_CMP, "shown %s %.2f ms score %.2f out %d líneas %d caché %s" % [
			result.source, result.latency_usec / 1000.0, result.score, result.text.length(), result.text.count("\n") + 1, "hit" if result.cached else "miss"])


func _on_accepted_partial(result: CompletionResult) -> void:
	if _log and result:
		_log.add(AgentLog.CH_CMP, "accepted_partial %s" % result.source)


func _on_finished(result: CompletionResult, outcome: String) -> void:
	if _log and result:
		_log.add(AgentLog.CH_CMP, "%s %s" % [outcome, result.source])
