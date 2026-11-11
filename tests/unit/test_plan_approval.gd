extends "test_case.gd"
## La tarjeta del plan (m11-22) con el pedido real de ExitPlanMode de claude-agent-acp 0.105
## (tests/fixtures/acp/exit_plan_mode_0105.json): se reconoce, ofrece solo aprobar y rechazar, no
## vence, y aprobar pasa a Construir sin session/set_mode antes de contestar. Lo editado y los
## motivos vuelven al agente como prompts del harness.

const AgentLog := preload("res://addons/godot_agent/core/agent_log.gd")
const SessionController := preload("res://addons/godot_agent/session/session_controller.gd")
const SessionModel := preload("res://addons/godot_agent/session/session_model.gd")
const PermissionRequest := preload("res://addons/godot_agent/session/permission_request.gd")
const PermissionPolicy := preload("res://addons/godot_agent/session/permission_policy.gd")
const PlanApproval := preload("res://addons/godot_agent/session/plan_approval.gd")
const PlanStore := preload("res://addons/godot_agent/session/plan_store.gd")
const HarnessPrompts := preload("res://addons/godot_agent/session/harness_prompts.gd")

const FIXTURE := "res://tests/fixtures/acp/exit_plan_mode_0105.json"
const M := SessionModel.HarnessMode


func _fixture() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(FIXTURE))


func _project_dir(name: String) -> String:
	var dir := ProjectSettings.globalize_path("user://").path_join("plan_test_%s_%d" % [name, Time.get_ticks_usec()])
	DirAccess.make_dir_recursive_absolute(dir)
	return dir


## Controller en `mode`, con el agente en "plan" y los modos de 0.105; `sent` junta lo que sale.
func _controller(mode: SessionModel.HarnessMode, sent: Array, project_dir: String = "/tmp/project") -> SessionController:
	var controller := SessionController.new()
	controller.setup(SessionModel.new(), AgentLog.new(), project_dir)
	controller.model.set_harness_mode(mode)
	controller.model.session_id = "session-0001"
	controller.model.agent_modes = [{"id": "default"}, {"id": "acceptEdits"}, {"id": "plan"}]
	controller.model.current_agent_mode = "plan"
	controller.client.setup(func(line: String) -> bool:
		sent.append(JSON.parse_string(line))
		return true, controller.agent_log)
	return controller


func _ask(controller: SessionController, params: Dictionary, results: Array) -> void:
	var run := func() -> void: results.append(await controller.permissions.on_request_permission(params))
	run.call()


static func _methods(sent: Array) -> Array:
	return sent.map(func(message: Variant) -> String: return str(message.get("method", "")) if message is Dictionary else "")


func _frames(n: int = 2) -> void:
	for i: int in n:
		await Engine.get_main_loop().process_frame


func test_detects_the_real_request() -> void:
	var fixture := _fixture()
	var tool_call: Dictionary = fixture.request.toolCall
	assert_true(PlanApproval.is_plan_request(tool_call), "ExitPlanMode de 0.105")
	assert_eq(PlanApproval.plan_text(tool_call), tool_call.rawInput.plan, "el plan sale de rawInput.plan")
	assert_true(PlanApproval.plan_text(tool_call).begins_with("# Plan: Jump with gravity"), "el texto entero")
	var by_kind := {"toolCallId": "x", "kind": "switch_mode", "content": tool_call.content}
	assert_true(PlanApproval.is_plan_request(by_kind), "sin name: switch_mode con plan en el contenido")
	assert_true(PlanApproval.is_plan_request({"toolCallId": "x", "_meta": {"claudeCode": {"toolName": "ExitPlanMode"}}}), "por el _meta de Claude Code")
	assert_true(PlanApproval.is_plan_request({"toolCallId": "x"}, "ExitPlanMode"), "por el ToolCall ya conocido")
	assert_false(PlanApproval.is_plan_request({"toolCallId": "x", "kind": "switch_mode", "title": "Switch mode"}), "switch_mode sin plan no es plan")
	assert_false(PlanApproval.is_plan_request({"toolCallId": "x", "kind": "edit", "title": "Write player.gd", "rawInput": {"file_path": "player.gd"}}), "una edición no")


