extends RefCounted
## m16-11: los gamepads reales de la máquina, fuera de los juegos que maneja el agente.
## Godot (SDL) lee los joysticks de todo el sistema, sin importar qué ventana tiene el foco, y los lee
## también en headless. Un stick apoyado o con drift deja apretado ui_up/ui_left…:
## - el LineEdit que toma el foco con una flecha apretada no entra a editar, y lo que el agente tipea
##   no llega;
## - el movimiento del joystick mueve el foco de la UI a otro control;
## - el personaje camina solo.
## El agente cree que su input falló. Con esta variable SDL no abre ningún gamepad. Los eventos de
## joystick que manda el agente (Input.parse_input_event) no pasan por SDL y siguen andando.
## Solo tiene efecto en un proceso que arranca con ella: hay que ponerla antes de lanzarlo.

const ENV := "SDL_GAMECONTROLLER_IGNORE_DEVICES_EXCEPT"
## Una lista de excepciones con un VID/PID que no existe: no queda ninguno.
const NONE := "0x0000/0x0000"


## Los procesos que se lancen desde ahora ignoran los gamepads reales. Devuelve lo que había, para restore().
static func ignore_in_children() -> Variant:
	var previous: Variant = OS.get_environment(ENV) if OS.has_environment(ENV) else null
	OS.set_environment(ENV, NONE)
	return previous


static func restore(previous: Variant) -> void:
	if previous == null:
		OS.unset_environment(ENV)
	else:
		OS.set_environment(ENV, str(previous))


## Para un script headless (run_all, regression_cli) con un gamepad real conectado: se relanza a sí
## mismo sin ellos, con la misma salida, y devuelve su código de salida. -1 si no hacía falta o no pudo.
static func relaunch_without(tree: SceneTree, script_path: String) -> int:
	if Input.get_connected_joypads().is_empty() or OS.get_environment(ENV) == NONE:
		return -1
	var args := PackedStringArray()
	if DisplayServer.get_name() == "headless":
		args.append("--headless")
	args.append_array(["--path", ProjectSettings.globalize_path("res://"), "--script", script_path])
	var user_args := OS.get_cmdline_user_args()
	if not user_args.is_empty():
		args.append("--")
		args.append_array(user_args)
	var previous: Variant = ignore_in_children()
	var pid := OS.create_process(OS.get_executable_path(), args)
	restore(previous)
	if pid <= 0:
		return -1
	print("(%s: relaunched without the real gamepads, %s=%s)" % [script_path.get_file(), ENV, NONE])
	while OS.is_process_running(pid):
		await tree.create_timer(0.1).timeout
	return OS.get_process_exit_code(pid)
