@tool
extends RefCounted
## Ranker del proveedor local (spec §16.2): une candidatos de todas las fuentes, junta duplicados y
## elige uno solo si es claro. Ante la duda no muestra nada.
## - Una regla que aplica gana (sus candidatos ya vienen ordenados).
## - Si no, el mejor tiene que superar `threshold` y sacarle `margin` al primer rival. Un candidato
##   que es prefijo de otro no es rival: son compatibles.
## - Ante un empate entre compatibles, el más largo.

const DEFAULT_THRESHOLD := 0.5
const DEFAULT_MARGIN := 0.12


## `candidates`: [{text, score, source, rule?, positions?, level?}]. Devuelve el elegido o {}.
static func pick(candidates: Array[Dictionary], threshold: float = DEFAULT_THRESHOLD, margin: float = DEFAULT_MARGIN) -> Dictionary:
	var best_rule: Dictionary = {}
	for candidate: Dictionary in candidates:
		if not str(candidate.get("rule", "")).is_empty() and float(candidate.score) >= threshold:
			if best_rule.is_empty() or float(candidate.score) > float(best_rule.score):
				best_rule = candidate
	if not best_rule.is_empty():
		return best_rule
	var merged := merge(candidates)
	if merged.is_empty():
		return {}
	var best: Dictionary = merged[0]
	if float(best.score) < threshold:
		return {}
	for i in range(1, merged.size()):
		var other: Dictionary = merged[i]
		var other_text: String = other.text
		var best_text: String = best.text
		if other_text.begins_with(best_text) or best_text.begins_with(other_text):
			# Compatibles: si están empatados, el más largo.
			if float(best.score) - float(other.score) < margin and other_text.length() > best_text.length():
				best = other
			continue
		if float(best.score) - float(other.score) < margin:
			return {}
		break
	return best


## Junta candidatos con el mismo texto (1 - Π(1 - s)) y los ordena de mayor a menor puntaje.
static func merge(candidates: Array[Dictionary]) -> Array[Dictionary]:
	var by_text: Dictionary = {}
	for candidate: Dictionary in candidates:
		var text: String = candidate.text
		if text.is_empty():
			continue
		if by_text.has(text):
			var existing: Dictionary = by_text[text]
			var score := float(candidate.score)
			if score > float(existing.best):
				existing.source = candidate.source
				existing.best = score
			existing.score = 1.0 - (1.0 - float(existing.score)) * (1.0 - score)
			if candidate.has("positions") and not existing.has("positions"):
				existing.positions = candidate.positions
				existing.level = candidate.level
		else:
			var entry := {"text": text, "score": float(candidate.score), "source": candidate.source, "best": float(candidate.score)}
			# De dónde salió una línea recuperada, para extenderla a un bloque si gana.
			if candidate.has("positions"):
				entry.positions = candidate.positions
				entry.level = candidate.level
			by_text[text] = entry
	var out: Array[Dictionary] = []
	for text: String in by_text:
		var entry: Dictionary = by_text[text]
		entry.erase("best")
		out.append(entry)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a.score) > float(b.score) if not is_equal_approx(float(a.score), float(b.score)) else str(a.text).length() > str(b.text).length())
	return out
