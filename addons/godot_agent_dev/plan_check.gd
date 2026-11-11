@tool
extends RefCounted
## m11-22 en el editor, con el agente falso (tests/scripts/plan_mode.json) mandando ExitPlanMode como
## claude-agent-acp 0.105:
## 1. En Preguntar, el plan sale en su tarjeta (no la genérica) con Aprobar y construir · Editar ·
##    Seguir planeando…, sin las opciones de auto/bypass/clear context.
## 2. Editar → Mandar cambios: rechaza, el turno termina cancelled y el diff sale solo como prompt
##    del harness (PLAN_EDIT).
## 3. Aprobar y construir: el harness pasa a Construir sin mandar set_mode, el plan queda en
##    .godot_agent/plans y la primera edición del agente pide permiso (no se deniega).
## 4. «Denegar con motivo…» en una tarjeta de shell: el motivo sale con el turno siguiente (DENY_REASON).
## 5. Rechazo editado y después Detener: lo editado queda en la cola, en pausa; no sale solo.
## m11-38 (modelo por modo) en la misma corrida, con la configOption model de 0.106 en el escenario y
## una tienda en memoria (no se toca EditorSettings): Construir recuerda Sonnet y Preguntar Opus.
## a. Al abrir la sesión en Construir pide Sonnet, con el aviso de una línea y su «Change».
## b. Pasar a Preguntar pide Opus antes del set_mode plan, y el tooltip del selector lo dice.
## c. «Aprobar y construir» pide Sonnet en medio del turno, sin set_mode.
## d. Elegir Haiku en el selector del composer lo recuerda para Construir.
## Después, m11-58 con un agente sin modo plan (tests/scripts/plan_block.json):
## 6. «Planificar» con el pedido en el composer: pasa a Preguntar y el pedido sale como PLAN_REQUEST
##    pidiendo el bloque ```plan (no ExitPlanMode).
## 7. El bloque del final del turno se vuelve la tarjeta del plan, y el mensaje lo muestra en una línea.
## 8. Editar y «Seguir planeando…» salen enseguida (el turno ya terminó) pidiendo de nuevo el bloque.
## 9. Aprobar: guarda el plan, pasa a Construir y manda PLAN_APPROVED con la ruta.
## 10. /plan en el composer pide otro plan; otro mensaje con la tarjeta pendiente la cancela.

const SessionModel := preload("res://addons/godot_agent/session/session_model.gd")
const SessionController := preload("res://addons/godot_agent/session/session_controller.gd")
const HarnessSettings := preload("res://addons/godot_agent/core/harness_settings.gd")
const ModeModels := preload("res://addons/godot_agent/core/mode_models.gd")
const AgentProfile := preload("res://addons/godot_agent/core/agent_profile.gd")
const HarnessPrompts := preload("res://addons/godot_agent/session/harness_prompts.gd")
const PlanStore := preload("res://addons/godot_agent/session/plan_store.gd")
const I18n := preload("res://addons/godot_agent/core/i18n.gd")
const PLAN_VIEW_SCRIPT := "res://addons/godot_agent/ui/dock/entries/plan_approval_view.gd"
const PERMISSION_VIEW_SCRIPT := "res://addons/godot_agent/ui/dock/entries/permission_view.gd"
const SCENARIO := "res://tests/scripts/plan_mode.json"
const BLOCK_SCENARIO := "res://tests/scripts/plan_block.json"
## Corrida corta con Claude Code real (gasta tokens): una copia del jugador de tests/docs_demo.
const CLAUDE_TARGET := "res://tests/tmp/plan_demo/player.gd"
const CLAUDE_WAIT_MS := 240000
const WAIT_MS := 15000

var failures: PackedStringArray = []
var _tree: SceneTree
var _dock: Control
var _model: Object
var _controller: Object
var _shot_prefix: String = ""
var _models: Object


func run(tree: SceneTree, dock: Control, shot_prefix: String = "") -> PackedStringArray:
	_tree = tree
	_dock = dock
	_shot_prefix = shot_prefix
	_model = dock.get(&"_model")
	_controller = dock.get(&"_controller")
	var plans_dir := ProjectSettings.globalize_path("res://").path_join(PlanStore.DIR)
	var before := _plan_files(plans_dir)
	var saved_models: Object = _controller.get(&"mode_models")
	var saved_mode: int = _model.get(&"harness_mode")
	_models = ModeModels.new(HarnessSettings.new())  # en memoria: el check no toca EditorSettings
	_models.remember("fake", SessionModel.HarnessMode.BUILD, "sonnet", "Sonnet")
	_models.remember("fake", SessionModel.HarnessMode.ASK, "opus", "Opus")
	_controller.set(&"mode_models", _models)
	_controller.set(&"_mode_model_noticed", false)
	_model.call(&"set_harness_mode", SessionModel.HarnessMode.BUILD)
	await _run()
	_controller.set(&"mode_models", saved_models)
	_model.call(&"set_harness_mode", saved_mode)
	if failures.is_empty():
		await _run_block()
	for file: String in _plan_files(plans_dir):
		if not file in before:
			DirAccess.remove_absolute(plans_dir.path_join(file))
	_controller.call(&"stop")
	return failures


