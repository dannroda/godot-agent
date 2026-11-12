@tool
extends RefCounted
## Capturas de la guía (m7-41): con el agente falso y la escena de tests/docs_demo/, saca las
## imágenes del README a `dir` (overview, chat, permission, review, playtest, settings, oneshot y, desde m16-20,
## modes, mode-request, plan y turn-marks). Conviene correrlo con
## el editor en el mismo idioma que GODOT_AGENT_LANGUAGE (un Godot self-contained con
## interface/editor/editor_language): ver tests/docs_shots.sh.

const AgentProfile := preload("res://addons/godot_agent/core/agent_profile.gd")
const SessionModel := preload("res://addons/godot_agent/session/session_model.gd")
const ChatEntry := preload("res://addons/godot_agent/session/chat_entry.gd")
const I18n := preload("res://addons/godot_agent/core/i18n.gd")

const DOCK_SCRIPT := "res://addons/godot_agent/ui/dock/agent_dock.gd"
const PLAN_VIEW_SCRIPT := "res://addons/godot_agent/ui/dock/entries/plan_approval_view.gd"
## Modos del proyecto de la captura (m16-20), en la carpeta por defecto para que los vean el dock y
## godot.request_mode (el proyecto es una copia: tests/docs_shots.sh). Se borran al final.
const MODES_DIR := "res://agent_modes"
## El script que cambia en el último turno para la captura de las marcas por turno (m16-20).
const MARKS_SCRIPT := "res://tests/docs_demo/spawner.gd"
const MAIN_PLUGIN_SCRIPT := "res://addons/godot_agent/agent_plugin.gd"
const ANNOTATIONS_SCRIPT := "res://addons/godot_agent/review/review_annotations.gd"
const DEMO_SCENE := "res://tests/docs_demo/main.tscn"
const MAIN_SCREEN_SCRIPT := "res://addons/godot_agent/ui/main_screen/agent_main_screen.gd"
## Repo y store del One-shot de la captura: aparte, para no dejar ramas ni runs en el proyecto.
const ONESHOT_REPO := "user://docs_oneshot"
const DOCK_WIDTH := 480
## Dock angosto para la captura extra del veredicto (m12-42), si la pide `playtest_narrow_path`.
const NARROW_DOCK_WIDTH := 320
const TURN_TIMEOUT_S := 30.0
## Prompts por idioma (GODOT_AGENT_LANGUAGE); los escenarios en español terminan en _es.
const PROMPTS := {
	"en": {
		"build": "Add a wave counter to the HUD: it should say which asteroid wave is playing.",
		"permission": "Now make the asteroids faster with every wave.",
		"review": "Review the scripts in tests/docs_demo/.",
		"oneshot": "An asteroid shooter: waves that get faster, a score and a game over screen.",
		"playtest": "Asteroids get faster with every wave.",
		"plan": "A game over screen: when an asteroid hits the ship, show the score and a Restart button.",
		"mode_request": "Add a third asteroid wave to the level.",
	},
	"es": {
		"build": "Agregá un contador de oleadas al HUD: que diga qué oleada de asteroides se está jugando.",
		"permission": "Ahora hacé que los asteroides vayan más rápido en cada oleada.",
		"review": "Revisá los scripts de tests/docs_demo/.",
		"oneshot": "Un shooter de asteroides: oleadas cada vez más rápidas, puntaje y pantalla de game over.",
		"playtest": "Los asteroides van más rápido en cada oleada.",
		"plan": "Una pantalla de game over: cuando un asteroide choca la nave, mostrar el puntaje y un botón Reiniciar.",
		"mode_request": "Agregá una tercera oleada de asteroides al nivel.",
	},
}

var failures: PackedStringArray = []
## Si no está vacío, el veredicto del playtest se captura también con el dock angosto en esta ruta (el tour de UX).
var playtest_narrow_path: String = ""
var _tree: SceneTree
var _dock: Control
var _model: Object
var _controller: Object
var _hide_bottom_panel: Callable
var _language := "en"
var _plugin: Node


