@tool
extends Node
## Loop del One-shot (spec §10 y §10.1):
## - prompt inicial con el objetivo, el plan, los checks y la verificación con run_scene;
## - checkpoint git antes de cada tarea del plan (cuando una entrada pasa a in_progress);
## - presupuestos de tiempo, tokens y playtests: aviso al 80 %, cierre con reporte al 100 %;
## - lo que el usuario escribe en el chat (guide) se encola para el fin del turno;
## - cuota del plan: pausa al terminar la tarea o el turno (con un tope de espera), "limitado" con cpN-quota y reanudación;
## - el estado se guarda en disco mientras corre (D37): si el editor se cierra o se cae, al volver
##   el run queda en pausa y «Retomar» reabre la sesión del agente;
## - cuando el agente da el objetivo por cumplido, un evaluador aparte (sesión nueva, sin el
##   contexto del que construye y sin permisos de edición) juega el juego y decide los checks; si no
##   pasa, sus hallazgos vuelven como el próximo turno (D55).
## La UI (pantalla One-shot) solo lee el estado y llama a los métodos públicos.

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
const PermissionPolicy := preload("../session/permission_policy.gd")
const I18n := preload("../core/i18n.gd")

enum RunPhase { IDLE, PREPARING, RUNNING, PAUSED, PAUSED_QUOTA, LIMITED, WAITING_CONFIRM, CLOSING, FINISHED, SPEC_REVIEW, EVALUATING }

const PHASE_LABELS: Dictionary = {
	RunPhase.IDLE: "Not started",  # i18n
	RunPhase.PREPARING: "Preparing",  # i18n
	RunPhase.RUNNING: "Running",  # i18n
	RunPhase.PAUSED: "Paused",  # i18n
	RunPhase.PAUSED_QUOTA: "Paused for quota",  # i18n
	RunPhase.LIMITED: "Limited",  # i18n
	RunPhase.WAITING_CONFIRM: "Ready to resume",  # i18n
	RunPhase.CLOSING: "Closing",  # i18n
	RunPhase.FINISHED: "Finished",  # i18n
	RunPhase.SPEC_REVIEW: "Spec to review",  # i18n
	RunPhase.EVALUATING: "Evaluating",  # i18n
}
const BUDGET_TIME := "time"
const BUDGET_TOKENS := "tokens"
const BUDGET_PLAYTESTS := "playtests"
const BUDGET_LABELS: Dictionary = {
	BUDGET_TIME: "Time",  # i18n
	BUDGET_TOKENS: "Tokens",  # i18n
	BUDGET_PLAYTESTS: "Playtests",  # i18n
}
const WARN_RATIO := 0.8
## Motivo de cierre por presupuesto: en inglés con el id del presupuesto para el agente; traducido
## con la etiqueta para la UI (_close_reason_text).
const BUDGET_CLOSE_REASON := "The %s budget ran out."  # i18n
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
## Fases sin trabajo y cómo cuentan en los tiempos del informe.
const WAIT_KINDS: Dictionary = {
	RunPhase.PAUSED_QUOTA: "quota", RunPhase.LIMITED: "quota", RunPhase.WAITING_CONFIRM: "quota",
	RunPhase.PAUSED: "paused", RunPhase.SPEC_REVIEW: "spec_review",
}
## Cómo terminó el turno, para la actividad (end_turn = normal, sin nota).
const TURN_END_NOTES: Dictionary = {
	"cancelled": "cut short",  # i18n
	"error": "with an error",  # i18n
	"max_tokens": "out of output tokens",  # i18n
	"refusal": "the agent refused",  # i18n
}
## Sesión reabierta (por qué, en _reopen_reason) para la actividad: con session/load o una nueva.
const REOPEN_LOADED: Dictionary = {
	"editor": "The editor had closed: reopened the session with session/load",  # i18n
	"lost": "The session was lost: reopened the session with session/load",  # i18n
	"account": "Account switch: reopened the session with session/load",  # i18n
}
const REOPEN_NEW: Dictionary = {
	"editor": "The editor had closed: opened a new session with the plan summary",  # i18n
	"lost": "The session was lost: opened a new session with the plan summary",  # i18n
	"account": "Account switch: opened a new session with the plan summary",  # i18n
}
const TICK_S := 0.5
## Vueltas de QA por defecto (D55): evaluaciones como mucho, con una vuelta de corrección entre
## una y otra. 0 apaga el evaluador.
const QA_ROUNDS := 2
## Encabezado del prompt del evaluador (el agente falso de los tests lo reconoce por esto).
const QA_MARKER := "QA evaluation (One-shot)"
const QA_MODE_RULES := "You are the QA evaluator of a game another agent built: play it and read it, but do not change anything. Editing files, scenes or project settings and running shell commands are denied."
## Permisos del evaluador: lee, diagnostica y corre el juego; no edita.
const QA_RESTRICTIONS: Dictionary = {
	PermissionPolicy.GROUP_READ: PermissionPolicy.ALLOW,
	PermissionPolicy.GROUP_DIAGNOSTICS: PermissionPolicy.ALLOW,
	PermissionPolicy.GROUP_RUN: PermissionPolicy.ALLOW,
	PermissionPolicy.GROUP_EDIT_SCENE: PermissionPolicy.DENY,
	PermissionPolicy.GROUP_EDIT_FILES: PermissionPolicy.DENY,
	PermissionPolicy.GROUP_PROJECT: PermissionPolicy.DENY,
	PermissionPolicy.GROUP_ADDONS: PermissionPolicy.DENY,
	PermissionPolicy.GROUP_SHELL: PermissionPolicy.DENY,
}
## Hallazgos que van a la actividad por vuelta (el resto está en qa-<n>.md).
const QA_ACTIVITY_FINDINGS := 6
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
## Vueltas de QA (D55); 0 = sin evaluador: valen los checks que reporta el agente.
var qa_max_rounds: int = QA_ROUNDS
## Vuelta de QA en curso o la última (0 = todavía no se evaluó).
var qa_round: int = 0
## Resultado de cada vuelta: {round, passed, weighted, failing_checks, failing_criteria, findings, file}.
var qa_results: Array[Dictionary] = []