func _run() -> void:
	var profile := AgentProfile.from_dict({
		"id": "fake", "display_name": "Agente falso", "command": OS.get_executable_path(),
		"args": ["--headless", "--no-header", "--path", ProjectSettings.globalize_path("res://"),
			"--script", "res://tests/fake_agent.gd", "--", "--scenario=" + SCENARIO],
	})
	if not await _controller.call(&"start", profile):
		failures.append("no arrancó la sesión (%s)" % _model.get(&"failure_message"))
		return
	# a. Al abrir en Construir, el modelo recordado ahí.
	_expect(_current_model() == "sonnet", "al abrir en Construir pide Sonnet · %s" % _current_model())
	_expect(_log_count("fake_agent: set_config_option") == 1 and _log_count("fake_agent: set_config_option") == _fake_count("sonnet"), "con session/set_config_option · %d" % _log_count("fake_agent: set_config_option"))
	var uses := _notice_with("Build uses Sonnet")
	_expect(uses != null, "aviso de una línea «Build uses Sonnet»")
	if uses:
		var actions: Array = uses.get(&"actions")
		_expect(actions.size() == 1 and str(actions[0].id) == SessionController.ACTION_CHOOSE_MODEL, "con «Change» · %s" % [actions])
		var model_button: OptionButton = _dock.get(&"_composer").get(&"_model_button")
		_dock.call(&"_on_action_requested", SessionController.ACTION_CHOOSE_MODEL, null)
		await _tree.process_frame
		_expect(model_button.get_popup().visible, "«Change» abre el selector")
		model_button.get_popup().hide()

	# b. Preguntar: Opus antes del set_mode plan.
	var log_before: int = (_controller.get(&"agent_log").call(&"entries") as Array).size()
	_model.call(&"set_harness_mode", SessionModel.HarnessMode.ASK)
	await _until(func() -> bool: return str(_model.get(&"current_agent_mode")) == "plan", "el agente no pasó a plan al elegir Preguntar")
	_expect(_current_model() == "opus", "Preguntar pide Opus · %s" % _current_model())
	var order := (_controller.get(&"agent_log").call(&"entries") as Array).slice(log_before).map(func(e: Dictionary) -> String: return str(e.message)) \
		.filter(func(m: String) -> bool: return m.contains("fake_agent: set_"))
	_expect(order.size() >= 2 and order[0].contains("set_config_option") and order[0].contains("opus") and order[1].contains("set_mode plan"), "el modelo antes que el modo · %s" % [order])
	var tooltip := str((_dock.get(&"_composer").get(&"_model_button") as OptionButton).tooltip_text)
	_expect(tooltip.contains("Remembered for Ask"), "el tooltip del selector dice que se recuerda para Preguntar · %s" % tooltip)
	_expect(_notice_with("Ask uses Opus") == null, "el aviso, una vez por pestaña")
	var plans_dir := ProjectSettings.globalize_path("res://").path_join(PlanStore.DIR)
	var plans_before := _plan_files(plans_dir).size()

	# 1. La tarjeta del plan.
	_dock.call(&"send_text", "plan a jump for the player")
	var view: Control = await _wait_view(PLAN_VIEW_SCRIPT, 1)
	if view == null:
		failures.append("no apareció la tarjeta del plan")
		return
	var texts := _button_texts(view)
	for expected: String in [I18n.t("Approve and build"), I18n.t("Edit"), I18n.t("Keep planning…")]:
		_expect(expected in texts, "la tarjeta ofrece «%s» · %s" % [expected, texts])
	_expect(not texts.any(func(t: String) -> bool: return t.contains("auto") or t.contains("bypass") or t.contains("clear context")), "sin auto, bypass ni clear context · %s" % [texts])
	_expect(_views(PERMISSION_VIEW_SCRIPT).is_empty(), "no sale también la tarjeta genérica")
	await _shot("card")

	# 2. Editar → Mandar cambios.
	(_button(view, I18n.t("Edit"))).pressed.emit()
	await _tree.process_frame
	var editor: CodeEdit = view.get(&"_editor")
	editor.text = editor.text.replace("2. Jump with `ui_accept` on the floor.", "2. Jump with `ui_accept` on the floor.\n3. Double jump once in the air.")
	editor.text_changed.emit()
	await _tree.process_frame
	_expect(str((view.get(&"_counts") as Label).text).contains("+1"), "el contador muestra +1 · %s" % (view.get(&"_counts") as Label).text)
	await _shot("edit")
	(view.get(&"_send_edit") as Button).pressed.emit()
	var edit_entry: Object = await _wait_user_entry(HarnessPrompts.PLAN_EDIT)
	_expect(edit_entry != null, "lo editado salió solo como prompt del harness (PLAN_EDIT) al terminar el turno cancelled")
	if edit_entry:
		_expect(str(edit_entry.get(&"text")).contains("+ 3. Double jump once in the air."), "con la línea agregada")

	# 3. Aprobar y construir.
	view = await _wait_view(PLAN_VIEW_SCRIPT, 2)
	if view == null:
		failures.append("no apareció el plan corregido")
		return
	var set_mode_default_before := _log_count("set_mode default")
	var sonnet_before := _fake_count("sonnet")
	_button(view, I18n.t("Approve and build")).pressed.emit()
	await _tree.process_frame
	_expect(int(_model.get(&"harness_mode")) == SessionModel.HarnessMode.BUILD, "aprobar pasa a Construir")
	await _until(func() -> bool: return _current_model() == "sonnet", "c. «Aprobar y construir» no pidió el modelo de Construir")
	_expect(_fake_count("sonnet") == sonnet_before + 1, "c. Sonnet en medio del turno")
	var write_card: Control = await _wait_view(PERMISSION_VIEW_SCRIPT, 1)
	_expect(write_card != null, "la primera edición pide permiso en Construir (no se deniega)")
	_expect(str(_model.get(&"current_agent_mode")) == "default", "el agente pasó solo a default")
	_expect(_log_count("set_mode default") == set_mode_default_before, "sin session/set_mode al aprobar")
	_expect(_log_count("set_mode plan") > 0, "(el log registra los set_mode del agente falso)")
	_expect(_plan_files(plans_dir).size() == plans_before + 1, "el plan aprobado quedó en .godot_agent/plans")
	view = await _wait_view(PLAN_VIEW_SCRIPT, 2)  # contestada vuelve al chat: puede ser otra vista
	_expect(view != null and str(view.get(&"_result").text).contains("✓"), "la tarjeta queda plegada como aprobada")
	await _shot("approved")
	if write_card:
		_button(write_card, I18n.t("Allow once")).pressed.emit()
	await _until(func() -> bool: return not bool(_model.call(&"is_busy")), "el turno aprobado no terminó")

	# d. Elegir en el selector lo recuerda para el modo actual (Construir).
	var button: OptionButton = _dock.get(&"_composer").get(&"_model_button")
	var haiku := -1
	for i: int in button.item_count:
		if button.get_item_text(i) == "Haiku":
			haiku = i
	_expect(haiku >= 0, "d. el selector lista Haiku")
	if haiku >= 0:
		button.select(haiku)
		button.item_selected.emit(haiku)
		await _until(func() -> bool: return str(_models.call(&"get_model", "fake", SessionModel.HarnessMode.BUILD).get("value", "")) == "haiku", "d. elegir Haiku no quedó recordado para Construir")
		_expect(_current_model() == "haiku", "d. y se pidió · %s" % _current_model())

	# 4. Denegar con motivo en una tarjeta de shell.
	_dock.call(&"send_text", "push it")
	var shell_card: Control = await _wait_view(PERMISSION_VIEW_SCRIPT, 2)
	if shell_card == null:
		failures.append("no apareció la tarjeta de la shell")
		return
	_button(shell_card, I18n.t("Deny with reason…")).pressed.emit()
	await _tree.process_frame
	var reason: LineEdit = shell_card.get(&"_reason_edit")
	_expect(reason.is_visible_in_tree(), "se abre el campo del motivo")
	reason.text = "I review before pushing"
	await _shot("deny_reason")
	reason.text_submitted.emit(reason.text)
	var reason_entry: Object = await _wait_user_entry(HarnessPrompts.DENY_REASON)
	_expect(reason_entry != null and str(reason_entry.get(&"text")).contains("I review before pushing"), "el motivo salió con el turno siguiente (DENY_REASON)")
	_expect(not _agent_texts().any(func(e: Object) -> bool: return str(e.get(&"text")).contains("I won't push")), "el turno del rechazo se cortó: el agente no siguió sin el motivo")
	shell_card = await _wait_view(PERMISSION_VIEW_SCRIPT, 2)
	_expect(shell_card != null and str(shell_card.get(&"_result").text).contains("I review before pushing"), "la tarjeta muestra el motivo")
	await _until(func() -> bool: return not bool(_model.call(&"is_busy")), "el turno del motivo no terminó")

	# 5. Rechazo editado y Detener: no sale solo.
	_model.call(&"set_harness_mode", SessionModel.HarnessMode.ASK)
	_dock.call(&"send_text", "plan again")
	view = await _wait_view(PLAN_VIEW_SCRIPT, 3)
	if view == null:
		failures.append("no apareció el tercer plan")
		return
	_button(view, I18n.t("Keep planning…")).pressed.emit()
	await _tree.process_frame
	var keep_reason: LineEdit = view.get(&"_reason_edit")
	keep_reason.text = "smaller steps"
	keep_reason.text_submitted.emit(keep_reason.text)
	await _tree.process_frame
	await _tree.process_frame
	_dock.call(&"_on_cancel_requested")  # antes del corte automático (REJECT_CANCEL_DELAY_S)
	await _until(func() -> bool: return not bool(_model.call(&"is_busy")), "el turno no se canceló")
	await _tree.create_timer(1.0).timeout
	var queue: Object = _dock.get(&"_queue")
	_expect(int(queue.call(&"size")) == 1 and bool(queue.get(&"paused")), "con Detener, el motivo queda en la cola en pausa (cola %d, pausada %s)" % [queue.call(&"size"), queue.get(&"paused")])
	_expect(_user_entry(HarnessPrompts.PLAN_KEEP_PLANNING) == null, "y no sale solo")
	queue.call(&"clear")