## `hide_bottom_panel`: el de EditorPlugin. El Agent Log muestra JSON con rutas absolutas.
func run(tree: SceneTree, dir: String, hide_bottom_panel: Callable) -> PackedStringArray:
	_tree = tree
	_hide_bottom_panel = hide_bottom_panel
	_language = "es" if OS.get_environment("GODOT_AGENT_LANGUAGE") == "es" else "en"
	DirAccess.make_dir_recursive_absolute(dir)
	var annotations: Node = null
	for node: Node in tree.root.find_children("*", "Node", true, false):
		var script := node.get_script() as Script
		if script and script.resource_path == DOCK_SCRIPT:
			_dock = node
		elif script and script.resource_path == ANNOTATIONS_SCRIPT:
			annotations = node
	if _dock == null or annotations == null:
		failures.append("no se encontró el dock o las anotaciones")
		return failures
	_model = _dock.get(&"_model")
	_controller = _dock.get(&"_controller")
	for node: Node in tree.root.find_children("*", "Node", true, false):
		var script := node.get_script() as Script
		if script and script.resource_path == MAIN_PLUGIN_SCRIPT and node.get(&"_tabs") != null:
			_plugin = node
	if _plugin == null:
		failures.append("no se encontró el plugin principal")
		return failures
	_show_dock()
	await _widen_dock()
	EditorInterface.open_scene_from_path(DEMO_SCENE)
	EditorInterface.set_main_screen_editor("2D")
	await _frames(10)
	_center_2d_view()

	# Build: una conversación terminada, con el plan, las tools y el diff.
	if not await _start("docs_build"):
		return failures
	_model.call(&"set_harness_mode", SessionModel.HarnessMode.BUILD)
	_dock.call(&"_on_submitted", PROMPTS[_language].build)
	await _wait_ready()
	_hide_bottom_panel.call()
	await _frames(20)
	# Con una segunda pestaña: la principal lleva el pin (m12-50). Las capturas del dock van sin ella,
	# del mismo alto que antes.
	var second := await _open_second_tab()
	_save(_screen(), dir.path_join("overview.png"))
	await _close_tab(second)
	_save(_dock_image(), dir.path_join("chat.png"))
	# El selector de modo abierto sobre la misma conversación.
	await _modes_shot(dir)
	_model.call(&"set_project_mode", {})
	_model.call(&"set_harness_mode", SessionModel.HarnessMode.BUILD)
	await _frames(5)

	# Permiso: la tarjeta queda esperando la respuesta.
	_dock.call(&"_on_submitted", PROMPTS[_language].permission)
	var deadline := Time.get_ticks_msec() + int(TURN_TIMEOUT_S * 1000)
	while not _has_permission_entry() and Time.get_ticks_msec() < deadline:
		await _tree.process_frame
	if not _has_permission_entry():
		failures.append("no apareció la tarjeta de permiso")
	_hide_bottom_panel.call()
	await _frames(20)
	_save(_dock_image(), dir.path_join("permission.png"))
	_controller.call(&"stop")
	await _frames(5)

	await _mode_request_shot(dir)
	_remove_modes()
	await _plan_shot(dir)

	# Review: el hallazgo marcado en el Script Editor.
	if not await _start("docs_review"):
		return failures
	_model.call(&"set_harness_mode", SessionModel.HarnessMode.REVIEW)
	_dock.call(&"_on_submitted", PROMPTS[_language].review)
	await _wait_ready()
	var store: Object = _controller.get(&"review")
	var findings: Array = store.get(&"findings")
	if findings.is_empty():
		failures.append("review: sin hallazgos")
	else:
		annotations.call(&"focus_finding", int(findings[0].id))
		_hide_bottom_panel.call()
		await _frames(20)
		_save(_screen(), dir.path_join("review.png"))
	_controller.call(&"stop")
	await _frames(5)
	await _turn_marks_shot(dir)

	# Playtest: el veredicto con lo que vieron los detectores y los hallazgos con sus acciones.
	if not await _start("docs_playtest"):
		return failures
	_model.call(&"set_harness_mode", SessionModel.HarnessMode.REVIEW)
	await _frames(5)
	var panel: Control = _dock.get(&"_review_panel")
	(panel.get(&"_fold") as FoldableContainer).expand()
	panel.call(&"_start_playtest", PROMPTS[_language].playtest, false, 15)
	await _wait_ready()
	if (_controller.get(&"review").get(&"findings") as Array).is_empty():
		failures.append("playtest: sin hallazgos en el panel")
	_hide_bottom_panel.call()
	await _frames(30)
	_save(_dock_image(), dir.path_join("playtest.png"))
	_check_verdict_card()
	if not playtest_narrow_path.is_empty():
		await _widen_dock(NARROW_DOCK_WIDTH)
		await _frames(20)
		_save(_dock_image(), playtest_narrow_path)
		_check_verdict_card()
		await _widen_dock()
	_controller.call(&"stop")
	await _frames(5)

	# Settings: la matriz de permisos.
	(_dock.get(&"_settings_button") as Button).pressed.emit()
	await _frames(10)
	for node: Node in EditorInterface.get_base_control().get_children():
		if node is ConfirmationDialog and node.has_method(&"matrix_overrides"):
			var nav: ItemList = node.get(&"_nav")
			nav.select(1)
			nav.item_selected.emit(1)
			await _frames(10)
			_save((node as Window).get_texture().get_image(), dir.path_join("settings.png"))
			(node as Window).hide()

	await _oneshot_shot(dir)
	EditorInterface.set_main_screen_editor("2D")
	return failures


