@tool
extends Node
## Loop del One-shot (spec §10 y §10.1):
## - prompt inicial con el objetivo, el plan, los checks y la verificación con run_scene;
## - checkpoint git antes de cada tarea del plan (cuando una entrada pasa a in_progress);
## - presupuestos de tiempo, tokens y playtests: aviso al 80 %, cierre con reporte al 100 %;
## - "Guiar al agente" se encola para el fin del turno;
## - cuota del plan: pausa en el próximo checkpoint, "limitado" con cpN-quota y reanudación.
## La UI (pantalla Agent) solo lee el estado y llama a los métodos públicos.

signal changed
signal activity_added(entry: Dictionary)

const SessionController := preload("../session/session_controller.gd")
const SessionModel := preload("../session/session_model.gd")
const ChatEntry := preload("../session/chat_entry.gd")
const ToolCall := preload("../session/tool_call.gd")
const QuotaMonitor := preload("../core/quota_monitor.gd")
const GitCheckpoints := preload("git_checkpoints.gd")
const FindingsParser := preload("../review/findings_parser.gd")

enum Phase { IDLE, PREPARING, RUNNING, PAUSED, PAUSED_QUOTA, LIMITED, WAITING_CONFIRM, CLOSING, FINISHED }

const PHASE_LABELS: Dictionary = {
	Phase.IDLE: "Sin iniciar",
	Phase.PREPARING: "Preparando",
	Phase.RUNNING: "En curso",
	Phase.PAUSED: "Pausado",
	Phase.PAUSED_QUOTA: "Pausado por cuota",
	Phase.LIMITED: "Limitado",
	Phase.WAITING_CONFIRM: "Listo para retomar",
	Phase.CLOSING: "Cerrando",
	Phase.FINISHED: "Terminado",
}
const BUDGET_TIME := "time"
const BUDGET_TOKENS := "tokens"
const BUDGET_PLAYTESTS := "playtests"
const BUDGET_LABELS: Dictionary = {BUDGET_TIME: "Tiempo", BUDGET_TOKENS: "Tokens", BUDGET_PLAYTESTS: "Playtests"}
const WARN_RATIO := 0.8
## Turnos seguidos que terminan sin avance en el plan antes de dar el One-shot por terminado.
const MAX_IDLE_CONTINUES := 3
const ACTIVITY_LINE_CHARS := 140
const ACTIVITY_LIMIT := 400
## Sin hora de reinicio en una pausa por cuota, se reintenta cada tanto.
const PAUSE_RETRY_S := 3600
const TICK_S := 0.5

var controller: SessionController
var model: SessionModel
var quota: QuotaMonitor
var git: GitCheckpoints
## (rutas relativas al proyecto) -> void: recarga del editor después de "Volver acá".
var after_restore: Callable
## () -> bool (await): abre una sesión nueva si la anterior se perdió.
var restart_session: Callable
## Retomar solo al reiniciarse la cuota (Settings) o esperar confirmación.
var resume_auto: bool = true

var phase: Phase = Phase.IDLE
var goal: String = ""
## {time: minutos, tokens, playtests}; 0 = sin límite.
var budgets: Dictionary = {BUDGET_TIME: 45, BUDGET_TOKENS: 1500000, BUDGET_PLAYTESTS: 8}
var used: Dictionary = {BUDGET_TIME: 0.0, BUDGET_TOKENS: 0, BUDGET_PLAYTESTS: 0}
var checkpoints_enabled: bool = false
var checks: Array[Dictionary] = []
var activity: Array[Dictionary] = []
var last_capture: Image
var last_capture_caption: String = ""
var finish_reason: String = ""
## Tarea en la que hay que retomar (pausa, límite o "Volver acá").
var resume_task: String = ""
## Fin de la pausa por cuota (unix; 0 = sin hora).
var quota_resume_at: int = 0

var _started_msec: int = 0
var _turn_running: bool = false
var _guidance: Array[String] = []
var _warned: Dictionary = {}
var _current_task: int = -1
var _plan_progress: int = 0
var _idle_continues: int = 0
var _counted_playtests: Dictionary = {}
var _captured_calls: Dictionary = {}
var _git_queue: Array[Callable] = []
var _git_busy: bool = false
var _close_reason: String = ""
## Ya se creó el cpN-quota de este límite (los reintentos fallidos no crean otro).
var _quota_checkpoint_done: bool = false
var _timer: Timer


