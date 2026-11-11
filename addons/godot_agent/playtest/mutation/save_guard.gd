@tool
extends ResourceFormatSaver
## Guardia del runner con mutantes (m11-41): el script mutado vive solo en memoria y nada de esa
## corrida puede llegar a disco por ResourceSaver. Registrada primera, reconoce cualquier recurso y
## extensión, no escribe nada y termina el proceso con EXIT_CODE. Devuelve OK a propósito: con un
## error, ResourceSaver prueba el saver siguiente y el archivo se escribe igual.

const EXIT_CODE := 4

## Lo que se intentó guardar (para los tests).
var attempts: PackedStringArray = []


func _recognize(_resource: Resource) -> bool:
	return true


func _recognize_path(_resource: Resource, _path: String) -> bool:
	return true


func _get_recognized_extensions(_resource: Resource) -> PackedStringArray:
	return PackedStringArray(["tres", "res", "tscn", "scn", "gd", "gdshader", "json", "cfg", "import", "material", "theme", "anim", "mesh"])


func _save(_resource: Resource, path: String, _flags: int) -> Error:
	attempts.append(path)
	printerr("regressions: a mutant run tried to save %s: refused, aborting" % path)
	var tree := Engine.get_main_loop() as SceneTree
	if tree and not Engine.has_meta(&"godot_agent_save_guard_test"):
		tree.quit(EXIT_CODE)
	return OK