func _run_block() -> void:
	var profile := AgentProfile.from_dict({
		"id": "fake-block", "display_name": "Agente falso sin modo plan", "command": OS.get_executable_path(),
		"args": ["--headless", "--no-header", "--path", ProjectSettings.globalize_path("res://"),
			"--script", "res://tests/fake_agent.gd", "--", "--scenario=" + BLOCK_SCENARIO],
	})
	if not await _controller.call(&"start", profile):
		failures.append("bloque: no arrancó la sesión (%s)" % _model.get(&"failure_message"))
		return
	_model.call(&"set_harness_mode", SessionModel.HarnessMode.BUILD)
	await _tree.process_frame
	var plans_dir := ProjectSettings.globalize_path("res://").path_join(PlanStore.DIR)
	var plans_before := _plan_files(plans_dir).size()
	var composer: Control = _dock.get(&"_composer")
	var plan_button: Button = composer.find_child("PlanButton", true, false)
	_expect(plan_button != null and plan_button.is_visible_in_tree(), "bloque: «Planificar» está en la fila del composer con la sesión libre")
	if plan_button == null:
		return

	# 6. Planificar con el pedido escrito.
	composer.call(&"insert_text", "add a coin counter")
	await _shot("block_composer")
	plan_button.pressed.emit()
	_expect(_model.get(&"agent_modes").is_empty(), "bloque: el agente nuevo no hereda los modos del anterior · %s" % [_model.get(&"agent_modes")])
	var request_entry: Object = await _wait_user_entry(HarnessPrompts.PLAN_REQUEST)
	_expect(request_entry != null, "bloque: el pedido salió como prompt del harness (PLAN_REQUEST)")
	if request_entry:
		var text := str(request_entry.get(&"text"))
		_expect(text.contains("add a coin counter") and text.contains("```plan") and not text.contains("ExitPlanMode"), "bloque: pide el bloque ```plan, no ExitPlanMode")
	_expect(int(_model.get(&"harness_mode")) == SessionModel.HarnessMode.ASK, "bloque: «Planificar» pasa a Preguntar")
	_expect(str(composer.call(&"current_text")).is_empty(), "bloque: el composer quedó vacío")
	_expect(not plan_button.is_visible_in_tree(), "bloque: «Planificar» se oculta con el agente trabajando")

	# 7. La tarjeta.
	var view: Control = await _wait_view(PLAN_VIEW_SCRIPT, 1)
	if view == null:
		failures.append("bloque: el bloque ```plan no se volvió la tarjeta del plan")
		return
	var request: Object = view.get(&"entry").get(&"permission")
	_expect(bool(request.get(&"from_block")) and str(request.get(&"plan_text")).begins_with("# Plan: Coin counter"), "bloque: la tarjeta tiene el plan del bloque")
	_expect(_plan_lines() == 1, "bloque: el mensaje muestra el bloque como una línea (%d)" % _plan_lines())
	_expect(not _code_blocks_with("WHEN the player touches a coin"), "bloque: el plan no se repite en el mensaje")
	await _shot("block_card")

	# 8. Editar → sale enseguida.
	_button(view, I18n.t("Edit")).pressed.emit()
	await _tree.process_frame
	var editor: CodeEdit = view.get(&"_editor")
	editor.text = editor.text.replace("2. Show it in the HUD.", "2. Show it in the HUD, top right.")
	editor.text_changed.emit()
	(view.get(&"_send_edit") as Button).pressed.emit()
	var edit_entry: Object = await _wait_user_entry(HarnessPrompts.PLAN_EDIT)
	_expect(edit_entry != null and str(edit_entry.get(&"text")).contains("+ 2. Show it in the HUD, top right.") and str(edit_entry.get(&"text")).contains("```plan block"), "bloque: lo editado salió enseguida, pidiendo de nuevo el bloque")
	view = await _wait_view(PLAN_VIEW_SCRIPT, 1)  # contestada vuelve al chat: puede ser otra vista
	_expect(view != null and str(view.get(&"_result").text).contains(I18n.t("Edited (+%d −%d): sent to the agent") % [1, 1]), "bloque: la tarjeta dice que se mandó · %s" % (view.get(&"_result").text if view else ""))
	view = await _wait_view(PLAN_VIEW_SCRIPT, 2)
	if view == null:
		failures.append("bloque: no apareció el plan corregido")
		return
	_button(view, I18n.t("Keep planning…")).pressed.emit()
	await _tree.process_frame
	var reason: LineEdit = view.get(&"_reason_edit")
	reason.text = "use a CanvasLayer for the HUD"
	reason.text_submitted.emit(reason.text)
	var keep_entry: Object = await _wait_user_entry(HarnessPrompts.PLAN_KEEP_PLANNING)
	_expect(keep_entry != null and str(keep_entry.get(&"text")).ends_with("use a CanvasLayer for the HUD"), "bloque: el motivo salió enseguida")

	# 9. Aprobar.
	view = await _wait_view(PLAN_VIEW_SCRIPT, 3)
	if view == null:
		failures.append("bloque: no apareció el tercer plan")
		return
	_button(view, I18n.t("Approve and build")).pressed.emit()
	var approved_entry: Object = await _wait_user_entry(HarnessPrompts.PLAN_APPROVED)
	_expect(approved_entry != null and str(approved_entry.get(&"text")).contains(PlanStore.DIR), "bloque: aprobar manda PLAN_APPROVED con la ruta del plan")
	_expect(int(_model.get(&"harness_mode")) == SessionModel.HarnessMode.BUILD, "bloque: aprobar pasa a Construir")
	_expect(_plan_files(plans_dir).size() == plans_before + 1, "bloque: el plan aprobado quedó en .godot_agent/plans")
	view = await _wait_view(PLAN_VIEW_SCRIPT, 3)
	_expect(view != null and str(view.get(&"_result").text).contains("✓"), "bloque: la tarjeta queda aprobada")
	await _until(func() -> bool: return not bool(_model.call(&"is_busy")), "bloque: el turno de construir no terminó")
	_expect((_model.get(&"plan") as Array).size() == 3, "bloque: el agente lleva las tareas como su plan")
	await _shot("block_approved")

	# 10. /plan y otro mensaje con la tarjeta pendiente.
	composer.call(&"insert_text", "/plan add lives")
	composer.call(&"_submit")
	await _until(func() -> bool: return (_model.call(&"entries") as Array).filter(func(e: Object) -> bool: return int(e.get(&"kind")) == 0 and str(e.get(&"harness_label")) == HarnessPrompts.PLAN_REQUEST).size() == 2, "bloque: /plan no pidió otro plan")
	_expect(int(_model.get(&"harness_mode")) == SessionModel.HarnessMode.ASK, "bloque: /plan pasa a Preguntar")
	view = await _wait_view(PLAN_VIEW_SCRIPT, 4)
	if view == null:
		failures.append("bloque: no apareció el plan de /plan")
		return
	await _until(func() -> bool: return not bool(_model.call(&"is_busy")), "bloque: el turno de /plan no terminó")
	var pending: Object = view.get(&"entry").get(&"permission")
	_dock.call(&"send_text", "never mind")
	await _until(func() -> bool: return not bool(pending.call(&"is_pending")), "bloque: otro mensaje no canceló la tarjeta")
	await _tree.process_frame
	view = await _wait_view(PLAN_VIEW_SCRIPT, 4)
	_expect(view != null and str(view.get(&"_result").text).begins_with("⊘"), "bloque: la tarjeta queda cancelada · %s" % (view.get(&"_result").text if view else ""))


