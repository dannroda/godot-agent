@tool
extends EditorPlugin
## Raíz de composición del addon: crea los servicios y la UI, y los desarma al deshabilitar.

const AgentExportPlugin := preload("export/agent_export_plugin.gd")
const PlaytestAutoload := preload("playtest/playtest_autoload.gd")
const EditorSurfaces := preload("ui/editor_surfaces.gd")
const AgentDockScene := preload("ui/dock/agent_dock.tscn")
const AgentMainScreenScene := preload("ui/main_screen/agent_main_screen.tscn")
const AgentLogPanelScene := preload("ui/log_panel/agent_log_panel.tscn")

const PLUGIN_NAME := "Agent"
const DOCK_TITLE := "Agent"
const LOG_PANEL_TITLE := "Agent Log"
const ICON_NAME := &"Script"

var _export_plugin: AgentExportPlugin
var _surfaces: EditorSurfaces


func _enter_tree() -> void:
	PlaytestAutoload.remove_orphan(self)

	_export_plugin = AgentExportPlugin.new()
	_export_plugin.setup(_remove_playtest_autoload)
	add_export_plugin(_export_plugin)

	_surfaces = EditorSurfaces.new(self)
	_surfaces.add(EditorSurfaces.Surface.SIDE, AgentDockScene.instantiate(), DOCK_TITLE, "godot_agent_dock")
	_surfaces.add(EditorSurfaces.Surface.BOTTOM, AgentLogPanelScene.instantiate(), LOG_PANEL_TITLE, "godot_agent_log")
	_surfaces.add(
		EditorSurfaces.Surface.MAIN_SCREEN, AgentMainScreenScene.instantiate(), PLUGIN_NAME, "godot_agent_main", _get_plugin_icon()
	)


func _exit_tree() -> void:
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


func _remove_playtest_autoload() -> void:
	PlaytestAutoload.unregister(self)
