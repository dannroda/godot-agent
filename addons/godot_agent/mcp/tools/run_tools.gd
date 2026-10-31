@tool
extends RefCounted
## Tools de ejecución (spec §6): run_scene, stop_scene, capture_game_frame y, con el juego
## corriendo, game_tree, game_get, game_set, game_call, game_wait y game_input (m4-07, D54), más
## game_find, game_ui, game_ui_act, game_script, game_pause, game_step, game_watch y game_frames (M13).
## El juego es otro proceso: el probe de playtest (autoload temporal) captura frames, reproduce
## inputs y contesta pedidos (`request` → `reply` con id) por el canal del debugger. El autoload se da de alta en EditorPlugin._build() solo si el
## run lo pidió el harness (`harness_requested`) y de baja cuando el juego ya leyó project.godot.

const McpTool := preload("../mcp_tool.gd")
const ErrorCollector := preload("../../editor/error_collector.gd")
const PlaytestDebugger := preload("../../playtest/playtest_debugger.gd")
const PermissionPolicy := preload("../../session/permission_policy.gd")
const PlaytestMemory := preload("../../review/playtest_memory.gd")
const ProjectTools := preload("project_tools.gd")

## Las del juego en ejecución: extendidas con tools/list compacto (D56).
const GAME_TOOLS: PackedStringArray = ["game_tree", "game_get", "game_set", "game_call", "game_wait", "game_input", "game_find", "game_ui", "game_ui_act", "game_script", "game_pause", "game_step", "game_watch", "game_frames"]
const MAX_SECONDS := 120.0
const STARTUP_TIMEOUT_S := 20.0
const FRAME_TIMEOUT_S := 5.0
const STOP_TIMEOUT_S := 5.0
## Margen para que lleguen al editor los últimos errores y el Output del juego.
const SETTLE_S := 0.5
const OUTPUT_LINE_LIMIT := 150
const ERROR_LIMIT := 100
## Margen para que el juego conteste un pedido, además de lo que dure (game_wait, game_input).
const REQUEST_TIMEOUT_S := 5.0
const WAIT_MAX_S := 60.0
const INPUT_MAX_STEPS := 200
## Pulsación por defecto de un paso sin `pressed` (tecla, acción, click): apretar y soltar.
const TAP_HOLD_S := 0.1
## Pausa por defecto entre pasos sin `t`.
const STEP_GAP_S := 0.05
## Con `frame` (m14-01): pulsación por defecto en frames de física, y el máximo de frames.
const TAP_HOLD_FRAMES := 6
## Grabación de un run (m14-03): carpeta, fps fijos del Movie Maker y la espera a que el juego cierre.
const RECORD_DIR := "res://.godot_agent/playtests"
const RECORD_FPS := 30
const RECORD_CLOSE_S := 10.0
const MOVIE_FILE_SETTING := "editor/movie_writer/movie_file"
const MOVIE_FPS_SETTING := "editor/movie_writer/fps"
const FRAME_MAX := 60 * 60
const SCRIPT_MAX_S := 60.0
const WATCH_MAX_S := 60.0
## Pausas del debugger seguidas que se saltean antes de dejar el juego parado (m15-05): un error por
## frame frenaría todo igual.
const CONTINUE_MAX := 30
## Un frame largo justo después de salir de una pausa del debugger no es del juego.
const HITCH_AFTER_BREAK_MS := 1500
## Filmación (m15-22): frames por carpeta y carpetas que se guardan.
const FILM_MAX_FRAMES := 900
const FILM_KEEP_RUNS := 5
const FRAMES_MAX_SHOWN := 12
const FINDING_FRAMES_KEPT := 50
## APIs que game_script no puede usar: el evaluador del One-shot y el Playtest no tocan el proyecto (m15-12).
## shortcut: una lista de nombres frena un descuido, no a alguien que quiera esquivarla; si eso importa, hace falta correr el juego en un sandbox.
const SCRIPT_BLOCKED := "\\b(FileAccess|DirAccess|ResourceSaver|ConfigFile|ZIPPacker|OS\\s*\\.\\s*(execute|execute_with_pipe|create_process|create_instance|shell_open|shell_show_in_file_manager|move_to_trash|kill)|ProjectSettings\\s*\\.\\s*save)\\b|\\.save_(png|jpg|webp|exr)\\s*\\("
const NO_PROBE := "No game is running with the playtest probe: launch it with run_scene (manual runs have it only with «Use the playtest autoload also when running the game manually» in Settings → MCP server)."
const STEPS_HELP := "Each step is one of {action: \"jump\"}, {key: \"Space\" | \"Ctrl+S\"}, {event: \"joy_button:a\" | \"joy_axis:left_x:-\"}, {click: [x, y], button: \"left|right|middle\"}, {move: [x, y]} (window pixels), {look: [dx, dy]} (relative mouse motion: first-person aim) or {text: \"abc\"} (types it, into the focused LineEdit), with optional t (seconds from the start; default: right after the previous step), pressed (true: only press, false: only release; default: press and release after `hold` seconds, 0.1) and strength (0–1, actions only). For reproducible input use frame instead of t in every step: physics frames from the start (default: right after the previous step), with hold_frames (default 6) instead of hold; the same sequence then plays the same at any framerate."

var errors: ErrorCollector
var debugger: PlaytestDebugger
var max_image_side: int = 1280
## Lo lee EditorPlugin._build(): este run lo pidió el harness y lleva el autoload de playtest.
var harness_requested: bool = false
## Quita el autoload si el juego no llegó a arrancar (lo inyecta el plugin).
var cleanup: Callable
## Cuándo se acaba el tiempo del playtest en curso, en ms de Time.get_ticks_msec; 0 = sin tope (m15-19).
## Lo fija el controller: hay un solo juego corriendo a la vez.
static var playtest_deadline_ms: int = 0

