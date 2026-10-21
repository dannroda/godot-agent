extends "test_case.gd"
## Partes puras de run_scene (spec §6): validación de inputs y Output nuevo del panel.

const RunTools := preload("res://addons/godot_agent/mcp/tools/run_tools.gd")


func test_validate_inputs() -> void:
	var steps: Array = []
	assert_eq(RunTools._validate_inputs([{"t": 0.5, "action": "ui_accept"}, {"t": -1, "action": "ui_cancel", "pressed": false}], steps), "", "pasos válidos")
	assert_eq(steps, [{"t": 0.5, "action": "ui_accept", "pressed": true}, {"t": 0.0, "action": "ui_cancel", "pressed": false}], "normaliza pressed y t negativo")
	assert_eq(RunTools._validate_inputs(null, []), "", "sin inputs")
	assert_true(RunTools._validate_inputs("ui_accept", []).contains("lista"), "no es lista")
	assert_true(RunTools._validate_inputs([{"action": "ui_accept"}], []).contains("`t`"), "falta t")
	assert_true(RunTools._validate_inputs([{"t": 0, "action": "no_existe"}], []).contains("no_existe"), "acción inexistente")


func test_output_delta() -> void:
	assert_eq(RunTools._output_delta("a\nb\n", "a\nb\nc\n\nd"), "c\nd", "solo lo nuevo, sin líneas vacías")
	assert_eq(RunTools._output_delta("viejo\n", "nuevo"), "nuevo", "panel limpiado al correr: todo")
	var many: PackedStringArray = []
	for i in RunTools.OUTPUT_LINE_LIMIT + 5:
		many.append("l%d" % i)
	var delta := RunTools._output_delta("", "\n".join(many))
	assert_true(delta.begins_with("(… 5 líneas anteriores)"), "recorta y avisa")
	assert_true(delta.ends_with("l%d" % (RunTools.OUTPUT_LINE_LIMIT + 4)), "conserva las últimas")
