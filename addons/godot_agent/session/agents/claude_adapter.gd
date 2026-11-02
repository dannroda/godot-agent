@tool
extends "agent_adapter.gd"
## Claude Code (claude-agent-acp): la cuota llega sola en `usage_update._meta["_claude/rateLimit"]`,
## la cuenta se pregunta al CLI `claude` y la sesión lleva las skills apagadas y el pedido de permiso
## para cada subagente.

const SkillCatalog := preload("../../extensions/skill_catalog.gd")
const PermissionPolicy := preload("../permission_policy.gd")


func _init() -> void:
	kind = ClaudeExtensions.AGENT_CLAUDE


func reads_account_from_cli() -> bool:
	return true


## Las skills apagadas en el proyecto (m7-36) y que pida permiso para cada subagente, así el modo
## decide y se cuentan (m7-43).
func session_meta(disabled_skills: PackedStringArray) -> Dictionary:
	var settings := SkillCatalog.session_settings(disabled_skills)
	settings["permissions"] = {"ask": Array(PermissionPolicy.SUBAGENT_ASK_RULES)}
	return {"claudeCode": {"options": {"settings": settings}}}


func api_key_variable() -> String:
	return "ANTHROPIC_API_KEY"


func account_variable() -> String:
	return "CLAUDE_CONFIG_DIR"


func default_account_dir() -> String:
	return "~/.claude"


## El `oauthAccount` de `.claude.json`; para ~/.claude, Claude Code guarda ese archivo en la carpeta
## del usuario.
func account_email(dir: String) -> String:
	var home := OS.get_environment("HOME")
	var plain := dir.trim_suffix("/") == home.path_join(".claude")
	var path := home.path_join(".claude.json") if plain else dir.path_join(".claude.json")
	if not FileAccess.file_exists(path):
		return ""
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	var account: Variant = (data as Dictionary).get("oauthAccount") if data is Dictionary else null
	return str((account as Dictionary).get("emailAddress", "")) if account is Dictionary else ""