var _busy: bool = false
var _state: Dictionary = {}
var _replies: Dictionary = {}
var _next_request: int = 1
## Saltear las pausas del debugger por errores (m15-05): solo en el run que lo pidió y en game_script.
var _continue_errors: bool = false
var _breaks: int = 0
var _last_break_ms: int = -HITCH_AFTER_BREAK_MS
var _continued: PackedStringArray = []
## firma → hallazgo de los detectores (m15-07); `_findings_new`: firmas sin reportar todavía.
var _findings: Dictionary = {}
var _findings_new: PackedStringArray = []
## Carpeta y frames ({number, t, path}) de la filmación del run (m15-22).
var _film_dir: String = ""
var _film_frames: Array[Dictionary] = []


func setup(collector: ErrorCollector, playtest_debugger: PlaytestDebugger) -> void:
	errors = collector
	debugger = playtest_debugger
	# Métodos y no lambdas: una lambda captura a RunTools, el debugger la guarda en su señal y
	# RunTools guarda al debugger; el ciclo no se libera al deshabilitar el plugin (m13-10).
	debugger.session_started.connect(_flag.bind("started"))
	debugger.session_stopped.connect(_on_session_stopped)
	debugger.session_breaked.connect(_on_session_breaked)
	debugger.probe_ready.connect(_flag.bind("ready"))
	debugger.inputs_done.connect(_on_inputs_done)
	debugger.problem_reported.connect(_on_problem_reported)
	debugger.frame_received.connect(_on_frame_received)
	debugger.reply_received.connect(_on_reply_received)
	debugger.finding_received.connect(_on_finding_received)
	debugger.finding_frame_received.connect(_on_finding_frame_received)
	debugger.film_frame_received.connect(_on_film_frame_received)


func _flag(key: String) -> void:
	_state[key] = true


func _on_session_stopped() -> void:
	_continue_errors = false
	_flag("stopped")


## Un error del juego: se saltea si este run lo pidió, guardando el motivo (el panel se llena un
## momento después de la pausa).
func _on_session_breaked() -> void:
	if not _continue_errors or _breaks >= CONTINUE_MAX:
		if _continue_errors:
			_continued.append("Stopped skipping errors after %d in this run: the game is stopped in the debugger." % CONTINUE_MAX)
			_continue_errors = false
		_flag("breaked")
		return
	_breaks += 1
	var tree := Engine.get_main_loop() as SceneTree
	var reason := ""
	for frame in 20:
		await tree.process_frame
		if frame >= 1:
			reason = PlaytestDebugger.break_reason()
			if not reason.is_empty():
				break
	# Un breakpoint lo puso alguien para frenar acá: no es un error que se saltea (m16-05).
	if reason.begins_with("Breakpoint"):
		_continue_errors = false
		_flag("breaked")
		return
	_continued.append(reason if not reason.is_empty() else "(the debugger gave no reason)")
	_last_break_ms = Time.get_ticks_msec()
	debugger.resume()


func _on_finding_received(finding: Dictionary) -> void:
	if finding.get("detector") == "hitch" and Time.get_ticks_msec() - _last_break_ms < HITCH_AFTER_BREAK_MS:
		return
	var signature := str(finding.get("signature", ""))
	_findings[signature] = finding
	if not signature in _findings_new:
		_findings_new.append(signature)


func _on_finding_frame_received(signature: String, png: PackedByteArray) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(RECORD_DIR))
	var path := RECORD_DIR.path_join("finding_%s_%d.png" % [signature.md5_text().left(8), Time.get_ticks_msec()])
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return
	file.store_buffer(png)
	file.close()
	if _findings.has(signature):
		_findings[signature]["frame"] = path
		if not signature in _findings_new:
			_findings_new.append(signature)
	_keep_newest(RECORD_DIR, "finding_", FINDING_FRAMES_KEPT)


func _on_film_frame_received(number: int, game_time: float, jpeg: PackedByteArray) -> void:
	if _film_dir.is_empty():
		return
	var path := _film_dir.path_join("%06d.jpg" % number)
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return
	file.store_buffer(jpeg)
	file.close()
	_film_frames.append({"number": number, "t": game_time, "path": path})
	if _film_frames.size() > FILM_MAX_FRAMES:
		var old: Dictionary = _film_frames.pop_front()
		DirAccess.remove_absolute(ProjectSettings.globalize_path(old.path))


## Deja los `kept` archivos o carpetas más nuevos de `dir` cuyo nombre empieza con `prefix`.
static func _keep_newest(dir: String, prefix: String, kept: int) -> void:
	var names: Array = []
	for name: String in DirAccess.get_files_at(dir) + DirAccess.get_directories_at(dir):
		if name.begins_with(prefix):
			names.append(name)
	names.sort()  # llevan la fecha o los ms en el nombre
	for name: String in names.slice(0, maxi(names.size() - kept, 0)):
		var path := ProjectSettings.globalize_path(dir.path_join(name))
		if DirAccess.dir_exists_absolute(path):
			for file: String in DirAccess.get_files_at(path):
				DirAccess.remove_absolute(path.path_join(file))
		DirAccess.remove_absolute(path)


func _on_inputs_done(count: int) -> void:
	_state["inputs_done"] = count


func _on_problem_reported(text: String) -> void:
	(_state.get_or_add("problems", []) as Array).append(text)


func _on_frame_received(png: PackedByteArray, _width: int, _height: int) -> void:
	_state["frame"] = png


func _on_reply_received(id: int, result: Dictionary) -> void:
	_replies[id] = result


