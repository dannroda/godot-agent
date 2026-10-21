extends SceneTree
## Loop del One-shot (M6) contra el agente falso, sin editor: checkpoints en un repo temporal,
## pausa por cuota, límite con cpN-quota y reanudación sola o con confirmación, presupuestos y
## "Guiar al agente".
## Uso: godot --headless --path <repo> --script tests/oneshot_check.gd

const SessionController := preload("res://addons/godot_agent/session/session_controller.gd")
const SessionModel := preload("res://addons/godot_agent/session/session_model.gd")
const ChatEntry := preload("res://addons/godot_agent/session/chat_entry.gd")
const AgentLog := preload("res://addons/godot_agent/core/agent_log.gd")
const AgentProfile := preload("res://addons/godot_agent/core/agent_profile.gd")
const QuotaMonitor := preload("res://addons/godot_agent/core/quota_monitor.gd")
const OneShotRun := preload("res://addons/godot_agent/oneshot/oneshot_run.gd")

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
	await _scenario_budget()
	await _scenario_no_plan()
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


func _make(scenario: String) -> OneShotRun:
	var model := SessionModel.new()
	var controller := SessionController.new()
	controller.setup(model, AgentLog.new(), ProjectSettings.globalize_path("res://").trim_suffix("/"))
	var run := OneShotRun.new()
	run.setup(controller, _repo(scenario))
	run.restart_session = func(_lost_id: String) -> bool: return await controller.start(_profile(scenario))
	root.add_child(run)
	return run


func _scenario_quota() -> void:
	print("— cuota")
	var run := _make("oneshot_quota")
	var controller := run.controller
	var model := run.model
	run.resume_auto = true
	var started: bool = await run.start("Pong de 2 jugadores con puntaje", {"time": 10, "tokens": 0, "playtests": 10}, true)
	_check(started, "cuota: arranca")
	_check(model.harness_mode == SessionModel.HarnessMode.ONESHOT, "cuota: modo One-shot")
	_check(str(_user_messages(model)[0]).contains("Objetivo (modo One-shot): Pong") and str(_user_messages(model)[0]).contains("\"checks\""), "cuota: prompt inicial")

	# Turno 1: cp2 antes de la tarea 1; al 91 % la tarea 2 crea su checkpoint y se pausa.
	await _wait(func() -> bool: return run.phase == OneShotRun.Phase.PAUSED_QUOTA and not run.is_git_busy(), 10.0)
	_check(run.phase == OneShotRun.Phase.PAUSED_QUOTA, "cuota: pausado por cuota (%s)" % run.phase_label())
	_check(_cp_labels(run) == ["cp1 Estado inicial", "cp2 Paletas y pelota", "cp3 Puntaje y saque"], "cuota: checkpoints %s" % [_cp_labels(run)])
	_check(int(run.used.playtests) == 1, "cuota: un playtest contado")
	_check(run.last_capture != null and run.last_capture.get_width() == 16, "cuota: captura del playtest")
	_check(run.checks.size() == 2 and run.checks[0].status == "pass", "cuota: checks del turno")
	_check(not _agent_text(model).contains("Esto no debería llegar"), "cuota: el turno se cortó en el checkpoint")
	_check(run.resume_task == "Puntaje y saque", "cuota: retoma en la tarea 2")

	# A los 3 s se reinicia la ventana y retoma solo; el turno 2 choca con el límite. Desde ahí espera
	# confirmación (se cambia al entrar en "limitado": la ventana se reinicia en 3 s).
	run.changed.connect(func() -> void:
		if run.phase == OneShotRun.Phase.LIMITED:
			run.resume_auto = false)
	await _wait(func() -> bool: return run.phase == OneShotRun.Phase.LIMITED and not run.is_git_busy(), 10.0)
	_check(_user_messages(model).size() >= 2 and str(_user_messages(model)[1]).contains("Continuá con el plan desde la tarea «Puntaje y saque»; el estado está en el checkpoint cp3"), "cuota: prompt de reanudación (%s)" % str(_user_messages(model).back()).left(120))
	_check(run.phase == OneShotRun.Phase.LIMITED, "cuota: limitado (%s)" % run.phase_label())
	_check(_cp_labels(run).back() == "cp4-quota Puntaje y saque", "cuota: cpN-quota (%s)" % [_cp_labels(run)])
	_check(controller.quota.seconds_until_retry() > 0, "cuota: cuenta regresiva")
	var time_before := float(run.used.time)

	await _wait(func() -> bool: return run.phase == OneShotRun.Phase.WAITING_CONFIRM, 10.0)
	_check(run.phase == OneShotRun.Phase.WAITING_CONFIRM, "cuota: espera confirmación (%s)" % run.phase_label())
	_check(float(run.used.time) == time_before, "cuota: el tiempo en limitado no cuenta")
	run.resume()
	await _wait(func() -> bool: return run.phase == OneShotRun.Phase.FINISHED and not run.is_git_busy(), 10.0)
	_check(str(_user_messages(model).back()).contains("desde la tarea «Puntaje y saque»; el estado está en el checkpoint cp4-quota"), "cuota: retoma desde cp4-quota")
	_check(run.phase == OneShotRun.Phase.FINISHED and run.finish_reason == "El agente terminó el plan.", "cuota: terminó (%s)" % run.finish_reason)
	_check(_cp_labels(run).back() == "cp5 Playtest final", "cuota: checkpoint de la última tarea (%s)" % [_cp_labels(run)])
	_check(controller.quota.state == QuotaMonitor.State.NORMAL, "cuota: normal después del reinicio")
	_check(run.checks.size() == 2 and run.checks[1].status == "pass", "cuota: checks actualizados")
	var log := await run.git.run(["log", "--format=%s", "-6"])
	_check(log.output.begins_with("cp5: Playtest final\ncp4-quota: Puntaje y saque\ncp3: Puntaje y saque\ncp2: Paletas y pelota\ncp1: Estado inicial"), "cuota: commits en la rama del agente:\n" + log.output)
	controller.stop()
	run.queue_free()


