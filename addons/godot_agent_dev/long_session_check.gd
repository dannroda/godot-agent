@tool
extends RefCounted
## Rendimiento con sesiones largas (M7): el agente falso manda un turno con más de 600 entradas
## (texto en Markdown, streameado en chunks, alternado con tool calls). Mide los frames del editor
## mientras llega y comprueba el tope de vistas vivas y "Mostrar anteriores".

const AgentProfile := preload("res://addons/godot_agent/core/agent_profile.gd")
const ChatEntry := preload("res://addons/godot_agent/session/chat_entry.gd")
const DOCK_SCRIPT := "res://addons/godot_agent/ui/dock/agent_dock.gd"
const SCENARIO_PATH := "user://long_session.json"
const PAIRS := 320
const CHUNKS_PER_MESSAGE := 12
## Umbrales generosos: el editor corre con OpenGL por software en Xvfb.
const MAX_FRAME_MS := 400.0
const MAX_P95_MS := 120.0
const TURN_TIMEOUT_S := 120.0

var failures: PackedStringArray = []
var report: String = ""


func run_long(tree: SceneTree) -> PackedStringArray:
	var dock: Control = null
	for node: Node in tree.root.find_children("*", "VBoxContainer", true, false):
		if node.get_script() and (node.get_script() as Script).resource_path == DOCK_SCRIPT:
			dock = node
	if dock == null:
		failures.append("no se encontró el dock")
		return failures
	_write_scenario()
	var controller: Object = dock.get(&"_controller")
	var model: Object = dock.get(&"_model")
	var view: Object = dock.get(&"_conversation")
	var profile := AgentProfile.from_dict({
		"id": "fake", "display_name": "Agente falso", "command": OS.get_executable_path(),
		"args": ["--headless", "--no-header", "--path", ProjectSettings.globalize_path("res://"),
			"--script", "res://tests/fake_agent.gd", "--", "--scenario=" + ProjectSettings.globalize_path(SCENARIO_PATH)],
	})
	if not await controller.call(&"start", profile):
		failures.append("no arrancó la sesión: %s" % model.get(&"failure_message"))
		return failures

	var frames: PackedFloat64Array = []
	var last := [Time.get_ticks_usec()]
	var on_frame := func() -> void:
		var now := Time.get_ticks_usec()
		frames.append((now - int(last[0])) / 1000.0)
		last[0] = now
	tree.process_frame.connect(on_frame)
	var started := Time.get_ticks_msec()
	var turn: Array = []
	model.connect(&"turn_finished", func(reason: String) -> void: turn.append(reason), CONNECT_ONE_SHOT)
	controller.call(&"send_prompt", "sesión larga")  # sin await: se mide mientras llega
	while (turn.is_empty() or view.call(&"is_building")) and Time.get_ticks_msec() - started < TURN_TIMEOUT_S * 1000:
		await tree.process_frame
	await tree.process_frame
	await tree.process_frame
	tree.process_frame.disconnect(on_frame)
	var elapsed := (Time.get_ticks_msec() - started) / 1000.0

	var entries: int = (model.call(&"entries") as Array).size()
	var live: int = view.call(&"entry_count")
	var hidden: int = view.call(&"hidden_count")
	var sorted := frames.duplicate()
	sorted.sort()
	var worst := sorted[sorted.size() - 1] if not sorted.is_empty() else 0.0
	var p95 := sorted[int(sorted.size() * 0.95)] if not sorted.is_empty() else 0.0
	var average := 0.0
	for value: float in frames:
		average += value
	average /= maxf(1.0, frames.size())
	report = "%d entradas en %.1f s · %d frames · promedio %.1f ms · p95 %.1f ms · peor %.1f ms (frame %d) · %d vistas vivas, %d ocultas" % [entries, elapsed, frames.size(), average, p95, worst, frames.find(worst), live, hidden]
	_check(not turn.is_empty() and turn[0] == "end_turn", "el turno no terminó (%s)" % [turn])
	_check(entries >= PAIRS * 2, "pocas entradas en el modelo (%d)" % entries)
	_check(live <= 250, "más vistas vivas que el tope (%d)" % live)
	_check(live + hidden >= entries - 1, "vistas vivas + ocultas no cubren las entradas (%d + %d de %d)" % [live, hidden, entries])
	_check(worst <= MAX_FRAME_MS, "frame más lento %.1f ms (máx. %.0f)" % [worst, MAX_FRAME_MS])
	_check(p95 <= MAX_P95_MS, "p95 %.1f ms (máx. %.0f)" % [p95, MAX_P95_MS])

	# El último mensaje se ve completo (el refresco agrupado no pierde chunks).
	var last_text := ""
	for entry: Object in model.call(&"entries"):
		if int(entry.get(&"kind")) == ChatEntry.EntryKind.AGENT:
			last_text = str(entry.get(&"text"))
	_check(last_text.contains("Mensaje %d" % (PAIRS - 1)) and last_text.ends_with("fin.\n"), "último mensaje incompleto: " + last_text.right(80))

	view.call(&"show_older")
	await tree.process_frame
	_check(int(view.call(&"entry_count")) == live + 50 and int(view.call(&"hidden_count")) == hidden - 50, "Mostrar anteriores agrega 50 (%d vivas, %d ocultas)" % [view.call(&"entry_count"), view.call(&"hidden_count")])
	controller.call(&"stop")
	return failures


func _write_scenario() -> void:
	var steps: Array = []
	for i in PAIRS:
		var message := "### Mensaje %d\n\nReviso `player.gd` y **ajusto** la *velocidad* con [docs](https://docs.godotengine.org). Paso %d:\n\n- uno\n- dos con `código`\n\n```gdscript\nvar speed := %d.0\n```\nfin.\n" % [i, i, i]
		var size := ceili(message.length() / float(CHUNKS_PER_MESSAGE))
		for c in CHUNKS_PER_MESSAGE:
			steps.append({"chunk": message.substr(c * size, size)})
		steps.append({"update": {"sessionUpdate": "tool_call", "toolCallId": "t%d" % i, "title": "mcp__godot__get_errors", "kind": "read", "status": "in_progress", "rawInput": {"path": "res://player.gd"}}})
		steps.append({"update": {"sessionUpdate": "tool_call_update", "toolCallId": "t%d" % i, "status": "completed", "content": [{"type": "content", "content": {"type": "text", "text": "0 errores"}}]}})
		if i % 4 == 0:
			steps.append({"delay": 0.02})
	var file := FileAccess.open(SCENARIO_PATH, FileAccess.WRITE)
	file.store_string(JSON.stringify({"turns": [{"steps": steps}]}))
	file.close()


func _check(condition: bool, label: String) -> void:
	if not condition:
		failures.append(label)
