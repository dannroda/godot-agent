@tool
extends RefCounted
## godot.project_map (m11-26): el mapa rankeado del proyecto (ProjectMap) sobre un ProjectIndex de
## solo estructura. El índice, el grafo y el texto se arman en un worker (en un proyecto de 744
## scripts, 315 escenas y 356 .tres: ~2.3 s la primera vez, ~0.45 s después, porque el índice
## reusa lo que no cambió por mtime). Las llamadas que llegan mientras se arma esperan a que termine
## y arman la suya sobre ese índice (lo que no cambió no se vuelve a leer).
## `wait()` corta el build y lo espera: el plugin la llama al deshabilitarse (si el editor se cierra
## con el worker andando, Godot aborta).

const McpTool := preload("../mcp_tool.gd")
const PermissionPolicy := preload("../../session/permission_policy.gd")
const ProjectIndex := preload("../../completion/project_index.gd")
const ProjectMap := preload("../project_map.gd")

## Cuántos nombres del foco entran en el encabezado; el resto se cuenta.
const LABEL_PATHS := 5
const CANCELLED := "The project map was interrupted: the plugin is shutting down."

## Raíz del proyecto a mapear (los tests y la medición usan otra carpeta).
var root: String = "res://"
## Callable() -> PackedStringArray: lo abierto en el editor (escena actual y script actual), el foco
## cuando el agente no pasa uno. Sin él (tests), sin foco.
var editor_focus: Callable

var _index: ProjectIndex
var _building: bool = false
## La tarea del worker en curso (-1: ninguna) y su corte, compartido con ProjectIndex.build.
var _task: int = -1
var _cancel: Array = [false]


func tools() -> Array:
	return [
		McpTool.enveloped(McpTool.create("project_map", PermissionPolicy.GROUP_READ,
			"A ranked map of the project to get oriented before reading files one by one: the scripts, scenes and resources most related to `focus`, each with its line-numbered signals, public functions, exports and enums (scripts), node tree and saved signal connections (scenes), and where each script is used. Relations come from what Godot uses: scripts attached in scenes, instanced scenes, resources in .tscn/.tres, saved connections, preload/load paths, class_name and autoload names in code, extends and groups. Without `focus` it ranks toward the scene and script open in the editor. Files in res://addons/ (plugins) are left out unless the focus is in there.",
			{
				"focus": {"type": "array", "items": {"type": "string"}, "description": "res:// paths, class_names, autoload names or file names (with or without extension) to rank toward"},
				"max_tokens": {"type": "integer", "description": "Size of the answer (default %d, %d–%d)" % [ProjectMap.DEFAULT_TOKENS, ProjectMap.MIN_TOKENS, ProjectMap.MAX_TOKENS]},
			}, [], _project_map), McpTool.ENVELOPE_ALL),
	]


func _project_map(args: Dictionary) -> Dictionary:
	var focus := PackedStringArray()
	var asked: Variant = args.get("focus")
	if asked is Array:
		for item: Variant in asked:
			focus.append(str(item))
	var from_editor := focus.is_empty()
	if from_editor and editor_focus.is_valid():
		focus = editor_focus.call()
	var tree := Engine.get_main_loop() as SceneTree
	# Una llamada que llega durante un build espera a que termine y arma la suya sobre ese índice.
	while _building:
		await tree.process_frame
	if _cancel[0]:
		return McpTool.error(CANCELLED)
	var job := {"root": root, "previous": _index, "focus": focus, "from_editor": from_editor, "cancel": _cancel,
		"autoloads": read_autoloads(root),
		"max_tokens": McpTool.int_arg(args, "max_tokens", ProjectMap.DEFAULT_TOKENS), "result": {}}
	_building = true
	var task := WorkerThreadPool.add_task(_work.bind(job), false, "godot.project_map")
	_task = task
	while _task == task and not WorkerThreadPool.is_task_completed(task):
		await tree.process_frame
	# `wait()` ya la esperó (el plugin se deshabilita): esperarla otra vez es un error de Godot.
	if _task == task:
		WorkerThreadPool.wait_for_task_completion(task)
		_task = -1
	_building = false
	var result: Dictionary = job.result
	if _cancel[0] or result.is_empty():
		return McpTool.error(CANCELLED)
	_index = result.get("index")
	return McpTool.text(str(result.get("text", "")))


## Corta el build en curso y lo espera (el plugin al deshabilitarse). Después no arma más.
func wait() -> void:
	_cancel[0] = true
	if _task >= 0:
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1


## Los autoloads de project.godot con sus rutas; los guardados como uid:// (Godot 4.4+) se resuelven
## con ResourceUID en el hilo principal. Los que no resuelve quedan para ProjectMap (los .uid).
static func read_autoloads(index_root: String) -> Dictionary:
	var found := ProjectMap.read_autoloads(index_root)
	if index_root != "res://":
		return found
	for name: String in found:
		var path := str(found[name])
		if path.begins_with("uid://"):
			var id := ResourceUID.text_to_id(path)
			if id != ResourceUID.INVALID_ID and ResourceUID.has_id(id):
				found[name] = ResourceUID.get_id_path(id)
	return found


## En el worker: índice (reusando el anterior), grafo, ranking y texto.
static func _work(job: Dictionary) -> void:
	var cancel: Array = job.cancel
	var index: ProjectIndex = ProjectIndex.build({"root": job.root, "structure_only": true, "previous": job.previous, "cancel": cancel})
	if cancel[0]:
		return
	var map := ProjectMap.create(index, job.root, job.autoloads)
	var resolved: Dictionary = map.resolve_focus(job.focus)
	var paths: PackedStringArray = resolved.paths
	map.include_addons = paths.size() > 0 and Array(paths).any(func(path: String) -> bool: return path.begins_with(ProjectMap.ADDONS))
	var label := "the whole project"
	if not paths.is_empty():
		var named := ", ".join(paths.slice(0, LABEL_PATHS)) + (" and %d more" % (paths.size() - LABEL_PATHS) if paths.size() > LABEL_PATHS else "")
		label = ("what is open in the editor: " if job.from_editor else "") + named
	var text: String = map.render(paths, int(job.max_tokens), label)
	var unknown: PackedStringArray = resolved.unknown
	if not unknown.is_empty():
		var named := ", ".join(unknown.slice(0, LABEL_PATHS)) + (" and %d more" % (unknown.size() - LABEL_PATHS) if unknown.size() > LABEL_PATHS else "")
		text = "Not found in the project: %s.\n%s" % [named, text]
	job.result = {"index": index, "text": text}
