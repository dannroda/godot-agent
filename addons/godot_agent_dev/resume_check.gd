@tool
extends RefCounted
## Reanudar una sesión larga del historial (m7-55): con el agente falso (session/load), mide desde que
## se lee el registro hasta poder escribir, los frames del editor mientras se arma la conversación y
## la memoria que queda. Por defecto, una sesión sintética de SYNTHETIC_EVENTS eventos;
## GODOT_AGENT_RESUME_SOURCE=<.jsonl del historial> usa ese archivo.

const AgentProfile := preload("res://addons/godot_agent/core/agent_profile.gd")
const SessionHistory := preload("res://addons/godot_agent/session/session_history.gd")
const DOCK_SCRIPT := "res://addons/godot_agent/ui/dock/agent_dock.gd"
const SCENARIO_PATH := "user://resume_session.json"
const SESSION_ID := "resume-check-session"
const SYNTHETIC_EVENTS := 20000
## Hasta poder escribir (lo que pide m7-55), con OpenGL por software en Xvfb.
const MAX_READY_MS := 2000
const MAX_FRAME_MS := 400.0
## Lo que queda son las vistas (MAX_VIEWS), no el largo de la sesión: con 20000 eventos sintéticos, ~215 MB.
const MAX_MEMORY_MB := 300.0

var failures: PackedStringArray = []
var report: PackedStringArray = []


func run(tree: SceneTree) -> PackedStringArray:
	var dock: Control = null
	for node: Node in tree.root.find_children("*", "VBoxContainer", true, false):
		if node.get_script() and (node.get_script() as Script).resource_path == DOCK_SCRIPT:
			dock = node
	if dock == null:
		failures.append("no se encontró el dock")
		return failures
	var controller: Object = dock.get(&"_controller")
	var model: Object = dock.get(&"_model")
	var view: Object = dock.get(&"_conversation")
	var history: Object = controller.get(&"history")
	var source := OS.get_environment("GODOT_AGENT_RESUME_SOURCE")
	_install_session(ProjectSettings.globalize_path(str(history.get(&"dir"))), source)
	var file := FileAccess.open(SCENARIO_PATH, FileAccess.WRITE)
	file.store_string(JSON.stringify({"initialize": {"agentCapabilities": {"loadSession": true}}, "turns": []}))
	file.close()
	var profile := AgentProfile.from_dict({
		"id": "fake", "display_name": "Agente falso", "command": OS.get_executable_path(),
		"args": ["--headless", "--no-header", "--path", ProjectSettings.globalize_path("res://"),
			"--script", "res://tests/fake_agent.gd", "--", "--scenario=" + ProjectSettings.globalize_path(SCENARIO_PATH)],
	})

	var frames: PackedFloat64Array = []
	var last := [Time.get_ticks_usec()]
	var on_frame := func() -> void:
		var now := Time.get_ticks_usec()
		frames.append((now - int(last[0])) / 1000.0)
		last[0] = now
	var memory_before := OS.get_static_memory_usage()
	tree.process_frame.connect(on_frame)
	var started := Time.get_ticks_usec()
	var record: Dictionary = history.call(&"load_record", SESSION_ID, SessionHistory.TAIL_EVENTS)  # como open_history_session
	var events: int = (record.get("events", []) as Array).size()
	var ok: bool = await controller.call(&"start", profile, record)
	record = {}
	var ready_ms := (Time.get_ticks_usec() - started) / 1000
	while view.call(&"is_building") and Time.get_ticks_usec() - started < 120 * 1000000:
		await tree.process_frame
	await tree.process_frame
	var built_ms := (Time.get_ticks_usec() - started) / 1000
	tree.process_frame.disconnect(on_frame)
	var memory_mb := (OS.get_static_memory_usage() - memory_before) / 1048576.0

	var worst := 0.0
	for value: float in frames:
		worst = maxf(worst, value)
	report.append("%d eventos · hasta poder escribir %d ms · hasta armar la vista %d ms · %d frames, peor %.0f ms · %d entradas en el modelo · %d vistas vivas, %d ocultas · memoria +%.1f MB" % [
		events, ready_ms, built_ms, frames.size(), worst, (model.call(&"entries") as Array).size(), view.call(&"entry_count"), view.call(&"hidden_count"), memory_mb])
	_check(ok, "no se reanudó: %s" % model.get(&"failure_message"))
	_check(ready_ms <= MAX_READY_MS, "hasta poder escribir %d ms (máx. %d)" % [ready_ms, MAX_READY_MS])
	_check(worst <= MAX_FRAME_MS, "frame más lento %.0f ms (máx. %.0f)" % [worst, MAX_FRAME_MS])
	_check(memory_mb <= MAX_MEMORY_MB, "memoria +%.1f MB (máx. %.0f)" % [memory_mb, MAX_MEMORY_MB])
	controller.call(&"stop")
	return failures


