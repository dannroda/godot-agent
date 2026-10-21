extends "test_case.gd"
## Diff por líneas.

const LineDiff := preload("res://addons/godot_agent/core/line_diff.gd")


func test_counts_and_first_line() -> void:
	var ops := LineDiff.diff("a\nb\nc\n", "a\nB\nc\nd\n")
	assert_eq(LineDiff.count(ops), {"added": 2, "removed": 1}, "conteo")
	assert_eq(LineDiff.first_changed_line(ops), 2, "primera línea cambiada")
	assert_eq(LineDiff.count(LineDiff.diff("", "x\ny")), {"added": 2, "removed": 0}, "archivo nuevo")
	assert_eq(LineDiff.count(LineDiff.diff("x\n", "x\n")), {"added": 0, "removed": 0}, "sin cambios")


func test_lcs_keeps_common_lines() -> void:
	var ops := LineDiff.diff("1\n2\n3\n4\n5", "1\n3\n4\nX\n5")
	var kinds: Array = ops.map(func(op: Dictionary) -> int: return op.kind)
	assert_eq(kinds, [0, 2, 0, 0, 1, 0], "LCS mínimo")
