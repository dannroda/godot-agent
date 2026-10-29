@tool
extends RefCounted
## Los agentes que se ofrecen cuando no hay ninguno configurado (m12-15, m12-21): los más usados,
## con lo que piden. Claude Code se arma acá mismo (npx); los demás se agregan desde el registro de
## ACP, que da el comando de cada plataforma (y baja el programa si hace falta).

const AgentProfile := preload("agent_profile.gd")

## `{key, name, needs, description, profile?, registry_query?}`. `needs` y `description` son textos
## para la UI (se traducen; el registro de ACP solo trae descripciones en inglés, m12-28).
const AGENTS: Array[Dictionary] = [
	{
		"key": "claude", "name": "Claude Code", "profile": AgentProfile.CLAUDE_CODE,
		"needs": "Node.js (npx) and a Claude account or an Anthropic API key",  # i18n
		"description": "Anthropic's coding agent: reads and edits the project, runs commands and uses the editor tools.",  # i18n
	},
	{
		"key": "codex", "name": "Codex", "registry_query": "codex",
		"needs": "Node.js (npx) and a ChatGPT account or an OpenAI API key",  # i18n
		"description": "OpenAI's coding agent, through its ACP adapter.",  # i18n
	},
	{
		"key": "antigravity", "name": "Google Antigravity", "registry_query": "antigravity",
		"needs": "A Google account; its program is downloaded from the ACP registry",  # i18n
		"description": "Google's coding agent, with Gemini, Claude and GPT models in its plan.",  # i18n
	},
]


## El sugerido que corresponde a un agente del registro (por id o nombre), o {}.
static func matching(agent_id: String, agent_name: String) -> Dictionary:
	var text := ("%s %s" % [agent_id, agent_name]).to_lower()
	for suggested: Dictionary in AGENTS:
		if text.contains(str(suggested.key)):
			return suggested
	return {}


## El perfil listo para guardar, o {} si este agente se agrega desde el registro.
static func profile_of(agent: Dictionary) -> Dictionary:
	if not agent.has("profile"):
		return {}
	var data: Dictionary = (agent.profile as Dictionary).duplicate(true)
	data.merge({"env": {}, "default": false})
	return data
