extends SceneTree
## Loop del One-shot (M6) contra el agente falso, sin editor: checkpoints en un repo temporal,
## pausa por cuota, límite con cpN-quota y reanudación sola o con confirmación, presupuestos,
## "Guiar al agente" y el evaluador con su vuelta de corrección (D55).
## Uso: godot --headless --path <repo> --script tests/oneshot_check.gd

const SessionController := preload("res://addons/godot_agent/session/session_controller.gd")
const SessionModel := preload("res://addons/godot_agent/session/session_model.gd")
const ChatEntry := preload("res://addons/godot_agent/session/chat_entry.gd")
const AgentLog := preload("res://addons/godot_agent/core/agent_log.gd")
const AgentProfile := preload("res://addons/godot_agent/core/agent_profile.gd")
const QuotaMonitor := preload("res://addons/godot_agent/core/quota_monitor.gd")
const OneShotRun := preload("res://addons/godot_agent/oneshot/oneshot_run.gd")
const PermissionPolicy := preload("res://addons/godot_agent/session/permission_policy.gd")

const WATCHDOG_S := 120.0

var _failures: PackedStringArray = []
var _checks: int = 0


func _initialize() -> void:
	await process_frame
	create_timer(WATCHDOG_S).timeout.connect(func() -> void:
		printerr("FAIL oneshot_check: watchdog (%d s)" % WATCHDOG_S)
		quit(1)
	)
	await _scenario_quota()
	await _scenario_quota_turn_end()
	await _scenario_quota_grace()
	await _scenario_account()
	await _scenario_budget()
	await _scenario_budget_raise()
	await _scenario_no_plan()
	await _scenario_remote_control()
	await _scenario_recover()
	await _scenario_loop()
	await _scenario_spec()
	await _scenario_qa()
	await _scenario_qa_without_playing()
	for failure: String in _failures:
		printerr("FAIL " + failure)
	print("oneshot_check: %d checks, %d fallos (%s)" % [_checks, _failures.size(), Engine.get_version_info().string])
	quit(1 if not _failures.is_empty() else 0)


func _profile(scenario: String) -> AgentProfile:
	return AgentProfile.from_dict({
		"id": "fake", "display_name": "Agente falso", "command": OS.get_executable_path(),
		"args": ["--headless", "--no-header", "--path", ProjectSettings.globalize_path("res://"),
			"--script", "res://tests/fake_agent.gd", "--", "--scenario=res://tests/scripts/%s.json" % scenario],
	})


## Repo git temporal con un proyecto mínimo y un commit.
func _repo(name: String) -> String:
	var dir := ProjectSettings.globalize_path("user://oneshot_check/" + name)
	OS.execute("rm", ["-rf", dir])
	DirAccess.make_dir_recursive_absolute(dir)
	var file := FileAccess.open(dir + "/project.godot", FileAccess.WRITE)
	file.store_string("config_version=5\n")
	file.close()
	OS.execute("git", ["-c", "init.defaultBranch=main", "init", "-q", dir])
	OS.execute("git", ["-C", dir, "add", "-A"])
	OS.execute("git", ["-C", dir, "-c", "user.name=t", "-c", "user.email=t@t", "commit", "-q", "-m", "inicio"])
	return dir


## `repo`: carpeta de un repo ya armado (si no, uno nuevo con el nombre del guion).
func _make(scenario: String, repo: String = "") -> OneShotRun:
	var model := SessionModel.new()
	var controller := SessionController.new()
	controller.setup(model, AgentLog.new(), ProjectSettings.globalize_path("res://").trim_suffix("/"))
	var run := OneShotRun.new()
	run.setup(controller, repo if not repo.is_empty() else _repo(scenario))
	run.restart_session = func(_lost_id: String) -> bool: return await controller.start(_profile(scenario))
	run.qa_max_rounds = 0  # los guiones de antes del evaluador terminan con lo que reporta el agente
	root.add_child(run)
	return run


