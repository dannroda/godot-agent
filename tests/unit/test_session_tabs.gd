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


## m12-45: la pestaña de una copia lleva un ícono (o «⎘» sin el tema del editor) y la rama en el
## tooltip, no un sufijo en el nombre.
func test_copy_tab_is_marked() -> void:
	var tabs := SessionTabs.new()
	tabs.add_session("s1", Control.new(), SessionModel.new(), "Session 1")
	tabs.add_session("s2", Control.new(), SessionModel.new(), "Session 2")
	tabs.set_copy("s2", "Works in a separate copy of the project · branch agent/copy-1")
	var bar: TabBar = tabs.get(&"_bar")
	assert_true(bar.get_tab_icon(1) != null or bar.get_tab_title(1).begins_with("⎘ "), "marcada · %s" % bar.get_tab_title(1))
	assert_true(bar.get_tab_title(1).ends_with("Session 2"), "el nombre entero, sin sufijo")
	assert_true(bar.get_tab_tooltip(1).contains("branch agent/copy-1"), "la rama en el tooltip · " + bar.get_tab_tooltip(1))
	assert_true(bar.get_tab_icon(0) == null and bar.get_tab_title(0) == "Session 1", "la otra no")
	tabs.remove_session("s2")
	assert_false(tabs.is_copy("s2"), "al cerrarla se olvida")
	tabs.free()