func setup(session_controller: SessionController, project_root: String) -> void:
	controller = session_controller
	model = controller.model
	quota = controller.quota
	git = GitCheckpoints.new(project_root)


func _ready() -> void:
	_timer = Timer.new()
	_timer.wait_time = TICK_S
	_timer.timeout.connect(_tick)
	add_child(_timer)
	model.plan_changed.connect(_on_plan_changed)
	model.tool_call_changed.connect(_on_tool_call_changed)


func is_active() -> bool:
	return not phase in [Phase.IDLE, Phase.FINISHED]


## Hay una operación git en curso (un checkpoint se crea en segundo plano).
func is_git_busy() -> bool:
	return _git_busy


func phase_label() -> String:
	return PHASE_LABELS[phase]


## Fase "n de m" según el plan, o "".
func plan_position() -> String:
	if model.plan.is_empty():
		return ""
	var index := _current_task if _current_task >= 0 else _completed_count()
	return "fase %d de %d" % [mini(index + 1, model.plan.size()), model.plan.size()]


func budget_ratio(budget: String) -> float:
	var limit := float(budgets.get(budget, 0))
	if limit <= 0.0:
		return 0.0
	var value := float(used[budget]) / 60.0 if budget == BUDGET_TIME else float(used[budget])
	return value / limit


# --- inicio --------------------------------------------------------------------------------------

## Valida git: {ok, needs_wip_confirm, warning}. La UI pide confirmación del WIP y llama a start().
func preflight(use_checkpoints: bool) -> Dictionary:
	if not use_checkpoints:
		return {"ok": true, "needs_wip_confirm": false, "warning": ""}
	if not await git.check_available():
		return {"ok": true, "needs_wip_confirm": false, "warning": git.last_error}
	return {"ok": true, "needs_wip_confirm": not await git.is_clean(), "warning": ""}


func start(goal_text: String, budget_values: Dictionary, use_checkpoints: bool) -> bool:
	if is_active():
		return false
	goal = goal_text.strip_edges()
	budgets.merge(budget_values, true)
	used = {BUDGET_TIME: 0.0, BUDGET_TOKENS: 0, BUDGET_PLAYTESTS: 0}
	checks.clear()
	activity.clear()
	_guidance.clear()
	_warned.clear()
	_counted_playtests.clear()
	_captured_calls.clear()
	_current_task = -1
	_idle_continues = 0
	_close_reason = ""
	_quota_checkpoint_done = false
	finish_reason = ""
	resume_task = ""
	last_capture = null
	_started_msec = Time.get_ticks_msec()
	_set_phase(Phase.PREPARING)
	checkpoints_enabled = false
	if use_checkpoints:
		if await git.check_available():
			checkpoints_enabled = await git.start()
			if checkpoints_enabled:
				_add_activity("checkpoint", "Rama %s · %s %s" % [git.agent_branch, git.checkpoints[0].name, git.checkpoints[0].label])
			else:
				_add_activity("aviso", git.last_error)
		else:
			_add_activity("aviso", git.last_error)
	if not controller.is_connected_to_agent() and not await _restart_session():
		_finish("No se pudo abrir una sesión con el agente.")
		return false
	model.set_harness_mode(SessionModel.HarnessMode.ONESHOT)
	_set_phase(Phase.RUNNING)
	_timer.start()
	_run_turn(initial_prompt())
	return true


