@tool
extends RefCounted
## Verificación de M6 dentro del editor: la pantalla One-shot maneja un One-shot con el agente falso
## (tests/scripts/oneshot_ui.json: el guion de oneshot_check con ventanas de cuota de 8 s) sobre un
## repo git temporal en user://, nunca sobre este repo.
## Recorre el formulario, la pausa por cuota (banner, cuenta regresiva, cpN), "Limitado" con
## cpN-quota, Retomar con confirmación, el resumen de cambios, "Volver acá" y "Aceptar todo".
## Al final, un run a medias cargado de disco (D37): actividad, plan y aviso, y Detener lo cierra.
## Con `shot_path` guarda capturas <shot>_paused.png, <shot>_limited.png, <shot>_recovered.png y
## <shot>.png.

const AgentProfile := preload("res://addons/godot_agent/core/agent_profile.gd")
const OneShotRun := preload("res://addons/godot_agent/oneshot/oneshot_run.gd")
const GitCheckpoints := preload("res://addons/godot_agent/oneshot/git_checkpoints.gd")
const RunReport := preload("res://addons/godot_agent/oneshot/run_report.gd")
const MAIN_SCREEN_SCRIPT := "res://addons/godot_agent/ui/main_screen/agent_main_screen.gd"
const DOCK_SCRIPT := "res://addons/godot_agent/ui/dock/agent_dock.gd"
const MAIN_PLUGIN_SCRIPT := "res://addons/godot_agent/plugin.gd"
const MAIN_SCREEN_NAME := "One-shot"
const REPO_DIR := "user://oneshot_ui_check"
const STEP_TIMEOUT_S := 15.0
const CLAUDE_GOAL := "Pong de 2 jugadores con puntaje: paletas con W/S y flechas arriba/abajo, pelota que rebota, puntaje arriba y saque desde el centro después de cada punto."
## Presupuestos del One-shot con Claude real: {time (min), tokens, playtests}.
const CLAUDE_BUDGETS: Dictionary = {"time": 25, "tokens": 3000000, "playtests": 5}

var failures: PackedStringArray = []
var _tree: SceneTree
var _screen: Control
var _run: OneShotRun
var _restored: PackedStringArray = []


