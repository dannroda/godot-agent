extends "test_case.gd"
## Tarjeta de permiso (m12-10): el orden de los botones no depende del agente.

const PermissionView := preload("res://addons/godot_agent/ui/dock/entries/permission_view.gd")


func test_sorted_options() -> void:
	var options := [
		{"optionId": "a", "kind": "allow_always"},
		{"optionId": "x", "kind": "something_else"},
		{"optionId": "r", "kind": "reject_once"},
		{"optionId": "o", "kind": "allow_once"},
		"no es un diccionario",
	]
	var ids := PermissionView.sorted_options(options).map(func(option: Dictionary) -> String: return option.optionId)
	assert_eq(ids, ["o", "r", "a", "x"], "permitir, denegar, siempre; lo desconocido al final")
