@tool
extends RefCounted
## Extrae del texto del agente los bloques `{"findings": […]}` (spec §9.4), `{"checks": […]}`
## (One-shot, §10), `{"scores": […]}` (criterios del evaluador, D40) y `{"playtest": {…}}` (veredicto
## de un playtest, m14-03), de forma tolerante:
## - en fences ```json o sin fence, con texto alrededor, o varios bloques en el mismo mensaje;
## - comas finales, campos con otros nombres (description, fix, file…), "archivo.gd:12" en path;
## - severidades en inglés o castellano.
## Lo que no se puede normalizar se descarta, sin cortar el resto.

const SEVERITIES: PackedStringArray = ["bug", "order", "perf", "style"]
const SEVERITY_ALIASES: Dictionary = {
	"bug": "bug", "error": "bug", "critical": "bug", "crítico": "bug", "critico": "bug", "high": "bug", "alta": "bug",
	"order": "order", "orden": "order", "ordering": "order", "init": "order", "lifecycle": "order", "orden de ejecución": "order",
	"perf": "perf", "performance": "perf", "rendimiento": "perf", "optimization": "perf", "optimización": "perf",
	"style": "style", "estilo": "style", "nit": "style", "convention": "style", "convención": "style", "info": "style", "low": "style",
}
const MAX_TEXT := 4000


## `{findings: Array[Dictionary], checks: Array[Dictionary], scores: Array[Dictionary], playtest: Dictionary}`.
## Playtest: {verdict: pass|fail|blocked|explored, kind, summary, evidence: [texto], repro: [paso], visual,
## alerts, notes, stale_notes} o {} si no hubo.
## Finding: {path (res:// si se pudo), line (≥1, 0 = sin línea), severity, title, body, suggestion}.
## Check: {label, status: pass|fail|pending, detail}.
## Score: {criterion, score (0–10), reason}.
static func parse(text: String, project_root: String = "") -> Dictionary:
	var findings: Array[Dictionary] = []
	var checks: Array[Dictionary] = []
	var scores: Array[Dictionary] = []
	var playtest: Dictionary = {}
	var seen: Dictionary = {}
	for candidate: Variant in _json_candidates(text):
		var raw_findings: Variant = null
		var raw_checks: Variant = null
		var raw_scores: Variant = null
		if candidate is Dictionary:
			raw_findings = candidate.get("findings")
			raw_checks = candidate.get("checks")
			raw_scores = candidate.get("scores")
			var verdict := normalize_playtest(candidate.get("playtest"))
			if not verdict.is_empty():
				playtest = verdict  # el último bloque del turno manda
		elif candidate is Array and not candidate.is_empty() and candidate[0] is Dictionary and (candidate[0] as Dictionary).has("line"):
			raw_findings = candidate
		if raw_findings is Array:
			for item: Variant in raw_findings:
				var finding := normalize_finding(item, project_root)
				var key := "%s:%d:%s" % [finding.get("path", ""), finding.get("line", 0), finding.get("title", "")]
				if not finding.is_empty() and not seen.has(key):
					seen[key] = true
					findings.append(finding)
		if raw_checks is Array:
			for item: Variant in raw_checks:
				var check := normalize_check(item)
				if not check.is_empty():
					checks.append(check)
		if raw_scores is Array:
			for item: Variant in raw_scores:
				var score := normalize_score(item)
				if not score.is_empty():
					scores.append(score)
	return {"findings": findings, "checks": checks, "scores": scores, "playtest": playtest}


## Veredicto de un playtest, o {} si no se entiende (sin veredicto reconocible no hay playtest).
static func normalize_playtest(item: Variant) -> Dictionary:
	if not item is Dictionary:
		return {}
	var raw := _first_string(item, ["verdict", "result", "status"]).strip_edges().to_lower()
	var verdict := ""
	if raw in ["pass", "passed", "ok", "success", "works", "funciona", "achieved"]:
		verdict = "pass"
	elif raw in ["fail", "failed", "broken", "falla", "error", "not_achieved"]:
		verdict = "fail"
	elif raw in ["explored", "explore"]:
		verdict = "explored"
	elif raw in ["blocked", "bloqueado", "inconclusive", "skipped", "cannot test"]:
		verdict = "blocked"
	if verdict.is_empty():
		return {}
	return {
		"verdict": verdict,
		"summary": _first_string(item, ["summary", "reason", "detail", "description"]).left(MAX_TEXT),
		"evidence": _strings(_first_value(item, ["evidence", "observations", "notes"])),
		"repro": _strings(_first_value(item, ["repro", "steps", "reproduce", "steps_to_reproduce"])),
		"kind": _first_string(item, ["kind", "type"]).to_lower(),
		"visual": item.get("visual") == true,
		"alerts": _strings(item.get("alerts")),
		"notes": _strings(item.get("notes")) if item.has("evidence") or item.has("observations") else PackedStringArray(),
		"stale_notes": _strings(item.get("stale_notes")),
	}


