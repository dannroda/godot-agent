@tool
extends RefCounted
## Capturas de la guía (m7-41): con el agente falso y la escena de tests/docs_demo/, saca las
## imágenes del README a `dir` (overview, chat, permission, review, settings y oneshot). Conviene correrlo con
## el editor en el mismo idioma que GODOT_AGENT_LANGUAGE (un Godot self-contained con
## interface/editor/editor_language): ver tests/docs_shots.sh.

const AgentProfile := preload("res://addons/godot_agent/core/agent_profile.gd")
const SessionModel := preload("res://addons/godot_agent/session/session_model.gd")
const ChatEntry := preload("res://addons/godot_agent/session/chat_entry.gd")

const DOCK_SCRIPT := "res://addons/godot_agent/ui/dock/agent_dock.gd"
const MAIN_PLUGIN_SCRIPT := "res://addons/godot_agent/plugin.gd"
const ANNOTATIONS_SCRIPT := "res://addons/godot_agent/review/review_annotations.gd"
const DEMO_SCENE := "res://tests/docs_demo/main.tscn"
const MAIN_SCREEN_SCRIPT := "res://addons/godot_agent/ui/main_screen/agent_main_screen.gd"
## Repo y store del One-shot de la captura: aparte, para no dejar ramas ni runs en el proyecto.
const ONESHOT_REPO := "user://docs_oneshot"
const DOCK_WIDTH := 480
const TURN_TIMEOUT_S := 30.0
## Prompts por idioma (GODOT_AGENT_LANGUAGE); los escenarios en español terminan en _es.
const PROMPTS := {
	"en": {
		"build": "Add a wave counter to the HUD: it should say which asteroid wave is playing.",
		"permission": "Now make the asteroids faster with every wave.",
		"review": "Review the scripts in tests/docs_demo/.",
		"oneshot": "An asteroid shooter: waves that get faster, a score and a game over screen.",
	},
	"es": {
		"build": "Agregá un contador de oleadas al HUD: que diga qué oleada de asteroides se está jugando.",
		"permission": "Ahora hacé que los asteroides vayan más rápido en cada oleada.",
		"review": "Revisá los scripts de tests/docs_demo/.",
		"oneshot": "Un shooter de asteroides: oleadas cada vez más rápidas, puntaje y pantalla de game over.",
	},
}

var failures: PackedStringArray = []
var _tree: SceneTree
var _dock: Control
var _model: Object
var _controller: Object
var _hide_bottom_panel: Callable
var _language := "en"


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
	_save(_screen(), dir.path_join("overview.png"))
	_save(_dock_image(), dir.path_join("chat.png"))

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
	run.set(&"restart_session", func(_lost_id: String) -> bool: return await controller.call(&"start", profile))
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
	controller.call(&"stop")
	await _frames(5)


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
	for node: Node in _dock.get_tree().root.find_children("*", "EditorPlugin", true, false):
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
func _widen_dock() -> void:
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
				var missing := DOCK_WIDTH - _dock.size.x
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
			if absf(DOCK_WIDTH - _dock.size.x) >= 4.0:
				failures.append("no se pudo ensanchar el dock (%d px)" % _dock.size.x)
			return
		node = parent


func _center_2d_view() -> void:
	# El 2D muestra la escena entera: «Frame Selection» con todo seleccionado sería lo justo, pero
	# alcanza con el zoom que deja ver los 1152x648 del juego.
	var selection := EditorInterface.get_selection()
	selection.clear()


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
