extends "test_case.gd"
## Variantes en paralelo (m11-90): limpiar lo que propone el agente, el prompt de cada copia, la tool
## godot.propose_variants y el diálogo donde el usuario elige, edita y agrega.

const Variants := preload("res://addons/godot_agent/session/variants.gd")
const VariantsDialog := preload("res://addons/godot_agent/ui/variants_dialog.gd")
const SessionTools := preload("res://addons/godot_agent/mcp/tools/session_tools.gd")
const PermissionPolicy := preload("res://addons/godot_agent/session/permission_policy.gd")
const McpTool := preload("res://addons/godot_agent/mcp/mcp_tool.gd")


func test_clean_and_check() -> void:
	assert_eq(Variants.clean(["  Coyote time ", "", "coyote TIME", 3, "x".repeat(400)]), PackedStringArray(["Coyote time", "3", "x".repeat(Variants.TEXT_MAX)]), "sin vacías ni repetidas, cortadas")
	assert_true(Variants.check(" ", PackedStringArray(["a", "b"])).contains("`goal`"), "sin objetivo")
	assert_true(Variants.check("g", PackedStringArray(["a"])).contains("at least 2"), "una sola")
	assert_eq(Variants.check("g", PackedStringArray(["a", "b", "c", "d", "e", "f"])), "", "más de 4 vale: elige el usuario")
	assert_eq(Variants.tab_label(1, "Stronger gravity when falling down fast"), "V2 · Stronger gravity when f…", "pestaña corta")


func test_copy_prompt() -> void:
	var variants := PackedStringArray(["Coyote time", "Stronger gravity", "Variable height"])
	var prompt := Variants.copy_prompt("Better jump", variants, 1, 3)
	assert_true(prompt.contains("variant V2 of 3") and prompt.contains("Your variant: Stronger gravity"), "su variante")
	assert_true(prompt.contains("- V1: Coyote time") and prompt.contains("- V3: Variable height") and not prompt.contains("- V2"), "las otras, para no hacerlas")
	assert_true(Variants.copy_prompt("g", variants, 1, 3, "/p/.godot_agent/playtests/regressions", "/c/p").contains("--path /c/p --script res://addons/godot_agent/playtest/regression_cli.gd -- /p/.godot_agent/playtests/regressions"), "cómo correr el juez, con las del proyecto")
	assert_true(prompt.contains("3 saved regressions"), "el juez")
	assert_true(Variants.copy_prompt("g", variants, 0, 0).contains("no saved regressions"), "sin regresiones lo dice")


func test_tool() -> void:
	var tools := SessionTools.new()
	var calls: Array = []
	tools.caller = func() -> String: return "s2"
	tools.propose_variants = func(from: String, goal: String, variants: PackedStringArray) -> Dictionary:
		calls.append([from, goal, variants])
		return {"ok": true, "text": "opened"}
	var tool: McpTool
	for candidate: McpTool in tools.tools():
		if candidate.name == "propose_variants":
			tool = candidate
	assert_true(tool != null and tool.group == PermissionPolicy.GROUP_READ, "grupo read: el usuario decide en el diálogo")
	var ok: Dictionary = await tool.handler.call({"goal": " Jump ", "variants": ["a", "A", "b"]})
	assert_eq(calls, [["s2", "Jump", PackedStringArray(["a", "b"])]], "limpias antes del diálogo")
	assert_false(ok.get("isError", false), "abiertas")
	var bad: Dictionary = await tool.handler.call({"goal": "Jump", "variants": "a"})
	assert_true(bad.get("isError", false) and calls.size() == 1, "sin lista no abre el diálogo")


func test_dialog() -> void:
	var dialog := VariantsDialog.new()
	dialog.fill("Better jump", PackedStringArray(["a", "b", "c", "d", "e"]), 2)
	assert_eq(dialog.chosen(), PackedStringArray(["a", "b", "c"]), "las primeras 3 tildadas")
	assert_eq(dialog.get_ok_button().text, "Open 3 copies", "abre 3")
	(dialog.find_child("AddVariant", true, false) as Button).pressed.emit()
	assert_eq(dialog.chosen().size(), 3, "una nueva vacía no cuenta")
	var rows := dialog.find_children("*", "LineEdit", true, false)
	var added := rows[rows.size() - 1] as LineEdit
	added.text = "mine"
	added.text_changed.emit("mine")
	assert_eq(dialog.chosen(), PackedStringArray(["a", "b", "c", "mine"]), "la agregada, tildada")
	var boxes := dialog.find_children("*", "CheckBox", true, false)
	(boxes[3] as CheckBox).button_pressed = true
	assert_true(dialog.get_ok_button().disabled, "5 son demasiadas")
	(boxes[0] as CheckBox).button_pressed = false
	assert_false(dialog.get_ok_button().disabled, "4 de nuevo")
	var goal := dialog.find_child("Goal", true, false) as LineEdit
	goal.text = ""
	goal.text_changed.emit("")
	assert_true(dialog.get_ok_button().disabled, "sin objetivo no abre")
	dialog.free()