## La pantalla One-shot con un run en curso: plan con una tarea hecha y otra en marcha, presupuestos,
## checks, checkpoints y la captura del último playtest. Se guarda solo esa pantalla.
func _oneshot_shot(dir: String) -> void:
	var screen: Control = null
	for node: Node in _tree.root.find_children("*", "VBoxContainer", true, false):
		var script := node.get_script() as Script
		if script and script.resource_path == MAIN_SCREEN_SCRIPT:
			screen = node
	if screen == null:
		failures.append("no se encontró la pantalla One-shot")
		return
	var run: Object = screen.get(&"_run")
	var controller: Object = run.get(&"controller")
	controller.call(&"stop")
	var repo := ProjectSettings.globalize_path(ONESHOT_REPO)
	OS.execute("rm", ["-rf", repo, repo + "_store"])
	DirAccess.make_dir_recursive_absolute(repo)
	var file := FileAccess.open(repo.path_join("project.godot"), FileAccess.WRITE)
	file.store_string("config_version=5\n")
	file.close()
	OS.execute("git", ["-c", "init.defaultBranch=main", "init", "-q", repo])
	OS.execute("git", ["-C", repo, "add", "-A"])
	OS.execute("git", ["-C", repo, "-c", "user.name=docs", "-c", "user.email=docs@example.com", "commit", "-q", "-m", "start"])
	(run.get(&"git") as Object).set(&"root", repo)
	(run.get(&"files") as Object).set(&"project_root", repo)
	(run.get(&"store") as Object).set(&"dir", repo + "_store")
	run.set(&"qa_max_rounds", 0)
	var profile := _profile("docs_oneshot")
	# El run se pasa a la sesión de su propia pestaña al empezar (m17-19): se arranca la que tenga.
	run.set(&"restart_session", func(_lost_id: String) -> bool: return await (run.get(&"controller") as Object).call(&"start", profile))
	screen.set(&"agent_name", func() -> String: return "Claude Code")
	EditorInterface.set_main_screen_editor("One-shot")
	await _frames(10)
	var goal: TextEdit = screen.get(&"_goal_edit")
	goal.text = PROMPTS[_language].oneshot
	goal.text_changed.emit()
	(screen.get(&"_checkpoints_check") as CheckBox).button_pressed = true
	(screen.get(&"_start_button") as Button).pressed.emit()
	var ready := func() -> bool:
		return (screen.get(&"_checks_list") as Control).get_child_count() == 3 \
			and (screen.get(&"_capture_rect") as TextureRect).texture != null \
			and not bool(run.call(&"is_git_busy"))
	var deadline := Time.get_ticks_msec() + int(TURN_TIMEOUT_S * 1000)
	while not ready.call() and Time.get_ticks_msec() < deadline:
		await _tree.process_frame
	if not ready.call():
		failures.append("el One-shot no llegó a mostrar el plan, los checks y la captura")
	_hide_bottom_panel.call()
	await _frames(30)
	_save(_screen().get_region(Rect2i(screen.get_global_rect())), dir.path_join("oneshot.png"))
	run.call(&"stop")
	(run.get(&"controller") as Object).call(&"stop")
	controller.call(&"stop")
	await _frames(5)