func run_oneshot(tree: SceneTree, shot_path: String = "") -> PackedStringArray:
	_tree = tree
	for node: Node in tree.root.find_children("*", "VBoxContainer", true, false):
		var script := node.get_script() as Script
		if script and script.resource_path == MAIN_SCREEN_SCRIPT:
			_screen = node
	if _screen == null:
		failures.append("no se encontró la pantalla One-shot")
		return failures
	if not FileAccess.file_exists("res://tests/fake_agent.gd"):
		failures.append("hace falta el repo del addon (tests/fake_agent.gd)")
		return failures
	_run = _screen.get(&"_run")
	var controller: Object = _run.controller
	controller.call(&"stop")
	var repo := _make_repo()
	_run.git.root = repo
	_run.files.project_root = repo  # el spec y el progreso (D41) van al repo de prueba, no al del addon
	_run.after_restore = func(paths: PackedStringArray) -> void: _restored = paths
	_run.restart_session = func(_lost_id: String) -> bool: return await controller.call(&"start", _profile())
	_run.resume_auto = true
	var qa_rounds: int = _run.qa_max_rounds
	_run.qa_max_rounds = 0  # los guiones de antes del evaluador (D55) terminan con lo que reporta el agente
	var store_dir := ProjectSettings.globalize_path(REPO_DIR + "_store")
	OS.execute("rm", ["-rf", store_dir])
	_run.store.dir = store_dir  # no el del proyecto: un run a medias aparecería en otra prueba
	EditorInterface.set_main_screen_editor(MAIN_SCREEN_NAME)
	await _frames(10)

	# Formulario.
	var form: Control = _screen.get(&"_form")
	var start: Button = _screen.get(&"_start_button")
	_check(form.is_visible_in_tree(), "se ve el formulario")
	_check(start.disabled, "sin objetivo no se puede iniciar")
	var goal: TextEdit = _screen.get(&"_goal_edit")
	var form_panel: Control = form.get_child(0)
	_check(form_panel.size.x >= minf(form.size.x * 0.6, 1300.0) - 2.0 and goal.size.y >= form.size.y * 0.35, "el formulario crece con la pantalla (%s en %s, objetivo %d)" % [form_panel.size, form.size, goal.size.y])
	goal.text = "Pong de 2 jugadores con puntaje"
	goal.text_changed.emit()
	_shot(shot_path, "_form")
	(_screen.get(&"_checkpoints_check") as CheckBox).button_pressed = true
	(_screen.get(&"_budget_spins")[OneShotRun.BUDGET_PLAYTESTS] as SpinBox).value = 10
	_check(not start.disabled, "con objetivo se puede iniciar")
	start.pressed.emit()

	# Pausa por cuota: el agente falso pasa al 91 % y empieza la tarea 2.
	await _wait(func() -> bool: return _run.phase == OneShotRun.RunPhase.PAUSED_QUOTA and not _run.is_git_busy())
	_check(_run.phase == OneShotRun.RunPhase.PAUSED_QUOTA, "pausado por cuota (%s)" % _run.phase_label())
	await _frames(3)
	_check((_screen.get(&"_run_view") as Control).is_visible_in_tree(), "se ve la vista del One-shot")
	_check(_text(&"_phase_label").begins_with("Paused for quota · task 2 of 3"), "fase: " + _text(&"_phase_label"))
	_check(_text(&"_goal_label") == "Pong de 2 jugadores con puntaje", "objetivo en la barra")
	_check((_screen.get(&"_banner") as Control).visible and _text(&"_banner_label").begins_with("Quota at 91 %:"), "banner de cuota: " + _text(&"_banner_label"))
	_check(_text(&"_countdown_label").contains("Paused for quota before “Puntaje y saque”"), "cuenta regresiva: " + _text(&"_countdown_label"))
	_check(_text(&"_rule_label").contains("current task or turn"), "regla de cuota: " + _text(&"_rule_label"))
	_check(((_screen.get(&"_quota_row") as Dictionary).label as Label).text == "Quota  91 %", "barra de cuota: " + ((_screen.get(&"_quota_row") as Dictionary).label as Label).text)
	_check(((_screen.get(&"_budget_rows") as Dictionary)[OneShotRun.BUDGET_PLAYTESTS].label as Label).text == "Playtests  1 / 10", "barra de playtests")
	_check((_screen.get(&"_pause_button") as Button).text == "Resume", "el botón dice Retomar")
	_check(_rows(&"_plan_list") == 3, "tres tareas en el plan (%d)" % _rows(&"_plan_list"))
	_check(_rows(&"_checks_list") == 2, "dos verificaciones (%d)" % _rows(&"_checks_list"))
	_check(_rows(&"_checkpoints_list") == 3, "tres checkpoints (%d)" % _rows(&"_checkpoints_list"))
	_check((_screen.get(&"_capture_rect") as TextureRect).texture != null, "captura del playtest")
	_check((_screen.get(&"_activity_text") as RichTextLabel).get_parsed_text().contains("Playtest #1"), "actividad con el playtest")
	# Lo que "escribe el agente" en la tarea 2 entra en el cpN-quota.
	_write(repo.path_join("pong.gd"), "extends Node2D\n\nvar score := 0\n")
	_shot(shot_path, "_paused")

	_run.changed.connect(func() -> void:
		if _run.phase == OneShotRun.RunPhase.LIMITED:
			_run.resume_auto = false)
	await _wait(func() -> bool: return _run.phase == OneShotRun.RunPhase.LIMITED and not _run.is_git_busy())
	_check(_run.phase == OneShotRun.RunPhase.LIMITED, "limitado (%s)" % _run.phase_label())
	await _frames(3)
	_check(_text(&"_countdown_label").begins_with("⏳"), "cuenta regresiva en Limitado: " + _text(&"_countdown_label"))
	_check(_text(&"_banner_label").begins_with("Plan limit reached"), "banner de límite")
	_check(_rows(&"_checkpoints_list") == 4, "cp4-quota en la lista (%d)" % _rows(&"_checkpoints_list"))
	_shot(shot_path, "_limited")
	var plan_times: Dictionary = _screen.get(&"_plan_times")
	var shown_times: Array = plan_times.values().map(func(label: Label) -> String: return label.text).filter(func(text: String) -> bool: return not text.is_empty())
	_check(shown_times.size() >= 2 and shown_times.all(func(text: String) -> bool: return text.ends_with(" s")), "duración de las tareas en el plan %s" % [shown_times])
	var account: MenuButton = _screen.get(&"_account_button")
	_check(account.is_visible_in_tree(), "«Cambiar de cuenta» en Limitado")
	account.about_to_popup.emit()
	var popup := account.get_popup()
	_check(popup.item_count >= 1 and popup.get_item_text(popup.item_count - 1).begins_with("I already signed in with another account"), "menú de cambio de cuenta")

	await _wait(func() -> bool: return _run.phase == OneShotRun.RunPhase.WAITING_CONFIRM)
	await _frames(2)
	_check(_text(&"_countdown_label").begins_with("The quota is free again"), "espera confirmación: " + _text(&"_countdown_label"))
	# «Reintentar» del dock retoma el run en su sesión (m6-15), no abre una en blanco.
	var dock := _find_by_script(DOCK_SCRIPT)
	var session_id: String = _run.model.session_id
	_check(dock != null and (dock.get(&"retry_interceptor") as Callable).call(), "«Reintentar» del dock lo toma el One-shot")
	_check(_run.phase == OneShotRun.RunPhase.RUNNING and _run.model.session_id == session_id, "retoma en la misma sesión")
	await _wait(func() -> bool: return _run.phase == OneShotRun.RunPhase.FINISHED and not _run.is_git_busy())
	_check(_run.phase == OneShotRun.RunPhase.FINISHED, "terminó (%s)" % _run.phase_label())
	_screen.set(&"_summary_dirty", true)
	await _wait(func() -> bool: return not (_screen.get(&"_summary") as Dictionary).get("files", []).is_empty())
	await _frames(2)
	_check(_text(&"_summary_label").begins_with("1 file changed · 0 scenes · 1 script"), "resumen: " + _text(&"_summary_label"))
	_check((_screen.get(&"_new_button") as Button).visible and not (_screen.get(&"_pause_button") as Button).visible, "Nuevo One-shot en lugar de Pausar")
	_check(_text(&"_banner_label") == "The agent finished the plan.", "banner de fin: " + _text(&"_banner_label"))

	# Informe (D39).
	await _wait(func() -> bool: return not _run.last_report.is_empty())
	await _frames(2)
	var report_button: Button = _screen.get(&"_report_button")
	_check(report_button.visible, "botón Informe al terminar")
	report_button.pressed.emit()
	await _frames(2)
	var report_text := (_screen.get(&"_report_text") as RichTextLabel).get_parsed_text()
	_check((_screen.get(&"_report_dialog") as Window).visible and report_text.contains("One-shot report") and report_text.contains("godot.run_scene") and report_text.contains("pong.gd"), "informe: " + report_text.left(200))
	_shot(shot_path, "_report")
	(_screen.get(&"_report_dialog") as Window).hide()

	# Revisar cambios: lista y diff contra el estado inicial.
	var diffs: Array = []
	_screen.connect(&"diff_requested", func(title: String, _a: String, old_text: String, _b: String, new_text: String) -> void: diffs.append([title, old_text, new_text]), CONNECT_ONE_SHOT)
	(_screen.get(&"_review_button") as Button).pressed.emit()
	var list: ItemList = _screen.get(&"_changes_list")
	_check(list.item_count == 1 and list.get_item_text(0).ends_with("pong.gd"), "lista de cambios")
	if list.item_count > 0:
		list.item_activated.emit(0)
		await _wait(func() -> bool: return not diffs.is_empty())
		_check(not diffs.is_empty() and diffs[0][1] == "" and str(diffs[0][2]).contains("var score"), "diff de pong.gd")
	_shot(shot_path, "_diff")
	for window: Node in EditorInterface.get_base_control().find_children("*", "AcceptDialog", true, false):
		(window as Window).hide()
	await _frames(2)
	_shot(shot_path, "")

	# Volver acá a cp2: pong.gd desaparece.
	if _run.git.checkpoints.size() < 2:
		failures.append("no hay cp2 (%d checkpoints)" % _run.git.checkpoints.size())
		return failures
	var cp2: Dictionary = _run.git.checkpoints[1]
	_screen.call(&"_on_restore_pressed", cp2)
	(_screen.get(&"_restore_dialog") as ConfirmationDialog).confirmed.emit()
	(_screen.get(&"_restore_dialog") as ConfirmationDialog).hide()
	await _wait(func() -> bool: return _run.git.checkpoints.size() == 2 and not _run.is_git_busy())
	_check(not FileAccess.file_exists(repo.path_join("pong.gd")), "Volver acá borró pong.gd")
	_check("pong.gd" in _restored, "recarga del editor con %s" % _restored)
	await _frames(2)
	_check(_rows(&"_checkpoints_list") == 2, "quedan dos checkpoints (%d)" % _rows(&"_checkpoints_list"))

	# Aceptar todo: la rama del agente queda, sin merge.
	(_screen.get(&"_accept_dialog") as ConfirmationDialog).confirmed.emit()
	(_screen.get(&"_accept_dialog") as ConfirmationDialog).hide()
	await _wait(func() -> bool: return _run.finish_reason.begins_with("Changes accepted"))
	_check(_run.finish_reason.begins_with("Changes accepted in agent/"), "aceptado: " + _run.finish_reason)
	var branches: Dictionary = await _run.git.run(["branch", "--format=%(refname:short)"])
	_check(str(branches.output).contains("main") and str(branches.output).contains("agent/"), "las dos ramas siguen: " + str(branches.output))

	(_screen.get(&"_new_button") as Button).pressed.emit()
	await _frames(2)
	_check(form.is_visible_in_tree() and goal.text == "Pong de 2 jugadores con puntaje", "Nuevo One-shot vuelve al formulario con el objetivo")

	# El mismo run, como si el editor se hubiera caído a mitad: vuelve en pausa con su actividad.
	var saved := _run.store.load_run(_run.run_id)
	saved["active"] = true
	_run.store.save(saved)
	# Como al reabrir el editor: sin sesión, chat vacío, y el plugin restaura el run con su aviso.
	_run.controller.call(&"stop")
	_run.model.reset()
	var plugin := _find_by_script(MAIN_PLUGIN_SCRIPT)
	plugin.call(&"_restore_oneshot")
	_check(_run.phase == OneShotRun.RunPhase.PAUSED, "carga el run a medias")
	await _frames(3)
	var notices: Array = _run.model.entries().filter(func(entry: Object) -> bool: return str(entry.get(&"text")).begins_with("There is an unfinished One-shot"))
	_check(notices.size() == 1 and (notices[0].get(&"actions") as Array).map(func(action: Dictionary) -> String: return str(action.label)) == ["Resume One-shot", "Open One-shot screen"], "run a medias: aviso con «Resume One-shot» y «Open One-shot screen»")
	var restored_dock := _find_by_script(DOCK_SCRIPT)
	var dock_start: Button = restored_dock.get(&"_start_button")
	# Dentro del dock: según el layout del editor, la pestaña del dock puede no ser la elegida en su slot.
	_check(_visible_within(dock_start, restored_dock) and dock_start.text == "Resume One-shot", "run a medias: el dock ofrece «Resume One-shot» (%s, %s)" % [_visible_within(dock_start, restored_dock), dock_start.text])
	_check((_screen.get(&"_run_view") as Control).is_visible_in_tree(), "run a medias: se ve el run")
	_check(_text(&"_phase_label").begins_with("Paused"), "run a medias: fase " + _text(&"_phase_label"))
	_check(_text(&"_banner_label").begins_with("The One-shot was left unfinished"), "run a medias: banner " + _text(&"_banner_label"))
	_check((_screen.get(&"_pause_button") as Button).text == "Resume", "run a medias: Retomar")
	_check(_rows(&"_plan_list") == 3, "run a medias: el plan guardado (%d)" % _rows(&"_plan_list"))
	var activity := (_screen.get(&"_activity_text") as RichTextLabel).get_parsed_text()
	_check(activity.contains("Playtest #1") and activity.contains("“Resume” reopens the agent's session"), "run a medias: la actividad se rearmó")
	_shot(shot_path, "_recovered")
	(_screen.get(&"_stop_button") as Button).pressed.emit()
	await _frames(2)
	_check(_run.phase == OneShotRun.RunPhase.FINISHED and _run.store.load_interrupted().is_empty(), "run a medias: Detener lo cierra")

	# Spec (D41): el agente escribe el spec y espera; «Revisar spec» lo muestra y «Aprobar spec» sigue.
	var spec_repo := _make_repo()
	_run.git.root = spec_repo
	_run.files.project_root = spec_repo
	_run.restart_session = func(_lost_id: String) -> bool: return await controller.call(&"start", _profile("oneshot_spec"))
	controller.call(&"stop")
	(_screen.get(&"_new_button") as Button).pressed.emit()
	await _frames(2)
	(_screen.get(&"_spec_check") as CheckBox).button_pressed = true
	start.pressed.emit()
	await _wait(func() -> bool: return _run.phase == OneShotRun.RunPhase.RUNNING)
	_run.files.write(_run.files.spec_path(), "# Pong\nDos paletas.\n")  # lo que haría el agente
	await _wait(func() -> bool: return _run.phase == OneShotRun.RunPhase.SPEC_REVIEW)
	await _frames(3)
	var spec_button: Button = _screen.get(&"_spec_button")
	_check(spec_button.visible and spec_button.text == "Review spec", "spec: botón Revisar spec")
	_check(_text(&"_banner_label").begins_with("The agent wrote the spec"), "spec: banner " + _text(&"_banner_label"))
	var spec_view: RichTextLabel = _screen.get(&"_spec_view")
	_check(spec_view.is_visible_in_tree() and spec_view.get_parsed_text().contains("Dos paletas") and (_screen.get(&"_spec_bar") as Control).is_visible_in_tree(), "spec: la columna muestra el spec con Aprobar")
	_check(not (_screen.get(&"_plan_list").get_parent() as Control).is_visible_in_tree(), "spec: el plan vacío no se muestra")
	_shot(shot_path, "_spec_column")
	# Presupuestos con el run en curso (m6-12): el diálogo trae los actuales e «Ilimitado» los saca.
	var budgets_button: Button = _screen.get(&"_budgets_button")
	_check(budgets_button.visible, "presupuestos: botón con el run en curso")
	budgets_button.pressed.emit()
	await _frames(2)
	var budgets_dialog: ConfirmationDialog = _screen.get(&"_budgets_dialog")
	var budget_spins: Dictionary = _screen.get(&"_budgets_edit")
	_check(budgets_dialog.visible and int((budget_spins[OneShotRun.BUDGET_PLAYTESTS] as SpinBox).value) == int(_run.budgets.playtests), "presupuestos: el diálogo trae los actuales")
	budgets_dialog.custom_action.emit(&"unlimited")
	await _frames(3)
	_check(not budgets_dialog.visible and int(_run.budgets.time) == 0 and int(_run.budgets.tokens) == 0 and int(_run.budgets.playtests) == 0, "presupuestos: Ilimitado")
	_check(((_screen.get(&"_budget_rows") as Dictionary)[OneShotRun.BUDGET_PLAYTESTS].label as Label).text.ends_with("/ ∞"), "presupuestos: la barra muestra ∞")
	spec_button.pressed.emit()
	await _frames(2)
	var files_dialog: ConfirmationDialog = _screen.get(&"_files_dialog")
	var spec_edit: TextEdit = _screen.get(&"_spec_edit")
	var tabs: TabContainer = _screen.get(&"_files_tabs")
	_check(files_dialog.visible and spec_edit.text.contains("Dos paletas") and files_dialog.ok_button_text == "Approve spec", "spec: el diálogo muestra el spec")
	_check(tabs.get_tab_count() == 2 and tabs.get_tab_title(1) == "Progress", "spec: pestañas Spec y Progreso (%d)" % tabs.get_tab_count())
	_check(_text(&"_files_path_label").ends_with("spec.md"), "spec: ruta del archivo " + _text(&"_files_path_label"))
	spec_edit.text = "# Pong\nDos paletas y power-ups.\n"
	_shot(shot_path, "_spec")
	files_dialog.get_ok_button().pressed.emit()
	await _wait(func() -> bool: return _run.phase == OneShotRun.RunPhase.FINISHED and not _run.is_git_busy())
	_check(_run.phase == OneShotRun.RunPhase.FINISHED and _run.files.read(_run.files.spec_path()).contains("power-ups"), "spec: aprobado con cambios y terminado (%s)" % _run.phase_label())
	_check(spec_button.text == "Spec and progress" and spec_button.visible, "spec: queda el botón Spec y progreso")
	_check(not spec_view.is_visible_in_tree() and (_screen.get(&"_plan_list").get_parent() as Control).is_visible_in_tree(), "spec: después de aprobar vuelve el plan")
	# Un link del chat a progress.md abre el visor en esa pestaña (D41).
	_run.files.write(_run.files.progress_path(), "Hecho: paletas.\n")
	_screen.call(&"show_run_file", _run.files.progress_path())
	await _frames(2)
	_check(files_dialog.visible and tabs.current_tab == 1 and (tabs.get_child(1) as TextEdit).text.contains("paletas"), "spec: el link a progress.md abre su pestaña")
	files_dialog.hide()

	# Evaluador (D55): la fase «Evaluando» con su vuelta, Pausar disponible, y el final con el veredicto.
	var qa_repo := _make_repo()
	_run.git.root = qa_repo
	_run.files.project_root = qa_repo
	_run.qa_max_rounds = 2
	var starts: Array[int] = [0]
	_run.restart_session = func(_lost_id: String) -> bool:
		starts[0] += 1
		return await controller.call(&"start", _profile("oneshot_qa" if starts[0] == 1 else "oneshot_qa_fix"))
	controller.call(&"stop")
	(_screen.get(&"_new_button") as Button).pressed.emit()
	await _frames(2)
	(_screen.get(&"_spec_check") as CheckBox).button_pressed = false
	start.pressed.emit()
	await _wait(func() -> bool: return _run.phase == OneShotRun.RunPhase.EVALUATING)
	await _frames(3)
	_check(_text(&"_phase_label").begins_with("Evaluating · QA round 1"), "qa: fase " + _text(&"_phase_label"))
	var pause: Button = _screen.get(&"_pause_button")
	_check(pause.text == "Pause" and not pause.disabled, "qa: se puede pausar mientras evalúa")
	_shot(shot_path, "_qa")
	await _wait(func() -> bool: return _run.phase == OneShotRun.RunPhase.FINISHED and not _run.last_report.is_empty())
	await _frames(3)
	_check(_text(&"_banner_label") == "QA round 2: the game passes.", "qa: banner de fin " + _text(&"_banner_label"))
	var qa_activity := (_screen.get(&"_activity_text") as RichTextLabel).get_parsed_text()
	_check(qa_activity.contains("QA round 1: doesn't pass · Puntaje") and qa_activity.contains("El puntaje no sube (score.gd:12)"), "qa: la actividad muestra los hallazgos de la vuelta")
	_check(RunReport.to_markdown(_run.last_report).contains("| 1 | doesn't pass |"), "qa: el informe tiene las vueltas")
	_run.qa_max_rounds = qa_rounds
	controller.call(&"stop")
	return failures