## El editor se cae a mitad de un turno: el run quedó guardado. Otro editor lo carga en pausa y
## «Retomar» sigue en una sesión nueva con el resumen (D37).
func _scenario_recover() -> void:
	print("— recuperación")
	var store_dir := ProjectSettings.globalize_path("user://oneshot_check/store")
	OS.execute("rm", ["-rf", store_dir])
	var run := _make("oneshot_recover")
	run.store.dir = store_dir
	await run.start("Pong con puntaje", {"time": 0, "tokens": 0, "playtests": 0}, true)
	# El primer turno deja plan, playtest y checks; el editor se cae en el segundo.
	await _wait(func() -> bool: return run.checks.size() == 2 and _user_messages(run.model).size() == 2 and not run.is_git_busy(), 10.0)
	await create_timer(2.6).timeout  # un guardado periódico
	var session_id := run.model.session_id
	var checkpoints := _cp_labels(run)
	# Caída: sin suspend() ni _finish(); lo último en disco es el guardado periódico.
	run.set(&"_suspended", true)
	var repo := run.git.root
	run.controller.stop()
	run.queue_free()
	await process_frame

	var again := _make("oneshot_recover_resume", repo)
	again.store.dir = store_dir
	_check(again.restore_interrupted(), "recuperación: carga el run a medias")
	_check(again.recovered and again.phase == OneShotRun.RunPhase.PAUSED, "recuperación: queda en pausa (%s)" % again.phase_label())
	_check(again.goal == "Pong con puntaje" and int(again.used.playtests) == 1 and again.checks.size() == 2, "recuperación: objetivo, playtests y checks")
	_check(_cp_labels(again) == checkpoints and again.checkpoints_enabled, "recuperación: checkpoints %s" % [_cp_labels(again)])
	_check(again.current_plan().size() == 2 and again.resume_task == "Paletas y pelota", "recuperación: plan guardado y tarea (%s)" % again.resume_task)
	_check(str(again.activity.back().text).contains("“Resume”"), "recuperación: la actividad lo explica")
	_check(again.to_dict().session_id == session_id, "recuperación: recuerda la sesión del agente")
	again.resume()
	await _wait(func() -> bool: return again.phase == OneShotRun.RunPhase.FINISHED and not again.is_git_busy(), 15.0)
	var messages := _user_messages(again.model)
	_check(not messages.is_empty() and str(messages[0]).begins_with("We're resuming a One-shot") and str(messages[0]).contains("[in_progress] Paletas y pelota") and str(messages[0]).contains("[pass] Paletas"), "recuperación: sesión nueva con el resumen %s" % [messages.map(func(m: String) -> String: return m.left(60))])
	_check(again.activity.any(func(entry: Dictionary) -> bool: return str(entry.text).begins_with("The editor had closed: opened a new session")), "recuperación: actividad de la sesión nueva")
	_check(again.finish_reason == "The agent finished the plan.", "recuperación: terminó (%s)" % again.finish_reason)
	_check(_cp_labels(again).back() == "cp3 Puntaje", "recuperación: sigue creando checkpoints (%s)" % [_cp_labels(again)])
	_check(again.store.load_interrupted().is_empty(), "recuperación: terminado, ya no se ofrece retomar")
	# Informe (D39): suma lo medido antes y después de la caída, y queda en <id>.report.json.
	await _wait(func() -> bool: return not again.last_report.is_empty(), 10.0)
	var report := again.store.load_report(again.run_id)
	_check(not report.is_empty() and report.id == again.run_id and report.goal == "Pong con puntaje", "informe: guardado en el store")
	var tools: Array = report.get("tools", [])
	_check(tools.any(func(row: Dictionary) -> bool: return row.tool == "godot.run_scene" and int(row.count) == 1), "informe: el playtest de antes de la caída %s" % [tools])
	var tasks: Array = report.get("tasks", [])
	_check(tasks.size() == 2 and tasks.all(func(task: Dictionary) -> bool: return task.status == "completed" and int(task.duration_s) >= 0), "informe: tareas con duración %s" % [tasks])
	_check(report.get("checkpoints", []).size() == 3 and report.get("changes", {}).has("files"), "informe: checkpoints y cambios")
	_check(int(report.get("events", {}).get("turns", 0)) >= 2, "informe: turnos %s" % [report.get("events")])
	again.controller.stop()
	again.queue_free()


