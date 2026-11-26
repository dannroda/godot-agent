@tool
extends RefCounted
## Carpetas del proyecto con contenido que escribe y comparte el usuario (recetas, m11-30; tools del
## proyecto, m11-46): visibles, versionables y configurables en Settings. Las mismas reglas para todas.

const PROTECTED_PREFIX := "addons/godot_agent"

## La carpeta del proyecto cuando no es res:// (m20-13): la app aparte corre con un proyecto propio
## (sin los autoloads del juego) y el del usuario llega por --project. "" en el editor: res://.
static var root: String = ""


## `res://x` del proyecto del usuario como ruta del sistema cuando no es res:// (ver `root`); si no,
## igual. Para leer y escribir lo del usuario (config, modos, recetas, reportes) también fuera del editor.
static func to_fs(path: String) -> String:
	if root.is_empty() or not path.begins_with("res://"):
		return path
	return root.path_join(path.trim_prefix("res://"))


## Como ProjectSettings.globalize_path, pero con el proyecto del usuario aunque no sea res://.
static func globalize(path: String) -> String:
	return ProjectSettings.globalize_path(to_fs(path))


## La carpeta user:// del proyecto de `project_dir`, como la calcula Godot con su project.godot (nombre
## o carpeta propia), para compartir historial y cuotas con el editor desde la app aparte. "" sin
## project.godot.
static func user_dir_of(project_dir: String, data_dir: String = OS.get_data_dir()) -> String:
	var config := ConfigFile.new()
	if config.load(project_dir.path_join("project.godot")) != OK:
		return ""
	var name := str(config.get_value("application", "config/name", ""))
	if bool(config.get_value("application", "config/use_custom_user_dir", false)):
		var custom := str(config.get_value("application", "config/custom_user_dir_name", ""))
		return data_dir.path_join((custom if not custom.is_empty() else name).validate_filename())
	var godot_dir := "godot" if OS.get_name() in ["Linux", "FreeBSD", "NetBSD", "OpenBSD", "BSD"] else "Godot"
	return data_dir.path_join(godot_dir).path_join("app_userdata").path_join(name.validate_filename() if not name.is_empty() else "[unnamed project]")


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
