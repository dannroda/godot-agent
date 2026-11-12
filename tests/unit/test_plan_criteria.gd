extends "test_case.gd"
## Criterios de aceptación de un plan verificados jugando (m11-23): la lectura de los criterios, la
## corrida que arranca con «Aprobar y construir», un playtest por criterio, la corrección de los que
## fallan y su segunda vuelta, los que no se pueden probar, el tope y «Verificar el resto».

const AgentLog := preload("res://addons/godot_agent/core/agent_log.gd")
const SessionController := preload("res://addons/godot_agent/session/session_controller.gd")
const SessionModel := preload("res://addons/godot_agent/session/session_model.gd")
const ChatEntry := preload("res://addons/godot_agent/session/chat_entry.gd")
const HarnessPrompts := preload("res://addons/godot_agent/session/harness_prompts.gd")
const PlanApproval := preload("res://addons/godot_agent/session/plan_approval.gd")
const PermissionRequest := preload("res://addons/godot_agent/session/permission_request.gd")
const PlanStore := preload("res://addons/godot_agent/session/plan_store.gd")
const PlanApprovalView := preload("res://addons/godot_agent/ui/dock/entries/plan_approval_view.gd")
const MarkdownBBCode := preload("res://addons/godot_agent/ui/markdown/markdown_bbcode.gd")

const PLAN := """# Plan: Lives

## 1. Acceptance criteria
- **WHEN** the player touches an enemy, **THE GAME SHALL** take one life away.
- WHEN lives reach 0,
  THE GAME SHALL show the game over screen.
1. "CUANDO el jugador junta una moneda, EL JUEGO DEBE sumar 10 puntos"
- If you want, add sounds when the player gets hurt.
- IF the game is paused THE GAME SHALL ignore enemy contact.

## 2. Tasks
1. Add a Lives autoload
2. When the player touches an enemy, call Lives.lose()
"""


func test_criteria() -> void:
	var criteria := PlanApproval.criteria(PLAN)
	assert_eq(criteria, PackedStringArray([
		"WHEN the player touches an enemy, THE GAME SHALL take one life away.",
		"WHEN lives reach 0, THE GAME SHALL show the game over screen.",
		"CUANDO el jugador junta una moneda, EL JUEGO DEBE sumar 10 puntos",
		"IF the game is paused THE GAME SHALL ignore enemy contact.",
	]), "con o sin viñeta, partidos en dos renglones, en español; las tareas no")
	assert_eq(PlanApproval.criteria("1. Add the screen\n2. Wire it"), PackedStringArray(), "un plan sin criterios")
	assert_eq(PlanApproval.criteria("- WHEN a\n- WHEN a\n- when the game starts the game shall show the menu").size(), 1, "sin SHALL no cuenta; repetidos tampoco")
	assert_eq(PlanApproval.criteria("```\nWHEN x THE GAME SHALL y\n```").size(), 1, "dentro de un bloque de código también")
	assert_eq(PlanApproval.plan_title(PLAN), "Lives")
	assert_eq(PlanApproval.plan_title("1. Add"), "")
	var items := SessionController.criteria_items(criteria, 3)
	assert_eq(items.map(func(i: Dictionary) -> String: return i.status), ["pending", "pending", "pending", "skipped"], "más allá del tope quedan afuera")
	assert_eq(SessionController.criteria_summary([{"status": "pass"}, {"status": "pass"}, {"status": "retest"}, {"status": "blocked"}, {"status": "skipped"}]).text, "2 ✓ · 1 ✗ · 1 ⊘")


func test_verifies_setting_and_checkbox() -> void:
	var sent: Array = []
	var controller := _controller(sent)
	var request := PlanApproval.block_request(PLAN)
	assert_true(controller.verifies_criteria(request), "prendido por defecto")
	controller.plan_criteria_settings = func() -> Dictionary: return {"on": false, "max": 6}
	assert_false(controller.verifies_criteria(request), "el setting lo apaga")
	request.verify_criteria = 1
	assert_true(controller.verifies_criteria(request), "la casilla de la tarjeta manda")
	controller.plan_criteria_settings = Callable()
	request.verify_criteria = 0
	assert_false(controller.verifies_criteria(request))
	assert_false(controller.verifies_criteria(PlanApproval.block_request("1. Add the screen")), "sin criterios no hay nada que verificar")
	request.verify_criteria = 0
	controller.model.add_permission(request)
	controller.approve_plan(request)
	await _frames()
	assert_true(controller.recipe_run().is_empty(), "con la casilla apagada no arranca")
	await _end(controller)