func test_judge_line() -> void:
	var t := func(text: String) -> String: return text
	var report := {"ok": false, "flaky": 1, "regressions": [
		{"passed": true, "measured": {"frame_ms_p95": 4.04, "nodes_max": 30}},
		{"passed": false, "flaky": true, "measured": {"frame_ms_p95": 8.21}},
		{"passed": true}]}
	assert_eq(Variants.judge_line({"ok": true, "report": report}, t), "2 of 3 regressions pass · 1 flaky · frame_ms_p95 8.2 · nodes_max 30", "pasan, inestables y el peor de cada métrica")
	assert_eq(Variants.judge_line({"ok": false, "error": "boom"}, t), "Could not judge it: boom", "sin juez")


## Un Godot headless de verdad sobre este proyecto con las regresiones de prueba que pasan.
func test_judge_runs_the_regressions() -> void:
	var report := temp_dir("variants_judge").path_join("report.json")
	var judged: Dictionary = await Variants.judge(ProjectSettings.globalize_path("res://"), ProjectSettings.globalize_path("res://tests/fixtures/regressions/pass"), report)
	assert_true(judged.ok, "corrió: %s" % judged.get("error", ""))
	assert_eq([judged.report.get("ok"), (judged.report.get("regressions", []) as Array).size()], [true, 2], "las 2 pasan")
	assert_eq(int(judged.report.regressions[0].runs), Variants.REPEAT, "cada una REPEAT veces")
	var missing: Dictionary = await Variants.judge(ProjectSettings.globalize_path("res://"), "/nowhere/regressions", report)
	assert_false(missing.ok, "sin regresiones no hay report")


func test_comparison_text() -> void:
	var t := func(text: String) -> String: return text
	var judged := {"ok": true, "report": {"ok": true, "flaky": 0, "regressions": [{"passed": true, "measured": {"draw_calls_max": 12}}]}}
	var text := Variants.comparison_text([
		{"label": "V1 · Coyote", "state": "judged", "judged": judged, "changed": 4},
		{"label": "V2 · Gravity", "state": "judging"},
		{"label": "V3 · Height", "state": "working"},
		{"label": "V4 · Dash", "state": "closed"}], t)
	assert_true(text.contains("• V1 · Coyote: 1 of 1 regressions pass · draw_calls_max 12 · 4 files changed"), "la juzgada, con métricas y archivos")
	assert_true(text.contains("• V2 · Gravity: judging…") and text.contains("• V3 · Height: working…") and text.contains("• V4 · Dash: closed"), "los otros estados")


## Restart and resume (m11-90): lo guardado pasa por JSON y vuelve con la pestaña nueva de quien propuso.
func test_saved_across_restart() -> void:
	var variant := {"run": "20261124-1200", "index": 2, "text": "Dash", "goal": "Move", "from": "s3", "turns": 1,
		"judging": true, "changed": PackedStringArray(["player.gd"]), "judged": {"ok": true, "report": {"ok": true}}}
	var saved: Variant = JSON.parse_string(JSON.stringify(Variants.to_saved(variant)))
	assert_false((saved as Dictionary).has("judging"), "«juzgando» no se guarda")
	var back := Variants.from_saved(saved, {"s3": "s7"})
	assert_eq([back.from, back.index, back.turns, back.changed], ["s7", 2, 1, PackedStringArray(["player.gd"])], "con la pestaña nueva, enteros y la lista de archivos")
	assert_eq(back.judged, {"ok": true, "report": {"ok": true}}, "el último juicio sigue")
	assert_eq(Variants.from_saved(saved, {}).from, "", "si la que propuso no volvió, sin comparación")
