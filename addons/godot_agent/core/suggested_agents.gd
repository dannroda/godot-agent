@tool
extends RefCounted
## Los agentes que se ofrecen cuando no hay ninguno configurado (m12-15, m12-21): los más usados,
## con lo que piden. Claude Code se arma acá mismo (npx); los demás se agregan desde el registro de
## ACP, que da el comando de cada plataforma (y baja el programa si hace falta).

const AgentProfile := preload("agent_profile.gd")

## `{key, name, needs, profile?, registry_query?}`. `needs` es un texto para la UI (se traduce).
const AGENTS: Array[Dictionary] = [
	{
		"key": "claude", "name": "Claude Code", "profile": AgentProfile.CLAUDE_CODE,
		"needs": "Node.js (npx) and a Claude account or an Anthropic API key",  # i18n
	},
	{
		"key": "codex", "name": "Codex", "registry_query": "codex",
		"needs": "Node.js (npx) and a ChatGPT account or an OpenAI API key",  # i18n
	},
	{
		"key": "antigravity", "name": "Google Antigravity", "registry_query": "antigravity",
		"needs": "A Google account; its program is downloaded from the ACP registry",  # i18n
	},
]


## El perfil listo para guardar, o {} si este agente se agrega desde el registro.
static func profile_of(agent: Dictionary) -> Dictionary:
	if not agent.has("profile"):
		return {}
	var data: Dictionary = (agent.profile as Dictionary).duplicate(true)
	data.merge({"env": {}, "default": false})
	return data