func test_run() -> void:
	var sent: Array = []
	var controller := _controller(sent)
	controller.plan_criteria_settings = func() -> Dictionary: return {"on": true, "max": 3}
	var request := PlanApproval.block_request(PLAN)
	var changes: Array = []
	request.changed.connect(func() -> void: changes.append(1))
	controller.model.add_permission(request)
	controller.approve_plan(request)
	await _frames()
	var run := controller.recipe_run()
	assert_eq(run.get("title"), "Lives", "la corrida del plan, con su título")
	assert_eq(run.origin, "plan")
	assert_eq(request.criteria_results.size(), 4, "la tarjeta tiene los criterios")
	assert_eq(request.criteria_results[3].status, "skipped", "el cuarto pasa el tope")
	# El turno que construye (aprobación del bloque) termina; los checks pasan: juega el primero.
	await _end_turn(controller)
	await controller.call(&"_run_turn_checks", int(Time.get_unix_time_from_system()) - 5)
	await _frames()
	var prompt := _last_prompt(sent)
	assert_true(prompt.begins_with("Playtest: check this acceptance criterion of the approved plan: WHEN the player touches an enemy"), prompt.left(120))
	assert_eq(controller.model.harness_mode, SessionModel.HarnessMode.REVIEW, "en Revisar")
	assert_true(controller.model.entries().any(func(e: ChatEntry) -> bool: return e.harness_label == HarnessPrompts.PLAN_CRITERION), "prompt del harness")
	# 1 pasa, 2 falla, 3 no se puede probar.
	await _verdict(controller, {"verdict": "pass", "summary": "One life less"})
	assert_eq(request.criteria_results[0].status, "pass")
	assert_true(_last_prompt(sent).contains("WHEN lives reach 0"), "sigue con el segundo, en otro turno")
	await _verdict(controller, {"verdict": "fail", "summary": "No game over screen", "repro": ["touch an enemy 3 times"], "evidence": ["lives = 0, scene still Main"]})
	assert_true(_last_prompt(sent).contains("CUANDO el jugador"), "el tercero")
	var before := _prompts(sent).size()
	await _verdict(controller, {"verdict": "blocked", "summary": "No coins in the level"})
	# La corrección: solo el que falló, en Construir.
	assert_eq(controller.model.harness_mode, SessionModel.HarnessMode.BUILD, "vuelve a Construir")
	assert_eq(_prompts(sent).size(), before + 1, "un turno de corrección")
	prompt = _last_prompt(sent)
	assert_true(prompt.contains("acceptance criteria failed") and prompt.contains("WHEN lives reach 0") and prompt.contains("No game over screen") and prompt.contains("- touch an enemy 3 times"), prompt)
	assert_false(prompt.contains("No coins"), "el que no se pudo probar no se corrige")
	assert_true(controller.model.entries().any(func(e: ChatEntry) -> bool: return e.harness_label == HarnessPrompts.PLAN_CRITERIA_FIX))
	assert_eq(request.criteria_results.map(func(i: Dictionary) -> String: return i.status), ["pass", "retest", "blocked", "skipped"])
	assert_true(_notices(controller)[-1].contains("1 of the criteria failed"), _notices(controller)[-1])
	# Después del arreglo vuelve a jugar solo el segundo, y pasa.
	await _end_turn(controller)
	await controller.call(&"_run_turn_checks", int(Time.get_unix_time_from_system()) - 5)
	await _frames()
	assert_true(_last_prompt(sent).contains("WHEN lives reach 0"), "vuelve a probar el que falló")
	before = _prompts(sent).size()
	await _verdict(controller, {"verdict": "pass", "summary": "Game over shows"})
	assert_eq(_prompts(sent).size(), before, "no juega el que ya pasó ni el que no se pudo probar")
	assert_true(controller.recipe_run().is_empty(), "la corrida terminó")
	var final: String = _notices(controller)[-1]
	assert_true(final.contains("2 ✓ · 0 ✗ · 1 ⊘"), final)
	assert_true(final.contains("✓ Criterion 2: WHEN lives reach 0") and final.contains("⊘ Criterion 3"), final)
	assert_true(final.contains("1 more criteria weren't played"), final)
	var entry: ChatEntry = controller.model.entries().filter(func(e: ChatEntry) -> bool: return e.kind == ChatEntry.EntryKind.NOTICE)[-1]
	assert_eq(entry.actions[0].id, SessionController.ACTION_VERIFY_REST, "ofrece verificar el resto")
	assert_eq(PackedStringArray(entry.actions[0].data), PackedStringArray(["IF the game is paused THE GAME SHALL ignore enemy contact."]))
	assert_true(changes.size() >= 5, "la tarjeta se entera de cada cambio")
	assert_eq(request.criteria_results[1].tries, 2)
	var saved := FileAccess.get_file_as_string(str(_plan_files(controller)[0]))
	assert_true(saved.contains("## Verification") and saved.contains("2 ✓ · 0 ✗ · 1 ⊘"), "el plan guardado suma la verificación: %s" % saved.right(300))
	assert_true(saved.contains("- ✓ WHEN lives reach 0, THE GAME SHALL show the game over screen.\n  - Game over shows"), saved.right(400))
	assert_true(saved.contains("- · IF the game is paused") and saved.contains("(not played)"), saved.right(300))
	# «Verificar el resto»: juega sin turno de construir, y lo que falla no se corrige.
	controller.verify_rest(entry.actions[0].data)
	await _frames()
	assert_true(_last_prompt(sent).contains("IF the game is paused"), "juega el que quedó afuera")
	before = _prompts(sent).size()
	await _verdict(controller, {"verdict": "fail", "summary": "Enemies still hurt"})
	assert_eq(_prompts(sent).size(), before, "sin corrección")
	assert_true(_notices(controller)[-1].contains("0 ✓ · 1 ✗"), _notices(controller)[-1])
	assert_true(controller.recipe_run().is_empty())
	await _end(controller)