## «+» → Nueva sesión, con un nombre, y de vuelta a la principal. Devuelve el id de la pestaña nueva.
func _open_second_tab() -> String:
	var tabs: Control = _plugin.get(&"_tabs")
	var main_id: String = tabs.call(&"active_id")
	(tabs.find_child("NewSessionTabButton", true, false) as Button).pressed.emit()
	(tabs.get(&"_new_menu") as PopupMenu).id_pressed.emit(0)
	await _frames(2)
	var ids: PackedStringArray = tabs.call(&"ids")
	if ids.size() != 2:
		failures.append("«+» no abrió la segunda pestaña: %s" % [ids])
		return ""
	tabs.call(&"set_label", ids[1], "Game over" if _language == "en" else "Game over")
	tabs.call(&"select", main_id)
	await _frames(20)
	if not bool(tabs.call(&"is_pinned", main_id)):
		failures.append("la pestaña principal no lleva el pin")
	return ids[1]


func _close_tab(id: String) -> void:
	if id.is_empty():
		return
	_plugin.call(&"_close_session_tab", id, false)
	await _frames(20)


## Tres modos del proyecto en una carpeta aparte (los de las plantillas de Extensiones › Modes).
func _write_modes() -> void:
	var dir := ProjectSettings.globalize_path(MODES_DIR)
	DirAccess.make_dir_recursive_absolute(dir)
	var es := _language == "es"
	var modes := [
		{"version": 1, "name": "Diseño de niveles" if es else "Level design", "base": "build", "icon": "TileMap",
			"when_to_use": "Armar y ajustar niveles: ubica y ajusta nodos en las escenas, nunca toca scripts" if es else "Laying out levels: places and tunes nodes in scenes, never touches scripts",
			"instructions": "Edit only the .tscn files of the level.", "editable": ["res://tests/docs_demo/*.tscn"]},
		{"version": 1, "name": "Shaders", "base": "build", "icon": "Shader", "shell": "deny",
			"when_to_use": "Escribir y ajustar shaders" if es else "Writing and tuning shaders",
			"editable": ["**/*.gdshader", "**/*.gdshaderinc"]},
		{"version": 1, "name": "Solo tests" if es else "Tests only", "base": "auto", "icon": "Debug",
			"when_to_use": "Escribir tests sin tocar el juego" if es else "Writing tests without touching the game",
			"editable": ["res://tests/**"]},
	]
	for mode: Dictionary in modes:
		var file := FileAccess.open(dir.path_join(str(mode.name).to_lower().replace(" ", "_") + ".json"), FileAccess.WRITE)
		file.store_string(JSON.stringify(mode, "\t"))
		file.close()
	_dock.call(&"load_project_modes")


func _remove_modes() -> void:
	var dir := ProjectSettings.globalize_path(MODES_DIR)
	for file: String in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(file))
	DirAccess.remove_absolute(dir)
	_model.call(&"set_project_mode", {})
	_dock.call(&"load_project_modes")


