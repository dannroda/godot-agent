extends "test_case.gd"
## La tarjeta de caída del agente (m13-22): las últimas líneas del stderr, recortadas; el Agent
## Log conserva cada línea entera.

const SessionController := preload("res://addons/godot_agent/session/session_controller.gd")
const SessionModel := preload("res://addons/godot_agent/session/session_model.gd")
const AgentLog := preload("res://addons/godot_agent/core/agent_log.gd")
const ChatEntry := preload("res://addons/godot_agent/session/chat_entry.gd")


func _json_line(chars: int) -> String:
	return 'fake_agent: prompt {"jsonrpc":"2.0","params":{"prompt":[{"type":"text","text":"' + "x".repeat(chars) + '"}],"harness_context":true,"END_MARKER":1}}'


func test_long_lines_are_cut_and_say_how_much_is_missing() -> void:
	var line := _json_line(3000)
	var summary := SessionController.stderr_summary(PackedStringArray([line]))
	assert_true(summary.begins_with("fake_agent: prompt {"), "conserva el principio, que dice qué es")
	assert_true(summary.length() < 260, "queda corta (%d)" % summary.length())
	assert_false(summary.contains("END_MARKER"), "el final del JSON no está")
	var missing := line.length() - SessionController.STDERR_LINE_CHARS
	assert_true(summary.ends_with("… %d more characters, see the Agent Log" % missing), "dice cuántos caracteres faltan (%s)" % summary.right(60))


func test_short_lines_stay_and_empty_ones_go() -> void:
	var lines := PackedStringArray(["Error: Cannot find module", "", "   ", "    at node:internal/modules (file.js:10:5)", "node: exit 1"])
	assert_eq(SessionController.stderr_summary(lines), "Error: Cannot find module\nat node:internal/modules (file.js:10:5)\nnode: exit 1", "líneas tal cual, sin las vacías, sin espacios de más")


func test_only_the_last_lines_survive() -> void:
	var lines: PackedStringArray = []
	for i in 12:
		lines.append("line %d" % i)
	var summary := SessionController.stderr_summary(lines)
	assert_eq(summary.split("\n").size(), SessionController.STDERR_TAIL, "como mucho STDERR_TAIL líneas")
	assert_true(summary.begins_with("line 4\n") and summary.ends_with("line 11"), "las últimas, en orden (%s)" % summary.replace("\n", "|"))
	assert_eq(SessionController.stderr_summary(PackedStringArray(["a", "b", "c"]), 2), "b\nc", "con otro máximo")


func test_crash_card_is_short_and_the_log_keeps_everything() -> void:
	var model := SessionModel.new()
	var log := AgentLog.new()
	var controller := SessionController.new()
	controller.setup(model, log, "/tmp/project")
	controller.call(&"_on_stderr", "starting")
	controller.call(&"_on_stderr", _json_line(5000))
	controller.call(&"_on_stderr", "Segmentation fault")
	controller.call(&"_fail_agent", "Fake stopped", "The agent's process ended unexpectedly (code 139).", "The agent exited unexpectedly (code 139).", [] as Array[Dictionary])
	var card: ChatEntry = model.entries().back()
	assert_eq(card.kind, ChatEntry.EntryKind.NOTICE, "la tarjeta")
	assert_eq(card.title, "Fake stopped", "con su título")
	var details_lines := card.details.split("\n")
	assert_eq(details_lines.size(), 3, "las tres líneas (%s)" % card.details.left(80))
	assert_eq(details_lines[0], "starting", "la primera tal cual")
	assert_true(details_lines[1].length() <= SessionController.STDERR_LINE_CHARS + 60, "la del JSON recortada (%d)" % details_lines[1].length())
	assert_false(card.details.contains("END_MARKER"), "sin el prompt de sistema")
	assert_eq(details_lines[2], "Segmentation fault", "la causa se ve")
	var full: Array = log.entries().filter(func(entry: Dictionary) -> bool: return str(entry.message).contains("END_MARKER"))
	assert_eq(full.size(), 1, "el Agent Log tiene la línea entera")
	assert_eq(model.state, SessionModel.SessionState.FAILED, "FAILED")


## El token del server MCP va en los headers de session/new que el agente vuelca por stderr: la
## tarjeta no puede mostrarlo, ni entero ni el pedazo que quedaría si el recorte cae en el medio.
func test_secrets_never_reach_the_card() -> void:
	var model := SessionModel.new()
	var log := AgentLog.new()
	var controller := SessionController.new()
	controller.setup(model, log, "/tmp/project")
	var token := "tok_" + "s3cr3t".repeat(6)
	log.add_secret(token)
	controller.call(&"_on_stderr", 'fake_agent: session/new {"mcpServers":[{"headers":[{"name":"Authorization","value":"Bearer %s"}]}]}' % token)
	# El token empieza en la posición 150: el recorte a 160 caería en el medio.
	var prefix := "x".repeat(150)
	controller.call(&"_on_stderr", prefix + token + " and then a long tail " + "y".repeat(200))
	controller.call(&"_fail_agent", "Fake stopped", "The agent's process ended unexpectedly (code 1).", "The agent exited unexpectedly (code 1).", [] as Array[Dictionary])
	var card: ChatEntry = model.entries().back()
	assert_false(card.details.contains(token), "el token entero no está")
	assert_false(card.details.contains(token.left(8)), "ni su principio")
	assert_eq(card.details.count(AgentLog.REDACTED), 2, "las dos veces redactado (%s)" % card.details)
	assert_true(card.details.contains("Authorization"), "el resto de la línea sigue")
	var tail: PackedStringArray = controller.get(&"_stderr_tail")
	assert_false("\n".join(tail).contains(token), "la cola del controller tampoco lo guarda")
	assert_false(log.entries().any(func(entry: Dictionary) -> bool: return str(entry.message).contains(token)), "el log tampoco")


func test_empty_lines_do_not_take_room_in_the_tail() -> void:
	var controller := SessionController.new()
	controller.setup(SessionModel.new(), AgentLog.new(), "/tmp/project")
	for i in 20:
		controller.call(&"_on_stderr", "")
		controller.call(&"_on_stderr", "   ")
	for i in 8:
		controller.call(&"_on_stderr", "useful %d" % i)
	var tail: PackedStringArray = controller.get(&"_stderr_tail")
	assert_eq(tail.size(), SessionController.STDERR_TAIL, "la cola llena de líneas útiles")
	assert_eq(tail[0], "useful 0", "ninguna vacía ocupó lugar")