static func _strings(value: Variant) -> PackedStringArray:
	var result: PackedStringArray = []
	if value is String and not (value as String).strip_edges().is_empty():
		result.append((value as String).strip_edges().left(MAX_TEXT))
	elif value is Array:
		for item: Variant in value:
			var text := str(int(item)) if item is float and is_equal_approx(item, roundf(item)) else str(item)
			if (item is String or item is float or item is int) and not text.strip_edges().is_empty():
				result.append(text.strip_edges().left(MAX_TEXT))
	return result


## El código de un bloque es un bloque `findings` legible (para plegarlo en el chat, m12-38).
static func is_findings_block(code: String) -> bool:
	if not code.contains("\"findings\"") and not code.contains("\"line\""):
		return false
	var parsed: Variant = _parse_lenient(code)
	if parsed is Dictionary:
		return (parsed as Dictionary).get("findings") is Array
	return parsed is Array and not parsed.is_empty() and parsed[0] is Dictionary and (parsed[0] as Dictionary).has("line")


## Puntaje de un criterio: {criterion, score (0–10), reason}.
static func normalize_score(item: Variant) -> Dictionary:
	if not item is Dictionary:
		return {}
	var criterion := _first_string(item, ["criterion", "criterio", "id", "name", "label"])
	var value: Variant = _first_value(item, ["score", "puntaje", "value", "nota"])
	if criterion.is_empty() or not (value is float or value is int or (value is String and (value as String).is_valid_float())):
		return {}
	return {"criterion": criterion, "score": clampf(float(value), 0.0, 10.0), "reason": _first_string(item, ["reason", "razón", "razon", "detail", "evidence", "notes"]).left(MAX_TEXT)}


static func normalize_finding(item: Variant, project_root: String = "") -> Dictionary:
	if not item is Dictionary:
		return {}
	var path := _first_string(item, ["path", "file", "archivo", "filename", "location"])
	var line := _to_int(_first_value(item, ["line", "línea", "linea", "line_number", "lineNumber"]))
	var location := RegEx.create_from_string("^(.*?):(\\d+)(?::\\d+)?$").search(path)
	if location:
		path = location.get_string(1)
		if line <= 0:
			line = int(location.get_string(2))
	path = to_res_path(path, project_root)
	var body := _first_string(item, ["body", "description", "descripción", "descripcion", "detail", "details", "message", "explanation"])
	var title := _first_string(item, ["title", "título", "titulo", "summary", "name", "issue"])
	if title.is_empty():
		title = body.get_slice("\n", 0).left(120)
	var node := _first_string(item, ["node", "nodo"])
	# Un hallazgo de playtest puede no tener archivo: está en un nodo del juego (m15-18).
	if (path.is_empty() and node.is_empty()) or title.is_empty():
		return {}
	var finding := {
		"path": path,
		"line": maxi(line, 0),
		"severity": normalize_severity(_first_string(item, ["severity", "severidad", "kind", "type", "category", "level"])),
		"title": title.left(MAX_TEXT),
		"body": body.left(MAX_TEXT),
		"suggestion": _first_string(item, ["suggestion", "sugerencia", "fix", "suggested_fix", "suggestedFix", "replacement", "code"]).left(MAX_TEXT),
	}
	if not node.is_empty():
		finding["node"] = node
	return finding


