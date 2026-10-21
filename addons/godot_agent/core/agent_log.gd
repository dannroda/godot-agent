@tool
extends RefCounted
## Registro del harness: entradas con hora, canal y mensaje, más el JSON crudo opcional.
## Acotado (ring buffer) para que una sesión larga no crezca sin límite.

signal entry_added(entry: Dictionary)
signal cleared

const CH_ACP := &"acp"
const CH_MCP := &"mcp"
const CH_FS := &"fs"
const CH_PERM := &"perm"
const CH_PROC := &"proc"
const CH_CMP := &"cmp"
const CHANNELS: Array[StringName] = [CH_ACP, CH_MCP, CH_FS, CH_PERM, CH_PROC, CH_CMP]

const DEFAULT_CAPACITY := 2000
## Tope de caracteres del JSON crudo guardado por entrada.
const RAW_LIMIT := 20000

var capacity: int = DEFAULT_CAPACITY
var _entries: Array[Dictionary] = []
var _next_seq: int = 1


## Agrega una entrada. `raw` es el mensaje JSON-RPC completo (se muestra en modo raw).
func add(channel: StringName, message: String, raw: String = "") -> Dictionary:
	var entry := {
		"seq": _next_seq,
		"time": Time.get_time_string_from_system(),
		"channel": channel,
		"message": message,
		"raw": raw.left(RAW_LIMIT),
	}
	_next_seq += 1
	_entries.append(entry)
	if _entries.size() > capacity:
		_entries = _entries.slice(_entries.size() - capacity)
	entry_added.emit(entry)
	return entry


func entries() -> Array[Dictionary]:
	return _entries


func clear() -> void:
	_entries.clear()
	cleared.emit()


## Texto plano para copiar: hora · canal · mensaje (y el raw si se pide).
static func format_entry(entry: Dictionary, include_raw: bool = false) -> String:
	var line := "%s  %-4s  %s" % [entry.time, entry.channel, entry.message]
	if include_raw and not str(entry.raw).is_empty():
		line += "\n" + str(entry.raw)
	return line
