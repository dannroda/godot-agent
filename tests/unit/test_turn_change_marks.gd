extends "test_case.gd"
## Las marcas de los trozos del último turno en el Script Editor (m11-66): dónde cae cada línea del
## final del turno en el texto actual del editor. El resto (gutter, ✓ y ✗) lo prueba turn-marks.

const TurnChangeMarks := preload("res://addons/godot_agent/editor/turn_change_marks.gd")


func test_line_mapping() -> void:
	var end_text := "a\nb\nc\nd\n"
	assert_eq(TurnChangeMarks.line_mapping(end_text, end_text), {1: 1, 2: 2, 3: 3, 4: 4}, "sin cambios, cada una en su lugar")
	var mapping := TurnChangeMarks.line_mapping(end_text, "# note\na\nb\nc\nd\n")
	assert_eq(mapping, {1: 2, 2: 3, 3: 4, 4: 5}, "una línea escrita arriba las baja")
	mapping = TurnChangeMarks.line_mapping(end_text, "a\nd\n")
	assert_eq(mapping, {1: 1, 4: 2}, "las que ya no están no tienen lugar")
	assert_eq(TurnChangeMarks.anchor_line(mapping, 2), 2, "una que ya no está cae debajo de la anterior que sigue")
	assert_eq(TurnChangeMarks.anchor_line(mapping, 3), 2)
	assert_eq(TurnChangeMarks.anchor_line({}, 3), 1, "sin nada antes, en la primera")
	mapping = TurnChangeMarks.line_mapping(end_text, "a\nB\nc\nd\n")
	assert_false(mapping.has(2), "una línea cambiada después no se marca")
	assert_eq(mapping.get(3), 3)
