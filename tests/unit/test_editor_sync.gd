extends "test_case.gd"
## EditorSync.replace_buffer: reemplazo mínimo, deshacible, conservando el cursor.

const EditorSync := preload("res://addons/godot_agent/editor/editor_sync.gd")

const BASE := "extends Node\n\nvar a := 1\nvar b := 2\n\nfunc _ready() -> void:\n\tpass\n"


func _check(old_text: String, new_text: String, label: String) -> CodeEdit:
	var code_edit := CodeEdit.new()
	code_edit.text = old_text
	code_edit.clear_undo_history()
	EditorSync.replace_buffer(code_edit, new_text)
	assert_eq(code_edit.text, new_text, label)
	code_edit.undo()
	assert_eq(code_edit.text, old_text, label + " (undo en un paso)")
	code_edit.free()
	return null


func test_replace_cases() -> void:
	_check(BASE, BASE.replace("var b := 2", "var b := 3"), "cambio de una línea")
	_check(BASE, BASE.replace("var a := 1\n", ""), "borrado en el medio")
	_check(BASE, BASE.replace("\tpass\n", "\tprint(a)\n\tprint(b)\n"), "más líneas")
	_check(BASE, "signal x\n" + BASE, "inserción al principio")
	_check(BASE, BASE + "func extra() -> void:\n\tpass\n", "inserción al final")
	_check(BASE, BASE.replace("var a := 1\nvar b := 2\n", "var a := 1\nvar c := 0\nvar b := 2\n"), "inserción en el medio")
	_check("a\nb\nc", "a\nb", "borrado de la última línea")
	_check("a\nb\nc", "b\nc", "borrado de la primera línea")
	_check("a", "", "vaciar")
	_check("", "hola\nmundo", "llenar")


func test_caret_moves_with_changes_above() -> void:
	var code_edit := CodeEdit.new()
	code_edit.text = BASE
	code_edit.set_caret_line(6)
	code_edit.set_caret_column(2)
	EditorSync.replace_buffer(code_edit, "signal x\nsignal y\n" + BASE)
	assert_eq(code_edit.get_caret_line(), 8, "el cursor baja 2 líneas")
	assert_eq(code_edit.get_caret_column(), 2, "misma columna")
	code_edit.free()
