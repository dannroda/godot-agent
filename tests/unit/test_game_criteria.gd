extends "test_case.gd"
## Criterios de evaluación del juego (D40): overrides, textos para los prompts, veredicto y el
## bloque de puntajes del evaluador.

const GameCriteria := preload("res://addons/godot_agent/oneshot/game_criteria.gd")
const FindingsParser := preload("res://addons/godot_agent/review/findings_parser.gd")
const OneShotRun := preload("res://addons/godot_agent/oneshot/oneshot_run.gd")


func test_resolve() -> void:
	var criteria := GameCriteria.resolve({"visual": {"weight": 0}, "code": {"threshold": 12}, "nope": {"weight": 3}})
	assert_eq(criteria.size(), 4, "los cuatro criterios")
	assert_eq(criteria[0].weight, 3, "default intacto")
	assert_eq(criteria[2].weight, 0, "peso pisado")
	assert_eq(criteria[3].threshold, 10, "umbral acotado a 10")
	assert_eq(GameCriteria.active(criteria).size(), 3, "peso 0 no se usa")
	assert_eq(GameCriteria.DEFAULTS[2].weight, 2, "los defaults no se tocan")


func test_prompts() -> void:
	var criteria := GameCriteria.resolve({"code": {"weight": 0}})
	var generator := GameCriteria.generator_text(criteria)
	assert_true(generator.contains("Playability (minimum 7, weight 3)") and not generator.contains("Code ("), generator)
	var rubric := GameCriteria.evaluator_rubric(criteria)
	for expected: String in ["id `playability`", "3: entities appear but don't respond to input", "cannot hear", "\"scores\""]:
		assert_true(rubric.contains(expected), "rúbrica: " + expected)
	var run := OneShotRun.new()
	run.goal = "Pong"
	assert_true(run.initial_prompt().contains("How the game will be evaluated"), "el prompt del One-shot lleva los criterios")
	run.free()


func test_verdict() -> void:
	var criteria := GameCriteria.resolve()
	var all_pass := GameCriteria.verdict([
		{"criterion": "playability", "score": 8}, {"criterion": "Functionality", "score": 7},
		{"criterion": "Visuals and feel", "score": 5}, {"criterion": "CODE", "score": 9},
	], criteria)
	assert_true(all_pass.passed, "todos llegan al mínimo")
	assert_true(is_equal_approx(all_pass.weighted, 7.1), "promedio ponderado (24+21+10+9)/9")
	var low := GameCriteria.verdict([{"criterion": "Playability", "score": 4}, {"criterion": "functionality", "score": 9}, {"criterion": "visual", "score": 9}], criteria)
	assert_false(low.passed, "uno abajo del mínimo")
	assert_eq(low.failing.size(), 1, "falla jugabilidad")
	assert_eq(low.failing[0].id, "playability", "id del que falla")
	assert_eq(low.missing, PackedStringArray(["code"]), "sin puntaje = no pasa")


func test_parser_scores() -> void:
	var text := "Evalué.\n```json\n{\"checks\": [{\"label\": \"Saque\", \"status\": \"fail\"}], \"scores\": [{\"criterion\": \"playability\", \"score\": \"6\", \"reason\": \"no hay reinicio\"}, {\"criterio\": \"visual\", \"puntaje\": 12}, {\"criterion\": \"code\"}]}\n```"
	var parsed := FindingsParser.parse(text)
	assert_eq(parsed.checks.size(), 1, "checks en el mismo bloque")
	assert_eq(parsed.scores, [{"criterion": "playability", "score": 6.0, "reason": "no hay reinicio"}, {"criterion": "visual", "score": 10.0, "reason": ""}], "puntajes normalizados")
	assert_eq(FindingsParser.parse("{\"scores\": [{\"criterion\": \"code\", \"score\": 7}]} y listo").scores.size(), 1, "sin fence")
