@tool
extends RefCounted
## m13-27: prueba en runtime del workaround para leer el profiler de scripts desde un plugin.
## El editor no pasa servers:profile_frame a EditorDebuggerPlugin._capture (tiene handler propio),
## pero el ScriptEditorDebugger interno emite `debug_data(msg, data)` para todo mensaje. El check:
## - encuentra los ScriptEditorDebugger del editor y se conecta a `debug_data`;
## - corre tests/fixtures/profile_fixture.tscn y prende el profiler con la API pública
##   (EditorDebuggerSession.toggle_profiler("servers", true, [max_funcs, include_native]));
## - verifica que llegan la firma y los frames de `_hot` y `_step`, con llamadas y tiempos;
## - mide el overhead: el juego cronometra `_hot()` y manda el promedio por ventana con un mensaje
##   propio (profcheck:window), que sí llega por _capture. Antes, durante y después del profiler.
## También confirma la limitación: _capture("servers…") no recibe nada aunque lo pida.

const SCENE := "res://tests/fixtures/profile_fixture.tscn"
const FIXTURE_SCRIPT := "res://tests/fixtures/profile_fixture.gd"
const CALLS_PER_FRAME := 2000
const MAX_FUNCS := 256
const RUN_ARGS_ENV := "GODOT_AGENT_TEST_RUN_ARGS"
const RUN_ARGS_SETTING := "editor/run/main_run_args"
const TIMEOUT_MS := 30000
## Ventanas (de 20 frames) que se promedian en cada fase; la primera de cada fase se descarta.
const WINDOWS_PER_PHASE := 6


class ProfileCapture extends EditorDebuggerPlugin:
	var windows: Array[float] = []
	var servers_captured := 0

	func _has_capture(prefix: String) -> bool:
		return prefix == "profcheck" or prefix == "servers"

	func _capture(message: String, data: Array, _session_id: int) -> bool:
		if message == "profcheck:window":
			windows.append(float(data[0]))
			return true
		if message.begins_with("servers:"):
			servers_captured += 1
		return false


var report: Dictionary = {}
var _tree: SceneTree
var _failures: PackedStringArray = []
var _signatures: Dictionary = {}  # id → "res://ruta.gd::línea::nombre"
var _frames: Array[Array] = []
var _total: Array = []
var _debugger_of_frames: Node


func run(tree: SceneTree, editor_plugin: EditorPlugin) -> PackedStringArray:
	_tree = tree
	var capture := ProfileCapture.new()
	editor_plugin.add_debugger_plugin(capture)
	var debuggers := EditorInterface.get_base_control().find_children("*", "ScriptEditorDebugger", true, false)
	report.engine = Engine.get_version_info().string
	report.debuggers = debuggers.size()
	var connected: Array[Node] = []
	for dbg: Node in debuggers:
		if dbg.has_signal(&"debug_data"):
			dbg.connect(&"debug_data", _on_debug_data.bind(dbg))
			connected.append(dbg)
	if connected.is_empty():
		_failures.append("no hay ScriptEditorDebugger con la señal debug_data (%d nodos): cambió la clase interna" % debuggers.size())
		editor_plugin.remove_debugger_plugin(capture)
		return _failures
	var previous_args: Variant = ProjectSettings.get_setting(RUN_ARGS_SETTING, "")
	if not OS.get_environment(RUN_ARGS_ENV).is_empty():
		ProjectSettings.set_setting(RUN_ARGS_SETTING, OS.get_environment(RUN_ARGS_ENV))
	await _profile(capture)
	if EditorInterface.is_playing_scene():
		EditorInterface.stop_playing_scene()
	for dbg: Node in connected:
		if is_instance_valid(dbg):
			dbg.disconnect(&"debug_data", _on_debug_data)
	editor_plugin.remove_debugger_plugin(capture)
	ProjectSettings.set_setting(RUN_ARGS_SETTING, previous_args)
	ProjectSettings.save()
	print("[profile-check] ", JSON.stringify(report))
	return _failures


