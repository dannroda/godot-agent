extends "test_case.gd"
## m12-61: lo que le llegó a Claude Code por fuera del chat (un mensaje de otra sesión, una tarea que
## terminó) se lee del final de su transcript y sale en el chat antes de la respuesta, y en el
## historial. El transcript es uno armado (tests/fixtures/outside_input), no uno real.

const OutsideInput := preload("res://addons/godot_agent/session/outside_input.gd")
const ChatEntry := preload("res://addons/godot_agent/session/chat_entry.gd")
const SessionModel := preload("res://addons/godot_agent/session/session_model.gd")
const SessionHistory := preload("res://addons/godot_agent/session/session_history.gd")
const SessionController := preload("res://addons/godot_agent/session/session_controller.gd")
const SessionExport := preload("res://addons/godot_agent/session/session_export.gd")
const SessionDigest := preload("res://addons/godot_agent/session/session_digest.gd")
const ClaudeAdapter := preload("res://addons/godot_agent/session/agents/claude_adapter.gd")
const AgentAdapter := preload("res://addons/godot_agent/session/agents/agent_adapter.gd")
const AgentLog := preload("res://addons/godot_agent/core/agent_log.gd")
const UserMessageView := preload("res://addons/godot_agent/ui/dock/entries/user_message_view.gd")
const MarkdownBBCode := preload("res://addons/godot_agent/ui/markdown/markdown_bbcode.gd")
const I18n := preload("res://addons/godot_agent/core/i18n.gd")

const FIXTURE := "res://tests/fixtures/outside_input/transcript.jsonl"
const SESSION := "00000000-0000-4000-8000-000000000001"


## Las primeras `count` líneas del transcript armado.
func _lines(count: int = -1) -> PackedStringArray:
	var lines := FileAccess.get_file_as_string(FIXTURE).split("\n", false)
	return lines if count < 0 else lines.slice(0, count)


func _write(path: String, lines: PackedStringArray) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string("\n".join(lines) + "\n")
	file.close()


func test_peer_message_of_the_last_turn() -> void:
	# Hasta la línea 7: el mensaje de opus-0 arrancó el turno; después vinieron una tool y su resultado.
	var inputs := OutsideInput.latest(_lines(7))
	assert_eq(inputs.size(), 1, "una entrada: %s" % [inputs])
	assert_eq(inputs[0].kind, OutsideInput.KIND_PEER, "un mensaje de otra sesión")
	assert_eq(inputs[0].from, "opus-0", "con su nombre")
	assert_eq(inputs[0].text, "Rebase on main and run the suite again.", "el texto, de origin.body")
	assert_eq(inputs[0].uuid, "u-03", "y su uuid")


func test_several_inputs_in_a_row_oldest_first() -> void:
	var inputs := OutsideInput.latest(_lines())
	assert_eq(inputs.map(func(input: Dictionary) -> String: return input.uuid), ["u-08", "u-09"], "la tarea y el mensaje que llegaron juntos, sin el de antes")
	assert_eq(inputs[0].kind, OutsideInput.KIND_TASK, "primero la tarea")
	assert_eq(inputs[0].status, "completed", "con su estado")
	assert_eq(inputs[0].text, "Background command \"Run the suite\" completed (exit code 0)", "y su resumen")
	assert_eq(inputs[1].from, "opus-1", "el mensaje sin body")
	assert_eq(inputs[1].text, "The suite is green here too.", "sale del <cross-session-message>")


func test_nothing_when_the_turn_came_from_the_chat_or_was_shown() -> void:
	assert_eq(OutsideInput.latest(_lines(2)), [] as Array[Dictionary], "el turno lo pidió el usuario")
	assert_eq(OutsideInput.latest(_lines(), {"u-09": true}), [] as Array[Dictionary], "lo último ya se mostró")
	assert_eq(OutsideInput.latest(_lines(), {}, 1).size(), 1, "como mucho max_inputs")
	assert_eq(OutsideInput.latest(PackedStringArray(["not json", "{\"type\": \"user\", \"origin\": 3}"])), [] as Array[Dictionary], "líneas rotas")


func test_tail_drops_the_cut_line() -> void:
	var dir := temp_dir("outside_input_tail")
	var path := ProjectSettings.globalize_path(dir.path_join("t.jsonl"))
	_write(path, _lines())
	var whole := OutsideInput.read_tail(path)
	assert_eq(whole.size(), 10, "el archivo entero")
	var tail := OutsideInput.read_tail(path, _lines()[9].length() + _lines()[8].length() + 10)
	assert_eq(tail.size(), 2, "la primera, cortada, no: %d" % tail.size())
	assert_eq(JSON.parse_string(tail[1]).uuid, "u-10", "llega hasta el final")
	assert_eq(OutsideInput.read_tail(path.get_base_dir().path_join("missing.jsonl")), PackedStringArray(), "sin archivo")


