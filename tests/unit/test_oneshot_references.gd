extends "test_case.gd"
## Archivos de referencia del One-shot: llegan al prompt inicial y al evaluador. Que se guarden con
## el run y se recuperen lo prueba tests/oneshot_check.gd (recuperación).

const OneShotRun := preload("res://addons/godot_agent/oneshot/oneshot_run.gd")


func test_prompts() -> void:
	var run := OneShotRun.new()
	run.goal = "Pong"
	assert_false(run.initial_prompt().contains("Reference material"), "sin referencias, nada")
	run.references = PackedStringArray(["/p/docs/gdd.md", "/p/.godot_agent/oneshot/x/refs/arte.png"])
	var initial := run.initial_prompt()
	assert_true(initial.contains("Reference material from the user") and initial.contains("- /p/docs/gdd.md") and initial.contains("- /p/.godot_agent/oneshot/x/refs/arte.png"), "el prompt inicial las lista")
	assert_true(initial.find("Reference material") < initial.find("Work autonomously"), "antes de los pasos: se leen antes de la spec")
	assert_true(initial.contains("the goal wins"), "si no coinciden, gana el objetivo")
	assert_true(run.qa_prompt().contains("- /p/docs/gdd.md"), "el evaluador compara el juego con ellas")
	run.free()
