@tool
extends RefCounted
## Elige el adaptador de un agente (m13-04, A1). Antes de conectar sale del perfil; después de
## `initialize`, el nombre que manda el agente (`agentInfo.name`) manda.

const AgentAdapter := preload("agent_adapter.gd")
const ClaudeAdapter := preload("claude_adapter.gd")
const AntigravityAdapter := preload("antigravity_adapter.gd")
const CodexAdapter := preload("codex_adapter.gd")
const ClaudeExtensions := preload("../../extensions/claude_extensions.gd")

## `agentInfo.name` de los adaptadores ACP oficiales.
const ANTIGRAVITY_AGENT := "antigravity-acp"
const CODEX_AGENT := "codex-acp"


## Por el comando del perfil. Sin perfil, el genérico.
static func for_profile(command: String, args: PackedStringArray, profile_id: String = "") -> AgentAdapter:
	var kind := ClaudeExtensions.agent_kind(command, args, profile_id) if not command.is_empty() else ClaudeExtensions.AGENT_OTHER
	return _for_kind(kind)


## Después de `initialize`: el nombre que dice el agente gana sobre el comando del perfil.
static func for_session(command: String, args: PackedStringArray, profile_id: String, agent_info: Dictionary) -> AgentAdapter:
	var agent_name := str(agent_info.get("name", ""))
	if agent_name == ANTIGRAVITY_AGENT:
		return AntigravityAdapter.new()
	if agent_name.get_file() == CODEX_AGENT:
		return CodexAdapter.new()
	return for_profile(command, args, profile_id)


static func _for_kind(kind: String) -> AgentAdapter:
	match kind:
		ClaudeExtensions.AGENT_CLAUDE:
			return ClaudeAdapter.new()
		ClaudeExtensions.AGENT_ANTIGRAVITY:
			return AntigravityAdapter.new()
		ClaudeExtensions.AGENT_CODEX:
			return CodexAdapter.new()
	var generic := AgentAdapter.new()
	generic.kind = kind
	return generic