func test_retries_and_user_message() -> void:
	var sent: Array = []
	var controller := _controller(sent)
	var request := PlanApproval.block_request("# Plan: Jump\n- WHEN the player presses jump THE GAME SHALL make them jump\n")
	controller.model.add_permission(request)
	controller.approve_plan(request)
	await _end_turn(controller)
	var started := int(Time.get_unix_time_from_system()) - 5
	await controller.call(&"_run_turn_checks", started)
	await _frames()
	for i: int in 2:
		await _verdict(controller, {"verdict": "fail", "summary": "No jump"})
		assert_true(_last_prompt(sent).contains("acceptance criteria failed"), "corrección %d" % (i + 1))
		await _end_turn(controller)
		await controller.call(&"_run_turn_checks", started)
		await _frames()
	var before := _prompts(sent).size()
	await _verdict(controller, {"verdict": "fail", "summary": "Still no jump"})
	assert_eq(_prompts(sent).size(), before, "con 2 reintentos, no corrige más")
	assert_true(_notices(controller)[-1].contains("0 ✓ · 1 ✗"), _notices(controller)[-1])
	assert_true(controller.recipe_run().is_empty())
	# Un mensaje del usuario corta la corrida; lo que no se jugó queda sin probar en la tarjeta.
	var other := PlanApproval.block_request("# Plan: Run\n- WHEN the player holds shift THE GAME SHALL make them run\n")
	controller.model.add_permission(other)
	controller.approve_plan(other)
	await _end_turn(controller)
	controller.send_prompt("Actually, make it a double jump")
	await _frames()
	assert_true(controller.recipe_run().is_empty(), "otro mensaje del usuario la termina")
	assert_eq(other.criteria_results[0].status, "blocked")
	await _end(controller)


func test_plan_file() -> void:
	var dir := ProjectSettings.globalize_path("user://").path_join("plan_file_%d" % Time.get_ticks_usec())
	var path := PlanStore.save_approved(dir, "# Plan: Jump\n- WHEN x THE GAME SHALL y", "2026-11-11")
	var criteria := [{"goal": "WHEN x THE GAME SHALL y", "status": "fail", "summary": "No y", "evidence": ["y = 0"]}]
	assert_true(PlanStore.append_verification(path, criteria, "0 ✓ · 1 ✗", "2026-11-11 10:00"))
	var text := FileAccess.get_file_as_string(path)
	assert_true(text.contains("<!-- Approved: 2026-11-11 -->\n\n## Verification\n\nChecked by playing (2026-11-11 10:00): 0 ✓ · 1 ✗\n\n- ✗ WHEN x THE GAME SHALL y\n  - No y\n  - y = 0\n"), text)
	criteria[0].status = "pass"
	PlanStore.append_verification(path, criteria, "1 ✓ · 0 ✗", "2026-11-11 11:00")
	text = FileAccess.get_file_as_string(path)
	assert_eq(text.count("## Verification"), 1, "una segunda verificación reemplaza la anterior")
	assert_true(text.contains("- ✓ WHEN x"), text)
	assert_false(PlanStore.append_verification("", criteria, ""), "sin plan guardado no escribe")
	DirAccess.remove_absolute(path)