func tools() -> Array:
	var run := PermissionPolicy.GROUP_RUN
	var read := PermissionPolicy.GROUP_READ
	var steps_schema := {"type": "array", "description": STEPS_HELP, "items": {"type": "object", "properties": {
		"t": {"type": "number"}, "action": {"type": "string"}, "key": {"type": "string"}, "event": {"type": "string"},
		"click": {"type": "array", "items": {"type": "number"}}, "move": {"type": "array", "items": {"type": "number"}},
		"button": {"type": "string"}, "pressed": {"type": "boolean"}, "hold": {"type": "number"},
		"look": {"type": "array", "items": {"type": "number"}}, "text": {"type": "string"},
		"frame": {"type": "integer"}, "hold_frames": {"type": "integer"}, "strength": {"type": "number"}}}}
	var path_schema := {"type": "string", "description": "Node path in the running game: relative to the current scene (\"Player\", \"HUD/Score\"), \"\" for the scene itself, or absolute (\"/root/GameState\" for an autoload)"}
	return [
		McpTool.create("run_scene", run,
			"Runs a scene (default: the open one), waits `seconds` or until it ends, and returns the game's errors and Output. The game keeps running afterwards: capture_game_frame to see it, stop_scene to close it. Saves the scenes before running.",
			{
				"scene": {"type": "string", "description": "res://…tscn path (default: the open scene)"},
				"seconds": {"type": "number", "description": "Seconds to wait after the game starts (max. 120)"},
				"inputs": steps_schema,
				"record": {"type": "boolean", "description": "Record the run as a video (AVI) under res://.godot_agent/playtests/: evidence for a playtest. While recording the game runs at a fixed %d fps and closes by itself at the end of `seconds`." % RECORD_FPS},
				"continue_on_error": {"type": "boolean", "description": "Don't stop in the debugger at a script error: the game goes on and every error is listed (breakpoints still stop it). For testing a whole game; while building, stopping at the first error is better."},
				"film_fps": {"type": "number", "description": "Keep small frames of the run at this rate (2 to 10 is plenty), to look back with game_frames. The game keeps running and its frame rate is free, unlike `record`."},
			},
			["seconds"], _run_scene),
		McpTool.create("stop_scene", run, "Stops the running game.", {}, [], _stop_scene),
		McpTool.create("capture_game_frame", run, "Captures the current frame of the running game (launched with run_scene) as a PNG.", {}, [], _capture_game_frame),
		McpTool.create("game_tree", read,
			"The live node tree of the running game (nodes spawned at runtime included), with types, scripts, positions and texts.",
			{"path": path_schema, "depth": {"type": "integer", "description": "Levels below `path` (default 4)"}}, [], _game_tree),
		McpTool.create("game_get", read,
			"Reads properties of a node in the running game (\"health\", \"position:x\"). Without `properties`: its script variables and the usual ones (position, velocity, visible, text…).",
			{"path": path_schema, "properties": {"type": "array", "items": {"type": "string"}}}, ["path"], _game_get),
		McpTool.create("game_set", run,
			"Changes properties of a node in the running game, live (the scene file is not changed). Vectors as [x, y], colors as \"#rrggbb\", resources as res:// paths.",
			{"path": path_schema, "properties": {"type": "object"}}, ["path", "properties"], _game_set),
		McpTool.create("game_call", run,
			"Calls a method on a node in the running game and returns its result (\"take_damage\" with args [10]).",
			{"path": path_schema, "method": {"type": "string"}, "args": {"type": "array"}}, ["path", "method"], _game_call),
		McpTool.create("game_wait", run,
			"Waits in the running game until `condition` is true (a Godot Expression evaluated on the node every frame: \"health <= 0\", \"get_node('Boss') == null\", \"score >= 3\"), until the node emits `signal`, or just `timeout` seconds. Returns how long it took or that it timed out.",
			{"path": path_schema, "condition": {"type": "string"}, "signal": {"type": "string"}, "timeout": {"type": "number", "description": "Seconds (default 5, max. 60)"}},
			[], _game_wait),
		McpTool.create("game_input", run,
			"Sends live input to the running game and waits until it has been played: keys, InputMap actions, mouse clicks and moves, joypad. " + STEPS_HELP,
			{"steps": steps_schema, "settle_frames": {"type": "integer", "description": "Physics frames to wait after the last step before answering (frame mode; default 0)"}}, ["steps"], _game_input),
		McpTool.create("game_find", read,
			"Finds nodes in the running game by class (a Godot class or a script's class_name, subclasses included), group (\"group:enemies\") or part of the name. Without filters, the scene's things: its direct children, physics bodies and areas.",
			{"class": {"type": "string"}, "name": {"type": "string"}, "limit": {"type": "integer"}}, [], _game_find),
		McpTool.create("game_ui", read,
			"What a player sees of the UI of the running game: every visible text, and every button, checkbox, list, slider and text field with its id and pixel position. Use the id with game_ui_act instead of guessing pixels.",
			{}, [], _game_ui),
		McpTool.create("game_ui_act", run,
			"Acts on a control listed by game_ui. A click goes through the viewport as a real mouse click does, so something on top of the control blocks it: that comes back as an error, because a player could not press it either. `set` and choosing an option change the value directly (not by input), and say so. To type: action focus, then game_input {text}.",
			{"id": {"type": "string"}, "action": {"type": "string", "enum": ["click", "right_click", "double_click", "focus", "set"]}, "value": {"description": "For set: the value. For click on a list: the option's text."}}, ["id"], _game_ui_act),
		McpTool.create("game_script", run,
			"Runs a short GDScript inside the running game, so it can react in the same frame and do many reads and inputs in one call. The code needs `func run(game):` and runs as a coroutine; what it returns and what it says with game.say(...) come back. `game` has: say(...), node(path), player(), tree(), movement() (speed, jump and gravity read from the player's script); await press(name), hold(name), release(name), mouse(dx, dy), await wait(seconds), await wait_frames(n), await until(callable, timeout), await look_at(node_or_point, tolerance) (3D). press, until and look_at return {ok, why, data}: read `why` before you blame the game. Example: func run(game):\n\tawait game.press(\"jump\")\n\treturn game.player().velocity.y\nAt `timeout` it stops, the keys it held are let go and the game is paused. It can't use files or start processes.",
			{"code": {"type": "string"}, "timeout": {"type": "number", "description": "Seconds (default 10, max. %d)" % SCRIPT_MAX_S}}, ["code"], _game_script),
		McpTool.create("game_pause", run,
			"Pauses or resumes the running game, so nothing happens while you think. While paused, advance it with game_step. Reads and captures still work. Code that measures real time (Time.get_ticks_*) keeps counting.",
			{"paused": {"type": "boolean"}}, ["paused"], _game_pause),
		McpTool.create("game_step", run,
			"Lets the game run for `frames` physics frames, playing `steps` by frame meanwhile, and pauses it again: play turn by turn, even a fast game. " + STEPS_HELP,
			{"frames": {"type": "integer", "description": "Physics frames to advance (default 1; at least until the last step)"}, "steps": steps_schema}, [], _game_step),
		McpTool.create("game_watch", run,
			"Watches nodes every frame for `seconds` and lists what changed, with times: moved, turned, changed size, shown or hidden, freed, animations that started or ended, and the given properties. Catches what lasts less than a tool call; pass `steps` to play input while watching.",
			{"paths": {"type": "array", "items": {"type": "string"}, "description": "Node paths"}, "seconds": {"type": "number", "description": "Default 2, max. %d" % WATCH_MAX_S}, "properties": {"type": "array", "items": {"type": "string"}}, "steps": steps_schema}, ["paths"], _game_watch),
		McpTool.create("game_frames", read,
			"The frames of the last `seconds` of play, with their game times and file paths (a subagent can read those files). Needs a run filmed with run_scene film_fps, or pass `fps` here to start filming.",
			{"seconds": {"type": "number", "description": "How far back (default 3)"}, "count": {"type": "integer", "description": "How many, evenly spaced (default 6, max. %d)" % FRAMES_MAX_SHOWN}, "fps": {"type": "number", "description": "Start filming at this rate"}}, [], _game_frames),
	]