func initial_prompt() -> String:
	var limits: PackedStringArray = []
	if int(budgets[BUDGET_TIME]) > 0:
		limits.append("%d min" % budgets[BUDGET_TIME])
	if int(budgets[BUDGET_TOKENS]) > 0:
		limits.append("%d tokens" % budgets[BUDGET_TOKENS])
	if int(budgets[BUDGET_PLAYTESTS]) > 0:
		limits.append("%d playtests" % budgets[BUDGET_PLAYTESTS])
	return "\n".join([
		"Objetivo (modo One-shot): %s" % goal,
		"",
		"Trabajá de forma autónoma hasta cumplir el objetivo:",
		"1. Armá primero un plan con tu herramienta de plan o de tareas (por ejemplo TodoWrite o TaskCreate/TaskUpdate), una entrada por tarea. Marcá cada tarea in_progress al empezarla y completed al terminarla: el harness ve el plan y crea un checkpoint git antes de cada tarea.",
		"2. Después de cada tarea, verificá con godot.run_scene (con inputs si hace falta), godot.capture_game_frame y godot.get_errors.",
		"3. Al terminar cada tarea, reportá las verificaciones vigentes en un bloque ```json {\"checks\":[{\"label\":\"…\",\"status\":\"pass|fail|pending\"}]}.",
		"4. Presupuestos: %s. Si te acercás al límite, priorizá dejar algo jugable." % (", ".join(limits) if not limits.is_empty() else "sin límite"),
		"No hagas commits ni cambies de rama: los checkpoints git los maneja el harness.",
	])


# --- controles -----------------------------------------------------------------------------------

func pause() -> void:
	if phase != Phase.RUNNING:
		return
	resume_task = _task_name(_current_task)
	_set_phase(Phase.PAUSED)
	_add_activity("estado", "Pausado por el usuario")
	if _turn_running:
		controller.cancel()


func resume() -> void:
	if not phase in [Phase.PAUSED, Phase.PAUSED_QUOTA, Phase.LIMITED, Phase.WAITING_CONFIRM]:
		return
	var was_limited := phase == Phase.LIMITED or quota.is_limited()
	_set_phase(Phase.RUNNING)
	if was_limited:
		quota.note_retry()
	if not controller.is_connected_to_agent():
		_add_activity("sesión", "La sesión se perdió: se abre una nueva con el resumen del plan")
		if not await _restart_session():
			_finish("No se pudo reabrir la sesión con el agente.")
			return
		model.set_harness_mode(SessionModel.HarnessMode.ONESHOT)
		_run_turn(_summary_prompt())
		return
	_run_turn(_resume_prompt())


func stop() -> void:
	if not is_active():
		return
	if _turn_running:
		controller.cancel()
	_finish("Detenido por el usuario.")


## "Guiar al agente": se manda al terminar el turno actual (o ya, si no hay turno en curso).
func guide(text: String) -> void:
	text = text.strip_edges()
	if text.is_empty() or not is_active():
		return
	_add_activity("guía", text)
	if _turn_running or phase in [Phase.PREPARING, Phase.CLOSING, Phase.LIMITED]:
		_guidance.append(text)
		changed.emit()
		return
	if phase in [Phase.PAUSED, Phase.PAUSED_QUOTA, Phase.WAITING_CONFIRM]:
		_set_phase(Phase.RUNNING)
	_run_turn(text)


## El usuario editó el plan: se manda como guía.
func edit_plan(lines: PackedStringArray) -> void:
	var items: PackedStringArray = []
	for i in lines.size():
		if not lines[i].strip_edges().is_empty():
			items.append("%d. %s" % [items.size() + 1, lines[i].strip_edges()])
	if not items.is_empty():
		guide("Actualicé el plan; seguí con este (releelo y actualizá tu herramienta de plan):\n" + "\n".join(items))


## "Volver acá": pausa, restaura el checkpoint y recarga el editor. Devuelve "" o el error.
func restore(checkpoint_entry: Dictionary) -> String:
	if not checkpoints_enabled:
		return "Los checkpoints están desactivados."
	if _turn_running:
		resume_task = str(checkpoint_entry.get("label", ""))
		_set_phase(Phase.PAUSED)
		controller.cancel()
		while _turn_running:
			await get_tree().process_frame
	var changed_paths: Variant = await _git(func() -> Variant: return await git.restore(checkpoint_entry))
	if changed_paths == null:
		return git.last_error
	if after_restore.is_valid():
		after_restore.call(changed_paths)
	resume_task = str(checkpoint_entry.get("label", ""))
	_add_activity("checkpoint", "Volvió a %s (%s) · %d archivos" % [checkpoint_entry.name, checkpoint_entry.label, (changed_paths as PackedStringArray).size()])
	if is_active():
		_set_phase(Phase.PAUSED)
	changed.emit()
	return ""


