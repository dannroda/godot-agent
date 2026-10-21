@tool
extends RefCounted
## Extrae del texto del agente los bloques `{"findings": […]}` (spec §9.4) y `{"checks": […]}`
## (One-shot, §10), de forma tolerante:
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


## `{findings: Array[Dictionary], checks: Array[Dictionary]}`.
## Finding: {path (res:// si se pudo), line (≥1, 0 = sin línea), severity, title, body, suggestion}.
## Check: {title, ok, detail}.
static func parse(text: String, project_root: String = "") -> Dictionary:
	var findings: Array[Dictionary] = []
	var checks: Array[Dictionary] = []
	var seen: Dictionary = {}
	for candidate: Variant in _json_candidates(text):
		var raw_findings: Variant = null
		var raw_checks: Variant = null
		if candidate is Dictionary:
			raw_findings = candidate.get("findings")
			raw_checks = candidate.get("checks")
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
	return {"findings": findings, "checks": checks}


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
	if path.is_empty() or title.is_empty():
		return {}
	return {
		"path": path,
		"line": maxi(line, 0),
		"severity": normalize_severity(_first_string(item, ["severity", "severidad", "kind", "type", "category", "level"])),
		"title": title.left(MAX_TEXT),
		"body": body.left(MAX_TEXT),
		"suggestion": _first_string(item, ["suggestion", "sugerencia", "fix", "suggested_fix", "suggestedFix", "replacement", "code"]).left(MAX_TEXT),
	}


static func normalize_check(item: Variant) -> Dictionary:
	if item is String:
		return {"title": item, "ok": false, "detail": ""}
	if not item is Dictionary:
		return {}
	var title := _first_string(item, ["title", "name", "text", "check", "description"])
	if title.is_empty():
		return {}
	var ok_value: Variant = _first_value(item, ["ok", "passed", "pass", "done", "status", "result"])
	var ok := false
	if ok_value is bool:
		ok = ok_value
	elif ok_value is String:
		ok = ok_value.to_lower() in ["ok", "pass", "passed", "done", "true", "yes", "sí", "si", "✓"]
	elif ok_value is float or ok_value is int:
		ok = ok_value != 0
	return {"title": title.left(MAX_TEXT), "ok": ok, "detail": _first_string(item, ["detail", "details", "body", "note", "evidence"]).left(MAX_TEXT)}


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
		if chunk.contains("\"findings\"") or chunk.contains("\"checks\""):
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