func _run_scene(args: Dictionary) -> Dictionary:
	if _busy:
		return McpTool.error("A run_scene is already in progress: wait for it to finish.")
	var scene := McpTool.str_arg(args, "scene")
	if scene.is_empty():
		var root := EditorInterface.get_edited_scene_root()
		if root == null:
			return McpTool.error("There is no open scene: pass `scene`.")
		scene = root.scene_file_path
		if scene.is_empty():
			return McpTool.error("The open scene was never saved: save it with save_scene or pass `scene`.")
	elif not scene.begins_with("res://") or not ResourceLoader.exists(scene):
		return McpTool.error("The scene %s does not exist." % scene)
	var seconds := clampf(float(args.get("seconds", 5.0)), 0.1, MAX_SECONDS)
	var inputs: Array = []
	var invalid := normalize_steps(args.get("inputs", []), inputs)
	if not invalid.is_empty():
		return McpTool.error(invalid)

	_busy = true
	if EditorInterface.is_playing_scene():
		EditorInterface.stop_playing_scene()
		await _until(func() -> bool: return not EditorInterface.is_playing_scene(), STOP_TIMEOUT_S)
	var recording := _start_recording() if args.get("record") == true else {}
	var since := errors.mark()
	var output_before := errors.output_text()
	_state = {}
	_continue_errors = args.get("continue_on_error") == true
	_breaks = 0
	_continued = []
	_findings = {}
	_findings_new = []
	_film_dir = ""
	_film_frames = []
	harness_requested = true
	EditorInterface.play_custom_scene(scene)  # llama a _build() en el momento
	harness_requested = false
	if not EditorInterface.is_playing_scene():
		_busy = false
		_cleanup()
		_stop_recording(recording)
		return McpTool.error("The editor could not launch %s (did a plugin's build fail?). Try get_errors." % scene)

	await _until(func() -> bool: return _state.has("ready") or _state.has("stopped") or _state.has("breaked"), STARTUP_TIMEOUT_S)
	var notes: PackedStringArray = []
	if _state.has("ready"):
		if not inputs.is_empty():
			debugger.send("inputs", [inputs])
		if float(args.get("film_fps", 0.0)) > 0.0:
			notes.append(await _start_film(float(args.film_fps)))
	elif not _state.has("stopped") and not _state.has("breaked"):
		notes.append("The playtest probe did not respond within %d s: no inputs or captures." % STARTUP_TIMEOUT_S)
	await _until(func() -> bool: return _state.has("stopped") or _state.has("breaked"), seconds)
	await Engine.get_main_loop().create_timer(SETTLE_S).timeout
	if not recording.is_empty():
		notes.append(await _finish_recording(recording))
	if not _state.has("started"):
		_cleanup()
	if EditorInterface.is_playing_scene() and debugger.has_probe() and not _stopped_in_debugger():
		var opening := await request("opening", {})
		if opening.has("text"):
			notes.append("Now in the game:\n%s" % opening.text)
	var report := _report(scene, seconds, inputs, notes, since, output_before)
	_busy = false
	return McpTool.text(report)


## Prende el Movie Maker del editor hacia un AVI nuevo; devuelve lo que hay que restaurar y la ruta.
func _start_recording() -> Dictionary:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(RECORD_DIR))
	var stamp := Time.get_datetime_string_from_system().replace(":", "-").replace("T", "_")
	var path := RECORD_DIR.path_join("playtest_%s.avi" % stamp)
	var recording := {
		"path": path, "enabled": EditorInterface.is_movie_maker_enabled(),
		"file": ProjectSettings.get_setting(MOVIE_FILE_SETTING, ""), "fps": ProjectSettings.get_setting(MOVIE_FPS_SETTING, 60),
	}
	ProjectSettings.set_setting(MOVIE_FILE_SETTING, ProjectSettings.globalize_path(path))
	ProjectSettings.set_setting(MOVIE_FPS_SETTING, RECORD_FPS)
	EditorInterface.set_movie_maker_enabled(true)
	return recording


## Cierra el juego desde adentro (el video queda bien terminado) y deja el Movie Maker como estaba.
func _finish_recording(recording: Dictionary) -> String:
	if EditorInterface.is_playing_scene():
		debugger.send("quit")
		await _until(func() -> bool: return not EditorInterface.is_playing_scene(), RECORD_CLOSE_S)
		if EditorInterface.is_playing_scene():
			EditorInterface.stop_playing_scene()
			await _until(func() -> bool: return not EditorInterface.is_playing_scene(), STOP_TIMEOUT_S)
	_stop_recording(recording)
	var path: String = recording.path
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() == 0:
		return "The recording was not written (%s)." % path
	return "Recording: %s (%d KB, %d fps). The game was closed to finish the video." % [path, file.get_length() / 1024, RECORD_FPS]