var phase: RunPhase = RunPhase.IDLE
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
## Operaciones git en curso o en cola: entre una y la siguiente hay un frame sin _git_busy.
var _git_pending: int = 0
var _close_reason: String = ""
## Ya se creó el cpN-quota de este límite (los reintentos fallidos no crean otro).
var _quota_checkpoint_done: bool = false
var _timer: Timer
## Último plan visto: lo que se guarda, y lo que se muestra mientras la sesión no se reabre.
var _plan_snapshot: Array = []
## Sesión del agente de un run cargado de disco: «Retomar» la reabre con session/load.
var _recovered_session_id: String = ""
## Por qué se reabre la sesión en el próximo resume() (para la actividad): "account" (cambio de
## cuenta) o "" (el editor se cerró o la sesión se perdió).
var _reopen_reason: String = ""
## Tool calls terminadas en el turno en curso, y desde cuándo está el run en su fase (para medir
## las esperas del informe, m6-16).
var _turn_tools: int = 0
var _phase_since_ms: int = 0
var _dirty: bool = false
var _capture_dirty: bool = false
var _last_save_msec: int = 0
## El editor se está cerrando: el run quedó guardado tal como estaba y no se vuelve a escribir.
var _suspended: bool = false
## Falta que el usuario apruebe el spec: el próximo fin de turno pasa a SPEC_REVIEW.
var _awaiting_spec: bool = false
## Se subió el presupuesto mientras se cortaba el turno por agotarlo: al cortarse, sigue.
var _continue_after_cancel: bool = false
## Sesión del agente que construye mientras evalúa el evaluador: se vuelve a ella después.
var _generator_session_id: String = ""
## La evaluación se cortó (pausa, cuota, error): «Retomar» la vuelve a empezar, en la misma vuelta.
var _resume_qa: bool = false
## Por qué terminaba el agente cuando se pidió la evaluación (si el evaluador no llega a decidir).
var _done_reason: String = ""


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
	return not phase in [RunPhase.IDLE, RunPhase.FINISHED]


## Hay una operación git en curso (un checkpoint se crea en segundo plano).
func is_git_busy() -> bool:
	return _git_pending > 0


func phase_label() -> String:
	if phase == RunPhase.EVALUATING:
		return I18n.t("Evaluating · QA round %d") % qa_round
	return I18n.t(PHASE_LABELS[phase])


## Fase "n de m" según el plan, o "".
func plan_position() -> String:
	var plan := current_plan()
	if plan.is_empty():
		return ""
	var index := _current_task if _current_task >= 0 else _completed_count()
	return I18n.t("task %d of %d") % [mini(index + 1, plan.size()), plan.size()]


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
	qa_round = 0
	qa_results.clear()
	_generator_session_id = ""
	_resume_qa = false
	_done_reason = ""
	finish_reason = ""
	resume_task = ""
	last_capture = null
	_started_msec = Time.get_ticks_msec()
	_set_phase(RunPhase.PREPARING)
	# Una tool de un MCP server de terceros en "ask" frena el run hasta que alguien conteste (m7-35).
	var asking := controller.mcp_servers_not_allowed(SessionModel.HarnessMode.ONESHOT)
	if not asking.is_empty():
		_add_activity("warning", I18n.t("These MCP servers ask for permission in One-shot: %s. The run waits at each of their tools; allow them in Settings → Permissions so it doesn't stop.") % ", ".join(asking))
	checkpoints_enabled = false
	if use_checkpoints:
		if await git.check_available():
			checkpoints_enabled = await git.start()
			if checkpoints_enabled:
				_add_activity("checkpoint", I18n.t("Branch %s · %s %s") % [git.agent_branch, git.checkpoints[0].name, git.checkpoints[0].label])
			else:
				_add_activity("warning", git.last_error)
		else:
			_add_activity("warning", git.last_error)
	# Después de git.start: los archivos nacen en la rama del agente.
	if not files.prepare():
		_add_activity("warning", I18n.t("Couldn't create %s: the agent won't have anywhere to write the spec") % files.relative_dir())
	if not controller.is_connected_to_agent() and not await _restart_session(""):
		_finish(I18n.t("Couldn't open a session with the agent."))
		return false
	# Remote Control (m7-21): los turnos que se mandan desde el celular no pasan por el run y
	# romperían los presupuestos y el conteo de checks. Se apaga antes de empezar.
	if not model.remote_control_url.is_empty():
		_add_activity("warning", I18n.t("Remote Control turned off: One-shot runs on its own."))
		await controller.send_prompt(controller.remote_control_command(false))
	model.set_harness_mode(SessionModel.HarnessMode.ONESHOT)
	_set_phase(RunPhase.RUNNING)
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
	var spec_step := "0. Before anything else, write the game spec in %s: mechanics, game loop (start → play → win or lose → restart), visual direction and what \"done\" means. Ambitious in scope but high level: no technical detail (no nodes, scripts or APIs)." % files.spec_path()
	if spec_review:
		spec_step += " Then end the turn without building anything: the user reviews and approves it."
	return "\n".join([
		"Goal (One-shot mode): %s" % goal,
		"",
		"Work autonomously until the goal is met:",
		spec_step,
		"1. Make a plan from the spec with your plan or task tool (for example TodoWrite or TaskCreate/TaskUpdate), one entry per task. Mark each task in_progress when you start it and completed when you finish it: the harness sees the plan and creates a git checkpoint before each task.",
		"2. After each task, verify with godot.run_scene (with inputs if needed), godot.capture_game_frame and godot.get_errors.",
		"3. When you finish each task, update %s (what is done, what is missing, decisions and known problems: it is what whoever resumes will read) and report the current checks in a ```json {\"checks\":[{\"label\":\"…\",\"status\":\"pass|fail|pending\"}]} block." % files.progress_path(),
		"4. Budgets: %s. If you get close to a limit, prioritize leaving something playable." % (", ".join(limits) if not limits.is_empty() else "unlimited"),
		"Don't make commits or switch branches: the harness handles the git checkpoints.",
		"",
		GameCriteria.generator_text(criteria),
	])


# --- controles -----------------------------------------------------------------------------------

func pause() -> void:
	if phase != RunPhase.RUNNING and phase != RunPhase.EVALUATING:
		return
	if phase == RunPhase.EVALUATING:
		_resume_qa = true
	resume_task = _task_name(_current_task)
	_set_phase(RunPhase.PAUSED)
	_add_activity("status", I18n.t("Paused by the user"))
	if _turn_running:
		controller.cancel()


## Fases desde las que se puede retomar (Retomar, Reintentar, Cambiar de cuenta).
func can_resume() -> bool:
	return phase in [RunPhase.PAUSED, RunPhase.PAUSED_QUOTA, RunPhase.LIMITED, RunPhase.WAITING_CONFIRM]


