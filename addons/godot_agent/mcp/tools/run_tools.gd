@tool
extends RefCounted
## Tools de ejecución (spec §6): run_scene, stop_scene, capture_game_frame y, con el juego
## corriendo, game_tree, game_get, game_set, game_call, game_wait y game_input (m4-07, D54).
## El juego es otro proceso: el probe de playtest (autoload temporal) captura frames, reproduce
## inputs y contesta pedidos (`request` → `reply` con id) por el canal del debugger. El autoload se da de alta en EditorPlugin._build() solo si el
## run lo pidió el harness (`harness_requested`) y de baja cuando el juego ya leyó project.godot.

const McpTool := preload("../mcp_tool.gd")
const ErrorCollector := preload("../../editor/error_collector.gd")
const PlaytestDebugger := preload("../../playtest/playtest_debugger.gd")
const PermissionPolicy := preload("../../session/permission_policy.gd")
const ProjectTools := preload("project_tools.gd")

## Las del juego en ejecución: extendidas con tools/list compacto (D56).
const GAME_TOOLS: PackedStringArray = ["game_tree", "game_get", "game_set", "game_call", "game_wait", "game_input"]
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
const NO_PROBE := "No game is running with the playtest probe: launch it with run_scene (manual runs have it only with «Use the playtest autoload also when running the game manually» in Settings → MCP server)."
const STEPS_HELP := "Each step is one of {action: \"jump\"}, {key: \"Space\" | \"Ctrl+S\"}, {event: \"joy_button:a\" | \"joy_axis:left_x:-\"}, {click: [x, y], button: \"left|right|middle\"} or {move: [x, y]} (window pixels), with optional t (seconds from the start; default: right after the previous step), pressed (true: only press, false: only release; default: press and release after `hold` seconds, 0.1)."

var errors: ErrorCollector
var debugger: PlaytestDebugger
var max_image_side: int = 1280
## Lo lee EditorPlugin._build(): este run lo pidió el harness y lleva el autoload de playtest.
var harness_requested: bool = false
## Quita el autoload si el juego no llegó a arrancar (lo inyecta el plugin).
var cleanup: Callable

var _busy: bool = false
var _state: Dictionary = {}
var _replies: Dictionary = {}
var _next_request: int = 1


func setup(collector: ErrorCollector, playtest_debugger: PlaytestDebugger) -> void:
	errors = collector
	debugger = playtest_debugger
	# Métodos y no lambdas: una lambda captura a RunTools, el debugger la guarda en su señal y
	# RunTools guarda al debugger; el ciclo no se libera al deshabilitar el plugin (m13-10).
	debugger.session_started.connect(_flag.bind("started"))
	debugger.session_stopped.connect(_flag.bind("stopped"))
	debugger.session_breaked.connect(_flag.bind("breaked"))
	debugger.probe_ready.connect(_flag.bind("ready"))
	debugger.inputs_done.connect(_on_inputs_done)
	debugger.problem_reported.connect(_on_problem_reported)
	debugger.frame_received.connect(_on_frame_received)
	debugger.reply_received.connect(_on_reply_received)


