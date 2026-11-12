extends "test_case.gd"
## run_scene con varias instancias (m11-50): la validación de `instances` y el tope, los argumentos de
## cada proceso (--remote-debug, mosaico, headless, los del juego después de --), el entorno, el user://
## de cada instancia y el mapa sesión → instancia del debugger.

const GameInstances := preload("res://addons/godot_agent/playtest/game_instances.gd")
const InstanceEnv := preload("res://addons/godot_agent/playtest/runtime/instance_env.gd")
const DeviceSim := preload("res://addons/godot_agent/playtest/runtime/device_sim.gd")
const RealGamepads := preload("res://addons/godot_agent/playtest/real_gamepads.gd")
const InstanceSessions := preload("res://addons/godot_agent/playtest/instance_sessions.gd")
const PlaytestAutoload := preload("res://addons/godot_agent/playtest/playtest_autoload.gd")

const AREA := Rect2i(0, 0, 1920, 1040)


func test_normalize_and_limit() -> void:
	assert_eq(GameInstances.normalize(null), {"instances": []}, "sin instances, ninguna")
	var ok := GameInstances.normalize([{"args": ["--server", 7000]}, {"headless": true, "device": "phone"}])
	assert_false(ok.has("error"), "dos válidas · %s" % ok.get("error", ""))
	assert_eq(ok.instances[0].args, PackedStringArray(["--server", "7000"]), "args como texto")
	assert_true(ok.instances[1].headless and ok.instances[1].device.name == "phone", "headless y dispositivo")
	assert_true(str(GameInstances.normalize([{}, {}, {}, {}]).get("error", "")).contains("At most 4"), "con la del editor, 5 son demasiadas")
	assert_false(GameInstances.normalize([{}, {}, {}]).has("error"), "4 en total, sí")
	assert_true(str(GameInstances.normalize([{}], 4).get("error", "")).contains("4 already running"), "cuenta las que ya corren")
	assert_true(GameInstances.normalize("two").has("error"), "no es una lista")
	assert_true(GameInstances.normalize([{"args": "--server"}]).has("error"), "args no es una lista")
	assert_true(GameInstances.normalize([{"device": "toaster"}]).has("error"), "un dispositivo que no existe")
	assert_true(GameInstances.normalize([{"inputs": "jump"}]).has("error"), "inputs no es una lista")


func test_launch_args() -> void:
	var entry: Dictionary = GameInstances.normalize_entry({"args": ["--client", "127.0.0.1:7000"]})
	var args := GameInstances.launch_args("/p", "res://main.tscn", "tcp://127.0.0.1:6007", entry, 2, AREA)
	assert_eq(args.slice(0, 4), PackedStringArray(["--path", "/p", "--remote-debug", "tcp://127.0.0.1:6007"]), "al debugger del editor")
	assert_true("--resolution" in args and args[args.find("--resolution") + 1] == "640x360", "ventana del tamaño por defecto · %s" % [args])
	var scene_at := args.find("res://main.tscn")
	assert_true(scene_at > 0 and args[scene_at + 1] == "--" and args.slice(scene_at + 2) == PackedStringArray(["--client", "127.0.0.1:7000"]), "los del juego después de -- · %s" % [args])
	var server := GameInstances.launch_args("/p", "res://main.tscn", "tcp://127.0.0.1:6007", GameInstances.normalize_entry({"headless": true}), 3, AREA)
	assert_true("--headless" in server and not "--position" in server and not "--" in server, "headless: sin ventana · %s" % [server])
	var phone := GameInstances.normalize_entry({"device": "phone"})
	assert_eq(GameInstances.window_size(phone), Vector2i(phone.device.size[0], phone.device.size[1]), "la ventana del dispositivo")


## Con el puerto de los settings tomado por otro editor, este escucha en el siguiente: las instancias
## extra van adonde se conectó el juego del editor, no a remote_port.
func test_debugger_uri() -> void:
	assert_eq(GameInstances.remote_debug_arg(PackedStringArray(["godot", "--path", "/p", "--remote-debug", "tcp://127.0.0.1:6008", "res://main.tscn"])), "tcp://127.0.0.1:6008", "lo que recibió el juego")
	assert_eq(GameInstances.remote_debug_arg(PackedStringArray(["--remote-debug=tcp://10.0.0.2:6010"])), "tcp://10.0.0.2:6010", "con =")
	assert_eq(GameInstances.remote_debug_arg(PackedStringArray(["--path", "/p"])), "", "sin debugger")
	var own := GameInstances.command_line(OS.get_process_id())
	assert_true(own.size() > 1 and Array(OS.get_cmdline_user_args()).all(func(arg: String) -> bool: return arg in own), "la línea de comandos de este proceso · %s" % [own])
	assert_eq(GameInstances.editor_debugger_uri(0), "", "sin PID, nada")
	assert_eq(GameInstances.debugger_uri("tcp://127.0.0.1:6008", "127.0.0.1", 6007), "tcp://127.0.0.1:6008", "el del juego del editor gana")
	assert_eq(GameInstances.debugger_uri("", "", 6007), "tcp://127.0.0.1:6007", "sin él, los settings")