func resume() -> void:
	if not can_resume():
		return
	var was_limited := phase == RunPhase.LIMITED or quota.is_limited()
	pause_note = ""
	_set_phase(RunPhase.RUNNING)
	if was_limited:
		quota.note_retry()
	if _resume_qa:
		_evaluate()
		return
	# Un run cargado de disco retoma su propia sesión, aunque el dock tenga otra abierta.
	var from_disk := not _recovered_session_id.is_empty()
	var lost_id := _recovered_session_id if from_disk else model.session_id
	if not controller.is_connected_to_agent() or (from_disk and model.session_id != lost_id):
		if not await _restart_session(lost_id):
			_recovered_session_id = ""
			_finish(I18n.t("Couldn't reopen the session with the agent."))
			return
		_recovered_session_id = ""
		model.set_harness_mode(SessionModel.HarnessMode.ONESHOT)
		var why := _reopen_reason if not _reopen_reason.is_empty() else ("editor" if from_disk else "lost")
		_reopen_reason = ""
		if not lost_id.is_empty() and model.session_id == lost_id:
			_add_activity("session", I18n.t(REOPEN_LOADED[why]))
			_run_turn(_resume_prompt())
		else:
			_add_activity("session", I18n.t(REOPEN_NEW[why]))
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
	_add_activity("session", I18n.t("Account switch: restarting the agent and resuming the same session"))
	controller.stop()
	_recovered_session_id = session_id
	_reopen_reason = "account"
	resume()


func stop() -> void:
	if not is_active():
		return
	if _turn_running:
		controller.cancel()
	_finish(I18n.t("Stopped by the user."))


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
	if _turn_running or phase in [RunPhase.PREPARING, RunPhase.CLOSING, RunPhase.LIMITED]:
		_queue_guidance(text)
		changed.emit()
		return
	if phase in [RunPhase.PAUSED, RunPhase.PAUSED_QUOTA, RunPhase.WAITING_CONFIRM, RunPhase.SPEC_REVIEW]:
		pause_note = ""
		_set_phase(RunPhase.RUNNING)
	_add_activity("guide", I18n.t("sent: %s") % text)
	_run_turn(text)


## La guía espera al final del turno: queda en la actividad y en el chat, para que se vea que no
## se perdió (m6-14).
func _queue_guidance(text: String) -> void:
	_guidance.append(text)
	_user_guidance.append(text)
	_add_activity("guide", I18n.t("queued: %s") % text)
	model.add_notice(I18n.t("One-shot · queued: “%s”. The agent gets it when the current turn ends.") % text.left(120), ChatEntry.NoticeLevel.INFO)


func _pop_guidance() -> String:
	var text: String = _guidance.pop_front()
	var index := _user_guidance.find(text)
	if index >= 0:
		_user_guidance.remove_at(index)
		_add_activity("guide", I18n.t("sent: %s") % text)
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
	_add_activity("budget", I18n.t("Budgets: %s") % budgets_text())
	var exhausted := [BUDGET_TIME, BUDGET_TOKENS, BUDGET_PLAYTESTS].any(func(budget: String) -> bool: return budget_ratio(budget) >= 1.0)
	if not _closed_budget().is_empty() and not exhausted:
		_close_reason = ""
		_add_activity("budget", I18n.t("With the new budget, the run continues"))
		if phase == RunPhase.CLOSING:
			_set_phase(RunPhase.RUNNING)
		elif phase == RunPhase.RUNNING:
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
		parts.append("%s %s" % [I18n.t(BUDGET_LABELS[budget]).to_lower(), ("%d min" % limit if budget == BUDGET_TIME else str(limit)) if limit > 0 else I18n.t("unlimited")])
	return ", ".join(parts)


## Presupuesto que agotó el run según `_close_reason`, o "".
func _closed_budget() -> String:
	for budget: String in [BUDGET_TIME, BUDGET_TOKENS, BUDGET_PLAYTESTS]:
		if _close_reason == BUDGET_CLOSE_REASON % budget:
			return budget
	return ""


## `_close_reason` (en inglés, para el agente) para la UI.
func _close_reason_text() -> String:
	var budget := _closed_budget()
	if budget.is_empty():
		return _close_reason
	return I18n.t(BUDGET_CLOSE_REASON) % I18n.t(BUDGET_LABELS[budget]).to_lower()


## «Aprobar spec» (D41): con `text` distinto del archivo, primero se guarda lo que editó el usuario.
func approve_spec(text: String = "") -> void:
	if phase != RunPhase.SPEC_REVIEW:
		return
	var edited := not text.strip_edges().is_empty() and text != files.read(files.spec_path())
	if edited:
		files.write(files.spec_path(), text)
	_awaiting_spec = false
	_add_activity("spec", I18n.t("Spec approved with the user's changes") if edited else I18n.t("Spec approved"))
	_set_phase(RunPhase.RUNNING)
	_run_turn("The spec is approved%s. Continue with the rest: make the plan from the spec and build." % (" with changes: reread it before making the plan" if edited else ""))


## El usuario editó el plan: se manda como guía.
func edit_plan(lines: PackedStringArray) -> void:
	var items: PackedStringArray = []
	for i in lines.size():
		if not lines[i].strip_edges().is_empty():
			items.append("%d. %s" % [items.size() + 1, lines[i].strip_edges()])
	if not items.is_empty():
		guide("I updated the plan; continue with this one (reread it and update your plan tool):\n" + "\n".join(items))


## "Volver acá": pausa, restaura el checkpoint y recarga el editor. Devuelve "" o el error.
func restore(checkpoint_entry: Dictionary) -> String:
	if not checkpoints_enabled:
		return I18n.t("Checkpoints are turned off.")
	if _turn_running:
		resume_task = str(checkpoint_entry.get("label", ""))
		_set_phase(RunPhase.PAUSED)
		controller.cancel()
		while _turn_running:
			await get_tree().process_frame
	var changed_paths: Variant = await _git(func() -> Variant: return await git.restore(checkpoint_entry))
	if changed_paths == null:
		return git.last_error
	if after_restore.is_valid():
		after_restore.call(changed_paths)
	resume_task = str(checkpoint_entry.get("label", ""))
	_add_activity("checkpoint", I18n.t("Went back to %s (%s) · %d files") % [checkpoint_entry.name, checkpoint_entry.label, (changed_paths as PackedStringArray).size()])
	if is_active():
		_set_phase(RunPhase.PAUSED)
	changed.emit()
	return ""