## "Aceptar todo": commit final en la rama del agente; el merge lo hace el usuario.
func accept_all() -> String:
	if not checkpoints_enabled:
		return "Los checkpoints están desactivados: no hay rama del agente."
	if _turn_running:
		controller.cancel()
	var ok: bool = await _git(func() -> Variant: return await git.accept(goal))
	if not ok:
		return git.last_error
	_add_activity("checkpoint", "La rama %s quedó lista para merge (el harness no hace merge ni push)" % git.agent_branch)
	_finish("Cambios aceptados en %s." % git.agent_branch)
	return ""


func changes_summary() -> Dictionary:
	if not checkpoints_enabled:
		return {}
	return await _git(func() -> Variant: return await git.changes_summary())


# --- turnos --------------------------------------------------------------------------------------

func _run_turn(text: String) -> void:
	if _turn_running:
		_guidance.append(text)
		return
	_turn_running = true
	var first_entry := model.entries().size()
	var progress_before := _completed_count() + int(used[BUDGET_PLAYTESTS])
	var reason: String = await controller.send_in_mode(SessionModel.HarnessMode.ONESHOT, text)
	_turn_running = false
	if not is_instance_valid(self) or not is_inside_tree():
		return
	_account_tokens(controller.last_turn_usage)
	var turn_text := controller.agent_text_since(first_entry)
	_merge_checks(FindingsParser.parse(turn_text).checks)
	var summary := _summary_of(turn_text)
	if not summary.is_empty():
		_add_activity("agente", summary)
	if _completed_count() + int(used[BUDGET_PLAYTESTS]) > progress_before:
		_idle_continues = 0
	if reason == "end_turn":
		_quota_checkpoint_done = false
	await _after_turn(reason)


func _after_turn(reason: String) -> void:
	match phase:
		Phase.CLOSING:
			_finish(_close_reason if not _close_reason.is_empty() else "Terminado.")
			return
		Phase.FINISHED, Phase.PAUSED, Phase.PAUSED_QUOTA, Phase.WAITING_CONFIRM, Phase.IDLE:
			return
	if quota.is_limited():
		await _enter_limited()
		return
	if reason.is_empty():  # no se pudo mandar: la sesión no estaba lista
		resume_task = _task_name(_current_task)
		_set_phase(Phase.PAUSED)
		_add_activity("sesión", "El agente no estaba listo para otro turno: retomá cuando quieras")
		return
	if reason == "error" and not controller.is_connected_to_agent():
		resume_task = _task_name(_current_task)
		_set_phase(Phase.PAUSED)
		_add_activity("sesión", "El agente se cerró: retomá cuando quieras (se abre una sesión nueva con el resumen)")
		return
	if not _close_reason.is_empty():
		_close()
		return
	if not _guidance.is_empty():
		_run_turn(_guidance.pop_front())
		return
	if reason == "cancelled":
		return
	if model.plan.is_empty():
		_after_turn_without_plan()
		return
	if _plan_pending() and _idle_continues < MAX_IDLE_CONTINUES:
		_idle_continues += 1
		_run_turn("Seguí con el plan: la próxima tarea pendiente es «%s». Verificá con run_scene, capture_game_frame y get_errors, y reportá el bloque de checks." % _task_name(_next_pending()))
		return
	_finish("El agente terminó el plan." if not _plan_pending() else "El agente dejó de avanzar con el plan.")


## Sin plan, lo que falta sale de los checks: el agente a veces cierra el turno a mitad de camino
## ("pruebo si add_node acepta…"). Termina cuando todos pasan o cuando deja de avanzar.
func _after_turn_without_plan() -> void:
	var open: PackedStringArray = []
	for check: Dictionary in checks:
		if check.status != "pass":
			open.append("«%s» (%s)" % [check.label, check.status])
	if not checks.is_empty() and open.is_empty():
		_finish("El agente terminó: todos los checks pasan.")
		return
	if _idle_continues >= MAX_IDLE_CONTINUES:
		_finish("El agente dejó de avanzar (sin plan; quedan checks sin pasar)." if not open.is_empty() else "El agente terminó sin reportar checks.")
		return
	_idle_continues += 1
	if open.is_empty():
		_run_turn("Si falta algo del objetivo, seguí. Si está terminado, verificalo con run_scene y capture_game_frame y reportá el bloque de checks.")
	else:
		_run_turn("Seguí con el objetivo: quedan checks sin pasar: %s. Verificá con run_scene, capture_game_frame y get_errors, y reportá el bloque de checks." % ", ".join(open))


