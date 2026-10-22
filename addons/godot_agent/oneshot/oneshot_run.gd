@tool
extends Node
## Loop del One-shot (spec §10 y §10.1):
## - prompt inicial con el objetivo, el plan, los checks y la verificación con run_scene;
## - checkpoint git antes de cada tarea del plan (cuando una entrada pasa a in_progress);
## - presupuestos de tiempo, tokens y playtests: aviso al 80 %, cierre con reporte al 100 %;
## - lo que el usuario escribe en el chat (guide) se encola para el fin del turno;
## - cuota del plan: pausa al terminar la tarea o el turno (con un tope de espera), "limitado" con cpN-quota y reanudación;
## - el estado se guarda en disco mientras corre (D37): si el editor se cierra o se cae, al volver
##   el run queda en pausa y «Retomar» reabre la sesión del agente.
## La UI (pantalla Agent) solo lee el estado y llama a los métodos públicos.

signal changed
signal activity_added(entry: Dictionary)
## Se cargó un run guardado (la UI rearma la actividad).
signal restored
## El informe del run terminado está listo (`last_report`).
signal report_ready

const SessionController := preload("../session/session_controller.gd")
const SessionModel := preload("../session/session_model.gd")
const ChatEntry := preload("../session/chat_entry.gd")
const ToolCall := preload("../session/tool_call.gd")
const QuotaMonitor := preload("../core/quota_monitor.gd")
const GitCheckpoints := preload("git_checkpoints.gd")
const FindingsParser := preload("../review/findings_parser.gd")
const OneShotStore := preload("oneshot_store.gd")
const LoopDetector := preload("loop_detector.gd")
const RunReport := preload("run_report.gd")
const GameCriteria := preload("game_criteria.gd")
const OneShotFiles := preload("oneshot_files.gd")

enum Phase { IDLE, PREPARING, RUNNING, PAUSED, PAUSED_QUOTA, LIMITED, WAITING_CONFIRM, CLOSING, FINISHED, SPEC_REVIEW }

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
	Phase.SPEC_REVIEW: "Spec para revisar",
}
const BUDGET_TIME := "time"
const BUDGET_TOKENS := "tokens"
const BUDGET_PLAYTESTS := "playtests"
const BUDGET_LABELS: Dictionary = {BUDGET_TIME: "Tiempo", BUDGET_TOKENS: "Tokens", BUDGET_PLAYTESTS: "Playtests"}
const WARN_RATIO := 0.8
const BUDGET_CLOSE_PREFIX := "Se agotó el presupuesto de "
## Turnos seguidos que terminan sin avance en el plan antes de dar el One-shot por terminado.
const MAX_IDLE_CONTINUES := 3
const ACTIVITY_LINE_CHARS := 140
const ACTIVITY_LIMIT := 400
## Sin hora de reinicio en una pausa por cuota, se reintenta cada tanto.
const PAUSE_RETRY_S := 3600
## Con la pausa por cuota programada, el run espera a que termine la tarea o el turno. Si eso no
## pasa en este tiempo, o la cuota llega a QUOTA_PAUSE_HARD, corta el turno y pausa igual.
const QUOTA_PAUSE_GRACE_S := 600
const QUOTA_PAUSE_HARD := 0.98
const TICK_S := 0.5
## Cada cuánto se guarda el run como mucho (además de en cada cambio de fase).
const SAVE_INTERVAL_MS := 2000

var controller: SessionController
var model: SessionModel
var quota: QuotaMonitor
var git: GitCheckpoints
## (rutas relativas al proyecto) -> void: recarga del editor después de "Volver acá".
var after_restore: Callable
## (id de la sesión perdida, o "") -> bool (await): reabre esa sesión con session/load si se puede;
## si no, abre una nueva.
var restart_session: Callable
## Retomar solo al reiniciarse la cuota (Settings) o esperar confirmación.
var resume_auto: bool = true
## Dónde se guardan los runs (sin carpeta, no se guardan).
var store := OneShotStore.new()
## Loops del agente (D38); `repeats` sale de la config del proyecto.
var loops := LoopDetector.new()
## Métricas para el informe final (D39).
var report := RunReport.new()
## Criterios de evaluación del juego (D40), con los pesos y umbrales del proyecto.
var criteria: Array[Dictionary] = GameCriteria.resolve()
## spec.md, progress.md y qa-<n>.md en el proyecto (D41).
var files := OneShotFiles.new()
## El agente escribe el spec y espera «Aprobar spec» antes de construir.
var spec_review: bool = false
## Informe del último run terminado, o {} mientras corre.
var last_report: Dictionary = {}

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
## Por qué se pausó solo (un loop): se muestra en la pantalla hasta que se retoma.
var pause_note: String = ""
## Tarea en la que hay que retomar (pausa, límite o "Volver acá").
var resume_task: String = ""
## Fin de la pausa por cuota (unix; 0 = sin hora).
var quota_resume_at: int = 0
var quota_pause_grace_s: int = QUOTA_PAUSE_GRACE_S
## Cuándo se programó la pausa por cuota (0 = no hay); para el tope de QUOTA_PAUSE_GRACE_S.
var _quota_scheduled_msec: int = 0
var run_id: String = ""
## El run se cargó de disco después de un cierre o una caída del editor.
var recovered: bool = false

