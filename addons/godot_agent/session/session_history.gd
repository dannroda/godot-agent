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

const DIR := "user://godot_agent/sessions"
const INDEX_FILE := "index.json"
const EXTENSION := ".jsonl"
const FORMAT := 2
const MAX_SESSIONS := 100
const MAX_EVENTS := 20000
const MAX_TOOL_TEXT := 4000
const MAX_DIFF_TEXT := 40000
const TITLE_CHARS := 70
const IMAGE_PLACEHOLDER := "[screenshot: not stored in the history]"
const SKIPPED_UPDATES: PackedStringArray = ["usage_update", "available_commands_update", "current_mode_update", "config_option_update", "config_options_update"]
const CHUNK_UPDATES: PackedStringArray = ["agent_message_chunk", "agent_thought_chunk", "user_message_chunk"]

var dir: String = DIR
## () -> int: reloj unix (los tests lo fijan).
var now_provider: Callable = func() -> int: return int(Time.get_unix_time_from_system())

## Sesión que se está grabando ({} si ninguna): {format, id, profile_id, agent, cwd, title, created, updated, turns, events_count, truncated}.
var _meta: Dictionary = {}
## Eventos todavía no escritos (el turno en curso).
var _pending: Array[Dictionary] = []
var _dirty: bool = false
var _writer := Writer.new()


func is_recording() -> bool:
	return not _meta.is_empty()


func current_id() -> String:
	return str(_meta.get("id", ""))


## Empieza a grabar una sesión nueva o, si `previous` viene del historial, sigue en su archivo.
func begin(session_id: String, profile_id: String, agent_name: String, cwd: String, previous: Dictionary = {}) -> void:
	end()
	if not _valid_id(session_id):
		return
	var now: int = now_provider.call()
	if previous.get("id") == session_id:
		_meta = previous.duplicate()
		_meta.erase("events")
		_meta.events_count = (previous.get("events", []) as Array).size()
		_meta.updated = now
		# Sin entrada en el índice (borrado o de otro formato), el registro trae solo la cabecera.
		_meta.merge({"title": "", "turns": 0, "truncated": false})
	else:
		_meta = {"format": FORMAT, "id": session_id, "profile_id": profile_id, "agent": agent_name, "cwd": cwd,
			"title": "", "created": now, "updated": now, "turns": 0, "events_count": 0, "truncated": false}
	_dirty = false


func record_prompt(text: String) -> void:
	if text.strip_edges().is_empty() or not is_recording():
		return
	if str(_meta.title).is_empty():
		_meta.title = title_from(text)
	_meta.turns = int(_meta.turns) + 1
	_append({"type": "user", "text": text})


func record_update(update: Dictionary) -> void:
	var kind := str(update.get("sessionUpdate", ""))
	if not is_recording() or kind in SKIPPED_UPDATES:
		return
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
	_meta.updated = now_provider.call()
	var header := {"format": FORMAT, "id": _meta.id, "profile_id": _meta.profile_id, "agent": _meta.agent, "cwd": _meta.cwd, "created": _meta.created}
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


## Sesiones guardadas, la más reciente primero: [{id, title, profile_id, agent, cwd, created, updated, turns, truncated}].
## `cwd` filtra por proyecto ("" = todas).
func list(cwd: String = "") -> Array[Dictionary]:
	flush()
	var result: Array[Dictionary] = []
	for item: Dictionary in _read_index(_abs_dir()):
		if cwd.is_empty() or item.get("cwd") == cwd:
			result.append(item)
	return result


## El registro completo ({metadatos del índice…, events}), o {} si no existe o está roto.
func load_record(id: String) -> Dictionary:
	flush()
	if not _valid_id(id) or not FileAccess.file_exists(_abs_path(id)):
		return {}
	var file := FileAccess.open(_abs_path(id), FileAccess.READ)
	if file == null:
		return {}
	var header: Variant = JSON.parse_string(file.get_line())
	if not header is Dictionary or int(header.get("format", 0)) != FORMAT or header.get("id") != id:
		return {}
	var events: Array = []
	while not file.eof_reached():
		var line := file.get_line()
		if line.is_empty():
			continue
		var event: Variant = JSON.parse_string(line)
		if event is Dictionary:
			events.append(event)
	var record: Dictionary = header
	for item: Dictionary in _read_index(_abs_dir()):
		if item.id == id:
			record.merge(item)
	record.events = events
	return record


func remove(id: String) -> void:
	if _valid_id(id):
		_enqueue({"kind": "remove", "path": _abs_path(id), "id": id})


## Vuelve a armar la conversación en `model` (que ya tiene que estar vacío).
static func replay(record: Dictionary, model: SessionModel) -> void:
	model.replaying = true
	for event: Variant in record.get("events", []):
		if not event is Dictionary:
			continue
		match str(event.get("type", "")):
			"user":
				model.add_user_message(str(event.get("text", "")))
			"update":
				if event.get("update") is Dictionary:
					model.apply_update(event.update)
			"turn_end":
				model.finish_turn(str(event.get("reason", "end_turn")))
	var title := str(record.get("title", ""))
	if not title.is_empty() and model.title.is_empty():
		model.apply_update({"sessionUpdate": "session_info_update", "title": title})
	model.replaying = false


static func summary_of(meta: Dictionary) -> Dictionary:
	return {"id": meta.id, "title": meta.get("title", ""), "profile_id": meta.get("profile_id", ""),
		"agent": meta.get("agent", ""), "cwd": meta.get("cwd", ""), "created": meta.get("created", 0),
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
class Writer extends RefCounted:
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
static func _drain(writer: Writer) -> void:
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
	var path := abs_dir.path_join(INDEX_FILE)
	var temp := path + ".tmp"
	var file := FileAccess.open(temp, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify({"format": FORMAT, "sessions": index}))
	file.close()
	return DirAccess.rename_absolute(temp, path)