func _profile(capture: ProfileCapture) -> void:
	EditorInterface.play_custom_scene(SCENE)
	var session: EditorDebuggerSession = null
	var deadline := Time.get_ticks_msec() + TIMEOUT_MS
	while session == null and Time.get_ticks_msec() < deadline:
		for candidate: EditorDebuggerSession in capture.get_sessions():
			if candidate.is_active():
				session = candidate
		await _tree.process_frame
	if session == null:
		_failures.append("el juego no abrió una sesión del debugger")
		return
	report.session_id = capture.get_sessions().find(session)

	# Fase 1: sin profiler.
	if not await _wait_windows(capture, WINDOWS_PER_PHASE):
		_failures.append("el juego no mandó sus tiempos (profcheck:window) sin profiler")
		return
	var base := _mean(capture.windows.slice(1))
	var mark := capture.windows.size()

	# Fase 2: profiler prendido con la API pública.
	session.toggle_profiler("servers", true, [MAX_FUNCS, false])
	if not await _wait_windows(capture, mark + WINDOWS_PER_PHASE):
		_failures.append("con el profiler prendido el juego dejó de mandar sus tiempos")
		return
	var profiled := _mean(capture.windows.slice(mark + 1))
	mark = capture.windows.size()

	# Fase 3: apagado. El juego manda el acumulado en servers:profile_total.
	session.toggle_profiler("servers", false, [])
	await _wait_windows(capture, mark + WINDOWS_PER_PHASE)
	var after := _mean(capture.windows.slice(mark + 1))

	report.hot_us_without_profiler = snappedf(base, 0.1)
	report.hot_us_with_profiler = snappedf(profiled, 0.1)
	report.hot_us_after_profiler = snappedf(after, 0.1)
	var reference := (base + after) / 2.0
	report.overhead_ratio = snappedf(profiled / reference, 0.01) if reference > 0 else 0.0
	report.overhead_ns_per_call = snappedf((profiled - reference) * 1000.0 / (CALLS_PER_FRAME + 1), 0.1)
	report.frames = _frames.size()
	report.servers_messages_seen_by_capture = capture.servers_captured
	if capture.servers_captured > 0:
		# No es falla: si un Godot nuevo los pasa a _capture, el workaround ya no hace falta.
		report.note = "_capture recibió mensajes servers:*: el editor ya los pasa a los plugins"
	if _debugger_of_frames and report.session_id != _debugger_of_frames.get_index():
		_failures.append("los frames llegaron por el ScriptEditorDebugger %d, la sesión es la %d" % [_debugger_of_frames.get_index(), report.session_id])
	_check_frames()