## "Aceptar todo": commit final en la rama del agente; el merge lo hace el usuario.
func accept_all() -> String:
	if not checkpoints_enabled:
		return I18n.t("Checkpoints are turned off: there is no agent branch.")
	if _turn_running:
		controller.cancel()
	var ok: bool = await _git(func() -> Variant: return await git.accept(goal))
	if not ok:
		return git.last_error
	_add_activity("checkpoint", I18n.t("The branch %s is ready to merge (the harness doesn't merge or push)") % git.agent_branch)
	_finish(I18n.t("Changes accepted in %s.") % git.agent_branch)
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
	var turn_started := _elapsed_ms()
	_turn_tools = 0
	var first_entry := model.entries().size()
	var progress_before := _progress()
	var reason: String = await controller.send_in_mode(SessionModel.HarnessMode.ONESHOT, text)
	_turn_running = false
	if not is_instance_valid(self) or not is_inside_tree():
		return
	_account_tokens(controller.last_turn_usage)
	var turn_ms := _elapsed_ms() - turn_started
	report.observe_turn(turn_started, turn_ms, reason, _turn_tools)
	var note := ""
	if TURN_END_NOTES.has(reason):
		note = " · " + I18n.t(TURN_END_NOTES[reason])
	elif reason.is_empty():
		note = " · " + I18n.t("couldn't send")
	elif reason != "end_turn":
		note = " · " + reason
	var turn_format := I18n.t("Turn %d · %s · %d tool") if _turn_tools == 1 else I18n.t("Turn %d · %s · %d tools")
	_add_activity("turn", turn_format % [report.turns.size(), RunReport.format_ms(turn_ms), _turn_tools] + note)
	if reason == "error" or reason.is_empty():
		report.count("turn_errors")
	var turn_text := controller.agent_text_since(first_entry)
	var new_checks: Array = FindingsParser.parse(turn_text).checks
	_merge_checks(new_checks)
	if phase == RunPhase.RUNNING:
		_on_loop(loops.observe_checks(new_checks), false)
	var summary := _summary_of(turn_text)
	if not summary.is_empty():
		_add_activity("agent", summary)
	if _progress() > progress_before:
		_idle_continues = 0
	if reason == "end_turn":
		_quota_checkpoint_done = false
	await _after_turn(reason)


func _after_turn(reason: String) -> void:
	match phase:
		RunPhase.CLOSING:
			_finish(_close_reason_text() if not _close_reason.is_empty() else I18n.t("Finished."))
			return
		RunPhase.FINISHED, RunPhase.PAUSED, RunPhase.PAUSED_QUOTA, RunPhase.WAITING_CONFIRM, RunPhase.IDLE:
			return
	if quota.is_limited():
		await _enter_limited()
		return
	if reason.is_empty():  # no se pudo mandar: la sesión no estaba lista
		resume_task = _task_name(_current_task)
		_set_phase(RunPhase.PAUSED)
		_add_activity("session", I18n.t("The agent wasn't ready for another turn: resume whenever you want"))
		return
	if reason == "error" and not controller.is_connected_to_agent():
		resume_task = _task_name(_current_task)
		_set_phase(RunPhase.PAUSED)
		_add_activity("session", I18n.t("The agent closed: resume whenever you want (a new session opens with the summary)"))
		return
	if not _close_reason.is_empty():
		_close()
		return
	if phase == RunPhase.RUNNING and quota.state == QuotaMonitor.QuotaState.PAUSE_SCHEDULED and reason != "cancelled":
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
		_run_turn("Keep going with the plan: the next pending task is “%s”. Verify with run_scene, capture_game_frame and get_errors, and report the checks block." % _task_name(_next_pending()))
		return
	_done(I18n.t("The agent finished the plan.") if not _plan_pending() else I18n.t("The agent stopped making progress on the plan."))


## Sin plan, lo que falta sale de los checks: el agente a veces cierra el turno a mitad de camino
## ("pruebo si add_node acepta…"). Termina cuando todos pasan o cuando deja de avanzar.
func _after_turn_without_plan() -> void:
	var open: PackedStringArray = []
	for check: Dictionary in checks:
		# Un check que rechazó el evaluador está abierto hasta que el agente reporta que lo arregló.
		var status: String = check.get("claimed", check.status)
		if status != "pass":
			open.append("“%s” (%s)" % [check.label, status])
	if not checks.is_empty() and open.is_empty():
		_done(I18n.t("The agent finished: all checks pass."))
		return
	if _idle_continues >= MAX_IDLE_CONTINUES:
		_done(I18n.t("The agent stopped making progress (no plan; some checks still don't pass).") if not open.is_empty() else I18n.t("The agent finished without reporting checks."))
		return
	_idle_continues += 1
	if open.is_empty():
		_run_turn("If anything in the goal is missing, keep going. If it's done, verify it with run_scene and capture_game_frame and report the checks block.")
	else:
		_run_turn("Keep going with the goal: some checks still don't pass: %s. Verify with run_scene, capture_game_frame and get_errors, and report the checks block." % ", ".join(open))


func _enter_spec_review() -> void:
	_set_phase(RunPhase.SPEC_REVIEW)
	if files.has_spec():
		_add_activity("spec", I18n.t("%s/%s is ready: review and approve it so the agent starts building") % [files.relative_dir(), OneShotFiles.SPEC])
	else:
		_add_activity("warning", I18n.t("The agent didn't write %s/%s. Ask it in the chat to write it, or approve to continue without a spec.") % [files.relative_dir(), OneShotFiles.SPEC])
	model.add_notice(I18n.t("One-shot · the spec is ready for review in the One-shot screen."), ChatEntry.NoticeLevel.INFO)


func _close() -> void:
	_set_phase(RunPhase.CLOSING)
	_add_activity("budget", _close_reason_text())
	_run_turn("%s Don't continue with the plan: write the final report (what got done, what's missing and how to test it) and the checks block." % _close_reason)


func _finish(reason: String) -> void:
	_end_qa_role()
	finish_reason = reason
	_timer.stop()
	_recovered_session_id = ""
	_add_activity("status", reason)
	_set_phase(RunPhase.FINISHED)
	store.prune()
	_write_report()


