@tool
extends EditorPlugin
## Raíz de composición del addon: crea los servicios y la UI, y los desarma al deshabilitar.

const AgentExportPlugin := preload("export/agent_export_plugin.gd")
const PlaytestAutoload := preload("playtest/playtest_autoload.gd")
const EditorSurfaces := preload("ui/editor_surfaces.gd")
const AgentDockScene := preload("ui/dock/agent_dock.tscn")
const AgentMainScreenScene := preload("ui/main_screen/agent_main_screen.tscn")
const AgentLogPanelScene := preload("ui/log_panel/agent_log_panel.tscn")
const AgentLog := preload("core/agent_log.gd")
const HarnessSettings := preload("core/harness_settings.gd")
const SessionModel := preload("session/session_model.gd")
const SessionController := preload("session/session_controller.gd")
const EditorContext := preload("ui/editor_context.gd")

const PLUGIN_NAME := "Agent"
const DOCK_TITLE := "Agent"
const LOG_PANEL_TITLE := "Agent Log"
const ICON_NAME := &"Script"

var _export_plugin: AgentExportPlugin
var _surfaces: EditorSurfaces
var _settings: HarnessSettings
var _log: AgentLog
var _model: SessionModel
var _controller: SessionController


func _enter_tree() -> void:
	PlaytestAutoload.remove_orphan(self)

	_export_plugin = AgentExportPlugin.new()
	_export_plugin.setup(_remove_playtest_autoload)
	add_export_plugin(_export_plugin)

	_settings = HarnessSettings.new(EditorInterface.get_editor_settings())
	_log = AgentLog.new()
	_model = SessionModel.new()
	_controller = SessionController.new()
	_controller.setup(_model, _log, EditorContext.project_path())
	_controller.prompt_variables_provider = _prompt_variables

	var dock := AgentDockScene.instantiate()
	dock.setup(_model, _controller, _settings)
	dock.show_log_requested.connect(_show_log)
	var log_panel := AgentLogPanelScene.instantiate()
	log_panel.setup(_log)

	_surfaces = EditorSurfaces.new(self)
	_surfaces.add(EditorSurfaces.Surface.SIDE, dock, DOCK_TITLE, "godot_agent_dock")
	_surfaces.add(EditorSurfaces.Surface.BOTTOM, log_panel, LOG_PANEL_TITLE, "godot_agent_log")
	_surfaces.add(
		EditorSurfaces.Surface.MAIN_SCREEN, AgentMainScreenScene.instantiate(), PLUGIN_NAME, "godot_agent_main", _get_plugin_icon()
	)


func _exit_tree() -> void:
	if _controller:
		_controller.stop()
		_controller = null
	PlaytestAutoload.unregister(self)

	if _export_plugin:
		remove_export_plugin(_export_plugin)
		_export_plugin = null

	if _surfaces:
		_surfaces.remove_all()
		_surfaces = null


## Solo con la API vieja (4.4–4.7). En 4.8+ la main screen es un EditorDock (ver EditorSurfaces).
func _has_main_screen() -> bool:
	return not EditorSurfaces.uses_dock_api(EditorSurfaces.Surface.MAIN_SCREEN)


func _make_visible(visible: bool) -> void:
	if _surfaces:
		_surfaces.set_legacy_main_screen_visible(visible)


func _get_plugin_name() -> String:
	return PLUGIN_NAME


func _get_plugin_icon() -> Texture2D:
	return EditorInterface.get_editor_theme().get_icon(ICON_NAME, &"EditorIcons")


func _show_log() -> void:
	if _surfaces:
		_surfaces.make_visible(EditorSurfaces.Surface.BOTTOM)


func _prompt_variables() -> Dictionary:
	return {
		"project_name": str(ProjectSettings.get_setting("application/config/name", "")),
		"project_path": EditorContext.project_path(),
		"godot_version": Engine.get_version_info().string,
	}


func _remove_playtest_autoload() -> void:
	PlaytestAutoload.unregister(self)