func _check_frames() -> void:
	if _frames.is_empty():
		_failures.append("no llegó ningún servers:profile_frame por debug_data")
		return
	var hot_id := _signature_id("_hot")
	var step_id := _signature_id("_step")
	report.signatures = {"_hot": _signatures.get(hot_id, ""), "_step": _signatures.get(step_id, "")}
	if hot_id < 0 or step_id < 0:
		_failures.append("faltan firmas de _hot/_step: %s" % JSON.stringify(_signatures.values()))
		return
	var frames_with_step := 0
	var wrong_counts: Array[int] = []
	var hot_self := 0.0
	var hot_total := 0.0
	var step_self := 0.0
	var step_total := 0.0
	# El primer frame con el profiler prendido es basura (Godot 4.7/4.8): el toggle llega a mitad de
	# `_hot` y las llamadas en curso, que empezaron sin profiler (function_start_time = 0), se miden
	# como `ticks_usec() - 0`: cientos de ms. También entra en servers:profile_total. Se descarta y se
	# informa; godot.profile_run tiene que hacer lo mismo.
	var first := _script_functions(_frames[0])
	if first.has(step_id) and first[step_id].calls != CALLS_PER_FRAME:
		report.first_frame_artifact = {"step_calls": first[step_id].calls, "step_total_s": first[step_id].total}
		_frames.remove_at(0)
	for frame: Array in _frames:
		var functions := _script_functions(frame)
		if functions.has(step_id):
			frames_with_step += 1
			var step: Dictionary = functions[step_id]
			if step.calls != CALLS_PER_FRAME:
				wrong_counts.append(step.calls)
			step_self += step.self
			step_total += step.total
			if step.total + 1e-9 < step.self or step.total > 0.1:
				_failures.append("_step con total < self: %s" % step)
		if functions.has(hot_id):
			var hot: Dictionary = functions[hot_id]
			if hot.calls != 1:
				wrong_counts.append(hot.calls)
			hot_self += hot.self
			hot_total += hot.total
	report.frames_with_step = frames_with_step
	if OS.get_environment("PROFILE_CHECK_DUMP") == "1":
		for frame: Array in _frames.slice(0, 4) + _frames.slice(-3):
			print("[profile-check] frame ", frame.slice(0, 7), " ", _script_functions(frame))
	if frames_with_step < 10:
		_failures.append("_step apareció en %d frames de %d" % [frames_with_step, _frames.size()])
		return
	if not wrong_counts.is_empty():
		_failures.append("llamadas por frame distintas de 1 (_hot) y %d (_step): %s" % [CALLS_PER_FRAME, wrong_counts.slice(0, 10)])
	var n := float(frames_with_step)
	report.step_ms_per_frame = {"self": snappedf(step_self * 1000.0 / n, 0.001), "total": snappedf(step_total * 1000.0 / n, 0.001)}
	report.hot_ms_per_frame = {"self": snappedf(hot_self * 1000.0 / n, 0.001), "total": snappedf(hot_total * 1000.0 / n, 0.001)}
	if step_self <= 0.0 or hot_self <= 0.0:
		_failures.append("tiempos propios en cero: _hot %f, _step %f" % [hot_self, step_self])
	if hot_total + 1e-6 < step_total:
		_failures.append("el total de _hot (%f) es menor que el de _step (%f), que llama" % [hot_total, step_total])
	if _total.is_empty():
		_failures.append("no llegó servers:profile_total al apagar el profiler")
	else:
		var total_functions := _script_functions(_total)
		if total_functions.has(step_id):
			report.total_step = total_functions[step_id]


func _on_debug_data(message: String, data: Array, dbg: Node) -> void:
	match message:
		"servers:function_signature":
			_signatures[int(data[1])] = str(data[0])
		"servers:profile_frame":
			_frames.append(data)
			_debugger_of_frames = dbg
		"servers:profile_total":
			_total = data


func _signature_id(function_name: String) -> int:
	for id: int in _signatures:
		var signature: String = _signatures[id]
		if signature.begins_with(FIXTURE_SCRIPT + "::") and signature.ends_with("::" + function_name):
			return id
	return -1


## Las funciones de script de un ServersProfilerFrame serializado (servers_debugger.cpp):
## [frame, frame_time, process, physics, physics_frame, script_time, n_servers,
##  (nombre, 2*n, (fn, t)…)…, 5*n_funcs, (sig_id, calls, self, total, internal)…], tiempos en s.
static func _script_functions(frame: Array) -> Dictionary:
	var result := {}
	if frame.size() < 8:
		return result
	var idx := 7
	for i in int(frame[6]):
		idx += 2 + int(frame[idx + 1])
	var size := int(frame[idx])
	idx += 1
	for i in size / 5:
		result[int(frame[idx])] = {"calls": int(frame[idx + 1]), "self": float(frame[idx + 2]), "total": float(frame[idx + 3]), "internal": float(frame[idx + 4])}
		idx += 5
	return result


func _wait_windows(capture: ProfileCapture, count: int) -> bool:
	var deadline := Time.get_ticks_msec() + TIMEOUT_MS
	while capture.windows.size() < count:
		if Time.get_ticks_msec() > deadline:
			return false
		await _tree.process_frame
	return true


static func _mean(values: Array) -> float:
	if values.is_empty():
		return 0.0
	var sum := 0.0
	for value: float in values:
		sum += value
	return sum / values.size()
