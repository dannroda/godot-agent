extends "test_case.gd"
## Formularios y enlaces del agente (`elicitation/create` y `elicitation/complete`, m11-17).

const ElicitationRequest := preload("res://addons/godot_agent/session/elicitation_request.gd")
const ElicitationView := preload("res://addons/godot_agent/ui/dock/entries/elicitation_view.gd")
const SessionModel := preload("res://addons/godot_agent/session/session_model.gd")
const SessionController := preload("res://addons/godot_agent/session/session_controller.gd")
const ChatEntry := preload("res://addons/godot_agent/session/chat_entry.gd")
const AgentLog := preload("res://addons/godot_agent/core/agent_log.gd")
const MarkdownBBCode := preload("res://addons/godot_agent/ui/markdown/markdown_bbcode.gd")


func test_elicitation_request_schema_and_validation() -> void:
	var req := ElicitationRequest.from_params({
		"mode": "form",
		"message": "Choose the export options:",
		"elicitationId": "el_1",
		"requestedSchema": {
			"type": "object",
			"required": ["name", "tags"],
			"properties": {
				"name": {"type": "string", "title": "Project Name", "minLength": 2},
				"debug": {"type": "boolean", "default": true},
				"target": {"type": "string", "oneOf": [{"const": "linux", "title": "Linux"}, {"const": "web", "title": "Web"}]},
				"tags": {"type": "array", "minItems": 1, "items": {"type": "string", "enum": ["2d", "3d", "vr"]}},
			},
		},
	})
	assert_eq(req.mode, ElicitationRequest.MODE_FORM, "modo form")
	assert_eq(req.elicitation_id, "el_1", "elicitationId")
	assert_eq(req.field_names(), PackedStringArray(["name", "debug", "target", "tags"]), "campos")
	assert_true(req.is_required("name"), "name requerido")
	assert_false(req.is_required("debug"), "debug opcional")
	assert_eq(req.validate({"name": "", "tags": ["2d"]}), "Project Name", "string vacío falla minLength/required")
	assert_eq(req.validate({"name": "a", "tags": ["2d"]}), "Project Name", "string de 1 char falla minLength 2")
	assert_eq(req.validate({"name": "ok", "tags": []}), "tags", "array vacío falla minItems/required")
	assert_eq(req.validate({"name": "ok", "tags": ["2d"]}), "", "válido")
	var choices := ElicitationRequest.enum_choices(req.field_schema("target"))
	assert_eq(choices.size(), 2, "dos opciones oneOf")
	assert_eq(choices[0], {"value": "linux", "label": "Linux", "description": ""}, "primera opción")
	req.accept({"name": "ok", "debug": false, "target": "web", "tags": ["2d"]})
	assert_false(req.is_pending(), "resuelto")
	assert_eq(req.response, {
		"action": "accept",
		"content": {"name": "ok", "debug": false, "target": "web", "tags": ["2d"]},
	}, "respuesta accept con content")


func test_elicitation_view_builds_and_collects_values() -> void:
	var req := ElicitationRequest.from_params({
		"mode": "form",
		"message": "Configure build:",
		"requestedSchema": {
			"type": "object",
			"required": ["title"],
			"properties": {
				"title": {"type": "string", "default": "Demo"},
				"fullscreen": {"type": "boolean", "default": true},
				"count": {"type": "integer", "default": 3, "minimum": 1, "maximum": 10},
				"platform": {"type": "string", "enum": ["linux", "windows"], "default": "windows"},
				"features": {"type": "array", "items": {"enum": ["audio", "net"]}, "default": ["net"]},
			},
		},
	})
	var entry := ChatEntry.new()
	entry.id = 1
	entry.kind = ChatEntry.EntryKind.ELICITATION
	entry.elicitation = req
	var view := ElicitationView.new()
	view.setup(entry, Color.CORNFLOWER_BLUE, MarkdownBBCode.new())
	view._ready()
	var values := view.collect_values()
	assert_eq(values.get("title"), "Demo", "default string")
	assert_eq(values.get("fullscreen"), true, "default boolean")
	assert_eq(values.get("count"), 3, "default integer")
	assert_eq(values.get("platform"), "windows", "default enum")
	assert_eq(values.get("features"), ["net"], "default multi-select")
	view.free()


