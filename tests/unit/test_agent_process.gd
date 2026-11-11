extends "test_case.gd"
## AgentProcess con procesos reales (sh): líneas de stdout y stderr, exit después de la última
## línea, y que recargar el script con el proceso corriendo no tire el editor (D35: sin threads).

const AgentProcess := preload("res://addons/godot_agent/transport/agent_process.gd")
const ProcessTree := preload("res://addons/godot_agent/transport/process_tree.gd")
const SCRIPT_PATH := "res://addons/godot_agent/transport/agent_process.gd"
const TIMEOUT_MS := 8000


func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


func _wait_until(condition: Callable) -> bool:
	var deadline := Time.get_ticks_msec() + TIMEOUT_MS
	while not condition.call() and Time.get_ticks_msec() < deadline:
		await _tree().process_frame
	return condition.call()


func test_split_lines() -> void:
	var split := AgentProcess._split_lines("uno\r\n\ndos\ntr".to_utf8_buffer())
	assert_eq(split.lines, PackedStringArray(["uno", "dos"]), "sin vacías ni \\r")
	assert_eq(split.rest.get_string_from_utf8(), "tr", "lo incompleto queda")
	split = AgentProcess._split_lines("ñandú 🦊\n".to_utf8_buffer())
	assert_eq(split.lines, PackedStringArray(["ñandú 🦊"]), "utf-8")


func test_lines_and_exit() -> void:
	var process := AgentProcess.new()
	var events: Array[String] = []
	process.line_received.connect(func(line: String) -> void: events.append("out:" + line))
	process.stderr_received.connect(func(line: String) -> void: events.append("err:" + line))
	process.exited.connect(func(code: int) -> void: events.append("exit:%d" % code))
	assert_true(process.start("sh", ["-c", "echo uno; echo problema >&2; i=0; while [ $i -lt 500 ]; do echo l$i; i=$((i+1)); done; printf fin; exit 3"]), "arranca")
	assert_true(await _wait_until(func() -> bool: return events.has("exit:3")), "exit con su código")
	var out := events.filter(func(event: String) -> bool: return event.begins_with("out:"))
	assert_eq(out.size(), 502, "todas las líneas, con la última sin \\n")
	assert_eq(out[0], "out:uno", "en orden")
	assert_eq(events[-2], "out:fin", "la línea sin \\n justo antes del exit")
	assert_eq(events[-1], "exit:3", "el exit al final")
	assert_true(events.has("err:problema"), "stderr")
	process.stop()


func test_send_line_and_stop() -> void:
	var process := AgentProcess.new()
	var lines: PackedStringArray = []
	var exits: Array[int] = []
	process.line_received.connect(func(line: String) -> void: lines.append(line))
	process.exited.connect(func(code: int) -> void: exits.append(code))
	assert_true(process.start("sh", ["-c", "while read l; do echo \"eco $l\"; done"]), "arranca")
	assert_true(process.send_line("hola"), "escribe en stdin")
	assert_true(await _wait_until(func() -> bool: return lines.has("eco hola")), "responde")
	process.stop()
	assert_false(process.is_running(), "stop lo mata")
	for i in 5:
		await _tree().process_frame
	assert_eq(exits, [] as Array[int], "stop no emite exited")


## Al cerrar el editor, el plugin termina con stop_all() lo que sigue vivo de cualquier dueño, con
## sus hijos (npx → node); un proceso que terminó solo o que se liberó ya no está en la lista.
func test_stop_all() -> void:
	var before := AgentProcess.live_count()
	var held := AgentProcess.new()
	assert_true(held.start("sh", ["-c", "sleep 60 & wait"]), "arranca con un hijo")
	var pid := held.pid()
	assert_true(await _wait_until(func() -> bool: return not ProcessTree.descendants(pid).is_empty()), "el hijo arrancó")
	var child := ProcessTree.descendants(pid)[0]
	var done := AgentProcess.new()
	assert_true(done.start("sh", ["-c", "exit 0"]), "arranca uno que termina solo")
	var dropped := AgentProcess.new()
	assert_true(dropped.start("sleep", ["60"]), "arranca uno que se suelta")
	var dropped_pid := dropped.pid()
	assert_eq(AgentProcess.live_count(), before + 3, "los tres registrados")
	dropped = null
	assert_false(ProcessTree.is_alive(dropped_pid) and OS.is_process_running(dropped_pid), "soltarlo lo mata")
	assert_true(await _wait_until(func() -> bool: return AgentProcess.live_count() == before + 1), "el que terminó y el soltado salen de la lista")
	AgentProcess.stop_all()
	assert_false(held.is_running(), "stop_all mata al que sigue vivo")
	assert_true(await _wait_until(func() -> bool: return not ProcessTree.is_alive(child)), "y a su hijo")
	assert_eq(AgentProcess.live_count(), 0, "la lista queda vacía")


## Lo que tiró el editor (2026-10-22): un script del addon cambió en disco con el agente corriendo
## y el editor lo recargó bajo los threads lectores.
func test_reload_while_running() -> void:
	var process := AgentProcess.new()
	var lines: PackedStringArray = []
	process.line_received.connect(func(line: String) -> void: lines.append(line))
	assert_true(process.start("sh", ["-c", "while true; do echo tick; sleep 0.02; done"]), "arranca")
	assert_true(await _wait_until(func() -> bool: return lines.size() >= 3), "lee antes")
	var script: GDScript = load(SCRIPT_PATH)
	var source := script.source_code
	script.source_code = source + "\n"
	assert_eq(script.reload(true), OK, "recarga con el proceso corriendo")
	var before := lines.size()
	assert_true(await _wait_until(func() -> bool: return lines.size() >= before + 3), "sigue leyendo después")
	assert_true(process.is_running(), "sigue vivo")
	process.stop()
	script.source_code = source
	script.reload(true)