## Las líneas «Plan presentado» en los mensajes del agente.
func _plan_lines() -> int:
	return _dock.find_children("*", "Label", true, false).filter(func(l: Label) -> bool: return l.has_meta(&"plan_line") and l.is_visible_in_tree()).size()


func _code_blocks_with(text: String) -> bool:
	for node: Node in _dock.find_children("*", "", true, false):
		if node.get_script() != null and str(node.get_script().resource_path).ends_with("code_block_view.gd") and str(node.get(&"_code")).contains(text):
			return true
	return false


## Con Claude Code real (m11-22): Preguntar → plan chico → Editar una línea → plan nuevo → Aprobar →
## el agente pasa solo a default (sin set_mode) → su primera edición pide permiso con la matriz de
## Construir → Denegar con motivo → el motivo sale y el agente sigue. Corta apenas lo ve.
func run_claude(tree: SceneTree, dock: Control, shot_prefix: String = "") -> PackedStringArray:
	_tree = tree
	_dock = dock
	_shot_prefix = shot_prefix
	_model = dock.get(&"_model")
	_controller = dock.get(&"_controller")
	var plans_dir := ProjectSettings.globalize_path("res://").path_join(PlanStore.DIR)
	var before := _plan_files(plans_dir)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(CLAUDE_TARGET.get_base_dir()))
	var source := FileAccess.get_file_as_string("res://tests/docs_demo/player.gd")
	var file := FileAccess.open(CLAUDE_TARGET, FileAccess.WRITE)
	file.store_string(source)
	file.close()
	await _run_claude(source)
	for name: String in _plan_files(plans_dir):
		if not name in before:
			print("[claude-plan] plan guardado: %s" % name)
			DirAccess.remove_absolute(plans_dir.path_join(name))
	_controller.call(&"stop")
	return failures


