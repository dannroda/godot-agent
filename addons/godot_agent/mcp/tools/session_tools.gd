@tool
extends RefCounted
## Canal entre las sesiones del agente abiertas a la vez en el editor (m7-44): `sessions` muestra
## las demás (qué hacen, qué archivos están editando, quién tiene el juego) y `session_send` le deja
## un mensaje a otra, que le llega como prompt cuando queda libre.

const McpTool := preload("../mcp_tool.gd")
const PermissionPolicy := preload("../../session/permission_policy.gd")

const MESSAGE_MAX := 4000

## La sesión que llama (ToolRegistry.current_caller).
var caller: Callable
## `(caller) -> String`: el estado de las sesiones, visto desde `caller`.
var describe: Callable
## `(caller, to, message) -> String`: "" si se entregó; si no, el motivo.
var send: Callable


func tools() -> Array:
	return [
		McpTool.create("sessions", PermissionPolicy.GROUP_READ,
			"Lists the agent sessions open in this editor besides yours: their name, mode and state, what they're working on, the files each one is editing in its current turn (off limits to you until that turn ends) and which one has the game running.",
			{}, [], _sessions),
		McpTool.create("session_send", PermissionPolicy.GROUP_READ,
			"Sends a short message to another agent session open in this editor (`to`: its name from godot.sessions, e.g. \"Session 2\"). It reaches that agent as a prompt when its turn ends, marked as coming from you. Use it to hand off work or agree on who edits what; don't use it for chit-chat.",
			{"to": {"type": "string"}, "message": {"type": "string"}}, ["to", "message"], _session_send),
	]


func _sessions(_args: Dictionary) -> Dictionary:
	var from := str(caller.call()) if caller.is_valid() else ""
	return McpTool.text(str(describe.call(from)) if describe.is_valid() else "There is only one agent session open.")


func _session_send(args: Dictionary) -> Dictionary:
	var from := str(caller.call()) if caller.is_valid() else ""
	var message := McpTool.str_arg(args, "message").strip_edges()
	if message.is_empty():
		return McpTool.error("`message` is empty.")
	if message.length() > MESSAGE_MAX:
		return McpTool.error("The message is too long (%d characters; the limit is %d): say it shorter." % [message.length(), MESSAGE_MAX])
	if not send.is_valid():
		return McpTool.error("There is only one agent session open.")
	var failure: String = send.call(from, McpTool.str_arg(args, "to").strip_edges(), message)
	return McpTool.error(failure) if not failure.is_empty() else McpTool.text("Delivered: it reaches that session when its current turn ends.")
