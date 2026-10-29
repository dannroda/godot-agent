@tool
extends "agent_adapter.gd"
## Codex (codex-acp): `/status` dice la cuota y la cuenta. Solo si el agente lo anuncia: el adaptador
## del registro (@agentclientprotocol/codex-acp) lo corre local; el viejo de Zed no lo tiene y se lo
## pasaría al modelo como un prompt.

const QuotaMonitor := preload("../../core/quota_monitor.gd")


func _init() -> void:
	kind = ClaudeExtensions.AGENT_CODEX


func quota_command(model: RefCounted) -> String:
	var commands: Array = model.get(&"commands")
	var has_status := commands.any(func(command: Variant) -> bool: return command is Dictionary and command.get("name") == "status")
	return "/status" if has_status else ""


func read_quota(text: String, quota: RefCounted, model: RefCounted, model_name: String) -> void:
	var groups := QuotaMonitor.parse_codex_status(text, int((quota.get(&"now_provider") as Callable).call()))
	quota.call(&"observe_windows", QuotaMonitor.codex_windows(groups, model_name), text, groups if groups.size() > 1 else {})
	if (model.get(&"account") as Dictionary).is_empty():
		var account := QuotaMonitor.parse_codex_account(text)
		if not account.is_empty():
			model.call(&"set_account", account)
