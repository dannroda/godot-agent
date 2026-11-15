extends "test_case.gd"
## Historial por partes (m7-55): reanudar lee solo el final del .jsonl, «Mostrar anteriores» lee lo de
## antes, el modelo suelta lo viejo al terminar un turno y el export sigue teniendo la sesión entera.

const SessionHistory := preload("res://addons/godot_agent/session/session_history.gd")
const SessionModel := preload("res://addons/godot_agent/session/session_model.gd")
const ChatEntry := preload("res://addons/godot_agent/session/chat_entry.gd")
const ConversationView := preload("res://addons/godot_agent/ui/dock/conversation_view.gd")
const ResumeCheck := preload("res://addons/godot_agent_dev/resume_check.gd")
const DIR := "user://test_history_window"
const ID := "window-session"


func _history(events: Array) -> SessionHistory:
	var history := SessionHistory.new()
	history.dir = DIR
	var dir := ProjectSettings.globalize_path(DIR)
	DirAccess.make_dir_recursive_absolute(dir)
	var file := FileAccess.open(dir.path_join(ID + ".jsonl"), FileAccess.WRITE)
	file.store_line(JSON.stringify({"format": SessionHistory.FORMAT, "id": ID, "profile_id": "p", "account": "", "agent": "A", "cwd": "/tmp", "created": 0}))
	for event: Variant in events:
		file.store_line(JSON.stringify(event))
	file.close()
	return history


func _cleanup() -> void:
	var dir := ProjectSettings.globalize_path(DIR)
	for file: String in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(file))
	DirAccess.remove_absolute(dir)


func _update(update: Dictionary) -> Dictionary:
	return {"type": "update", "update": update}


func test_safe_start_skips_calls_that_started_before() -> void:
	var events: Array = [
		_update({"sessionUpdate": "tool_call_update", "toolCallId": "old", "status": "in_progress"}),  # su tool_call quedó antes
		_update({"sessionUpdate": "agent_message_chunk", "content": {"type": "text", "text": "a"}}),
		_update({"sessionUpdate": "tool_call_update", "toolCallId": "old", "status": "completed"}),
		_update({"sessionUpdate": "agent_message_chunk", "content": {"type": "text", "text": "b"}}),  # sigue el mismo mensaje
		_update({"sessionUpdate": "tool_call", "toolCallId": "new", "status": "in_progress"}),
		_update({"sessionUpdate": "tool_call_update", "toolCallId": "new", "status": "completed"}),
	]
	assert_eq(SessionHistory.safe_start(events), 4, "después del último update de lo que empezó antes, en el tool call siguiente")
	var with_child: Array = [
		{"type": "user", "text": "hola"},
		_update({"sessionUpdate": "tool_call", "toolCallId": "agent", "status": "in_progress"}),
		_update({"sessionUpdate": "tool_call", "toolCallId": "c1", "status": "completed", "_meta": {"claudeCode": {"parentToolUseId": "agent"}}}),
		_update({"sessionUpdate": "tool_call", "toolCallId": "x", "status": "completed"}),
	]
	assert_eq(SessionHistory.safe_start(with_child), 0, "un mensaje del usuario sin nada abierto")
	assert_eq(SessionHistory.safe_start(with_child.slice(2)), 1, "el hijo de un subagente que empezó antes no es un corte")


