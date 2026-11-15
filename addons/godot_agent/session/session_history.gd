@tool
extends RefCounted
## Historial de sesiones (spec §11, M7): `user://godot_agent/sessions/<id>.jsonl` con los eventos ACP
## normalizados, para reabrir y mostrar. Reanudar de verdad es `session/load` (SessionController).
##
## Normalizar = guardar lo que hace falta para volver a armar la conversación y nada más:
## - los chunks seguidos del mismo mensaje se juntan en uno;
## - las capturas no se guardan (pesan cientos de KB en base64) y los textos largos se recortan;
## - lo que es estado de la sesión y no conversación (uso, comandos, modos, opciones) no se guarda.
## Nada de esto lleva secretos: el token MCP va en la config de session/new, que no se registra.
##
## Formato: JSON Lines, una cabecera y después un evento por línea. Al fin de cada turno solo se
## agregan los eventos nuevos, así guardar no crece con la sesión (reescribir un JSON de 3 MB son
## ~50 ms). Título, fechas y turnos van en `index.json`. Una línea cortada por un cierre a mitad de
## escritura se saltea al leer. Las escrituras van a un worker, en orden; las lecturas lo esperan.

const SessionModel := preload("session_model.gd")
const AtomicFile := preload("../core/atomic_file.gd")

const DIR := "user://godot_agent/sessions"
const INDEX_FILE := "index.json"
const EXTENSION := ".jsonl"
const FORMAT := 2
const MAX_SESSIONS := 100
const MAX_EVENTS := 20000
## Eventos que se leen al reanudar (m7-55): los últimos, desde un punto donde no queda nada a medias.
## Lo anterior se lee con «Mostrar anteriores» (load_older), de a OLDER_EVENTS.
const TAIL_EVENTS := 3000
const OLDER_EVENTS := 1500
const READ_BLOCK := 1 << 20
const MAX_TOOL_TEXT := 4000
const MAX_DIFF_TEXT := 40000
const TITLE_CHARS := 70
## Durante un turno largo se guarda cada tanto: un turno que nunca termina (el agente se colgó, el
## editor se cerró) no se pierde entero (m17-16).
const SAVE_INTERVAL_MSEC := 15000
const IMAGE_PLACEHOLDER := "[screenshot: not stored in the history]"
const SKIPPED_UPDATES: PackedStringArray = ["usage_update", "available_commands_update", "current_mode_update", "config_option_update", "config_options_update"]
const CHUNK_UPDATES: PackedStringArray = ["agent_message_chunk", "agent_thought_chunk", "user_message_chunk"]

var dir: String = DIR
## () -> int: reloj unix (los tests lo fijan).
var now_provider: Callable = func() -> int: return int(Time.get_unix_time_from_system())

## Sesión que se está grabando ({} si ninguna): {format, id, profile_id, account, agent, cwd, title, created, updated, turns, events_count, truncated}.
## `account`: la carpeta de la cuenta de Claude Code elegida en la pestaña ("" si la del perfil).
var _meta: Dictionary = {}
## Eventos todavía no escritos (el turno en curso).
var _pending: Array[Dictionary] = []
var _dirty: bool = false
var _writer := HistoryWriter.new()
var _last_save_msec: int = 0
## compactionId ya grabados en esta sesión (m11-60): de cada compactación queda solo su estado final.
var _compactions_recorded: Dictionary = {}


func is_recording() -> bool:
	return not _meta.is_empty()


func current_id() -> String:
	return str(_meta.get("id", ""))


## Índice que va a tener el próximo evento que se grabe (el de la entrada que se está por crear).
func next_event_index() -> int:
	return int(_meta.get("events_count", 0)) if is_recording() else -1


