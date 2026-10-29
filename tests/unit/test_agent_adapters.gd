extends "test_case.gd"
## Adaptadores por agente (m13-04): cuál sale de cada perfil y qué cambia en cada uno.

const AgentAdapters := preload("res://addons/godot_agent/session/agents/agent_adapters.gd")
const ClaudeExtensions := preload("res://addons/godot_agent/extensions/claude_extensions.gd")
const QuotaMonitor := preload("res://addons/godot_agent/core/quota_monitor.gd")
const SessionModel := preload("res://addons/godot_agent/session/session_model.gd")
const AgentLog := preload("res://addons/godot_agent/core/agent_log.gd")


func test_for_profile() -> void:
	assert_eq(AgentAdapters.for_profile("npx", PackedStringArray(["-y", "@agentclientprotocol/claude-agent-acp"])).kind, ClaudeExtensions.AGENT_CLAUDE, "Claude por el comando")
	assert_eq(AgentAdapters.for_profile("/agents/agy_acp_server.par", PackedStringArray(["--uid="]), "antigravity-acp").kind, ClaudeExtensions.AGENT_ANTIGRAVITY, "Antigravity")
	assert_eq(AgentAdapters.for_profile("opencode", PackedStringArray(["acp"])).kind, ClaudeExtensions.AGENT_OPENCODE, "OpenCode: genérico con su familia")
	assert_eq(AgentAdapters.for_profile("", PackedStringArray()).kind, ClaudeExtensions.AGENT_OTHER, "sin comando")


func test_for_session_trusts_agent_info() -> void:
	var adapter := AgentAdapters.for_session("/opt/agente", PackedStringArray(), "x", {"name": "antigravity-acp"})
	assert_eq(adapter.kind, ClaudeExtensions.AGENT_ANTIGRAVITY, "el nombre del agente gana sobre el comando")
	assert_eq(adapter.quota_command(SessionModel.new()), "/usage", "Antigravity pide /usage")
	var codex := AgentAdapters.for_session("npx", PackedStringArray(["codex"]), "", {"name": "@agentclientprotocol/codex-acp"})
	var model := SessionModel.new()
	assert_eq(codex.quota_command(model), "", "Codex sin /status anunciado: nada (se lo pasaría al modelo)")
	model.commands = [{"name": "status"}]
	assert_eq(codex.quota_command(model), "/status", "Codex con /status")


func test_claude_specifics() -> void:
	var claude := AgentAdapters.for_profile("claude", PackedStringArray())
	assert_true(claude.reads_account_from_cli(), "la cuenta sale del CLI")
	assert_eq(claude.api_key_variable(), "ANTHROPIC_API_KEY", "aviso de API key")
	assert_true(claude.session_meta(PackedStringArray()).has("claudeCode"), "_meta propio")
	var generic := AgentAdapters.for_profile("opencode", PackedStringArray())
	assert_eq(generic.session_meta(PackedStringArray()), {}, "el genérico no manda _meta")
	assert_eq(generic.quota_command(SessionModel.new()), "", "ni pide cuota")


func test_antigravity_reads_quota() -> void:
	var quota := QuotaMonitor.new()
	quota.setup(AgentLog.new())
	var text := "### Quota Limits\n- **Gemini Models**\n  - **Weekly Limit Remaining:** 80% remaining (resets Nov 02, 2026, 00:41 UTC)\n  - **Five Hour Limit Remaining:** 90% remaining (resets Oct 29, 2026, 00:09 UTC)\n"
	AgentAdapters.for_session("", PackedStringArray(), "", {"name": "antigravity-acp"}).read_quota(text, quota, SessionModel.new(), "Gemini 3.8 Flash")
	assert_true(quota.has_data(), "ventanas leídas")
	assert_true(absf(quota.utilization(QuotaMonitor.WINDOW_WEEKLY) - 0.2) < 0.001, "semana: 20 % usado")