var _started_msec: int = 0
var _turn_running: bool = false
var _guidance: Array[String] = []
## Los textos de _guidance que escribió el usuario (los demás los pone el harness, p. ej. el aviso
## de loop): al salir quedan en la actividad como «enviado».
var _user_guidance: Array[String] = []
var _warned: Dictionary = {}
var _current_task: int = -1
var _plan_progress: int = 0
var _idle_continues: int = 0
var _counted_playtests: Dictionary = {}
var _captured_calls: Dictionary = {}
var _loop_calls: Dictionary = {}
var _git_queue: Array[Callable] = []
var _git_busy: bool = false
var _close_reason: String = ""
## Ya se creó el cpN-quota de este límite (los reintentos fallidos no crean otro).
var _quota_checkpoint_done: bool = false
var _timer: Timer
## Último plan visto: lo que se guarda, y lo que se muestra mientras la sesión no se reabre.
var _plan_snapshot: Array = []
## Sesión del agente de un run cargado de disco: «Retomar» la reabre con session/load.
var _recovered_session_id: String = ""
## Por qué se reabre la sesión en el próximo resume() (para la actividad): el editor se cerró, se
## cambió de cuenta…
var _reopen_reason: String = ""
var _dirty: bool = false
var _capture_dirty: bool = false
var _last_save_msec: int = 0
## El editor se está cerrando: el run quedó guardado tal como estaba y no se vuelve a escribir.
var _suspended: bool = false
## Falta que el usuario apruebe el spec: el próximo fin de turno pasa a SPEC_REVIEW.
var _awaiting_spec: bool = false
## Se subió el presupuesto mientras se cortaba el turno por agotarlo: al cortarse, sigue.
var _continue_after_cancel: bool = false


func setup(session_controller: SessionController, project_root: String) -> void:
	controller = session_controller
	model = controller.model
	quota = controller.quota
	git = GitCheckpoints.new(project_root)
	files.project_root = project_root


func _ready() -> void:
	_timer = Timer.new()
	_timer.wait_time = TICK_S
	_timer.timeout.connect(_tick)
	add_child(_timer)
	model.plan_changed.connect(_on_plan_changed)
	model.tool_call_changed.connect(_on_tool_call_changed)
	model.permission_requested.connect(_on_permission_requested)
	changed.connect(func() -> void: _dirty = true)


func is_active() -> bool:
	return not phase in [Phase.IDLE, Phase.FINISHED]


## Hay una operación git en curso (un checkpoint se crea en segundo plano).
func is_git_busy() -> bool:
	return _git_busy


func phase_label() -> String:
	return PHASE_LABELS[phase]


## Fase "n de m" según el plan, o "".
func plan_position() -> String:
	var plan := current_plan()
	if plan.is_empty():
		return ""
	var index := _current_task if _current_task >= 0 else _completed_count()
	return "fase %d de %d" % [mini(index + 1, plan.size()), plan.size()]


## El plan del agente. Mientras un run cargado de disco no reabre su sesión (o si la sesión nueva
## todavía no mandó plan), el último que se vio.
func current_plan() -> Array:
	return _plan_snapshot if not _recovered_session_id.is_empty() or model.plan.is_empty() else model.plan


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