func test_transcript_path_from_the_account_dir() -> void:
	var dir := ProjectSettings.globalize_path(temp_dir("outside_input_account"))
	var cwd := "/home/someone/my.game"
	var project := dir.path_join("projects").path_join("-home-someone-my-game")
	DirAccess.make_dir_recursive_absolute(project)
	_write(project.path_join(SESSION + ".jsonl"), _lines(1))
	assert_eq(OutsideInput.transcript_path(dir, cwd, SESSION), project.path_join(SESSION + ".jsonl"), "en la carpeta del proyecto")
	assert_eq(OutsideInput.transcript_path(dir, "/somewhere/else", SESSION), project.path_join(SESSION + ".jsonl"), "o buscándolo en las de todos")
	assert_eq(OutsideInput.transcript_path(dir, cwd, "other-session"), "", "otra sesión: no está")
	assert_eq(OutsideInput.transcript_path(dir, cwd, "../x"), "", "un id raro no sale de la carpeta")
	assert_eq(ClaudeAdapter.new().transcript_path(SESSION, cwd, {"CLAUDE_CONFIG_DIR": dir}), project.path_join(SESSION + ".jsonl"), "Claude Code usa la carpeta de la cuenta del perfil")
	assert_eq(AgentAdapter.new().transcript_path(SESSION, cwd, {}), "", "otro agente: no se sabe")
	DirAccess.remove_absolute(project.path_join(SESSION + ".jsonl"))


func test_captions() -> void:
	I18n.set_locale("en")
	assert_eq(OutsideInput.caption({"kind": "peer", "from": "opus-0"}), "From opus-0")
	assert_eq(OutsideInput.caption({"kind": "peer", "from": ""}), "From another session")
	assert_eq(OutsideInput.caption({"kind": "task", "status": "completed"}), "Background task finished")
	assert_eq(OutsideInput.caption({"kind": "task", "status": "failed"}), "Background task finished (failed)")
	I18n.set_locale("es")
	assert_eq(OutsideInput.caption({"kind": "peer", "from": "opus-0"}), "De opus-0", "traducida")
	assert_eq(OutsideInput.caption({"kind": "peer", "from": "opus-0"}, false), "From opus-0", "en inglés para el export")
	I18n.set_locale("en")


func _controller(transcript: String) -> SessionController:
	var controller := SessionController.new()
	controller.setup(SessionModel.new(), AgentLog.new(), "/tmp/project")
	controller.model.session_id = SESSION
	controller.model.set_state(SessionModel.SessionState.READY)
	controller.transcript_path_override = transcript
	return controller


func _send(controller: SessionController, update: Dictionary) -> void:
	controller.call(&"_on_session_update", {"sessionId": SESSION, "update": update})


func _chunk(text: String) -> Dictionary:
	return {"sessionUpdate": "agent_message_chunk", "content": {"type": "text", "text": text}}


func test_outside_turn_shows_what_started_it() -> void:
	var path := ProjectSettings.globalize_path(temp_dir("outside_input_turn").path_join("t.jsonl"))
	_write(path, _lines(4))  # el mensaje de opus-0 ya está; el agente recién empieza a contestar
	var controller := _controller(path)
	_send(controller, _chunk("Rebasing"))
	_send(controller, _chunk(" now."))
	var entries := controller.model.entries()
	assert_eq(entries.size(), 2, "la entrada de afuera y la respuesta: %s" % [entries.map(func(e: ChatEntry) -> int: return e.kind)])
	assert_eq(entries[0].kind, ChatEntry.EntryKind.USER, "primero lo que llegó")
	assert_eq(entries[0].incoming.get("from"), "opus-0", "de opus-0")
	assert_eq(entries[0].text, "Rebase on main and run the suite again.", "con el mensaje")
	assert_eq(entries[1].kind, ChatEntry.EntryKind.AGENT, "después la respuesta")
	# El resultado del turno trae un usage_update; el turno siguiente lo arrancan dos entradas más.
	_send(controller, {"sessionUpdate": "usage_update", "used": 1000, "size": 200000})
	_write(path, _lines())
	_send(controller, _chunk("Both done."))
	entries = controller.model.entries()
	var incoming := entries.filter(func(e: ChatEntry) -> bool: return not e.incoming.is_empty())
	assert_eq(incoming.map(func(e: ChatEntry) -> String: return e.incoming.uuid), ["u-03", "u-08", "u-09"], "cada una una vez")
	assert_eq(entries[entries.size() - 2].incoming.get("from"), "opus-1", "antes de la respuesta del segundo turno")
	assert_false(entries.any(func(e: ChatEntry) -> bool: return e.kind == ChatEntry.EntryKind.NOTICE), "sin el aviso genérico")
	# Otra respuesta del mismo turno (sin usage_update en el medio): nada nuevo, y sin aviso.
	controller.set(&"_outside_turn_open", false)
	_send(controller, _chunk("More."))
	assert_eq(controller.model.entries().filter(func(e: ChatEntry) -> bool: return e.kind == ChatEntry.EntryKind.NOTICE).size(), 0, "ya mostradas: sin aviso")


