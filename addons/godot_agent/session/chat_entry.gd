@tool
extends RefCounted
## Una entrada de la conversación tal como la muestra el dock.

enum EntryKind { USER, AGENT, THOUGHT, TOOL_GROUP, PLAN, PERMISSION, NOTICE }

## Severidad de los NOTICE.
enum NoticeLevel { INFO, WARNING, ERROR }

var id: int = 0
var kind: EntryKind = EntryKind.AGENT
## USER / AGENT / THOUGHT / NOTICE: texto (Markdown en AGENT y THOUGHT).
var text: String = ""
## messageId de ACP para unir chunks del mismo mensaje.
var message_id: String = ""
## TOOL_GROUP: ids de los tool calls, en orden.
var tool_call_ids: PackedStringArray = []
## PLAN: `[{content, priority, status}]`.
var plan: Array = []
## PERMISSION: el PermissionRequest (M2).
var permission: RefCounted
## NOTICE
var level: NoticeLevel = NoticeLevel.INFO
## NOTICE: acciones sugeridas (`[{id, label}]`), p. ej. "Reintentar" o "Ver log".
var actions: Array[Dictionary] = []
var created_unix: float = 0.0
## Imágenes u otros bloques no textuales adjuntos (USER).
var attachments: Array[Dictionary] = []