func test_resume_reads_only_the_tail_of_20000_events() -> void:
	var events := ResumeCheck.synthetic_events(20000)
	var history := _history(events)
	var started := Time.get_ticks_msec()
	var record := history.load_record(ID, SessionHistory.TAIL_EVENTS)
	var model := SessionModel.new()
	model.session_id = ID
	SessionHistory.replay(record, model)
	var elapsed := Time.get_ticks_msec() - started
	assert_eq(int(record.events_total), 20000, "sabe cuántos hay")
	assert_true((record.events as Array).size() <= SessionHistory.TAIL_EVENTS, "lee a lo sumo la cola (%d)" % (record.events as Array).size())
	assert_eq(int(record.events_offset) + (record.events as Array).size(), 20000, "hasta el final")
	assert_true(model.has_older() and model.first_event == int(record.events_offset), "el modelo sabe que hay más antes")
	assert_true(elapsed < 1500, "leer y armar la cola tarda poco (%d ms)" % elapsed)
	for entry: ChatEntry in model.entries():
		assert_true(entry.event_index >= model.first_event, "cada entrada con su evento")
	assert_eq(model.entries()[0].event_index, model.first_event, "la primera entrada empieza en el corte")

	# «Mostrar anteriores» hasta el principio: la misma conversación que leyendo todo.
	var loads := 0
	while model.has_older() and loads < 100:
		assert_true(history.load_older(model) > 0 or not model.has_older(), "cada tanda agrega entradas")
		loads += 1
	assert_false(model.has_older(), "llega al primer turno (%d tandas)" % loads)
	assert_eq(model.entries()[0].text, "Pedido 1: revisá el nivel y arreglá lo que encuentres.", "empieza en el primer pedido")
	var full := SessionModel.new()
	SessionHistory.replay(history.load_record(ID), full)
	assert_eq(_agent_text(model), _agent_text(full), "los mismos mensajes del agente")
	assert_eq(_call_states(model), _call_states(full), "los mismos tool calls, cada uno con su estado final")
	_cleanup()


func test_model_drops_whole_turns_and_marks_keep_their_place() -> void:
	var events: Array = []
	for turn in 4:
		events.append({"type": "user", "text": "turno %d" % turn})
		for i in 3:
			events.append(_update({"sessionUpdate": "tool_call", "toolCallId": "t%d-%d" % [turn, i], "title": "Bash", "status": "in_progress"}))
			events.append(_update({"sessionUpdate": "tool_call_update", "toolCallId": "t%d-%d" % [turn, i], "status": "completed"}))
		events.append(_update({"sessionUpdate": "agent_message_chunk", "content": {"type": "text", "text": "listo %d" % turn}}))
		events.append({"type": "turn_end", "reason": "end_turn"})
	var history := _history(events)
	var model := SessionModel.new()
	model.session_id = ID
	SessionHistory.replay(history.load_record(ID), model)
	assert_eq(model.entries().size(), 12, "usuario, grupo y mensaje por turno")
	var mark := model.entry_mark()
	var third_turn := model.entry_mark() - 6
	var dropped: Array[int] = []
	model.entries_dropped.connect(func(count: int) -> void: dropped.append(count))
	assert_eq(model.drop_front(5), 3, "corta al principio de un turno, no a la mitad")
	assert_eq(dropped, [3], "avisa cuántas soltó")
	assert_eq(model.entries()[0].text, "turno 1", "el primer turno que queda")
	assert_eq(model.first_event, 9, "desde el evento de ese mensaje")
	assert_true(model.tool_call("t0-0") == null and model.tool_call("t1-0") != null, "suelta los tool calls de lo soltado")
	assert_eq(model.entry_mark(), mark, "la marca de fin no se corre")
	assert_eq(model.entries()[model.entry_index(third_turn)].text, "turno 2", "una marca vieja sigue apuntando a su entrada")
	assert_eq(model.entry_index(0), 0, "una marca de lo soltado va al principio")

	assert_eq(history.load_older(model), 3, "vuelve lo soltado")
	assert_eq(model.entries()[0].text, "turno 0", "en orden")
	assert_false(model.has_older(), "ya está todo")
	assert_eq(model.entries()[model.entry_index(third_turn)].text, "turno 2", "la marca sigue en su lugar")
	assert_true(model.tool_call("t0-0") != null and model.tool_call("t0-0").is_finished(), "con sus tool calls terminados")
	_cleanup()


