@tool
extends RefCounted
## Lo que recibió el agente por fuera del chat (m12-61): Claude Code arranca un turno solo cuando le
## llega un mensaje de otra sesión suya (SendMessage) o termina una tarea en segundo plano, y
## claude-agent-acp no reenvía esa entrada. Claude Code sí la escribe en su transcript
## (`<carpeta de la cuenta>/projects/<proyecto>/<sesión>.jsonl`): de la cola de ese archivo se saca la
## entrada del turno, para mostrarla en el chat antes de la respuesta.
##
## Cada entrada del transcript es una línea JSON. Las que importan son `type: "user"` con `origin`:
## - `{kind: "human"}`: lo que escribió el usuario (en el editor, el prompt del dock).
## - `{kind: "peer", name, from, body}`: un mensaje de otra sesión; `body` es el texto.
## - `{kind: "task-notification"}`: terminó una tarea; `message.content` lleva `<status>` y `<summary>`.

const ProjectMemory := preload("../core/project_memory.gd")
const I18n := preload("../core/i18n.gd")

const KIND_PEER := "peer"
const KIND_TASK := "task"
## Cuánto del final del archivo se lee: alcanza para varios turnos, y leerlo no traba el editor.
const TAIL_BYTES := 262144
## Las entradas de un turno que se muestran, como mucho.
const MAX_INPUTS := 5


## La etiqueta de una entrada de afuera en el chat (ChatEntry.incoming): «De opus-0», «Terminó una
## tarea en segundo plano». `translate` false = en inglés (el export).
static func caption(incoming: Dictionary, translate: bool = true) -> String:
	if str(incoming.get("kind", "")) == KIND_TASK:
		var status := str(incoming.get("status", ""))
		var finished := I18n.t("Background task finished") if translate else "Background task finished"
		return finished if status.is_empty() or status == "completed" else "%s (%s)" % [finished, status]
	var from := str(incoming.get("from", ""))
	if from.is_empty():
		return I18n.t("From another session") if translate else "From another session"
	return (I18n.t("From %s") if translate else "From %s") % from


## El final del archivo en líneas, sin la primera (que puede estar cortada a la mitad si no se leyó
## desde el principio). Vacío si no se puede leer.
static func read_tail(path: String, max_bytes: int = TAIL_BYTES) -> PackedStringArray:
	if path.is_empty() or not FileAccess.file_exists(path):
		return PackedStringArray()
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return PackedStringArray()
	var length := file.get_length()
	var start := maxi(0, length - max_bytes)
	file.seek(start)
	var text := file.get_buffer(length - start).get_string_from_utf8()
	var lines := text.split("\n", false)
	if start > 0 and not lines.is_empty():
		lines.remove_at(0)
	return lines


## Las entradas de afuera que arrancaron el último turno, de la más vieja a la más nueva:
## `[{uuid, kind, from, status, text}]`. Se recorre desde el final salteando lo que el agente ya
## escribió en este turno (sus mensajes, los resultados de sus tools); la primera entrada de alguien
## que no es el agente define el turno: si es de afuera, se juntan las de afuera seguidas (pueden
## llegar varias juntas). Un prompt del usuario, una entrada ya mostrada (`seen`: uuid → true) o
## haberlas juntado y volver a encontrar algo del agente cortan la búsqueda. Si la primera no es de
## afuera, no devuelve nada.
static func latest(lines: PackedStringArray, seen: Dictionary = {}, max_inputs: int = MAX_INPUTS) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	for i in range(lines.size() - 1, -1, -1):
		var line := lines[i]
		# Antes de parsear: la mayoría de las líneas son del agente y no hace falta mirarlas a fondo.
		if found.is_empty() and not line.contains("\"origin\""):
			continue
		var data: Variant = JSON.parse_string(line)
		if not data is Dictionary:
			continue
		var type := str(data.get("type", ""))
		if type == "assistant":
			if found.is_empty():
				continue
			break
		if type != "user":
			continue
		var message: Variant = data.get("message")
		var content: Variant = message.get("content") if message is Dictionary else null
		var origin: Variant = data.get("origin")
		if not origin is Dictionary:
			# Un resultado de tool (lista) o un mensaje del sistema sin origen: del agente.
			if found.is_empty():
				continue
			break
		var input := _input(data, origin, content)
		if input.is_empty() or seen.has(input.uuid):
			break
		found.push_front(input)
		if found.size() >= max_inputs:
			break
	return found


static func _input(data: Dictionary, origin: Dictionary, content: Variant) -> Dictionary:
	var uuid := str(data.get("uuid", ""))
	if uuid.is_empty():
		return {}
	match str(origin.get("kind", "")):
		"peer":
			var body := str(origin.get("body", ""))
			if body.is_empty() and content is String:
				body = _peer_body(content)
			return {"uuid": uuid, "kind": KIND_PEER, "from": str(origin.get("name", origin.get("from", ""))), "status": "",
				"text": body.strip_edges()}
		"task-notification":
			var text := str(content) if content is String else ""
			var summary := _tag(text, "summary")
			var note := _tag(text, "note")
			if not note.is_empty():
				summary = (summary + "\n\n" + note).strip_edges()
			return {"uuid": uuid, "kind": KIND_TASK, "from": "", "status": _tag(text, "status"),
				"text": summary if not summary.is_empty() else text.strip_edges()}
	return {}


## El texto de `<name>…</name>`; "" si no está.
static func _tag(text: String, name: String) -> String:
	var open := "<%s>" % name
	var start := text.find(open)
	if start < 0:
		return ""
	start += open.length()
	var end := text.find("</%s>" % name, start)
	return text.substr(start, (end if end >= 0 else text.length()) - start).strip_edges()


## Lo que va dentro de `<cross-session-message …>…</cross-session-message>`, por si falta `body`.
static func _peer_body(text: String) -> String:
	var tag := text.find("<cross-session-message")
	var start := text.find(">", tag) if tag >= 0 else -1
	var end := text.find("</cross-session-message>", start) if start >= 0 else -1
	return text.substr(start + 1, end - start - 1) if end > start else ""


## El archivo del transcript de `session_id` en la carpeta de la cuenta `config_dir`: primero en la
## carpeta del proyecto `cwd` (el nombre que le da Claude Code); si no está (rutas muy largas que
## Claude Code acorta), se busca en las de todos los proyectos. "" si no está.
static func transcript_path(config_dir: String, cwd: String, session_id: String) -> String:
	if config_dir.is_empty() or session_id.is_empty() or not session_id.is_valid_filename():
		return ""
	var projects := config_dir.path_join("projects")
	var direct := projects.path_join(ProjectMemory.claude_project_slug(cwd)).path_join(session_id + ".jsonl")
	if FileAccess.file_exists(direct):
		return direct
	var access := DirAccess.open(projects)
	if access == null:
		return ""
	for project: String in access.get_directories():
		var path := projects.path_join(project).path_join(session_id + ".jsonl")
		if FileAccess.file_exists(path):
			return path
	return ""