## Informe con lo medido (D39): se muestra en la pantalla y queda en `<id>.report.json`.
func _write_report() -> void:
	var data := {
		"id": run_id, "goal": goal, "finish_reason": finish_reason, "duration_ms": _elapsed_ms(),
		"budgets": budgets.duplicate(), "used": used.duplicate(), "checks": checks.duplicate(true),
		"files_dir": files.relative_dir(), "qa": qa_results.duplicate(true),
	}
	# changes_summary espera la cola de git: después, los checkpoints en curso ya están en la lista.
	data["changes"] = await changes_summary() if checkpoints_enabled else {}
	data["checkpoints"] = git.checkpoints.map(func(cp: Dictionary) -> Dictionary: return {"name": cp.name, "label": cp.label}) if checkpoints_enabled else []
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
	var where := "" if last.is_empty() else "; the state is in checkpoint %s (%s)" % [last.name, last.label]
	var handoff := " If you're missing context, reread spec.md and progress.md in %s." % files.dir() if files.has_spec() else ""
	if task.is_empty():
		return "Continue with the goal from where you left off%s.%s" % [where, handoff]
	return "Continue with the plan from the task “%s”%s.%s" % [task, where, handoff]


func _summary_prompt() -> String:
	var lines: PackedStringArray = ["We're resuming a One-shot that was interrupted.", "", initial_prompt(), ""]
	if files.has_spec():
		lines.append_array(["The handoff is in %s: read spec.md and progress.md (and the qa-*.md files, if any) before continuing; the spec is already written." % files.dir(), ""])
	lines.append("Plan so far:")
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
	if not is_active() or model.replaying or phase == RunPhase.EVALUATING:  # el plan del evaluador no es el del run
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
		_add_activity("plan", I18n.t("Task %d: %s") % [in_progress + 1, task])
		if phase == RunPhase.RUNNING and quota.state == QuotaMonitor.QuotaState.PAUSE_SCHEDULED and previous >= 0:
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
		if current_plan().is_empty() and checkpoints_enabled and phase != RunPhase.EVALUATING:
			_checkpoint("Playtest #%d" % used[BUDGET_PLAYTESTS])
		_check_budgets()
	elif not name.is_empty() or call.status == ToolCall.STATUS_FAILED:
		_add_activity("tool", _one_line("%s · %s · %s" % [call.display_name(), RunReport.format_ms(call.duration_msec()), _call_summary(call)]))
	if call.status != ToolCall.STATUS_CANCELLED and not _loop_calls.has(call.id):
		_loop_calls[call.id] = true
		var failed := call.status == ToolCall.STATUS_FAILED
		report.observe_tool(RunReport.tool_label(call.title, name, call.tool_name, call.kind), failed, call.duration_msec())
		_turn_tools += 1
		if phase == RunPhase.RUNNING:
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
		pause_note = I18n.t("One-shot paused: the agent is still in a loop (%s) even after being asked for another approach. Tell it in the chat how to continue, or resume whenever you want.") % finding.label
		resume_task = _task_name(_current_task)
		_set_phase(RunPhase.PAUSED)
		_add_activity("loop", I18n.t("Paused: %s again") % finding.label)
		model.add_notice(pause_note, ChatEntry.NoticeLevel.WARNING)
		if _turn_running:
			controller.cancel()
		return
	_add_activity("loop", I18n.t("Possible loop: %s") % finding.label)
	model.add_notice(I18n.t("One-shot · possible loop: %s. Asking the agent for another approach.") % finding.label, ChatEntry.NoticeLevel.WARNING)
	_guidance.append("It looks like you're in a loop: %s. Don't repeat it the same way: think about why it doesn't work and try another approach (another solution, another file, or simplify the task). If something can't be solved, note it in the checks block and continue with the rest." % finding.text)
	if mid_turn and _turn_running:
		controller.cancel()  # la guía se manda al cortar el turno (_after_turn)
	changed.emit()


## Checks que reporta el agente que construye. Con evaluador, el estado de un check que ya evaluó
## (`verified`) lo decide el evaluador: el autorreporte queda como progreso (`claimed`).
func _merge_checks(new_checks: Array) -> void:
	report.observe_checks(new_checks)
	for check: Dictionary in new_checks:
		var found := false
		for existing: Dictionary in checks:
			if existing.label == check.label:
				if existing.get("verified", false):
					existing["claimed"] = check.status
				else:
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
	if phase in [RunPhase.RUNNING, RunPhase.CLOSING, RunPhase.EVALUATING]:
		used[BUDGET_TIME] = float(used[BUDGET_TIME]) + TICK_S
		_check_budgets()
	_check_quota_pause()
	match phase:
		RunPhase.LIMITED:
			if quota.retry_due():
				_on_quota_back(I18n.t("Quota: the window reset") if quota.limited_until > 0 else I18n.t("Quota: time for a retry"))
		RunPhase.PAUSED_QUOTA:
			var now := int(Time.get_unix_time_from_system())
			if quota.state in [QuotaMonitor.QuotaState.NORMAL, QuotaMonitor.QuotaState.WARNING] or (quota_resume_at > 0 and now >= quota_resume_at):
				_on_quota_back(I18n.t("Quota: available again"))
	changed.emit()


func _check_budgets() -> void:
	if phase != RunPhase.RUNNING:
		return
	for budget: String in [BUDGET_TIME, BUDGET_TOKENS, BUDGET_PLAYTESTS]:
		var ratio := budget_ratio(budget)
		if ratio >= 1.0 and _close_reason.is_empty():
			_close_reason = BUDGET_CLOSE_REASON % budget
			_add_activity("budget", _close_reason_text())
			if _turn_running:
				controller.cancel()
			else:
				_close()
			return
		if ratio >= WARN_RATIO and not _warned.has(budget):
			_warned[budget] = true
			var text := I18n.t("%s: %d %% of the budget.") % [I18n.t(BUDGET_LABELS[budget]), roundi(ratio * 100.0)]
			_add_activity("budget", text)
			model.add_notice(I18n.t("One-shot · %s") % text, ChatEntry.NoticeLevel.WARNING)


