extends "test_case.gd"
## Dock vacío: las sesiones anteriores del proyecto (m12-12).

const RecentSessions := preload("res://addons/godot_agent/ui/dock/recent_sessions.gd")


func test_recent_meta() -> void:
	var updated := Time.get_unix_time_from_datetime_string("2026-10-29T03:56:00")
	assert_eq(RecentSessions.recent_meta({"agent": "Claude Code", "updated": updated, "turns": 4}), "Claude Code · 29/10 03:56 · 4 turns", "agente, cuándo y turnos")
	assert_eq(RecentSessions.recent_meta({"agent": "", "updated": 0, "turns": 1}), "1 turn", "solo lo que hay")
