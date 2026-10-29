extends "test_case.gd"
## System prompt del harness: las convenciones de Godot van en todos los modos (m7-19).

const SessionController := preload("res://addons/godot_agent/session/session_controller.gd")
const SessionModel := preload("res://addons/godot_agent/session/session_model.gd")
const AgentLog := preload("res://addons/godot_agent/core/agent_log.gd")
const GameCriteria := preload("res://addons/godot_agent/oneshot/game_criteria.gd")

const CONVENTIONS: PackedStringArray = [
	"Godot conventions", "scenes saved on disk", "built-in nodes", "Call down, signal up",
	"Statically typed", "Resources", "seed", "Verify after every change", "the project's file wins",
]


func test_conventions_in_every_mode() -> void:
	var model := SessionModel.new()
	var controller := SessionController.new()
	controller.setup(model, AgentLog.new(), "/tmp/project")
	for mode: int in [SessionModel.HarnessMode.ASK, SessionModel.HarnessMode.REVIEW, SessionModel.HarnessMode.BUILD, SessionModel.HarnessMode.ONESHOT]:
		model.set_harness_mode(mode)
		var prompt := controller.system_prompt()
		for text: String in CONVENTIONS:
			assert_true(prompt.contains(text), "modo %d: %s" % [mode, text])
	model.set_harness_mode(SessionModel.HarnessMode.REVIEW)
	assert_true(controller.system_prompt().contains("Departures from the Godot conventions"), "Revisar las reporta como hallazgos")
	var prompt := controller.system_prompt()
	assert_true(prompt.contains(ProjectSettings.globalize_path(SessionController.HEADLESS_GUIDE_PATH)), "la ruta de la guía headless (m14-06)")
	assert_false(RegEx.create_from_string("\\{[a-z_]+\\}").search(prompt) != null, "sin variables sin reemplazar")
	assert_true(FileAccess.get_file_as_string(SessionController.HEADLESS_GUIDE_PATH).contains("owner = root"), "la guía existe")


func test_code_criterion_uses_conventions() -> void:
	var code: Dictionary = GameCriteria.resolve().filter(func(c: Dictionary) -> bool: return c.id == "code")[0]
	for text: String in ["scenes saved on disk", "call down and signal up", "Resources", "seeded"]:
		assert_true(str(code.description).contains(text), text)
