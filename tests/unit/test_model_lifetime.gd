extends "test_case.gd"
## Un SessionModel con una tarjeta sin contestar se libera (m16-14): la conexión a `resolved` no
## puede capturar el pedido, la entrada ni el modelo, porque eso era un ciclo mientras el pedido
## seguía pendiente.

const SessionModel := preload("res://addons/godot_agent/session/session_model.gd")
const PermissionRequest := preload("res://addons/godot_agent/session/permission_request.gd")
const ElicitationRequest := preload("res://addons/godot_agent/session/elicitation_request.gd")


func test_model_with_pending_cards_is_freed() -> void:
	var model := SessionModel.new()
	var request := PermissionRequest.new()
	request.title = "Edit main.gd"
	request.options = PermissionRequest.default_options()
	model.add_permission(request)
	model.add_elicitation(ElicitationRequest.from_params({"message": "Which one?"}))
	assert_eq(model.pending_permissions.size(), 1, "permiso pendiente")
	assert_eq(model.pending_elicitations.size(), 1, "pregunta pendiente")
	var model_ref: WeakRef = weakref(model)
	var request_ref: WeakRef = weakref(request)
	model = null
	request = null
	assert_eq(model_ref.get_ref(), null, "el modelo se libera aunque haya tarjetas sin contestar")
	assert_eq(request_ref.get_ref(), null, "y el pedido también")


func test_resolved_card_leaves_pending_and_updates() -> void:
	var model := SessionModel.new()
	var request := PermissionRequest.new()
	request.options = PermissionRequest.default_options()
	var entry := model.add_permission(request)
	var updated: Array = []
	model.entry_updated.connect(func(e: Variant) -> void: updated.append(e))
	request.select("allow_once")
	assert_eq(model.pending_permissions.size(), 0, "sale de los pendientes")
	assert_true(updated.has(entry), "la tarjeta se actualiza")
	var question := ElicitationRequest.from_params({"message": "Which one?"})
	model.add_elicitation(question)
	model.cancel_pending_permissions()
	assert_eq(model.pending_elicitations.size(), 0, "cancelar vacía también las preguntas")
