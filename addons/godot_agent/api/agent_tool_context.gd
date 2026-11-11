@tool
extends RefCounted
## Lo que recibe `_run(args, ctx)` de una tool del proyecto (m11-46).

## El UndoRedo del editor: lo que la tool cambie por acá, el usuario lo deshace con Ctrl+Z. null fuera
## del editor (los tests).
var undo_redo: EditorUndoRedoManager
## La carpeta del proyecto, absoluta.
var project_dir: String = ""
## Nombre de la tool que corre.
var tool_name: String = ""
var _log: Callable


## Una línea en el log del harness (canal MCP), con el nombre de la tool.
func note(text: String) -> void:
	if _log.is_valid():
		_log.call("godot.%s: %s" % [tool_name, text])