## Empieza a grabar una sesión nueva o, si `previous` viene del historial, sigue en su archivo.
func begin(session_id: String, profile_id: String, agent_name: String, cwd: String, previous: Dictionary = {}, account: String = "") -> void:
	end()
	if not _valid_id(session_id):
		return
	var now: int = now_provider.call()
	if previous.get("id") == session_id:
		_meta = previous.duplicate()
		_meta.erase("events")
		_meta.events_count = int(previous.get("events_total", (previous.get("events", []) as Array).size()))
		_meta.erase("events_total")
		_meta.erase("events_offset")
		_meta.updated = now
		# Sin entrada en el índice (borrado o de otro formato), el registro trae solo la cabecera; una
		# sesión que solo lista el agente (session/list, m11-16) no trae ni eso.
		_meta.merge({"title": "", "turns": 0, "truncated": false, "format": FORMAT, "profile_id": profile_id,
			"agent": agent_name, "cwd": cwd, "created": now, "account": account})
		_meta.erase("from_agent")
	else:
		_meta = {"format": FORMAT, "id": session_id, "profile_id": profile_id, "account": account, "agent": agent_name, "cwd": cwd,
			"title": "", "created": now, "updated": now, "turns": 0, "events_count": 0, "truncated": false}
	_dirty = false
	_compactions_recorded.clear()
	_last_save_msec = Time.get_ticks_msec()


func record_prompt(text: String, harness_label: String = "") -> void:
	if text.strip_edges().is_empty() or not is_recording():
		return
	if str(_meta.title).is_empty():
		_meta.title = title_from(text)
	_meta.turns = int(_meta.turns) + 1
	var event := {"type": "user", "text": text}
	if not harness_label.is_empty():
		event.harness = harness_label
	_append(event)
	save()


func record_update(update: Dictionary) -> void:
	var kind := str(update.get("sessionUpdate", ""))
	if not is_recording() or kind in SKIPPED_UPDATES:
		return
	_record_update(update, kind)
	if Time.get_ticks_msec() - _last_save_msec >= SAVE_INTERVAL_MSEC:
		save()


func _record_update(update: Dictionary, kind: String) -> void:
	if kind == "compaction_update":
		# Solo el estado final, una vez: sin in_progress ni el completed repetido sin summary.
		var id := str(update.get("compactionId", ""))
		if str(update.get("status", "")) == "in_progress" or _compactions_recorded.has(id):
			return
		_compactions_recorded[id] = true
	if kind == "session_info_update" and update.get("title") is String and not str(update.title).is_empty():
		_meta.title = str(update.title)
		_dirty = true
	if kind in CHUNK_UPDATES:
		var text := SessionModel.content_to_text(update.get("content"))
		if text.is_empty():
			text = IMAGE_PLACEHOLDER if _is_image(update.get("content")) else ""
		if text.is_empty():
			return
		var message_id := str(update.get("messageId", "")) if update.get("messageId") != null else ""
		var parent := SessionModel.parent_tool_call_id(update)
		var last: Dictionary = _pending.back() if not _pending.is_empty() else {}
		if last.get("type") == "update" and last.update.get("sessionUpdate") == kind and str(last.update.get("messageId", "")) == message_id \
				and SessionModel.parent_tool_call_id(last.update) == parent:
			last.update.content.text += text
			return
		var chunk := {"sessionUpdate": kind, "content": {"type": "text", "text": text}}
		if not message_id.is_empty():
			chunk.messageId = message_id
		if not parent.is_empty():
			chunk._meta = {"claudeCode": {"parentToolUseId": parent}}
		_append({"type": "update", "update": chunk})
		return
	_append({"type": "update", "update": normalize_update(update)})


## Fin de turno: se graba y se guarda (una escritura por turno, no por chunk).
func record_turn_end(stop_reason: String) -> void:
	_append({"type": "turn_end", "reason": stop_reason})
	save()


## Guarda y deja de grabar.
func end() -> void:
	if is_recording():
		save()
	_meta = {}
	_pending.clear()
	_dirty = false