func test_tiles_dont_overlap() -> void:
	var size := GameInstances.DEFAULT_SIZE
	var rects: Array[Rect2i] = []
	for number in range(2, GameInstances.MAX_INSTANCES + 1):
		var position := GameInstances.tile_position(number, size, AREA)
		assert_true(AREA.has_point(position), "la %d dentro de la pantalla · %s" % [number, position])
		rects.append(Rect2i(position - Vector2i(0, GameInstances.TITLE_BAR), size + Vector2i(0, GameInstances.TITLE_BAR)))
	for i in rects.size():
		for j in range(i + 1, rects.size()):
			assert_false(rects[i].intersects(rects[j]), "la %d y la %d no se tapan" % [i + 2, j + 2])
	var small := Rect2i(0, 0, 1366, 500)
	assert_true(GameInstances.tile_position(2, size, small).x != GameInstances.tile_position(3, size, small).x, "en una pantalla baja, otra columna")


func test_environment() -> void:
	var env := GameInstances.environment(GameInstances.normalize_entry({"device": "phone"}), 3, false)
	assert_eq(env[InstanceEnv.ENV_INSTANCE], "3", "el número")
	assert_eq(env[RealGamepads.ENV], RealGamepads.NONE, "sin los gamepads reales")
	assert_eq(JSON.parse_string(env[DeviceSim.ENV]).name, "phone", "el dispositivo")
	assert_eq(env[InstanceEnv.ENV_SHARED_USER_DIR], "", "user:// propio por defecto")
	var shared := GameInstances.environment(GameInstances.normalize_entry({"shared_user_dir": true}), 2, true)
	assert_true(shared[InstanceEnv.ENV_SHARED_USER_DIR] == "1" and not shared.has(RealGamepads.ENV) and shared[DeviceSim.ENV] == "", "compartido, gamepads reales, sin dispositivo")


func test_user_dir_per_instance() -> void:
	var data := "/home/u/.local/share"
	var default_dir := data + "/godot/app_userdata/My Game"
	assert_eq(InstanceEnv.custom_dir_name(1, default_dir, data, false), "", "la 1, el de siempre")
	assert_eq(InstanceEnv.custom_dir_name(2, default_dir, data, false), "godot/app_userdata/My Game/instances/2", "la 2, su carpeta")
	assert_eq(InstanceEnv.custom_dir_name(3, default_dir, data, true), "", "compartido")
	assert_eq(InstanceEnv.custom_dir_name(2, data + "/mygame", data, false), "mygame/instances/2", "un user dir propio del proyecto suma la subcarpeta")


func test_sessions_map() -> void:
	var map := InstanceSessions.new()
	assert_eq(map.started(0), 0, "la sesión del editor no es una instancia extra")
	map.expecting = 2
	assert_eq(map.started(1), 2, "la siguiente que arranca es la esperada")
	assert_eq(map.expecting, 0, "una sola vez")
	assert_eq([map.session_of(2), map.number_of(1), map.number_of(0), map.probe_of(2)], [1, 2, 0, -1], "mapa, sin probe todavía")
	assert_eq(map.ready(1), 2, "su probe")
	assert_eq(map.ready(0), 0, "el ready del editor no la toca")
	assert_eq(map.probe_of(2), 1, "probe de la 2")
	assert_eq(map.stopped(0), 0, "el fin del juego del editor no es de una instancia")
	assert_eq(map.stopped(1), 2, "la 2 terminó")
	assert_eq([map.session_of(2), map.probe_of(2)], [-1, -1], "fuera del mapa")
	map.expecting = 3
	map.started(1)
	assert_eq(map.number_of(1), 3, "una sesión reusada por otra instancia")
	assert_eq(map.started(1), 0, "y otra vez por el juego del editor")
	assert_eq(map.number_of(1), 0, "deja de ser instancia")


func test_autoload_goes_first() -> void:
	var name := "autoload/GodotAgentTestEarly"
	ProjectSettings.set_setting(name, "*res://nothing.gd")
	var order := PlaytestAutoload.first_order()
	assert_true(order < ProjectSettings.get_order(name), "antes que los autoloads del proyecto")
	ProjectSettings.set_setting(name, null)