func _run_claude(source: String) -> void:
	var profile := AgentProfile.from_dict(AgentProfile.CLAUDE_CODE)
	if not await _controller.call(&"start", profile):
		failures.append("no arrancó Claude: %s" % _model.get(&"failure_message"))
		return
	_model.call(&"set_harness_mode", SessionModel.HarnessMode.ASK)
	await _until(func() -> bool: return str(_model.get(&"current_agent_mode")) == "plan", "Claude no pasó a plan al elegir Preguntar")
	var path := ProjectSettings.globalize_path(CLAUDE_TARGET)
	_dock.call(&"send_text", "Plan this small change, don't implement it yet: add a jump counter to the ship in %s (count each press of ui_accept in a `jumps` variable and print it). Read only that file, nothing else. Keep the plan to 3 short steps, then present it for approval." % path)
	var view: Control = await _wait_view_for(PLAN_VIEW_SCRIPT, 1, CLAUDE_WAIT_MS)
	if view == null:
		failures.append("Claude no presentó un plan con su tarjeta en %d s" % (CLAUDE_WAIT_MS / 1000))
		_dump()
		return
	var request: Object = view.get(&"entry").get(&"permission")
	print("[claude-plan] plan 1 (%d líneas), opciones %s" % [str(request.get(&"plan_text")).count("\n") + 1, (request.get(&"options") as Array).map(func(o: Dictionary) -> String: return o.optionId)])
	await _shot("claude_card")
	_button(view, I18n.t("Edit")).pressed.emit()
	await _tree.process_frame
	var editor: CodeEdit = view.get(&"_editor")
	editor.text = editor.text.strip_edges() + "\n\nAlso: reset `jumps` to 0 when the ship wraps around the screen edge."
	editor.text_changed.emit()
	(view.get(&"_send_edit") as Button).pressed.emit()
	var edit_entry: Object = await _wait_user_entry_for(HarnessPrompts.PLAN_EDIT, CLAUDE_WAIT_MS)
	_expect(edit_entry != null, "lo editado salió como prompt PLAN_EDIT tras el turno cancelled (stop %s)" % _model.get(&"last_stop_reason"))
	view = await _wait_view_for(PLAN_VIEW_SCRIPT, 2, CLAUDE_WAIT_MS)
	if view == null:
		failures.append("Claude no volvió a presentar el plan")
		_dump()
		return
	request = view.get(&"entry").get(&"permission")
	_expect(str(request.get(&"plan_text")).to_lower().contains("wrap"), "el plan nuevo incluye el cambio editado")
	var set_modes_before := _log_count("session/set_mode")
	var requests: Array = []
	_model.connect(&"permission_requested", func(r: Object) -> void: requests.append(r))
	_button(view, I18n.t("Approve and build")).pressed.emit()
	await _tree.process_frame
	_expect(int(_model.get(&"harness_mode")) == SessionModel.HarnessMode.BUILD, "aprobar pasa a Construir")
	await _until_for(func() -> bool: return not requests.is_empty() or not bool(_model.call(&"is_busy")), "Claude no pidió editar después de aprobar", CLAUDE_WAIT_MS)
	print("[claude-plan] modo del agente: %s · set_mode desde que se aprobó: %d" % [_model.get(&"current_agent_mode"), _log_count("session/set_mode") - set_modes_before])
	_expect(str(_model.get(&"current_agent_mode")) == "default", "Claude quedó en default (%s)" % _model.get(&"current_agent_mode"))
	_expect(_log_count("session/set_mode") == set_modes_before, "sin session/set_mode al aprobar")
	if requests.is_empty():
		failures.append("no hubo pedido de edición (¿escribió sin preguntar?): archivo cambiado %s" % (FileAccess.get_file_as_string(CLAUDE_TARGET) != source))
		_dump()
		return
	var edit: Object = requests[0]
	print("[claude-plan] primera tarjeta: %s · grupo %s" % [edit.get(&"title"), edit.get(&"group")])
	_expect(str(edit.get(&"group")) == "edit_files", "la primera edición es del grupo edit_files (%s)" % edit.get(&"group"))
	_expect(_log_count("denied in") == 0, "nada se denegó por la matriz")
	await _shot("claude_edit_card")
	edit.call(&"deny_with_reason", "call the variable jump_count instead of jumps")
	var reason_entry: Object = await _wait_user_entry_for(HarnessPrompts.DENY_REASON, CLAUDE_WAIT_MS)
	_expect(reason_entry != null, "el motivo salió como prompt DENY_REASON (stop %s)" % _model.get(&"last_stop_reason"))
	var agent_before := _agent_texts().size()
	var cards_before := requests.size()
	await _until_for(func() -> bool: return requests.size() > cards_before or _agent_texts().size() > agent_before, "Claude no siguió después del motivo", CLAUDE_WAIT_MS)
	if requests.size() > cards_before:
		print("[claude-plan] siguió con: %s" % requests[-1].get(&"title"))
	_expect(FileAccess.get_file_as_string(CLAUDE_TARGET) == source, "nada se escribió sin permiso")
	_dump()
	if bool(_model.call(&"is_busy")):
		_controller.call(&"cancel")  # cortar apenas se vio, para no gastar


