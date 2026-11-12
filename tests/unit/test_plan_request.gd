extends "test_case.gd"
## «Planificar» y /plan (m11-58): el pedido del plan según el agente tenga modo plan o no, el bloque
## ```plan que se vuelve la tarjeta del plan al terminar un turno de plan, y lo que sale al aprobar,
## editar o seguir planeando (sin pedido ACP que contestar).

const AgentLog := preload("res://addons/godot_agent/core/agent_log.gd")
const SessionController := preload("res://addons/godot_agent/session/session_controller.gd")
const SessionModel := preload("res://addons/godot_agent/session/session_model.gd")
const ChatEntry := preload("res://addons/godot_agent/session/chat_entry.gd")
const PermissionRequest := preload("res://addons/godot_agent/session/permission_request.gd")
const PlanApproval := preload("res://addons/godot_agent/session/plan_approval.gd")
const HarnessPrompts := preload("res://addons/godot_agent/session/harness_prompts.gd")
const AgentDock := preload("res://addons/godot_agent/ui/dock/agent_dock.gd")
const PlanApprovalView := preload("res://addons/godot_agent/ui/dock/entries/plan_approval_view.gd")

const M := SessionModel.HarnessMode
const PLAN := "# Plan: Coin counter\n\n## Criteria\n- WHEN the player touches a coin, THE GAME SHALL add one to the counter.\n\n## Tasks\n1. Add `coins` to player.gd.\n2. Show it in the HUD.\n"


func _project_dir(name: String) -> String:
	var dir := ProjectSettings.globalize_path("user://").path_join("plan_request_%s_%d" % [name, Time.get_ticks_usec()])
	DirAccess.make_dir_recursive_absolute(dir)
	return dir


## Controller listo en `mode`, con un agente sin modo plan (modos `modes`); `sent` junta lo que sale.
func _controller(mode: SessionModel.HarnessMode, sent: Array, project_dir: String = "/tmp/project", modes: Array = []) -> SessionController:
	var controller := SessionController.new()
	controller.setup(SessionModel.new(), AgentLog.new(), project_dir)
	controller.model.set_harness_mode(mode)
	controller.model.session_id = "session-0001"
	controller.model.agent_modes = modes
	controller.model.set_state(SessionModel.SessionState.READY)
	controller.client.setup(func(line: String) -> bool:
		sent.append(JSON.parse_string(line))
		return true, controller.agent_log)
	return controller


## Un turno de plan que terminó: el mensaje del agente con `text` y la tarjeta si trae un bloque.
func _plan_turn(controller: SessionController, text: String) -> ChatEntry:
	var first := controller.model.entries().size()
	controller.model.apply_update({"sessionUpdate": "agent_message_chunk", "content": {"type": "text", "text": text}})
	controller._offer_block_plan(first)
	return controller.model.entries()[first]


static func _prompts(sent: Array) -> Array:
	var texts: Array = []
	for message: Variant in sent:
		if message is Dictionary and message.get("method") == "session/prompt":
			for block: Variant in message.params.prompt:
				texts.append(str(block.get("text", "")))
	return texts


## Cierra el session/prompt que quedó esperando (no hay agente que conteste) para no dejar el
## controller vivo en una corrutina.
func _end_turns(controller: SessionController) -> void:
	await _frames()
	controller.client.fail_all_pending("end of test")
	await _frames()


func _frames(n: int = 2) -> void:
	for i: int in n:
		await Engine.get_main_loop().process_frame


func test_plan_block_parsing() -> void:
	assert_eq(PlanApproval.plan_block("Here it is.\n\n```plan\n%s```\n" % PLAN), PLAN.strip_edges(), "el contenido del bloque")
	assert_eq(PlanApproval.plan_block("```plan\nold\n```\nthen\n```plan\nnew one\n```"), "new one", "el último bloque")
	assert_eq(PlanApproval.plan_block("```gdscript\nvar coins := 0\n```"), "", "otro lenguaje no")
	assert_eq(PlanApproval.plan_block("```plan\n# Plan: cut in the middle"), "", "un bloque sin cerrar no cuenta")
	assert_eq(PlanApproval.plan_block("```plantuml\nA -> B\n```"), "", "plantuml no es plan")
	assert_eq(PlanApproval.plan_block("text\r\n```plan\r\n1. one\r\n```\r\n"), "1. one", "con CRLF")