## Umbral de pausa (spec §10.1): no corta la tarea en curso. Pausa al empezar la siguiente (con su
## checkpoint) o al terminar el turno, lo que llegue primero; si ninguna llega a tiempo, la red de
## _check_quota_pause corta el turno a mitad de la tarea.
func _pause_for_quota(next_task: String, mid_task: bool = false) -> void:
	resume_task = next_task
	quota_resume_at = quota.pause_resets_at()
	if quota_resume_at <= 0:
		quota_resume_at = int(Time.get_unix_time_from_system()) + PAUSE_RETRY_S
	_quota_scheduled_msec = 0
	_set_phase(RunPhase.PAUSED_QUOTA)
	report.count("quota_pauses")
	var percent := roundi(quota.max_utilization() * 100.0)
	if mid_task:
		_add_activity("quota", I18n.t("Quota at %d %%: the task wasn't finishing, cutting the turn and pausing") % percent)
	elif next_task.is_empty():
		_add_activity("quota", I18n.t("Quota at %d %%: pausing when the turn ends") % percent)
	else:
		_add_activity("quota", I18n.t("Quota at %d %%: pausing before “%s”") % [percent, next_task])
	if checkpoints_enabled:
		_checkpoint(next_task if not next_task.is_empty() else "Quota pause", "-quota" if mid_task else "")
	if _turn_running:
		controller.cancel()


## Red de la pausa por cuota: si la tarea o el turno no terminan en quota_pause_grace_s, o la
## cuota llega a QUOTA_PAUSE_HARD, se corta el turno y se pausa a mitad de la tarea.
func _check_quota_pause() -> void:
	if phase != RunPhase.RUNNING or quota.state != QuotaMonitor.QuotaState.PAUSE_SCHEDULED:
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
	if quota.state != QuotaMonitor.QuotaState.PAUSE_SCHEDULED or phase != RunPhase.RUNNING:
		return ""
	var left := quota_pause_grace_s
	if _quota_scheduled_msec > 0:
		left = maxi(quota_pause_grace_s - int((Time.get_ticks_msec() - _quota_scheduled_msec) / 1000.0), 0)
	return I18n.t("Quota at %d %%: the One-shot pauses when the current task or turn ends (if they don't end within %s, it cuts the turn and pauses anyway)") % [
		roundi(quota.max_utilization() * 100.0), QuotaMonitor.format_duration(left)]


## Límite a mitad de turno: tool calls pendientes → cancelled, cpN-quota y "Limitado".
func _enter_limited() -> void:
	model.cancel_unfinished_tool_calls()
	resume_task = _task_name(_current_task) if _current_task >= 0 else _task_name(_next_pending())
	_set_phase(RunPhase.LIMITED)
	report.count("limited")
	quota_resume_at = quota.limited_until
	if quota.limited_until > 0:
		var until := Time.get_time_string_from_unix_time(quota.limited_until + int(Time.get_time_zone_from_system().get("bias", 0)) * 60).left(5)
		_add_activity("quota", I18n.t("Plan limit reached until %s") % until)
	else:
		_add_activity("quota", I18n.t("Plan limit reached, with no reset time (retries at 5, 10, 20 and every 60 min)"))
	if checkpoints_enabled and not _quota_checkpoint_done:
		_quota_checkpoint_done = true
		await _checkpoint(resume_task, "-quota")


## `text`: por qué se retoma, para la actividad.
func _on_quota_back(text: String) -> void:
	_add_activity("quota", text)
	if resume_auto:
		resume()
	else:
		_set_phase(RunPhase.WAITING_CONFIRM)


# --- evaluador (D55) -------------------------------------------------------------------------------

## El agente da el objetivo por cumplido (o dejó de avanzar). Si quedan vueltas de QA y
## presupuesto, evalúa un agente aparte; si no, termina.
func _done(reason: String) -> void:
	if qa_max_rounds > 0 and qa_round < qa_max_rounds and _budget_left():
		_done_reason = reason
		await _evaluate()
		return
	_finish(reason)


## Una vuelta de QA: sesión nueva del agente (sin el contexto del que construye), con permisos de
## solo lectura más correr el juego, y el prompt escéptico con la rúbrica.
func _evaluate() -> void:
	if not _resume_qa:
		qa_round += 1
	_resume_qa = false
	_idle_continues = 0
	pause_note = ""
	_set_phase(RunPhase.EVALUATING)
	_add_activity("qa", I18n.t("QA round %d: an independent evaluator plays and checks the game") % qa_round)
	if not controller.is_connected_to_agent() and not await _restart_session(_saved_session_id()):
		_finish(I18n.t("Couldn't open a session with the agent."))
		return
	_recovered_session_id = ""
	if _generator_session_id.is_empty():
		_generator_session_id = model.session_id
	controller.policy.restrictions = QA_RESTRICTIONS.duplicate()
	controller.mode_rules_override = QA_MODE_RULES
	var opened: bool = await controller.open_session_keeping_previous()
	if not is_inside_tree() or phase != RunPhase.EVALUATING:
		_end_qa_role()
		return
	model.set_harness_mode(SessionModel.HarnessMode.ONESHOT)
	if not opened:
		_end_qa_role()
		_add_activity("warning", I18n.t("Couldn't open the evaluator's session"))
		await _back_to_generator()
		_finish(_done_reason)
		return
	var turn := await _run_qa_turn(qa_prompt())
	if not is_inside_tree():
		return
	await _after_qa(str(turn.reason), str(turn.text))


func qa_prompt() -> String:
	var lines: PackedStringArray = [
		"%s · round %d of at most %d" % [QA_MARKER, qa_round, qa_max_rounds],
		"",
		"Another agent built this game and says it is done. You are the QA evaluator: you did not build it, and builders are lenient with their own work. Be skeptical: find what does not work before anyone else does.",
		"Goal: %s" % goal,
	]
	if files.has_spec():
		lines.append("The spec is in %s and the builder's notes in %s: treat the notes as claims to verify, not facts." % [files.spec_path(), files.progress_path()])
	if qa_round > 1 and FileAccess.file_exists(files.qa_path(qa_round - 1)):
		lines.append("The previous QA report is %s: check that each of its problems is really fixed, then look for new ones." % files.qa_path(qa_round - 1))
	lines.append_array([
		"",
		"How to evaluate:",
		"- Play it like a user: godot.run_scene with inputs, godot.game_input for live keys, actions and clicks, godot.capture_game_frame to look at it, and godot.game_tree, godot.game_get and godot.game_wait to verify facts (the score went up, the enemy died, the level changed) instead of guessing from a frame.",
		"- Read the code and the scenes, and check godot.get_errors.",
		"- Do not change anything: edits, project settings and shell commands are denied. Report problems; the builder fixes them.",
		"- If you found a problem, it fails. Do not talk yourself into approving it.",
	])
	if not checks.is_empty():
		lines.append_array(["", "Checks the builder reported (decide each one yourself, keeping the same label):"])
		for check: Dictionary in checks:
			lines.append("- %s (builder says: %s)" % [check.label, check.get("claimed", check.status)])
	lines.append_array([
		"",
		GameCriteria.evaluator_rubric(criteria),
		"",
		"Answer with your report and one ```json block: {\"checks\":[{\"label\",\"status\":\"pass|fail\",\"detail\"}], \"scores\":[{\"criterion\",\"score\",\"reason\"}], \"findings\":[{\"title\",\"body\":\"what fails and how to reproduce it\",\"path\":\"res://… where (if you know)\",\"line\",\"severity\":\"bug|order|perf|style\"}]}. Add a check for each problem you find that no check covers.",
	])
	return "\n".join(lines)