## El selector de modo del composer abierto, con los modos del proyecto y «Level design (Build)» elegido.
## El menú es una ventana aparte: se pega encima del dock donde se ve.
func _modes_shot(dir: String) -> void:
	_write_modes()
	if not bool(_dock.call(&"choose_project_mode", "Diseño de niveles" if _language == "es" else "Level design")):
		failures.append("modes: no se pudo elegir Level design")
		return
	var composer: Object = _dock.get(&"_composer")
	var button: OptionButton = composer.get(&"_mode_button")
	var label := "%s (%s)" % ["Diseño de niveles" if _language == "es" else "Level design", I18n.t("Build")]
	if button.get_item_text(button.selected) != label:
		failures.append("modes: el selector muestra «%s», no «%s»" % [button.get_item_text(button.selected), label])
	_hide_bottom_panel.call()
	await _frames(10)
	# El menú es una ventana aparte. Sin gestor de ventanas (Xvfb) se cierra en el cuadro siguiente al
	# no recibir el foco: si pasa, se vuelve a mostrar sin la marca de popup. Su imagen se pega encima.
	button.show_popup()
	var popup := button.get_popup()
	await _tree.process_frame
	if not popup.visible:
		var at := popup.position
		popup.set_flag(Window.FLAG_POPUP, false)
		popup.position = at
		popup.show()
	await _frames(10)
	if not popup.visible:
		failures.append("modes: el menú del selector no se abrió")
		return
	var image := _dock_image()
	var dock_rect := Rect2i((_dock.get_parent() as Control).get_global_rect())
	if not popup.is_embedded():
		var menu := popup.get_texture().get_image()
		menu.convert(image.get_format())
		# Donde lo abre Godot: arriba del botón, alineado a su izquierda (sin gestor de ventanas, la
		# posición de la ventana no es confiable).
		var button_rect := Rect2i(button.get_global_rect())
		var at := Vector2i(button_rect.position.x, button_rect.position.y - menu.get_height()) - dock_rect.position
		at.x = clampi(at.x, 0, image.get_width() - menu.get_width())
		image.blit_rect(menu, Rect2i(Vector2i.ZERO, menu.get_size()), at)
	_save(image, dir.path_join("modes.png"))
	popup.hide()
	popup.set_flag(Window.FLAG_POPUP, true)
	await _frames(5)


## godot.request_mode (m11-68) desde Preguntar a «Level design»: la tarjeta con el aviso de más permisos.
func _mode_request_shot(dir: String) -> void:
	if not await _start("docs_mode_request"):
		return
	_model.call(&"set_project_mode", {})
	_model.call(&"set_harness_mode", SessionModel.HarnessMode.ASK)
	_dock.call(&"_on_submitted", PROMPTS[_language].mode_request)
	var deadline := Time.get_ticks_msec() + int(TURN_TIMEOUT_S * 1000)
	while _pending() == null and Time.get_ticks_msec() < deadline:
		await _tree.process_frame
	var request: Object = _pending()
	if request == null:
		failures.append("mode-request: no apareció la tarjeta")
		return
	if not str(request.get(&"description")).contains("⚠"):
		failures.append("mode-request: la tarjeta no avisa de más permisos: %s" % request.get(&"description"))
	_hide_bottom_panel.call()
	await _frames(20)
	_save(_dock_image(), dir.path_join("mode-request.png"))
	request.call(&"select", "stay")
	await _wait_ready()
	_controller.call(&"stop")
	await _frames(5)


## La tarjeta del plan en bloque con dos criterios jugables (m11-23) y, después de aprobar, construir y
## jugar cada criterio, el estado de cada uno en la misma tarjeta.
func _plan_shot(dir: String) -> void:
	var saved_regressions: String = _controller.get(&"regressions_dir")
	var saved_settings: Callable = _controller.get(&"plan_criteria_settings")
	_controller.set(&"regressions_dir", ProjectSettings.globalize_path("user://docs_regressions"))
	_controller.set(&"plan_criteria_settings", func() -> Dictionary: return {"on": true, "max": 6})
	if await _start("docs_plan"):
		await _plan_flow(dir)
		_controller.call(&"stop")
		await _frames(5)
	_controller.set(&"regressions_dir", saved_regressions)
	_controller.set(&"plan_criteria_settings", saved_settings)


