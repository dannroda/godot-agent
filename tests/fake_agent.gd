extends SceneTree
## Agente ACP falso (spec §13). Lee JSON-RPC por stdin y responde según un guion JSON.
## Uso: godot --headless --no-header --path <repo> --script res://tests/fake_agent.gd -- --scenario=<ruta>
##
## Guion (tests/scripts/*.json):
##   {
##     "initialize": {...}      campos que pisan el resultado de initialize (opcional)
##     "session": {...}         campos extra del resultado de session/new (modes, configOptions)
##     "on_new_session": [pasos] pasos que corren después de responder session/new
##     "turns": [ {"steps": [paso, ...]}, ... ]   un turno por prompt; el último se repite
##     "auth": {"marker": "user://…", "code": "…"}   session/new responde authRequired (-32000)
##                              mientras no exista `marker`. Con `--login` en los args (el método
##                              `terminal` del guion) el proceso hace de login: imprime el enlace
##                              como Claude Code, espera el código por stdin y, si es `code`, crea
##                              `marker` y sale con 0 (si no, con 1).
##   }
## Pasos:
##   {"chunk": "texto"}                agent_message_chunk
##   {"thought": "texto"}              agent_thought_chunk
##   {"update": {...}}                 session/update arbitrario (tool_call, plan, usage_update…)
##   {"delay": segundos}
##   {"request": {"method", "params"}} request al cliente; espera la respuesta y la reporta por stderr
##   {"garbage": "texto"}              una línea que no es JSON
##   {"stop": "end_turn"}              responde el prompt (si no está, al terminar los pasos)
##   {"error": "mensaje", "data": {}} responde el prompt con un error JSON-RPC (-32603)
##   {"quota": {"five_hour": 0.9, "seven_day": 0.4, "status": "allowed_warning", "resets_in": 3600}}
##                                     usage_update con la cuota del plan, en la forma de Claude Code (D22)
##   {"limit": {"resets_in": 120}}     límite alcanzado como lo manda Claude Code: cuota "rejected",
##                                     mensaje "You've hit your limit · resets HH:MM" y error del prompt
##   {"exit": true}                    el proceso se mata a sí mismo (simula una caída)
## Un session/cancel corta el turno en curso y responde stopReason "cancelled".

const STDIN_BUFFER := 1 << 20

var _scenario: Dictionary = {}
var _inbox: Array[String] = []
var _inbox_mutex := Mutex.new()
var _reader: Thread
var _session_id: String = ""
var _turn_index: int = 0
var _prompt_id: Variant = null
var _steps: Array = []
var _wait_until_msec: int = 0
var _waiting_request_id: int = -1
var _next_request_id: int = 1000
var _message_counter: int = 0


func _initialize() -> void:
	var path := ""
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--scenario="):
			path = arg.trim_prefix("--scenario=")
	if not path.is_empty():
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if data is Dictionary:
			_scenario = data
		else:
			printerr("fake_agent: guion inválido: %s" % path)
	if "--login" in OS.get_cmdline_user_args():
		_run_login()
		return
	_reader = Thread.new()
	_reader.start(_read_stdin)


func _process(_delta: float) -> bool:
	_inbox_mutex.lock()
	var lines := _inbox.duplicate()
	_inbox.clear()
	_inbox_mutex.unlock()
	for line: String in lines:
		if line.is_empty():
			_reader.wait_to_finish()
			return true
		_handle_line(line)
	_advance_turn()
	return false


func _read_stdin() -> void:
	while true:
		var line := OS.read_string_from_stdin(STDIN_BUFFER)
		if line.is_empty():
			# El cliente nunca manda líneas vacías: vacío es EOF (stdin cerrado).
			_inbox_mutex.lock()
			_inbox.append("")
			_inbox_mutex.unlock()
			return
		_inbox_mutex.lock()
		_inbox.append(line)
		_inbox_mutex.unlock()


