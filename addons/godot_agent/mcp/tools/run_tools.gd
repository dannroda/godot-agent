@tool
extends RefCounted
## Tools de ejecución (spec §6): run_scene, stop_scene y capture_game_frame.
## El juego es otro proceso: el probe de playtest (autoload temporal) captura frames y reproduce
## inputs por el canal del debugger. El autoload se da de alta en EditorPlugin._build() solo si el
## run lo pidió el harness (`harness_requested`) y de baja cuando el juego ya leyó project.godot.

const McpTool := preload("../mcp_tool.gd")
const ErrorCollector := preload("../../core/error_collector.gd")
const PlaytestDebugger := preload("../../playtest/playtest_debugger.gd")
const PermissionPolicy := preload("../../session/permission_policy.gd")

const MAX_SECONDS := 120.0
const STARTUP_TIMEOUT_S := 20.0
const FRAME_TIMEOUT_S := 5.0
const STOP_TIMEOUT_S := 5.0
## Margen para que lleguen al editor los últimos errores y el Output del juego.
const SETTLE_S := 0.5
const OUTPUT_LINE_LIMIT := 150
const ERROR_LIMIT := 100

var errors: ErrorCollector
var debugger: PlaytestDebugger
var max_image_side: int = 1280
## Lo lee EditorPlugin._build(): este run lo pidió el harness y lleva el autoload de playtest.
var harness_requested: bool = false
## Quita el autoload si el juego no llegó a arrancar (lo inyecta el plugin).
var cleanup: Callable

var _busy: bool = false
var _state: Dictionary = {}


func setup(collector: ErrorCollector, playtest_debugger: PlaytestDebugger) -> void:
	errors = collector
	debugger = playtest_debugger
	debugger.session_started.connect(func() -> void: _state["started"] = true)
	debugger.session_stopped.connect(func() -> void: _state["stopped"] = true)
	debugger.session_breaked.connect(func() -> void: _state["breaked"] = true)
	debugger.probe_ready.connect(func() -> void: _state["ready"] = true)
	debugger.inputs_done.connect(func(count: int) -> void: _state["inputs_done"] = count)
	debugger.problem_reported.connect(func(text: String) -> void: (_state.get_or_add("problems", []) as Array).append(text))
	debugger.frame_received.connect(func(png: PackedByteArray, _w: int, _h: int) -> void: _state["frame"] = png)


func tools() -> Array:
	var run := PermissionPolicy.GROUP_RUN
	return [
		McpTool.create("run_scene", run,
			"Runs a scene (default: the open one), waits `seconds` or until it ends, and returns the game's errors and Output. The game keeps running afterwards: capture_game_frame to see it, stop_scene to close it. Saves the scenes before running.",
			{
				"scene": {"type": "string", "description": "res://…tscn path (default: the open scene)"},
				"seconds": {"type": "number", "description": "Seconds to wait after the game starts (max. 120)"},
				"inputs": {"type": "array", "description": "Steps {t: seconds since the game started, action: InputMap action, pressed: bool}",
					"items": {"type": "object", "properties": {"t": {"type": "number"}, "action": {"type": "string"}, "pressed": {"type": "boolean"}}, "required": ["t", "action"]}},
			},
			["seconds"], _run_scene),
		McpTool.create("stop_scene", run, "Stops the running game.", {}, [], _stop_scene),
		McpTool.create("capture_game_frame", run, "Captures the current frame of the running game (launched with run_scene) as a PNG.", {}, [], _capture_game_frame),
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
	var invalid := _validate_inputs(args.get("inputs", []), inputs)
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


## Llena `out` con los pasos normalizados; devuelve "" o el error.
static func _validate_inputs(value: Variant, out: Array) -> String:
	if value == null:
		return ""
	if not value is Array:
		return "`inputs` must be a list of {t, action, pressed}."
	for step: Variant in value:
		if not step is Dictionary or not step.get("action") is String or not (step.get("t") is float or step.get("t") is int):
			return "Each `inputs` step needs `t` (number) and `action` (text): %s" % JSON.stringify(step).left(120)
		var action: String = step.action
		if not ProjectSettings.has_setting("input/" + action) and not InputMap.has_action(action):
			return "The action '%s' does not exist in the project's InputMap." % action
		out.append({"t": maxf(float(step.t), 0.0), "action": action, "pressed": step.get("pressed", true) == true})
	return ""


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
			lines.append("Inputs: %d of %d played." % [_state.inputs_done, inputs.size()])
		elif _state.has("ready"):
			lines.append("Inputs: %d sent; they did not finish in time." % inputs.size())
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


func _until(condition: Callable, timeout_s: float) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var deadline := Time.get_ticks_msec() + int(timeout_s * 1000.0)
	while not condition.call() and Time.get_ticks_msec() < deadline:
		await tree.process_frame


func _cleanup() -> void:
	if cleanup.is_valid():
		cleanup.call()
