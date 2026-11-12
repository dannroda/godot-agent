@tool
extends RefCounted
## Carpetas del proyecto con contenido que escribe y comparte el usuario (recetas, m11-30; tools del
## proyecto, m11-46): visibles, versionables y configurables en Settings. Las mismas reglas para todas.

const PROTECTED_PREFIX := "addons/godot_agent"


## La carpeta como ruta res:// limpia, o "" si no sirve: vacía, la raíz, con «..», escondida (empieza
## con «.», como .godot o .godot_agent) o dentro del addon (se reemplaza al actualizar).
static func normalize(value: String) -> String:
	var path := value.strip_edges().trim_prefix("res://")
	while path.begins_with("/"):
		path = path.substr(1)
	while path.ends_with("/"):
		path = path.left(-1)
	if path.is_empty() or path.begins_with(".") or path.begins_with(PROTECTED_PREFIX):
		return ""
	if ".." in path.split("/"):
		return ""
	return ("res://" + path).simplify_path()


## La carpeta configurada o, si no sirve, `default`.
static func resolve(configured: String, default: String) -> String:
	var dir := normalize(configured)
	return default if dir.is_empty() else dir