## Check del One-shot (spec §10): {label, status: pass|fail|pending, detail}.
static func normalize_check(item: Variant) -> Dictionary:
	if item is String:
		return {"label": item, "status": "pending", "detail": ""} if not (item as String).strip_edges().is_empty() else {}
	if not item is Dictionary:
		return {}
	var label := _first_string(item, ["label", "title", "name", "text", "check", "description"])
	if label.is_empty():
		return {}
	var value: Variant = _first_value(item, ["status", "ok", "passed", "pass", "result", "done"])
	var status := "pending"
	if value is bool:
		status = "pass" if value else "fail"
	elif value is float or value is int:
		status = "pass" if value != 0 else "fail"
	elif value is String:
		var text := (value as String).strip_edges().to_lower()
		if text in ["pass", "passed", "ok", "true", "yes", "sí", "si", "done", "✓", "success"]:
			status = "pass"
		elif text in ["fail", "failed", "false", "no", "error", "✗", "ko"]:
			status = "fail"
	return {"label": label.left(MAX_TEXT), "status": status, "detail": _first_string(item, ["detail", "details", "body", "note", "evidence"]).left(MAX_TEXT)}


static func normalize_severity(value: String) -> String:
	var key := value.strip_edges().to_lower()
	return SEVERITY_ALIASES.get(key, "style")


## Ruta del agente → res:// (relativa al proyecto, absoluta dentro del proyecto o file://).
static func to_res_path(path: String, project_root: String = "") -> String:
	var clean := path.strip_edges().trim_prefix("file://").replace("\\", "/")
	if clean.is_empty() or clean.begins_with("res://"):
		return clean
	var root := project_root.trim_suffix("/")
	if not root.is_empty() and clean.begins_with(root + "/"):
		return "res://" + clean.substr(root.length() + 1)
	if clean.is_absolute_path():
		return clean  # fuera del proyecto: se deja como está
	return "res://" + clean.trim_prefix("./")


## Objetos y listas JSON que pueden ser bloques de hallazgos: primero los fences, después cualquier
## `{…}` balanceado que mencione "findings" o "checks".
static func _json_candidates(text: String) -> Array:
	var candidates: Array = []
	var fence := RegEx.create_from_string("```[a-zA-Z]*[ \\t]*\\n([\\s\\S]*?)```")
	var outside := text
	for match_result: RegExMatch in fence.search_all(text):
		var parsed: Variant = _parse_lenient(match_result.get_string(1))
		if parsed != null:
			candidates.append(parsed)
			outside = outside.replace(match_result.get_string(0), "")
	var start := 0
	while true:
		var brace := outside.find("{", start)
		if brace < 0:
			break
		var end := _matching_brace(outside, brace)
		if end < 0:
			break
		var chunk := outside.substr(brace, end - brace + 1)
		if chunk.contains("\"findings\"") or chunk.contains("\"checks\"") or chunk.contains("\"scores\"") or chunk.contains("\"playtest\""):
			var parsed: Variant = _parse_lenient(chunk)
			if parsed != null:
				candidates.append(parsed)
				start = end + 1
				continue
		start = brace + 1
	return candidates


static func _parse_lenient(source: String) -> Variant:
	var text := source.strip_edges()
	var json := JSON.new()
	if json.parse(text) == OK:
		return json.data
	var without_trailing_commas := RegEx.create_from_string(",(\\s*[}\\]])").sub(text, "$1", true)
	if json.parse(without_trailing_commas) == OK:
		return json.data
	return null


## Índice del `}` que cierra el `{` de `from`, respetando strings JSON; -1 si no cierra.
static func _matching_brace(text: String, from: int) -> int:
	var depth := 0
	var in_string := false
	var escaped := false
	for i in range(from, text.length()):
		var c := text[i]
		if in_string:
			if escaped:
				escaped = false
			elif c == "\\":
				escaped = true
			elif c == "\"":
				in_string = false
		elif c == "\"":
			in_string = true
		elif c == "{":
			depth += 1
		elif c == "}":
			depth -= 1
			if depth == 0:
				return i
	return -1


static func _first_value(item: Dictionary, keys: Array) -> Variant:
	for key: String in keys:
		if item.has(key) and item[key] != null:
			return item[key]
	return null


static func _first_string(item: Dictionary, keys: Array) -> String:
	var value: Variant = _first_value(item, keys)
	if value == null:
		return ""
	return (value if value is String else JSON.stringify(value) if value is Dictionary or value is Array else str(value)).strip_edges()


static func _to_int(value: Variant) -> int:
	if value is int:
		return value
	if value is float:
		return int(value)
	if value is String and value.strip_edges().is_valid_int():
		return int(value)
	return 0
