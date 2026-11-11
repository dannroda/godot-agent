@tool
extends RefCounted
## Hooks del proyecto en eventos del editor (m11-24): lo que ningún agente ve (una escena o un script
## guardados, un juego que termina) dispara un comando, una tool o un prompt. Viven en
## project_config.tres (`hooks`), bajo addons/godot_agent, que las file tools del agente no escriben
## (ProtectedPaths). Igual viajan con el proyecto: un hook corre solo si se aprobó su definición entera
## en esta máquina (MachineApproval.KIND_HOOK). Son avisos después del hecho: nunca frenan ni cambian
## el evento. El fin de turno no es un evento de hooks: eso son los turn_checks (m11-31).
##
## Un hook es `{name, event, paths, by, only_errors, action, command, tool, args, prompt, auto_send,
## timeout_s, enabled}`:
## - event "saved": una escena o un script guardados. `paths` (globs res://) filtra; `by` dice quién
##   guardó: "user" (por defecto), "agent" (durante una tool del agente o escrito por sus file tools) o
##   "any".
## - event "game_stopped": terminó un juego. `by`: "user" (F5/F6) o "agent" (run_scene). `only_errors`
##   (por defecto true): solo si dejó errores.
## - event "regressions_finished": terminó una tanda de regresiones de playtest (del panel, by "user", o
##   de godot.run_regressions, by "agent"); `errors` son las que fallaron y `only_errors` vale igual.
## - event "export_started": empieza un export; `path` es el archivo de salida. Solo avisa: no lo frena.
## - action "command": un programa con argumentos, sin shell (TurnChecks.parse_command). Además de
##   {godot} y {project}, {path} y {event} se reemplazan dentro de cada argumento ya separado, y el
##   evento llega en variables de entorno GODOT_AGENT_*.
## - action "tool" / "prompt": ver HookRunner.

const MachineApproval := preload("machine_approval.gd")
const TurnChecks := preload("turn_checks.gd")
const UntrustedText := preload("../mcp/untrusted_text.gd")

const EVENT_SAVED := "saved"
const EVENT_GAME_STOPPED := "game_stopped"
const EVENT_REGRESSIONS := "regressions_finished"
const EVENT_EXPORT := "export_started"
const EVENTS: PackedStringArray = [EVENT_SAVED, EVENT_GAME_STOPPED, EVENT_REGRESSIONS, EVENT_EXPORT]
const ACTION_COMMAND := "command"
const ACTION_TOOL := "tool"
const ACTION_PROMPT := "prompt"
const ACTIONS: PackedStringArray = [ACTION_COMMAND, ACTION_TOOL, ACTION_PROMPT]
const BY_USER := "user"
const BY_AGENT := "agent"
const BY_ANY := "any"
const BYS: PackedStringArray = [BY_USER, BY_AGENT, BY_ANY]
const DEFAULT_TIMEOUT_S := 60
const MAX_TIMEOUT_S := 600
## Los grupos de permisos de las tools que puede correr un hook: leer, diagnosticar y correr el juego o
## las regresiones. Un hook corre sin pasar por el modo, así que nada que edite ni la shell.
const TOOL_GROUPS: PackedStringArray = ["read", "diagnostics", "run"]
## Prompts de hooks seguidos sin un mensaje del usuario, con auto_send (como los turnos de m11-04).
const MAX_AUTO_PROMPTS := 2
const PATH_PLACEHOLDER := "{path}"
const EVENT_PLACEHOLDER := "{event}"


static func make(event: String = EVENT_SAVED, action: String = ACTION_COMMAND, name: String = "") -> Dictionary:
	return {"name": name, "event": event if event in EVENTS else EVENT_SAVED, "paths": PackedStringArray(), "by": BY_USER,
		"only_errors": true, "action": action if action in ACTIONS else ACTION_COMMAND, "command": "", "tool": "", "args": {},
		"prompt": "", "auto_send": false, "timeout_s": DEFAULT_TIMEOUT_S, "enabled": true}


## Un hook guardado, con todos los campos y del tipo esperado ({} si no es un Dictionary o el evento o la
## acción no existen: un hook de una versión más nueva no corre a medias).
static func normalize(data: Variant) -> Dictionary:
	if not data is Dictionary:
		return {}
	var source: Dictionary = data
	var event := str(source.get("event", EVENT_SAVED))
	var action := str(source.get("action", ACTION_COMMAND))
	if not event in EVENTS or not action in ACTIONS:
		return {}
	var hook := make(event, action, str(source.get("name", "")).strip_edges())
	if source.get("paths") is Array or source.get("paths") is PackedStringArray:
		for path: Variant in source.paths:
			if not str(path).strip_edges().is_empty():
				hook.paths.append(str(path).strip_edges())
	var by := str(source.get("by", BY_USER))
	hook.by = by if by in BYS else BY_USER
	hook.only_errors = bool(source.get("only_errors", true))
	hook.command = str(source.get("command", "")).strip_edges()
	hook.tool = str(source.get("tool", "")).strip_edges().trim_prefix("godot.")
	hook.args = source.get("args") if source.get("args") is Dictionary else {}
	hook.prompt = str(source.get("prompt", "")).strip_edges()
	hook.auto_send = bool(source.get("auto_send", false))
	hook.timeout_s = clampi(int(source.get("timeout_s", DEFAULT_TIMEOUT_S)), 1, MAX_TIMEOUT_S)
	hook.enabled = bool(source.get("enabled", true))
	if hook.name.is_empty():
		hook.name = describe_action(hook).get_slice(" ", 0).get_file().left(40)
	return hook


