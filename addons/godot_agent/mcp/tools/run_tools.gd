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
			"Corre una escena (default: la abierta), espera `seconds` o a que termine y devuelve los errores y el Output del juego. El juego sigue corriendo después: capture_game_frame para verlo, stop_scene para cerrarlo. Guarda las escenas antes de correr.",
			{
				"scene": {"type": "string", "description": "Ruta res://…tscn (default: la escena abierta)"},
				"seconds": {"type": "number", "description": "Segundos a esperar desde que arranca el juego (máx. 120)"},
				"inputs": {"type": "array", "description": "Pasos {t: segundos desde que arranca, action: acción del InputMap, pressed: bool}",
					"items": {"type": "object", "properties": {"t": {"type": "number"}, "action": {"type": "string"}, "pressed": {"type": "boolean"}}, "required": ["t", "action"]}},
			},
			["seconds"], _run_scene),
		McpTool.create("stop_scene", run, "Detiene el juego que está corriendo.", {}, [], _stop_scene),
		McpTool.create("capture_game_frame", run, "Captura el frame actual del juego corriendo (lanzado con run_scene) como PNG.", {}, [], _capture_game_frame),
	]


func _run_scene(args: Dictionary) -> Dictionary:
	if _busy:
		return McpTool.error("Ya hay un run_scene en curso: esperá a que termine.")
	var scene := McpTool.str_arg(args, "scene")
	if scene.is_empty():
		var root := EditorInterface.get_edited_scene_root()
		if root == null:
			return McpTool.error("No hay ninguna escena abierta: pasá `scene`.")
		scene = root.scene_file_path
		if scene.is_empty():
			return McpTool.error("La escena abierta nunca se guardó: guardala con save_scene o pasá `scene`.")
	elif not scene.begins_with("res://") or not ResourceLoader.exists(scene):
		return McpTool.error("No existe la escena %s." % scene)
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
		return McpTool.error("El editor no pudo lanzar %s (¿falló el build de algún plugin?). Probá get_errors." % scene)

	await _until(func() -> bool: return _state.has("ready") or _state.has("stopped") or _state.has("breaked"), STARTUP_TIMEOUT_S)
	var notes: PackedStringArray = []
	if _state.has("ready"):
		if not inputs.is_empty():
			debugger.send("inputs", [inputs])
	elif not _state.has("stopped") and not _state.has("breaked"):
		notes.append("El probe de playtest no respondió en %d s: sin inputs ni capturas." % STARTUP_TIMEOUT_S)
	await _until(func() -> bool: return _state.has("stopped") or _state.has("breaked"), seconds)
	await Engine.get_main_loop().create_timer(SETTLE_S).timeout
	if not _state.has("started"):
		_cleanup()
	var report := _report(scene, seconds, inputs, notes, since, output_before)
	_busy = false
	return McpTool.text(report)


func _stop_scene(_args: Dictionary) -> Dictionary:
	if not EditorInterface.is_playing_scene():
		return McpTool.text("No hay ningún juego corriendo.")
	EditorInterface.stop_playing_scene()
	await _until(func() -> bool: return not EditorInterface.is_playing_scene(), STOP_TIMEOUT_S)
	_cleanup()
	return McpTool.text("Juego detenido.")


func _capture_game_frame(_args: Dictionary) -> Dictionary:
	if not EditorInterface.is_playing_scene() or not debugger.has_probe():
		return McpTool.error("No hay un juego corriendo con el probe de playtest: lanzalo con run_scene (los runs manuales no lo llevan).")
	_state.erase("frame")
	debugger.send("capture", [max_image_side])
	await _until(func() -> bool: return _state.has("frame"), FRAME_TIMEOUT_S)
	if not _state.has("frame"):
		var paused := " El juego está detenido en el debugger." if _state.has("breaked") else ""
		return McpTool.error("No llegó el frame del juego en %d s.%s" % [FRAME_TIMEOUT_S, paused])
	var image := Image.new()
	if image.load_png_from_buffer(_state.frame) != OK:
		return McpTool.error("El frame del juego llegó roto.")
	return McpTool.image(image, "Frame del juego (%dx%d)" % [image.get_width(), image.get_height()])


## Llena `out` con los pasos normalizados; devuelve "" o el error.
static func _validate_inputs(value: Variant, out: Array) -> String:
	if value == null:
		return ""
	if not value is Array:
		return "`inputs` tiene que ser una lista de {t, action, pressed}."
	for step: Variant in value:
		if not step is Dictionary or not step.get("action") is String or not (step.get("t") is float or step.get("t") is int):
			return "Cada paso de `inputs` necesita `t` (número) y `action` (texto): %s" % JSON.stringify(step).left(120)
		var action: String = step.action
		if not ProjectSettings.has_setting("input/" + action) and not InputMap.has_action(action):
			return "La acción '%s' no existe en el InputMap del proyecto." % action
		out.append({"t": maxf(float(step.t), 0.0), "action": action, "pressed": step.get("pressed", true) == true})
	return ""


func _report(scene: String, seconds: float, inputs: Array, notes: PackedStringArray, since: int, output_before: String) -> String:
	var lines: PackedStringArray = []
	if _state.has("breaked"):
		var reason := PlaytestDebugger.break_reason()
		lines.append("%s: el juego se detuvo en el debugger por un error%s. Sigue pausado: corregí y volvé a correr (run_scene lo reinicia) o usá stop_scene." % [scene, ": " + reason if not reason.is_empty() else ""])
	elif _state.has("stopped"):
		lines.append("%s: el juego terminó solo antes de %.1f s." % [scene, seconds])
	else:
		lines.append("%s: corrió %.1f s y sigue corriendo (capture_game_frame para verlo, stop_scene para cerrarlo)." % [scene, seconds])
	if not inputs.is_empty():
		if _state.has("inputs_done"):
			lines.append("Inputs: %d de %d reproducidos." % [_state.inputs_done, inputs.size()])
		elif _state.has("ready"):
			lines.append("Inputs: enviados %d; no terminaron dentro del tiempo." % inputs.size())
	for note: String in notes:
		lines.append(note)
	for problem: Variant in _state.get("problems", []):
		lines.append("Probe: %s" % problem)

	var entries := errors.entries_since(since)
	if entries.is_empty():
		lines.append("Sin errores ni warnings.")
	else:
		lines.append("Errores y warnings (%d):" % entries.size())
		for entry: Dictionary in entries.slice(maxi(entries.size() - ERROR_LIMIT, 0)):
			lines.append("  " + ErrorCollector.format_entry(entry))
	var output := _output_delta(output_before, errors.output_text())
	if not output.is_empty():
		lines.append("Output:")
		lines.append(output)
	lines.append("marca de get_errors: %d" % errors.mark())
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
		kept.insert(0, "(… %d líneas anteriores)" % skipped)
	return "\n".join(kept)


func _until(condition: Callable, timeout_s: float) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var deadline := Time.get_ticks_msec() + int(timeout_s * 1000.0)
	while not condition.call() and Time.get_ticks_msec() < deadline:
		await tree.process_frame


func _cleanup() -> void:
	if cleanup.is_valid():
		cleanup.call()
