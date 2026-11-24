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
	assert_true(prompt.contains("3 saved regressions") and prompt.contains("don't edit"), "el juez y no tocarlo")
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