func _run_qa_turn(text: String) -> Dictionary:
	_turn_running = true
	report.count("turns")
	report.count("qa_turns")
	var turn_started := _elapsed_ms()
	_turn_tools = 0
	var first_entry := model.entries().size()
	var reason: String = await controller.send_in_mode(SessionModel.HarnessMode.ONESHOT, text)
	_turn_running = false
	if not is_instance_valid(self) or not is_inside_tree():
		return {"reason": "", "text": ""}
	_account_tokens(controller.last_turn_usage)
	var turn_ms := _elapsed_ms() - turn_started
	report.observe_turn(turn_started, turn_ms, reason, _turn_tools)
	var turn_format := I18n.t("QA turn · %s · %d tool") if _turn_tools == 1 else I18n.t("QA turn · %s · %d tools")
	_add_activity("turn", turn_format % [RunReport.format_ms(turn_ms), _turn_tools])
	return {"reason": reason, "text": controller.agent_text_since(first_entry)}


func _after_qa(reason: String, text: String) -> void:
	if phase != RunPhase.EVALUATING:  # se pausó o se detuvo durante la evaluación
		_end_qa_role()
		return
	if reason != "end_turn":
		_end_qa_role()
		_resume_qa = true
		if quota.is_limited():
			await _enter_limited()
			return
		resume_task = ""
		_set_phase(RunPhase.PAUSED)
		_add_activity("session", I18n.t("The evaluator's turn didn't finish: “Resume” evaluates again"))
		return
	var parsed := FindingsParser.parse(text, controller.cwd)
	var verdict := GameCriteria.verdict(parsed.scores, criteria)
	var failing_checks: Array = parsed.checks.filter(func(check: Dictionary) -> bool: return check.status != "pass")
	var conclusive: bool = not parsed.checks.is_empty() or not parsed.scores.is_empty()
	var passed: bool = conclusive and failing_checks.is_empty() and bool(verdict.passed)
	var qa_file := files.qa_path(qa_round)
	files.write(qa_file, "# QA %d\n\n%s\n" % [qa_round, text.strip_edges()])
	_apply_qa_checks(parsed.checks)
	var failing_criteria: Array = verdict.failing.map(func(item: Dictionary) -> String: return "%s %s/%d" % [item.name, _score_text(item.score), item.threshold])
	failing_criteria.append_array(Array(verdict.missing).map(func(id: String) -> String: return "%s (%s)" % [id, I18n.t("no score")]))
	qa_results.append({
		"round": qa_round, "passed": passed, "weighted": verdict.weighted,
		"failing_checks": failing_checks.map(func(check: Dictionary) -> String: return str(check.label)),
		"failing_criteria": failing_criteria, "findings": parsed.findings.size(),
		"file": qa_file.trim_prefix(files.project_root).trim_prefix("/"),
	})
	report.observe_checks(parsed.checks)
	_end_qa_role()
	if not conclusive:
		_add_activity("warning", I18n.t("QA round %d: the evaluator didn't report checks or scores") % qa_round)
	elif passed:
		_add_activity("qa", I18n.t("QA round %d: passes (weighted score %s)") % [qa_round, _score_text(verdict.weighted)])
	else:
		var problems: PackedStringArray = []
		problems.append_array(PackedStringArray(qa_results.back().failing_checks))
		problems.append_array(PackedStringArray(failing_criteria))
		_add_activity("qa", I18n.t("QA round %d: doesn't pass · %s") % [qa_round, ", ".join(problems)])
		for finding: Dictionary in parsed.findings.slice(0, QA_ACTIVITY_FINDINGS):
			_add_activity("qa", "%s · %s%s" % [finding.severity, finding.title, " (%s:%d)" % [finding.path.get_file(), finding.line] if int(finding.line) > 0 else " (%s)" % finding.path.get_file()])
	changed.emit()
	var back := await _back_to_generator()
	if not is_inside_tree() or phase != RunPhase.EVALUATING:
		return
	if not conclusive:
		_finish(I18n.t("%s The evaluator couldn't reach a verdict (see %s).") % [_done_reason, qa_results.back().file])
	elif passed:
		_finish(I18n.t("QA round %d: the game passes.") % qa_round)
	elif qa_round >= qa_max_rounds or not _budget_left() or back == "failed":
		_finish(I18n.t("QA round %d: the game doesn't pass yet (see %s).") % [qa_round, qa_results.back().file])
	else:
		_set_phase(RunPhase.RUNNING)
		var fix := _fix_prompt(failing_checks, verdict, parsed)
		_run_turn(_summary_prompt() + "\n\n" + fix if back == "new" else fix)


## Los checks del evaluador mandan: pasan a `verified` y el autorreporte queda en `claimed`.
func _apply_qa_checks(qa_checks: Array) -> void:
	for check: Dictionary in qa_checks:
		var found := false
		for existing: Dictionary in checks:
			if existing.label == check.label:
				existing.erase("claimed")
				existing.merge(check, true)
				existing["verified"] = true
				found = true
		if not found:
			var added := check.duplicate()
			added["verified"] = true
			checks.append(added)


## El turno de corrección para el agente que construye.
func _fix_prompt(failing_checks: Array, verdict: Dictionary, parsed: Dictionary) -> String:
	var lines: PackedStringArray = [
		"QA round %d: an independent evaluator played the game and it doesn't pass yet. Fix these problems, verify each fix (run_scene, and game_get or game_wait to check facts), update %s and report the checks block. The full report is in %s." % [qa_round, files.progress_path(), files.qa_path(qa_round)],
	]
	if not failing_checks.is_empty():
		lines.append_array(["", "Checks that fail:"])
		for check: Dictionary in failing_checks:
			lines.append("- %s%s" % [check.label, ": " + str(check.detail) if not str(check.get("detail", "")).is_empty() else ""])
	var reasons := {}
	for score: Dictionary in parsed.scores:
		reasons[GameCriteria.match_id(str(score.criterion), criteria)] = str(score.get("reason", ""))
	if not verdict.failing.is_empty() or not verdict.missing.is_empty():
		lines.append_array(["", "Criteria below the minimum:"])
		for item: Dictionary in verdict.failing:
			lines.append("- %s: %s of %d. %s" % [item.name, _score_text(item.score), item.threshold, reasons.get(item.id, "")])
	if not parsed.findings.is_empty():
		lines.append_array(["", "Findings:"])
		for finding: Dictionary in parsed.findings:
			var where: String = finding.path + (":%d" % finding.line if int(finding.line) > 0 else "")
			lines.append("- [%s] %s (%s): %s" % [finding.severity, finding.title, where, finding.body])
	return "\n".join(lines)