func test_only_approve_and_reject_are_offered() -> void:
	var options := PlanApproval.filter_options(_fixture().request.options)
	assert_eq(options.map(func(o: Dictionary) -> String: return o.optionId), ["exit-plan-default", "reject"], "sin auto, bypass ni clear context")
	var other := PlanApproval.filter_options([
		{"optionId": "a", "kind": "allow_always"}, {"optionId": "b", "kind": "allow_once"}, {"optionId": "c", "kind": "reject_always"}])
	assert_eq(other.map(func(o: Dictionary) -> String: return o.optionId), ["b", "c"], "otros ids: la primera allow_once y, sin reject_once, reject_always")


func test_plan_card_in_ask_mode_and_approve_builds() -> void:
	var sent: Array = []
	var dir := _project_dir("approve")
	var controller := _controller(M.ASK, sent, dir)
	var results: Array = []
	_ask(controller, _fixture().request, results)
	assert_eq(results.size(), 0, "espera al usuario")
	assert_eq(controller.model.pending_permissions.size(), 1, "una tarjeta")
	var request: PermissionRequest = controller.model.pending_permissions[0]
	assert_true(request.is_plan(), "es la tarjeta del plan")
	var call = controller.model.tool_call(request.tool_call_id)
	assert_true(call != null and call.plan_card, "la fila de la tool sabe que el plan está en la tarjeta")
	assert_eq(request.plan_text, _fixture().request.toolCall.rawInput.plan, "con el plan")
	assert_eq(request.options.size(), 2, "aprobar y rechazar")
	assert_eq(PermissionPolicy.new().decide(PermissionPolicy.GROUP_EDIT_FILES, M.ASK), PermissionPolicy.DENY, "(en Preguntar las ediciones se deniegan)")
	var path := controller.approve_plan(request)
	assert_eq(controller.model.harness_mode, M.BUILD, "aprobar pasa a Construir")
	assert_false("session/set_mode" in _methods(sent), "sin set_mode: el adapter cambia de modo solo")
	await _frames()
	assert_eq(results.size(), 1, "contestado")
	assert_eq(results[0], {"outcome": {"outcome": "selected", "optionId": "exit-plan-default"}}, "con la opción default de 0.105")
	assert_ne_policy_deny(controller)
	assert_true(path.begins_with(dir.path_join(".godot_agent/plans/")), "guardado en .godot_agent/plans (%s)" % path)
	assert_true(path.get_file().ends_with("-jump-with-gravity-in-player-gd.md"), "con el slug del título (%s)" % path.get_file())
	var saved := FileAccess.get_file_as_string(path)
	assert_true(saved.begins_with("# Plan: Jump with gravity"), "el plan")
	assert_true(saved.contains("Approved: "), "y la fecha de aprobación")
	# Lo que sigue en la captura: el adapter pasa solo a default y el turno termina.
	controller.model.apply_update(_fixture().after_allow[0])
	assert_eq(controller.model.current_agent_mode, "default", "current_mode_update del adapter")
	controller.model.finish_turn("end_turn")
	await _frames()
	assert_false("session/set_mode" in _methods(sent), "agente y harness ya coinciden: tampoco al terminar")


func assert_ne_policy_deny(controller: SessionController) -> void:
	var decision := controller.policy.decide(PermissionPolicy.GROUP_EDIT_FILES, controller.model.harness_mode)
	assert_eq(decision, PermissionPolicy.ASK, "la primera edición pide permiso de Construir, no se deniega")


func test_agent_that_stays_in_plan_mode_is_synced_after_the_turn() -> void:
	var sent: Array = []
	var controller := _controller(M.REVIEW, sent, _project_dir("sync"))
	var results: Array = []
	_ask(controller, _fixture().request, results)
	controller.approve_plan(controller.model.pending_permissions[0])
	assert_eq(controller.model.harness_mode, M.BUILD, "en Revisar también pasa a Construir")
	assert_false("session/set_mode" in _methods(sent), "no antes de contestar")
	controller.model.finish_turn("end_turn")
	await _frames()
	assert_true("session/set_mode" in _methods(sent), "el agente siguió en plan: se lo sincroniza al terminar el turno")