func _close() -> void:
	_set_phase(Phase.CLOSING)
	_add_activity("presupuesto", _close_reason)
	_run_turn("%s No sigas con el plan: escribí el reporte final (qué quedó hecho, qué falta y cómo probarlo) y el bloque de checks." % _close_reason)


func _finish(reason: String) -> void:
	finish_reason = reason
	_timer.stop()
	_set_phase(Phase.FINISHED)
	_add_activity("estado", reason)


func _restart_session() -> bool:
	if not restart_session.is_valid():
		return false
	return await restart_session.call()


func _resume_prompt() -> String:
	var task := resume_task if not resume_task.is_empty() else _task_name(_next_pending())
	var last := git.checkpoints.back() if checkpoints_enabled and not git.checkpoints.is_empty() else {}
	var where := "" if last.is_empty() else "; el estado está en el checkpoint %s (%s)" % [last.name, last.label]
	if task.is_empty():
		return "Continuá con el objetivo desde donde quedaste%s." % where
	return "Continuá con el plan desde la tarea «%s»%s." % [task, where]


func _summary_prompt() -> String:
	var lines: PackedStringArray = ["Retomamos un One-shot que se interrumpió.", "", initial_prompt(), "", "Plan hasta ahora:"]
	for entry: Variant in model.plan:
		if entry is Dictionary:
			lines.append("- [%s] %s" % [entry.get("status", "pending"), entry.get("content", "")])
	if not checks.is_empty():
		lines.append("Checks:")
		for check: Dictionary in checks:
			lines.append("- [%s] %s" % [check.status, check.label])
	if checkpoints_enabled:
		lines.append("Checkpoints: " + ", ".join(git.checkpoints.map(func(cp: Dictionary) -> String: return "%s %s" % [cp.name, cp.label])))
	lines.append("")
	lines.append(_resume_prompt())
	return "\n".join(lines)


# --- plan, tool calls y checks --------------------------------------------------------------------

func _on_plan_changed(plan: Array) -> void:
	if not is_active():
		return
	var in_progress := -1
	for i in plan.size():
		if plan[i] is Dictionary and str(plan[i].get("status", "")) == "in_progress":
			in_progress = i
			break
	if in_progress >= 0 and in_progress != _current_task:
		var previous := _current_task
		_current_task = in_progress
		var task := _task_name(in_progress)
		_add_activity("plan", "Tarea %d: %s" % [in_progress + 1, task])
		if phase == Phase.RUNNING and quota.state == QuotaMonitor.State.PAUSE_SCHEDULED and previous >= 0:
			_pause_for_quota(task)
		elif checkpoints_enabled:
			_checkpoint(task)
	changed.emit()


func _on_tool_call_changed(call: ToolCall, _group: ChatEntry) -> void:
	if not is_active() or not call.is_finished():
		return
	var name := call.godot_tool_name()
	if name == "run_scene" and call.status == ToolCall.STATUS_COMPLETED and not _counted_playtests.has(call.id):
		_counted_playtests[call.id] = true
		used[BUDGET_PLAYTESTS] = int(used[BUDGET_PLAYTESTS]) + 1
		_add_activity("playtest", "Playtest #%d · %s" % [used[BUDGET_PLAYTESTS], _call_summary(call)])
		# Sin plan no hay tareas que marquen los checkpoints: se crea uno por playtest (D24).
		if model.plan.is_empty() and checkpoints_enabled:
			_checkpoint("Playtest #%d" % used[BUDGET_PLAYTESTS])
		_check_budgets()
	elif not name.is_empty() or call.status == ToolCall.STATUS_FAILED:
		_add_activity("tool", _one_line("%s · %s" % [call.display_name(), _call_summary(call)]))
	if not _captured_calls.has(call.id):
		for block: Variant in call.content:
			var inner: Variant = block.get("content") if block is Dictionary else null
			if inner is Dictionary and str(inner.get("type", "")) == "image":
				var image := _decode_image(str(inner.get("data", "")), str(inner.get("mimeType", "")))
				if image:
					_captured_calls[call.id] = true
					last_capture = image
					last_capture_caption = "Playtest #%d · %s" % [maxi(int(used[BUDGET_PLAYTESTS]), 1), _elapsed_text()]
					changed.emit()