## Vuelve a la sesión del agente que construye: "loaded" (session/load), "new" (sesión nueva, va
## con el resumen) o "failed".
func _back_to_generator() -> String:
	var session_id := _generator_session_id
	_generator_session_id = ""
	if session_id.is_empty():
		return "loaded"
	if not await _restart_session(session_id):
		_add_activity("warning", I18n.t("Couldn't go back to the builder's session"))
		return "failed"
	model.set_harness_mode(SessionModel.HarnessMode.ONESHOT)
	if model.session_id == session_id:
		_add_activity("session", I18n.t("Back to the builder's session"))
		return "loaded"
	_add_activity("session", I18n.t("Back to the builder: opened a new session with the plan summary"))
	return "new"


func _end_qa_role() -> void:
	controller.policy.restrictions = {}
	controller.mode_rules_override = ""


## La sesión que se guarda para retomar: la del agente que construye, también mientras evalúa.
func _saved_session_id() -> String:
	if not _recovered_session_id.is_empty():
		return _recovered_session_id
	return _generator_session_id if not _generator_session_id.is_empty() else model.session_id


func _budget_left() -> bool:
	return [BUDGET_TIME, BUDGET_TOKENS, BUDGET_PLAYTESTS].all(func(budget: String) -> bool: return budget_ratio(budget) < 1.0)


static func _score_text(value: Variant) -> String:
	var number := float(value)
	return str(int(number)) if is_equal_approx(number, roundf(number)) else "%.1f" % number


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
		"phase_id": RunPhase.keys()[phase],
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
		"qa_round": qa_round,
		"qa_results": qa_results,
		"resume_qa": _resume_qa or phase == RunPhase.EVALUATING,
		"report": report.to_dict(),
		"session_id": _saved_session_id(),
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
	qa_round = int(data.get("qa_round", 0))
	qa_results.assign(data.get("qa_results", []))
	_resume_qa = bool(data.get("resume_qa", false))
	_generator_session_id = ""
	report.apply(data.get("report", {}) if data.get("report") is Dictionary else {})
	last_report = {}
	_recovered_session_id = str(data.get("session_id", ""))
	_started_msec = Time.get_ticks_msec() - int(data.get("elapsed_ms", 0))
	_phase_since_ms = Time.get_ticks_msec()
	last_capture = store.load_capture(run_id)
	last_capture_caption = str(data.get("capture_caption", ""))
	finish_reason = ""
	_idle_continues = 0
	_suspended = false
	recovered = true
	phase = RunPhase.PAUSED
	# Un run que esperaba la cuota sigue esperándola: retoma solo cuando se reinicia la ventana.
	quota_resume_at = int(data.get("quota_resume_at", 0))
	var waiting_quota := str(data.get("phase_id", "")) in ["LIMITED", "PAUSED_QUOTA"]
	if waiting_quota and quota_resume_at > int(Time.get_unix_time_from_system()):
		phase = RunPhase.PAUSED_QUOTA
		var at := Time.get_time_string_from_unix_time(quota_resume_at + int(Time.get_time_zone_from_system().get("bias", 0)) * 60).left(5)
		if resume_task.is_empty():
			_add_activity("session", I18n.t("The editor closed while the One-shot was waiting for quota: it resumes on its own at %s (“Resume” or “Switch account” to skip the wait).") % at)
		else:
			_add_activity("session", I18n.t("The editor closed while the One-shot was waiting for quota: it resumes on its own at %s and continues from “%s” (“Resume” or “Switch account” to skip the wait).") % [at, resume_task])
	else:
		quota_resume_at = 0
		if resume_task.is_empty():
			_add_activity("session", I18n.t("The editor closed while the One-shot was running. “Resume” reopens the agent's session."))
		else:
			_add_activity("session", I18n.t("The editor closed while the One-shot was running. “Resume” reopens the agent's session and continues from “%s”.") % resume_task)
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
		_add_activity("warning", I18n.t("Couldn't create the checkpoint: %s") % git.last_error)
	else:
		_add_activity("checkpoint", "%s: %s" % [entry.name, entry.label])
	changed.emit()


## Las operaciones git van de a una, en orden.
func _git(operation: Callable) -> Variant:
	_git_pending += 1
	while _git_busy:
		await get_tree().process_frame
	_git_busy = true
	var result: Variant = await operation.call()
	_git_busy = false
	_git_pending -= 1
	return result


func _set_phase(value: RunPhase) -> void:
	if phase == value:
		return
	var wait_kind: String = WAIT_KINDS.get(phase, "")
	if not wait_kind.is_empty() and _phase_since_ms > 0:
		report.add_wait(wait_kind, Time.get_ticks_msec() - _phase_since_ms)
	_phase_since_ms = Time.get_ticks_msec()
	phase = value
	changed.emit()
	_save()


func _add_activity(kind: String, text: String) -> void:
	var entry := {"time": _elapsed_text(), "kind": kind, "text": text}
	activity.append(entry)
	if activity.size() > ACTIVITY_LIMIT:
		activity.remove_at(0)
	activity_added.emit(entry)


## Milisegundos desde que empezó el run (para el contador de la tarea en curso).
func elapsed_ms() -> int:
	return _elapsed_ms()


func _elapsed_ms() -> int:
	return Time.get_ticks_msec() - _started_msec if _started_msec > 0 else 0


func _elapsed_text() -> String:
	var seconds := _elapsed_ms() / 1000
	return "%02d:%02d:%02d" % [seconds / 3600, (seconds / 60) % 60, seconds % 60]


func _task_name(index: int) -> String:
	var plan := current_plan()
	if index >= 0 and index < plan.size() and plan[index] is Dictionary:
		return str(plan[index].get("content", "task %d" % (index + 1)))
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
	var input: Variant = call.godot_arguments()
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