static func _stop_recording(recording: Dictionary) -> void:
	if recording.is_empty():
		return
	EditorInterface.set_movie_maker_enabled(recording.enabled)
	ProjectSettings.set_setting(MOVIE_FILE_SETTING, recording.file)
	ProjectSettings.set_setting(MOVIE_FPS_SETTING, recording.fps)


func _stop_scene(_args: Dictionary) -> Dictionary:
	if not EditorInterface.is_playing_scene():
		return McpTool.text("No game is running.")
	EditorInterface.stop_playing_scene()
	await _until(func() -> bool: return not EditorInterface.is_playing_scene(), STOP_TIMEOUT_S)
	_cleanup()
	return McpTool.text("Game stopped.")


func _capture_game_frame(_args: Dictionary) -> Dictionary:
	if not EditorInterface.is_playing_scene() or not debugger.has_probe():
		return McpTool.error("No game is running with the playtest probe: launch it with run_scene (manual runs do not have it).")
	var frame: Variant = await capture_frame()
	if frame is String:
		return McpTool.error(frame)
	var image: Image = frame
	return McpTool.image(image, "Game frame (%dx%d)" % [image.get_width(), image.get_height()])


## El frame actual del juego (que tiene que tener la probe) como Image, o el error en inglés.
## También lo usa «+ contexto → Captura del juego» del dock.
func capture_frame() -> Variant:
	_state.erase("frame")
	debugger.send("capture", [max_image_side])
	await _until(func() -> bool: return _state.has("frame"), FRAME_TIMEOUT_S)
	if not _state.has("frame"):
		var paused := " The game is stopped in the debugger." if _state.has("breaked") else ""
		return "The game frame did not arrive within %d s.%s" % [FRAME_TIMEOUT_S, paused]
	var image := Image.new()
	if image.load_png_from_buffer(_state.frame) != OK:
		return "The game frame arrived corrupted."
	return image


## Llena `out` con los eventos para el probe ({t, kind, pressed, …}); devuelve "" o el error.
## Un paso sin `pressed` es apretar y soltar; sin `t`, va justo después del paso anterior.
static func normalize_steps(value: Variant, out: Array) -> String:
	if value == null:
		return ""
	if not value is Array:
		return "`inputs`/`steps` must be a list. " + STEPS_HELP
	value = _expand_text_steps(value)
	if (value as Array).size() > INPUT_MAX_STEPS:
		return "At most %d steps per call." % INPUT_MAX_STEPS
	var next_t := 0.0
	var next_frame := 0
	var by_frame := (value as Array).any(func(step: Variant) -> bool: return step is Dictionary and step.has("frame"))
	for step: Variant in value:
		if not step is Dictionary:
			return "Each step must be an object. " + STEPS_HELP
		var shown := JSON.stringify(step).left(120)
		if step.has("t") and not (step.t is float or step.t is int):
			return "`t` must be a number: %s" % shown
		if by_frame and step.has("t"):
			return "Use either `t` or `frame` in one call, not both: %s" % shown
		if step.has("frame") and not (step.frame is int or (step.frame is float and is_equal_approx(step.frame, roundf(step.frame)))):
			return "`frame` must be a whole number: %s" % shown
		if step.has("strength") and not (step.strength is float or step.strength is int):
			return "`strength` must be a number between 0 and 1: %s" % shown
		var t := maxf(float(step.get("t", next_t)), 0.0)
		var hold := clampf(float(step.get("hold", TAP_HOLD_S)), 0.0, WAIT_MAX_S)
		var frame := clampi(int(step.get("frame", next_frame)), 0, FRAME_MAX)
		var hold_frames := clampi(int(step.get("hold_frames", TAP_HOLD_FRAMES)), 0, FRAME_MAX)
		var events: Array = []
		if step.get("action") is String:
			var action: String = step.action
			if not ProjectSettings.has_setting("input/" + action) and not InputMap.has_action(action):
				return "The action '%s' does not exist in the project's InputMap." % action
			var action_event := {"kind": "action", "action": action}
			if step.has("strength"):
				action_event["strength"] = clampf(float(step.strength), 0.0, 1.0)
			events.append(action_event)
		elif step.get("char") is String:
			events.append(_char_step(step.char))
		elif step.get("look") is Array:
			var delta: Array = step.look
			if delta.size() != 2 or not (delta[0] is float or delta[0] is int) or not (delta[1] is float or delta[1] is int):
				return "`look` must be [dx, dy]: %s" % shown
			events.append({"kind": "mouse_motion", "rel_x": float(delta[0]), "rel_y": float(delta[1])})
		elif step.get("key") is String or step.get("event") is String:
			var spec: String = step.get("key") if step.get("key") is String else step.get("event")
			if step.get("key") is String and not ":" in spec:
				spec = "key:" + spec
			var parsed: Variant = ProjectTools.parse_event(spec)
			if parsed is String:
				return "%s (%s)" % [parsed, shown]
			var converted := _event_step(parsed, step)
			if converted.is_empty():
				return "Unsupported event in %s." % shown
			events.append(converted)
		elif step.get("click") is Array or step.get("move") is Array:
			var point: Variant = step.get("click", step.get("move"))
			if (point as Array).size() != 2 or not (point[0] is float or point[0] is int) or not (point[1] is float or point[1] is int):
				return "`click`/`move` must be [x, y] in window pixels: %s" % shown
			events.append({"kind": "mouse_motion", "x": float(point[0]), "y": float(point[1]), "motion": true})
			if step.has("click"):
				var button := str(step.get("button", "left")).to_lower()
				if not ProjectTools.MOUSE_BUTTONS.has(button):
					return "Unknown mouse button '%s' (left, right, middle, wheel_up, wheel_down)." % button
				events.append({"kind": "mouse_button", "button": ProjectTools.MOUSE_BUTTONS[button], "x": float(point[0]), "y": float(point[1])})
		else:
			return "Step without action, key, event, click or move: %s. %s" % [shown, STEPS_HELP]
		for event: Dictionary in events:
			if by_frame:
				event["frame"] = frame
			else:
				event["t"] = t
			if event.get("kind") == "mouse_motion":
				event.erase("motion")
				out.append(event)
			elif step.has("pressed"):
				event["pressed"] = step.pressed == true
				out.append(event)
			else:
				event["pressed"] = true
				out.append(event)
				var release := event.duplicate()
				release["pressed"] = false
				if by_frame:
					release["frame"] = frame + hold_frames
				else:
					release["t"] = t + hold
				out.append(release)
		var tap: bool = not step.has("pressed") and not step.has("move") and not step.has("look")
		next_t = t + (hold if tap else 0.0) + STEP_GAP_S
		next_frame = frame + (hold_frames if tap else 0) + 1
	return ""