func test_card() -> void:
	var sent: Array = []
	var controller := _controller(sent)
	controller.plan_criteria_settings = func() -> Dictionary: return {"on": true, "max": 3}
	var request := PlanApproval.block_request(PLAN)
	var entry := controller.model.add_permission(request)
	assert_eq(request.verify_criteria, 1, "la tarjeta arranca con el setting")
	assert_eq(request.criteria_max, 3)
	var view := PlanApprovalView.new()
	view.setup(entry, Color.WHITE, MarkdownBBCode.new())
	(Engine.get_main_loop() as SceneTree).root.add_child(view)
	var check: CheckBox = view.find_child("VerifyCriteria", true, false)
	var cost: Label = view.find_child("VerifyCost", true, false)
	assert_true(check.is_visible_in_tree() and check.button_pressed, "la casilla se ve, prendida")
	assert_eq(check.text, "Verify the criteria by playing (4)")
	assert_true(cost.text.contains("one playtest") and cost.text.contains("3 times") and cost.text.contains("Up to 3 per plan (change it in Settings)"), cost.text)
	check.button_pressed = false
	assert_eq(request.verify_criteria, 0, "apagarla vale para este plan")
	assert_false(controller.verifies_criteria(request))
	check.button_pressed = true
	controller.approve_plan(request)
	await _frames()
	view.refresh()
	assert_false(check.is_visible_in_tree(), "aprobado, la casilla se va")
	var box: VBoxContainer = view.find_child("CriteriaResults", true, false)
	assert_true(box.visible, "y quedan los criterios")
	var lines := box.get_children().filter(func(l: Label) -> bool: return l.visible).map(func(l: Label) -> String: return l.text)
	assert_eq(lines.size(), 4)
	assert_true(str(lines[0]).begins_with("… Criterion 1 · WHEN the player touches an enemy") and str(lines[0]).ends_with("waiting to be played"), str(lines[0]))
	assert_true(str(lines[3]).begins_with("· Criterion 4") and str(lines[3]).contains("over the limit"), str(lines[3]))
	request.criteria_results[0].status = "pass"
	request.criteria_results[0].summary = "One life less"
	request.criteria_results[0].evidence = ["lives 3 → 2"]
	request.changed.emit()
	var first: Label = box.get_child(0)
	assert_true(first.text.begins_with("✓ Criterion 1") and not first.text.contains("—"), first.text)
	assert_eq(first.tooltip_text, "One life less\n• lives 3 → 2", "lo que vio, en el tooltip")
	view.queue_free()
	await _end(controller)


func _plan_files(controller: SessionController) -> Array:
	var dir := controller.cwd.path_join(PlanStore.DIR)
	return Array(DirAccess.get_files_at(dir)).map(func(f: String) -> String: return dir.path_join(f))


func _controller(sent: Array) -> SessionController:
	var dir := ProjectSettings.globalize_path("user://").path_join("plan_criteria_%d" % Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(dir)
	var controller := SessionController.new()
	controller.setup(SessionModel.new(), AgentLog.new(), dir)
	controller.regressions_dir = dir.path_join("regressions")
	controller.model.session_id = "s"
	controller.model.set_state(SessionModel.SessionState.READY)
	controller.model.set_harness_mode(SessionModel.HarnessMode.BUILD)
	controller.client.setup(func(line: String) -> bool:
		sent.append(JSON.parse_string(line))
		return true, controller.agent_log)
	controller.turn_checks_provider = func() -> Dictionary: return {"checks": [], "godot": OS.get_executable_path(), "project": dir}
	return controller


## Termina el turno del playtest con ese veredicto, como _report_playtest y el final del turno.
func _verdict(controller: SessionController, verdict: Dictionary) -> void:
	await _end_turn(controller)
	controller.get(&"_recipe_run").playtest_verdict = verdict
	controller.call(&"_after_recipe_playtest")
	await _frames()


func _prompts(sent: Array) -> Array:
	return sent.filter(func(message: Variant) -> bool: return message is Dictionary and message.get("method") == "session/prompt")


func _last_prompt(sent: Array) -> String:
	return str(_prompts(sent)[-1].params.prompt[-1].text)


func _notices(controller: SessionController) -> Array:
	return controller.model.entries().filter(func(entry: ChatEntry) -> bool: return entry.kind == ChatEntry.EntryKind.NOTICE).map(func(entry: ChatEntry) -> String: return entry.text)


func _end_turn(controller: SessionController) -> void:
	controller.client.fail_all_pending("end of turn")
	await _frames()
	controller.model.set_state(SessionModel.SessionState.READY)


func _end(controller: SessionController) -> void:
	controller.client.fail_all_pending("end of test")
	await _frames()


func _frames(n: int = 2) -> void:
	for i: int in n:
		await Engine.get_main_loop().process_frame