func test_request_prompt_depends_on_plan_mode() -> void:
	var with_mode := PlanApproval.request_prompt("  add a coin counter ", true)
	var without := PlanApproval.request_prompt("add a coin counter", false)
	for text: String in [with_mode, without]:
		assert_true(text.contains("don't change any file yet: add a coin counter\n"), "el pedido, sin espacios de más")
		assert_true(text.contains("WHEN the player touches an enemy, THE GAME SHALL"), "criterios jugables")
		assert_true(text.contains("signals, autoloads, input map actions and collision layers"), "diseño en términos de Godot")
		assert_true(text.contains("Numbered tasks"), "tareas numeradas")
		assert_true(text.contains("`# Plan: <short title>`"), "un título, para el nombre del archivo")
	assert_true(with_mode.contains("ExitPlanMode") and not with_mode.contains("```plan"), "con modo plan: su herramienta, sin bloque")
	assert_true(without.contains("```plan") and not without.contains("ExitPlanMode"), "sin modo plan: el bloque, sin ExitPlanMode")


func test_agent_has_plan_mode() -> void:
	assert_false(_controller(M.BUILD, []).agent_has_plan_mode(), "sin modos")
	assert_false(_controller(M.BUILD, [], "/tmp/project", [{"id": "default"}, {"id": "yolo"}]).agent_has_plan_mode(), "sin un modo plan")
	assert_true(_controller(M.BUILD, [], "/tmp/project", [{"id": "default"}, {"id": "plan"}]).agent_has_plan_mode(), "Claude Code")


func test_plan_command() -> void:
	assert_true(AgentDock.is_plan_command("/plan add a coin counter"), "con pedido")
	assert_true(AgentDock.is_plan_command("  /plan  "), "sin pedido")
	assert_false(AgentDock.is_plan_command("/planner x"), "otro comando")
	assert_false(AgentDock.is_plan_command("make a /plan"), "no al principio")
	assert_eq(AgentDock.plan_command_request("/plan  add a coin counter \n"), "add a coin counter", "el pedido")


func test_block_becomes_the_plan_card() -> void:
	var controller := _controller(M.ASK, [])
	var entry := _plan_turn(controller, "I read player.gd.\n\n```plan\n%s```" % PLAN)
	assert_true(entry.plan_folded, "el mensaje muestra el bloque como una línea")
	assert_eq(controller.model.pending_permissions.size(), 1, "una tarjeta")
	var request: PermissionRequest = controller.model.pending_permissions[0]
	assert_true(request.is_plan() and request.from_block, "la tarjeta del plan, propia del harness")
	assert_eq(request.plan_text, PLAN.strip_edges(), "con el plan")
	assert_eq(request.options.map(func(o: Dictionary) -> String: return o.kind), ["allow_once", "reject_once"], "aprobar y rechazar")
	var last: ChatEntry = controller.model.entries()[-1]
	assert_eq(last.kind, ChatEntry.EntryKind.PERMISSION, "la tarjeta va debajo del mensaje")
	controller.model.cancel_pending_permissions()  # como al cerrar la sesión: la tarjeta pendiente retiene al controller


