@tool
extends RefCounted
## Perfil de agente (spec §4.4): cómo lanzar un agente ACP. Se guarda como Dictionary en
## EditorSettings. `env` guarda valores literales: para secretos, el perfil referencia una
## variable del entorno del editor con `$NOMBRE` y se resuelve al lanzar (no se guarda la clave).

## Claude Code por ACP, para las pruebas contra el agente real: al usuario no se le presetea ninguno.
const CLAUDE_CODE := {"id": "claude-code", "display_name": "Claude Code", "command": "npx", "args": ["-y", "@agentclientprotocol/claude-agent-acp"]}

var id: String = ""
var display_name: String = ""
var command: String = ""
var args: PackedStringArray = []
var env: Dictionary = {}
var is_default: bool = false


static func from_dict(data: Dictionary) -> RefCounted:
	var profile := new()
	profile.id = str(data.get("id", ""))
	profile.display_name = str(data.get("display_name", profile.id))
	profile.command = str(data.get("command", ""))
	var raw_args: Variant = data.get("args", [])
	if raw_args is Array or raw_args is PackedStringArray:
		for arg: Variant in raw_args:
			profile.args.append(str(arg))
	var raw_env: Variant = data.get("env", {})
	if raw_env is Dictionary:
		for key: Variant in raw_env:
			profile.env[str(key)] = str(raw_env[key])
	profile.is_default = bool(data.get("default", false))
	return profile


func to_dict() -> Dictionary:
	return {
		"id": id,
		"display_name": display_name,
		"command": command,
		"args": Array(args),
		"env": env.duplicate(),
		"default": is_default,
	}


## Entorno para el proceso: `$VAR` se reemplaza por el valor de VAR en el entorno del editor.
func resolved_env() -> Dictionary:
	var result: Dictionary = {}
	for key: String in env:
		var value: String = env[key]
		if value.begins_with("$") and value.length() > 1:
			value = OS.get_environment(value.substr(1))
		result[key] = value
	return result


## Línea de comando legible para la UI.
func command_line() -> String:
	var parts: PackedStringArray = [command]
	parts.append_array(args)
	return " ".join(parts)

