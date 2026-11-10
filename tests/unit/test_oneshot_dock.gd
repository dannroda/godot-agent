extends "test_case.gd"
## Lo que el One-shot le toma al dock mientras corre (m13-06): el prompt, «Reintentar» y el login.

const OneShotRun := preload("res://addons/godot_agent/oneshot/oneshot_run.gd")
const SessionModel := preload("res://addons/godot_agent/session/session_model.gd")


## m13-29: fase y etapa para el agente, con su antigüedad.
func test_describe_phase() -> void:
	var run := OneShotRun.new()
	for stage: int in OneShotRun.RunStage.values():
		assert_true(OneShotRun.STAGE_LABELS.has(stage), "etapa %d con etiqueta" % stage)
	assert_eq(run.describe_phase(), "one-shot: idle, building", "sin arrancar: sin antigüedad")
	assert_eq(run.phase_age_seconds(), -1, "sin cambios de fase, no se sabe")
	run.free()


func test_takes_only_while_running() -> void:
	var run := OneShotRun.new()
	var dock_model := SessionModel.new()
	assert_false(run.take_dock_prompt("más rápido"), "sin run, el prompt es del dock")
	assert_false(run.take_dock_retry(dock_model), "sin run, Reintentar abre la sesión del dock")
	assert_false(run.take_login(), "sin run, el login abre una sesión nueva")
	run.phase = OneShotRun.RunPhase.RUNNING
	assert_true(run.take_dock_retry(dock_model), "corriendo, Reintentar es del run")
	assert_true(dock_model.entries().size() == 1 and str(dock_model.entries()[0].text).contains("still running"), "y avisa que sigue corriendo")
	assert_false(run.take_login(), "corriendo sin pausa, el login no lo retoma")
	run.free()