func _handle_line(line: String) -> void:
	var message: Variant = JSON.parse_string(line)
	if not message is Dictionary:
		printerr("fake_agent: línea inválida: %s" % line)
		return
	var method: Variant = message.get("method")
	var id: Variant = message.get("id")
	if id is float:
		id = int(id)
	if method == null:
		if id != null and int(id) == _waiting_request_id:
			printerr("fake_agent: respuesta %s" % JSON.stringify(message.get("result", message.get("error"))))
			_waiting_request_id = -1
		return
	match str(method):
		"initialize":
			var result := {
				"protocolVersion": 1,
				"agentCapabilities": {
					"loadSession": false,
					"promptCapabilities": {"image": true, "audio": false, "embeddedContext": true},
					"mcpCapabilities": {"http": true, "sse": false},
				},
				"authMethods": [],
				"agentInfo": {"name": "fake-agent", "title": "Agente falso", "version": "1.0.0"},
			}
			result.merge(_scenario.get("initialize", {}), true)
			printerr("fake_agent: initialize %s" % JSON.stringify(message.get("params", {})))
			printerr("fake_agent: GODOT=%s PATH=%s" % [OS.get_environment("GODOT"), OS.get_environment("PATH").get_slice(":", 0)])
			_reply(id, result)
		"session/new":
			var auth: Dictionary = _scenario.get("auth", {})
			if not auth.is_empty() and not FileAccess.file_exists(str(auth.get("marker", ""))):
				printerr("fake_agent: session/new sin login")
				_send({"jsonrpc": "2.0", "id": id, "error": {"code": -32000, "message": "Authentication required"}})
				return
			_session_id = "fake-session-%d" % (Time.get_ticks_usec() % 100000)
			var result := {"sessionId": _session_id}
			result.merge(_scenario.get("session", {}), true)
			printerr("fake_agent: session/new %s" % JSON.stringify(message.get("params", {})))
			_reply(id, result)
			if _scenario.get("on_new_session") is Array:
				_steps = (_scenario.on_new_session as Array).duplicate(true)
		"session/load":
			# Como claude-agent-acp: vuelve a mandar la conversación como session/update y después responde.
			_session_id = str(message.get("params", {}).get("sessionId", ""))
			printerr("fake_agent: session/load %s" % _session_id)
			_update({"sessionUpdate": "user_message_chunk", "content": {"type": "text", "text": "(replay del agente)"}})
			_update({"sessionUpdate": "agent_message_chunk", "content": {"type": "text", "text": "(replay del agente)"}})
			_reply(id, _scenario.get("session", {}))
		"session/prompt":
			printerr("fake_agent: prompt %s" % JSON.stringify(message.get("params", {}).get("prompt", [])))
			_start_turn(id)
		"session/cancel":
			printerr("fake_agent: cancel")
			if _prompt_id != null:
				_steps.clear()
				_waiting_request_id = -1
				_finish_prompt("cancelled")
		"session/set_mode":
			printerr("fake_agent: set_mode %s" % str(message.get("params", {}).get("modeId", "")))
			_reply(id, {})
		"session/set_config_option":
			printerr("fake_agent: set_config_option %s" % JSON.stringify(message.get("params", {})))
			_reply(id, {})
		_:
			if id != null:
				_send({"jsonrpc": "2.0", "id": id, "error": {"code": -32601, "message": "Method not found"}})


func _start_turn(id: Variant) -> void:
	_prompt_id = id
	var turns: Array = _scenario.get("turns", [])
	if turns.is_empty():
		_steps = [{"chunk": "Hola, soy el agente falso."}, {"stop": "end_turn"}]
	else:
		var turn: Dictionary = turns[mini(_turn_index, turns.size() - 1)]
		_steps = (turn.get("steps", []) as Array).duplicate(true)
	_turn_index += 1
	_message_counter += 1


func _advance_turn() -> void:
	while not _steps.is_empty():
		if Time.get_ticks_msec() < _wait_until_msec or _waiting_request_id != -1:
			return
		var step: Dictionary = _steps.pop_front()
		if step.has("chunk"):
			_update({"sessionUpdate": "agent_message_chunk", "messageId": "msg-%d" % _message_counter, "content": {"type": "text", "text": step.chunk}})
		elif step.has("thought"):
			_update({"sessionUpdate": "agent_thought_chunk", "content": {"type": "text", "text": step.thought}})
		elif step.has("update"):
			_update(_expand(step.update))
		elif step.has("delay"):
			_wait_until_msec = Time.get_ticks_msec() + int(float(step.delay) * 1000.0)
		elif step.has("request"):
			_waiting_request_id = _next_request_id
			_next_request_id += 1
			var params: Dictionary = _expand(step.request.get("params", {}))
			params["sessionId"] = _session_id
			_send({"jsonrpc": "2.0", "id": _waiting_request_id, "method": step.request.method, "params": params})
		elif step.has("garbage"):
			print(step.garbage)
		elif step.has("stop"):
			_finish_prompt(str(step.stop))
		elif step.has("error"):
			_fail_prompt(str(step.error), step.get("data"))
		elif step.has("quota"):
			_update(_quota_update(step.quota))
		elif step.has("limit"):
			var resets_in := int(step.limit.get("resets_in", 3600))
			_update(_quota_update({"status": "rejected", "five_hour": 1.0, "seven_day": step.limit.get("seven_day", 0.5), "resets_in": resets_in}))
			var reset_time := Time.get_time_string_from_unix_time(int(Time.get_unix_time_from_system()) + resets_in + _utc_offset_s()).left(5)
			var text := "You've hit your limit · resets %s" % reset_time
			_update({"sessionUpdate": "agent_message_chunk", "messageId": "msg-limit-%d" % _message_counter, "content": {"type": "text", "text": text}})
			_fail_prompt("Internal error: " + text, {"errorKind": "rate_limit"})
		elif step.has("exit"):
			# quit() no termina el proceso mientras el thread lector está bloqueado en stdin:
			# se simula la caída matando el propio proceso.
			OS.kill(OS.get_process_id())
			return
	if _prompt_id != null and _waiting_request_id == -1 and Time.get_ticks_msec() >= _wait_until_msec:
		_finish_prompt("end_turn")