func test_controller_handles_create_complete_and_cancel() -> void:
	var model := SessionModel.new()
	var controller := SessionController.new()
	var sent: Array[Dictionary] = []
	controller.setup(model, AgentLog.new(), "/tmp")
	controller.client.setup(func(line: String) -> bool:
		sent.append(JSON.parse_string(line))
		return true
	)
	var caps := controller.client_capabilities()
	assert_eq(caps.get("elicitation"), {"form": {}, "url": {}}, "declara capacidades form y url")

	# 1. URL elicitation que se completa con elicitation/complete
	controller.client.receive_line(JSON.stringify({
		"jsonrpc": "2.0",
		"id": 41,
		"method": "elicitation/create",
		"params": {
			"mode": "url",
			"elicitationId": "oauth_99",
			"message": "Complete OAuth in your browser",
			"url": "https://example.com/auth",
		},
	}))
	assert_eq(model.pending_elicitations.size(), 1, "elicitation en espera")
	var url_req: ElicitationRequest = model.pending_elicitations[0]
	assert_eq(url_req.url, "https://example.com/auth", "url guardada")
	controller.client.receive_line(JSON.stringify({
		"jsonrpc": "2.0",
		"method": "elicitation/complete",
		"params": {"elicitationId": "oauth_99"},
	}))
	assert_true(url_req.completed_by_agent, "marcado como completado por el agente")
	assert_eq(model.pending_elicitations.size(), 0, "ya no está pendiente")
	# La respuesta sale un frame después: lo que sigue a un pedido resuelto no corre dentro de quien
	# lo resolvió (m13-02).
	await (Engine.get_main_loop() as SceneTree).process_frame
	assert_eq(sent.back().get("result"), {"action": "cancel"}, "responde cancel: el usuario no aceptó desde acá")

	# 2. Form elicitation retirada con $/cancel_request
	controller.client.receive_line(JSON.stringify({
		"jsonrpc": "2.0",
		"id": 42,
		"method": "elicitation/create",
		"params": {
			"mode": "form",
			"message": "Pick a name",
			"requestedSchema": {"type": "object", "properties": {"name": {"type": "string"}}},
		},
	}))
	assert_eq(model.pending_elicitations.size(), 1, "segundo elicitation pendiente")
	var form_req: ElicitationRequest = model.pending_elicitations[0]
	controller.client.receive_line(JSON.stringify({
		"jsonrpc": "2.0",
		"method": "$/cancel_request",
		"params": {"requestId": 42},
	}))
	assert_true(form_req.withdrawn, "marcado como retirado por $/cancel_request")
	assert_eq(model.pending_elicitations.size(), 0, "ya no queda pendiente")
	assert_eq(sent.back().get("result"), {"action": "cancel"}, "responde action cancel")


## Un enlace que no es http(s) se rechaza (abriría un archivo local), y los mínimos que llegan por
## JSON (floats) se validan igual.
func test_rejects_local_links_and_json_numbers() -> void:
	var bad := ElicitationRequest.from_params({"mode": "url", "elicitationId": "e", "url": "file:///tmp/run.sh"})
	assert_false(bad.invalid_reason().is_empty(), "file:// rechazado")
	assert_false(ElicitationRequest.from_params({"mode": "url", "elicitationId": "e", "url": "run.sh"}).invalid_reason().is_empty(), "ruta relativa rechazada")
	assert_false(ElicitationRequest.from_params({"mode": "url", "url": "https://example.com"}).invalid_reason().is_empty(), "sin elicitationId")
	assert_false(ElicitationRequest.from_params({"mode": "raw"}).invalid_reason().is_empty(), "modo desconocido")
	assert_eq(ElicitationRequest.from_params({"mode": "url", "elicitationId": "e", "url": "https://example.com/ok"}).invalid_reason(), "", "https aceptado")
	var form: Variant = ElicitationRequest.from_params(JSON.parse_string('{"mode":"form","requestedSchema":{"type":"object","properties":{"name":{"type":"string","minLength":3},"tags":{"type":"array","minItems":2}}}}'))
	assert_eq(form.validate({"name": "ab"}), "name", "minLength desde JSON")
	assert_eq(form.validate({"name": "abc", "tags": ["x"]}), "tags", "minItems desde JSON")
	assert_eq(form.validate({"name": "abc", "tags": ["x", "y"]}), "", "válido")


