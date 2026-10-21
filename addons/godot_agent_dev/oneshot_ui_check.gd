@tool
extends RefCounted
## Verificación de M6 dentro del editor: la pantalla Agent maneja un One-shot con el agente falso
## (tests/scripts/oneshot_ui.json: el guion de oneshot_check con ventanas de cuota de 8 s) sobre un
## repo git temporal en user://, nunca sobre este repo.
## Recorre el formulario, la pausa por cuota (banner, cuenta regresiva, cpN), "Limitado" con
## cpN-quota, Retomar con confirmación, el resumen de cambios, "Volver acá" y "Aceptar todo".
## Con `shot_path` guarda capturas <shot>_paused.png, <shot>_limited.png y <shot>.png.

const AgentProfile := preload("res://addons/godot_agent/core/agent_profile.gd")
const OneShotRun := preload("res://addons/godot_agent/oneshot/oneshot_run.gd")
const GitCheckpoints := preload("res://addons/godot_agent/oneshot/git_checkpoints.gd")
const MAIN_SCREEN_SCRIPT := "res://addons/godot_agent/ui/main_screen/agent_main_screen.gd"
const MAIN_SCREEN_NAME := "Agent"
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
		failures.append("no se encontró la pantalla Agent")
		return failures
	if not FileAccess.file_exists("res://tests/fake_agent.gd"):
		failures.append("hace falta el repo del addon (tests/fake_agent.gd)")
		return failures
	_run = _screen.get(&"_run")
	var controller: Object = _run.controller
	controller.call(&"stop")
	var repo := _make_repo()
	_run.git.root = repo
	_run.after_restore = func(paths: PackedStringArray) -> void: _restored = paths
	_run.restart_session = func() -> bool: return await controller.call(&"start", _profile())
	_run.resume_auto = true
	EditorInterface.set_main_screen_editor(MAIN_SCREEN_NAME)
	await _frames(10)

	# Formulario.
	var form: Control = _screen.get(&"_form")
	var start: Button = _screen.get(&"_start_button")
	_check(form.is_visible_in_tree(), "se ve el formulario")
	_check(start.disabled, "sin objetivo no se puede iniciar")
	var goal: TextEdit = _screen.get(&"_goal_edit")
	goal.text = "Pong de 2 jugadores con puntaje"
	goal.text_changed.emit()
	(_screen.get(&"_checkpoints_check") as CheckBox).button_pressed = true
	(_screen.get(&"_budget_spins")[OneShotRun.BUDGET_PLAYTESTS] as SpinBox).value = 10
	_check(not start.disabled, "con objetivo se puede iniciar")
	start.pressed.emit()

	# Pausa por cuota: el agente falso pasa al 91 % y empieza la tarea 2.
	await _wait(func() -> bool: return _run.phase == OneShotRun.Phase.PAUSED_QUOTA and not _run.is_git_busy())
	_check(_run.phase == OneShotRun.Phase.PAUSED_QUOTA, "pausado por cuota (%s)" % _run.phase_label())
	await _frames(3)
	_check((_screen.get(&"_run_view") as Control).is_visible_in_tree(), "se ve la vista del One-shot")
	_check(_text(&"_phase_label").begins_with("Pausado por cuota · fase 2 de 3"), "fase: " + _text(&"_phase_label"))
	_check(_text(&"_goal_label") == "Pong de 2 jugadores con puntaje", "objetivo en la barra")
	_check((_screen.get(&"_banner") as Control).visible and _text(&"_banner_label").begins_with("Cuota al 91 %: se pausa"), "banner de cuota: " + _text(&"_banner_label"))
	_check(_text(&"_countdown_label").contains("Pausado por cuota antes de «Puntaje y saque»"), "cuenta regresiva: " + _text(&"_countdown_label"))
	_check(_text(&"_rule_label").contains("próximo checkpoint"), "regla de cuota: " + _text(&"_rule_label"))
	_check(((_screen.get(&"_quota_row") as Dictionary).label as Label).text == "Cuota  91 %", "barra de cuota: " + ((_screen.get(&"_quota_row") as Dictionary).label as Label).text)
	_check(((_screen.get(&"_budget_rows") as Dictionary)[OneShotRun.BUDGET_PLAYTESTS].label as Label).text == "Playtests  1 / 10", "barra de playtests")
	_check((_screen.get(&"_pause_button") as Button).text == "Retomar", "el botón dice Retomar")
	_check(_rows(&"_plan_list") == 3, "tres tareas en el plan (%d)" % _rows(&"_plan_list"))
	_check(_rows(&"_checks_list") == 2, "dos verificaciones (%d)" % _rows(&"_checks_list"))
	_check(_rows(&"_checkpoints_list") == 3, "tres checkpoints (%d)" % _rows(&"_checkpoints_list"))
	_check((_screen.get(&"_capture_rect") as TextureRect).texture != null, "captura del playtest")
	_check((_screen.get(&"_activity_text") as RichTextLabel).get_parsed_text().contains("Playtest #1"), "actividad con el playtest")
	# Lo que "escribe el agente" en la tarea 2 entra en el cpN-quota.
	_write(repo.path_join("pong.gd"), "extends Node2D\n\nvar score := 0\n")
	_shot(shot_path, "_paused")

	_run.changed.connect(func() -> void:
		if _run.phase == OneShotRun.Phase.LIMITED:
			_run.resume_auto = false)
	await _wait(func() -> bool: return _run.phase == OneShotRun.Phase.LIMITED and not _run.is_git_busy())
	_check(_run.phase == OneShotRun.Phase.LIMITED, "limitado (%s)" % _run.phase_label())
	await _frames(3)
	_check(_text(&"_countdown_label").begins_with("⏳"), "cuenta regresiva en Limitado: " + _text(&"_countdown_label"))
	_check(_text(&"_banner_label").begins_with("Límite del plan alcanzado"), "banner de límite")
	_check(_rows(&"_checkpoints_list") == 4, "cp4-quota en la lista (%d)" % _rows(&"_checkpoints_list"))
	_shot(shot_path, "_limited")

	await _wait(func() -> bool: return _run.phase == OneShotRun.Phase.WAITING_CONFIRM)
	await _frames(2)
	_check(_text(&"_countdown_label").begins_with("La cuota se liberó"), "espera confirmación: " + _text(&"_countdown_label"))
	(_screen.get(&"_pause_button") as Button).pressed.emit()
	await _wait(func() -> bool: return _run.phase == OneShotRun.Phase.FINISHED and not _run.is_git_busy())
	_check(_run.phase == OneShotRun.Phase.FINISHED, "terminó (%s)" % _run.phase_label())
	_screen.set(&"_summary_dirty", true)
	await _wait(func() -> bool: return not (_screen.get(&"_summary") as Dictionary).get("files", []).is_empty())
	await _frames(2)
	_check(_text(&"_summary_label").begins_with("1 archivo cambiado · 0 escenas · 1 script"), "resumen: " + _text(&"_summary_label"))
	_check((_screen.get(&"_new_button") as Button).visible and not (_screen.get(&"_pause_button") as Button).visible, "Nuevo One-shot en lugar de Pausar")
	_check(_text(&"_banner_label") == "El agente terminó el plan.", "banner de fin: " + _text(&"_banner_label"))

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
	await _wait(func() -> bool: return _run.finish_reason.begins_with("Cambios aceptados"))
	_check(_run.finish_reason.begins_with("Cambios aceptados en agent/"), "aceptado: " + _run.finish_reason)
	var branches: Dictionary = await _run.git.run(["branch", "--format=%(refname:short)"])
	_check(str(branches.output).contains("main") and str(branches.output).contains("agent/"), "las dos ramas siguen: " + str(branches.output))

	(_screen.get(&"_new_button") as Button).pressed.emit()
	await _frames(2)
	_check(form.is_visible_in_tree() and goal.text == "Pong de 2 jugadores con puntaje", "Nuevo One-shot vuelve al formulario con el objetivo")
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
		failures.append("hace falta la pantalla Agent dentro del sandbox de tests/make_sandbox.sh")
		return failures
	_run = _screen.get(&"_run")
	var model: Object = _run.model
	model.connect(&"permission_requested", func(request: Object) -> void:
		var title := str(request.get(&"title")) + " " + str(request.get(&"description"))
		var deny := title.contains("git ")
		print("[claude-oneshot] permiso %s: %s" % ["denegado" if deny else "concedido", title.left(160)])
		var option: String = request.call(&"option_id_for", PackedStringArray(["reject_once"] if deny else ["allow_once"]))
		request.call(&"select", option))
	_run.restart_session = func() -> bool: return await _run.controller.call(&"start", AgentProfile.from_dict(AgentProfile.defaults()[0]))
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
	while _run.phase != OneShotRun.Phase.FINISHED and Time.get_ticks_msec() < deadline:
		if _run.last_capture != null and shots == 0:
			shots += 1
			await _frames(5)
			_shot(shot_path, "_playtest")
		await _tree.create_timer(1.0).timeout
	print("[claude-oneshot] fin: %s · playtests %d · tokens %d · %.1f min · checkpoints %s" % [_run.finish_reason, _run.used.playtests, _run.used.tokens, float(_run.used.time) / 60.0, _run.git.checkpoints.map(func(cp: Dictionary) -> String: return cp.name + " " + cp.label)])
	for check: Dictionary in _run.checks:
		print("[claude-oneshot] check %s: %s" % [check.status, check.label])
	_check(_run.phase == OneShotRun.Phase.FINISHED, "el One-shot no terminó a tiempo (%s)" % _run.phase_label())
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


func _find_files(dir: String, extension: String) -> PackedStringArray:
	var found: PackedStringArray = []
	for file: String in DirAccess.get_files_at(dir):
		if file.get_extension() == extension:
			found.append(dir.path_join(file))
	for sub: String in DirAccess.get_directories_at(dir):
		if not sub in [".godot", "addons"]:
			found.append_array(_find_files(dir.path_join(sub), extension))
	return found


func _profile() -> AgentProfile:
	return AgentProfile.from_dict({
		"id": "fake", "display_name": "Agente falso", "command": OS.get_executable_path(),
		"args": ["--headless", "--no-header", "--path", ProjectSettings.globalize_path("res://"),
			"--script", "res://tests/fake_agent.gd", "--", "--scenario=res://tests/scripts/oneshot_ui.json"],
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
