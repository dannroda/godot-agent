@tool
extends EditorExportPlugin
## Garantiza que nada del addon llegue a un juego exportado (spec §2).

const PlaytestAutoload := preload("../playtest/playtest_autoload.gd")
const ExportPresetsPatcher := preload("export_presets_patcher.gd")

const ADDON_DIR := "res://addons/godot_agent/"
## Spec, progreso e informes del One-shot (D41). Su .gdignore ya los deja afuera; esto es por las dudas.
const ONESHOT_FILES_DIR := "res://.godot_agent/"

## Quita el autoload de playtest; lo inyecta el plugin (remove_autoload_singleton es de EditorPlugin).
var _remove_playtest_autoload: Callable


func setup(remove_playtest_autoload: Callable) -> void:
	_remove_playtest_autoload = remove_playtest_autoload


## El editor ordena los export plugins por nombre y, por archivo, corta la cadena en el primero que
## hace skip() o remap. El plugin de GDScript ("GDScript") remapea .gd → .gdc, así que este nombre
## tiene que ordenar antes que él para que skip() llegue a los scripts (docs/decisions.md, D10).
func _get_name() -> String:
	return "!GodotAgentExcludeAddon"


func _export_begin(_features: PackedStringArray, _is_debug: bool, _path: String, _flags: int) -> void:
	if PlaytestAutoload.is_registered():
		push_error(
			"Godot Agent: el autoload de playtest '%s' seguía registrado al exportar (¿un playtest quedó abierto?). Se quitó antes de generar el export."
			% PlaytestAutoload.NAME
		)
		if _remove_playtest_autoload.is_valid():
			_remove_playtest_autoload.call()
	var missing := ExportPresetsPatcher.presets_missing_filter()
	if not missing.is_empty():
		push_warning(
			"Godot Agent: los presets %s no excluyen '%s'. Si exportás con el plugin deshabilitado, el addon se incluiría. Usá \"Agregar a los presets\" en el dock Agent."
			% [", ".join(missing), ExportPresetsPatcher.FILTER]
		)


func _export_file(path: String, _type: String, _features: PackedStringArray) -> void:
	if path.begins_with(ADDON_DIR) or path.begins_with(ONESHOT_FILES_DIR):
		skip()