func _flag(key: String) -> void:
	_state[key] = true


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
		"button": {"type": "string"}, "pressed": {"type": "boolean"}, "hold": {"type": "number"}}}}
	var path_schema := {"type": "string", "description": "Node path in the running game: relative to the current scene (\"Player\", \"HUD/Score\"), \"\" for the scene itself, or absolute (\"/root/GameState\" for an autoload)"}
	return [
		McpTool.create("run_scene", run,
			"Runs a scene (default: the open one), waits `seconds` or until it ends, and returns the game's errors and Output. The game keeps running afterwards: capture_game_frame to see it, stop_scene to close it. Saves the scenes before running.",
			{
				"scene": {"type": "string", "description": "res://…tscn path (default: the open scene)"},
				"seconds": {"type": "number", "description": "Seconds to wait after the game starts (max. 120)"},
				"inputs": steps_schema,
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
			{"steps": steps_schema}, ["steps"], _game_input),
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
	var since := errors.mark()
	var output_before := errors.output_text()
	_state = {}
	harness_requested = true
	EditorInterface.play_custom_scene(scene)  # llama a _build() en el momento
	harness_requested = false
	if not EditorInterface.is_playing_scene():
		_busy = false
		_cleanup()
		return McpTool.error("The editor could not launch %s (did a plugin's build fail?). Try get_errors." % scene)

	await _until(func() -> bool: return _state.has("ready") or _state.has("stopped") or _state.has("breaked"), STARTUP_TIMEOUT_S)
	var notes: PackedStringArray = []
	if _state.has("ready"):
		if not inputs.is_empty():
			debugger.send("inputs", [inputs])
	elif not _state.has("stopped") and not _state.has("breaked"):
		notes.append("The playtest probe did not respond within %d s: no inputs or captures." % STARTUP_TIMEOUT_S)
	await _until(func() -> bool: return _state.has("stopped") or _state.has("breaked"), seconds)
	await Engine.get_main_loop().create_timer(SETTLE_S).timeout
	if not _state.has("started"):
		_cleanup()
	var report := _report(scene, seconds, inputs, notes, since, output_before)
	_busy = false
	return McpTool.text(report)


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
	if (value as Array).size() > INPUT_MAX_STEPS:
		return "At most %d steps per call." % INPUT_MAX_STEPS
	var next_t := 0.0
	for step: Variant in value:
		if not step is Dictionary:
			return "Each step must be an object. " + STEPS_HELP
		var shown := JSON.stringify(step).left(120)
		if step.has("t") and not (step.t is float or step.t is int):
			return "`t` must be a number: %s" % shown
		var t := maxf(float(step.get("t", next_t)), 0.0)
		var hold := clampf(float(step.get("hold", TAP_HOLD_S)), 0.0, WAIT_MAX_S)
		var events: Array = []
		if step.get("action") is String:
			var action: String = step.action
			if not ProjectSettings.has_setting("input/" + action) and not InputMap.has_action(action):
				return "The action '%s' does not exist in the project's InputMap." % action
			events.append({"kind": "action", "action": action})
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
				release["t"] = t + hold
				out.append(release)
		next_t = t + (hold if not step.has("pressed") and not step.has("move") else 0.0) + STEP_GAP_S
	return ""


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
	lines.append("get_errors mark: %d" % errors.mark())
	return "\n".join(lines)


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


func _game_input(args: Dictionary) -> Dictionary:
	var steps: Array = []
	var invalid := normalize_steps(args.get("steps"), steps)
	if not invalid.is_empty():
		return McpTool.error(invalid)
	if steps.is_empty():
		return McpTool.error("`steps` is empty. " + STEPS_HELP)
	var duration := 0.0
	for step: Dictionary in steps:
		duration = maxf(duration, float(step.t))
	return await _game_request("input", {"steps": steps}, duration)


## Manda un pedido al probe y arma el resultado con su respuesta y los errores nuevos del juego.
func _game_request(op: String, params: Dictionary, duration_s: float = 0.0) -> Dictionary:
	if not EditorInterface.is_playing_scene() or not debugger.has_probe():
		return McpTool.error(NO_PROBE)
	if debugger.is_breaked():
		return McpTool.error("The game is stopped in the debugger (%s): fix the error and run it again, or continue it from the Debugger." % PlaytestDebugger.break_reason())
	var since := errors.mark()
	var reply := await request(op, params, duration_s + REQUEST_TIMEOUT_S)
	var lines: PackedStringArray = [str(reply.get("text", ""))] if not reply.has("error") else []
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
	await _until(func() -> bool: return _replies.has(id) or not debugger.has_probe() or debugger.is_breaked(), timeout_s)
	if _replies.has(id):
		var reply: Dictionary = _replies[id]
		_replies.erase(id)
		return reply
	if debugger.is_breaked():
		return {"error": "The game stopped in the debugger before answering: %s" % PlaytestDebugger.break_reason()}
	if not debugger.has_probe():
		return {"error": "The game closed before answering."}
	return {"error": "The game did not answer within %d s." % ceili(timeout_s)}


func _until(condition: Callable, timeout_s: float) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var deadline := Time.get_ticks_msec() + int(timeout_s * 1000.0)
	while not condition.call() and Time.get_ticks_msec() < deadline:
		await tree.process_frame


func _cleanup() -> void:
	if cleanup.is_valid():
		cleanup.call()
