@tool
extends RefCounted
## godot.project_map (m11-26): el mapa rankeado del proyecto (ProjectMap) sobre un ProjectIndex de
## solo estructura. El índice, el grafo y el texto se arman en un worker (en un proyecto de 744
## scripts, 315 escenas y 356 .tres: ~3.5 s la primera vez, ~0.5 s después, porque el índice
## reusa lo que no cambió por mtime). Las llamadas que llegan mientras se arma esperan a la misma.

const McpTool := preload("../mcp_tool.gd")
const PermissionPolicy := preload("../../session/permission_policy.gd")
const ProjectIndex := preload("../../completion/project_index.gd")
const ProjectMap := preload("../project_map.gd")

## Raíz del proyecto a mapear (los tests y la medición usan otra carpeta).
var root: String = "res://"
## Callable() -> PackedStringArray: lo abierto en el editor (escena actual y script actual), el foco
## cuando el agente no pasa uno. Sin él (tests), sin foco.
var editor_focus: Callable

var _index: ProjectIndex
var _building: bool = false


func tools() -> Array:
	return [
		McpTool.enveloped(McpTool.create("project_map", PermissionPolicy.GROUP_READ,
			"A ranked map of the project to get oriented before reading files one by one: the scripts, scenes and resources most related to `focus`, each with its line-numbered signals, public functions, exports and enums (scripts), node tree and saved signal connections (scenes), and where each script is used. Relations come from what Godot uses: scripts attached in scenes, instanced scenes, resources in .tscn/.tres, saved connections, preload/load paths, class_name and autoload names in code, extends and groups. Without `focus` it ranks toward the scene and script open in the editor.",
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
	var job := {"root": root, "previous": _index, "focus": focus, "from_editor": from_editor,
		"max_tokens": McpTool.int_arg(args, "max_tokens", ProjectMap.DEFAULT_TOKENS), "result": {}}
	while _building:
		await (Engine.get_main_loop() as SceneTree).process_frame
	_building = true
	var task := WorkerThreadPool.add_task(_work.bind(job), false, "godot.project_map")
	while not WorkerThreadPool.is_task_completed(task):
		await (Engine.get_main_loop() as SceneTree).process_frame
	WorkerThreadPool.wait_for_task_completion(task)
	_building = false
	var result: Dictionary = job.result
	_index = result.get("index")
	return McpTool.text(str(result.get("text", "")))


## En el worker: índice (reusando el anterior), grafo, ranking y texto.
static func _work(job: Dictionary) -> void:
	var index: ProjectIndex = ProjectIndex.build({"root": job.root, "structure_only": true, "previous": job.previous})
	var map := ProjectMap.create(index, job.root, ProjectMap.read_autoloads(job.root))
	var resolved: Dictionary = map.resolve_focus(job.focus)
	var paths: PackedStringArray = resolved.paths
	var label := "the whole project"
	if not paths.is_empty():
		label = ("what is open in the editor: " if job.from_editor else "") + ", ".join(paths)
	var text: String = map.render(paths, int(job.max_tokens), label)
	if not (resolved.unknown as PackedStringArray).is_empty():
		text = "Not found in the project: %s.\n%s" % [", ".join(resolved.unknown), text]
	job.result = {"index": index, "text": text}
