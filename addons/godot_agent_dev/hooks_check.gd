@tool
extends RefCounted
## m11-24 en el editor: hooks del proyecto con eventos de verdad.
## 1. Un hook de «saved» sin aprobar: guardar una escena del editor no lo corre y la pestaña activa
##    avisa con «Aprobar…»; el diálogo muestra lo que corre y «Allow on this machine» lo aprueba.
## 2. Aprobado, el próximo guardado del usuario lo corre (un comando sin shell que deja una marca).
## 3. Lo que escribe el agente es un guardado by=agent: corre el hook by=agent y no el by=user.
## 4. Un hook de prompt deja un aviso con «Send to the agent» y no manda nada; con auto_send y el tope de
##    prompts seguidos alcanzado, también queda en aviso y lo dice.
## 5. Un hook de tool corre godot.validate_scripts (diagnostics) y no corre godot.delete_file (edit_files).
## 6. Un hook de tool que nombra una tool del proyecto (m11-46): sin aprobar el código de la tool no hay
##    tool; aprobado, el hook la corre con sus argumentos.
## La aprobación va a una tienda en memoria y los hooks del proyecto se ponen en memoria y se
## restauran: no se guarda nada.

const HarnessSettings := preload("res://addons/godot_agent/core/harness_settings.gd")
const ProjectHooks := preload("res://addons/godot_agent/core/project_hooks.gd")
const SessionController := preload("res://addons/godot_agent/session/session_controller.gd")
const PLUGIN_SCRIPT := "res://addons/godot_agent/agent_plugin.gd"
const WORK_DIR := "res://tests/tmp/hooks"
const SCENE := WORK_DIR + "/level.tscn"
const TOOLS_DIR := WORK_DIR + "/agent_tools"
const PROBE_TOOL := """@tool
extends "res://addons/godot_agent/api/agent_tool.gd"

func _description() -> String:
	return "Writes a marker file for hooks_check."

func _parameters() -> Dictionary:
	return {"properties": {"path": {"type": "string"}, "text": {"type": "string"}}, "required": ["path", "text"]}

func _run(args: Dictionary, _ctx: RefCounted) -> Variant:
	var file := FileAccess.open(args.path, FileAccess.WRITE)
	file.store_string(args.text)
	file.close()
	return "marked"
"""
## Un tool hook corre godot.validate_scripts sobre todo el proyecto: en CI puede pasar de 8 s.
const WAIT_MS := 30000

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
	var loader: Object = plugin.get(&"_project_tools")
	var saved_tools := {"dir": loader.get(&"dir"), "approved": loader.get(&"is_approved")} if loader else {}
	await _run(runner, config, controller)
	if loader:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TOOLS_DIR).path_join("hook_probe.gd"))
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TOOLS_DIR))
		loader.set(&"dir", saved_tools.dir)
		loader.set(&"is_approved", saved_tools.approved)
		loader.call(&"refresh")
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
	await _idle(runner)

	# 4. Prompt: aviso con «Send to the agent», sin turno; con auto_send y el tope alcanzado, también.
	var prompt_hook := {"name": "Review level", "event": "saved", "paths": [WORK_DIR + "/**"], "action": "prompt", "prompt": "Review the level I just saved."}
	var capped_hook := {"name": "Auto review", "event": "saved", "paths": [WORK_DIR + "/**"], "action": "prompt", "prompt": "Auto review.", "auto_send": true}
	var tool_ok := {"name": "Validate", "event": "saved", "paths": [WORK_DIR + "/**"], "action": "tool", "tool": "godot.validate_scripts"}
	var tool_denied := {"name": "Delete", "event": "saved", "paths": [WORK_DIR + "/**"], "action": "tool", "tool": "delete_file", "args": {"path": SCENE}}
	config.set(&"hooks", [prompt_hook, capped_hook, tool_ok, tool_denied])
	for hook: Dictionary in [prompt_hook, capped_hook, tool_ok, tool_denied]:
		store.approve_command(ProjectHooks.approval_key(project, ProjectHooks.normalize(hook)))
	var plugin_node: Object = runner.get_parent()
	plugin_node.set(&"_hook_prompts_in_row", ProjectHooks.MAX_AUTO_PROMPTS)
	var results := {}
	var on_finished := func(hook: Dictionary, result: Dictionary) -> void: results[hook.name] = result
	runner.connect(&"finished", on_finished)
	var before: int = (model.call(&"entries") as Array).size()
	EditorInterface.mark_scene_as_unsaved()
	EditorInterface.save_scene()
	await _until(func() -> bool: return results.size() >= 4)
	runner.disconnect(&"finished", on_finished)
	var notices := {}
	for entry: Object in (model.call(&"entries") as Array).slice(before):
		notices[str(entry.get(&"title"))] = entry
	var review: Object = notices.get("Project hook «Review level»")
	_expect(review != null and (review.get(&"actions") as Array).size() == 1 and str((review.get(&"actions") as Array)[0].label) == "Send to the agent", "el hook de prompt deja un aviso con «Send to the agent» · %s" % [notices.keys()])
	var capped: Object = notices.get("Project hook «Auto review»")
	_expect(capped != null and str(capped.get(&"text")).contains("Not sent on its own"), "auto_send con el tope alcanzado queda en aviso y lo dice")
	_expect(not bool(model.call(&"is_busy")), "no se mandó ningún turno")
	_expect(results.has("Validate") and bool(results.Validate.ok), "godot.validate_scripts corre · %s" % [results.get("Validate")])
	_expect(results.has("Delete") and not bool(results.Delete.ok) and str(results.Delete.output).contains("edit_files"), "godot.delete_file no corre: no es de leer, revisar ni correr · %s" % [results.get("Delete")])
	_expect(FileAccess.file_exists(SCENE), "y la escena sigue ahí")
	plugin_node.set(&"_hook_prompts_in_row", 0)
	await _idle(runner)

	# 6. Una tool del proyecto desde un hook: sin aprobar su código no existe; aprobada, corre.
	var loader: Object = plugin_node.get(&"_project_tools")
	_expect(loader != null, "el plugin tiene el loader de tools del proyecto")
	if loader:
		var tools_dir := ProjectSettings.globalize_path(TOOLS_DIR)
		DirAccess.make_dir_recursive_absolute(tools_dir)
		var file := FileAccess.open(tools_dir.path_join("hook_probe.gd"), FileAccess.WRITE)
		file.store_string(PROBE_TOOL)
		file.close()
		loader.set(&"dir", TOOLS_DIR)
		loader.set(&"is_approved", store.is_command_approved)
		loader.call(&"refresh")
		var marker := work.path_join("tool.marker")
		DirAccess.remove_absolute(marker)
		var tool_hook := {"name": "Project tool", "event": "saved", "paths": [WORK_DIR + "/*.tscn"], "action": "tool", "tool": "godot.hook_probe", "args": {"path": marker, "text": "from hook"}}
		config.set(&"hooks", [tool_hook])
		store.approve_command(ProjectHooks.approval_key(project, ProjectHooks.normalize(tool_hook)))
		results.clear()
		runner.connect(&"finished", on_finished)
		EditorInterface.mark_scene_as_unsaved()
		EditorInterface.save_scene()
		await _until(func() -> bool: return results.has("Project tool"))
		_expect(results.has("Project tool") and not bool(results["Project tool"].ok) and str(results["Project tool"].output).contains("no tool"), "con el código sin aprobar, el hook no encuentra la tool · %s" % [results.get("Project tool")])
		_expect(not FileAccess.file_exists(marker), "y no corrió")
		var held: Array = loader.call(&"held")
		_expect(held.size() == 1, "la tool queda frenada · %s" % [held])
		if held.size() == 1:
			store.approve_command(str(held[0].key))
			loader.call(&"refresh")
			results.clear()
			await _idle(runner)
			EditorInterface.mark_scene_as_unsaved()
			EditorInterface.save_scene()
			await _until(func() -> bool: return results.has("Project tool"))
			_expect(results.has("Project tool") and bool(results["Project tool"].ok) and str(results["Project tool"].output).contains("marked"), "aprobada, el hook corre la tool del proyecto · %s" % [results.get("Project tool")])
			_expect(FileAccess.get_file_as_string(marker) == "from hook", "con los argumentos del hook")
		runner.disconnect(&"finished", on_finished)
		DirAccess.remove_absolute(marker)

	# Que termine la corrida (espera la salida un momento después de que sale el proceso): si el editor
	# se cierra antes, el proceso queda vivo hasta el final.
	await _idle(runner)
	EditorInterface.close_scene()


func _idle(runner: Node) -> void:
	var deadline := Time.get_ticks_msec() + WAIT_MS
	while Time.get_ticks_msec() < deadline and (not (runner.get(&"_running") as Dictionary).is_empty() or not (runner.get(&"_pending") as Dictionary).is_empty()):
		await _tree.process_frame


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