func _scenario_quota() -> void:
	print("— cuota")
	var run := _make("oneshot_quota")
	var controller := run.controller
	var model := run.model
	run.resume_auto = true
	var started: bool = await run.start("Pong de 2 jugadores con puntaje", {"time": 10, "tokens": 0, "playtests": 10}, true)
	_check(started, "cuota: arranca")
	_check(model.harness_mode == SessionModel.HarnessMode.ONESHOT, "cuota: modo One-shot")
	_check(str(_user_messages(model)[0]).contains("Goal (One-shot mode): Pong") and str(_user_messages(model)[0]).contains("\"checks\""), "cuota: prompt inicial")

	# Turno 1: cp2 antes de la tarea 1; al 91 % la tarea 2 crea su checkpoint y se pausa.
	await _wait(func() -> bool: return run.phase == OneShotRun.RunPhase.PAUSED_QUOTA and not run.is_git_busy(), 10.0)
	_check(run.phase == OneShotRun.RunPhase.PAUSED_QUOTA, "cuota: pausado por cuota (%s)" % run.phase_label())
	_check(_cp_labels(run) == ["cp1 Initial state", "cp2 Paletas y pelota", "cp3 Puntaje y saque"], "cuota: checkpoints %s %s" % [_cp_labels(run), run.activity.map(func(e: Dictionary) -> String: return e.kind + ":" + e.text)])
	_check(int(run.used.playtests) == 1, "cuota: un playtest contado")
	_check(run.last_capture != null and run.last_capture.get_width() == 16, "cuota: captura del playtest")
	_check(run.checks.size() == 2 and run.checks[0].status == "pass", "cuota: checks del turno")
	_check(not _agent_text(model).contains("Esto no debería llegar"), "cuota: el turno se cortó en el checkpoint")
	_check(run.resume_task == "Puntaje y saque", "cuota: retoma en la tarea 2")

	# A los 3 s se reinicia la ventana y retoma solo; el turno 2 choca con el límite. Desde ahí espera
	# confirmación (se cambia al entrar en "limitado": la ventana se reinicia en 3 s).
	run.changed.connect(func() -> void:
		if run.phase == OneShotRun.RunPhase.LIMITED:
			run.resume_auto = false)
	await _wait(func() -> bool: return run.phase == OneShotRun.RunPhase.LIMITED and not run.is_git_busy(), 10.0)
	_check(_user_messages(model).size() >= 2 and str(_user_messages(model)[1]).contains("Continue with the plan from the task “Puntaje y saque”; the state is in checkpoint cp3"), "cuota: prompt de reanudación (%s)" % str(_user_messages(model).back()).left(120))
	_check(run.phase == OneShotRun.RunPhase.LIMITED, "cuota: limitado (%s)" % run.phase_label())
	_check(_cp_labels(run).back() == "cp4-quota Puntaje y saque", "cuota: cpN-quota (%s)" % [_cp_labels(run)])
	_check(controller.quota.seconds_until_retry() > 0, "cuota: cuenta regresiva")
	var time_before := float(run.used.time)

	await _wait(func() -> bool: return run.phase == OneShotRun.RunPhase.WAITING_CONFIRM, 10.0)
	_check(run.phase == OneShotRun.RunPhase.WAITING_CONFIRM, "cuota: espera confirmación (%s)" % run.phase_label())
	_check(float(run.used.time) == time_before, "cuota: el tiempo en limitado no cuenta")
	run.resume()
	await _wait(func() -> bool: return run.phase == OneShotRun.RunPhase.FINISHED and not run.is_git_busy(), 10.0)
	_check(str(_user_messages(model).back()).contains("from the task “Puntaje y saque”; the state is in checkpoint cp4-quota"), "cuota: retoma desde cp4-quota")
	_check(run.phase == OneShotRun.RunPhase.FINISHED and run.finish_reason == "The agent finished the plan.", "cuota: terminó (%s)" % run.finish_reason)
	_check(_cp_labels(run).back() == "cp5 Playtest final", "cuota: checkpoint de la última tarea (%s)" % [_cp_labels(run)])
	_check(controller.quota.state == QuotaMonitor.QuotaState.NORMAL, "cuota: normal después del reinicio")
	_check(run.checks.size() == 2 and run.checks[1].status == "pass", "cuota: checks actualizados")
	var log := await run.git.run(["log", "--format=%s", "-6"])
	_check(log.output.begins_with("cp5: Playtest final\ncp4-quota: Puntaje y saque\ncp3: Puntaje y saque\ncp2: Paletas y pelota\ncp1: Initial state"), "cuota: commits en la rama del agente:\n" + log.output)
	controller.stop()
	run.queue_free()


## Sin pasar a otra tarea, la pausa por cuota llega al terminar el turno: no se manda «Seguí con
## el plan» con la cuota al 92 % (pasó en un run real que nunca cambiaba de tarea).
func _scenario_quota_turn_end() -> void:
	print("— cuota al terminar el turno")
	var run := _make("oneshot_quota_turn")
	run.resume_auto = true
	await run.start("Platformer", {"time": 0, "tokens": 0, "playtests": 0}, true)
	await _wait(func() -> bool: return run.phase == OneShotRun.RunPhase.PAUSED_QUOTA and not run.is_git_busy(), 10.0)
	_check(run.phase == OneShotRun.RunPhase.PAUSED_QUOTA, "cuota-turno: pausa al terminar el turno (%s)" % run.phase_label())
	_check(_user_messages(run.model).size() == 1, "cuota-turno: no manda otro turno (%d)" % _user_messages(run.model).size())
	_check(run.resume_task == "Nivel 1", "cuota-turno: retoma en la tarea en curso (%s)" % run.resume_task)
	_check(run.activity.any(func(entry: Dictionary) -> bool: return str(entry.text).contains("pausing before “Nivel 1”")), "cuota-turno: la actividad lo dice")
	await _wait(func() -> bool: return run.phase == OneShotRun.RunPhase.FINISHED and not run.is_git_busy(), 15.0)
	_check(run.phase == OneShotRun.RunPhase.FINISHED, "cuota-turno: retoma solo y termina (%s)" % run.phase_label())
	_check(str(_user_messages(run.model)[1]).contains("from the task “Nivel 1”"), "cuota-turno: prompt de reanudación")
	run.controller.stop()
	run.queue_free()


