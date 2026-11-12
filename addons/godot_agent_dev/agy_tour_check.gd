@tool
extends "plan_check.gd"
## m18-02: recorrido de una sesión con Antigravity (antigravity-acp del registro de ACP; gasta tokens,
## pedidos chicos sobre tests/docs_demo). Imprime lo que pasa en cada paso con [agy-tour] para anotar
## en la tarea qué anda, qué no y qué difiere de Claude Code. Con AGY_TOUR_WRAP=<script> el agente
## corre envuelto (python3 <script> <log> <comando>): así se registra el tráfico ACP y el MCP.

const TOUR_TARGET := "res://tests/tmp/agy_tour/player.gd"
const TURN_WAIT_MS := 240000


func run_tour(tree: SceneTree, dock: Control) -> PackedStringArray:
	_tree = tree
	_dock = dock
	_model = dock.get(&"_model")
	_controller = dock.get(&"_controller")
	var command := _antigravity_command()
	if command.is_empty():
		return PackedStringArray(["antigravity-acp no está instalado (registro de ACP)"])
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(TOUR_TARGET.get_base_dir()))
	var file := FileAccess.open(TOUR_TARGET, FileAccess.WRITE)
	file.store_string(FileAccess.get_file_as_string("res://tests/docs_demo/player.gd"))
	file.close()
	var args: Array = []
	var wrap := OS.get_environment("AGY_TOUR_WRAP")
	if not wrap.is_empty():
		args = [wrap, OS.get_environment("AGY_TOUR_LOG"), command]
		command = "python3"
	var profile := AgentProfile.from_dict({"id": "antigravity-acp", "display_name": "Google Antigravity", "command": command, "args": args})
	_model.connect(&"permission_requested", func(r: Object) -> void:
		print("[agy-tour] tarjeta: %s · grupo %s · opciones %s" % [r.get(&"title"), r.get(&"group"), (r.get(&"options") as Array).map(func(o: Dictionary) -> String: return str(o.get("kind", "")) + ":" + str(o.get("optionId", "")))]))
	_model.connect(&"agent_modes_changed", func(current: String, _modes: Array) -> void: print("[agy-tour] modo del agente → %s" % current))
	await _start(profile)
	if failures.is_empty():
		await _ask()
		await _build()
		await _playtest()
		await _cancel()
		await _history(profile)
	print("[agy-tour] uso: %d / %d" % [_model.get(&"usage_used"), _model.get(&"usage_size")])
	_dump_as("agy-tour")
	_controller.call(&"stop")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TOUR_TARGET))
	return failures


func _start(profile: AgentProfile) -> void:
	var started := Time.get_ticks_msec()
	if not await _controller.call(&"start", profile):
		failures.append("no arrancó Antigravity: %s" % _model.get(&"failure_message"))
		return
	var modes: Array = (_model.get(&"agent_modes") as Array).map(func(m: Variant) -> String: return str(m.get("id", "")) if m is Dictionary else "")
	print("[agy-tour] arrancó en %d ms · sesión %s" % [Time.get_ticks_msec() - started, _model.get(&"session_id")])
	print("[agy-tour] modos %s · actual %s · modo plan propio %s" % [modes, _model.get(&"current_agent_mode"), _controller.call(&"agent_has_plan_mode")])
	print("[agy-tour] capacidades %s" % JSON.stringify(_model.get(&"agent_capabilities")))
	print("[agy-tour] load %s · resume %s" % [_model.call(&"supports_load_session"), _model.call(&"supports_resume_session")])


## Preguntar: no edita; la respuesta llega y el turno termina.
func _ask() -> void:
	var first := (_model.call(&"entries") as Array).size()
	var before := FileAccess.get_file_as_string(TOUR_TARGET)
	var started := Time.get_ticks_msec()
	_controller.call(&"send_in_mode", SessionModel.HarnessMode.ASK, "In one sentence: what does %s do? Do not edit anything." % ProjectSettings.globalize_path(TOUR_TARGET))
	await _turn("Preguntar")
	print("[agy-tour] Preguntar: %d ms · modo del agente %s · stop %s · tools %s" % [Time.get_ticks_msec() - started, _model.get(&"current_agent_mode"), _model.get(&"last_stop_reason"), _tool_names(first)])
	print("[agy-tour] Preguntar respondió: %s" % str(_controller.call(&"agent_text_since", first)).left(300).replace("\n", " "))
	_expect(FileAccess.get_file_as_string(TOUR_TARGET) == before, "Preguntar no editó el archivo")