func start(goal_text: String, budget_values: Dictionary, use_checkpoints: bool, review_spec: bool = false) -> bool:
	if is_active():
		return false
	goal = goal_text.strip_edges()
	run_id = OneShotStore.new_id()
	files.run_id = run_id
	spec_review = review_spec
	_awaiting_spec = review_spec
	recovered = false
	_recovered_session_id = ""
	_suspended = false
	_plan_snapshot = []
	budgets.merge(budget_values, true)
	used = {BUDGET_TIME: 0.0, BUDGET_TOKENS: 0, BUDGET_PLAYTESTS: 0}
	checks.clear()
	activity.clear()
	_guidance.clear()
	_user_guidance.clear()
	_warned.clear()
	_counted_playtests.clear()
	_captured_calls.clear()
	_loop_calls.clear()
	loops.reset()
	report.reset()
	last_report = {}
	pause_note = ""
	_current_task = -1
	_idle_continues = 0
	_close_reason = ""
	_continue_after_cancel = false
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
	# Después de git.start: los archivos nacen en la rama del agente.
	if not files.prepare():
		_add_activity("aviso", "No se pudo crear %s: el agente no va a tener dónde escribir el spec" % files.relative_dir())
	if not controller.is_connected_to_agent() and not await _restart_session(""):
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
	var spec_step := "0. Antes que nada, escribí el spec del juego en %s: mecánicas, loop de juego (empezar → jugar → ganar o perder → reiniciar), dirección visual y qué significa \"terminado\". Ambicioso en alcance pero de alto nivel: sin detalle técnico (nada de nodos, scripts ni APIs)." % files.spec_path()
	if spec_review:
		spec_step += " Después terminá el turno sin construir nada: el usuario lo revisa y lo aprueba."
	return "\n".join([
		"Objetivo (modo One-shot): %s" % goal,
		"",
		"Trabajá de forma autónoma hasta cumplir el objetivo:",
		spec_step,
		"1. Armá un plan a partir del spec con tu herramienta de plan o de tareas (por ejemplo TodoWrite o TaskCreate/TaskUpdate), una entrada por tarea. Marcá cada tarea in_progress al empezarla y completed al terminarla: el harness ve el plan y crea un checkpoint git antes de cada tarea.",
		"2. Después de cada tarea, verificá con godot.run_scene (con inputs si hace falta), godot.capture_game_frame y godot.get_errors.",
		"3. Al terminar cada tarea, actualizá %s (qué está hecho, qué falta, decisiones y problemas conocidos: es lo que lee quien retome) y reportá las verificaciones vigentes en un bloque ```json {\"checks\":[{\"label\":\"…\",\"status\":\"pass|fail|pending\"}]}." % files.progress_path(),
		"4. Presupuestos: %s. Si te acercás al límite, priorizá dejar algo jugable." % (", ".join(limits) if not limits.is_empty() else "sin límite"),
		"No hagas commits ni cambies de rama: los checkpoints git los maneja el harness.",
		"",
		GameCriteria.generator_text(criteria),
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


## Fases desde las que se puede retomar (Retomar, Reintentar, Cambiar de cuenta).
func can_resume() -> bool:
	return phase in [Phase.PAUSED, Phase.PAUSED_QUOTA, Phase.LIMITED, Phase.WAITING_CONFIRM]


func resume() -> void:
	if not can_resume():
		return
	var was_limited := phase == Phase.LIMITED or quota.is_limited()
	pause_note = ""
	_set_phase(Phase.RUNNING)
	if was_limited:
		quota.note_retry()
	# Un run cargado de disco retoma su propia sesión, aunque el dock tenga otra abierta.
	var from_disk := not _recovered_session_id.is_empty()
	var lost_id := _recovered_session_id if from_disk else model.session_id
	if not controller.is_connected_to_agent() or (from_disk and model.session_id != lost_id):
		if not await _restart_session(lost_id):
			_recovered_session_id = ""
			_finish("No se pudo reabrir la sesión con el agente.")
			return
		_recovered_session_id = ""
		model.set_harness_mode(SessionModel.HarnessMode.ONESHOT)
		var what := _reopen_reason if not _reopen_reason.is_empty() else ("El editor se había cerrado" if from_disk else "La sesión se perdió")
		_reopen_reason = ""
		if not lost_id.is_empty() and model.session_id == lost_id:
			_add_activity("sesión", "%s: se reabrió la sesión con session/load" % what)
			_run_turn(_resume_prompt())
		else:
			_add_activity("sesión", "%s: se abrió una sesión nueva con el resumen del plan" % what)
			_run_turn(_summary_prompt())
		return
	_recovered_session_id = ""
	_run_turn(_resume_prompt())


## Cambio de cuenta (m6-15): la cuota medida era de la cuenta anterior. Se relanza el proceso del
## agente, que lee las credenciales nuevas, y se retoma la misma sesión con session/load.
func switch_account() -> void:
	if not can_resume():
		return
	var session_id := _recovered_session_id if not _recovered_session_id.is_empty() else model.session_id
	quota.forget_account()
	quota_resume_at = 0
	report.count("account_switches")
	_add_activity("sesión", "Cambio de cuenta: se reinicia el agente y se retoma la misma sesión")
	controller.stop()
	_recovered_session_id = session_id
	_reopen_reason = "Cambio de cuenta"
	resume()


func stop() -> void:
	if not is_active():
		return
	if _turn_running:
		controller.cancel()
	_finish("Detenido por el usuario.")


## Lo que el usuario escribe en el chat del dock: se manda al terminar el turno actual (o ya, si no hay turno en curso).
func guide(text: String) -> void:
	text = text.strip_edges()
	if text.is_empty() or not is_active():
		return
	report.count("guidance")
	if not _recovered_session_id.is_empty():  # primero se reabre la sesión del run
		_queue_guidance(text)
		resume()
		return
	if _turn_running or phase in [Phase.PREPARING, Phase.CLOSING, Phase.LIMITED]:
		_queue_guidance(text)
		changed.emit()
		return
	if phase in [Phase.PAUSED, Phase.PAUSED_QUOTA, Phase.WAITING_CONFIRM, Phase.SPEC_REVIEW]:
		pause_note = ""
		_set_phase(Phase.RUNNING)
	_add_activity("guía", "enviado: " + text)
	_run_turn(text)


## La guía espera al final del turno: queda en la actividad y en el chat, para que se vea que no
## se perdió (m6-14).
func _queue_guidance(text: String) -> void:
	_guidance.append(text)
	_user_guidance.append(text)
	_add_activity("guía", "en cola: " + text)
	model.add_notice("One-shot · en cola: «%s». Le llega al agente al terminar el turno." % text.left(120), ChatEntry.Level.INFO)


func _pop_guidance() -> String:
	var text: String = _guidance.pop_front()
	var index := _user_guidance.find(text)
	if index >= 0:
		_user_guidance.remove_at(index)
		_add_activity("guía", "enviado: " + text)
	return text


## Presupuestos nuevos con el run en curso (m6-12); 0 = sin límite. Los avisos del 80 % se rearman
## y, si el run iba a cerrar por presupuesto y ahora alcanza, sigue: si ya se pidió el reporte
## final, ese turno queda como uno más.
func set_budgets(values: Dictionary) -> void:
	if not is_active():
		return
	for budget: String in [BUDGET_TIME, BUDGET_TOKENS, BUDGET_PLAYTESTS]:
		if values.has(budget):
			budgets[budget] = maxi(int(values[budget]), 0)
		if budget_ratio(budget) < WARN_RATIO:
			_warned.erase(budget)
	report.count("budget_changes")
	_add_activity("presupuesto", "Presupuestos: " + budgets_text())
	var exhausted := [BUDGET_TIME, BUDGET_TOKENS, BUDGET_PLAYTESTS].any(func(budget: String) -> bool: return budget_ratio(budget) >= 1.0)
	if _close_reason.begins_with(BUDGET_CLOSE_PREFIX) and not exhausted:
		_close_reason = ""
		_add_activity("presupuesto", "Con el presupuesto nuevo, el run sigue")
		if phase == Phase.CLOSING:
			_set_phase(Phase.RUNNING)
		elif phase == Phase.RUNNING:
			if _turn_running:
				_continue_after_cancel = true
			else:
				_run_turn(_resume_prompt())
	_check_budgets()
	changed.emit()


func budgets_text() -> String:
	var parts: PackedStringArray = []
	for budget: String in [BUDGET_TIME, BUDGET_TOKENS, BUDGET_PLAYTESTS]:
		var limit := int(budgets.get(budget, 0))
		parts.append("%s %s" % [str(BUDGET_LABELS[budget]).to_lower(), ("%d min" % limit if budget == BUDGET_TIME else str(limit)) if limit > 0 else "sin límite"])
	return ", ".join(parts)


## «Aprobar spec» (D41): con `text` distinto del archivo, primero se guarda lo que editó el usuario.
func approve_spec(text: String = "") -> void:
	if phase != Phase.SPEC_REVIEW:
		return
	var edited := not text.strip_edges().is_empty() and text != files.read(files.spec_path())
	if edited:
		files.write(files.spec_path(), text)
	_awaiting_spec = false
	_add_activity("spec", "Spec aprobado" + (" con cambios del usuario" if edited else ""))
	_set_phase(Phase.RUNNING)
	_run_turn("El spec está aprobado%s. Seguí con el resto: armá el plan a partir del spec y construí." % (" con cambios: releelo antes de armar el plan" if edited else ""))


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
	report.count("turns")
	var first_entry := model.entries().size()
	var progress_before := _progress()
	var reason: String = await controller.send_in_mode(SessionModel.HarnessMode.ONESHOT, text)
	_turn_running = false
	if not is_instance_valid(self) or not is_inside_tree():
		return
	_account_tokens(controller.last_turn_usage)
	if reason == "error" or reason.is_empty():
		report.count("turn_errors")
	var turn_text := controller.agent_text_since(first_entry)
	var new_checks: Array = FindingsParser.parse(turn_text).checks
	_merge_checks(new_checks)
	if phase == Phase.RUNNING:
		_on_loop(loops.observe_checks(new_checks), false)
	var summary := _summary_of(turn_text)
	if not summary.is_empty():
		_add_activity("agente", summary)
	if _progress() > progress_before:
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
	if phase == Phase.RUNNING and quota.state == QuotaMonitor.State.PAUSE_SCHEDULED and reason != "cancelled":
		_pause_for_quota(_task_name(_next_pending()))
		return
	if not _guidance.is_empty():
		_run_turn(_pop_guidance())
		return
	if reason == "cancelled":
		if _continue_after_cancel:
			_continue_after_cancel = false
			_run_turn(_resume_prompt())
		return
	if _awaiting_spec:
		_enter_spec_review()
		return
	if current_plan().is_empty():
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


func _enter_spec_review() -> void:
	_set_phase(Phase.SPEC_REVIEW)
	if files.has_spec():
		_add_activity("spec", "%s/%s listo: revisalo y aprobalo para que empiece a construir" % [files.relative_dir(), OneShotFiles.SPEC])
	else:
		_add_activity("aviso", "El agente no escribió %s/%s. Escribile en el chat que lo escriba, o aprobá para seguir sin spec." % [files.relative_dir(), OneShotFiles.SPEC])
	model.add_notice("One-shot · el spec está listo para revisar en la pantalla Agent.", ChatEntry.Level.INFO)


func _close() -> void:
	_set_phase(Phase.CLOSING)
	_add_activity("presupuesto", _close_reason)
	_run_turn("%s No sigas con el plan: escribí el reporte final (qué quedó hecho, qué falta y cómo probarlo) y el bloque de checks." % _close_reason)


func _finish(reason: String) -> void:
	finish_reason = reason
	_timer.stop()
	_recovered_session_id = ""
	_add_activity("estado", reason)
	_set_phase(Phase.FINISHED)
	store.prune()
	_write_report()


## Informe con lo medido (D39): se muestra en la pantalla y queda en `<id>.report.json`.
func _write_report() -> void:
	var data := {
		"id": run_id, "goal": goal, "finish_reason": finish_reason, "duration_ms": _elapsed_ms(),
		"budgets": budgets.duplicate(), "used": used.duplicate(), "checks": checks.duplicate(true),
		"files_dir": files.relative_dir(),
		"checkpoints": git.checkpoints.map(func(cp: Dictionary) -> Dictionary: return {"name": cp.name, "label": cp.label}) if checkpoints_enabled else [],
	}
	data["changes"] = await changes_summary() if checkpoints_enabled else {}
	last_report = report.build(data)
	store.save_report(run_id, last_report)
	report_ready.emit()
	changed.emit()


func _on_permission_requested(request: SessionModel.PermissionRequest) -> void:
	if not is_active():
		return
	report.count("permissions_asked")
	request.resolved.connect(func(_outcome: Dictionary) -> void:
		if not request.was_allowed():
			report.count("permissions_denied")
	, CONNECT_ONE_SHOT)


func _restart_session(lost_id: String) -> bool:
	if not restart_session.is_valid():
		return false
	return await restart_session.call(lost_id)


func _resume_prompt() -> String:
	var task := resume_task if not resume_task.is_empty() else _task_name(_next_pending())
	var last := git.checkpoints.back() if checkpoints_enabled and not git.checkpoints.is_empty() else {}
	var where := "" if last.is_empty() else "; el estado está en el checkpoint %s (%s)" % [last.name, last.label]
	var handoff := " Si te falta contexto, releé spec.md y progress.md en %s." % files.dir() if files.has_spec() else ""
	if task.is_empty():
		return "Continuá con el objetivo desde donde quedaste%s.%s" % [where, handoff]
	return "Continuá con el plan desde la tarea «%s»%s.%s" % [task, where, handoff]


func _summary_prompt() -> String:
	var lines: PackedStringArray = ["Retomamos un One-shot que se interrumpió.", "", initial_prompt(), ""]
	if files.has_spec():
		lines.append_array(["El traspaso está en %s: leé spec.md y progress.md (y los qa-*.md si hay) antes de seguir; el spec ya está escrito." % files.dir(), ""])
	lines.append("Plan hasta ahora:")
	for entry: Variant in current_plan():
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
	if not is_active() or model.replaying:
		return
	if not plan.is_empty():
		_plan_snapshot = plan.duplicate(true)
		report.observe_plan(plan, _elapsed_ms())
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
	if not is_active() or model.replaying or not call.is_finished():
		return
	var name := call.godot_tool_name()
	if name == "run_scene" and call.status == ToolCall.STATUS_COMPLETED and not _counted_playtests.has(call.id):
		_counted_playtests[call.id] = true
		used[BUDGET_PLAYTESTS] = int(used[BUDGET_PLAYTESTS]) + 1
		_add_activity("playtest", "Playtest #%d · %s" % [used[BUDGET_PLAYTESTS], _call_summary(call)])
		# Sin plan no hay tareas que marquen los checkpoints: se crea uno por playtest (D24).
		if current_plan().is_empty() and checkpoints_enabled:
			_checkpoint("Playtest #%d" % used[BUDGET_PLAYTESTS])
		_check_budgets()
	elif not name.is_empty() or call.status == ToolCall.STATUS_FAILED:
		_add_activity("tool", _one_line("%s · %s" % [call.display_name(), _call_summary(call)]))
	if call.status != ToolCall.STATUS_CANCELLED and not _loop_calls.has(call.id):
		_loop_calls[call.id] = true
		var failed := call.status == ToolCall.STATUS_FAILED
		report.observe_tool(RunReport.tool_label(call.title, name, call.tool_name, call.kind), failed)
		if phase == Phase.RUNNING:
			_on_loop(loops.observe_call(call.title, call.kind, name, call.raw_input, failed), true)
	if not _captured_calls.has(call.id):
		for block: Variant in call.content:
			var inner: Variant = block.get("content") if block is Dictionary else null
			if inner is Dictionary and str(inner.get("type", "")) == "image":
				var image := _decode_image(str(inner.get("data", "")), str(inner.get("mimeType", "")))
				if image:
					_captured_calls[call.id] = true
					last_capture = image
					_capture_dirty = true
					last_capture_caption = "Playtest #%d · %s" % [maxi(int(used[BUDGET_PLAYTESTS]), 1), _elapsed_text()]
					changed.emit()


## Un loop (D38). La primera vez se corta el turno (si viene de tool calls) y se le pide otro
## enfoque; si la misma huella vuelve a aparecer, el run se pausa y espera al usuario.
func _on_loop(finding: Dictionary, mid_turn: bool) -> void:
	if finding.is_empty():
		return
	report.count("loops")
	if bool(finding.repeated):
		pause_note = "One-shot en pausa: el agente sigue en un loop (%s) aunque se le pidió otro enfoque. Escribile en el chat cómo seguir, o retomá cuando quieras." % finding.text
		resume_task = _task_name(_current_task)
		_set_phase(Phase.PAUSED)
		_add_activity("loop", "Pausa: %s otra vez" % finding.text)
		model.add_notice(pause_note, ChatEntry.Level.WARNING)
		if _turn_running:
			controller.cancel()
		return
	_add_activity("loop", "Posible loop: %s" % finding.text)
	model.add_notice("One-shot · posible loop: %s. Se le pide otro enfoque." % finding.text, ChatEntry.Level.WARNING)
	_guidance.append("Parece que estás en un loop: %s. No lo repitas igual: pensá por qué no funciona y probá otro enfoque (otra solución, otro archivo, o simplificá la tarea). Si algo no se puede resolver, anotalo en el bloque de checks y seguí con lo demás." % finding.text)
	if mid_turn and _turn_running:
		controller.cancel()  # la guía se manda al cortar el turno (_after_turn)
	changed.emit()


func _merge_checks(new_checks: Array) -> void:
	report.observe_checks(new_checks)
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
	if _dirty and Time.get_ticks_msec() - _last_save_msec >= SAVE_INTERVAL_MS:
		_save()
	if phase in [Phase.RUNNING, Phase.CLOSING]:
		used[BUDGET_TIME] = float(used[BUDGET_TIME]) + TICK_S
		_check_budgets()
	_check_quota_pause()
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
			_close_reason = BUDGET_CLOSE_PREFIX + "%s." % str(BUDGET_LABELS[budget]).to_lower()
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


## Umbral de pausa (spec §10.1): no corta la tarea en curso. Pausa al empezar la siguiente (con su
## checkpoint) o al terminar el turno, lo que llegue primero; si ninguna llega a tiempo, la red de
## _check_quota_pause corta el turno a mitad de la tarea.
func _pause_for_quota(next_task: String, mid_task: bool = false) -> void:
	resume_task = next_task
	quota_resume_at = quota.pause_resets_at()
	if quota_resume_at <= 0:
		quota_resume_at = int(Time.get_unix_time_from_system()) + PAUSE_RETRY_S
	_quota_scheduled_msec = 0
	_set_phase(Phase.PAUSED_QUOTA)
	report.count("quota_pauses")
	var percent := roundi(quota.max_utilization() * 100.0)
	if mid_task:
		_add_activity("cuota", "Cuota al %d %%: la tarea no terminaba, se corta el turno y se pausa" % percent)
	elif next_task.is_empty():
		_add_activity("cuota", "Cuota al %d %%: pausa al terminar el turno" % percent)
	else:
		_add_activity("cuota", "Cuota al %d %%: pausa antes de «%s»" % [percent, next_task])
	if checkpoints_enabled:
		_checkpoint(next_task if not next_task.is_empty() else "Pausa por cuota", "-quota" if mid_task else "")
	if _turn_running:
		controller.cancel()


## Red de la pausa por cuota: si la tarea o el turno no terminan en quota_pause_grace_s, o la
## cuota llega a QUOTA_PAUSE_HARD, se corta el turno y se pausa a mitad de la tarea.
func _check_quota_pause() -> void:
	if phase != Phase.RUNNING or quota.state != QuotaMonitor.State.PAUSE_SCHEDULED:
		_quota_scheduled_msec = 0
		return
	if _quota_scheduled_msec == 0:
		_quota_scheduled_msec = Time.get_ticks_msec()
	var waited_s := (Time.get_ticks_msec() - _quota_scheduled_msec) / 1000.0
	if waited_s >= quota_pause_grace_s or quota.max_utilization() >= QUOTA_PAUSE_HARD:
		_pause_for_quota(_task_name(_next_pending()), true)


## Cuándo se pausa por cuota, para el banner: al terminar la tarea o el turno, como mucho en
## los minutos que quedan de la espera. "" si no hay pausa programada.
func quota_pause_text() -> String:
	if quota.state != QuotaMonitor.State.PAUSE_SCHEDULED or phase != Phase.RUNNING:
		return ""
	var left := quota_pause_grace_s
	if _quota_scheduled_msec > 0:
		left = maxi(quota_pause_grace_s - int((Time.get_ticks_msec() - _quota_scheduled_msec) / 1000.0), 0)
	return "Cuota al %d %%: el One-shot se pausa al terminar la tarea o el turno en curso (si no, en %s se corta y se pausa igual)" % [
		roundi(quota.max_utilization() * 100.0), QuotaMonitor.format_duration(left)]


## Límite a mitad de turno: tool calls pendientes → cancelled, cpN-quota y "Limitado".
func _enter_limited() -> void:
	model.cancel_unfinished_tool_calls()
	resume_task = _task_name(_current_task) if _current_task >= 0 else _task_name(_next_pending())
	_set_phase(Phase.LIMITED)
	report.count("limited")
	quota_resume_at = quota.limited_until
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


# --- persistencia (D37) ---------------------------------------------------------------------------

## El editor se cierra o se deshabilita el plugin con el run en curso: queda guardado como estaba,
## para retomarlo al volver (en lugar de darlo por terminado).
func suspend() -> void:
	if not is_active():
		return
	_save()
	_suspended = true
	_timer.stop()


## Carga el último run si quedó a medias. Queda en pausa: «Retomar» reabre su sesión.
func restore_interrupted() -> bool:
	if is_active():
		return false
	var data := store.load_interrupted()
	if data.is_empty():
		return false
	_apply(data)
	return true


func to_dict() -> Dictionary:
	return {
		"id": run_id,
		"active": is_active(),
		"phase": PHASE_LABELS[phase],
		"phase_id": Phase.keys()[phase],
		"quota_resume_at": quota_resume_at,
		"goal": goal,
		"budgets": budgets,
		"used": used,
		"checkpoints_enabled": checkpoints_enabled,
		"git": {"base_branch": git.base_branch, "base_sha": git.base_sha, "agent_branch": git.agent_branch, "checkpoints": git.checkpoints},
		"checks": checks,
		"activity": activity,
		"plan": _plan_snapshot,
		"current_task": _current_task,
		"resume_task": resume_task if not resume_task.is_empty() else _task_name(_current_task),
		"guidance": _guidance,
		"user_guidance": _user_guidance,
		"close_reason": _close_reason,
		"finish_reason": finish_reason,
		"warned": _warned,
		"pause_note": pause_note,
		"spec_review": spec_review,
		"awaiting_spec": _awaiting_spec,
		"report": report.to_dict(),
		"session_id": _recovered_session_id if not _recovered_session_id.is_empty() else model.session_id,
		"elapsed_ms": _elapsed_ms(),
		"capture_caption": last_capture_caption,
	}


func _apply(data: Dictionary) -> void:
	run_id = str(data.id)
	goal = str(data.get("goal", ""))
	budgets.merge(data.get("budgets", {}) as Dictionary, true)
	var saved_used: Dictionary = data.get("used", {})
	used = {BUDGET_TIME: float(saved_used.get(BUDGET_TIME, 0)), BUDGET_TOKENS: int(saved_used.get(BUDGET_TOKENS, 0)), BUDGET_PLAYTESTS: int(saved_used.get(BUDGET_PLAYTESTS, 0))}
	checkpoints_enabled = bool(data.get("checkpoints_enabled", false))
	var saved_git: Dictionary = data.get("git", {})
	git.base_branch = str(saved_git.get("base_branch", ""))
	git.base_sha = str(saved_git.get("base_sha", ""))
	git.agent_branch = str(saved_git.get("agent_branch", ""))
	git.checkpoints.assign(saved_git.get("checkpoints", []))
	checks.assign(data.get("checks", []))
	activity.assign(data.get("activity", []))
	_plan_snapshot = data.get("plan", []) if data.get("plan") is Array else []
	_current_task = int(data.get("current_task", -1))
	resume_task = str(data.get("resume_task", ""))
	_guidance.assign(data.get("guidance", []))
	_user_guidance.assign(data.get("user_guidance", []))
	_close_reason = str(data.get("close_reason", ""))
	_warned = data.get("warned", {}) if data.get("warned") is Dictionary else {}
	pause_note = str(data.get("pause_note", ""))
	files.run_id = run_id
	spec_review = bool(data.get("spec_review", false))
	_awaiting_spec = bool(data.get("awaiting_spec", false))
	report.apply(data.get("report", {}) if data.get("report") is Dictionary else {})
	last_report = {}
	_recovered_session_id = str(data.get("session_id", ""))
	_started_msec = Time.get_ticks_msec() - int(data.get("elapsed_ms", 0))
	last_capture = store.load_capture(run_id)
	last_capture_caption = str(data.get("capture_caption", ""))
	finish_reason = ""
	_idle_continues = 0
	_suspended = false
	recovered = true
	phase = Phase.PAUSED
	var where := " y sigue desde «%s»" % resume_task if not resume_task.is_empty() else ""
	# Un run que esperaba la cuota sigue esperándola: retoma solo cuando se reinicia la ventana.
	quota_resume_at = int(data.get("quota_resume_at", 0))
	var waiting_quota := str(data.get("phase_id", "")) in ["LIMITED", "PAUSED_QUOTA"]
	if waiting_quota and quota_resume_at > int(Time.get_unix_time_from_system()):
		phase = Phase.PAUSED_QUOTA
		var at := Time.get_time_string_from_unix_time(quota_resume_at + int(Time.get_time_zone_from_system().get("bias", 0)) * 60).left(5)
		_add_activity("sesión", "El editor se cerró con el One-shot esperando la cuota: retoma solo a las %s%s («Retomar» o «Cambiar de cuenta» para no esperar)." % [at, where])
	else:
		quota_resume_at = 0
		_add_activity("sesión", "El editor se cerró con el One-shot en curso. «Retomar» reabre la sesión del agente%s." % where)
	_timer.start()
	restored.emit()
	changed.emit()
	_save()


func _save() -> void:
	if _suspended or run_id.is_empty() or not store.is_enabled():
		return
	_dirty = false
	_last_save_msec = Time.get_ticks_msec()
	store.save(to_dict(), last_capture if _capture_dirty else null)
	_capture_dirty = false


func _exit_tree() -> void:
	if _dirty:
		_save()


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
	_save()


func _add_activity(kind: String, text: String) -> void:
	var entry := {"time": _elapsed_text(), "kind": kind, "text": text}
	activity.append(entry)
	if activity.size() > ACTIVITY_LIMIT:
		activity.remove_at(0)
	activity_added.emit(entry)


func _elapsed_ms() -> int:
	return Time.get_ticks_msec() - _started_msec if _started_msec > 0 else 0


func _elapsed_text() -> String:
	var seconds := _elapsed_ms() / 1000
	return "%02d:%02d:%02d" % [seconds / 3600, (seconds / 60) % 60, seconds % 60]


func _task_name(index: int) -> String:
	var plan := current_plan()
	if index >= 0 and index < plan.size() and plan[index] is Dictionary:
		return str(plan[index].get("content", "tarea %d" % (index + 1)))
	return ""


## Avance real (D38): tareas completadas y checks que pasan. Un playtest o un resumen no cuentan.
func _progress() -> int:
	return _completed_count() + checks.filter(func(check: Dictionary) -> bool: return check.status == "pass").size()


func _completed_count() -> int:
	var count := 0
	for entry: Variant in current_plan():
		if entry is Dictionary and str(entry.get("status", "")) == "completed":
			count += 1
	return count


func _next_pending() -> int:
	var plan := current_plan()
	for i in plan.size():
		if plan[i] is Dictionary and str(plan[i].get("status", "")) != "completed":
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