static func normalize_list(data: Variant) -> Array:
	var result: Array = []
	if data is Array:
		for item: Variant in data:
			var hook := normalize(item)
			if not hook.is_empty():
				result.append(hook)
	return result


## Lo que corre, en una línea: el comando, «godot.tool {args}» o el prompt.
static func describe_action(hook: Dictionary) -> String:
	match str(hook.action):
		ACTION_TOOL:
			return "godot.%s %s" % [hook.tool, JSON.stringify(hook.args)]
		ACTION_PROMPT:
			return str(hook.prompt)
	return str(hook.command)


## Si `hook` corre con `event` (`{event, path, by, errors}`).
static func matches(hook: Dictionary, event: Dictionary) -> bool:
	if not bool(hook.enabled) or str(hook.event) != str(event.get("event", "")):
		return false
	if str(hook.by) != BY_ANY and str(hook.by) != str(event.get("by", BY_USER)):
		return false
	if str(hook.event) in [EVENT_GAME_STOPPED, EVENT_REGRESSIONS] and bool(hook.only_errors) and int(event.get("errors", 0)) <= 0:
		return false
	var globs: PackedStringArray = hook.paths
	if globs.is_empty():
		return true
	var path := str(event.get("path", ""))
	for glob: String in globs:
		if path.match(glob) or path.match(glob.trim_suffix("/**") + "/*"):
			return true
	return false


## La clave con que se aprueba en esta máquina: el proyecto y la definición entera menos `enabled`
## (prender o apagar no cambia lo que corre). Cualquier otro cambio pide aprobar de nuevo.
static func approval_key(project_dir: String, hook: Dictionary) -> String:
	var definition := hook.duplicate(true)
	definition.erase("enabled")
	return MachineApproval.key(project_dir, "hook\n" + JSON.stringify(definition, "", true))


## El programa y los argumentos de un hook de comando para `event`.
static func invocation(hook: Dictionary, event: Dictionary, godot_path: String, project_dir: String) -> Dictionary:
	var parsed := TurnChecks.parse_command(str(hook.command))
	if not str(parsed.error).is_empty():
		return {"program": "", "args": PackedStringArray(), "error": parsed.error}
	var args := PackedStringArray()
	for arg: String in TurnChecks.expand(parsed.args, godot_path, project_dir):
		args.append(arg.replace(PATH_PLACEHOLDER, str(event.get("path", ""))).replace(EVENT_PLACEHOLDER, str(event.get("event", ""))))
	return {"program": args[0], "args": args.slice(1), "error": ""}


## Las variables de entorno con el evento para un comando.
static func environment(hook: Dictionary, event: Dictionary) -> Dictionary:
	return {"GODOT_AGENT_HOOK": str(hook.name), "GODOT_AGENT_EVENT": str(event.get("event", "")),
		"GODOT_AGENT_PATH": str(event.get("path", "")), "GODOT_AGENT_BY": str(event.get("by", "")),
		"GODOT_AGENT_ERRORS": str(int(event.get("errors", 0)))}


## El prompt de un hook para el agente: la instrucción del hook (la aprobó el usuario en esta máquina) y
## el evento, que trae texto de afuera (rutas, errores del juego), en sobre.
static func prompt_text(hook: Dictionary, event: Dictionary) -> String:
	var parts: PackedStringArray = ["A project hook («%s») fired on the editor event «%s». Its instruction, from the project's settings and approved by the user on this machine:" % [hook.name, event.get("event", "")], str(hook.prompt)]
	var facts: PackedStringArray = []
	if not str(event.get("path", "")).is_empty():
		facts.append("path: " + str(event.path))
	if event.has("by"):
		facts.append("by: " + str(event.by))
	if event.has("errors"):
		facts.append("game errors: %d" % int(event.errors))
	var lines: PackedStringArray = event.get("lines", PackedStringArray())
	if not lines.is_empty():
		facts.append("\n".join(lines))
	if not facts.is_empty():
		parts.append("Event details:")
		parts.append(UntrustedText.wrap("\n".join(facts)))
	return UntrustedText.seal("\n".join(parts), UntrustedText.new_nonce())
