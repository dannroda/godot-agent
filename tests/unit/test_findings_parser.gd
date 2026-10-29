extends "test_case.gd"
## Parser tolerante de hallazgos (spec §9.4) y checks (§10).

const FindingsParser := preload("res://addons/godot_agent/review/findings_parser.gd")


func test_fenced_block() -> void:
	var text := "Revisé los scripts.\n\n```json\n{\"findings\": [\n  {\"path\": \"res://src/player.gd\", \"line\": 12, \"severity\": \"bug\", \"title\": \"Velocidad sin delta\", \"body\": \"Se mueve distinto según los FPS.\", \"suggestion\": \"position += velocity * delta\"}\n]}\n```\n\nEso es todo."
	var result := FindingsParser.parse(text)
	assert_eq(result.findings.size(), 1, "un hallazgo")
	assert_eq(result.findings[0], {"path": "res://src/player.gd", "line": 12, "severity": "bug", "title": "Velocidad sin delta", "body": "Se mueve distinto según los FPS.", "suggestion": "position += velocity * delta"}, "campos completos")
	assert_eq(result.checks.size(), 0, "sin checks")


func test_raw_json_with_prose_and_braces() -> void:
	var text := "Uso {llaves} en el texto. {\"findings\": [{\"path\": \"src/hud.gd\", \"line\": \"7\", \"severity\": \"Rendimiento\", \"title\": \"get_node en _process\", \"body\": \"Cachealo con {@onready}\",}]} y nada más."
	var result := FindingsParser.parse(text)
	assert_eq(result.findings.size(), 1, "sin fence, con coma final y llaves en strings")
	assert_eq(result.findings[0].path, "res://src/hud.gd", "ruta relativa → res://")
	assert_eq(result.findings[0].line, 7, "línea como string")
	assert_eq(result.findings[0].severity, "perf", "severidad en castellano")
	assert_eq(result.findings[0].suggestion, "", "sugerencia faltante → vacía")


func test_alternate_fields() -> void:
	var finding := FindingsParser.normalize_finding({"file": "/home/u/juego/src/enemy.gd:33", "kind": "orden", "description": "Lee el nodo antes de _ready.\nDetalle.", "fix": "@onready"}, "/home/u/juego")
	assert_eq(finding.path, "res://src/enemy.gd", "absoluta dentro del proyecto")
	assert_eq(finding.line, 33, "línea desde path:línea")
	assert_eq(finding.severity, "order", "orden → order")
	assert_eq(finding.title, "Lee el nodo antes de _ready.", "título desde la primera línea del cuerpo")
	assert_eq(finding.suggestion, "@onready", "fix → suggestion")
	assert_true(FindingsParser.normalize_finding({"line": 3, "title": "sin ruta"}).is_empty(), "sin ruta se descarta")
	assert_true(FindingsParser.normalize_finding("texto").is_empty(), "no es objeto")
	assert_eq(FindingsParser.normalize_finding({"path": "a.gd", "title": "t", "line": -4}).line, 0, "línea negativa → 0")


func test_severities() -> void:
	assert_eq(FindingsParser.normalize_severity("ERROR"), "bug", "error")
	assert_eq(FindingsParser.normalize_severity(" performance "), "perf", "performance")
	assert_eq(FindingsParser.normalize_severity("estilo"), "style", "estilo")
	assert_eq(FindingsParser.normalize_severity("???"), "style", "desconocida → style")


func test_several_blocks_and_duplicates() -> void:
	var block := "```json\n{\"findings\": [{\"path\": \"a.gd\", \"line\": 1, \"title\": \"x\"}]}\n```"
	var text := block + "\nY otro:\n```\n{\"findings\": [{\"path\": \"b.gd\", \"line\": 2, \"title\": \"y\", \"severity\": \"nit\"}]}\n```\n" + block
	var result := FindingsParser.parse(text)
	assert_eq(result.findings.size(), 2, "dos bloques, sin duplicados")
	assert_eq(result.findings[1].severity, "style", "nit → style")
	assert_eq(FindingsParser.parse("```json\n{\"findings\": [ roto\n```").findings.size(), 0, "JSON roto no corta")
	assert_eq(FindingsParser.parse("Sin hallazgos.").findings.size(), 0, "texto sin bloque")


func test_checks() -> void:
	var text := "```json\n{\"checks\": [{\"label\": \"La escena corre\", \"status\": \"pass\"}, {\"name\": \"Sin errores\", \"status\": \"fail\", \"detail\": \"2 errores\"}, \"Captura revisada\", {\"title\": \"Puntaje\", \"ok\": true}, {\"ok\": true}]}\n```"
	var checks: Array = FindingsParser.parse(text).checks
	assert_eq(checks.size(), 4, "el que no tiene etiqueta se descarta")
	assert_eq(checks[0], {"label": "La escena corre", "status": "pass", "detail": ""}, "formato del spec")
	assert_eq(checks[1], {"label": "Sin errores", "status": "fail", "detail": "2 errores"}, "fail con detalle")
	assert_eq(checks[2].status, "pending", "string suelto: pendiente")
	assert_eq(checks[3].status, "pass", "ok bool")


## m12-38: qué bloques de código se pliegan en el chat.
func test_is_findings_block() -> void:
	assert_true(FindingsParser.is_findings_block("{\"findings\": [{\"path\": \"a.gd\", \"line\": 3, \"title\": \"x\"}]}"), "objeto con findings")
	assert_true(FindingsParser.is_findings_block("{\"findings\": [],}"), "vacío y con coma final")
	assert_true(FindingsParser.is_findings_block("[{\"path\": \"a.gd\", \"line\": 3}]"), "lista suelta de hallazgos")
	assert_false(FindingsParser.is_findings_block("{\"findings\": [{\"path\""), "a medio escribir (streaming)")
	assert_false(FindingsParser.is_findings_block("func _ready() -> void:\n\tpass"), "código común")
	assert_false(FindingsParser.is_findings_block("{\"checks\": []}"), "otro bloque")


## m14-03: el veredicto de un playtest, con alias y listas o texto suelto.
func test_playtest_verdict() -> void:
	var text := "Jugué el nivel.\n```json\n{\"playtest\": {\"verdict\": \"FAILED\", \"summary\": \"No llega a la segunda plataforma\", \"evidence\": [\"Player.position.y = 412 en el frame 90\", 3], \"steps\": \"Saltar en el borde\"}}\n```"
	var playtest: Dictionary = FindingsParser.parse(text).playtest
	assert_eq(playtest.verdict, "fail", "failed → fail")
	assert_eq(playtest.summary, "No llega a la segunda plataforma", "resumen")
	assert_eq(playtest.evidence, PackedStringArray(["Player.position.y = 412 en el frame 90", "3"]), "evidencia")
	assert_eq(playtest.repro, PackedStringArray(["Saltar en el borde"]), "pasos como texto suelto")
	assert_eq(FindingsParser.parse("{\"playtest\": {\"verdict\": \"maybe\"}}").playtest, {}, "sin veredicto reconocible no hay playtest")
	assert_eq(FindingsParser.parse("{\"findings\": []}").playtest, {}, "sin bloque")
	assert_eq(FindingsParser.parse("{\"playtest\": {\"result\": \"blocked\", \"reason\": \"no hay escena principal\"}}").playtest.verdict, "blocked", "result y blocked")