func test_no_block_or_exit_plan_mode_card_means_no_block_card() -> void:
	var controller := _controller(M.ASK, [])
	var entry := _plan_turn(controller, "I need to know which scene has the HUD before planning.")
	assert_false(entry.plan_folded, "sin bloque")
	assert_eq(controller.model.pending_permissions.size(), 0, "sin tarjeta")
	# Con la tarjeta de ExitPlanMode en el turno, un bloque de más no arma otra.
	var first := controller.model.entries().size()
	controller.model.apply_update({"sessionUpdate": "tool_call", "toolCallId": "p1", "title": "Approve Plan", "kind": "switch_mode", "status": "pending"})
	controller.model.mark_plan_card("p1")
	controller.model.apply_update({"sessionUpdate": "agent_message_chunk", "content": {"type": "text", "text": "```plan\n%s```" % PLAN}})
	controller._offer_block_plan(first)
	assert_eq(controller.model.pending_permissions.size(), 0, "el plan ya está en la tarjeta de ExitPlanMode")


func test_approve_builds_with_the_saved_plan() -> void:
	var sent: Array = []
	var dir := _project_dir("approve")
	# Un agente con modos pero sin "plan": en Construir ya está en default, así que no hace falta set_mode.
	var controller := _controller(M.ASK, sent, dir, [{"id": "default"}, {"id": "readonly"}])
	controller.model.current_agent_mode = "default"
	var feedback: Array = []
	controller.reject_feedback.connect(func(text: String) -> void: feedback.append(text))
	_plan_turn(controller, "```plan\n%s```" % PLAN)
	var request: PermissionRequest = controller.model.pending_permissions[0]
	var path := controller.approve_plan(request)
	assert_true(request.was_allowed() and request.plan_approved, "la tarjeta queda aprobada")
	assert_eq(controller.model.harness_mode, M.BUILD, "pasa a Construir")
	assert_true(path.begins_with(dir.path_join(".godot_agent/plans/")) and path.ends_with("-coin-counter.md"), "guardado (%s)" % path)
	await _frames()
	var prompts := _prompts(sent)
	var approved := prompts.filter(func(t: String) -> bool: return t.begins_with("I approved your plan."))
	assert_eq(approved.size(), 1, "sale el pedido de construirlo (%s)" % [prompts])
	assert_true(str(approved[0]).contains("`.godot_agent/plans/%s`" % path.get_file()), "con la ruta relativa del plan")
	assert_eq(controller.model.entries().filter(func(e: ChatEntry) -> bool: return e.harness_label == HarnessPrompts.PLAN_APPROVED).size(), 1, "como prompt del harness")
	assert_eq(feedback.size(), 0, "aprobar no manda devolución")
	await _end_turns(controller)


func test_edit_and_keep_planning_send_right_away() -> void:
	var controller := _controller(M.ASK, [])
	var feedback: Array = []
	controller.reject_feedback.connect(func(text: String) -> void: feedback.append(text))
	_plan_turn(controller, "```plan\n%s```" % PLAN)
	var request: PermissionRequest = controller.model.pending_permissions[0]
	request.submit_edited_plan(request.plan_text.replace("Show it in the HUD.", "Show it in the HUD, top right."))
	assert_eq(feedback.size(), 1, "lo editado sale enseguida (el turno ya terminó)")
	assert_true(feedback[0].contains("+ 2. Show it in the HUD, top right."), "con el diff")
	assert_true(feedback[0].contains("```plan block") and not feedback[0].contains("ExitPlanMode"), "pide de nuevo el bloque")
	assert_eq(controller.prompt_label(feedback[0]), HarnessPrompts.PLAN_EDIT, "etiqueta")
	assert_eq(controller.model.harness_mode, M.ASK, "sigue en Preguntar")
	_plan_turn(controller, "```plan\n%s```" % PLAN)
	controller.model.pending_permissions[0].deny_with_reason("use a CanvasLayer for the HUD")
	assert_eq(feedback.size(), 2, "el motivo también")
	assert_true(feedback[1].ends_with("What to change: use a CanvasLayer for the HUD") and feedback[1].contains("```plan block"), feedback[1])
	assert_eq(controller.prompt_label(feedback[1]), HarnessPrompts.PLAN_KEEP_PLANNING, "etiqueta")


