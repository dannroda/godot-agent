@tool
extends RefCounted
## Cuándo sugerir un traspaso (m11-35): una vez por sesión al pasar WARN_RATIO del contexto, y otra
## vez solo si el uso bajó de REARM_RATIO (el agente compactó o se borró el contexto) y volvió a subir.
## «✕» en el aviso lo calla hasta ese rearme. Que el agente compacte la conversación también se avisa:
## después de compactar se pierden detalles, y es el otro momento natural para seguir en otra sesión.

signal changed

const WARN_RATIO := 0.85
const REARM_RATIO := 0.6
## El tool call de Claude Code al compactar (sin la capacidad session.compaction del cliente).
const COMPACTION_TITLES: Array[String] = ["Compact conversation", "Compacting conversation"]

var ratio: float = 0.0
## El aviso está a la vista (pasó el umbral y nadie lo cerró).
var warning: bool = false
var _armed: bool = true


## Un usage_update. true si recién ahora hay que avisar.
func update(used: int, size: int) -> bool:
	if size <= 0:
		return false
	ratio = float(used) / float(size)
	var before := warning
	if ratio < REARM_RATIO:
		_armed = true
		warning = false
	elif ratio >= WARN_RATIO and _armed:
		_armed = false
		warning = true
	if warning != before:
		changed.emit()
	return warning and not before


func percent() -> int:
	return int(ratio * 100.0)


## «✕»: no vuelve hasta que el uso baje de REARM_RATIO.
func dismiss() -> void:
	if warning:
		warning = false
		changed.emit()


## Una sesión nueva (otra pestaña, otro session_id): empieza de cero.
func reset() -> void:
	ratio = 0.0
	_armed = true
	if warning:
		warning = false
		changed.emit()


## true si la actualización ACP es el agente compactando la conversación: el tool call de Claude Code
## (título o `_meta.claudeCode.toolName` «compact») o `compaction_update` (m11-60).
static func is_compaction(update: Dictionary) -> bool:
	var kind := str(update.get("sessionUpdate", ""))
	if kind == "compaction_update":
		return true
	if kind != "tool_call":
		return false
	var meta: Variant = update.get("_meta")
	var claude: Variant = meta.get("claudeCode") if meta is Dictionary else null
	return is_compaction_call(str(update.get("title", "")), str(claude.get("toolName", "")) if claude is Dictionary else "")


## Lo mismo con un tool call del modelo (título y nombre de la tool).
static func is_compaction_call(title: String, tool_name: String) -> bool:
	return title in COMPACTION_TITLES or tool_name.to_lower() == "compact"