func test_plan_card_asks_in_every_mode() -> void:
	for mode: SessionModel.HarnessMode in [M.BUILD, M.AUTO, M.ONESHOT]:
		var sent: Array = []
		var controller := _controller(mode, sent)
		var results: Array = []
		_ask(controller, _fixture().request, results)
		assert_eq(results.size(), 0, "modo %d: no se aprueba solo" % mode)
		assert_eq(controller.model.pending_permissions.size(), 1, "modo %d: la tarjeta" % mode)
		controller.model.cancel_pending_permissions()


func test_edit_rejects_and_queues_the_diff() -> void:
	var sent: Array = []
	var controller := _controller(M.ASK, sent)
	var feedback: Array = []
	controller.reject_feedback.connect(func(text: String) -> void: feedback.append(text))
	var results: Array = []
	_ask(controller, _fixture().request, results)
	var request: PermissionRequest = controller.model.pending_permissions[0]
	var edited := request.plan_text.replace("bound to Space", "bound to Space and the gamepad A button")
	request.submit_edited_plan(request.plan_text)
	assert_true(request.is_pending(), "sin cambios no se manda nada")
	request.submit_edited_plan(edited)
	await _frames()
	assert_eq(results[0], {"outcome": {"outcome": "selected", "optionId": "reject"}}, "rechaza (el turno termina cancelled)")
	assert_eq(controller.model.harness_mode, M.ASK, "sigue planeando en Preguntar")
	assert_eq(feedback.size(), 1, "una devolución para el agente")
	var text: String = feedback[0]
	assert_true(text.contains("+ 3. **Add a `jump` input action.** Add it in Project Settings → Input Map, bound to Space and the gamepad A button."), "la línea agregada")
	assert_true(text.contains("- 3. **Add a `jump` input action.** Add it in Project Settings → Input Map, bound to Space. "), "la quitada")
	assert_true(text.contains("ExitPlanMode"), "le pide volver a presentarlo")
	assert_true(text.ends_with(edited.strip_edges()), "con el plan entero")
	assert_eq(controller.prompt_label(text), HarnessPrompts.PLAN_EDIT, "sale como prompt del harness")
	assert_eq(PlanApproval.change_counts(request.plan_text, edited), {"added": 1, "removed": 1}, "+1 −1")


func test_keep_planning_with_a_reason() -> void:
	var controller := _controller(M.ASK, [])
	var feedback: Array = []
	controller.reject_feedback.connect(func(text: String) -> void: feedback.append(text))
	var results: Array = []
	_ask(controller, _fixture().request, results)
	var request: PermissionRequest = controller.model.pending_permissions[0]
	request.deny_with_reason("   ")
	assert_true(request.is_pending(), "sin motivo no rechaza")
	request.deny_with_reason("use ui_accept, no new input action")
	await _frames()
	assert_eq(results[0].outcome.optionId, "reject", "rechaza")
	assert_eq(feedback.size(), 1, "una devolución")
	assert_true(feedback[0].ends_with("What to change: use ui_accept, no new input action"), feedback[0])
	assert_eq(controller.prompt_label(feedback[0]), HarnessPrompts.PLAN_KEEP_PLANNING, "etiqueta")


func test_plain_reject_sends_nothing() -> void:
	var controller := _controller(M.ASK, [])
	var feedback: Array = []
	controller.reject_feedback.connect(func(text: String) -> void: feedback.append(text))
	var results: Array = []
	_ask(controller, _fixture().request, results)
	var request: PermissionRequest = controller.model.pending_permissions[0]
	request.select("reject")
	await _frames()
	assert_eq(results[0].outcome.optionId, "reject", "rechaza")
	assert_eq(feedback.size(), 0, "sin motivo no hay prompt")


