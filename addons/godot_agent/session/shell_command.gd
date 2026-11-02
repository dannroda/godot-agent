@tool
extends RefCounted
## El comando de shell de una tool call `execute`. Cada agente lo manda con otro nombre en rawInput:
## Claude Code `command`, Antigravity `CommandLine` (y `command_line` en el update), otros `cmd` o
## una lista de argumentos (m17-24). Sin esto, la allowlist del modo Auto y el bloqueo de escrituras
## al proyecto no veían el comando.

const KEYS: PackedStringArray = ["command", "CommandLine", "command_line", "commandLine", "cmd"]


static func of(raw_input: Variant) -> String:
	if not raw_input is Dictionary:
		return ""
	for key: String in KEYS:
		var value: Variant = (raw_input as Dictionary).get(key)
		if value is String and not (value as String).strip_edges().is_empty():
			return value
		if value is Array and not (value as Array).is_empty():
			return " ".join((value as Array).map(func(part: Variant) -> String: return str(part)))
	return ""