## M6 con Claude Code real (gasta tokens) en el sandbox de tests/make_sandbox.sh: el One-shot de
## Pong tiene que terminar con al menos un playtest con captura y checkpoints, y "Volver acá" tiene
## que dejar el proyecto exactamente como en el checkpoint. Los permisos que pregunta el modo
## One-shot (shell) se conceden, salvo comandos git.
func run_claude_oneshot(tree: SceneTree, shot_path: String = "") -> PackedStringArray:
	_tree = tree
	for node: Node in tree.root.find_children("*", "VBoxContainer", true, false):
		var script := node.get_script() as Script
		if script and script.resource_path == MAIN_SCREEN_SCRIPT:
			_screen = node
	if _screen == null or not FileAccess.file_exists("res://.sandbox_one_shot"):
		failures.append("hace falta la pantalla One-shot dentro del sandbox de tests/make_sandbox.sh")
		return failures
	_run = _screen.get(&"_run")
	var model: Object = _run.model
	model.connect(&"permission_requested", func(request: Object) -> void:
		var title := str(request.get(&"title")) + " " + str(request.get(&"description"))
		var deny := title.contains("git ")
		print("[claude-oneshot] permiso %s: %s" % ["denegado" if deny else "concedido", title.left(160)])
		var option: String = request.call(&"option_id_for", PackedStringArray(["reject_once"] if deny else ["allow_once"]))
		request.call(&"select", option))
	_run.restart_session = func(_lost_id: String) -> bool: return await _run.controller.call(&"start", AgentProfile.from_dict(AgentProfile.CLAUDE_CODE))
	_run.activity_added.connect(func(entry: Dictionary) -> void: print("[claude-oneshot] %s %s %s" % [entry.time, entry.kind, str(entry.text).left(200)]))
	EditorInterface.set_main_screen_editor(MAIN_SCREEN_NAME)
	await _frames(10)
	var goal: TextEdit = _screen.get(&"_goal_edit")
	goal.text = CLAUDE_GOAL
	goal.text_changed.emit()
	(_screen.get(&"_checkpoints_check") as CheckBox).button_pressed = true
	for key: String in CLAUDE_BUDGETS:
		(_screen.get(&"_budget_spins")[key] as SpinBox).value = CLAUDE_BUDGETS[key]
	(_screen.get(&"_start_button") as Button).pressed.emit()
	var wip: ConfirmationDialog = _screen.get(&"_wip_dialog")
	await _wait(func() -> bool: return _run.is_active() or wip.visible)
	if wip.visible:
		print("[claude-oneshot] cambios sin commitear al abrir el sandbox: se confirman como WIP")
		wip.hide()
		wip.confirmed.emit()
	var shots := 0
	var deadline := Time.get_ticks_msec() + (int(CLAUDE_BUDGETS.time) + 10) * 60000
	while _run.phase != OneShotRun.RunPhase.FINISHED and Time.get_ticks_msec() < deadline:
		if _run.last_capture != null and shots == 0:
			shots += 1
			await _frames(5)
			_shot(shot_path, "_playtest")
		await _tree.create_timer(1.0).timeout
	print("[claude-oneshot] fin: %s · playtests %d · tokens %d · %.1f min · checkpoints %s" % [_run.finish_reason, _run.used.playtests, _run.used.tokens, float(_run.used.time) / 60.0, _run.git.checkpoints.map(func(cp: Dictionary) -> String: return cp.name + " " + cp.label)])
	for check: Dictionary in _run.checks:
		print("[claude-oneshot] check %s: %s" % [check.status, check.label])
	_check(_run.phase == OneShotRun.RunPhase.FINISHED, "el One-shot no terminó a tiempo (%s)" % _run.phase_label())
	_check(int(_run.used.playtests) >= 1, "sin playtests")
	_check(_run.last_capture != null, "sin captura de playtest")
	_check(_run.git.checkpoints.size() >= 3, "pocos checkpoints (%d)" % _run.git.checkpoints.size())
	var scenes := _find_files("res://", "tscn")
	_check(not scenes.is_empty(), "el agente no creó escenas")
	_screen.set(&"_summary_dirty", true)
	await _wait(func() -> bool: return not (_screen.get(&"_summary") as Dictionary).is_empty())
	await _frames(5)
	_shot(shot_path, "")

	# Volver acá al checkpoint anterior a la última tarea: el proyecto queda idéntico a ese commit.
	if _run.git.checkpoints.size() >= 3:
		var cp: Dictionary = _run.git.checkpoints[_run.git.checkpoints.size() - 2]
		_screen.call(&"_on_restore_pressed", cp)
		var dialog: ConfirmationDialog = _screen.get(&"_restore_dialog")
		dialog.hide()
		dialog.confirmed.emit()
		await _wait(func() -> bool: return _run.git.checkpoints.back() == cp and not _run.is_git_busy())
		await _tree.create_timer(1.0).timeout
		var diff: Dictionary = await _run.git.run(PackedStringArray(["diff", "--name-only", cp.sha]) + GitCheckpoints.PATHSPEC)
		var untracked: Dictionary = await _run.git.run(PackedStringArray(["ls-files", "--others", "--exclude-standard"]) + GitCheckpoints.PATHSPEC)
		print("[claude-oneshot] Volver acá a %s (%s): diff='%s' sin seguimiento='%s'" % [cp.name, cp.label, diff.output, untracked.output])
		_check(diff.code == 0 and str(diff.output).is_empty() and str(untracked.output).is_empty(), "Volver acá no dejó el proyecto como en %s" % cp.name)
		_shot(shot_path, "_restored")
	_run.controller.call(&"stop")
	return failures