## Un paso {text} se vuelve un toque corto por carácter (m15-04), el primero en el `t` o `frame` del paso.
static func _expand_text_steps(steps: Array) -> Array:
	var expanded: Array = []
	for step: Variant in steps:
		if not (step is Dictionary and step.get("text") is String):
			expanded.append(step)
			continue
		var first := true
		for character: String in (step.text as String):
			var one := {"char": character, "hold": 0.02, "hold_frames": 1}
			if first:
				for key: String in ["t", "frame"]:
					if step.has(key):
						one[key] = step[key]
			first = false
			expanded.append(one)
	return expanded


## El evento de un carácter: la tecla si la tiene y siempre su unicode, que es lo que escribe.
static func _char_step(character: String) -> Dictionary:
	var keycode := OS.find_keycode_from_string(character.to_upper()) if character != " " else KEY_SPACE
	return {"kind": "key", "keycode": int(keycode), "unicode": character.unicode_at(0), "ctrl": false, "alt": false, "meta": false, "shift": character != character.to_lower()}


## El paso para el probe de un InputEvent de ProjectTools.parse_event, o {} si no se puede mandar.
static func _event_step(event: InputEvent, step: Dictionary) -> Dictionary:
	if event is InputEventKey:
		var key := event as InputEventKey
		var command := key.command_or_control_autoremap
		var mac := OS.has_feature("macos")
		return {"kind": "key", "keycode": int(key.physical_keycode), "ctrl": key.ctrl_pressed or (command and not mac),
			"shift": key.shift_pressed, "alt": key.alt_pressed, "meta": key.meta_pressed or (command and mac)}
	if event is InputEventMouseButton:
		var at: Array = step.get("at") if step.get("at") is Array and (step.get("at") as Array).size() == 2 else [0, 0]
		return {"kind": "mouse_button", "button": int((event as InputEventMouseButton).button_index), "x": float(at[0]), "y": float(at[1])}
	if event is InputEventJoypadButton:
		return {"kind": "joy_button", "button": int((event as InputEventJoypadButton).button_index)}
	if event is InputEventJoypadMotion:
		var motion := event as InputEventJoypadMotion
		return {"kind": "joy_axis", "axis": int(motion.axis), "value": motion.axis_value}
	return {}


func _report(scene: String, seconds: float, inputs: Array, notes: PackedStringArray, since: int, output_before: String) -> String:
	var lines: PackedStringArray = []
	if _state.has("breaked"):
		var reason := PlaytestDebugger.break_reason()
		lines.append("%s: the game stopped in the debugger because of an error%s. It is still paused: fix it and run again (run_scene restarts it) or use stop_scene." % [scene, ": " + reason if not reason.is_empty() else ""])
	elif _state.has("stopped"):
		lines.append("%s: the game ended by itself before %.1f s." % [scene, seconds])
	else:
		lines.append("%s: ran for %.1f s and is still running (capture_game_frame to see it, stop_scene to close it)." % [scene, seconds])
	if not inputs.is_empty():
		if _state.has("inputs_done"):
			lines.append("Inputs: %d of %d events played." % [_state.inputs_done, inputs.size()])
		elif _state.has("ready"):
			lines.append("Inputs: %d events sent; they did not finish in time." % inputs.size())
	for note: String in notes:
		lines.append(note)
	for problem: Variant in _state.get("problems", []):
		lines.append("Probe: %s" % problem)

	var entries := errors.entries_since(since)
	if entries.is_empty():
		lines.append("No errors or warnings.")
	else:
		lines.append("Errors and warnings (%d):" % entries.size())
		for entry: Dictionary in entries.slice(maxi(entries.size() - ERROR_LIMIT, 0)):
			lines.append("  " + ErrorCollector.format_entry(entry))
	var output := _output_delta(output_before, errors.output_text())
	if not output.is_empty():
		lines.append("Output:")
		lines.append(output)
	lines.append_array(_extra_lines())
	lines.append("get_errors mark: %d" % errors.mark())
	return "\n".join(lines)


## Lo que traen todas las respuestas: errores salteados, hallazgos de los detectores y tiempo restante.
func _extra_lines() -> PackedStringArray:
	var lines: PackedStringArray = []
	if not _continued.is_empty():
		lines.append("Script errors the game went past (%d):" % _continued.size())
		for reason: String in _continued:
			lines.append("  " + reason)
		_continued = []
	var silenced := PlaytestMemory.new().not_a_bug()
	for signature: String in _findings_new:
		if not signature in silenced:
			lines.append(format_finding(_findings[signature]))
	_findings_new = []
	if playtest_deadline_ms > 0:
		var left := (playtest_deadline_ms - Time.get_ticks_msec()) / 60000.0
		lines.append("Playtest time left: %.1f min." % left if left > 0.0 else "The playtest's time is up: answer now with what you have.")
	return lines