## Construir: una edición chica; la primera tarjeta se permite una vez, la segunda se rechaza.
func _build() -> void:
	var first := (_model.call(&"entries") as Array).size()
	var requests: Array = []
	var on_request := func(r: Object) -> void:
		requests.append(r)
		var allow := requests.size() == 1
		var option: String = r.call(&"option_id_for", PackedStringArray(["allow_once"] if allow else ["reject_once", "reject_always"]))
		print("[agy-tour] Construir: tarjeta %d «%s» → %s" % [requests.size(), r.get(&"title"), option])
		if not option.is_empty():
			r.call(&"select", option)
	_model.connect(&"permission_requested", on_request)
	var path := ProjectSettings.globalize_path(TOUR_TARGET)
	_controller.call(&"send_in_mode", SessionModel.HarnessMode.BUILD, "In %s add the line `# tour: first` at the very top. Then, as a separate edit, add `# tour: second` at the very end. Only those two edits, nothing else." % path)
	await _turn("Construir")
	_model.disconnect(&"permission_requested", on_request)
	var text := FileAccess.get_file_as_string(TOUR_TARGET)
	print("[agy-tour] Construir: tarjetas %d · modo del agente %s · stop %s · tools %s · primera %s · segunda %s" % [requests.size(), _model.get(&"current_agent_mode"), _model.get(&"last_stop_reason"), _tool_names(first), text.contains("# tour: first"), text.contains("# tour: second")])


## Playtest corto desde el panel de revisión: qué modo del agente queda y si usa las tools del juego.
func _playtest() -> void:
	var first := (_model.call(&"entries") as Array).size()
	var panel: Object = _dock.get(&"_review_panel")
	var cards: Array = []
	var on_request := func(r: Object) -> void:
		cards.append(r.get(&"title"))
		var option: String = r.call(&"option_id_for", PackedStringArray(["allow_once"]))
		if not option.is_empty():
			r.call(&"select", option)
	_model.connect(&"permission_requested", on_request)
	var started := Time.get_ticks_msec()
	panel.call(&"_start_playtest", "the scene res://tests/docs_demo/main.tscn starts without errors (one short run_scene of 2 seconds is enough; do not edit anything)", false, 2)
	await _turn("Playtest")
	_model.disconnect(&"permission_requested", on_request)
	print("[agy-tour] Playtest: tarjetas %s" % [cards])
	print("[agy-tour] Playtest: %d ms · modo del agente %s · stop %s · tools %s" % [Time.get_ticks_msec() - started, _model.get(&"current_agent_mode"), _model.get(&"last_stop_reason"), _tool_names(first)])
	print("[agy-tour] Playtest dijo: %s" % str(_controller.call(&"agent_text_since", first)).left(400).replace("\n", " "))
	if EditorInterface.is_playing_scene():
		EditorInterface.stop_playing_scene()


## Cancelar a mitad de un turno largo: cuánto tarda en quedar libre y con qué stop.
func _cancel() -> void:
	_controller.call(&"send_in_mode", SessionModel.HarnessMode.ASK, "Count slowly from 1 to 300, one number per line, explaining each number in a full sentence.")
	var first_chunk := await _until_for(func() -> bool: return str(_controller.call(&"agent_text_since", (_model.call(&"entries") as Array).size() - 1)).length() > 40, "Cancelar: no llegó texto para cortar", TURN_WAIT_MS)
	if not first_chunk:
		return
	var started := Time.get_ticks_msec()
	_controller.call(&"cancel")
	var idle := await _until_for(func() -> bool: return not bool(_model.call(&"is_busy")), "Cancelar: el turno no se cortó en 30 s", 30000)
	print("[agy-tour] Cancelar: libre %s en %d ms · stop %s" % [idle, Time.get_ticks_msec() - started, _model.get(&"last_stop_reason")])


## Historial: session/list, y retomar la sesión con session/load (o resume) en un proceso nuevo.
func _history(profile: AgentProfile) -> void:
	var listed: Array = await _controller.call(&"list_agent_sessions")
	var session_id := str(_model.get(&"session_id"))
	print("[agy-tour] session/list: %d sesiones · la de ahora %s" % [listed.size(), listed.any(func(s: Dictionary) -> bool: return str(s.get("id", s.get("sessionId", ""))) == session_id)])
	_controller.call(&"stop")
	var started := Time.get_ticks_msec()
	var loaded: bool = await _controller.call(&"start", profile, {"id": session_id})
	var entries := (_model.call(&"entries") as Array).size()
	print("[agy-tour] retomar: %s en %d ms · sesión %s · entradas %d · aviso %s" % [loaded, Time.get_ticks_msec() - started, _model.get(&"session_id"), entries, _last_notice()])
	if loaded:
		var first := entries
		_controller.call(&"send_in_mode", SessionModel.HarnessMode.ASK, "Which two comment lines did you add to the file earlier? Answer in one line.")
		await _turn("después de retomar")
		print("[agy-tour] después de retomar: %s" % str(_controller.call(&"agent_text_since", first)).left(300).replace("\n", " "))


func _turn(label: String) -> void:
	await _until_for(func() -> bool: return bool(_model.call(&"is_busy")), "%s: el turno no empezó" % label, 10000)
	await _until_for(func() -> bool: return not bool(_model.call(&"is_busy")), "%s: el turno no terminó en %d s" % [label, TURN_WAIT_MS / 1000], TURN_WAIT_MS)


func _tool_names(first: int) -> Array:
	return (_controller.call(&"tool_calls_since", first) as Array).map(func(call: Object) -> String: return "%s[%s]" % [call.get(&"title"), call.get(&"status")])


func _last_notice() -> String:
	var notices := (_model.call(&"entries") as Array).filter(func(e: Object) -> bool: return int(e.get(&"kind")) == 7)
	return str(notices[-1].get(&"text")).left(200) if not notices.is_empty() else "-"