func _scenario_budget() -> void:
	print("— presupuestos")
	var run := _make("oneshot_budget")
	var controller := run.controller
	var model := run.model
	var notices: Array[String] = []
	model.entry_added.connect(func(entry: ChatEntry) -> void:
		if entry.kind == ChatEntry.Kind.NOTICE:
			notices.append(entry.text))
	await run.start("Pong", {"time": 0, "tokens": 0, "playtests": 5}, false)
	_check(not run.checkpoints_enabled, "presupuestos: sin checkpoints")
	await _wait(func() -> bool: return int(run.used.playtests) >= 1, 5.0)
	run.guide("Usá paletas blancas y fondo negro.")
	await _wait(func() -> bool: return int(run.used.playtests) >= 4, 5.0)
	_check(notices.any(func(text: String) -> bool: return text.contains("Playtests: 80 %")), "presupuestos: aviso al 80 %% (%s)" % [notices])
	await _wait(func() -> bool: return run.phase == OneShotRun.Phase.FINISHED, 15.0)
	var messages := _user_messages(model)
	_check(messages.size() == 3, "presupuestos: inicial, guía y cierre (%d)" % messages.size())
	if messages.size() == 3:
		_check(messages[1] == "Usá paletas blancas y fondo negro.", "presupuestos: la guía va al terminar el turno")
		_check(str(messages[2]).begins_with("Se agotó el presupuesto de playtests.") and str(messages[2]).contains("reporte final"), "presupuestos: prompt de cierre")
	_check(not _agent_text(model).contains("No debería llegar"), "presupuestos: al 100 % corta el turno")
	_check(run.finish_reason == "Se agotó el presupuesto de playtests.", "presupuestos: motivo (%s)" % run.finish_reason)
	_check(run.checks.size() == 2 and run.checks[1].status == "fail", "presupuestos: checks del reporte")
	controller.stop()
	run.queue_free()


## Un agente que no manda plan por ACP: checkpoint por playtest y su fin de turno es el final.
func _scenario_no_plan() -> void:
	print("— sin plan")
	var run := _make("oneshot_noplan")
	await run.start("Pong", {"time": 0, "tokens": 0, "playtests": 0}, true)
	await _wait(func() -> bool: return run.phase == OneShotRun.Phase.FINISHED and not run.is_git_busy(), 10.0)
	_check(run.finish_reason == "El agente terminó: todos los checks pasan.", "sin plan: motivo (%s)" % run.finish_reason)
	var messages := _user_messages(run.model)
	_check(messages.size() == 2 and str(messages[1]).contains("«Puntaje» (pending)") and not str(messages[1]).contains("plan"), "sin plan: sigue por el check pendiente, sin hablar de plan %s" % [messages])
	_check(_cp_labels(run) == ["cp1 Estado inicial", "cp2 Playtest #1", "cp3 Playtest #2"], "sin plan: checkpoint por playtest %s" % [_cp_labels(run)])
	_check(run.checks.size() == 2 and run.checks.all(func(check: Dictionary) -> bool: return check.status == "pass"), "sin plan: checks")
	run.controller.stop()
	run.queue_free()


func _user_messages(model: SessionModel) -> Array:
	return model.entries().filter(func(entry: ChatEntry) -> bool: return entry.kind == ChatEntry.Kind.USER).map(func(entry: ChatEntry) -> String: return entry.text)


func _agent_text(model: SessionModel) -> String:
	return "\n".join(model.entries().filter(func(entry: ChatEntry) -> bool: return entry.kind == ChatEntry.Kind.AGENT).map(func(entry: ChatEntry) -> String: return entry.text))


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
