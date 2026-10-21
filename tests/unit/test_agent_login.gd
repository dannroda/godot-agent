extends "test_case.gd"
## Login del agente (ACP auth): qué métodos se ofrecen, qué comando corre cada uno y cómo se
## reconoce el error authRequired.

const AgentLogin := preload("res://addons/godot_agent/session/agent_login.gd")
const AgentProfile := preload("res://addons/godot_agent/core/agent_profile.gd")
const SessionController := preload("res://addons/godot_agent/session/session_controller.gd")


func _profile() -> AgentProfile:
	return AgentProfile.from_dict({"id": "claude", "display_name": "Claude Code", "command": "npx",
		"args": ["-y", "@agentclientprotocol/claude-agent-acp"], "env": {"DEBUG": "1"}})


func test_usable_methods() -> void:
	var methods := AgentLogin.usable_methods([
		{"id": "claude-ai-login", "name": "Claude Subscription", "type": "terminal", "args": ["--cli", "auth", "login", "--claudeai"]},
		{"id": "agent-side", "name": "Google"},
		{"id": "key", "name": "API key", "type": "env_var", "varName": "X"},
		{"name": "sin id"},
		"basura",
	])
	assert_eq(methods.map(func(method: Dictionary) -> String: return method.id), ["claude-ai-login", "agent-side"], "terminal y del agente; env_var no")
	assert_true(AgentLogin.is_terminal(methods[0]), "terminal")
	assert_false(AgentLogin.is_terminal(methods[1]), "sin type es del agente")
	assert_eq(AgentLogin.label_of(methods[0]), "Claude Subscription", "nombre")


func test_command_for() -> void:
	var method := {"id": "claude-ai-login", "type": "terminal", "args": ["--cli", "auth", "login", "--claudeai"], "env": {"NO_COLOR": "1"}}
	var command := AgentLogin.command_for(method, _profile())
	assert_eq(command.command, "npx", "el comando del perfil")
	assert_eq(command.args, PackedStringArray(["-y", "@agentclientprotocol/claude-agent-acp", "--cli", "auth", "login", "--claudeai"]), "args del perfil + del método")
	assert_eq(command.env, {"DEBUG": "1", "NO_COLOR": "1"}, "env del perfil + del método")
	method["_meta"] = {"terminal-auth": {"command": "/usr/bin/node", "args": ["/x/index.js", "--cli", "auth", "login"], "label": "Claude Login"}}
	command = AgentLogin.command_for(method, _profile())
	assert_eq(command.command, "/usr/bin/node", "_meta.terminal-auth manda")
	assert_eq(command.args, PackedStringArray(["/x/index.js", "--cli", "auth", "login"]), "args del _meta")
	assert_true(AgentLogin.is_terminal({"id": "x", "_meta": {"terminal-auth": {"command": "a"}}}), "terminal por _meta")


func test_auth_required_error() -> void:
	assert_true(SessionController.is_auth_required({"code": -32000, "message": "Authentication required"}), "el de ACP")
	assert_true(SessionController.is_auth_required({"code": -32000, "message": "Authentication required: Sign in with an API key"}), "con detalle")
	assert_false(SessionController.is_auth_required({"code": -32000, "message": "No se pudo enviar 'session/new' al agente."}), "el de transporte tiene el mismo código")
	assert_false(SessionController.is_auth_required({"code": -32603, "message": "Authentication required"}), "otro código")