## La línea de un hallazgo en el resultado de una tool; ReviewStore la vuelve a leer para el panel.
static func format_finding(finding: Dictionary) -> String:
	var parts: PackedStringArray = ["Detector %s ×%d [sig=%s]: %s" % [finding.get("detector", "?"), int(finding.get("count", 1)), finding.get("signature", ""), finding.get("summary", "")]]
	for key: String in ["node", "scene", "frame"]:
		if not str(finding.get(key, "")).is_empty():
			parts.append("%s=%s" % [key, finding[key]])
	if finding.get("where") is Array and not (finding.where as Array).is_empty():
		parts.append("where=%s" % JSON.stringify(finding.where))
	return " | ".join(parts)


## Lo nuevo del panel Output; si el editor lo limpió al correr ("Clear on play"), todo.
static func _output_delta(before: String, after: String) -> String:
	var text := after.substr(before.length()) if after.begins_with(before) else after
	var kept: PackedStringArray = []
	for line: String in text.split("\n"):
		if not line.strip_edges().is_empty():
			kept.append(line)
	if kept.size() > OUTPUT_LINE_LIMIT:
		var skipped := kept.size() - OUTPUT_LINE_LIMIT
		kept = kept.slice(skipped)
		kept.insert(0, "(… %d earlier lines)" % skipped)
	return "\n".join(kept)


# --- juego en ejecución (m4-07) ------------------------------------------------------------------

func _game_tree(args: Dictionary) -> Dictionary:
	return await _game_request("tree", {"path": McpTool.str_arg(args, "path"), "depth": int(args.get("depth", 4))})


func _game_get(args: Dictionary) -> Dictionary:
	var properties: Variant = args.get("properties", [])
	if not properties is Array:
		return McpTool.error("`properties` must be a list of property names.")
	return await _game_request("get", {"path": McpTool.str_arg(args, "path"), "properties": properties})


func _game_set(args: Dictionary) -> Dictionary:
	if not args.get("properties") is Dictionary or (args.properties as Dictionary).is_empty():
		return McpTool.error("`properties` must be an object {name: value}.")
	return await _game_request("set", {"path": McpTool.str_arg(args, "path"), "properties": args.properties})


func _game_call(args: Dictionary) -> Dictionary:
	var call_args: Variant = args.get("args", [])
	if not call_args is Array:
		return McpTool.error("`args` must be a list.")
	return await _game_request("call", {"path": McpTool.str_arg(args, "path"), "method": McpTool.str_arg(args, "method"), "args": call_args})


func _game_wait(args: Dictionary) -> Dictionary:
	var timeout := clampf(float(args.get("timeout", 5.0)), 0.0, WAIT_MAX_S)
	var params := {"path": McpTool.str_arg(args, "path"), "condition": McpTool.str_arg(args, "condition"), "signal": McpTool.str_arg(args, "signal"), "timeout": timeout}
	return await _game_request("wait", params, timeout)


func _game_find(args: Dictionary) -> Dictionary:
	return await _game_request("find", {"class": McpTool.str_arg(args, "class"), "name": McpTool.str_arg(args, "name"), "limit": McpTool.int_arg(args, "limit", 50)})


func _game_ui(_args: Dictionary) -> Dictionary:
	return await _game_request("ui", {})


func _game_ui_act(args: Dictionary) -> Dictionary:
	return await _game_request("ui_act", {"id": McpTool.str_arg(args, "id"), "action": McpTool.str_arg(args, "action", "click"), "value": args.get("value")})


func _game_script(args: Dictionary) -> Dictionary:
	var code := McpTool.str_arg(args, "code")
	var blocked := blocked_api(code)
	if not blocked.is_empty():
		return McpTool.error("game_script can't use %s: it may not touch files or start processes. Use it to play and to read the game." % blocked)
	var timeout := clampf(float(args.get("timeout", 10.0)), 0.1, SCRIPT_MAX_S)
	# Un error en el script del agente no tiene que frenar el juego en el debugger.
	var before := _continue_errors
	_continue_errors = true
	var result := await _game_request("script", {"code": code, "timeout": timeout}, timeout)
	_continue_errors = before
	return result


## La API prohibida que usa un script, o "".
static func blocked_api(code: String) -> String:
	var found := RegEx.create_from_string(SCRIPT_BLOCKED).search(code)
	return found.get_string(0) if found else ""


func _game_pause(args: Dictionary) -> Dictionary:
	return await _game_request("pause", {"paused": args.get("paused") == true})


func _game_step(args: Dictionary) -> Dictionary:
	var steps: Array = []
	var raw: Variant = args.get("steps", [])
	if raw is Array and not (raw as Array).is_empty() and not (raw as Array).any(func(step: Variant) -> bool: return step is Dictionary and step.has("frame")):
		raw = (raw as Array).duplicate(true)
		if raw[0] is Dictionary:
			raw[0]["frame"] = 0  # acá todo va por frame: el resto sigue después de este
	var invalid := normalize_steps(raw, steps)
	if not invalid.is_empty():
		return McpTool.error(invalid)
	var frames := clampi(McpTool.int_arg(args, "frames", 1), 0, FRAME_MAX)
	var duration := float(frames) / physics_fps()
	for step: Dictionary in steps:
		duration = maxf(duration, step_seconds(step))
	return await _game_request("step", {"frames": frames, "steps": steps}, duration)


func _game_watch(args: Dictionary) -> Dictionary:
	var steps: Array = []
	var invalid := normalize_steps(args.get("steps"), steps)
	if not invalid.is_empty():
		return McpTool.error(invalid)
	var seconds := clampf(float(args.get("seconds", 2.0)), 0.05, WATCH_MAX_S)
	return await _game_request("watch", {"paths": args.get("paths", []), "seconds": seconds, "properties": args.get("properties", []), "steps": steps}, seconds)


