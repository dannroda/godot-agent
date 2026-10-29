@tool
extends "agent_adapter.gd"
## Google Antigravity (antigravity-acp): no manda la cuota en usage_update; su `/usage` la dice por
## grupo de modelos, sin gastar tokens (m11-13).

const QuotaMonitor := preload("../../core/quota_monitor.gd")


func _init() -> void:
	kind = ClaudeExtensions.AGENT_ANTIGRAVITY


func quota_command(_model: RefCounted) -> String:
	return "/usage"


func read_quota(text: String, quota: RefCounted, _model: RefCounted, model_name: String) -> void:
	var groups := QuotaMonitor.parse_antigravity_usage(text)
	quota.call(&"observe_windows", QuotaMonitor.antigravity_windows(groups, model_name), text, groups)


func model_changed(quota: RefCounted, model_name: String) -> void:
	quota.call(&"select_antigravity_model", model_name)