## La tarea y el turno no terminan: pasado el tope de espera se corta el turno y se pausa con un
## checkpoint -quota.
func _scenario_quota_grace() -> void:
	print("— cuota con tope de espera")
	var run := _make("oneshot_quota_grace")
	run.quota_pause_grace_s = 1
	await run.start("Platformer", {"time": 0, "tokens": 0, "playtests": 0}, true)
	await _wait(func() -> bool: return run.phase == OneShotRun.RunPhase.PAUSED_QUOTA and not run.is_git_busy(), 8.0)
	_check(run.phase == OneShotRun.RunPhase.PAUSED_QUOTA, "cuota-tope: pausa sin esperar a la tarea (%s)" % run.phase_label())
	_check(run.quota_pause_text().is_empty(), "cuota-tope: el banner ya no dice que va a pausar")
	await _wait(func() -> bool: return run.model.state == SessionModel.SessionState.READY, 5.0)
	_check(not _agent_text(run.model).contains("no debería llegar"), "cuota-tope: el turno se cortó")
	_check(_cp_labels(run).back() == "cp3-quota Nivel 1", "cuota-tope: checkpoint -quota (%s)" % [_cp_labels(run)])
	_check(run.activity.any(func(entry: Dictionary) -> bool: return str(entry.text).contains("the task wasn't finishing")), "cuota-tope: la actividad lo explica")
	run.stop()
	run.controller.stop()
	run.queue_free()


## Límite del plan: el run guardado sigue esperando la cuota al reabrir el editor, y «Cambiar de
## cuenta» relanza el agente y sigue sin esperar (m6-15).
func _scenario_account() -> void:
	print("— cambio de cuenta")
	var store_dir := ProjectSettings.globalize_path("user://oneshot_check/store_account")
	OS.execute("rm", ["-rf", store_dir])
	var run := _make("oneshot_account")
	run.store.dir = store_dir
	await run.start("Platformer", {"time": 0, "tokens": 0, "playtests": 0}, true)
	await _wait(func() -> bool: return run.phase == OneShotRun.RunPhase.LIMITED and not run.is_git_busy(), 10.0)
	_check(run.phase == OneShotRun.RunPhase.LIMITED, "cuenta: limitado (%s)" % run.phase_label())
	var now := int(Time.get_unix_time_from_system())
	_check(run.quota_resume_at > now + 3000, "cuenta: guarda cuándo se reinicia la ventana (%d)" % (run.quota_resume_at - now))
	run.suspend()
	run.controller.stop()
	run.queue_free()

	var again := _make("oneshot_account")
	again.store.dir = store_dir
	again.resume_auto = true
	_check(again.restore_interrupted(), "cuenta: se restaura al reabrir")
	_check(again.phase == OneShotRun.RunPhase.PAUSED_QUOTA, "cuenta: sigue esperando la cuota (%s)" % again.phase_label())
	_check(again.quota_resume_at > now + 3000, "cuenta: con la hora de reinicio")
	_check(str(again.activity.back().text).contains("resumes on its own at"), "cuenta: la actividad dice cuándo retoma (%s)" % again.activity.back().text)
	await create_timer(1.5).timeout
	_check(again.phase == OneShotRun.RunPhase.PAUSED_QUOTA, "cuenta: no retoma antes de hora")
	again.restart_session = func(_lost_id: String) -> bool: return await again.controller.start(_profile("oneshot_account_after"))
	again.switch_account()
	await _wait(func() -> bool: return again.phase == OneShotRun.RunPhase.FINISHED and not again.is_git_busy(), 15.0)
	_check(again.phase == OneShotRun.RunPhase.FINISHED, "cuenta: retoma con la cuenta nueva y termina (%s · %s)" % [again.phase_label(), again.finish_reason])
	_check(again.activity.any(func(entry: Dictionary) -> bool: return str(entry.text).begins_with("Account switch: opened a new session")), "cuenta: la actividad lo dice")
	_check(int(again.report.events.get("account_switches", 0)) == 1, "cuenta: el informe lo cuenta")
	_check(again.activity.any(func(entry: Dictionary) -> bool: return str(entry.text).begins_with("Turn ") and str(entry.text).contains(" · ")), "tiempos: la actividad registra cada turno")
	_check(int(again.last_report.get("timing", {}).get("waiting_quota_s", -1)) >= 1, "tiempos: el informe cuenta la espera por cuota (%s)" % [again.last_report.get("timing", {})])
	again.controller.stop()
	again.queue_free()


