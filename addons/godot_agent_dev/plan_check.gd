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

const SessionModel := preload("res://addons/godot_agent/session/session_model.gd")
const AgentProfile := preload("res://addons/godot_agent/core/agent_profile.gd")
const HarnessPrompts := preload("res://addons/godot_agent/session/harness_prompts.gd")
const PlanStore := preload("res://addons/godot_agent/session/plan_store.gd")
const I18n := preload("res://addons/godot_agent/core/i18n.gd")
const PLAN_VIEW_SCRIPT := "res://addons/godot_agent/ui/dock/entries/plan_approval_view.gd"
const PERMISSION_VIEW_SCRIPT := "res://addons/godot_agent/ui/dock/entries/permission_view.gd"
const SCENARIO := "res://tests/scripts/plan_mode.json"
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


func run(tree: SceneTree, dock: Control, shot_prefix: String = "") -> PackedStringArray:
	_tree = tree
	_dock = dock
	_shot_prefix = shot_prefix
	_model = dock.get(&"_model")
	_controller = dock.get(&"_controller")
	var plans_dir := ProjectSettings.globalize_path("res://").path_join(PlanStore.DIR)
	var before := _plan_files(plans_dir)
	await _run()
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
	_model.call(&"set_harness_mode", SessionModel.HarnessMode.ASK)
	await _until(func() -> bool: return str(_model.get(&"current_agent_mode")) == "plan", "el agente no pasó a plan al elegir Preguntar")
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
	_button(view, I18n.t("Approve and build")).pressed.emit()
	await _tree.process_frame
	_expect(int(_model.get(&"harness_mode")) == SessionModel.HarnessMode.BUILD, "aprobar pasa a Construir")
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
