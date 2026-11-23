@tool
extends "agent_adapter.gd"
## Claude Code (claude-agent-acp): la cuota llega sola en `usage_update._meta["_claude/rateLimit"]`,
## la cuenta se pregunta al CLI `claude` y la sesión lleva las skills apagadas y el pedido de permiso
## para cada subagente.

const SkillCatalog := preload("../../extensions/skill_catalog.gd")
const PermissionPolicy := preload("../permission_policy.gd")
const AgentProfile := preload("../../core/agent_profile.gd")
const ProjectMemory := preload("../../core/project_memory.gd")
const OutsideInput := preload("../outside_input.gd")


func _init() -> void:
	kind = ClaudeExtensions.AGENT_CLAUDE


## La semana de Fable (y las de Opus y Sonnet) limita solo a su modelo (m12-55): el selector dice cuál
## cuenta hasta que el próximo usage_update lo confirme.
func model_changed(quota: RefCounted, model_name: String) -> void:
	quota.call(&"select_model", model_name)


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
	# HOME o, en Windows, USERPROFILE; con las barras normalizadas para comparar.
	var home := AgentProfile.home_dir().replace("\\", "/").simplify_path()
	var plain := dir.replace("\\", "/").simplify_path().trim_suffix("/") == home.path_join(".claude")
	var path := home.path_join(".claude.json") if plain else dir.path_join(".claude.json")
	if not FileAccess.file_exists(path):
		return ""
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	var account: Variant = (data as Dictionary).get("oauthAccount") if data is Dictionary else null
	return str((account as Dictionary).get("emailAddress", "")) if account is Dictionary else ""


## La carpeta de la cuenta: la del perfil (CLAUDE_CONFIG_DIR), la del entorno del editor o ~/.claude.
func transcript_path(session_id: String, cwd: String, env: Dictionary) -> String:
	return OutsideInput.transcript_path(ProjectMemory.claude_config_dir(env, AgentProfile.home_dir()), cwd, session_id)


## Claude Code guarda cada sesión en `<carpeta>/projects/<proyecto>/<id>.jsonl` (y lo de sus
## subagentes en `<id>/`). Se copia a la misma subcarpeta de la otra cuenta, pisando una copia vieja:
## la de la cuenta con la que corría es la que está al día.
func carry_session(session_id: String, from_dir: String, to_dir: String) -> bool:
	if session_id.is_empty() or not session_id.is_valid_filename():
		return false
	var projects := from_dir.path_join("projects")
	var access := DirAccess.open(projects)
	if access == null:
		return false
	for project: String in access.get_directories():
		var source := projects.path_join(project).path_join(session_id + ".jsonl")
		if not FileAccess.file_exists(source):
			continue
		var target_dir := to_dir.path_join("projects").path_join(project)
		if DirAccess.make_dir_recursive_absolute(target_dir) != OK:
			return false
		if DirAccess.copy_absolute(source, target_dir.path_join(session_id + ".jsonl")) != OK:
			return false
		_copy_tree(projects.path_join(project).path_join(session_id), target_dir.path_join(session_id))
		return true
	return false


static func _copy_tree(from: String, to: String) -> void:
	var access := DirAccess.open(from)
	if access == null:
		return
	DirAccess.make_dir_recursive_absolute(to)
	for file: String in access.get_files():
		DirAccess.copy_absolute(from.path_join(file), to.path_join(file))
	for dir: String in access.get_directories():
		_copy_tree(from.path_join(dir), to.path_join(dir))
