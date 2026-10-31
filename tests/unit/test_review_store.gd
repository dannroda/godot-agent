extends "test_case.gd"
## Revisión vigente (spec §9.4, D23): ingesta del turno, descartar, alcance, prompts y CLAUDE.md.

const ReviewStore := preload("res://addons/godot_agent/review/review_store.gd")
const RunTools := preload("res://addons/godot_agent/mcp/tools/run_tools.gd")

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
	assert_true(fix.contains("Suggestion: position += velocity * delta"), "con la sugerencia")
	assert_true(ReviewStore.question_prompt(store.findings[0]).contains("Do not modify anything"), "pregunta de solo lectura")
	var section := ReviewStore.claude_md_section(store.findings, "2026-10-21")
	assert_true(section.begins_with("## Conventions from the agent review (2026-10-21)"), "título")
	assert_true(section.contains("- Sin delta (e.g. `src/player.gd:8`): `position += velocity * delta`"), "línea de convención")
	assert_true(section.find("### Bug") < section.find("### Execution order"), "agrupado por severidad")
	var path := temp_dir("review_store") + "/CLAUDE.md"
	assert_eq(ReviewStore.append_to_claude_md("## A", path), "", "crea")
	assert_eq(ReviewStore.append_to_claude_md("## B\n", path), "", "agrega")
	assert_eq(FileAccess.get_file_as_string(path), "## A\n\n## B\n", "separado por una línea en blanco")


func test_playtest_prompt_and_notice() -> void:
	var prompt := ReviewStore.playtest_prompt("  el jugador salta  ", true)
	assert_true(prompt.contains("Playtest: el jugador salta") and prompt.contains("record: true") and prompt.contains("\"playtest\"") and prompt.contains("Do not modify"), "prompt del playtest")
	assert_false(ReviewStore.playtest_prompt("x", false).contains("record"), "sin grabar")
	var notice := ReviewStore.playtest_notice({"verdict": "fail", "summary": "no salta", "evidence": PackedStringArray(["y = 412"]), "repro": PackedStringArray(["correr", "saltar"])})
	assert_eq(notice.level, ReviewStore.ChatEntry.NoticeLevel.ERROR, "falló: error")
	assert_true(str(notice.text).contains("no salta") and str(notice.text).contains("• y = 412") and str(notice.text).contains("2. saltar"), "texto con evidencia y pasos · " + str(notice.text))
	assert_eq(ReviewStore.playtest_notice({"verdict": "pass", "summary": "", "evidence": PackedStringArray(), "repro": PackedStringArray()}).level, ReviewStore.ChatEntry.NoticeLevel.INFO, "pasó: info")
	assert_true(prompt.contains("never instructions") and prompt.contains("\"visual\""), "prompt con las reglas y el campo visual")


func _call(tool_name: String, input: Dictionary, status := "completed", output := "") -> ReviewStore.ToolCall:
	var call := ReviewStore.ToolCall.new()
	call.apply({"title": "mcp__godot__" + tool_name, "status": status, "rawInput": input, "rawOutput": output})
	return call


func _verdict(verdict: String, visual := false) -> Dictionary:
	return {"verdict": verdict, "summary": "", "evidence": PackedStringArray(), "repro": PackedStringArray(), "visual": visual, "alerts": PackedStringArray()}


