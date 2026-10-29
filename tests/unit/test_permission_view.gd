extends "test_case.gd"
## Tarjeta de permiso (m12-10): el orden de los botones no depende del agente.

const PermissionView := preload("res://addons/godot_agent/ui/dock/entries/permission_view.gd")
const PermissionRequest := preload("res://addons/godot_agent/session/permission_request.gd")
const SessionModel := preload("res://addons/godot_agent/session/session_model.gd")
const ConversationView := preload("res://addons/godot_agent/ui/dock/conversation_view.gd")


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


## El pendiente va a la barra fija sobre el composer; resuelto, vuelve al chat en su orden.
func test_pending_permission_goes_to_the_sticky_slot() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var model := SessionModel.new()
	var conversation := ConversationView.new()
	conversation.setup(model, Color.ORANGE)
	var sticky := VBoxContainer.new()
	conversation.sticky_slot = sticky
	tree.root.add_child(conversation)
	tree.root.add_child(sticky)
	model.add_notice("antes")
	var first := _request()
	model.add_permission(first)
	model.add_notice("entre")
	var second := _request()
	model.add_permission(second)
	await tree.process_frame
	await tree.process_frame
	assert_eq(sticky.get_child_count(), 2, "los dos pendientes, en la barra")
	second.select("o")
	await tree.process_frame
	await tree.process_frame
	var list: VBoxContainer = conversation.get(&"_list")
	assert_eq(sticky.get_child_count(), 1, "el resuelto sale de la barra")
	assert_eq(list.get_child_count(), 4, "«Mostrar anteriores», dos avisos y el resuelto")
	assert_true(list.get_child(3) is PermissionView, "el segundo vuelve al final")
	first.select("o")
	await tree.process_frame
	await tree.process_frame
	assert_eq(sticky.get_child_count(), 0, "barra vacía")
	assert_true(list.get_child(2) is PermissionView, "el primero vuelve entre los avisos")
	conversation.free()
	sticky.free()


static func _request() -> PermissionRequest:
	var request := PermissionRequest.new()
	request.title = "Edit player.gd"
	request.options = [{"optionId": "o", "kind": PermissionRequest.KIND_ALLOW_ONCE}]
	return request