func test_another_message_cancels_the_pending_card() -> void:
	var sent: Array = []
	var controller := _controller(M.ASK, sent, _project_dir("cancel"))
	var feedback: Array = []
	controller.reject_feedback.connect(func(text: String) -> void: feedback.append(text))
	_plan_turn(controller, "```plan\n%s```" % PLAN)
	var request: PermissionRequest = controller.model.pending_permissions[0]
	controller.send_prompt("actually, forget the coins")
	assert_false(request.is_pending(), "la tarjeta ya no está pendiente")
	assert_eq(request.outcome, {"outcome": "cancelled"}, "cancelada")
	assert_eq(feedback.size(), 0, "no manda nada")
	assert_eq(controller.approve_plan(request), "", "ya no se puede aprobar")
	await _end_turns(controller)


func test_plan_turn_labels() -> void:
	for label: String in [HarnessPrompts.PLAN_REQUEST, HarnessPrompts.PLAN_EDIT, HarnessPrompts.PLAN_KEEP_PLANNING]:
		assert_true(label in SessionController.PLAN_TURN_LABELS, label)
	assert_false(HarnessPrompts.PLAN_APPROVED in SessionController.PLAN_TURN_LABELS, "el turno de construir no busca planes")


## m18-05: Antigravity construye el plan aprobado sin mandar su lista de tareas (ACP plan). Al
## terminar el turno de construir sin ella, la tarjeta dice que no hay seguimiento; con ella, no.
func test_build_without_task_list_says_progress_not_tracked() -> void:
	var sent: Array = []
	var controller := _controller(M.ASK, sent, _project_dir("progress_none"), [{"id": "default"}])
	controller.model.current_agent_mode = "default"
	_plan_turn(controller, "```plan\n%s```" % PLAN)
	var request: PermissionRequest = controller.model.pending_permissions[0]
	var changes: Array[int] = []
	request.changed.connect(func() -> void: changes.append(1))
	controller.approve_plan(request)
	assert_eq(request.plan_progress, PermissionRequest.PLAN_PROGRESS_WAITING, "mira el avance desde que se aprueba")
	assert_false(PlanApprovalView.result_text(request).contains("not tracked"), "mientras construye no dice nada")
	controller.model.turn_finished.emit("cancelled")
	assert_eq(request.plan_progress, PermissionRequest.PLAN_PROGRESS_WAITING, "un turno cancelado no cuenta")
	changes.clear()
	controller.model.turn_finished.emit("end_turn")
	assert_eq(request.plan_progress, PermissionRequest.PLAN_PROGRESS_NONE, "terminó sin lista de tareas")
	assert_eq(changes.size(), 1, "la tarjeta se refresca")
	assert_true(PlanApprovalView.result_text(request).contains("Progress not tracked"), "y lo dice")
	# Ya no mira: un plan que llega después no lo cambia.
	controller.model.apply_update({"sessionUpdate": "plan", "entries": [{"content": "Add coins", "status": "completed", "priority": "medium"}]})
	assert_eq(request.plan_progress, PermissionRequest.PLAN_PROGRESS_NONE, "deja de mirar")
	await _end_turns(controller)


func test_build_with_task_list_is_tracked_by_the_agent() -> void:
	var controller := _controller(M.ASK, [], _project_dir("progress_agent"), [{"id": "default"}])
	controller.model.current_agent_mode = "default"
	_plan_turn(controller, "```plan\n%s```" % PLAN)
	var request: PermissionRequest = controller.model.pending_permissions[0]
	controller.approve_plan(request)
	controller.model.apply_update({"sessionUpdate": "plan", "entries": [{"content": "Add coins", "status": "in_progress", "priority": "medium"}]})
	assert_eq(request.plan_progress, PermissionRequest.PLAN_PROGRESS_AGENT, "la lista del agente lleva el avance")
	controller.model.turn_finished.emit("end_turn")
	assert_eq(request.plan_progress, PermissionRequest.PLAN_PROGRESS_AGENT, "el fin del turno no lo cambia")
	assert_false(PlanApprovalView.result_text(request).contains("not tracked"), "sin aviso")
	await _end_turns(controller)