func _scenario_budget() -> void:
	print("— presupuestos")
	var run := _make("oneshot_budget")
	var controller := run.controller
	var model := run.model
	var notices: Array[String] = []
	model.entry_added.connect(func(entry: ChatEntry) -> void:
		if entry.kind == ChatEntry.EntryKind.NOTICE:
			notices.append(entry.text))
	await run.start("Pong", {"time": 0, "tokens": 0, "playtests": 5}, false)
	_check(not run.checkpoints_enabled, "presupuestos: sin checkpoints")
	await _wait(func() -> bool: return int(run.used.playtests) >= 1, 5.0)
	run.guide("Usá paletas blancas y fondo negro.")
	await _wait(func() -> bool: return int(run.used.playtests) >= 4, 5.0)
	_check(notices.any(func(text: String) -> bool: return text.contains("Playtests: 80 %")), "presupuestos: aviso al 80 %% (%s)" % [notices])
	await _wait(func() -> bool: return run.phase == OneShotRun.RunPhase.FINISHED, 15.0)
	var messages := _user_messages(model)
	_check(messages.size() == 3, "presupuestos: inicial, guía y cierre (%d)" % messages.size())
	if messages.size() == 3:
		_check(messages[1] == "Usá paletas blancas y fondo negro.", "presupuestos: la guía va al terminar el turno")
		_check(str(messages[2]).begins_with("The playtests budget ran out.") and str(messages[2]).contains("final report"), "presupuestos: prompt de cierre")
	var guide_entries: Array = run.activity.filter(func(entry: Dictionary) -> bool: return entry.kind == "guide").map(func(entry: Dictionary) -> String: return entry.text)
	_check(guide_entries == ["queued: Usá paletas blancas y fondo negro.", "sent: Usá paletas blancas y fondo negro."], "presupuestos: la guía queda en cola y después sale %s" % [guide_entries])
	_check(notices.any(func(text: String) -> bool: return text.begins_with("One-shot · queued: “Usá paletas")), "presupuestos: el chat avisa que la guía está en cola")
	_check(not _agent_text(model).contains("No debería llegar"), "presupuestos: al 100 % corta el turno")
	_check(run.finish_reason == "The playtests budget ran out.", "presupuestos: motivo (%s)" % run.finish_reason)
	_check(run.checks.size() == 2 and run.checks[1].status == "fail", "presupuestos: checks del reporte")
	controller.stop()
	run.queue_free()


## Presupuesto agotado y el usuario lo saca con el run cerrando (m6-12): el pedido de reporte
## queda como un turno más y el run sigue con el plan.
func _scenario_budget_raise() -> void:
	print("— presupuesto con el run en curso")
	var run := _make("oneshot_budget")
	await run.start("Pong", {"time": 0, "tokens": 0, "playtests": 5}, false)
	await _wait(func() -> bool: return run.phase == OneShotRun.RunPhase.CLOSING, 15.0)
	_check(run.phase == OneShotRun.RunPhase.CLOSING, "presupuesto: cerrando por playtests (%s)" % run.phase_label())
	run.set_budgets({"playtests": 0})
	_check(run.phase == OneShotRun.RunPhase.RUNNING and int(run.budgets.playtests) == 0, "presupuesto: ilimitado sigue (%s)" % run.phase_label())
	_check(run.activity.any(func(entry: Dictionary) -> bool: return entry.text == "With the new budget, the run continues"), "presupuesto: la actividad lo dice")
	var closing_at := _user_messages(run.model).size()  # el último es el pedido de reporte
	await _wait(func() -> bool: return _user_messages(run.model).size() > closing_at, 10.0)
	var messages := _user_messages(run.model)
	_check(str(messages[closing_at - 1]).begins_with("The playtests budget ran out.") and messages.size() > closing_at and str(messages[closing_at]).begins_with("Keep going with the plan"), "presupuesto: después del reporte sigue con el plan %s" % [messages.map(func(m: String) -> String: return m.left(40))])
	_check(run.is_active(), "presupuesto: el run no terminó (%s)" % run.phase_label())
	run.set_budgets({"playtests": int(run.used.playtests) + 100, "time": 30})
	_check(run.budgets_text() == "time 30 min, tokens unlimited, playtests %d" % (int(run.used.playtests) + 100), "presupuesto: texto (%s)" % run.budgets_text())
	run.stop()
	await _wait(func() -> bool: return not run.last_report.is_empty(), 5.0)
	_check(int(run.last_report.get("events", {}).get("budget_changes", 0)) == 2, "presupuesto: el informe cuenta los cambios")
	run.controller.stop()
	run.queue_free()


## Un agente que no manda plan por ACP: checkpoint por playtest y su fin de turno es el final.
func _scenario_no_plan() -> void:
	print("— sin plan")
	var run := _make("oneshot_noplan")
	await run.start("Pong", {"time": 0, "tokens": 0, "playtests": 0}, true)
	await _wait(func() -> bool: return run.phase == OneShotRun.RunPhase.FINISHED and not run.is_git_busy(), 10.0)
	_check(run.finish_reason == "The agent finished: all checks pass.", "sin plan: motivo (%s)" % run.finish_reason)
	var messages := _user_messages(run.model)
	_check(messages.size() == 2 and str(messages[1]).contains("“Puntaje” (pending)") and not str(messages[1]).contains("plan"), "sin plan: sigue por el check pendiente, sin hablar de plan %s" % [messages])
	_check(_cp_labels(run) == ["cp1 Initial state", "cp2 Playtest #1", "cp3 Playtest #2"], "sin plan: checkpoint por playtest %s" % [_cp_labels(run)])
	_check(run.checks.size() == 2 and run.checks.all(func(check: Dictionary) -> bool: return check.status == "pass"), "sin plan: checks")
	run.controller.stop()
	run.queue_free()


