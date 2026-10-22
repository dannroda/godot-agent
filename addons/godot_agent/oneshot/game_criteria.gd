@tool
extends RefCounted
## Criterios con los que se evalúa un juego hecho por el One-shot (D40). Guían al agente que
## construye (van en su prompt) y al evaluador (rúbrica con ejemplos de puntaje, para que no se
## vuelva indulgente con el tiempo). Cada criterio tiene peso (0 = no se usa) y umbral de 0 a 10:
## el juego pasa si todos los criterios con peso llegan a su umbral; el peso arma el promedio y
## dice qué priorizar.

const DEFAULTS: Array[Dictionary] = [
	{
		"id": "playability", "name": "Jugabilidad", "weight": 3, "threshold": 7,
		"description": "La mecánica principal responde a los inputs, hay un loop completo (empezar → jugar → ganar o perder → reiniciar) y no hay estados trabados.",
		"anchors": [
			"3: las entidades aparecen pero no responden al input, o el juego no se puede empezar",
			"6: se juega, pero falta el fin de partida o el reinicio, o hay un estado donde se traba",
			"9: loop completo, los controles responden en el mismo frame y nada se traba",
		],
	},
	{
		"id": "functionality", "name": "Funcionalidad", "weight": 3, "threshold": 7,
		"description": "Cada feature del objetivo (y del spec, si hay) funciona en un playtest con inputs simulados, sin errores en get_errors.",
		"anchors": [
			"3: la mitad de las features no están o fallan, o hay errores en get_errors",
			"6: están casi todas, pero una falla en el playtest o hay warnings que importan",
			"9: todas funcionan en el playtest, sin errores ni warnings",
		],
	},
	{
		"id": "visual", "name": "Visual y feel", "weight": 2, "threshold": 5,
		"description": "Se lee qué pasa en pantalla, cada acción tiene feedback y el estilo es coherente (se mira con capture_game_frame).",
		"anchors": [
			"3: formas por defecto sin intención, no se entiende qué es cada cosa ni qué pasó",
			"6: se lee bien y el estilo es coherente, pero las acciones casi no tienen feedback",
			"9: legible de un vistazo, feedback claro en cada acción, estilo consistente",
		],
	},
	{
		"id": "code", "name": "Código", "weight": 1, "threshold": 5,
		"description": "GDScript con tipado estático, escenas bien armadas y sin warnings del parser.",
		"anchors": [
			"3: sin tipos, lógica amontonada en un script, warnings o rutas de nodos frágiles",
			"6: tipado en general, estructura razonable, algún warning",
			"9: tipado completo, escenas y scripts con una responsabilidad cada uno, sin warnings",
		],
	},
]
const AUDIO_NOTE := "El evaluador no puede oír: el audio se verifica solo por código (que los nodos AudioStreamPlayer existan, tengan stream y se disparen en el momento correcto), nunca por cómo suena."


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
	var lines: PackedStringArray = ["Así se va a evaluar el juego (puntaje de 0 a 10; tiene que llegar al mínimo en cada criterio, y el peso dice qué priorizar):"]
	for criterion: Dictionary in active(criteria):
		lines.append("- %s (mínimo %d, peso %d): %s" % [criterion.name, criterion.threshold, criterion.weight, criterion.description])
	return "\n".join(lines)


## Para el evaluador: la rúbrica con ejemplos de puntaje y el formato del bloque de puntajes.
static func evaluator_rubric(criteria: Array[Dictionary]) -> String:
	var lines: PackedStringArray = ["Criterios (puntaje de 0 a 10; el juego pasa solo si cada uno llega a su mínimo):"]
	for criterion: Dictionary in active(criteria):
		lines.append("- %s · id `%s` · mínimo %d · peso %d: %s" % [criterion.name, criterion.id, criterion.threshold, criterion.weight, criterion.description])
		for anchor: String in criterion.anchors:
			lines.append("    - %s" % anchor)
	lines.append("Usá los ejemplos como referencia fija: un 7 tiene que valer lo mismo en la primera vuelta que en la última. Ante la duda, el puntaje más bajo.")
	lines.append(AUDIO_NOTE)
	lines.append("Reportá los puntajes en un bloque ```json {\"scores\":[{\"criterion\":\"<id>\",\"score\":0-10,\"reason\":\"qué viste\"}]}.")
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
