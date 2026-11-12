extends "test_case.gd"
## godot.request_mode (m11-68): a qué modo se refiere el agente, cuándo el destino tiene más permisos,
## la tarjeta (siempre, también en Auto, sin «siempre»), el cambio al aceptar, One-shot denegado y la
## línea del system prompt.

const ProjectModes := preload("res://addons/godot_agent/core/project_modes.gd")
const SessionModel := preload("res://addons/godot_agent/session/session_model.gd")
const SessionController := preload("res://addons/godot_agent/session/session_controller.gd")
const PermissionRequest := preload("res://addons/godot_agent/session/permission_request.gd")
const PermissionPolicy := preload("res://addons/godot_agent/session/permission_policy.gd")
const ModeRequests := preload("res://addons/godot_agent/session/mode_requests.gd")
const AgentLog := preload("res://addons/godot_agent/core/agent_log.gd")
const SessionTools := preload("res://addons/godot_agent/mcp/tools/session_tools.gd")
const McpTool := preload("res://addons/godot_agent/mcp/mcp_tool.gd")

const M := SessionModel.HarnessMode
const PROJECT := "/tmp/project"


func _mode(name: String, base: String, extra: Dictionary = {}) -> Dictionary:
	var data := {"name": name, "base": base, "when_to_use": "When %s" % name.to_lower()}
	data.merge(extra, true)
	var parsed := ProjectModes.from_data(data, "res://agent_modes/%s.json" % name.to_lower())
	assert_eq(parsed.errors, PackedStringArray(), "el modo %s es válido" % name)
	return parsed.mode


func _modes() -> Array[Dictionary]:
	var modes: Array[Dictionary] = [
		_mode("Levels", "build", {"editable": ["res://levels/**"]}),
		_mode("Shaders", "build", {"editable": ["*.gdshader"], "shell": "deny"}),
		_mode("Docs", "auto"),
	]
	return modes


func _controller(base: int, layer: Dictionary = {}) -> SessionController:
	var controller := SessionController.new()
	controller.setup(SessionModel.new(), AgentLog.new(), PROJECT)
	controller.project_modes_provider = _modes
	if not layer.is_empty():
		controller.model.set_project_mode(layer)
	else:
		controller.model.set_harness_mode(base)
	return controller


func _wait() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	for i in 3:
		await tree.process_frame


func test_resolve() -> void:
	var modes := _modes()
	assert_eq(ModeRequests.resolve("build", modes).mode, M.BUILD, "un modo fijo")
	assert_eq(ModeRequests.resolve(" Auto ", modes).mode, M.AUTO, "sin mayúsculas ni espacios")
	var levels := ModeRequests.resolve("levels", modes)
	assert_eq([levels.mode, levels.project_mode.name], [M.BUILD, "Levels"], "un modo del proyecto, con su base")
	assert_eq(ModeRequests.resolve("Shaders", modes).project_mode.name, "Shaders", "por nombre")
	assert_true(str(ModeRequests.resolve("oneshot", modes).error).contains("One-shot is not a mode you can switch to"), "One-shot no se pide")
	var unknown := str(ModeRequests.resolve("planner", modes).error)
	assert_true(unknown.contains("no mode called «planner»") and unknown.contains("«Levels»") and unknown.contains("Review"), "uno que no está lista los que hay · %s" % unknown)
	assert_false(str(ModeRequests.resolve("", modes).error).is_empty(), "vacío")


func test_escalation() -> void:
	var modes := _modes()
	var levels: Dictionary = modes[0]
	var shaders: Dictionary = modes[1]
	var docs: Dictionary = modes[2]
	var cases := [
		[M.ASK, {}, M.BUILD, {}, true, "Preguntar → Construir"],
		[M.REVIEW, {}, M.ASK, {}, false, "Revisar → Preguntar"],
		[M.BUILD, {}, M.AUTO, {}, true, "Construir → Auto"],
		[M.AUTO, {}, M.BUILD, {}, false, "Auto → Construir"],
		[M.BUILD, {}, M.BUILD, levels, false, "Construir → Levels: limita más"],
		[M.BUILD, levels, M.BUILD, {}, true, "Levels → Construir: sin archivos limitados"],
		[M.BUILD, levels, M.ASK, {}, false, "Levels → Preguntar: no edita"],
		[M.BUILD, shaders, M.BUILD, levels, true, "Shaders (sin shell) → Levels: la shell pregunta"],
		[M.BUILD, levels, M.BUILD, shaders, false, "Levels → Shaders"],
		[M.ASK, {}, M.AUTO, docs, true, "Preguntar → Docs (Auto)"],
	]
	for case: Array in cases:
		assert_eq(ModeRequests.escalates(case[0], case[1], case[2], case[3]), case[4], case[5])
	assert_eq(ModeRequests.escalation_reasons(M.BUILD, levels, M.AUTO, {}), PackedStringArray(["edits without asking", "isn't limited to some files", "runs allowed shell commands without asking"]), "los motivos")