## Pasa los eventos pendientes al escritor (un worker): con el disco ocupado, abrir y escribir el
## archivo llegó a tardar 600 ms, y eso no puede pasar en el hilo principal.
func save() -> void:
	if not is_recording() or (not _dirty and _pending.is_empty()):
		return
	_last_save_msec = Time.get_ticks_msec()
	_meta.updated = now_provider.call()
	var header := {"format": FORMAT, "id": _meta.id, "profile_id": _meta.profile_id, "account": _meta.get("account", ""), "agent": _meta.agent, "cwd": _meta.cwd, "created": _meta.created}
	_enqueue({"kind": "append", "path": _abs_path(current_id()), "header": header, "events": _pending, "summary": summary_of(_meta)})
	_pending = []  # el worker se queda con el array anterior
	_dirty = false


## Espera a que el escritor termine (antes de leer, y al cerrar el plugin).
func flush() -> void:
	_writer.mutex.lock()
	var task := _writer.task
	_writer.task = -1
	_writer.mutex.unlock()
	if task >= 0:
		WorkerThreadPool.wait_for_task_completion(task)


## Sesiones guardadas, la más reciente primero: [{id, title, profile_id, account, agent, cwd, created, updated, turns, truncated}].
## `cwd` filtra por proyecto ("" = todas).
func list(cwd: String = "") -> Array[Dictionary]:
	flush()
	var result: Array[Dictionary] = []
	for item: Dictionary in _read_index(_abs_dir()):
		if cwd.is_empty() or item.get("cwd") == cwd:
			result.append(item)
	return result


## El registro ({metadatos del índice…, events, events_offset, events_total}), o {} si no existe o está
## roto. Con `tail` > 0 trae solo los últimos `tail` eventos, desde un punto seguro (safe_start), sin
## leer el resto: `events_offset` es el índice del primero y `events_total` cuántos hay (m7-55).
func load_record(id: String, tail: int = 0) -> Dictionary:
	flush()
	var path := _abs_path(id)
	if not _valid_id(id) or not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var header: Variant = JSON.parse_string(file.get_line())
	if not header is Dictionary or int(header.get("format", 0)) != FORMAT or header.get("id") != id:
		return {}
	var offsets := line_offsets(file)
	var start := maxi(0, offsets.size() - tail) if tail > 0 else 0
	var events := _read_events(file, offsets, start, offsets.size())
	if start > 0:
		var safe := safe_start(events)
		events = events.slice(safe)
		start += safe
	var record: Dictionary = header
	for item: Dictionary in _read_index(_abs_dir()):
		if item.id == id:
			record.merge(item)
	record.events = events
	record.events_offset = start
	record.events_total = offsets.size()
	return record


## Los eventos anteriores a `end` (índice en el archivo), hasta OLDER_EVENTS, desde un punto seguro:
## {events, events_offset}. {} si no hay nada antes.
func load_range_before(id: String, end: int, count: int = OLDER_EVENTS) -> Dictionary:
	flush()
	var path := _abs_path(id)
	if end <= 0 or not _valid_id(id) or not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	file.get_line()
	var offsets := line_offsets(file)
	end = mini(end, offsets.size())
	var start := maxi(0, end - count)
	var events := _read_events(file, offsets, start, end)
	if start > 0:
		var safe := safe_start(events)
		events = events.slice(safe)
		start += safe
	return {"events": events, "events_offset": start}


## Dónde empieza cada evento (cada línea después de la cabecera) en `file`, que tiene que estar justo
## después de la cabecera. Busca saltos de línea por bloques, sin parsear JSON.
static func line_offsets(file: FileAccess) -> PackedInt64Array:
	var offsets: PackedInt64Array = []
	var length := file.get_length()
	var position := file.get_position()
	var line_start := position
	while position < length:
		var block := file.get_buffer(mini(READ_BLOCK, length - position))
		var from := 0
		while true:
			var newline := block.find(10, from)
			if newline < 0:
				break
			if position + newline > line_start:
				offsets.append(line_start)
			line_start = position + newline + 1
			from = newline + 1
		position += block.size()
	if line_start < length:
		offsets.append(line_start)
	return offsets