## Copia la sesión al historial con este id: el archivo de GODOT_AGENT_RESUME_SOURCE o una sintética.
func _install_session(dir: String, source: String) -> void:
	DirAccess.make_dir_recursive_absolute(dir)
	var out := FileAccess.open(dir.path_join(SESSION_ID + SessionHistory.EXTENSION), FileAccess.WRITE)
	out.store_line(JSON.stringify({"format": SessionHistory.FORMAT, "id": SESSION_ID, "profile_id": "fake", "account": "",
		"agent": "Agente falso", "cwd": ProjectSettings.globalize_path("res://"), "created": 0}))
	if source.is_empty():
		for event: Dictionary in synthetic_events(SYNTHETIC_EVENTS):
			out.store_line(JSON.stringify(event))
	else:
		var input := FileAccess.open(source, FileAccess.READ)
		input.get_line()
		while not input.eof_reached():
			var line := input.get_line()
			if not line.is_empty():
				out.store_line(line)
	out.close()


## Una sesión con la forma de una real (b9fb423c): turnos largos de tool calls con su salida, mensajes
## del agente cada tanto y alguna edición con diff. `count` eventos en total.
static func synthetic_events(count: int) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	var turn := 0
	var call := 0
	while events.size() < count:
		turn += 1
		events.append({"type": "user", "text": "Pedido %d: revisá el nivel y arreglá lo que encuentres." % turn})
		var steps := 1200 if turn % 3 != 0 else 300
		for step in steps:
			if events.size() >= count - 1:
				break
			if step % 10 == 0:
				events.append({"type": "update", "update": {"sessionUpdate": "agent_message_chunk", "content": {"type": "text",
					"text": "Turno %d, paso %d: reviso `player.gd` y ajusto la **velocidad**.\n\n- uno\n- dos\n" % [turn, step]}}})
				continue
			call += 1
			var id := "call-%d" % call
			var edit := call % 25 == 0
			events.append({"type": "update", "update": {"sessionUpdate": "tool_call", "toolCallId": id, "title": "Edit" if edit else "Bash",
				"kind": "edit" if edit else "execute", "status": "in_progress", "rawInput": {"command": "grep -rn speed res://player.gd # %d" % call}}})
			var content: Array = []
			if edit:
				content.append({"type": "diff", "path": "/tmp/project/player.gd", "oldText": "var speed := 1.0\n".repeat(20), "newText": "var speed := 2.0\n".repeat(20)})
			else:
				content.append({"type": "content", "content": {"type": "text", "text": ("player.gd:%d: var speed := %d.0\n" % [call, call]).repeat(30)}})
			events.append({"type": "update", "update": {"sessionUpdate": "tool_call_update", "toolCallId": id, "status": "completed", "content": content}})
		events.append({"type": "turn_end", "reason": "end_turn"})
	return events.slice(0, count)


func _check(condition: bool, label: String) -> void:
	if not condition:
		failures.append(label)
