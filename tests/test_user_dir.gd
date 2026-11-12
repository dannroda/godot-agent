extends RefCounted
## user:// propio de cada checkout para los tests (m13-17).
##
## Godot resuelve user:// a ~/.local/share/godot/app_userdata/<nombre del proyecto>: la misma carpeta
## para el checkout principal y para todos sus worktrees. Dos suites corriendo a la vez (dos
## sesiones, dos ramas) se pisaban los repos temporales, los checkpoints y el historial, y daban
## fallos falsos de cuota y recuperación. Cada punto de entrada de los tests (run_all, los checks
## headless, el agente falso y el plugin de dev cuando corre un check en el editor) llama a `apply()`
## antes de tocar user://: desde ahí, todo el proceso usa
## <carpeta por defecto>/checkouts/<md5 de res://>-<major.minor de Godot>/. Los procesos hijos del
## mismo checkout (el agente falso, su login) calculan la misma carpeta, así los marcadores que
## comparten siguen funcionando. Fuera de los tests nada cambia.

const SUBDIR := "checkouts"
const SETTING_ENABLED := "application/config/use_custom_user_dir"
const SETTING_NAME := "application/config/custom_user_dir_name"


## Redirige user:// a la carpeta del checkout y devuelve su ruta absoluta. Llamarla otra vez (o con
## la redirección ya hecha por el proceso) no cambia nada.
static func apply() -> String:
	if bool(ProjectSettings.get_setting(SETTING_ENABLED, false)):
		return OS.get_user_data_dir()
	var default_dir := OS.get_user_data_dir()
	var data_dir := OS.get_data_dir()
	# El nombre custom es relativo a la carpeta de datos (~/.local/share): se conserva el camino por
	# defecto (godot/app_userdata/<nombre>) y se agrega la subcarpeta del checkout.
	var relative := default_dir.trim_prefix(data_dir).trim_prefix("/") if default_dir.begins_with(data_dir) else "godot/app_userdata/%s" % str(ProjectSettings.get_setting("application/config/name", "godot_agent"))
	var custom := "%s/%s/%s" % [relative, SUBDIR, checkout_tag()]
	for setting: String in [SETTING_ENABLED, SETTING_NAME]:
		var value: Variant = true if setting == SETTING_ENABLED else custom
		ProjectSettings.set_setting(setting, value)
		# Como valor inicial, ProjectSettings.save() no lo escribe: algunos checks del editor guardan
		# project.godot (el autoload de playtest, los argumentos del play) y no tiene que quedar ahí.
		ProjectSettings.set_initial_value(setting, value)
	# Godot crea user:// al arrancar, antes de la redirección: la carpeta del checkout no existe hasta
	# que alguien escribe con make_dir. Sin ella, un FileAccess.open directo en user:// falla (la copia
	# que valida SceneRevert en el editor de un worktree nuevo).
	DirAccess.make_dir_recursive_absolute(OS.get_user_data_dir())
	return OS.get_user_data_dir()


## Nombre de la subcarpeta: md5 de la ruta del checkout y la versión de Godot (4.7 y 4.8 sobre el
## mismo checkout tampoco se pisan).
static func checkout_tag() -> String:
	var version: Dictionary = Engine.get_version_info()
	return "%s-%d.%d" % [ProjectSettings.globalize_path("res://").md5_text().left(8), int(version.major), int(version.minor)]
