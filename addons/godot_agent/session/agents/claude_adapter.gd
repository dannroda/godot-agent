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