func test_export_model_has_the_whole_session() -> void:
	var events := ResumeCheck.synthetic_events(5000)
	var history := _history(events)
	var model := SessionModel.new()
	model.session_id = ID
	SessionHistory.replay(history.load_record(ID, 1000), model)
	var full := SessionModel.new()
	SessionHistory.replay(history.load_record(ID), full)
	var joined: RefCounted = history.full_model(model)
	assert_true(joined != model, "arma uno aparte")
	assert_eq(_agent_text(joined), _agent_text(full), "con la conversación entera")
	assert_true(model.has_older(), "sin tocar el de la sesión")
	_cleanup()


func test_begin_from_a_tail_keeps_counting_from_the_total() -> void:
	var history := _history(ResumeCheck.synthetic_events(4000))
	var record := history.load_record(ID, 500)
	history.begin(ID, "p", "A", "/tmp", record)
	assert_eq(history.next_event_index(), 4000, "el próximo evento va después de todos, no de la cola")
	history.end()
	_cleanup()


func test_view_asks_for_older_and_shows_them() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var history := _history(ResumeCheck.synthetic_events(3000))
	var model := SessionModel.new()
	model.session_id = ID
	SessionHistory.replay(history.load_record(ID, 300), model)
	var view := ConversationView.new()
	view.setup(model, Color.ORANGE)
	view.older_requested.connect(func() -> void: history.load_older(model))
	tree.root.add_child(view)
	await tree.process_frame  # _ready corre en el frame siguiente
	while view.is_building():
		await tree.process_frame
	assert_eq(view.hidden_count(), 0, "todo lo leído tiene vista")
	var before := view.entry_count()
	var first_shown: int = (view.get(&"_order") as Array)[0]
	var button: Button = view.get(&"_show_older")
	assert_true(button.visible, "hay más en el historial")
	view.show_older()
	assert_true(view.entry_count() > before, "«Mostrar anteriores» trae las del archivo (%d → %d)" % [before, view.entry_count()])
	var order: Array = view.get(&"_order")
	var index_of := func(id: int) -> int:
		for i in model.entries().size():
			if model.entries()[i].id == id:
				return i
		return -1
	assert_true(index_of.call(order[0]) < index_of.call(first_shown), "las nuevas van antes de las que se veían")
	assert_eq((view.get(&"_list") as Node).get_child(1), (view.get(&"_views") as Dictionary)[order[0]], "arriba de todo")
	view.queue_free()
	_cleanup()


func test_view_drops_hidden_entries_after_a_turn() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var model := SessionModel.new()
	var view := ConversationView.new()
	view.setup(model, Color.ORANGE)
	tree.root.add_child(view)
	model.event_cursor = 0
	for turn in 60:
		model.event_cursor = turn * 10
		model.add_user_message("turno %d" % turn)
		for i in 9:
			model.add_notice("aviso %d" % i)
	model.event_cursor = -1
	await tree.process_frame
	while view.is_building():
		await tree.process_frame
	assert_eq(view.hidden_count(), 600 - ConversationView.MAX_VIEWS, "las viejas quedan ocultas")
	model.finish_turn("end_turn")
	assert_true(view.hidden_count() <= ConversationView.HIDDEN_KEEP, "al terminar el turno se sueltan (%d ocultas)" % view.hidden_count())
	assert_true(model.entries().size() <= ConversationView.MAX_VIEWS + ConversationView.HIDDEN_KEEP + 10, "y el modelo queda acotado (%d)" % model.entries().size())
	assert_true(model.has_older(), "lo soltado se puede volver a leer")
	view.queue_free()


static func _agent_text(model: RefCounted) -> String:
	var parts: PackedStringArray = []
	for entry: ChatEntry in model.call(&"entries"):
		if entry.kind == ChatEntry.EntryKind.AGENT:
			parts.append(entry.text)
	return "".join(parts)


static func _call_states(model: RefCounted) -> Dictionary:
	var states := {}
	for entry: ChatEntry in model.call(&"entries"):
		for id: String in entry.tool_call_ids:
			states[id] = model.call(&"tool_call", id).status
	return states