static func _read_events(file: FileAccess, offsets: PackedInt64Array, start: int, end: int) -> Array:
	var events: Array = []
	if start >= end:
		return events
	file.seek(offsets[start])
	for i in range(start, end):
		var event: Variant = JSON.parse_string(file.get_line())
		# Una línea cortada o rota cuenta igual: el índice de cada evento es su línea.
		events.append(event if event is Dictionary else {})
	return events


## El primer índice de `events` desde el que se puede armar la conversación sin lo anterior: ningún
## evento de ahí en adelante sigue un tool call (o un subagente) que empezó antes, y empieza una entrada
## (un mensaje del usuario, un tool call o el primer trozo de un mensaje). 0 si no hay ninguno.
static func safe_start(events: Array) -> int:
	var opened := {}  # toolCallId -> índice de su tool_call
	var blocked := PackedInt32Array()
	blocked.resize(events.size() + 1)
	for i in events.size():
		var update: Variant = events[i].get("update") if events[i] is Dictionary else null
		if not update is Dictionary:
			continue
		var ids: PackedStringArray = []
		var id := str(update.get("toolCallId", ""))
		if not id.is_empty():
			if update.get("sessionUpdate") == "tool_call" and not opened.has(id):
				opened[id] = i
			ids.append(id)
		var parent := SessionModel.parent_tool_call_id(update)
		if not parent.is_empty():
			ids.append(parent)
		for referenced: String in ids:
			# De su tool_call (o del principio, si empezó antes de lo leído) hasta acá no se puede cortar.
			var from: int = int(opened.get(referenced, -1)) + 1
			if from <= i:
				blocked[from] += 1
				blocked[i + 1] -= 1
	var depth := 0
	for i in events.size():
		depth += blocked[i]
		if depth == 0 and _starts_entry(events, i):
			return i
	return 0


static func _starts_entry(events: Array, i: int) -> bool:
	var event: Variant = events[i]
	if not event is Dictionary:
		return false
	if event.get("type") == "user":
		return true
	var update: Variant = event.get("update")
	if event.get("type") != "update" or not update is Dictionary:
		return false
	var kind := str(update.get("sessionUpdate", ""))
	if kind == "tool_call":
		return true
	if not kind in CHUNK_UPDATES:
		return false
	# El trozo sigue el mensaje anterior si lo último que armó una entrada fue un trozo del mismo tipo:
	# los tool_call_update de llamadas que ya existen no arman nada en el medio.
	for back in range(i - 1, -1, -1):
		var previous: Variant = events[back].get("update") if events[back] is Dictionary else null
		if previous is Dictionary and previous.get("sessionUpdate") == "tool_call_update":
			continue
		return not (previous is Dictionary and previous.get("sessionUpdate") == kind)
	return false


func remove(id: String) -> void:
	if _valid_id(id):
		_enqueue({"kind": "remove", "path": _abs_path(id), "id": id})


## Vuelve a armar la conversación en `model` (que ya tiene que estar vacío). Cada entrada guarda el
## índice de su evento en el archivo (events_offset + posición), para leer después lo anterior.
static func replay(record: Dictionary, model: SessionModel) -> void:
	model.replaying = true
	var offset := int(record.get("events_offset", 0))
	model.first_event = offset
	var index := offset
	for event: Variant in record.get("events", []):
		model.event_cursor = index
		index += 1
		if not event is Dictionary:
			continue
		match str(event.get("type", "")):
			"user":
				model.add_user_message(str(event.get("text", "")), [], str(event.get("harness", "")))
			"update":
				if event.get("update") is Dictionary:
					model.apply_update(event.update)
			"turn_end":
				model.finish_turn(str(event.get("reason", "end_turn")))
	model.event_cursor = -1
	var title := str(record.get("title", ""))
	if not title.is_empty() and model.title.is_empty():
		model.apply_update({"sessionUpdate": "session_info_update", "title": title})
	model.replaying = false