func _plan_flow(dir: String) -> void:
	_controller.call(&"request_plan", PROMPTS[_language].plan)
	var view: Control = null
	var deadline := Time.get_ticks_msec() + int(TURN_TIMEOUT_S * 1000)
	while view == null and Time.get_ticks_msec() < deadline:
		await _tree.process_frame
		view = _plan_view()
	if view == null:
		failures.append("plan: no apareció la tarjeta del plan")
		return
	await _wait_ready()
	var check: CheckBox = view.find_child("VerifyCriteria", true, false)
	if check == null or not check.is_visible_in_tree() or not check.text.contains("(2)"):
		failures.append("plan: sin la casilla de los dos criterios")
	_hide_bottom_panel.call()
	await _frames(20)
	_scroll_to(view)
	await _frames(10)
	_save(_dock_image(), dir.path_join("plan.png"))
	var approve: Button = null
	for button: Button in view.find_children("*", "Button", true, false):
		if button.text == I18n.t("Approve and build"):
			approve = button
	if approve == null:
		failures.append("plan: sin «Approve and build»")
		return
	approve.pressed.emit()
	var box: Control = view.find_child("CriteriaResults", true, false)
	var done := func() -> bool:
		return box != null and box.get_child_count() == 2 and (box.get_child(1) as Label).text.begins_with("✓") \
			and (_controller.call(&"recipe_run") as Dictionary).is_empty() and int(_model.get(&"state")) == SessionModel.SessionState.READY
	deadline = Time.get_ticks_msec() + int(TURN_TIMEOUT_S * 2000)
	while not done.call() and Time.get_ticks_msec() < deadline:
		await _tree.process_frame
	if not done.call():
		failures.append("plan: los criterios no quedaron verificados")
		return
	_hide_bottom_panel.call()
	await _frames(20)
	_scroll_to(view)
	await _frames(10)
	_save(_dock_image(), dir.path_join("plan-verified.png"))


func _plan_view() -> Control:
	for node: Node in _dock.find_children("*", "VBoxContainer", true, false):
		var script := node.get_script() as Script
		if script and script.resource_path == PLAN_VIEW_SCRIPT:
			return node
	return null


## Lleva el chat hasta que `control` quede arriba (o entero, si entra).
func _scroll_to(control: Control) -> void:
	var node := control.get_parent()
	while node and not node is ScrollContainer:
		node = node.get_parent()
	if node is ScrollContainer:
		(node as ScrollContainer).ensure_control_visible(control)
		var scroll := node as ScrollContainer
		var top := control.get_global_rect().position.y - scroll.get_global_rect().position.y
		scroll.scroll_vertical += int(top) - 8


