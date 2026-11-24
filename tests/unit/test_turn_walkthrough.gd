extends "test_case.gd"
## Recorrer los cambios de un turno (m11-93): un trozo por paso, archivo por archivo, con los hallazgos
## de Revisar que caen en esas líneas, y Anterior / Siguiente.

const TurnChangesDialog := preload("res://addons/godot_agent/ui/turn_changes_dialog.gd")


func _hunk(index: int, new_start: int) -> Dictionary:
	return {"index": index, "state": "", "stale": false, "blocked": "", "hunk": {"index": index, "path": "a.gd", "at": "@@",
		"lines": PackedStringArray([" ctx", "-old", "+new"]), "old_start": new_start, "old_count": 2, "new_start": new_start, "new_count": 2}}


func _text(dialog: Node, name: String) -> String:
	var node := dialog.find_child(name, true, false)
	return str(node.get(&"text")) if node else ""


func test_walkthrough() -> void:
	var dialog := TurnChangesDialog.new()
	var requested: Array = []
	dialog.hunks_requested.connect(func(data: Dictionary, path: String) -> void:
		requested.append(path)
		var items: Array[Dictionary] = [_hunk(0, 4), _hunk(1, 20)]
		dialog.set_hunks(data, path, items))
	dialog.findings_for = func(path: String) -> Array:
		return [{"line": 5, "severity": "bug", "title": "Off by one"}, {"line": 21, "severity": "perf", "title": "Slow loop"}] if path == "res://a.gd" else []
	dialog.show_turn({"files": [{"path": "a.gd", "status": "M", "added": 2, "removed": 2}, {"path": "icon.png", "status": "A", "added": 0, "removed": 0}]})
	dialog.hide()
	(dialog.find_child("Walkthrough", true, false) as Button).pressed.emit()
	assert_eq(requested, ["a.gd"], "pide los trozos del primer archivo")
	assert_eq(_text(dialog, "GuideWhere"), "File 1 of 2 · change 1 of 2", "dónde está")
	assert_true(dialog.find_child("Hunk0", true, false) != null and dialog.find_child("Hunk1", true, false) == null, "un trozo por paso")
	var findings := dialog.find_children("Finding", "", true, false)
	assert_true(findings.size() == 1 and str(findings[0].get(&"text")).contains("Off by one"), "el hallazgo de sus líneas, no el otro")
	(dialog.find_child("Next", true, false) as Button).pressed.emit()
	assert_true(dialog.find_child("Hunk1", true, false) != null and str(dialog.find_children("Finding", "", true, false)[0].get(&"text")).contains("Slow loop"), "el segundo trozo con su hallazgo")
	(dialog.find_child("Next", true, false) as Button).pressed.emit()
	assert_eq(_text(dialog, "GuideWhere"), "File 2 of 2 · change 1 of 1", "un binario es un paso, sin trozos")
	assert_eq(_text(dialog, "Next"), "Done", "el último")
	(dialog.find_child("Previous", true, false) as Button).pressed.emit()
	assert_eq(_text(dialog, "GuideWhere"), "File 1 of 2 · change 2 of 2", "Anterior vuelve al último trozo del archivo de antes")
	(dialog.find_child("Next", true, false) as Button).pressed.emit()
	(dialog.find_child("Next", true, false) as Button).pressed.emit()
	assert_true(dialog.find_child("GuideWhere", true, false) == null and dialog.find_child("Walkthrough", true, false).visible, "al terminar vuelve a la lista")
	dialog.free()


func test_findings_in() -> void:
	var findings := [{"line": 3}, {"line": 7}, {"line": 9}]
	assert_eq(TurnChangesDialog.findings_in(findings, 7, 9).size(), 2, "dentro del rango")
	assert_eq(TurnChangesDialog.findings_in(findings, 7, 6).size(), 1, "un trozo que solo borra: su línea")
