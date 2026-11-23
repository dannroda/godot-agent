extends "test_case.gd"
## m11-80: el informe de diagnóstico para un issue, solo con valores de listas cerradas.

const DiagnosticReport := preload("res://addons/godot_agent/core/diagnostic_report.gd")
const DiagnosticReportDialog := preload("res://addons/godot_agent/ui/diagnostic_report_dialog.gd")
const SessionModel := preload("res://addons/godot_agent/session/session_model.gd")
const QuotaMonitor := preload("res://addons/godot_agent/core/quota_monitor.gd")

## Lo que no puede salir nunca en el informe.
const PRIVATE: PackedStringArray = ["/home/ana", "C:\\Users\\ana", "ana@example.com", "player.gd", "secret-token", "Ana Pérez", "hola agente"]


func _hostile_raw() -> Dictionary:
	return {
		"addon_version": "/home/ana/addons", "os": "C:\\Users\\ana", "architecture": "ana@example.com",
		"godot": {"major": "/home/ana", "minor": -3, "patch": 99999, "status": "player.gd"},
		"agent": {"kind": "secret-token", "name": "Ana Pérez", "version": "1.0 ana@example.com", "protocol_version": "hola agente"},
		"session": {"state": "hola agente", "acp_phase": "/home/ana", "harness_mode": "player.gd", "failure_kind": "secret-token",
			"error_code": 1234, "last_stop_reason": "ana@example.com", "quota_state": ["x"], "open_tabs": {"a": 1}},
		"mcp": {"server_listening": "yes", "agent_connected": true, "client": "Ana Pérez", "tool_calls": 1e9, "tool_errors": "3"},
		"oneshot": {"active": 1, "phase": "C:\\Users\\ana"},
		"extra": {"path": "/home/ana/secret-token"},
	}


func test_nothing_private_gets_through() -> void:
	var report := DiagnosticReport.build(_hostile_raw())
	var text := DiagnosticReport.clipboard_text(report)
	for value: String in PRIVATE:
		assert_false(text.contains(value), "no sale «%s»" % value)
	assert_false(report.has("extra"), "solo los campos del esquema")
	assert_eq(report.schema_version, DiagnosticReport.SCHEMA_VERSION, "lleva schema_version")
	assert_eq(report.os, "unknown", "un valor fuera de la lista es unknown")
	assert_eq(report.agent.name, "other", "un agente que no conocemos es other, sin su nombre")
	assert_eq(report.mcp.client, "other", "lo mismo un cliente MCP")
	assert_eq(report.godot.minor, 0, "los números no bajan de 0")
	assert_eq(report.mcp.tool_calls, DiagnosticReport.COUNT_MAX, "ni pasan del tope")
	assert_eq(report.session.error_code, 0, "un código de error que no conocemos es 0")
	assert_false(report.mcp.server_listening, "un bool que no es bool es false")
	assert_false(report.oneshot.active, "también acá")


func test_known_values_pass() -> void:
	var report := DiagnosticReport.build({
		"addon_version": "0.2.1", "os": "Windows", "architecture": "x86_64",
		"godot": {"major": 4, "minor": 7, "patch": 2, "status": "stable"},
		"agent": {"kind": "antigravity", "name": "antigravity-acp", "version": "1.4.3", "protocol_version": 1},
		"session": {"state": "failed", "acp_phase": "failed", "harness_mode": "build", "failure_kind": "process_exited", "error_code": -32000,
			"last_stop_reason": "error", "quota_state": "normal", "open_tabs": 2},
		"mcp": {"server_listening": true, "agent_connected": false, "client": "claude-code", "tool_calls": 12, "tool_errors": 2},
		"oneshot": {"active": true, "phase": "running"},
	})
	assert_eq(report.agent, {"kind": "antigravity", "name": "antigravity-acp", "version": "1.4.3", "protocol_version": 1}, "el agente")
	assert_eq(report.session.failure_kind, "process_exited", "la falla")
	assert_eq(report.session.error_code, -32000, "su código")
	assert_eq(report.mcp.client, "none", "sin conexión MCP no hay cliente")
	assert_eq(report.oneshot.phase, "running", "la fase del One-shot")


func test_bounded_version() -> void:
	for good: String in ["1.2.3", "0.2.1-beta3", "4.7.2+abc", "v2.0", "12"]:
		assert_false(DiagnosticReport.bounded_version(good) == "unknown", good)
	for bad: Variant in ["", "ana", "1.0 ana@example.com", "/home/ana/1.0", "1.2.3-" + "x".repeat(40), 3, null]:
		assert_eq(DiagnosticReport.bounded_version(bad), "unknown", str(bad))


func test_collect_from_a_session() -> void:
	var model := SessionModel.new()
	model.apply_initialize({"protocolVersion": 1, "agentInfo": {"name": "codex-acp", "title": "Codex de Ana", "version": "0.5.0"}})
	model.failure_kind = "turn_limit"
	model.failure_code = -32603
	var quota := QuotaMonitor.new()
	var raw := DiagnosticReport.collect("0.2.1", model, "codex", quota, {"server_listening": true, "agent_connected": true, "client": "codex-mcp-client"}, {"active": false, "phase": "idle"}, 1)
	var report := DiagnosticReport.build(raw)
	assert_eq(report.agent.name, "codex-acp", "el nombre del adaptador")
	assert_eq(report.agent.version, "0.5.0", "su versión")
	assert_eq(report.agent.protocol_version, 1, "el protocolo ACP")
	assert_eq(report.session.state, "disconnected", "el estado de la sesión")
	assert_eq(report.session.acp_phase, "none", "y la fase")
	assert_eq(report.session.failure_kind, "turn_limit", "la falla")
	assert_eq(report.session.harness_mode, "build", "el modo")
	assert_eq(report.session.quota_state, "unknown", "la cuota")
	assert_eq(report.godot.major, Engine.get_version_info().major, "la versión de Godot")
	assert_false(report.os == "unknown", "el sistema: %s" % report.os)
	assert_false(DiagnosticReport.serialize(report).contains("Ana"), "el título del agente no va")
	assert_eq(DiagnosticReport.acp_phase("starting", false), "initializing", "antes de initialize")
	assert_eq(DiagnosticReport.acp_phase("starting", true), "opening_session", "después")


func test_dialog_shows_what_it_copies() -> void:
	var report := DiagnosticReport.build({"addon_version": "0.2.1"})
	var dialog := DiagnosticReportDialog.new()
	dialog.setup(report)
	(Engine.get_main_loop() as SceneTree).root.add_child(dialog)
	assert_eq(dialog.preview_text(), DiagnosticReport.serialize(report), "la vista previa es el informe")
	var copied: Array = []
	dialog.copied.connect(func(text: String) -> void: copied.append(text))
	dialog.confirmed.emit()
	assert_eq(copied.size(), 1, "Copiar copia")
	assert_true(str(copied[0]).contains(dialog.preview_text()) and str(copied[0]).contains("```json"), "lo mismo que se vio, en un bloque de código")
	dialog.free()
