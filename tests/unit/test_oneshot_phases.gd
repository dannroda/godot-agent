extends "test_case.gd"
## Tabla de transiciones de RunPhase y RunStage del One-shot (m13-12): toda fase tiene su fila,
## cada cambio de la tabla pasa sin aviso, uno fuera de la tabla se anota y se aplica igual, y en
## el código nada asigna `phase` ni `_stage` fuera de su setter.

const OneShotRun := preload("res://addons/godot_agent/oneshot/oneshot_run.gd")
const SOURCE := "res://addons/godot_agent/oneshot/oneshot_run.gd"


func test_phase_table_covers_every_phase() -> void:
	var phases: Array = OneShotRun.RunPhase.values()
	for from: int in phases:
		assert_true(OneShotRun.PHASE_TRANSITIONS.has(from), "%s tiene fila en la tabla" % OneShotRun.RunPhase.keys()[from])
		for to: Variant in OneShotRun.PHASE_TRANSITIONS.get(from, []):
			assert_true(int(to) in phases and int(to) != from, "%s → %s es una fase distinta" % [OneShotRun.RunPhase.keys()[from], to])
	assert_eq(_reachable(OneShotRun.PHASE_TRANSITIONS, OneShotRun.RunPhase.IDLE).size(), phases.size(), "desde IDLE se llega a todas las fases")
	for from: int in phases:
		if from != OneShotRun.RunPhase.IDLE:
			assert_true(OneShotRun.RunPhase.FINISHED in _reachable(OneShotRun.PHASE_TRANSITIONS, from), "desde %s se puede terminar" % OneShotRun.RunPhase.keys()[from])


func test_walks_every_phase_transition() -> void:
	var run := OneShotRun.new()
	var walked := 0
	for from: int in OneShotRun.PHASE_TRANSITIONS:
		for to: int in OneShotRun.PHASE_TRANSITIONS[from]:
			run.phase = from as OneShotRun.RunPhase
			run._set_phase(to as OneShotRun.RunPhase)
			assert_eq(run.phase, to, "%s → %s" % [OneShotRun.RunPhase.keys()[from], OneShotRun.RunPhase.keys()[to]])
			walked += 1
	assert_eq(run.unexpected_transitions, 0, "ningún cambio de la tabla se anota como inesperado")
	assert_true(walked > OneShotRun.RunPhase.size(), "recorrió la tabla")
	run.free()


func test_unexpected_phase_transition_is_noted_and_applied() -> void:
	var run := OneShotRun.new()
	run.phase = OneShotRun.RunPhase.IDLE
	assert_false(OneShotRun.phase_transition_expected(OneShotRun.RunPhase.IDLE, OneShotRun.RunPhase.EVALUATING), "IDLE → EVALUATING no está en la tabla")
	run._set_phase(OneShotRun.RunPhase.EVALUATING)
	assert_eq(run.phase, OneShotRun.RunPhase.EVALUATING, "se aplica igual")
	assert_eq(run.unexpected_transitions, 1, "y se anota")
	assert_eq(run.last_unexpected_transition, "oneshot: unexpected phase transition IDLE -> EVALUATING")
	run._set_phase(OneShotRun.RunPhase.EVALUATING)
	assert_eq(run.unexpected_transitions, 1, "la misma fase no es un cambio")
	run.free()


func test_walks_every_stage_transition() -> void:
	var run := OneShotRun.new()
	for from: int in OneShotRun.RunStage.values():
		assert_true(OneShotRun.STAGE_TRANSITIONS.has(from), "%s tiene fila en la tabla" % OneShotRun.RunStage.keys()[from])
		for to: int in OneShotRun.STAGE_TRANSITIONS.get(from, []):
			run._set_stage(from as OneShotRun.RunStage, true)
			run._set_stage(to as OneShotRun.RunStage)
			assert_eq(run.stage(), to, "%s → %s" % [OneShotRun.RunStage.keys()[from], OneShotRun.RunStage.keys()[to]])
	assert_eq(run.unexpected_transitions, 0, "ningún cambio de etapa de la tabla se anota")
	run._set_stage(OneShotRun.RunStage.SPEC_APPROVAL, true)
	run._set_stage(OneShotRun.RunStage.EVALUATION)
	assert_eq(run.stage(), OneShotRun.RunStage.EVALUATION, "spec sin aprobar → QA se aplica igual")
	assert_eq(run.unexpected_transitions, 1, "y se anota")
	run.free()


func test_saved_stage_reads_old_saves() -> void:
	assert_eq(OneShotRun._saved_stage({"stage": "EVALUATION"}), OneShotRun.RunStage.EVALUATION, "con stage")
	assert_eq(OneShotRun._saved_stage({"resume_qa": true}), OneShotRun.RunStage.EVALUATION, "guardado viejo con la QA cortada")
	assert_eq(OneShotRun._saved_stage({"awaiting_spec": true}), OneShotRun.RunStage.SPEC_APPROVAL, "guardado viejo con el spec sin aprobar")
	assert_eq(OneShotRun._saved_stage({}), OneShotRun.RunStage.BUILDING, "sin nada, construye")


## En el código, `phase` y `_stage` solo se asignan dentro de su setter.
func test_state_only_changes_through_setters() -> void:
	var source := FileAccess.get_file_as_string(SOURCE)
	assert_false(source.is_empty(), "se lee oneshot_run.gd")
	for field: String in ["phase", "_stage"]:
		var setter := "_set_phase" if field == "phase" else "_set_stage"
		var assignment := RegEx.create_from_string("^\\t+(self\\.)?%s\\s*=[^=]" % field)
		var function := ""
		var found := 0
		for line: String in source.split("\n"):
			if line.begins_with("func ") or line.begins_with("static func "):
				function = line.get_slice("(", 0).get_slice(" ", line.get_slice("(", 0).get_slice_count(" ") - 1)
			if assignment.search(line) != null:
				found += 1
				assert_eq(function, setter, "`%s` se asigna en %s" % [line.strip_edges(), function])
		assert_eq(found, 1, "`%s` se asigna una sola vez (en %s)" % [field, setter])


func _reachable(table: Dictionary, start: int) -> Array:
	var seen: Array = [start]
	var queue: Array = [start]
	while not queue.is_empty():
		var current: int = queue.pop_front()
		for next: int in table.get(current, []):
			if not next in seen:
				seen.append(next)
				queue.append(next)
	return seen
