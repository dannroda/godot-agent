extends "test_case.gd"
## Chat en línea en el Script Editor (m11-05): el prompt, la respuesta del agente y aplicarla.

const InlineEdit := preload("res://addons/godot_agent/editor/inline_edit.gd")


func test_extract_code() -> void:
	assert_eq(InlineEdit.extract_code("Sure:\n```gdscript\nfunc a() -> void:\n\tpass\n```\nDone."), "func a() -> void:\n\tpass", "el primer bloque, sin las cercas")
	assert_eq(InlineEdit.extract_code("```\nx = 1\n```"), "x = 1", "sin lenguaje")
	assert_eq(InlineEdit.extract_code("No code here."), "", "sin bloque")


func test_build_prompt() -> void:
	var replace := InlineEdit.build_prompt("res://player.gd", {"from_line": 4, "to_line": 6, "original": "var a := 1"}, "make it a constant")
	assert_true(replace.contains("res://player.gd, lines 5–7"), "archivo y líneas desde 1")
	assert_true(replace.contains("make it a constant") and replace.contains("```gdscript\nvar a := 1\n```"), "pedido y código seleccionado")
	var insert := InlineEdit.build_prompt("res://player.gd", {"from_line": 9, "to_line": 9, "original": ""}, "add a jump")
	assert_true(insert.contains("line 10 (insert at the cursor)") and not insert.contains("Selected code"), "sin selección, insertar")


func test_apply() -> void:
	var code_edit := CodeEdit.new()
	code_edit.text = "extends Node\nvar speed := 1\nvar jump := 2\n"
	code_edit.select(1, 0, 2, 13)
	var span := InlineEdit.selection_range(code_edit)
	assert_eq(span.original, "var speed := 1\nvar jump := 2", "lo seleccionado")
	assert_true(InlineEdit.apply(code_edit, span, "const SPEED := 1\nconst JUMP := 2"), "aplica")
	assert_eq(code_edit.text, "extends Node\nconst SPEED := 1\nconst JUMP := 2\n", "reemplazado")
	code_edit.undo()
	assert_eq(code_edit.text, "extends Node\nvar speed := 1\nvar jump := 2\n", "un solo paso de deshacer")
	code_edit.set_line(1, "var speed := 5")
	assert_false(InlineEdit.apply(code_edit, span, "const SPEED := 1"), "si el código cambió, no aplica")
	code_edit.deselect()
	code_edit.set_caret_line(3)
	code_edit.set_caret_column(0)
	var at_caret := InlineEdit.selection_range(code_edit)
	assert_true(InlineEdit.apply(code_edit, at_caret, "func _ready() -> void:\n\tpass"), "sin selección inserta en el caret")
	assert_true(code_edit.text.ends_with("func _ready() -> void:\n\tpass"), "insertado: %s" % code_edit.text)
	code_edit.free()
	var key := InputEventKey.new()
	key.keycode = KEY_I
	key.alt_pressed = true
	assert_true(InlineEdit.is_shortcut(key), "Alt+I")
	key.ctrl_pressed = true
	assert_false(InlineEdit.is_shortcut(key), "Ctrl+Alt+I no")


func test_where_label() -> void:
	assert_eq(InlineEdit.where_label({"from_line": 14, "to_line": 15}), "lines 15–16", "rango, desde 1")
	assert_eq(InlineEdit.where_label({"from_line": 14, "to_line": 14}), "line 15", "una línea")


## m12-08: mientras espera, el panel dice qué se pidió, a quién, y cuánto lleva.
func test_waiting_texts() -> void:
	var span := {"from_line": 14, "to_line": 15}
	assert_eq(InlineEdit.request_label("make it async", "Claude Code", span), "“make it async” · Claude Code · lines 15–16", "pedido, agente y líneas")
	assert_eq(InlineEdit.request_label("x", "", {"from_line": 2, "to_line": 2}), "“x” · line 3", "sin agente")
	assert_eq(InlineEdit.waiting_status(1, 4200), "⠙ Waiting for the agent's answer · 4 s", "indicador y segundos")
