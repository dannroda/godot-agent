@tool
extends RefCounted
## m11-24 en el editor: hooks del proyecto con eventos de verdad.
## 1. Un hook de «saved» sin aprobar: guardar una escena del editor no lo corre y la pestaña activa
##    avisa con «Aprobar…»; el diálogo muestra lo que corre y «Allow on this machine» lo aprueba.
## 2. Aprobado, el próximo guardado del usuario lo corre (un comando sin shell que deja una marca).
## 3. Lo que escribe el agente es un guardado by=agent: corre el hook by=agent y no el by=user.
## La aprobación va a una tienda en memoria y los hooks del proyecto se ponen en memoria y se
## restauran: no se guarda nada.

const HarnessSettings := preload("res://addons/godot_agent/core/harness_settings.gd")
const ProjectHooks := preload("res://addons/godot_agent/core/project_hooks.gd")
const SessionController := preload("res://addons/godot_agent/session/session_controller.gd")
const PLUGIN_SCRIPT := "res://addons/godot_agent/agent_plugin.gd"
const WORK_DIR := "res://tests/tmp/hooks"
const SCENE := WORK_DIR + "/level.tscn"
const WAIT_MS := 8000

var failures: PackedStringArray = []
var _tree: SceneTree
var _dock: Control


func run(tree: SceneTree, dock: Control) -> PackedStringArray:
	_tree = tree
	_dock = dock
	var plugin: Node = null
	for node: Node in tree.root.find_children("*", "Node", true, false):
		if node.get_script() and (node.get_script() as Script).resource_path == PLUGIN_SCRIPT:
			plugin = node
	var runner: Node = plugin.get(&"_hooks") if plugin else null
	if runner == null:
		failures.append("el plugin no tiene el runner de hooks")
		return failures
	var config: Object = plugin.get(&"_project_config")
	var controller: Object = dock.get(&"_controller")
	var saved := {"hooks": config.get(&"hooks"), "approved": runner.get(&"is_approved"), "approve": controller.get(&"approve_command"), "debounce": runner.get(&"debounce_s")}
	await _run(runner, config, controller)
	config.set(&"hooks", saved.hooks)
	runner.set(&"is_approved", saved.approved)
	runner.set(&"debounce_s", saved.debounce)
	runner.call(&"forget_held")
	controller.set(&"approve_command", saved.approve)
	return failures


func _run(runner: Node, config: Object, controller: Object) -> void:
	var project := ProjectSettings.globalize_path("res://")
	var work := ProjectSettings.globalize_path(WORK_DIR)
	DirAccess.make_dir_recursive_absolute(work)
	for marker in ["user.marker", "agent.marker"]:
		DirAccess.remove_absolute(work.path_join(marker))
	var user_hook := {"name": "Mark user saves", "event": "saved", "paths": [WORK_DIR + "/**"], "command": "touch %s" % work.path_join("user.marker")}
	var agent_hook := {"name": "Mark agent saves", "event": "saved", "by": "agent", "paths": [WORK_DIR + "/**"], "command": "touch %s" % work.path_join("agent.marker")}
	config.set(&"hooks", [user_hook, agent_hook])
	var store := HarnessSettings.new()
	store.approve_command(ProjectHooks.approval_key(project, ProjectHooks.normalize(agent_hook)))
	runner.set(&"is_approved", store.is_command_approved)
	runner.set(&"debounce_s", 0.2)
	runner.call(&"forget_held")
	controller.set(&"approve_command", store.approve_command)
	var model: Object = _dock.get(&"_model")

	# 1. Sin aprobar: no corre y avisa.
	var root := Node2D.new()
	root.name = "Level"
	var scene := PackedScene.new()
	scene.pack(root)
	root.free()
	ResourceSaver.save(scene, SCENE)
	EditorInterface.get_resource_filesystem().scan()
	await _frames(20)
	EditorInterface.open_scene_from_path(SCENE)
	await _frames(10)
	EditorInterface.save_scene()
	var notice: Object = null
	var deadline := Time.get_ticks_msec() + WAIT_MS
	while notice == null and Time.get_ticks_msec() < deadline:
		await _tree.process_frame
		for entry: Object in model.call(&"entries"):
			if str(entry.get(&"text")).contains("«Mark user saves» is not approved"):
				notice = entry
	_expect(notice != null, "guardar sin aprobar avisa en la pestaña activa")
	await _frames(30)
	_expect(not FileAccess.file_exists(work.path_join("user.marker")), "sin aprobar no corre")
	if notice == null:
		return
	var actions: Array = notice.get(&"actions")
	_expect(actions.size() == 1 and str(actions[0].id) == SessionController.ACTION_APPROVE_ON_MACHINE, "con «Aprobar…» · %s" % [actions])
	if actions.is_empty():
		return
	_dock.call(&"_on_action_requested", str(actions[0].id), actions[0].data)
	await _tree.process_frame
	var dialog: ConfirmationDialog = null
	for child: Node in _dock.get_children():
		if child is ConfirmationDialog and (child as ConfirmationDialog).visible:
			dialog = child
	_expect(dialog != null and dialog.dialog_text.contains("touch") and dialog.dialog_text.contains("user.marker"), "el diálogo muestra el comando")
	if dialog:
		dialog.confirmed.emit()
		dialog.hide()
	_expect(store.is_command_approved(ProjectHooks.approval_key(project, ProjectHooks.normalize(user_hook))), "«Allow on this machine» lo aprueba")

	# 2. Aprobado: el próximo guardado del usuario lo corre; el by=agent no.
	EditorInterface.mark_scene_as_unsaved()
	EditorInterface.save_scene()
	await _until(func() -> bool: return FileAccess.file_exists(work.path_join("user.marker")))
	_expect(FileAccess.file_exists(work.path_join("user.marker")), "aprobado, guardar la escena lo corre")
	_expect(not FileAccess.file_exists(work.path_join("agent.marker")), "el hook by=agent no corre con un guardado del usuario")

	# 3. Lo que escribe el agente.
	DirAccess.remove_absolute(work.path_join("user.marker"))
	var plugin: Object = runner.get_parent()
	plugin.call(&"_after_agent_write", ProjectSettings.globalize_path(SCENE))
	await _until(func() -> bool: return FileAccess.file_exists(work.path_join("agent.marker")))
	_expect(FileAccess.file_exists(work.path_join("agent.marker")), "lo que escribe el agente corre el hook by=agent")
	_expect(not FileAccess.file_exists(work.path_join("user.marker")), "y no el by=user")
	# Que termine la corrida (espera la salida un momento después de que sale el proceso): si el editor
	# se cierra antes, el proceso queda vivo hasta el final.
	var deadline_idle := Time.get_ticks_msec() + WAIT_MS
	while Time.get_ticks_msec() < deadline_idle and (not (runner.get(&"_running") as Dictionary).is_empty() or not (runner.get(&"_pending") as Dictionary).is_empty()):
		await _tree.process_frame
	EditorInterface.close_scene()


func _until(done: Callable) -> void:
	var deadline := Time.get_ticks_msec() + WAIT_MS
	while not bool(done.call()) and Time.get_ticks_msec() < deadline:
		await _tree.process_frame
	await _frames(10)


func _frames(count: int) -> void:
	for i in count:
		await _tree.process_frame


func _expect(condition: bool, label: String) -> void:
	if not condition:
		failures.append(label)
