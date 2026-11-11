extends "test_case.gd"
## m12-48: el aviso de un playtest que pasó anuncia la regresión guardada con sus acciones.

const SessionController := preload("res://addons/godot_agent/session/session_controller.gd")
const SessionModel := preload("res://addons/godot_agent/session/session_model.gd")
const ChatEntry := preload("res://addons/godot_agent/session/chat_entry.gd")
const AgentLog := preload("res://addons/godot_agent/core/agent_log.gd")
const I18n := preload("res://addons/godot_agent/core/i18n.gd")


func test_regression_notice_parts() -> void:
	I18n.set_locale("en")
	var parts := SessionController.regression_notice_parts(3)
	assert_eq(parts.text, "Saved as a regression: the harness can replay it without the agent.", "la línea del aviso")
	var ids := (parts.actions as Array).map(func(action: Dictionary) -> String: return str(action.id))
	assert_eq(ids, [SessionController.ACTION_RUN_REGRESSIONS, SessionController.ACTION_REGRESSIONS_WORKFLOW], "correr y CI workflow")
	assert_eq(parts.actions[0].label, "Run regressions (3)", "con la cantidad guardada")
	assert_eq(parts.actions[0].data, 1, "una repetición")
	assert_eq(parts.actions[1].label, "CI workflow…", "el workflow")
	I18n.set_locale("es")
	assert_eq(SessionController.regression_notice_parts(1).actions[0].label, "Correr regresiones (1)", "traducido")
	I18n.set_locale("en")


## El veredicto de un playtest que pasó con script deja la regresión, lo dice y ofrece las acciones;
## la primera vez explica qué son; la segunda ya no.
func test_passing_playtest_announces_the_regression() -> void:
	I18n.set_locale("en")
	var controller := SessionController.new()
	controller.setup(SessionModel.new(), AgentLog.new(), "/tmp/project")
	controller.regressions_dir = temp_dir("regression_notice_%d" % Time.get_ticks_usec())
	var model := controller.model
	model.apply_update({"sessionUpdate": "tool_call", "toolCallId": "t1", "title": "mcp__godot__run_scene", "kind": "other", "status": "completed", "rawInput": {"scene": "res://a.tscn"}, "rawOutput": "ok"})
	var passed := {"verdict": "pass", "summary": "jumps", "evidence": PackedStringArray(["y = 1"]), "repro": PackedStringArray(), "regression": "func run(game):\n\treturn true"}
	controller.call(&"_report_playtest", passed, "", 0, "Playtest: salta")
	var notices: Array = model.entries().filter(func(entry: ChatEntry) -> bool: return entry.kind == ChatEntry.EntryKind.NOTICE)
	assert_eq(notices.size(), 2, "el veredicto y el aviso de la primera regresión")
	var verdict: ChatEntry = notices[0]
	assert_eq(verdict.title, "Playtest: passed · jumps", "el veredicto")
	assert_true(verdict.text.contains("Saved as a regression"), "dice que la guardó · " + verdict.text)
	assert_true(verdict.text.begins_with("Saved as a regression"), "sin alertas, sin línea vacía antes (revisión next2 #27) · %s" % [verdict.text.c_escape()])
	var ids := verdict.actions.map(func(action: Dictionary) -> String: return str(action.id))
	assert_eq(ids, [SessionController.ACTION_RUN_REGRESSIONS, SessionController.ACTION_REGRESSIONS_WORKFLOW], "con las acciones")
	assert_eq(verdict.actions[0].label, "Run regressions (1)", "cuenta la guardada")
	var first: ChatEntry = notices[1]
	assert_true(first.text.begins_with("First regression saved.") and first.text.contains("CI workflow") and first.level == ChatEntry.NoticeLevel.INFO, "explica qué son · " + first.text)
	controller.call(&"_report_playtest", {"verdict": "pass", "summary": "runs", "evidence": PackedStringArray(), "repro": PackedStringArray(), "regression": "func run(game):\n\treturn true"}, "", 0, "Playtest: corre")
	notices = model.entries().filter(func(entry: ChatEntry) -> bool: return entry.kind == ChatEntry.EntryKind.NOTICE)
	assert_eq(notices.size(), 3, "la segunda vez solo el veredicto")
	assert_eq((notices[2] as ChatEntry).actions[0].label, "Run regressions (2)", "y cuenta dos")
	controller.call(&"_report_playtest", {"verdict": "fail", "summary": "no", "evidence": PackedStringArray(), "repro": PackedStringArray(), "regression": "func run(game):\n\treturn true"}, "", 0, "Playtest: falla")
	notices = model.entries().filter(func(entry: ChatEntry) -> bool: return entry.kind == ChatEntry.EntryKind.NOTICE)
	assert_true((notices[3] as ChatEntry).actions.is_empty() and not (notices[3] as ChatEntry).text.contains("regression"), "lo que falló no deja regresión ni acciones")