func test_deny_with_reason_on_a_shell_card() -> void:
	var controller := _controller(M.BUILD, [])
	var feedback: Array = []
	controller.reject_feedback.connect(func(text: String) -> void: feedback.append(text))
	var results: Array = []
	_ask(controller, {"sessionId": "session-0001", "toolCall": {"toolCallId": "t1", "title": "git push origin main", "kind": "execute", "rawInput": {"command": "git push origin main"}},
		"options": [{"optionId": "allow", "name": "Allow", "kind": "allow_once"}, {"optionId": "deny", "name": "Deny", "kind": "reject_once"}]}, results)
	var request: PermissionRequest = controller.model.pending_permissions[0]
	assert_false(request.is_plan(), "tarjeta común")
	request.deny_with_reason("don't push yet, I review first")
	await _frames()
	assert_eq(results[0], {"outcome": {"outcome": "selected", "optionId": "deny"}}, "contesta reject_once")
	assert_eq(feedback.size(), 1, "el motivo va aparte")
	assert_true(feedback[0].contains("I review first"), feedback[0])
	assert_eq(controller.prompt_label(feedback[0]), HarnessPrompts.DENY_REASON, "etiqueta")


func test_plan_store_slug_and_no_overwrite() -> void:
	assert_eq(PlanStore.slug("# Plan: Jump with gravity in player.gd\n\nx"), "jump-with-gravity-in-player-gd", "del título, sin «Plan:»")
	assert_eq(PlanStore.slug("Just text, no heading"), "just-text-no-heading", "sin título, la primera línea")
	assert_eq(PlanStore.slug("# ¡¡!!"), "plan", "nada útil: «plan»")
	assert_eq(PlanStore.slug("# " + "a".repeat(80)).length(), PlanStore.SLUG_MAX, "acotado")
	var dir := _project_dir("store")
	var first := PlanStore.save_approved(dir, "# Plan: A\nbody", "2026-11-11")
	var second := PlanStore.save_approved(dir, "# Plan: A\nother", "2026-11-11")
	assert_eq(first.get_file(), "2026-11-11-a.md", "nombre")
	assert_eq(second.get_file(), "2026-11-11-a-2.md", "no pisa el anterior")
	assert_true(FileAccess.get_file_as_string(first).contains("body"), "el primero sigue")
	assert_eq(PlanStore.save_approved("", "x"), "", "sin proyecto no guarda")


## Historial viejo (sin tarjeta): la fila sigue mostrando el plan plegado; con tarjeta, una línea corta.
func test_tool_row_does_not_repeat_the_plan() -> void:
	var view_script := preload("res://addons/godot_agent/ui/dock/entries/tool_group_view.gd")
	var model := SessionModel.new()
	var update: Dictionary = _fixture().request.toolCall.duplicate(true)
	update["sessionUpdate"] = "tool_call"
	model.apply_update(update)
	var call = model.tool_call(update.toolCallId)
	assert_eq(view_script._summary(call), "switch_mode", "sin tarjeta, como siempre")
	model.mark_plan_card(update.toolCallId)
	assert_eq(view_script._short_name(call), "Plan presented", "con tarjeta: «Plan presentado»")
	assert_eq(view_script._summary(call), "waiting for you", "esperando")
	model.apply_update({"sessionUpdate": "tool_call_update", "toolCallId": update.toolCallId, "status": "completed"})
	assert_eq(view_script._summary(call), "approved", "y cómo terminó")
	var view = view_script.new()
	var extra := VBoxContainer.new()
	view.call(&"_refresh_extra", call, extra)
	assert_eq(extra.get_child_count(), 0, "sin el plan plegado debajo")
	extra.free()
	view.free()


func test_deny_with_reason_on_harness_cards() -> void:
	var controller := _controller(M.BUILD, [])
	var feedback: Array = []
	controller.reject_feedback.connect(func(text: String) -> void: feedback.append(text))
	var results: Array = []
	var run := func() -> void: results.append(await controller.permissions.authorize_fs_write("/tmp/project/player.gd", "a\n", "b\n"))
	run.call()
	(controller.model.pending_permissions[0] as PermissionRequest).deny_with_reason("not this file")
	await _frames()
	assert_eq(results, [false], "fs/write denegado")
	var run_shell := func() -> void: results.append(await controller.permissions.authorize_terminal_command("git push", "/tmp/project"))
	run_shell.call()
	(controller.model.pending_permissions[0] as PermissionRequest).deny_with_reason("no pushing")
	await _frames()
	assert_true(str(results[1]).begins_with("Permission denied"), "terminal denegado")
	assert_eq(feedback.size(), 2, "los dos motivos salen")
	assert_true(feedback[0].contains("not this file") and feedback[1].contains("no pushing"), str(feedback))
