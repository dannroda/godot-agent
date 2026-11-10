@tool
extends RefCounted
## Una entrada de la conversación tal como la muestra el dock.

enum EntryKind { USER, AGENT, THOUGHT, TOOL_GROUP, PLAN, PERMISSION, ELICITATION, NOTICE }

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
## ELICITATION: el ElicitationRequest (m11-17).
var elicitation: RefCounted
## NOTICE
var level: NoticeLevel = NoticeLevel.INFO
## NOTICE: título en negrita arriba del texto, y líneas del log (monoespaciado, con «Copiar»)
## debajo (m12-13).
var title: String = ""
var details: String = ""
## Las mismas líneas sin recortar (ya redactadas), para «Copy» (m13-22): un reporte de bug las quiere
## enteras. Vacío = se copia `details`.
var details_full: String = ""
## NOTICE: pie del turno (m12-20): una línea con los cambios y las acciones como enlaces, sin caja.
var footer: bool = false
## NOTICE: acciones sugeridas (`[{id, label}]`), p. ej. "Reintentar" o "Ver log".
var actions: Array[Dictionary] = []
var created_unix: float = 0.0
## AGENT: el harness ya leyó su bloque `findings` (modo Revisar) y el chat lo muestra plegado con
## esta cantidad de hallazgos (m12-38); -1 = no hubo bloque leído.
var findings_count: int = -1
## Imágenes u otros bloques no textuales adjuntos (USER).
var attachments: Array[Dictionary] = []
## USER que mandó el harness, no el usuario (m12-44): el msgid en inglés de su etiqueta (ver
## HarnessPrompts). Vacío = lo escribió el usuario.
var harness_label: String = ""
