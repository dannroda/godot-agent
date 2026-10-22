@tool
extends RefCounted
## Criterios con los que se evalúa un juego hecho por el One-shot (D40). Guían al agente que
## construye (van en su prompt) y al evaluador (rúbrica con ejemplos de puntaje, para que no se
## vuelva indulgente con el tiempo). Cada criterio tiene peso (0 = no se usa) y umbral de 0 a 10:
## el juego pasa si todos los criterios con peso llegan a su umbral; el peso arma el promedio y
## dice qué priorizar.

const DEFAULTS: Array[Dictionary] = [
	{
		"id": "playability", "weight": 3, "threshold": 7,
		"name": "Playability",  # i18n
		"description": "The core mechanic responds to input, there is a complete loop (start → play → win or lose → restart) and no state gets stuck.",
		"anchors": [
			"3: entities appear but don't respond to input, or the game can't be started",
			"6: it's playable, but the game over or the restart is missing, or there is a state where it gets stuck",
			"9: complete loop, controls respond on the same frame and nothing gets stuck",
		],
	},
	{
		"id": "functionality", "weight": 3, "threshold": 7,
		"name": "Functionality",  # i18n
		"description": "Every feature in the goal (and in the spec, if there is one) works in a playtest with simulated input, with no errors in get_errors.",
		"anchors": [
			"3: half of the features are missing or fail, or there are errors in get_errors",
			"6: almost all of them are there, but one fails in the playtest or there are warnings that matter",
			"9: all of them work in the playtest, with no errors or warnings",
		],
	},
	{
		"id": "visual", "weight": 2, "threshold": 5,
		"name": "Visuals and feel",  # i18n
		"description": "What happens on screen is readable, every action has feedback and the style is consistent (checked with capture_game_frame).",
		"anchors": [
			"3: default shapes with no intent; you can't tell what each thing is or what happened",
			"6: it reads well and the style is consistent, but actions have almost no feedback",
			"9: readable at a glance, clear feedback on every action, consistent style",
		],
	},
	{
		"id": "code", "weight": 1, "threshold": 5,
		"name": "Code",  # i18n
		"description": "Statically typed GDScript, well-built scenes and no parser warnings.",
		"anchors": [
			"3: no types, logic piled into one script, warnings or fragile node paths",
			"6: mostly typed, reasonable structure, a warning or two",
			"9: fully typed, scenes and scripts with one responsibility each, no warnings",
		],
	},
]
const AUDIO_NOTE := "The evaluator cannot hear: audio is verified only through the code (that the AudioStreamPlayer nodes exist, have a stream and are triggered at the right moment), never by how it sounds."


## Criterios con los pesos y umbrales del proyecto. `overrides`: id -> {weight, threshold}.
static func resolve(overrides: Dictionary = {}) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for base: Dictionary in DEFAULTS:
		var criterion := base.duplicate(true)
		var override: Variant = overrides.get(base.id)
		if override is Dictionary:
			if override.has("weight"):
				criterion.weight = clampi(int(override.weight), 0, 10)
			if override.has("threshold"):
				criterion.threshold = clampi(int(override.threshold), 0, 10)
		result.append(criterion)
	return result


static func active(criteria: Array[Dictionary]) -> Array[Dictionary]:
	return criteria.filter(func(criterion: Dictionary) -> bool: return int(criterion.weight) > 0)


## Para el prompt del agente que construye: qué se va a evaluar y con qué umbral.
static func generator_text(criteria: Array[Dictionary]) -> String:
	var lines: PackedStringArray = ["How the game will be evaluated (score from 0 to 10; it has to reach the minimum on every criterion, and the weight says what to prioritize):"]
	for criterion: Dictionary in active(criteria):
		lines.append("- %s (minimum %d, weight %d): %s" % [criterion.name, criterion.threshold, criterion.weight, criterion.description])
	return "\n".join(lines)


## Para el evaluador: la rúbrica con ejemplos de puntaje y el formato del bloque de puntajes.
static func evaluator_rubric(criteria: Array[Dictionary]) -> String:
	var lines: PackedStringArray = ["Criteria (score from 0 to 10; the game passes only if each one reaches its minimum):"]
	for criterion: Dictionary in active(criteria):
		lines.append("- %s · id `%s` · minimum %d · weight %d: %s" % [criterion.name, criterion.id, criterion.threshold, criterion.weight, criterion.description])
		for anchor: String in criterion.anchors:
			lines.append("    - %s" % anchor)
	lines.append("Use the examples as a fixed reference: a 7 has to be worth the same in the first round as in the last. When in doubt, give the lower score.")
	lines.append(AUDIO_NOTE)
	lines.append("Report the scores in a ```json {\"scores\":[{\"criterion\":\"<id>\",\"score\":0-10,\"reason\":\"what you saw\"}]} block.")
	return "\n".join(lines)


## Veredicto: {passed, weighted (promedio ponderado), failing: [{id, name, score, threshold}],
## missing: [ids sin puntaje]}. Un criterio sin puntaje no pasa.
static func verdict(scores: Array, criteria: Array[Dictionary]) -> Dictionary:
	var by_id := {}
	for score: Variant in scores:
		if score is Dictionary:
			var id := match_id(str(score.get("criterion", "")), criteria)
			if not id.is_empty():
				by_id[id] = float(score.get("score", 0))
	var failing: Array[Dictionary] = []
	var missing: PackedStringArray = []
	var total := 0.0
	var weights := 0.0
	for criterion: Dictionary in active(criteria):
		if not by_id.has(criterion.id):
			missing.append(criterion.id)
			continue
		var value: float = by_id[criterion.id]
		total += value * int(criterion.weight)
		weights += int(criterion.weight)
		if value < int(criterion.threshold):
			failing.append({"id": criterion.id, "name": criterion.name, "score": value, "threshold": int(criterion.threshold)})
	return {
		"passed": failing.is_empty() and missing.is_empty(),
		"weighted": snappedf(total / weights, 0.1) if weights > 0.0 else 0.0,
		"failing": failing,
		"missing": missing,
		"scores": by_id,
	}


## Id del criterio para lo que escribió el agente: el id o el nombre, sin mayúsculas ni tildes.
static func match_id(text: String, criteria: Array[Dictionary]) -> String:
	var key := _plain(text)
	for criterion: Dictionary in criteria:
		if key == _plain(criterion.id) or key == _plain(criterion.name) or key.begins_with(_plain(str(criterion.name).get_slice(" ", 0))):
			return criterion.id
	return ""


static func _plain(text: String) -> String:
	var plain := text.strip_edges().to_lower()
	for pair: Array in [["á", "a"], ["é", "e"], ["í", "i"], ["ó", "o"], ["ú", "u"]]:
		plain = plain.replace(pair[0], pair[1])
	return plain