## Reemplaza "{project}" por la ruta absoluta del proyecto en todos los strings.
func _expand(value: Variant) -> Variant:
	if value is String:
		return value.replace("{project}", ProjectSettings.globalize_path("res://").trim_suffix("/"))
	if value is Array:
		return value.map(_expand)
	if value is Dictionary:
		var result: Dictionary = {}
		for key: Variant in value:
			result[key] = _expand(value[key])
		return result
	return value


func _fail_prompt(message: String, data: Variant = null) -> void:
	if _prompt_id == null:
		return
	var error := {"code": -32603, "message": message}
	if data != null:
		error["data"] = data
	_send({"jsonrpc": "2.0", "id": _prompt_id, "error": error})
	_prompt_id = null


## usage_update con `_meta["_claude/rateLimit"]` como lo manda claude-agent-acp 0.94 (D22).
func _quota_update(quota: Dictionary) -> Dictionary:
	var now := int(Time.get_unix_time_from_system())
	var resets_at := float(now + int(quota.get("resets_in", 3600)))
	var info := {
		"status": str(quota.get("status", "allowed")),
		"rateLimitType": "five_hour",
		"resetsAt": resets_at,
		"isUsingOverage": false,
		"unifiedWindows": {
			"five_hour": {"utilization": float(quota.get("five_hour", 0.5)), "resetsAt": resets_at},
			"seven_day": {"utilization": float(quota.get("seven_day", 0.3)), "resetsAt": float(now + 5 * 86400)},
		},
	}
	if info.status != "allowed":
		info["utilization"] = info.unifiedWindows.five_hour.utilization
	return {"sessionUpdate": "usage_update", "used": 1000, "size": 200000, "_meta": {"_claude/rateLimit": info}}


static func _utc_offset_s() -> int:
	return int(Time.get_time_zone_from_system().get("bias", 0)) * 60


func _finish_prompt(stop_reason: String) -> void:
	if _prompt_id == null:
		return
	_reply(_prompt_id, {"stopReason": stop_reason, "usage": {"inputTokens": 10, "outputTokens": 5, "totalTokens": 15}})
	_prompt_id = null


func _update(update: Dictionary) -> void:
	_send({"jsonrpc": "2.0", "method": "session/update", "params": {"sessionId": _session_id, "update": update}})


func _reply(id: Variant, result: Variant) -> void:
	_send({"jsonrpc": "2.0", "id": id, "result": result})


func _send(message: Dictionary) -> void:
	print(JSON.stringify(message))


## Modo login: lee el código en el hilo principal (con un hilo lector bloqueado en stdin el proceso
## no terminaría mientras el cliente tenga el pipe abierto). El correcto crea el marcador del guion.
func _run_login() -> void:
	print("Opening browser to sign in…")
	print("If the browser didn't open, visit: https://example.invalid/oauth/authorize?code=true&state=fake")
	printraw("Paste code here if prompted > ")
	var code := OS.read_string_from_stdin(1024).strip_edges()
	var auth: Dictionary = _scenario.get("auth", {})
	var ok := code == str(auth.get("code", ""))
	if ok:
		var marker := FileAccess.open(str(auth.get("marker", "")), FileAccess.WRITE)
		marker.store_string("ok")
		marker.close()
		print("Login successful.")
	else:
		printerr("Invalid code")
	quit(0 if ok else 1)

