@tool
extends RefCounted
## Un tool call del agente, indexado por `toolCallId` (ACP tool_call / tool_call_update).

const STATUS_PENDING := "pending"
const STATUS_IN_PROGRESS := "in_progress"
const STATUS_COMPLETED := "completed"
const STATUS_FAILED := "failed"
## Local: el turno se canceló con el tool call sin terminar.
const STATUS_CANCELLED := "cancelled"
## Tools de Claude Code que lanzan un subagente.
const SUBAGENT_TOOLS: PackedStringArray = ["Agent", "Task"]
## Texto del subagente que se conserva (el final).
const SUBAGENT_TEXT_MAX := 2000

var id: String = ""
var title: String = ""
## read, edit, delete, move, search, execute, think, fetch, switch_mode u other.
var kind: String = "other"
var status: String = STATUS_PENDING
## Bloques `content`, `diff` y `terminal` tal como llegan (Dictionary).
var content: Array = []
## `{path, line?}`
var locations: Array = []
var raw_input: Variant = null
var raw_output: Variant = null
var started_msec: int = 0
var finished_msec: int = 0
## Paso de undo de una tool godot.* de edición (EditorUndo.record), o {}.
var undo_info: Dictionary = {}
var undo_done: bool = false
## Nombre de la tool del lado del agente (`_meta.claudeCode.toolName`: Agent, Bash…), si lo manda.
var tool_name: String = ""
## Tool call del subagente que hizo este (`_meta.claudeCode.parentToolUseId`), o "".
var parent_id: String = ""
## Tool calls que hizo el subagente de este tool call, en orden.
var child_ids: PackedStringArray = []
## Lo que fue escribiendo el subagente (los últimos SUBAGENT_TEXT_MAX caracteres).
var subagent_text: String = ""


func is_finished() -> bool:
	return status in [STATUS_COMPLETED, STATUS_FAILED, STATUS_CANCELLED]


## Aplica los campos presentes de un ToolCall / ToolCallUpdate de ACP.
func apply(data: Dictionary) -> void:
	if data.get("title") is String:
		title = data.title
	if data.get("kind") is String:
		kind = data.kind
	if data.get("status") is String:
		set_status(data.status)
	if data.get("content") is Array:
		content = data.content
	if data.get("locations") is Array:
		locations = data.locations
	if data.has("rawInput"):
		raw_input = data.rawInput
	if data.has("rawOutput"):
		raw_output = data.rawOutput
	var meta: Variant = data.get("_meta")
	if meta is Dictionary and meta.get("claudeCode") is Dictionary and meta.claudeCode.get("toolName") is String:
		tool_name = meta.claudeCode.toolName


func is_subagent() -> bool:
	return tool_name in SUBAGENT_TOOLS or not child_ids.is_empty()


func append_subagent_text(text: String) -> void:
	subagent_text += text
	if subagent_text.length() > SUBAGENT_TEXT_MAX:
		subagent_text = "…" + subagent_text.right(SUBAGENT_TEXT_MAX - 1)


func set_status(value: String) -> void:
	status = value
	if is_finished() and finished_msec == 0:
		finished_msec = Time.get_ticks_msec()


func duration_msec() -> int:
	if started_msec == 0:
		return 0
	return (finished_msec if finished_msec > 0 else Time.get_ticks_msec()) - started_msec


## Bloques `diff` del content: `{path, oldText, newText}`.
func diffs() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for block: Variant in content:
		if block is Dictionary and block.get("type") == "diff":
			result.append(block)
	return result


## Nombre corto para la UI. Las tools MCP del addon llegan como `mcp__godot__<tool>`.
func display_name() -> String:
	if title.is_empty():
		return kind
	return title


## Nombre de la tool godot.* sin prefijo ("add_node"), o "" si no es del addon.
func godot_tool_name() -> String:
	for prefix: String in ["mcp__godot__", "godot."]:
		if title.begins_with(prefix):
			return title.trim_prefix(prefix)
	return ""


func can_undo() -> bool:
	return not undo_info.is_empty() and not undo_done and status == STATUS_COMPLETED


func is_godot_tool() -> bool:
	return title.begins_with("mcp__godot__") or title.begins_with("godot.") or (
		raw_input is Dictionary and str(raw_input.get("server", "")) == "godot"
	)