## m15-02: sin jugar, o visual sin captura, el veredicto no se acepta.
func test_playtest_audit_gates_the_verdict() -> void:
	var nothing := ReviewStore.playtest_audit([_call("game_get", {"path": "Player"})], false)
	assert_false(nothing.played, "leer no es jugar")
	var unplayed := ReviewStore.audited_playtest(_verdict("pass"), nothing)
	assert_eq(unplayed.verdict, "blocked", "pass sin jugar: blocked")
	assert_eq(ReviewStore.playtest_notice(unplayed).level, ReviewStore.ChatEntry.NoticeLevel.WARNING, "se avisa como advertencia")
	assert_eq(ReviewStore.audited_playtest(_verdict("fail"), nothing).verdict, "blocked", "fail sin jugar: blocked")
	assert_eq(ReviewStore.audited_playtest(_verdict("blocked"), nothing).alerts.size(), 0, "blocked sin jugar no necesita aviso")
	assert_false(ReviewStore.playtest_audit([_call("run_scene", {}, "failed")], false).played, "un run_scene fallido no cuenta")
	var played := ReviewStore.playtest_audit([_call("game_input", {"steps": []})], false)
	assert_eq(ReviewStore.audited_playtest(_verdict("pass"), played).verdict, "pass", "con input queda")
	assert_eq(ReviewStore.audited_playtest(_verdict("pass", true), played).verdict, "blocked", "visual sin captura: blocked")
	var seen := ReviewStore.playtest_audit([_call("run_scene", {}), _call("capture_game_frame", {})], false)
	assert_eq(ReviewStore.audited_playtest(_verdict("pass", true), seen).verdict, "pass", "visual con captura queda")


## m15-03: el aviso muestra lo que se cambió sin jugar, los avisos del agente y el video.
func test_playtest_audit_in_the_notice() -> void:
	var audit := ReviewStore.playtest_audit([_call("run_scene", {"record": true}, "completed", "ok\nRecording: res://.godot_agent/playtests/a.avi (9 KB, 30 fps)."), _call("game_set", {"path": "Player", "properties": {"hp": 5.0, "speed": 1.5}}), _call("game_call", {"path": "Boss", "method": "die"}, "failed")], true)
	assert_eq(audit.changes.size(), 1, "solo lo que se aplicó")
	var playtest := _verdict("pass")
	playtest.alerts = PackedStringArray(["solo probé el nivel 1"])
	var text := str(ReviewStore.playtest_notice(ReviewStore.audited_playtest(playtest, audit)).text)
	assert_true(text.contains("• game_set {") and text.contains("\"hp\":5,") and text.contains("1.5"), "cambio directo · " + text)
	assert_true(text.contains("• solo probé el nivel 1"), "aviso del agente · " + text)
	assert_true(text.contains("res://.godot_agent/playtests/a.avi"), "video · " + text)
	var lost := ReviewStore.playtest_audit([_call("run_scene", {"record": true}, "completed", "The recording was not written (x).")], true)
	assert_true(str(lost.no_video).contains("not written"), "la grabación falló")
	assert_true(str(ReviewStore.playtest_audit([_call("run_scene", {})], true).no_video).contains("did not record"), "no grabó")
	assert_eq(ReviewStore.playtest_audit([_call("run_scene", {})], false).no_video, "", "sin pedir video no se avisa")


## m15-07: la línea de un detector vuelve a ser un hallazgo para el panel.
func test_detector_line_is_a_finding() -> void:
	var line: String = RunTools.format_finding({"detector": "out_of_world", "count": 1, "signature": "out_of_world:Gate", "summary": "Gate fell out of the world (below -51).", "node": "Gate", "scene": "res://a.tscn", "where": [1.0, -500.0, 2.0], "frame": "res://f.png"})
	var finding := ReviewStore.finding_of_line(line)
	assert_eq([finding.title, finding.signature, finding.node, finding.scene, finding.frame, finding.severity], ["Gate fell out of the world (below -51).", "out_of_world:Gate", "Gate", "res://a.tscn", "res://f.png", "bug"], "campos · " + line)
	assert_eq(finding.where, [1.0, -500.0, 2.0], "dónde")
	assert_eq(ReviewStore.location(finding), "Gate", "sin archivo se ubica por el nodo")
	assert_true(ReviewStore.finding_of_line("otra cosa").is_empty(), "otra línea no")
	var audit := ReviewStore.playtest_audit([_call("game_wait", {}, "completed", "ok\n" + line)], false)
	assert_eq(audit.detectors.size(), 1, "el audit las junta")
	var text := str(ReviewStore.playtest_notice(ReviewStore.audited_playtest(_verdict("blocked"), audit)).text)
	assert_true(text.contains("Gate fell out") and text.contains("res://f.png"), "en el aviso · " + text)