## Lee del historial la parte anterior a lo que tiene `model` y la pone al principio (m7-55). `redact`:
## Callable(Dictionary) -> Dictionary que saca los secretos (como al reanudar). Devuelve cuántas
## entradas agregó.
func load_older(model: SessionModel, redact: Callable = Callable()) -> int:
	if not model.has_older() or model.session_id.is_empty():
		return 0
	var older := load_range_before(model.session_id, model.first_event)
	if older.is_empty():
		model.first_event = 0
		return 0
	if redact.is_valid():
		older = redact.call(older)
	var part := SessionModel.new()
	replay(older, part)
	var added := part.entries().size()
	model.prepend(part)
	return added


## La conversación entera para recorrerla (el export): `model` mismo si la tiene toda en memoria, o un
## modelo de solo lectura con lo anterior leído del historial antes de lo que tiene.
func full_model(model: SessionModel, redact: Callable = Callable()) -> SessionModel:
	if not model.has_older() or model.session_id.is_empty():
		return model
	var older := load_range_before(model.session_id, model.first_event, MAX_EVENTS)
	if older.is_empty():
		return model
	if redact.is_valid():
		older = redact.call(older)
	var part := SessionModel.new()
	replay(older, part)
	return model.joined_after(part)


static func summary_of(meta: Dictionary) -> Dictionary:
	return {"id": meta.id, "title": meta.get("title", ""), "profile_id": meta.get("profile_id", ""),
		"account": meta.get("account", ""), "agent": meta.get("agent", ""), "cwd": meta.get("cwd", ""), "created": meta.get("created", 0),
		"updated": meta.get("updated", 0), "turns": meta.get("turns", 0), "truncated": meta.get("truncated", false)}


static func title_from(text: String) -> String:
	var line := text.strip_edges().split("\n")[0].strip_edges()
	return line if line.length() <= TITLE_CHARS else line.left(TITLE_CHARS - 1) + "…"


## tool_call / tool_call_update / plan, sin capturas, sin rawOutput y con los textos recortados. Del
## `_meta` quedan solo el nombre de la tool y el subagente que la hizo.
static func normalize_update(update: Dictionary) -> Dictionary:
	var result := update.duplicate(true)
	result.erase("rawOutput")
	result.erase("_meta")
	var meta: Variant = update.get("_meta")
	if meta is Dictionary and meta.get("claudeCode") is Dictionary:
		var kept := {}
		for key: String in ["toolName", "parentToolUseId"]:
			if meta.claudeCode.get(key) is String:
				kept[key] = meta.claudeCode[key]
		if not kept.is_empty():
			result._meta = {"claudeCode": kept}
	if result.get("content") is Array:
		var content: Array = []
		for item: Variant in result.content:
			if not item is Dictionary:
				continue
			var block: Variant = item.get("content")
			if block is Dictionary and block.get("type") == "image":
				content.append({"type": "content", "content": {"type": "text", "text": IMAGE_PLACEHOLDER}})
			elif item.get("type") == "diff" and str(item.get("oldText", "")).length() + str(item.get("newText", "")).length() > MAX_DIFF_TEXT:
				content.append({"type": "content", "content": {"type": "text", "text": "[diff of %s: too long for the history]" % str(item.get("path", "")).get_file()}})
			elif block is Dictionary and block.get("type") == "text" and str(block.get("text", "")).length() > MAX_TOOL_TEXT:
				content.append({"type": "content", "content": {"type": "text", "text": str(block.text).left(MAX_TOOL_TEXT) + "\n… (trimmed in the history)"}})
			else:
				content.append(item)
		result.content = content
	return result


func _append(event: Dictionary) -> void:
	if not is_recording():
		return
	if int(_meta.events_count) >= MAX_EVENTS:
		_meta.truncated = true
		_dirty = true
		return
	_pending.append(event)
	_meta.events_count = int(_meta.events_count) + 1


static func _is_image(content: Variant) -> bool:
	return content is Dictionary and content.get("type") == "image"


func _abs_dir() -> String:
	return ProjectSettings.globalize_path(dir)