## m11-58 con Antigravity (antigravity-acp del registro de ACP, sin modo plan; gasta tokens):
## Planificar con un pedido chico → el agente termina con un bloque ```plan → tarjeta → Aprobar →
## pasa a Construir y sale PLAN_APPROVED. Corta apenas el agente empieza a construir.
func run_antigravity(tree: SceneTree, dock: Control, shot_prefix: String = "") -> PackedStringArray:
	_tree = tree
	_dock = dock
	_shot_prefix = shot_prefix
	_model = dock.get(&"_model")
	_controller = dock.get(&"_controller")
	var command := _antigravity_command()
	if command.is_empty():
		return PackedStringArray(["antigravity-acp no está instalado (registro de ACP)"])
	var plans_dir := ProjectSettings.globalize_path("res://").path_join(PlanStore.DIR)
	var before := _plan_files(plans_dir)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(CLAUDE_TARGET.get_base_dir()))
	var source := FileAccess.get_file_as_string("res://tests/docs_demo/player.gd")
	var file := FileAccess.open(CLAUDE_TARGET, FileAccess.WRITE)
	file.store_string(source)
	file.close()
	await _run_antigravity(command, source)
	for name: String in _plan_files(plans_dir):
		if not name in before:
			print("[agy-plan] plan guardado: %s" % name)
			DirAccess.remove_absolute(plans_dir.path_join(name))
	_controller.call(&"stop")
	return failures