func _merge_checks(new_checks: Array) -> void:
	for check: Dictionary in new_checks:
		var found := false
		for existing: Dictionary in checks:
			if existing.label == check.label:
				existing.merge(check, true)
				found = true
		if not found:
			checks.append(check)
	if not new_checks.is_empty():
		changed.emit()


func _account_tokens(usage: Dictionary) -> void:
	if usage.is_empty():
		return
	# Sin las lecturas de caché: cuestan una fracción y en una sesión larga dominarían la cuenta (D24).
	var tokens := int(usage.get("inputTokens", 0)) + int(usage.get("outputTokens", 0)) + int(usage.get("cachedWriteTokens", 0))
	used[BUDGET_TOKENS] = int(used[BUDGET_TOKENS]) + tokens
	_check_budgets()


# --- presupuestos y cuota ------------------------------------------------------------------------

func _tick() -> void:
	if phase in [Phase.RUNNING, Phase.CLOSING]:
		used[BUDGET_TIME] = float(used[BUDGET_TIME]) + TICK_S
		_check_budgets()
	match phase:
		Phase.LIMITED:
			if quota.retry_due():
				_on_quota_back("se reinició la ventana" if quota.limited_until > 0 else "toca un reintento")
		Phase.PAUSED_QUOTA:
			var now := int(Time.get_unix_time_from_system())
			if quota.state in [QuotaMonitor.State.NORMAL, QuotaMonitor.State.WARNING] or (quota_resume_at > 0 and now >= quota_resume_at):
				_on_quota_back("la cuota volvió a estar disponible")
	changed.emit()


func _check_budgets() -> void:
	if phase != Phase.RUNNING:
		return
	for budget: String in [BUDGET_TIME, BUDGET_TOKENS, BUDGET_PLAYTESTS]:
		var ratio := budget_ratio(budget)
		if ratio >= 1.0 and _close_reason.is_empty():
			_close_reason = "Se agotó el presupuesto de %s." % str(BUDGET_LABELS[budget]).to_lower()
			_add_activity("presupuesto", _close_reason)
			if _turn_running:
				controller.cancel()
			else:
				_close()
			return
		if ratio >= WARN_RATIO and not _warned.has(budget):
			_warned[budget] = true
			var text := "%s: %d %% del presupuesto." % [BUDGET_LABELS[budget], roundi(ratio * 100.0)]
			_add_activity("presupuesto", text)
			model.add_notice("One-shot · " + text, ChatEntry.Level.WARNING)


## Umbral de pausa (spec §10.1): no corta la tarea en curso; al empezar la siguiente se crea su
## checkpoint, se corta el turno y se espera a que se libere la cuota.
func _pause_for_quota(next_task: String) -> void:
	resume_task = next_task
	quota_resume_at = quota.pause_resets_at()
	if quota_resume_at <= 0:
		quota_resume_at = int(Time.get_unix_time_from_system()) + PAUSE_RETRY_S
	_set_phase(Phase.PAUSED_QUOTA)
	_add_activity("cuota", "Cuota al %d %%: pausa antes de «%s»" % [roundi(quota.max_utilization() * 100.0), next_task])
	if checkpoints_enabled:
		_checkpoint(next_task)
	if _turn_running:
		controller.cancel()


## Límite a mitad de turno: tool calls pendientes → cancelled, cpN-quota y "Limitado".
func _enter_limited() -> void:
	model.cancel_unfinished_tool_calls()
	resume_task = _task_name(_current_task) if _current_task >= 0 else _task_name(_next_pending())
	_set_phase(Phase.LIMITED)
	var until := "hasta las %s" % Time.get_time_string_from_unix_time(quota.limited_until + int(Time.get_time_zone_from_system().get("bias", 0)) * 60).left(5) if quota.limited_until > 0 else "sin hora de reinicio (reintentos 5, 10, 20 y cada 60 min)"
	_add_activity("cuota", "Límite del plan alcanzado %s" % until)
	if checkpoints_enabled and not _quota_checkpoint_done:
		_quota_checkpoint_done = true
		await _checkpoint(resume_task, "-quota")