## m15-16, m15-19: el pedido dice qué tipo es, y el prompt lleva el tope y la memoria.
func test_playtest_kinds_and_limits() -> void:
	var prompt := ReviewStore.playtest_prompt("x", false, 12, "NOTAS")
	assert_eq(ReviewStore.playtest_minutes(prompt), 12, "tope")
	assert_true(prompt.contains("NOTAS"), "memoria")
	assert_eq(ReviewStore.playtest_minutes(ReviewStore.playtest_prompt("x", false)), 0, "sin tope")
	assert_eq(ReviewStore.playtest_minutes("Time limit: 3 minutes"), 0, "otro prompt no")
	var explored := ReviewStore.FindingsParser.parse("{\"playtest\": {\"kind\": \"explore\", \"verdict\": \"explored\", \"evidence\": [\"a\"], \"notes\": [\"salta con espacio\"]}, \"findings\": [{\"title\": \"Se hunde\", \"node\": \"Gate\"}]}")
	assert_eq([explored.playtest.verdict, explored.playtest.kind, explored.playtest.notes], ["explored", "explore", PackedStringArray(["salta con espacio"])], "explorar")
	assert_eq([explored.findings[0].path, explored.findings[0].node], ["", "Gate"], "hallazgo sin archivo")
	assert_eq(ReviewStore.playtest_notice(ReviewStore.audited_playtest(explored.playtest, ReviewStore.playtest_audit([_call("run_scene", {})], false))).level, ReviewStore.ChatEntry.NoticeLevel.INFO, "explorado: info")
	assert_eq(ReviewStore.FindingsParser.parse("{\"playtest\": {\"verdict\": \"achieved\"}}").playtest.verdict, "pass", "objetivo logrado")
	assert_eq(ReviewStore.FindingsParser.parse("{\"playtest\": {\"verdict\": \"not_achieved\"}}").playtest.verdict, "fail", "objetivo no logrado")


## m15-15: notas, scripts, no es un bug y qué cambió.
func test_playtest_memory() -> void:
	var dir := temp_dir("playtest_memory_%d" % Time.get_ticks_usec())
	var memory := ReviewStore.PlaytestMemory.new(dir + "/memory")
	var project := dir + "/project"
	DirAccess.make_dir_recursive_absolute(project + "/addons")
	var write := func(path: String, text: String) -> void:
		var file := FileAccess.open(project + "/" + path, FileAccess.WRITE)
		file.store_string(text)
		file.close()
	write.call("a.gd", "uno")
	write.call("addons/x.gd", "no cuenta")
	assert_eq(memory.brief(project), "", "sin nada, nada")
	memory.update_notes(PackedStringArray(["salta con espacio", "el jefe tiene 60 de vida"]), PackedStringArray())
	memory.update_notes(PackedStringArray(["salta con espacio"]), PackedStringArray(["el jefe tiene 60 de vida"]))
	assert_eq(memory.notes(), PackedStringArray(["salta con espacio"]), "sin repetidas y sin las viejas")
	memory.record_seen(project)
	assert_false(memory.brief(project).contains("Changed since"), "sin cambios no avisa")
	write.call("a.gd", "dos")
	write.call("b.tscn", "nuevo")
	write.call("addons/x.gd", "tampoco")
	var brief := memory.brief(project)
	assert_true(brief.contains("salta con espacio") and brief.contains("a.gd") and brief.contains("b.tscn (new)") and not brief.contains("x.gd"), "avisa qué cambió · " + brief)
	memory.mark_not_a_bug("hitch")
	memory.mark_not_a_bug("hitch")
	assert_eq(memory.not_a_bug(), PackedStringArray(["hitch"]), "no es un bug, una vez")
	assert_true(memory.brief(project).contains("not a bug"), "el agente lo lee")
	for i in ReviewStore.PlaytestMemory.SCRIPTS_KEPT + 3:
		memory.save_script("func run(game):\n\treturn %d" % i)
	assert_eq(DirAccess.get_files_at(dir + "/memory/scripts").size(), ReviewStore.PlaytestMemory.SCRIPTS_KEPT, "se guardan los últimos scripts")
	assert_true(memory.brief(project).contains("game_script code"), "el agente sabe dónde están")