func test_controller_rejects_invalid_elicitation() -> void:
	var model := SessionModel.new()
	var controller := SessionController.new()
	controller.setup(model, AgentLog.new(), "/tmp")
	var response: Variant = await controller._on_create_elicitation({"mode": "url", "elicitationId": "e", "url": "file:///etc/passwd"})
	assert_true(response is Object and not response.ok, "responde error sin mostrar la tarjeta")
	assert_eq(model.entries().size(), 0, "no hay tarjeta")


## Un booleano o un número opcional sin default que el usuario no tocó no se manda.
func test_untouched_optional_fields_are_left_out() -> void:
	var req := ElicitationRequest.from_params({"mode": "form", "requestedSchema": {"type": "object", "properties": {
		"verbose": {"type": "boolean"}, "port": {"type": "integer"}, "ratio": {"type": "number", "minimum": 0.005}}}})
	var entry := ChatEntry.new()
	entry.id = 1
	entry.kind = ChatEntry.EntryKind.ELICITATION
	entry.elicitation = req
	var view := ElicitationView.new()
	view.setup(entry, Color.CORNFLOWER_BLUE, MarkdownBBCode.new())
	(Engine.get_main_loop() as SceneTree).root.add_child(view)  # Range solo avisa cambios en el árbol
	# Desde _initialize el árbol todavía no corre: sin un frame, _ready no llega y no hay campos.
	await (Engine.get_main_loop() as SceneTree).process_frame
	assert_eq(view.collect_values(), {}, "nada que el usuario no eligió")
	var spins := view.find_children("*", "SpinBox", true, false)
	assert_eq(spins.size(), 2, "un SpinBox para port y otro para ratio")
	if spins.size() < 2:
		view.queue_free()
		return
	(spins[1] as SpinBox).value = 0.0125
	assert_eq(view.collect_values(), {"ratio": 0.0125}, "number sin redondear a 0.01")
	view.queue_free()


## m12-40: el tool call de la pregunta (AskUserQuestion) no se repite en el grupo de herramientas.
func test_question_tool_call_leaves_the_tool_group() -> void:
	var model := SessionModel.new()
	model.apply_update({"sessionUpdate": "tool_call", "toolCallId": "read", "title": "Read main.gd", "status": "completed"})
	model.apply_update({"sessionUpdate": "tool_call", "toolCallId": "ask", "title": "Can I edit it?", "status": "in_progress"})
	model.add_elicitation(ElicitationRequest.from_params({"message": "Can I edit it?", "toolCallId": "ask"}))
	var group: ChatEntry = model.entries()[0]
	assert_eq(Array(group.tool_call_ids), ["read"], "por toolCallId: sale del grupo")
	model.apply_update({"sessionUpdate": "tool_call_update", "toolCallId": "ask", "status": "completed"})
	assert_eq(Array(group.tool_call_ids), ["read"], "y no vuelve al terminar")
	model.apply_update({"sessionUpdate": "tool_call", "toolCallId": "ask2", "title": "Which one?", "status": "in_progress"})
	model.add_elicitation(ElicitationRequest.from_params({"message": "Which one?"}))
	var kinds: Array = model.entries().map(func(entry: ChatEntry) -> int: return entry.kind)
	assert_false(kinds.slice(2).has(ChatEntry.EntryKind.TOOL_GROUP), "sin toolCallId, por título: el grupo que quedaba vacío se va")
	model.add_elicitation(ElicitationRequest.from_params({"message": "Unrelated"}))
	assert_eq(Array(group.tool_call_ids), ["read"], "una pregunta sin tool call no saca nada")