## Remote Control prendido en el chat (m7-21): empezar el One-shot lo apaga antes del primer turno.
func _scenario_remote_control() -> void:
	print("— Remote Control")
	var run := _make("oneshot_noplan")
	_check(await run.controller.start(_profile("oneshot_noplan")), "remote: la sesión arranca")
	await run.controller.send_prompt(run.controller.remote_control_command(true))
	_check(not run.model.remote_control_url.is_empty(), "remote: prendido antes del run")
	await run.start("Pong", {"time": 0, "tokens": 0, "playtests": 0}, true)
	_check(run.model.remote_control_url.is_empty(), "remote: el run lo apagó")
	_check(run.activity.any(func(entry: Dictionary) -> bool: return entry.text == "Remote Control turned off: One-shot runs on its own."), "remote: queda en la actividad")
	await _wait(func() -> bool: return run.phase == OneShotRun.RunPhase.FINISHED and not run.is_git_busy(), 10.0)
	_check(run.finish_reason == "The agent finished: all checks pass.", "remote: el run sigue normal (%s)" % run.finish_reason)
	run.controller.stop()
	run.queue_free()


## Loops (D38) con umbral 2: dos Edit iguales que fallan cortan el turno y piden otro enfoque;
## el mismo check que falla igual pide otro enfoque y, si vuelve a pasar, pausa el run.
func _scenario_loop() -> void:
	print("— loop")
	var run := _make("oneshot_loop")
	run.loops.repeats = 2
	await run.start("Salto", {"time": 0, "tokens": 0, "playtests": 0}, false)
	await _wait(func() -> bool: return run.phase == OneShotRun.RunPhase.PAUSED, 20.0)
	var messages := _user_messages(run.model)
	_check(run.phase == OneShotRun.RunPhase.PAUSED, "loop: pausa (%s)" % run.phase_label())
	_check(messages.size() == 5, "loop: turnos %s" % [messages])
	_check(messages.size() > 1 and str(messages[1]).contains("loop") and str(messages[1]).contains("“Edit player.gd” failed 2 times"), "loop: el Edit que falla corta el turno y pide otro enfoque %s" % [messages])
	_check(not _agent_text(run.model).contains("no tendría que llegar"), "loop: el turno se cortó")
	_check(messages.size() > 3 and str(messages[3]).contains("“Salto” failed 2 times"), "loop: el check que falla igual pide otro enfoque %s" % [messages])
	var loop_entries := run.activity.filter(func(entry: Dictionary) -> bool: return entry.kind == "loop")
	_check(loop_entries.size() == 3, "loop: actividad %s" % [loop_entries])
	_check(run.pause_note.contains("Salto"), "loop: motivo de la pausa (%s)" % run.pause_note)
	run.guide("Saltá con la tecla espacio")
	_check(run.phase == OneShotRun.RunPhase.RUNNING and run.pause_note.is_empty(), "loop: guiar retoma")
	_check(run.activity.back().kind == "guide" and run.activity.back().text == "sent: Saltá con la tecla espacio", "loop: en pausa la guía sale enseguida")
	await _wait(func() -> bool: return _user_messages(run.model).size() == 6, 10.0)
	run.stop()
	await _wait(func() -> bool: return not run.last_report.is_empty(), 5.0)
	var events: Dictionary = run.last_report.get("events", {})
	_check(int(events.get("loops", 0)) == 3 and int(events.get("guidance", 0)) == 1, "loop: informe %s" % [events])
	var edit: Array = run.last_report.get("tools", []).filter(func(row: Dictionary) -> bool: return row.tool == "Edit")
	_check(edit.size() == 1 and int(edit[0].failed) == 2, "loop: informe cuenta los Edit fallidos %s" % [edit])
	var salto: Array = run.last_report.get("checks", []).filter(func(row: Dictionary) -> bool: return row.label == "Salto")
	_check(salto.size() == 1 and int(salto[0].failures) >= 4, "loop: informe cuenta las fallas del check %s" % [salto])
	run.controller.stop()
	run.queue_free()