## Si `node` se ve dentro de `root` (sin contar si se ve `root`).
static func _visible_within(node: Node, root: Node) -> bool:
	while node and node != root:
		if node is CanvasItem and not (node as CanvasItem).visible:
			return false
		node = node.get_parent()
	return node == root


func _find_by_script(path: String) -> Node:
	for node: Node in _tree.root.find_children("*", "", true, false):
		var script := node.get_script() as Script
		if script and script.resource_path == path:
			return node
	return null


func _find_files(dir: String, extension: String) -> PackedStringArray:
	var found: PackedStringArray = []
	for file: String in DirAccess.get_files_at(dir):
		if file.get_extension() == extension:
			found.append(dir.path_join(file))
	for sub: String in DirAccess.get_directories_at(dir):
		if not sub in [".godot", "addons"]:
			found.append_array(_find_files(dir.path_join(sub), extension))
	return found


func _profile(scenario: String = "oneshot_ui") -> AgentProfile:
	return AgentProfile.from_dict({
		"id": "fake", "display_name": "Agente falso", "command": OS.get_executable_path(),
		"args": ["--headless", "--no-header", "--path", ProjectSettings.globalize_path("res://"),
			"--script", "res://tests/fake_agent.gd", "--", "--scenario=res://tests/scripts/%s.json" % scenario],
	})