func test_falls_back_to_the_notice() -> void:
	var controller := _controller("")  # sin perfil ni transcript: no se sabe dónde leer
	_send(controller, _chunk("Hi"))
	_send(controller, {"sessionUpdate": "usage_update", "used": 1000, "size": 200000})
	_send(controller, _chunk("Again"))
	var notices := controller.model.entries().filter(func(e: ChatEntry) -> bool: return e.kind == ChatEntry.EntryKind.NOTICE)
	assert_eq(notices.size(), 1, "el aviso de siempre, una vez hasta el próximo prompt")
	var empty := ProjectSettings.globalize_path(temp_dir("outside_input_empty").path_join("t.jsonl"))
	_write(empty, _lines(2))
	controller = _controller(empty)
	_send(controller, _chunk("Hi"))
	assert_eq(controller.model.entries()[0].kind, ChatEntry.EntryKind.NOTICE, "transcript sin nada de afuera: también")


func test_remote_control_message_needs_nothing() -> void:
	var path := ProjectSettings.globalize_path(temp_dir("outside_input_rc").path_join("t.jsonl"))
	_write(path, _lines())
	var controller := _controller(path)
	_send(controller, {"sessionUpdate": "user_message_chunk", "content": {"type": "text", "text": "from the phone"}})
	_send(controller, _chunk("Sure."))
	assert_true(controller.model.entries().all(func(e: ChatEntry) -> bool: return e.incoming.is_empty() and e.kind != ChatEntry.EntryKind.NOTICE), "el mensaje ya llegó: nada más")


func test_history_keeps_it_and_resume_does_not_repeat_it() -> void:
	var dir := temp_dir("outside_input_history")
	var history := SessionHistory.new()
	history.dir = dir
	history.begin("h1", "p", "A", "/tmp/project")
	history.record_prompt("Add a score label")
	history.record_incoming("Rebase on main.", {"kind": "peer", "from": "opus-0", "status": "", "uuid": "u-09"})
	history.end()
	var record := history.load_record("h1")
	assert_eq(int(record.get("turns", 0)), 1, "no cuenta como turno")
	var controller := _controller(ProjectSettings.globalize_path(FIXTURE))
	SessionHistory.replay(record, controller.model)
	var entries := controller.model.entries()
	assert_eq(entries.size(), 2, "el prompt y la entrada de afuera")
	assert_eq(entries[1].incoming.get("from"), "opus-0", "vuelve con quién la mandó")
	assert_eq(entries[1].text, "Rebase on main.", "y el texto")
	controller.model.set_state(SessionModel.SessionState.READY)
	_send(controller, _chunk("Done"))
	assert_eq(controller.model.entries().filter(func(e: ChatEntry) -> bool: return not e.incoming.is_empty()).size(), 1, "lo que ya estaba en el historial no se repite")
	assert_eq(SessionDigest.facts(record, "/tmp/project").get("requests"), ["Add a score label"], "el resumen no la toma como pedido del usuario")


func _view(entry: ChatEntry) -> UserMessageView:
	var view := UserMessageView.new()
	view.setup(entry, Color.ORANGE, MarkdownBBCode.new())
	view.call(&"_build")
	view.refresh()
	return view


func test_view_and_export() -> void:
	I18n.set_locale("en")
	var model := SessionModel.new()
	var short := model.add_incoming("Rebase on main.", {"kind": "peer", "from": "opus-0", "uuid": "a"})
	var view := _view(short)
	assert_true(view.is_incoming() and view.is_folded_kind(), "de afuera, con el estilo del harness")
	assert_eq((view.get(&"_caption") as Label).text, "✉ From opus-0", "quién la mandó")
	assert_true((view.get(&"_label") as Label).visible, "corta: desplegada")
	var long := model.add_incoming("line\n".repeat(20), {"kind": "task", "status": "completed", "uuid": "b"})
	var long_view := _view(long)
	assert_eq((long_view.get(&"_caption") as Label).text, "⚑ Background task finished", "la tarea")
	assert_false((long_view.get(&"_label") as Label).visible, "larga: plegada")
	long_view.call(&"_on_toggle")
	assert_true((long_view.get(&"_label") as Label).visible, "se despliega")
	var lines := PackedStringArray()
	SessionExport._entry_lines(model, short, lines, [] as Array[Dictionary], true)
	assert_eq(lines[0], "## From opus-0", "el export dice de quién es")
	view.free()
	long_view.free()
