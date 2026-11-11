extends "test_case.gd"
## La lista de hooks de Settings (m11-24): aprobación de lo que viene en el archivo, de lo que se edita,
## la explicación de auto_send y la validación.

const HooksEditor := preload("res://addons/godot_agent/ui/settings/hooks_editor.gd")
const ProjectHooks := preload("res://addons/godot_agent/core/project_hooks.gd")


func test_approval_auto_send_and_validate() -> void:
	var loaded := {"name": "Lint", "event": "saved", "command": "gdlint {path}"}
	var editor := HooksEditor.new()
	editor.load_from([loaded], func(_key: String) -> bool: return false, "/proj")
	var rows: Array = editor.get(&"_rows")
	var row: Dictionary = rows[0]
	assert_true((row.badge as Control).visible, "un hook del archivo sin aprobar lleva el aviso")
	assert_eq(editor.keys_to_approve(), PackedStringArray(), "guardar sin marcar «Allow» no lo aprueba")
	(row.allow as CheckBox).button_pressed = true
	assert_eq(editor.keys_to_approve().size(), 1, "con «Allow» sí")
	(row.allow as CheckBox).button_pressed = false
	(row.command as LineEdit).text = "gdlint --strict {path}"
	(row.command as LineEdit).text_changed.emit((row.command as LineEdit).text)
	assert_false((row.badge as Control).visible, "editado acá: sin aviso")
	assert_eq(editor.keys_to_approve(), PackedStringArray([ProjectHooks.approval_key("/proj", editor.hooks()[0])]), "y se aprueba al guardar, con la definición nueva")
	# Pasar a prompt: se ve el campo del prompt y no el del comando; auto_send explica al prenderlo.
	var action := row.action as OptionButton
	for i in action.item_count:
		if action.get_item_metadata(i) == ProjectHooks.ACTION_PROMPT:
			action.select(i)
			action.item_selected.emit(i)
	assert_true((row.prompt as Control).visible and not (row.command as Control).visible, "campos de la acción")
	assert_false((row.auto_send_hint as Control).visible, "auto_send apagado: sin explicación")
	assert_true(editor.validate().contains("write what to ask"), "un prompt vacío no se guarda · %s" % editor.validate())
	(row.prompt as LineEdit).text = "Review it."
	(row.auto_send as CheckBox).button_pressed = true
	assert_true((row.auto_send_hint as Control).visible and (row.auto_send_hint as Label).text.contains("spends tokens"), "al prenderlo, la explicación")
	assert_eq(editor.validate(), "", "válido")
	var saved: Dictionary = editor.hooks()[0]
	assert_eq([saved.action, saved.prompt, saved.auto_send], ["prompt", "Review it.", true], "lo que se guarda")
	editor.free()