## Las marcas del último turno en el Script Editor (m11-66): spawner.gd cambia en dos lugares entre dos
## snapshots de git (tests/docs_shots.sh hace del proyecto copiado un repo) y el gutter los marca con ✓/✗.
func _turn_marks_shot(dir: String) -> void:
	var snapshots: Object = _plugin.get(&"_turn_snapshots")
	var marks: Object = _plugin.get(&"_turn_marks")
	if snapshots == null or not snapshots.get(&"available") or marks == null:
		failures.append("turn-marks: sin snapshots de git (¿el proyecto copiado no es un repo?)")
		return
	var path := ProjectSettings.globalize_path(MARKS_SCRIPT)
	var before := FileAccess.get_file_as_string(path)
	var after := before.replace("@export var asteroids_per_wave: int = 4", "@export var asteroids_per_wave: int = 4\n@export var speed_step: float = 1.15") \
		.replace("\tasteroid.position = Vector2(randf_range(0, 1152), randf_range(0, 648))\n", "\tasteroid.position = Vector2(randf_range(0, 1152), randf_range(0, 648))\n\t\tasteroid.set_meta(&\"speed\", 60.0 * pow(speed_step, wave - 1))\n")
	if after == before or after.count("speed_step") != 2:
		failures.append("turn-marks: no se pudo armar el cambio de %s" % MARKS_SCRIPT)
		return
	var session := str(_controller.get(&"session_key"))
	var start: String = await snapshots.call(&"take", session)
	_write_text(path, after)
	var end: String = await snapshots.call(&"take", session)
	EditorInterface.get_resource_filesystem().update_file(MARKS_SCRIPT)
	await _tree.create_timer(0.5).timeout
	var data := {"session": session, "start": start, "end": end, "files": [{"path": MARKS_SCRIPT.trim_prefix("res://"), "status": "M", "added": 2, "removed": 0}]}
	_controller.set(&"last_turn_changes", data)
	EditorInterface.edit_script(load(MARKS_SCRIPT))
	EditorInterface.set_main_screen_editor("Script")
	_controller.emit_signal(&"turn_changes_reported", data)
	var deadline := Time.get_ticks_msec() + 10000
	while (marks.call(&"hunks_shown", MARKS_SCRIPT) as Array).size() != 2 and Time.get_ticks_msec() < deadline:
		await _tree.process_frame
	if (marks.call(&"hunks_shown", MARKS_SCRIPT) as Array).size() != 2:
		failures.append("turn-marks: no se marcaron los dos trozos: %s" % [marks.call(&"hunks_shown", MARKS_SCRIPT)])
	_hide_bottom_panel.call()
	await _frames(20)
	_save(_screen(), dir.path_join("turn-marks.png"))
	_controller.set(&"last_turn_changes", {})
	_write_text(path, before)
	EditorInterface.get_resource_filesystem().update_file(MARKS_SCRIPT)
	marks.call(&"refresh")
	await _frames(5)


