extends RefCounted
## Lado del juego de las instancias extra de run_scene (m11-50). El harness lanza la instancia N con
## GODOT_AGENT_INSTANCE=N en el entorno; desde la 2, cada una usa su propio user:// para que dos
## clientes no se pisen los saves ni los settings, salvo GODOT_AGENT_SHARED_USER_DIR=1.
## Lo llama el _init del autoload de playtest, que en esas corridas va primero en la lista de autoloads:
## los _init de los autoloads del juego ya ven la carpeta de su instancia.

const ENV_INSTANCE := "GODOT_AGENT_INSTANCE"
const ENV_SHARED_USER_DIR := "GODOT_AGENT_SHARED_USER_DIR"
const SUBDIR := "instances"
const SETTING_ENABLED := "application/config/use_custom_user_dir"
const SETTING_NAME := "application/config/custom_user_dir_name"


## El número de esta instancia: 1 para la que lanza el editor (sin la variable).
static func number() -> int:
	return maxi(1, int(OS.get_environment(ENV_INSTANCE)))


## El nombre custom de user:// de la instancia `n`: relativo a la carpeta de datos, como lo pide
## custom_user_dir_name. "" si la instancia usa el de siempre.
static func custom_dir_name(n: int, default_dir: String, data_dir: String, shared: bool) -> String:
	if n < 2 or shared:
		return ""
	var relative := default_dir.trim_prefix(data_dir).trim_prefix("/") if default_dir.begins_with(data_dir) else default_dir.get_file()
	return "%s/%s/%d" % [relative, SUBDIR, n]


## Redirige user:// para esta instancia, en memoria (no se guarda en project.godot). Un proyecto que
## ya usa un user dir propio lo conserva y suma la subcarpeta de la instancia.
static func apply() -> void:
	var name := custom_dir_name(number(), OS.get_user_data_dir(), OS.get_data_dir(), OS.get_environment(ENV_SHARED_USER_DIR) == "1")
	if name.is_empty():
		return
	ProjectSettings.set_setting(SETTING_NAME, name)
	ProjectSettings.set_setting(SETTING_ENABLED, true)
