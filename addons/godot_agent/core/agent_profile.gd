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
## Variable del entorno con la carpeta de configuración del agente, para elegir cuenta por pestaña.
## Vacía: la que conoce su adaptador (CLAUDE_CONFIG_DIR, GEMINI_HOME, CODEX_HOME).
var account_variable: String = ""
## Cuenta elegida en la pestaña: `account_dir` va en la variable `account_env`, por encima del entorno
## del perfil. No se guardan con el perfil: son de la pestaña y del historial de la sesión.
var account_dir: String = ""
var account_env: String = ""


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
	profile.account_variable = str(data.get("account_variable", ""))
	return profile


## Nombres de variables de entorno cuyo valor es un secreto (misma idea que ExternalMcpServers).
static var SECRET_ENV_NAME := RegEx.create_from_string("(?i)(key|token|secret|password|passwd|authorization|auth)")

func to_dict() -> Dictionary:
	return {
		"id": id,
		"display_name": display_name,
		"command": command,
		"args": Array(args),
		"env": env.duplicate(),
		"default": is_default,
	}.merged({"account_variable": account_variable} if not account_variable.is_empty() else {})


## Entorno para el proceso: `$VAR` se reemplaza por el valor de VAR en el entorno del editor y un
## `~/` al principio, por la carpeta del usuario (el proceso no pasa por un shell que lo expanda).
## Valores del entorno que parecen secretos por el nombre de su variable (API keys, tokens…), para
## registrarlos en el Agent Log (m13-25): el agente puede repetirlos en su stderr o en un error.
static func secret_env_values(resolved: Dictionary) -> PackedStringArray:
	var result: PackedStringArray = []
	for key: String in resolved:
		var value := str(resolved[key])
		if SECRET_ENV_NAME.search(key) and value.length() >= 8 and not value in result:
			result.append(value)
	return result


## Lo que el agente hereda del entorno del editor sin que el perfil lo nombre (m13-25): el proceso
## recibe el entorno entero, así que una key exportada en el shell (la API key del adapter) le llega
## igual. Devuelve los valores de `names` que existen y parecen secretos, con la misma regla que
## secret_env_values.
static func inherited_secret_values(names: PackedStringArray) -> PackedStringArray:
	var found: Dictionary = {}
	for name: String in names:
		if not name.is_empty() and OS.has_environment(name):
			found[name] = OS.get_environment(name)
	return secret_env_values(found)


func resolved_env() -> Dictionary:
	var result: Dictionary = {}
	for key: String in env:
		var value: String = env[key]
		if value.begins_with("$") and value.length() > 1:
			value = OS.get_environment(value.substr(1))
		elif value == "~" or value.begins_with("~/"):
			value = home_dir() + value.substr(1)
		result[key] = value
	if not account_dir.is_empty() and not account_env.is_empty():
		result[account_env] = account_dir
	return result


## Copia de este perfil que lanza el agente con otra cuenta: `dir` en la variable `variable` (dir
## vacío: la del perfil).
func with_account(dir: String, variable: String) -> RefCounted:
	var copy: RefCounted = from_dict(to_dict())
	copy.account_dir = dir
	copy.account_env = variable if not dir.is_empty() else ""
	return copy


## Nombre para el chip y el historial: con una cuenta elegida, «Claude Code · trabajo».
func label() -> String:
	return display_name if account_dir.is_empty() else "%s · %s" % [display_name, account_dir.trim_suffix("/").get_file()]


static func home_dir() -> String:
	var home := OS.get_environment("HOME")
	return home if not home.is_empty() else OS.get_environment("USERPROFILE")


## Línea de comando legible para la UI.
func command_line() -> String:
	var parts: PackedStringArray = [command]
	parts.append_array(args)
	return " ".join(parts)

