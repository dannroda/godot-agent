extends "test_case.gd"
## Revisión vigente (spec §9.4, D23): ingesta del turno, descartar, alcance, prompts y CLAUDE.md.

const ReviewStore := preload("res://addons/godot_agent/review/review_store.gd")

const TURN := "Revisé src/.\n```json\n{\"findings\": [\n {\"path\": \"src/player.gd\", \"line\": 20, \"severity\": \"perf\", \"title\": \"get_node en _process\", \"body\": \"Cada frame.\", \"suggestion\": \"@onready var sprite := $Sprite\"},\n {\"path\": \"src/player.gd\", \"line\": 8, \"severity\": \"bug\", \"title\": \"Sin delta\", \"body\": \"Depende de los FPS.\", \"suggestion\": \"position += velocity * delta\"},\n {\"path\": \"src/ui/hud.gd\", \"line\": 3, \"severity\": \"order\", \"title\": \"Lee antes de _ready\", \"body\": \"\", \"suggestion\": \"\"}\n]}\n```"


func _store() -> ReviewStore:
	var store := ReviewStore.new()
	store.ingest_turn_text(TURN)
	return store


func test_ingest() -> void:
	var store := ReviewStore.new()
	var changes: Array[int] = [0]
	store.changed.connect(func() -> void: changes[0] += 1)
	assert_false(store.ingest_turn_text("Te explico el código, sin bloque."), "sin bloque no toca nada")
	assert_true(store.ingest_turn_text(TURN), "con bloque")
	assert_eq(store.findings.size(), 3, "tres hallazgos")
	assert_eq(store.findings[0].line, 8, "ordenados por archivo y línea")
	assert_eq(changes[0], 1, "una señal por revisión")
	assert_eq(store.counts(), {"bug": 1, "order": 1, "perf": 1, "style": 0}, "contadores")
	assert_eq(store.for_path("res://src/player.gd").size(), 2, "por archivo")
	assert_eq(store.scope_label(), "src/", "carpeta común")
	assert_true(store.ingest_turn_text("```json\n{\"findings\": []}\n```"), "revisión limpia")
	assert_eq(store.findings.size(), 0, "reemplaza la anterior")
	assert_false(store.ingest_turn_text("El campo \"findings\" va en el bloque."), "mención suelta no borra")


func test_dismiss_and_ids() -> void:
	var store := _store()
	var id := int(store.findings[1].id)
	assert_eq(store.get_finding(id).title, "get_node en _process", "busca por id")
	store.dismiss(id)
	assert_eq(store.findings.size(), 2, "descartado")
	assert_true(store.get_finding(id).is_empty(), "ya no está")
	store.ingest_turn_text(TURN)
	assert_true(int(store.findings[0].id) > id, "ids nuevos en cada revisión")


func test_prompts_and_export() -> void:
	var store := _store()
	var fix := ReviewStore.fix_prompt(store.findings)
	assert_true(fix.contains("src/player.gd:8 [bug] Sin delta — Depende de los FPS."), "prompt de arreglo")
	assert_true(fix.contains("Sugerencia: position += velocity * delta"), "con la sugerencia")
	assert_true(ReviewStore.question_prompt(store.findings[0]).contains("No modifiques nada"), "pregunta de solo lectura")
	var section := ReviewStore.claude_md_section(store.findings, "2026-10-21")
	assert_true(section.begins_with("## Convenciones de la revisión del agente (2026-10-21)"), "título")
	assert_true(section.contains("- Sin delta (ej.: `src/player.gd:8`): `position += velocity * delta`"), "línea de convención")
	assert_true(section.find("### Bug") < section.find("### Orden de ejecución"), "agrupado por severidad")
	var path := temp_dir("review_store") + "/CLAUDE.md"
	assert_eq(ReviewStore.append_to_claude_md("## A", path), "", "crea")
	assert_eq(ReviewStore.append_to_claude_md("## B\n", path), "", "agrega")
	assert_eq(FileAccess.get_file_as_string(path), "## A\n\n## B\n", "separado por una línea en blanco")
