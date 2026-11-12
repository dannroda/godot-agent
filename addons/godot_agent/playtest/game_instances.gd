@tool
extends RefCounted
## Las instancias extra de run_scene (m11-50): un server y sus clientes, o casos en paralelo. La 1 es
## la que lanza el editor (play_custom_scene); desde la 2 son procesos del harness, con el binario del
## editor y --remote-debug al server del debugger del editor: cada una es una sesión más del debugger
## y carga el probe de playtest. Así cada una tiene su propio entorno (dispositivo simulado, gamepads,
## user:// aparte), sus argumentos y su PID para cortarla (game_instance stop).
## No se usa «Customize Run Instances» de Godot: el editor lo lee de su diálogo al lanzar y todas las
## instancias heredan el mismo entorno.

const DeviceSim := preload("runtime/device_sim.gd")
const InstanceEnv := preload("runtime/instance_env.gd")
const RealGamepads := preload("real_gamepads.gd")
const AgentProcess := preload("../transport/agent_process.gd")
const ProcessTree := preload("../transport/process_tree.gd")

## Contando la del editor. Cada una es un Godot entero; se sube si alguien lo pide.
const MAX_INSTANCES := 4
## Tamaño de la ventana de una instancia sin dispositivo simulado.
const DEFAULT_SIZE := Vector2i(640, 360)
const ARGS_MAX := 32
const MARGIN := 24
## Lo que suma la barra de título de una ventana al apilarlas.
const TITLE_BAR := 32

## número → {pid, args, headless, device, shared_user_dir, started_ms}
var entries: Dictionary = {}


## `instances` de run_scene → {instances: [{args, headless, device, inputs, shared_user_dir}]} o {error}.
## `used`: las que ya corren (la del editor cuenta como 1).
static func normalize(value: Variant, used: int = 1) -> Dictionary:
	if value == null:
		return {"instances": []}
	if not value is Array:
		return {"error": "`instances` must be a list of objects {args, headless, device, inputs}, one per extra instance (the editor's game is instance 1)."}
	var list: Array = value
	if used + list.size() > MAX_INSTANCES:
		return {"error": "At most %d instances run at once (each one is a whole Godot): %d asked for, %d already running." % [MAX_INSTANCES, list.size(), used]}
	var result: Array = []
	for item: Variant in list:
		var entry := normalize_entry(item)
		if entry.has("error"):
			return entry
		result.append(entry)
	return {"instances": result}


## Una instancia: {args?: [String], headless?: bool, device?, inputs?: Array, shared_user_dir?: bool}.
static func normalize_entry(item: Variant) -> Dictionary:
	var spec: Dictionary = item if item is Dictionary else {}
	if not item is Dictionary:
		return {"error": "Each instance must be an object {args, headless, device, inputs}."}
	var args: PackedStringArray = []
	var raw: Variant = spec.get("args", [])
	if not raw is Array:
		return {"error": "`args` of an instance must be a list of strings, e.g. [\"--client\", \"127.0.0.1:7000\"]."}
	if (raw as Array).size() > ARGS_MAX:
		return {"error": "Too many `args` for an instance (%d; at most %d)." % [(raw as Array).size(), ARGS_MAX]}
	for arg: Variant in raw:
		args.append(str(arg))
	var device := DeviceSim.normalize(spec.get("device"))
	if device.has("error"):
		return device
	var inputs: Variant = spec.get("inputs", [])
	if not inputs is Array:
		return {"error": "`inputs` of an instance must be a list of steps, like run_scene's."}
	return {"args": args, "headless": spec.get("headless") == true, "device": device.get("device", {}), "inputs": inputs, "shared_user_dir": spec.get("shared_user_dir") == true}


## Adonde se conecta una instancia extra: al debugger que usa el juego del editor (`reported`). Sin eso,
## el de los settings, que falla si otro editor tenía el puerto.
static func debugger_uri(reported: String, host: String, port: int) -> String:
	if reported.begins_with("tcp://"):
		return reported
	return "tcp://%s:%d" % [host if not host.is_empty() else "127.0.0.1", port]


## La dirección del debugger con que el editor lanzó el juego `pid` (`--remote-debug tcp://127.0.0.1:6008`),
## o "". Es la que vale: si otro editor ya tenía network/debug/remote_port, este escucha en el siguiente,
## y eso no lo dicen los settings ni ninguna API (el juego tampoco lo ve: Godot saca --remote-debug de
## OS.get_cmdline_args()). Solo lo sabe la línea de comandos del juego.
static func editor_debugger_uri(pid: int) -> String:
	return remote_debug_arg(command_line(pid)) if pid > 0 else ""


## El valor de --remote-debug en una línea de comandos, o "".
static func remote_debug_arg(args: PackedStringArray) -> String:
	for i in args.size():
		if args[i] == "--remote-debug" and i + 1 < args.size():
			return args[i + 1]
		if args[i].begins_with("--remote-debug="):
			return args[i].trim_prefix("--remote-debug=")
	return ""


