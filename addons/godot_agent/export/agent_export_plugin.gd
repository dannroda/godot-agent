@tool
extends EditorExportPlugin
## Garantiza que nada del addon llegue a un juego exportado (spec §2), ni las tools del proyecto que
## lo usan (m11-46), ni las recetas (m11-30), ni los modos del proyecto (m11-39).

const PlaytestAutoload := preload("../playtest/playtest_autoload.gd")
const ExportPresetsPatcher := preload("export_presets_patcher.gd")
const ProjectConfig := preload("../config/project_config.gd")
const ProjectToolLoader := preload("../mcp/project_tool_loader.gd")
const Recipes := preload("../core/recipes.gd")
const ProjectModes := preload("../core/project_modes.gd")

const ADDON_DIR := "res://addons/godot_agent/"
## Spec, progreso e informes del One-shot (D41). Su .gdignore ya los deja afuera; esto es por las dudas.
const ONESHOT_FILES_DIR := "res://.godot_agent/"

## Las tools propias del proyecto (m11-46): extienden un script del addon, así que tampoco van. Se lee
## de la config al empezar cada export ("res://agent_tools/").
var _tools_prefix := ProjectToolLoader.DEFAULT_DIR + "/"
## Las recetas del proyecto (m11-30): pedidos para el agente, no contenido del juego.
var _recipes_prefix := Recipes.DEFAULT_DIR + "/"
## Los modos del proyecto (m11-39): instrucciones para el agente, no contenido del juego.
var _modes_prefix := ProjectModes.DEFAULT_DIR + "/"

## Quita el autoload de playtest; lo inyecta el plugin (remove_autoload_singleton es de EditorPlugin).
var _remove_playtest_autoload: Callable


func setup(remove_playtest_autoload: Callable) -> void:
	_remove_playtest_autoload = remove_playtest_autoload


## El editor ordena los export plugins por nombre y, por archivo, corta la cadena en el primero que
## hace skip() o remap. El plugin de GDScript ("GDScript") remapea .gd → .gdc, así que este nombre
## tiene que ordenar antes que él para que skip() llegue a los scripts (docs/decisions.md, D10).
func _get_name() -> String:
	return "!GodotAgentExcludeAddon"


## Callable(path: String): empieza un export (m11-24, el evento export_started de los hooks).
var on_export_begin: Callable


func _export_begin(_features: PackedStringArray, _is_debug: bool, _path: String, _flags: int) -> void:
	var config := ProjectConfig.load_or_default()
	_tools_prefix = ProjectToolLoader.resolve_dir(str(config.get(&"project_tools_dir"))) + "/"
	_recipes_prefix = Recipes.resolve_dir(str(config.get(&"recipes_dir"))) + "/"
	_modes_prefix = ProjectModes.resolve_dir(str(config.get(&"modes_dir"))) + "/"
	if on_export_begin.is_valid():
		on_export_begin.call(_path)
	if PlaytestAutoload.is_registered():
		push_error(
			"Godot Agent: the playtest autoload '%s' was still registered at export time (was a playtest left open?). It was removed before generating the export."
			% PlaytestAutoload.NAME
		)
		if _remove_playtest_autoload.is_valid():
			_remove_playtest_autoload.call()
	var missing := ExportPresetsPatcher.presets_missing_filter()
	if not missing.is_empty():
		push_warning(
			"Godot Agent: the presets %s do not exclude '%s'. If you export with the plugin disabled, the addon would be included. Use \"Add to the presets\" in the Agent dock."
			% [", ".join(missing), ExportPresetsPatcher.filters_text()]
		)


func _export_file(path: String, _type: String, _features: PackedStringArray) -> void:
	if path.begins_with(ADDON_DIR) or path.begins_with(ONESHOT_FILES_DIR) or path.begins_with(_tools_prefix) or path.begins_with(_recipes_prefix) or path.begins_with(_modes_prefix):
		skip()