func test_card_in_auto_and_switch() -> void:
	var controller := _controller(M.AUTO)
	var model := controller.model
	var results: Array = []
	var ask := func() -> void: results.append(await controller.request_mode("levels", "The user wants the next room built.", 0))
	ask.call()
	assert_eq(model.pending_permissions.size(), 1, "sale la tarjeta también en Auto")
	var request: PermissionRequest = model.pending_permissions[0]
	assert_eq(request.title, "Switch to Levels (Build)", "el título dice adónde")
	assert_true(request.option_id_for([PermissionRequest.KIND_ALLOW_ALWAYS]).is_empty(), "sin «siempre»")
	assert_eq(request.options.map(func(option: Dictionary) -> String: return str(option.name)), ["Switch to Levels (Build)", "Stay in Auto"], "Cambiar o Quedarse")
	assert_true(request.description.contains("From Auto to Levels (Build).") and request.description.contains("edits only res://levels/**") and request.description.contains("«The user wants the next room built.»"), "de dónde a dónde, qué edita y el porqué · %s" % request.description)
	assert_false(request.description.contains("More permissions"), "Auto → Levels limita más: sin aviso")
	request.select("switch")
	await _wait()
	assert_eq([model.harness_mode, model.project_mode.get("name")], [M.BUILD, "Levels"], "pasa a Levels (Construir)")
	assert_true(results[0].ok and str(results[0].text).contains("Levels (a project mode based on Build)") and str(results[0].text).contains("res://levels/**"), "el agente recibe el modo y sus reglas · %s" % results[0].text)


func test_card_warns_and_stay() -> void:
	var controller := _controller(M.ASK)
	var model := controller.model
	var results: Array = []
	var ask := func() -> void: results.append(await controller.request_mode("auto", "Many small edits.", 0))
	ask.call()
	var request: PermissionRequest = model.pending_permissions[0]
	assert_true(request.description.contains("⚠ More permissions: Auto edits without asking."), "avisa que el destino tiene más permisos · %s" % request.description)
	request.select("stay")
	await _wait()
	assert_eq([model.harness_mode, model.project_mode], [M.ASK, {}], "se queda")
	assert_false(results[0].ok, "el agente sabe que no")
	assert_true(str(results[0].text).contains("stay in Ask"), "y en qué modo sigue · %s" % results[0].text)
	# Sin respuesta (vence o se cancela)
	ask = func() -> void: results.append(await controller.request_mode("build", "Edit the player.", 0))
	ask.call()
	model.pending_permissions[0].cancel()
	await _wait()
	assert_true(str(results[1].text).contains("No answer"), "sin respuesta, sigue igual · %s" % results[1].text)
	assert_eq(model.harness_mode, M.ASK, "sin cambio")


func test_project_mode_to_fixed_clears_layer() -> void:
	var controller := _controller(M.BUILD, _modes()[0])
	var model := controller.model
	var ask := func() -> void: await controller.request_mode("build", "Need to touch the player script.", 0)
	ask.call()
	var request: PermissionRequest = model.pending_permissions[0]
	assert_true(request.description.contains("More permissions: Build isn't limited to some files"), "Levels → Construir avisa · %s" % request.description)
	request.select("switch")
	await _wait()
	assert_eq([model.harness_mode, model.project_mode], [M.BUILD, {}], "saca la capa")


func test_denied_and_trivial() -> void:
	var oneshot := _controller(M.ONESHOT)
	var result: Dictionary = await oneshot.request_mode("build", "x", 0)
	assert_false(result.ok, "en One-shot se deniega")
	assert_true(str(result.text).contains("One-shot run"), "con el motivo")
	assert_true(oneshot.model.pending_permissions.is_empty(), "sin tarjeta")
	var controller := _controller(M.BUILD)
	result = await controller.request_mode("build", "x", 0)
	assert_true(result.ok and str(result.text).contains("already in Build"), "ya está en ese modo")
	result = await controller.request_mode("auto", "  ", 0)
	assert_true(not result.ok and str(result.text).contains("`why` is empty"), "sin porqué")
	result = await controller.request_mode("nope", "x", 0)
	assert_true(not result.ok and str(result.text).contains("no mode called"), "uno que no existe")
	assert_true(controller.model.pending_permissions.is_empty(), "nada de eso muestra tarjeta")


func test_system_prompt_lists_modes() -> void:
	var controller := _controller(M.ASK)
	var prompt := controller.system_prompt()
	assert_true(prompt.contains("godot.request_mode") and prompt.contains("«Levels» (based on Build): When levels") and prompt.contains("«Docs» (based on Auto)"), "el agente ve los modos y cuándo usarlos")
	controller.model.set_harness_mode(M.ONESHOT)
	assert_false(controller.system_prompt().contains("godot.request_mode"), "en One-shot no se ofrece")


func test_tool() -> void:
	var tools := SessionTools.new()
	var calls: Array = []
	tools.caller = func() -> String: return "tab-2"
	tools.request_mode = func(from: String, mode: String, why: String) -> Dictionary:
		calls.append([from, mode, why])
		return {"ok": mode == "build", "text": "done" if mode == "build" else "no"}
	var tool: McpTool
	for candidate: McpTool in tools.tools():
		if candidate.name == "request_mode":
			tool = candidate
	assert_true(tool != null and tool.group == PermissionPolicy.GROUP_READ, "del grupo read: por sí misma no cambia nada")
	var ok: Dictionary = await tool.handler.call({"mode": "build", "why": "w"})
	assert_eq(calls, [["tab-2", "build", "w"]], "pasa quién llama, el modo y el porqué")
	assert_false(ok.get("isError", false), "aceptado")
	var refused: Dictionary = await tool.handler.call({"mode": "x", "why": "w"})
	assert_true(refused.get("isError", false), "rechazado como error")