## La línea de comandos del proceso `pid`. Linux: /proc, sin lanzar nada. macOS y los BSD: ps.
## Windows: Get-CimInstance. Partida por espacios fuera de Linux: alcanza para --remote-debug, que no
## lleva espacios.
static func command_line(pid: int) -> PackedStringArray:
	var proc := "/proc/%d/cmdline" % pid
	if FileAccess.file_exists(proc):
		var file := FileAccess.open(proc, FileAccess.READ)
		if file == null:
			return PackedStringArray()
		# /proc reporta largo 0: se lee por bloques hasta que no viene más.
		var bytes := PackedByteArray()
		while true:
			var chunk := file.get_buffer(4096)
			bytes.append_array(chunk)
			if chunk.size() < 4096:
				break
		# Separados por NUL, que get_string_from_utf8 toma como el final.
		var args := PackedStringArray()
		var start := 0
		for i in bytes.size():
			if bytes[i] == 0:
				if i > start:
					args.append(bytes.slice(start, i).get_string_from_utf8())
				start = i + 1
		if start < bytes.size():
			args.append(bytes.slice(start).get_string_from_utf8())
		return args
	var output: Array = []
	var code := -1
	if OS.get_name() == "Windows":
		code = OS.execute("powershell", ["-NoProfile", "-Command", "(Get-CimInstance Win32_Process -Filter 'ProcessId=%d').CommandLine" % pid], output)
	else:
		code = OS.execute("ps", ["-ww", "-o", "command=", "-p", str(pid)], output)
	if code != 0 or output.is_empty():
		return PackedStringArray()
	return str(output[0]).strip_edges().replace("\"", "").split(" ", false)


## Los argumentos del proceso de la instancia `number`. Los del juego van después de `--`, donde los
## lee OS.get_cmdline_user_args().
static func launch_args(project: String, scene: String, uri: String, entry: Dictionary, number: int, area: Rect2i) -> PackedStringArray:
	var args := PackedStringArray(["--path", project, "--remote-debug", uri])
	if bool(entry.get("headless", false)):
		args.append("--headless")
	else:
		var size := window_size(entry)
		var position := tile_position(number, size, area)
		args.append_array(["--position", "%d,%d" % [position.x, position.y], "--resolution", "%dx%d" % [size.x, size.y]])
	args.append(scene)
	var game_args: PackedStringArray = entry.get("args", PackedStringArray())
	if not game_args.is_empty():
		args.append("--")
		args.append_array(game_args)
	return args


static func window_size(entry: Dictionary) -> Vector2i:
	var device: Dictionary = entry.get("device", {})
	var size: Array = device.get("size", [])
	return Vector2i(int(size[0]), int(size[1])) if size.size() == 2 else DEFAULT_SIZE


## Las instancias 2..N en mosaico sobre el borde derecho del área útil de la pantalla, de arriba hacia
## abajo, y en otra columna a la izquierda cuando no entran: no se tapan entre ellas.
static func tile_position(number: int, size: Vector2i, area: Rect2i) -> Vector2i:
	var slot := maxi(0, number - 2)
	var step := size.y + TITLE_BAR + MARGIN
	var per_column := maxi(1, (area.size.y - MARGIN) / maxi(1, step))
	var column := slot / per_column
	var row := slot % per_column
	var x := area.end.x - MARGIN - size.x - column * (size.x + MARGIN)
	var y := area.position.y + MARGIN + TITLE_BAR + row * step
	return Vector2i(maxi(area.position.x, x), y)


## El entorno de la instancia: su número, su dispositivo, los gamepads reales afuera y el user:// propio.
static func environment(entry: Dictionary, number: int, real_gamepads: bool) -> Dictionary:
	var env := {InstanceEnv.ENV_INSTANCE: str(number), InstanceEnv.ENV_SHARED_USER_DIR: "1" if bool(entry.get("shared_user_dir", false)) else ""}
	var device: Dictionary = entry.get("device", {})
	env[DeviceSim.ENV] = JSON.stringify(device) if not device.is_empty() else ""
	if not real_gamepads:
		env[RealGamepads.ENV] = RealGamepads.NONE
	return env


func running() -> PackedInt32Array:
	var numbers: PackedInt32Array = []
	for number: int in entries:
		if OS.is_process_running(int(entries[number].pid)):
			numbers.append(number)
	numbers.sort()
	return numbers


## El primer número libre desde el 2, o -1 si ya corren MAX_INSTANCES.
func free_number() -> int:
	for number in range(2, MAX_INSTANCES + 1):
		if not entries.has(number) or not OS.is_process_running(int(entries[number].pid)):
			return number
	return -1


## Lanza la instancia `number`. Devuelve su PID, o 0 si no arrancó. El entorno se setea solo
## alrededor del lanzamiento, como el de la instancia del editor.
func launch(number: int, args: PackedStringArray, entry: Dictionary, real_gamepads: bool) -> int:
	var env := environment(entry, number, real_gamepads)
	var previous := {}
	for key: String in env:
		previous[key] = OS.get_environment(key) if OS.has_environment(key) else null
		if str(env[key]).is_empty():
			OS.unset_environment(key)
		else:
			OS.set_environment(key, str(env[key]))
	var pid := OS.create_process(OS.get_executable_path(), args)
	for key: String in previous:
		if previous[key] == null:
			OS.unset_environment(key)
		else:
			OS.set_environment(key, str(previous[key]))
	if pid <= 0:
		return 0
	AgentProcess.track_pid(pid)
	entries[number] = {"pid": pid, "args": entry.get("args", PackedStringArray()), "headless": bool(entry.get("headless", false)),
		"device": entry.get("device", {}), "shared_user_dir": bool(entry.get("shared_user_dir", false)), "started_ms": Time.get_ticks_msec()}
	return pid


## Corta la instancia `number` (la mata con sus hijos): para el juego es una desconexión sin aviso.
func stop(number: int) -> bool:
	if not entries.has(number):
		return false
	var pid := int(entries[number].pid)
	entries.erase(number)
	AgentProcess.untrack_pid(pid)
	if OS.is_process_running(pid):
		ProcessTree.kill_tree(pid)
	return true


func stop_all() -> void:
	for number: int in entries.keys():
		stop(number)