func _on_quota_back(reason: String) -> void:
	_add_activity("cuota", "Cuota: %s" % reason)
	if resume_auto:
		resume()
	else:
		_set_phase(Phase.WAITING_CONFIRM)


# --- auxiliares ------------------------------------------------------------------------------------

func _checkpoint(label: String, suffix: String = "") -> void:
	var entry: Dictionary = await _git(func() -> Variant: return await git.checkpoint(label, suffix))
	if entry.is_empty():
		_add_activity("aviso", "No se pudo crear el checkpoint: " + git.last_error)
	else:
		_add_activity("checkpoint", "%s: %s" % [entry.name, entry.label])
	changed.emit()


## Las operaciones git van de a una, en orden.
func _git(operation: Callable) -> Variant:
	while _git_busy:
		await get_tree().process_frame
	_git_busy = true
	var result: Variant = await operation.call()
	_git_busy = false
	return result


func _set_phase(value: Phase) -> void:
	if phase == value:
		return
	phase = value
	changed.emit()


func _add_activity(kind: String, text: String) -> void:
	var entry := {"time": _elapsed_text(), "kind": kind, "text": text}
	activity.append(entry)
	if activity.size() > ACTIVITY_LIMIT:
		activity.remove_at(0)
	activity_added.emit(entry)


func _elapsed_text() -> String:
	var seconds := (Time.get_ticks_msec() - _started_msec) / 1000 if _started_msec > 0 else 0
	return "%02d:%02d:%02d" % [seconds / 3600, (seconds / 60) % 60, seconds % 60]


func _task_name(index: int) -> String:
	if index >= 0 and index < model.plan.size() and model.plan[index] is Dictionary:
		return str(model.plan[index].get("content", "tarea %d" % (index + 1)))
	return ""


func _completed_count() -> int:
	var count := 0
	for entry: Variant in model.plan:
		if entry is Dictionary and str(entry.get("status", "")) == "completed":
			count += 1
	return count


func _next_pending() -> int:
	for i in model.plan.size():
		if model.plan[i] is Dictionary and str(model.plan[i].get("status", "")) != "completed":
			return i
	return -1


func _plan_pending() -> bool:
	return _next_pending() >= 0


## Primer párrafo del texto del turno, sin los bloques de código (el JSON de checks va aparte).
static func _summary_of(text: String) -> String:
	var fences := RegEx.create_from_string("(?s)```.*?(```|$)")
	for paragraph: String in fences.sub(text, "", true).split("\n\n", false):
		var line := paragraph.strip_edges()
		if not line.is_empty():
			return line.left(240)
	return ""


## Los comandos de shell pueden traer heredocs enteros: en la actividad va solo la primera línea.
static func _one_line(text: String) -> String:
	var line := text.strip_edges().get_slice("\n", 0)
	var cut := line.length() > ACTIVITY_LINE_CHARS or text.strip_edges().contains("\n")
	return (line.left(ACTIVITY_LINE_CHARS) + "…") if cut else line


static func _call_summary(call: ToolCall) -> String:
	var input: Variant = call.raw_input
	if input is Dictionary:
		for key: String in ["scene", "path", "file_path", "node", "command"]:
			if input.has(key):
				return str(input[key]).get_file() if key in ["path", "file_path", "scene"] else str(input[key]).left(80)
	return call.status


static func _decode_image(data: String, mime_type: String) -> Image:
	if data.is_empty():
		return null
	var bytes := Marshalls.base64_to_raw(data)
	var image := Image.new()
	var error := ERR_FILE_UNRECOGNIZED
	match mime_type:
		"image/png":
			error = image.load_png_from_buffer(bytes)
		"image/jpeg", "image/jpg":
			error = image.load_jpg_from_buffer(bytes)
		"image/webp":
			error = image.load_webp_from_buffer(bytes)
	return image if error == OK and not image.is_empty() else null