func _abs_path(id: String) -> String:
	return _abs_dir().path_join(id + EXTENSION)


## Los ids vienen del agente: nada de rutas.
static func _valid_id(id: String) -> bool:
	return not id.is_empty() and id == id.validate_filename() and not id.begins_with(".")


# --- escritor (worker) ----------------------------------------------------------------------------

## Cola de escrituras en orden, procesada por una sola tarea del WorkerThreadPool a la vez.
class HistoryWriter extends RefCounted:
	var mutex := Mutex.new()
	var jobs: Array[Dictionary] = []
	var task: int = -1
	var running: bool = false


func _enqueue(job: Dictionary) -> void:
	job.dir = _abs_dir()
	_writer.mutex.lock()
	_writer.jobs.append(job)
	var start := not _writer.running
	var previous := _writer.task
	if start:
		_writer.running = true
	_writer.mutex.unlock()
	if not start:
		return
	if previous >= 0:
		WorkerThreadPool.wait_for_task_completion(previous)  # ya terminó o está por terminar
	# Callable sobre el script (no sobre self): el worker no depende de que este objeto siga vivo.
	var task := WorkerThreadPool.add_task(Callable(get_script(), &"_drain").bind(_writer), false, "godot_agent history")
	_writer.mutex.lock()
	_writer.task = task
	_writer.mutex.unlock()


## Corre en el worker. Solo usa lo que trae cada trabajo: nada del objeto que lo encoló.
static func _drain(writer: HistoryWriter) -> void:
	while true:
		writer.mutex.lock()
		if writer.jobs.is_empty():
			writer.running = false
			writer.mutex.unlock()
			return
		var job: Dictionary = writer.jobs.pop_front()
		writer.mutex.unlock()
		if job.kind == "append":
			_write_events(job)
		elif job.kind == "remove":
			DirAccess.remove_absolute(job.path)
			_write_index(job.dir, _read_index(job.dir).filter(func(item: Dictionary) -> bool: return item.id != job.id))


static func _write_events(job: Dictionary) -> void:
	var error := DirAccess.make_dir_recursive_absolute(job.dir)
	if error != OK and error != ERR_ALREADY_EXISTS:
		return
	var exists := FileAccess.file_exists(job.path)
	var file := FileAccess.open(job.path, FileAccess.READ_WRITE if exists else FileAccess.WRITE)
	if file == null:
		return
	# Si un cierre cortó la última línea, la próxima va en una línea nueva (la cortada se saltea al leer).
	if exists and file.get_length() > 0:
		file.seek(file.get_length() - 1)
		if file.get_8() != 10:
			file.seek_end()
			file.store_8(10)
	file.seek_end()
	if not exists:
		file.store_line(JSON.stringify(job.header))
	for event: Dictionary in job.events:
		file.store_line(JSON.stringify(event))
	file.close()
	var summary: Dictionary = job.summary
	var index: Array = _read_index(job.dir)
	index = index.filter(func(item: Dictionary) -> bool: return item.id != summary.id)
	index.push_front(summary)
	index.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.updated) > int(b.updated))
	while index.size() > MAX_SESSIONS:
		var dropped: Dictionary = index.pop_back()
		DirAccess.remove_absolute(str(job.dir).path_join(str(dropped.id) + EXTENSION))
	_write_index(job.dir, index)


static func _read_index(abs_dir: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var path := abs_dir.path_join(INDEX_FILE)
	if not FileAccess.file_exists(path):
		return result
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if data is Dictionary and int(data.get("format", 0)) == FORMAT and data.get("sessions") is Array:
		for item: Variant in data.sessions:
			if item is Dictionary and item.get("id") is String and _valid_id(item.id):
				result.append(item)
	return result


## Escribe en un temporal y lo renombra: un cierre a mitad de escritura no rompe el índice anterior.
static func _write_index(abs_dir: String, index: Array) -> Error:
	return AtomicFile.write_text(abs_dir.path_join(INDEX_FILE), JSON.stringify({"format": FORMAT, "sessions": index}))