## Spec y traspaso por archivos (D41): el agente escribe spec.md y espera; guiar le pide cambios
## y vuelve a esperar; «Aprobar spec» con cambios del usuario sigue construyendo. Los archivos
## quedan en .godot_agent/ (con .gdignore) y entran en los checkpoints.
func _scenario_spec() -> void:
	print("— spec")
	var run := _make("oneshot_spec")
	await run.start("Pong", {"time": 0, "tokens": 0, "playtests": 0}, true, true)
	var spec_path := run.files.spec_path()
	var first := _user_messages(run.model)
	_check(first.size() == 1 and str(first[0]).contains(spec_path) and str(first[0]).contains("end the turn without building") and str(first[0]).contains(run.files.progress_path()), "spec: el prompt pide el spec y el progreso")
	run.files.write(spec_path, "# Pong\nDos paletas.\n")  # lo que haría el agente
	await _wait(func() -> bool: return run.phase == OneShotRun.RunPhase.SPEC_REVIEW, 10.0)
	_check(run.phase == OneShotRun.RunPhase.SPEC_REVIEW, "spec: espera la revisión (%s)" % run.phase_label())
	_check(str(run.activity.back().text).contains("spec.md is ready"), "spec: la actividad lo avisa")
	_check(FileAccess.file_exists(run.git.root.path_join(".godot_agent/.gdignore")), "spec: .gdignore")
	run.guide("Sumá power-ups")
	await _wait(func() -> bool: return run.phase == OneShotRun.RunPhase.SPEC_REVIEW and _user_messages(run.model).size() == 2, 10.0)
	_check(run.phase == OneShotRun.RunPhase.SPEC_REVIEW, "spec: después de guiar vuelve a esperar (%s)" % run.phase_label())
	run.approve_spec("# Pong\nDos paletas y power-ups.\n")
	_check(run.files.read(spec_path).contains("power-ups"), "spec: se guardan los cambios del usuario")
	await _wait(func() -> bool: return run.phase == OneShotRun.RunPhase.FINISHED and not run.is_git_busy() and not run.last_report.is_empty(), 10.0)
	var messages := _user_messages(run.model)
	_check(messages.size() == 3 and str(messages[2]).begins_with("The spec is approved with changes"), "spec: aprobar sigue construyendo %s" % [messages])
	_check(run.finish_reason == "The agent finished: all checks pass.", "spec: terminó (%s)" % run.finish_reason)
	var tracked := []
	OS.execute("git", ["-C", run.git.root, "ls-files", ".godot_agent"], tracked)
	_check(str(tracked[0]).contains("spec.md"), "spec: el spec entra en los checkpoints (%s)" % tracked)
	_check(str(run.last_report.get("files_dir", "")) == run.files.relative_dir(), "spec: el informe apunta a los archivos")
	_check(run.activity.any(func(entry: Dictionary) -> bool: return str(entry.text) == "Spec approved with the user's changes"), "spec: actividad de la aprobación")
	run.controller.stop()
	run.queue_free()


## Evaluador (D55): el agente dice que todo pasa; el evaluador, en una sesión aparte y sin
## permisos de edición, encuentra que el puntaje no sube. Sus hallazgos vuelven al que construye,
## que corrige, y la segunda vuelta de QA aprueba.
func _scenario_qa() -> void:
	print("— evaluador")
	var run := _make("oneshot_qa")
	run.qa_max_rounds = 2
	# La primera sesión es la del guion; las siguientes (volver al que construye) son otro proceso.
	var starts: Array[int] = [0]
	run.restart_session = func(_lost_id: String) -> bool:
		starts[0] += 1
		return await run.controller.start(_profile("oneshot_qa" if starts[0] == 1 else "oneshot_qa_fix"))
	var sent: Array[String] = []  # los prompts de todas las sesiones (cada sesión nueva limpia el modelo)
	run.model.entry_added.connect(func(entry: ChatEntry) -> void:
		if entry.kind == ChatEntry.EntryKind.USER:
			sent.append(entry.text))
	await run.start("Pong con puntaje", {"time": 0, "tokens": 0, "playtests": 0}, false)
	await _wait(func() -> bool: return run.phase == OneShotRun.RunPhase.EVALUATING and sent.size() == 2, 10.0)
	var policy := run.controller.policy
	_check(run.phase == OneShotRun.RunPhase.EVALUATING and run.phase_label().contains("QA round 1"), "qa: evalúa cuando el agente dice que terminó (%s)" % run.phase_label())
	_check(policy.decide(PermissionPolicy.GROUP_EDIT_FILES, SessionModel.HarnessMode.ONESHOT) == PermissionPolicy.DENY and policy.decide(PermissionPolicy.GROUP_EDIT_SCENE, SessionModel.HarnessMode.ONESHOT) == PermissionPolicy.DENY and policy.decide(PermissionPolicy.GROUP_SHELL, SessionModel.HarnessMode.ONESHOT) == PermissionPolicy.DENY, "qa: el evaluador no edita")
	_check(policy.decide(PermissionPolicy.GROUP_RUN, SessionModel.HarnessMode.ONESHOT) == PermissionPolicy.ALLOW, "qa: el evaluador corre el juego")
	_check(run.controller.system_prompt().contains("QA evaluator"), "qa: reglas del evaluador en el prompt de sistema")
	_check(sent.size() == 2 and sent[1].begins_with(OneShotRun.QA_MARKER) and sent[1].contains("Puntaje (builder says: pass)") and sent[1].contains("`playability`") and not sent[1].contains("Goal (One-shot mode)"), "qa: prompt del evaluador, sin el contexto del que construye")
	_check(_user_messages(run.model).size() == 1, "qa: sesión nueva para el evaluador")
	await _wait(func() -> bool: return run.phase == OneShotRun.RunPhase.FINISHED and not run.last_report.is_empty(), 20.0)
	_check(run.finish_reason == "QA round 2: the game passes.", "qa: termina con la segunda vuelta (%s)" % run.finish_reason)
	_check(sent.size() == 4, "qa: inicial, QA 1, corrección y QA 2 (%d)" % sent.size())
	if sent.size() == 4:
		_check(sent[2].contains("QA round 1: an independent evaluator") and sent[2].contains("Puntaje: el puntaje no sube") and sent[2].contains("[bug] El puntaje no sube (res://score.gd:12)") and sent[2].contains("5 of 7. el puntaje no sube"), "qa: los hallazgos vuelven al que construye · " + sent[2].right(600))
		_check(sent[2].begins_with("We're resuming a One-shot"), "qa: sin session/load, la corrección va con el resumen")
		_check(sent[3].contains("round 2 of at most 2") and sent[3].contains("qa-1.md"), "qa: la segunda vuelta mira el informe anterior")
	_check(run.qa_results.size() == 2 and not run.qa_results[0].passed and run.qa_results[0].failing_checks == ["Puntaje"] and run.qa_results[1].passed, "qa: resultados %s" % [run.qa_results])
	_check(run.qa_results.size() > 0 and Array(run.qa_results[0].failing_criteria).any(func(text: String) -> bool: return text.contains("6/7")), "qa: criterios por debajo del mínimo %s" % [run.qa_results])
	_check(run.files.read(run.files.qa_path(1)).contains("El puntaje no sube") and FileAccess.file_exists(run.files.qa_path(2)), "qa: qa-1.md y qa-2.md")
	var puntaje: Array = run.checks.filter(func(check: Dictionary) -> bool: return check.label == "Puntaje")
	_check(puntaje.size() == 1 and puntaje[0].status == "pass" and puntaje[0].get("verified", false), "qa: el check lo decide el evaluador %s" % [run.checks])
	_check(policy.restrictions.is_empty() and run.controller.mode_rules_override.is_empty(), "qa: el que construye vuelve con sus permisos")
	var qa_activity: Array = run.activity.filter(func(entry: Dictionary) -> bool: return entry.kind == "qa").map(func(entry: Dictionary) -> String: return entry.text)
	_check(qa_activity.has("QA round 1: doesn't pass · Puntaje, Playability 6/7, Functionality 5/7") and qa_activity.has("bug · El puntaje no sube (score.gd:12)") and qa_activity.any(func(text: String) -> bool: return text.begins_with("QA round 2: passes")), "qa: actividad %s" % [qa_activity])
	_check(int(run.used.playtests) == 4, "qa: los playtests del evaluador cuentan (%d)" % int(run.used.playtests))
	_check(run.last_report.get("qa", []).size() == 2 and int(run.last_report.get("events", {}).get("qa_turns", 0)) == 2, "qa: informe")
	run.controller.stop()
	run.queue_free()