## El servidor ACP de la versión más nueva que bajó el registro, o "".
static func _antigravity_command() -> String:
	var root := EditorInterface.get_editor_paths().get_data_dir().path_join("godot_agent/agents/antigravity-acp")
	var versions := Array(DirAccess.get_directories_at(root))
	versions.sort_custom(func(a: String, b: String) -> bool: return a.naturalnocasecmp_to(b) < 0)
	if versions.is_empty():
		return ""
	var command := root.path_join(versions[-1]).path_join("agy_acp_server.par")
	return command if FileAccess.file_exists(command) else ""


func _run_antigravity(command: String, source: String) -> void:
	var profile := AgentProfile.from_dict({"id": "antigravity-acp", "display_name": "Google Antigravity", "command": command, "args": []})
	if not await _controller.call(&"start", profile):
		failures.append("no arrancó Antigravity: %s" % _model.get(&"failure_message"))
		return
	var modes: Array = (_model.get(&"agent_modes") as Array).map(func(m: Variant) -> String: return str(m.get("id", "")) if m is Dictionary else "")
	print("[agy-plan] modos del agente: %s · modo plan propio: %s" % [modes, _controller.call(&"agent_has_plan_mode")])
	_model.call(&"set_harness_mode", SessionModel.HarnessMode.BUILD)
	await _tree.process_frame
	var composer: Control = _dock.get(&"_composer")
	var plan_button: Button = composer.find_child("PlanButton", true, false)
	if plan_button == null or not plan_button.is_visible_in_tree():
		failures.append("«Planificar» no está visible con la sesión libre")
		return
	var path := ProjectSettings.globalize_path(CLAUDE_TARGET)
	composer.call(&"insert_text", "add a jump counter to the ship in %s (count each press of ui_accept in a `jumps` variable and print it). Read only that file, nothing else. Keep the plan short: 3 tasks at most." % path)
	var requests: Array = []
	_model.connect(&"permission_requested", func(r: Object) -> void:
		requests.append(r)
		print("[agy-plan] tarjeta: %s · grupo %s · plan %s" % [r.get(&"title"), r.get(&"group"), r.call(&"is_plan")]))
	plan_button.pressed.emit()
	var view: Control = await _wait_view_for(PLAN_VIEW_SCRIPT, 1, CLAUDE_WAIT_MS)
	if view == null:
		failures.append("Antigravity no dejó un bloque ```plan que se volviera tarjeta en %d s (stop %s)" % [CLAUDE_WAIT_MS / 1000, _model.get(&"last_stop_reason")])
		_dump_as("agy-plan")
		return
	var request: Object = view.get(&"entry").get(&"permission")
	print("[agy-plan] tarjeta del plan: bloque %s · %d líneas · línea plegada en el mensaje %d" % [request.get(&"from_block"), str(request.get(&"plan_text")).count("\n") + 1, _plan_lines()])
	print("[agy-plan] plan:\n" + str(request.get(&"plan_text")))
	_expect(bool(request.get(&"from_block")), "la tarjeta viene del bloque ```plan")
	_expect(int(_model.get(&"harness_mode")) == SessionModel.HarnessMode.ASK, "planeó en Preguntar")
	_expect(FileAccess.get_file_as_string(CLAUDE_TARGET) == source, "no tocó el archivo mientras planeaba")
	await _shot("agy_card")
	_button(view, I18n.t("Approve and build")).pressed.emit()
	var approved: Object = await _wait_user_entry(HarnessPrompts.PLAN_APPROVED)
	_expect(approved != null, "aprobar mandó PLAN_APPROVED")
	_expect(int(_model.get(&"harness_mode")) == SessionModel.HarnessMode.BUILD, "aprobar pasó a Construir")
	var cards_before := requests.size()
	var agent_before := _agent_texts().size()
	await _until_for(func() -> bool: return requests.size() > cards_before or (_model.get(&"plan") as Array).size() > 0 or not bool(_model.call(&"is_busy")), "Antigravity no empezó a construir", CLAUDE_WAIT_MS)
	print("[agy-plan] al construir: tarjetas nuevas %d · tareas en su plan %d · ocupado %s" % [requests.size() - cards_before, (_model.get(&"plan") as Array).size(), _model.call(&"is_busy")])
	if requests.size() > cards_before:
		var edit: Object = requests[-1]
		print("[agy-plan] primera tarjeta al construir: %s · grupo %s" % [edit.get(&"title"), edit.get(&"group")])
		if edit.call(&"is_pending"):
			edit.call(&"select", edit.call(&"option_id_for", PackedStringArray(["reject_once", "reject_always"])))
	_dump_as("agy-plan")
	if bool(_model.call(&"is_busy")):
		_controller.call(&"cancel")  # cortar apenas se vio, para no gastar
		await _until(func() -> bool: return not bool(_model.call(&"is_busy")), "no se cortó el turno")


func _dump_as(tag: String) -> void:
	for entry: Object in _model.call(&"entries"):
		var kind := int(entry.get(&"kind"))
		if kind in [0, 1, 7]:
			print("[%s] %s: %s" % [tag, {0: "user", 1: "agent", 7: "notice"}[kind], str(entry.get(&"harness_label")) + " " + str(entry.get(&"text")).left(400).replace("\n", " ")])


