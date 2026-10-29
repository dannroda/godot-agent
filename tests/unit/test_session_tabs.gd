extends "test_case.gd"
## Pestañas de sesión (m7-44): marcas y avisos de las sesiones que esperan al usuario.

const SessionTabs := preload("res://addons/godot_agent/ui/dock/session_tabs.gd")
const SessionModel := preload("res://addons/godot_agent/session/session_model.gd")
const PermissionRequest := preload("res://addons/godot_agent/session/permission_request.gd")


## m12-19: un toast por sesión mientras siga esperando; responder lo habilita de nuevo.
func test_one_toast_per_waiting_session() -> void:
	var tabs := SessionTabs.new()
	var model := SessionModel.new()
	tabs.add_session("s1", Control.new(), model, "Session 1")
	var first := PermissionRequest.new()
	model.add_permission(first)
	model.add_permission(PermissionRequest.new())
	assert_true(tabs.call(&"_claim_toast", "s1"), "el primer pedido avisa")
	assert_false(tabs.call(&"_claim_toast", "s1"), "el segundo, con el primero sin responder, no apila otro")
	first.cancel()
	assert_false(tabs.call(&"_claim_toast", "s1"), "todavía espera el segundo")
	model.cancel_pending_permissions()
	assert_true(tabs.call(&"_claim_toast", "s1"), "respondido todo, el próximo pedido avisa de nuevo")
	tabs.free()