## m16-04: un evaluador que aprueba sin haber jugado no cuenta como aprobación.
func _scenario_qa_without_playing() -> void:
	print("— evaluador sin jugar")
	var run := _make("oneshot_qa_noplay")
	run.qa_max_rounds = 2
	run.restart_session = func(_lost_id: String) -> bool:
		return await run.controller.start(_profile("oneshot_qa_noplay"))
	await run.start("Pong con puntaje", {"time": 0, "tokens": 0, "playtests": 0}, false)
	await _wait(func() -> bool: return run.phase in [OneShotRun.RunPhase.FINISHED, OneShotRun.RunPhase.PAUSED], 15.0)
	_check(run.finish_reason.contains("couldn't reach a verdict") and not run.finish_reason.contains("passes"), "sin jugar: no aprueba (%s)" % run.finish_reason)
	_check(run.activity.any(func(item: Dictionary) -> bool: return str(item.get("text", "")).contains("without playing")), "sin jugar: queda en la actividad")
	_check(run.files.read(run.files.qa_path(1)).contains("never played"), "sin jugar: el informe lo dice")
	_check(run.checks.all(func(check: Dictionary) -> bool: return not check.get("verified", false)), "sin jugar: sus checks no quedan verificados")
	run.controller.stop()
	run.queue_free()


func _user_messages(model: SessionModel) -> Array:
	return model.entries().filter(func(entry: ChatEntry) -> bool: return entry.kind == ChatEntry.EntryKind.USER).map(func(entry: ChatEntry) -> String: return entry.text)


func _agent_text(model: SessionModel) -> String:
	return "\n".join(model.entries().filter(func(entry: ChatEntry) -> bool: return entry.kind == ChatEntry.EntryKind.AGENT).map(func(entry: ChatEntry) -> String: return entry.text))


func _cp_labels(run: OneShotRun) -> Array:
	return run.git.checkpoints.map(func(cp: Dictionary) -> String: return "%s %s" % [cp.name, cp.label])


func _wait(condition: Callable, timeout_s: float) -> void:
	var deadline := Time.get_ticks_msec() + int(timeout_s * 1000)
	while not condition.call() and Time.get_ticks_msec() < deadline:
		await process_frame


func _check(condition: bool, label: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(label)