func _write_text(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()


func _pending() -> Object:
	for request: Object in _model.get(&"pending_permissions"):
		if request.call(&"is_pending"):
			return request
	return null


## El agente falso con el guion `scenario` (en el idioma de las capturas), con el nombre de Claude Code.
func _profile(scenario: String) -> AgentProfile:
	if _language != "en":
		scenario += "_" + _language
	return AgentProfile.from_dict({
		"id": "claude", "display_name": "Claude Code", "command": OS.get_executable_path(),
		"args": ["--headless", "--no-header", "--path", ProjectSettings.globalize_path("res://"),
			"--script", "res://tests/fake_agent.gd", "--", "--scenario=res://tests/scripts/%s.json" % scenario],
	})


func _start(scenario: String) -> bool:
	if not await _controller.call(&"start", _profile(scenario)):
		failures.append("no arrancó la sesión %s: %s" % [scenario, _model.get(&"failure_message")])
		return false
	return true


func _wait_ready() -> void:
	var deadline := Time.get_ticks_msec() + int(TURN_TIMEOUT_S * 1000)
	await _frames(2)
	while int(_model.get(&"state")) != SessionModel.SessionState.READY and Time.get_ticks_msec() < deadline:
		await _tree.process_frame
	if int(_model.get(&"state")) != SessionModel.SessionState.READY:
		failures.append("el turno no terminó (estado %d)" % int(_model.get(&"state")))


func _has_permission_entry() -> bool:
	for entry: ChatEntry in _model.call(&"entries"):
		if entry.kind == ChatEntry.EntryKind.PERMISSION:
			return true
	return false


func _show_dock() -> void:
	# Con un layout limpio (tests/docs_shots.sh) el dock arranca en una pestaña detrás del Inspector:
	# se trae al frente como lo hace el addon, con sus EditorSurfaces.
	for node: Node in _dock.get_tree().root.find_children("*", "Node", true, false):
		var script := node.get_script() as Script
		if script and script.resource_path == MAIN_PLUGIN_SCRIPT and node.get(&"_surfaces") != null:
			(node.get(&"_surfaces") as Object).call(&"make_visible", 0)  # EditorSurface.SIDE
			return
	var guard := _dock.get_parent()
	var holder := guard.get_parent()
	if holder.has_method(&"make_visible"):
		holder.call(&"make_visible")
	elif holder is TabContainer:
		(holder as TabContainer).current_tab = guard.get_index()


## Ensancha la columna del dock moviendo el divisor que la separa del centro, en el SplitContainer
## horizontal que la contiene (en 4.6+ tiene varios hijos y un offset por divisor: split_offsets).
func _widen_dock(width: int = DOCK_WIDTH) -> void:
	await _frames(5)
	var node: Node = _dock
	while node and node != EditorInterface.get_base_control():
		var parent := node.get_parent()
		if parent is SplitContainer and not (parent as SplitContainer).vertical and node.get_index() > 0:
			var split := parent as SplitContainer
			# Un offset por divisor entre hijos visibles.
			var divider := -1
			for child: Node in split.get_children():
				if child == node:
					break
				if child is Control and (child as Control).visible:
					divider += 1
			for attempt in 4:
				var missing := width - _dock.size.x
				if absf(missing) < 4.0:
					return
				var offsets: Variant = split.get(&"split_offsets")
				if offsets is PackedInt32Array and divider >= 0 and divider < (offsets as PackedInt32Array).size():
					var list := offsets as PackedInt32Array
					list[divider] -= int(missing)
					split.set(&"split_offsets", list)
				else:
					split.split_offset -= int(missing)
				await _frames(5)
			if absf(width - _dock.size.x) >= 4.0:
				failures.append("no se pudo ensanchar el dock (%d px)" % _dock.size.x)
			return
		node = parent


func _center_2d_view() -> void:
	# El 2D muestra la escena entera: «Frame Selection» con todo seleccionado sería lo justo, pero
	# alcanza con el zoom que deja ver los 1152x648 del juego.
	var selection := EditorInterface.get_selection()
	selection.clear()


## El veredicto del playtest es una tarjeta con jerarquía (m12-42): el título lleva el resultado y
## el motivo, y la evidencia y los pasos van en secciones plegables que entran en el dock.
func _check_verdict_card() -> void:
	var verdict: Object = null
	for entry: Object in _model.call(&"entries"):
		if entry.get(&"kind") == ChatEntry.EntryKind.NOTICE and str(entry.get(&"title")).begins_with(I18n.t("Playtest: failed")):
			verdict = entry
	if verdict == null:
		failures.append("playtest: no hay aviso con título «Playtest: failed»")
		return
	var sections: Array = verdict.get(&"sections")
	var titles := sections.map(func(section: Dictionary) -> String: return str(section.title).get_slice(" · ", 0))
	if not (I18n.t("Evidence") in titles and I18n.t("To reproduce") in titles):
		failures.append("playtest: faltan las secciones de evidencia y pasos (%s)" % [titles])
	var conversation: Object = _dock.get(&"_conversation")
	var view: Control = (conversation.get(&"_views") as Dictionary).get(verdict.get(&"id"))
	var folds: Array = view.find_children("*", "FoldableContainer", true, false) if view else []
	if folds.size() != sections.size():
		failures.append("playtest: %d secciones plegables en la tarjeta, %d en el aviso" % [folds.size(), sections.size()])
	var dock_rect := (_dock.get_parent() as Control).get_global_rect()
	for fold: FoldableContainer in folds:
		var trust := fold.title.begins_with(I18n.t("May have changed the game directly, not by playing"))
		if fold.folded == trust:
			failures.append("playtest: la sección «%s» empieza %s" % [fold.title, "plegada" if trust else "abierta"])
		if fold.get_global_rect().end.x > dock_rect.end.x + 1.0:
			failures.append("playtest: la sección «%s» sale del dock (%d > %d)" % [fold.title, fold.get_global_rect().end.x, dock_rect.end.x])


func _screen() -> Image:
	return EditorInterface.get_base_control().get_viewport().get_texture().get_image()


func _dock_image() -> Image:
	return _screen().get_region(Rect2i((_dock.get_parent() as Control).get_global_rect()))


func _save(image: Image, path: String) -> void:
	var err := image.save_png(path)
	if err != OK:
		failures.append("no se pudo guardar %s (%s)" % [path, error_string(err)])
	else:
		print("[docs-shots] ", path)


func _frames(count: int) -> void:
	for i in count:
		await _tree.process_frame