func _dump() -> void:
	for entry: Object in _model.call(&"entries"):
		var kind := int(entry.get(&"kind"))
		if kind in [0, 1, 7]:
			print("[claude-plan] %s: %s" % [{0: "user", 1: "agent", 7: "notice"}[kind], str(entry.get(&"harness_label")) + " " + str(entry.get(&"text")).left(240).replace("\n", " ")])


func _agent_texts() -> Array:
	return (_model.call(&"entries") as Array).filter(func(e: Object) -> bool: return int(e.get(&"kind")) == 1)


func _until_for(condition: Callable, failure: String, wait_ms: int) -> bool:
	var deadline := Time.get_ticks_msec() + wait_ms
	while not condition.call() and Time.get_ticks_msec() < deadline:
		await _tree.process_frame
	if not condition.call():
		failures.append(failure)
		return false
	return true


func _wait_view_for(script_path: String, n: int, wait_ms: int) -> Control:
	var deadline := Time.get_ticks_msec() + wait_ms
	while Time.get_ticks_msec() < deadline:
		var found := _views(script_path)
		if found.size() >= n:
			await _tree.process_frame
			return found[n - 1]
		await _tree.create_timer(0.2).timeout
	return null


func _wait_user_entry_for(label: String, wait_ms: int) -> Object:
	var deadline := Time.get_ticks_msec() + wait_ms
	while Time.get_ticks_msec() < deadline:
		var entry := _user_entry(label)
		if entry:
			return entry
		await _tree.create_timer(0.2).timeout
	return null


func _expect(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)


func _until(condition: Callable, failure: String) -> bool:
	var deadline := Time.get_ticks_msec() + WAIT_MS
	while not condition.call() and Time.get_ticks_msec() < deadline:
		await _tree.process_frame
	if not condition.call():
		failures.append(failure)
		return false
	return true


## La `n`-ésima vista con ese script (1 = la primera) cuando aparece, o null.
func _wait_view(script_path: String, n: int) -> Control:
	var deadline := Time.get_ticks_msec() + WAIT_MS
	while Time.get_ticks_msec() < deadline:
		var found := _views(script_path)
		if found.size() >= n:
			await _tree.process_frame
			return found[n - 1]
		await _tree.process_frame
	return null


func _views(script_path: String) -> Array[Control]:
	var result: Array[Control] = []
	var stack: Array[Node] = [_dock]
	while not stack.is_empty():
		var node: Node = stack.pop_front()
		var script: Script = node.get_script()
		if script and script.resource_path == script_path and not node.is_queued_for_deletion():
			result.append(node)
		stack.append_array(node.get_children())
	result.sort_custom(func(a: Control, b: Control) -> bool: return int(a.get(&"entry").get(&"id")) < int(b.get(&"entry").get(&"id")))
	return result


func _button_texts(root: Node) -> Array:
	return root.find_children("*", "Button", true, false).filter(func(b: Button) -> bool: return b.is_visible_in_tree()).map(func(b: Button) -> String: return b.text)


func _button(root: Node, text: String) -> Button:
	for button: Button in root.find_children("*", "Button", true, false):
		if button.text == text and button.is_visible_in_tree():
			return button
	failures.append("no está el botón «%s»" % text)
	return Button.new()


func _user_entry(label: String) -> Object:
	for entry: Object in _model.call(&"entries"):
		if int(entry.get(&"kind")) == 0 and str(entry.get(&"harness_label")) == label:
			return entry
	return null


func _wait_user_entry(label: String) -> Object:
	var deadline := Time.get_ticks_msec() + WAIT_MS
	while Time.get_ticks_msec() < deadline:
		var entry := _user_entry(label)
		if entry:
			return entry
		await _tree.process_frame
	return null


func _current_model() -> String:
	return str((_model.call(&"model_option") as Dictionary).get("currentValue", ""))


func _notice_with(text: String) -> Object:
	for entry: Object in _model.call(&"entries"):
		if int(entry.get(&"kind")) == 7 and str(entry.get(&"text")).contains(text):
			return entry
	return null


## Los set_config_option que recibió el agente falso con ese modelo.
func _fake_count(value: String) -> int:
	var log: Object = _controller.get(&"agent_log")
	return (log.call(&"entries") as Array).filter(func(entry: Dictionary) -> bool:
		return str(entry.message).contains("fake_agent: set_config_option") and str(entry.message).contains("\"value\":\"%s\"" % value)).size()


func _log_count(text: String) -> int:
	var log: Object = _controller.get(&"agent_log")
	return (log.call(&"entries") as Array).filter(func(entry: Dictionary) -> bool: return str(entry.message).contains(text)).size()


static func _plan_files(dir: String) -> PackedStringArray:
	return DirAccess.get_files_at(dir) if DirAccess.dir_exists_absolute(dir) else PackedStringArray()


func _shot(name: String) -> void:
	if _shot_prefix.is_empty():
		return
	await _tree.create_timer(0.3).timeout
	EditorInterface.get_base_control().get_viewport().get_texture().get_image().save_png("%s_%s.png" % [_shot_prefix, name])