func _make_repo() -> String:
	var dir := ProjectSettings.globalize_path(REPO_DIR)
	OS.execute("rm", ["-rf", dir])
	DirAccess.make_dir_recursive_absolute(dir)
	_write(dir.path_join("project.godot"), "config_version=5\n")
	OS.execute("git", ["-c", "init.defaultBranch=main", "init", "-q", dir])
	OS.execute("git", ["-C", dir, "add", "-A"])
	OS.execute("git", ["-C", dir, "-c", "user.name=t", "-c", "user.email=t@t", "commit", "-q", "-m", "inicio"])
	return dir


func _write(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()


func _text(property: StringName) -> String:
	var node: Variant = _screen.get(property)
	return str(node.text) if node is Label else ""


## Filas visibles de una lista (las que se borran con queue_free siguen un frame).
func _rows(property: StringName) -> int:
	var count := 0
	for child: Node in (_screen.get(property) as Node).get_children():
		if not child.is_queued_for_deletion():
			count += 1
	return count


func _shot(shot_path: String, suffix: String) -> void:
	if shot_path.is_empty():
		return
	var path := shot_path.get_basename() + suffix + ".png"
	EditorInterface.get_base_control().get_viewport().get_texture().get_image().save_png(path)


func _frames(count: int) -> void:
	for i in count:
		await _tree.process_frame


func _wait(condition: Callable) -> void:
	var deadline := Time.get_ticks_msec() + int(STEP_TIMEOUT_S * 1000)
	while not condition.call() and Time.get_ticks_msec() < deadline:
		await _tree.process_frame


func _check(condition: bool, label: String) -> void:
	if not condition:
		failures.append(label)