func _game_frames(args: Dictionary) -> Dictionary:
	if args.has("fps") and float(args.fps) > 0.0:
		if not EditorInterface.is_playing_scene() or not debugger.has_probe():
			return McpTool.error(NO_PROBE)
		return McpTool.text(await _start_film(float(args.fps)))
	if _film_frames.is_empty():
		return McpTool.error("There are no frames: launch the game with run_scene film_fps, or pass `fps` here to start filming.")
	var seconds := float(args.get("seconds", 3.0))
	var count := clampi(McpTool.int_arg(args, "count", 6), 1, FRAMES_MAX_SHOWN)
	var content: Array = []
	var chosen := pick_frames(_film_frames, seconds, count)
	for frame: Dictionary in chosen:
		var bytes := FileAccess.get_file_as_bytes(frame.path)
		if not bytes.is_empty():
			content.append({"type": "text", "text": "t=%.2f %s" % [frame.t, frame.path]})
			content.append({"type": "image", "mimeType": "image/jpeg", "data": Marshalls.raw_to_base64(bytes)})
	return {"content": content, "isError": false}


## `count` frames repartidos en los últimos `seconds` de la lista.
static func pick_frames(frames: Array[Dictionary], seconds: float, count: int) -> Array[Dictionary]:
	var last: float = frames[-1].t
	var recent := frames.filter(func(frame: Dictionary) -> bool: return float(frame.t) >= last - seconds)
	var picked: Array[Dictionary] = []
	if recent.size() <= count:
		picked.assign(recent)
		return picked
	for i: int in count:
		picked.append(recent[roundi(float(i) * (recent.size() - 1) / maxi(count - 1, 1))])
	return picked


## Empieza a filmar: carpeta nueva para este run. Devuelve la línea para el reporte.
func _start_film(fps: float) -> String:
	var stamp := Time.get_datetime_string_from_system().replace(":", "-").replace("T", "_")
	_film_dir = RECORD_DIR.path_join("film_%s" % stamp)
	_film_frames = []
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_film_dir))
	var manifest := FileAccess.open(_film_dir.path_join("film.json"), FileAccess.WRITE)
	if manifest:
		manifest.store_string(JSON.stringify({"fps": fps}))
		manifest.close()
	_keep_newest(RECORD_DIR, "film_", FILM_KEEP_RUNS)
	var reply := await request("film", {"fps": fps})
	return "Filming: %s" % _film_dir if reply.has("text") else "Not filming: %s" % reply.get("error", "")


func _game_input(args: Dictionary) -> Dictionary:
	var steps: Array = []
	var invalid := normalize_steps(args.get("steps"), steps)
	if not invalid.is_empty():
		return McpTool.error(invalid)
	if steps.is_empty():
		return McpTool.error("`steps` is empty. " + STEPS_HELP)
	var settle := clampi(int(args.get("settle_frames", 0)), 0, FRAME_MAX)
	var duration := float(settle) / physics_fps()
	for step: Dictionary in steps:
		duration = maxf(duration, step_seconds(step) + float(settle) / physics_fps())
	return await _game_request("input", {"steps": steps, "settle_frames": settle}, duration)


## Cuándo sale un paso del probe, en segundos (`frame` a los frames de física por segundo del proyecto).
static func step_seconds(step: Dictionary) -> float:
	return float(step.frame) / physics_fps() if step.has("frame") else float(step.get("t", 0.0))


static func physics_fps() -> float:
	return maxf(float(ProjectSettings.get_setting("physics/common/physics_ticks_per_second", 60)), 1.0)


## Manda un pedido al probe y arma el resultado con su respuesta y los errores nuevos del juego.
func _game_request(op: String, params: Dictionary, duration_s: float = 0.0) -> Dictionary:
	if not EditorInterface.is_playing_scene() or not debugger.has_probe():
		return McpTool.error(NO_PROBE)
	if _stopped_in_debugger():
		return McpTool.error("The game is stopped in the debugger (%s): fix the error and run it again, or continue it from the Debugger." % PlaytestDebugger.break_reason())
	var since := errors.mark()
	var reply := await request(op, params, duration_s + REQUEST_TIMEOUT_S)
	var lines: PackedStringArray = [str(reply.get("text", ""))] if not reply.has("error") else []
	# Los errores de la pausa se anotan unos frames después de que llega la respuesta.
	if _continue_errors:
		await (Engine.get_main_loop() as SceneTree).process_frame
	lines.append_array(_extra_lines())
	var entries := errors.entries_since(since).filter(func(entry: Dictionary) -> bool: return entry.source == "game")
	if not entries.is_empty():
		lines.append("Game errors and warnings (%d):" % entries.size())
		for entry: Dictionary in entries.slice(maxi(entries.size() - ERROR_LIMIT, 0)):
			lines.append("  " + ErrorCollector.format_entry(entry))
	if reply.has("error"):
		lines.insert(0, str(reply.error))
		return McpTool.error("\n".join(lines))
	return McpTool.text("\n".join(lines))


## Pedido al probe: {text} o {error}.
func request(op: String, params: Dictionary, timeout_s: float = REQUEST_TIMEOUT_S) -> Dictionary:
	var id := _next_request
	_next_request += 1
	if not debugger.send("request", [id, op, params]):
		return {"error": NO_PROBE}
	await _until(func() -> bool: return _replies.has(id) or not debugger.has_probe() or _stopped_in_debugger(), timeout_s)
	if _replies.has(id):
		var reply: Dictionary = _replies[id]
		_replies.erase(id)
		return reply
	if _stopped_in_debugger():
		return {"error": "The game stopped in the debugger before answering: %s" % PlaytestDebugger.break_reason()}
	if not debugger.has_probe():
		return {"error": "The game closed before answering."}
	return {"error": "The game did not answer within %d s." % ceili(timeout_s)}


## Parado en el debugger sin que este run lo vaya a sacar de ahí.
func _stopped_in_debugger() -> bool:
	return debugger.is_breaked() and not _continue_errors


func _until(condition: Callable, timeout_s: float) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var deadline := Time.get_ticks_msec() + int(timeout_s * 1000.0)
	while not condition.call() and Time.get_ticks_msec() < deadline:
		await tree.process_frame


func _cleanup() -> void:
	if cleanup.is_valid():
		cleanup.call()
