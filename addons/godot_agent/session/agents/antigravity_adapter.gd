@tool
extends "agent_adapter.gd"
## Google Antigravity (antigravity-acp): no manda la cuota en usage_update; su `/usage` la dice por
## grupo de modelos, sin gastar tokens (m11-13).

const QuotaMonitor := preload("../../core/quota_monitor.gd")
const I18n := preload("../../core/i18n.gd")
## Su skill de run_workflow: el harness de antigravity-acp (1.4.3) la escribe en <cwd>/skills/ en cada
## session/new. No se puede evitar desde afuera: el adapter no pasa materialized_skills_dir y no hay
## opción ni variable para eso, y el cwd de la sesión tiene que ser el proyecto (m18-03).
const SYSTEM_SKILL := "skills/system/run-workflow/SKILL.md"


func _init() -> void:
	kind = ClaudeExtensions.AGENT_ANTIGRAVITY


func quota_command(_model: RefCounted) -> String:
	return "/usage"


func read_quota(text: String, quota: RefCounted, _model: RefCounted, model_name: String) -> void:
	var groups := QuotaMonitor.parse_antigravity_usage(text)
	quota.call(&"observe_windows", QuotaMonitor.antigravity_windows(groups, model_name), text, groups)


func model_changed(quota: RefCounted, model_name: String) -> void:
	quota.call(&"select_antigravity_model", model_name)


## antigravity-acp guarda su login (antigravity-acp/acp_token.json) bajo GEMINI_HOME, o ~/.gemini.
## El token no trae el email.
func account_variable() -> String:
	return "GEMINI_HOME"


func default_account_dir() -> String:
	return "~/.gemini"


func notice_after_session(cwd: String) -> String:
	if not FileAccess.file_exists(cwd.path_join(SYSTEM_SKILL)):
		return ""
	return I18n.t("Antigravity wrote %s in the project when the session opened: it is its own run_workflow skill, and it writes it again in every session. You can delete it, but it comes back. Add skills/system/ to .gitignore so it is not committed. See Troubleshooting in the wiki.") % SYSTEM_SKILL
