@tool
extends Node
## Seguir al agente (m11-33, como el «Follow» de Zed): con el botón de la pestaña prendido, el editor
## salta a lo que el agente acaba de editar: el script en la línea del cambio, o la escena con el nodo
## seleccionado. Solo la pestaña activa (lo decide el plugin) y nunca encima del usuario: si tocó el
## editor fuera del dock hace menos de IDLE_S, o está escribiendo en un campo de texto fuera del dock,
## el salto espera a que pare (queda el último). Si el foco estaba en el dock (el composer), vuelve ahí.

const ToolCall := preload("../session/tool_call.gd")
const EditorContext := preload("../ui/editor_context.gd")

## Segundos sin input del usuario fuera del dock antes de saltar.
const IDLE_S := 2.5
const WRITING_KINDS: PackedStringArray = ["edit", "delete", "move"]
## Tools de escena de godot.*: qué argumento nombra el nodo que tocaron.
const NODE_ARG: Dictionary = {
	"set_properties": "node_path", "attach_script": "node_path",
	"connect_signal": "from",
}

## Las pestañas del dock (lo pone el plugin): lo que pasa adentro no cuenta como «el usuario está
## trabajando en el editor».
var dock: Callable = func() -> Control: return null
## Para las pruebas: el tiempo actual en ms.
var now_ms: Callable = func() -> int: return Time.get_ticks_msec()
var _last_outside_input_ms: int = -100000
var _pending: Dictionary = {}


func _ready() -> void:
	set_process_input(true)
	set_process(false)


func _input(event: InputEvent) -> void:
	var outside := false
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		outside = not _in_dock_rect((event as InputEventMouseButton).global_position)
	elif event is InputEventKey and (event as InputEventKey).pressed:
		outside = not _focus_in_dock()
	elif event is InputEventMouseMotion and (event as InputEventMouseMotion).button_mask != 0:
		outside = not _in_dock_rect((event as InputEventMouseMotion).global_position)  # arrastrando en un viewport
	if outside:
		_last_outside_input_ms = now_ms.call()


## Una tool call de la pestaña activa con el seguimiento prendido.
func follow(call: ToolCall) -> void:
	var target := target_of(call)
	if target.is_empty():
		return
	if user_busy():
		_pending = target
		set_process(true)
		return
	go(target)


func _process(_delta: float) -> void:
	if _pending.is_empty():
		set_process(false)
	elif not user_busy():
		var target := _pending
		_pending = {}
		set_process(false)
		go(target)


## Se apagó el seguimiento o cambió la pestaña: lo pendiente ya no va.
func cancel() -> void:
	_pending = {}
	set_process(false)


## El usuario está trabajando fuera del dock: tocó algo hace poco o tiene el foco en un texto.
func user_busy() -> bool:
	if now_ms.call() - _last_outside_input_ms < int(IDLE_S * 1000.0):
		return true
	var focus := _focus_owner()
	return focus != null and not _focus_in_dock() and (focus is TextEdit or focus is LineEdit)


## A dónde saltar por una tool call terminada: {path, line} (un archivo), {scene, node} (un nodo de
## una escena; node "." es la raíz) o {} si no hay nada que mostrar.
static func target_of(call: ToolCall) -> Dictionary:
	if call == null or call.status != ToolCall.STATUS_COMPLETED:
		return {}
	var tool := call.godot_tool_name()
	if not tool.is_empty():
		var args: Variant = call.godot_arguments()
		return _godot_target(tool, args if args is Dictionary else {})
	if not call.kind in WRITING_KINDS or call.kind == "delete":
		return {}
	for location: Variant in call.locations:
		if location is Dictionary and str(location.get("path", "")) != "":
			var line := int(location.get("line", 0))
			if line <= 0:
				line = _first_changed_line(call, str(location.path))
			return {"path": str(location.path), "line": line}
	for diff: Dictionary in call.diffs():
		if str(diff.get("path", "")) != "":
			return {"path": str(diff.path), "line": _first_changed_line(call, str(diff.path))}
	return {}


static func _godot_target(tool: String, args: Dictionary) -> Dictionary:
	var scene := str(args.get("scene", ""))
	var node := ""
	if NODE_ARG.has(tool):
		node = str(args.get(NODE_ARG[tool], ""))
	else:
		match tool:
			"add_node", "instantiate_scene":
				node = _join(str(args.get("parent", ".")), str(args.get("name", "")))
			"add_nodes":
				node = str(args.get("parent", "."))
			"rename_node":
				node = _join(_parent_of(str(args.get("node_path", ""))), str(args.get("new_name", "")))
			"reparent_node":
				node = _join(str(args.get("new_parent", "")), str(args.get("node_path", "")).get_file())
			"remove_node":
				node = _parent_of(str(args.get("node_path", "")))
			"duplicate_node":
				var original := str(args.get("node_path", ""))
				var new_parent := str(args.get("new_parent", ""))
				var new_name := str(args.get("new_name", ""))
				if new_name.is_empty() and new_parent.is_empty():
					node = original
				else:
					node = _join(new_parent if not new_parent.is_empty() else _parent_of(original), new_name if not new_name.is_empty() else original.get_file())
			"delete_file":
				return {}  # ya no está
			"create_scene", "open_scene":
				return {"scene": str(args.get("path", "")), "node": "."} if str(args.get("path", "")).begins_with("res://") else {}
			_:
				for key: String in ["script_path", "path", "to"]:
					var path := str(args.get(key, ""))
					if path.begins_with("res://") and path.get_extension() in ["gd", "cs", "gdshader", "tscn", "tres"]:
						return {"path": path, "line": 0}
				return {}
	if node.is_empty():
		return {}
	return {"scene": scene, "node": node}


static func _join(parent: String, child: String) -> String:
	if child.is_empty():
		return parent
	return child if parent in ["", "."] else parent.trim_suffix("/") + "/" + child


static func _parent_of(path: String) -> String:
	return "." if not path.contains("/") else path.get_base_dir()


## La primera línea (desde 1) que cambia en el diff de `path`; 0 si no se sabe.
static func _first_changed_line(call: ToolCall, path: String) -> int:
	for diff: Dictionary in call.diffs():
		if str(diff.get("path", "")) != path:
			continue
		var old_lines := str(diff.get("oldText", "")).split("\n")
		var new_lines := str(diff.get("newText", "")).split("\n")
		for i in new_lines.size():
			if i >= old_lines.size() or old_lines[i] != new_lines[i]:
				return i + 1
		return new_lines.size()
	return 0


## Salta: abre el archivo en la línea o la escena con el nodo seleccionado. El foco vuelve al dock si
## estaba ahí.
func go(target: Dictionary) -> void:
	var refocus := _focus_owner() if _focus_in_dock() else null
	if target.has("path"):
		var path := str(target.path)
		# Lo que el agente escribe fuera del proyecto (otra carpeta, una copia aparte) no se abre.
		if not EditorContext.to_res_path(path).is_empty():
			EditorContext.open_location(path, int(target.get("line", 0)))
	else:
		_select_node(str(target.get("scene", "")), str(target.node))
	if refocus and is_instance_valid(refocus):
		refocus.grab_focus.call_deferred()


static func _select_node(scene: String, node_path: String) -> void:
	var root := EditorInterface.get_edited_scene_root()
	if scene.begins_with("res://") and (root == null or root.scene_file_path != scene):
		if not FileAccess.file_exists(scene):
			return
		EditorInterface.open_scene_from_path(scene)
		root = EditorInterface.get_edited_scene_root()
	if root == null:
		return
	var node := root if node_path in ["", "."] else root.get_node_or_null(NodePath(node_path))
	if node == null:
		return
	var selection := EditorInterface.get_selection()
	selection.clear()
	selection.add_node(node)
	EditorInterface.edit_node(node)
	if node is Node3D:
		EditorInterface.set_main_screen_editor("3D")
	elif node is CanvasItem:
		EditorInterface.set_main_screen_editor("2D")


func _focus_owner() -> Control:
	return get_viewport().gui_get_focus_owner() if is_inside_tree() else null


func _focus_in_dock() -> bool:
	var focus := _focus_owner()
	var root: Control = dock.call()
	return focus != null and root != null and (root == focus or root.is_ancestor_of(focus))


func _in_dock_rect(point: Vector2) -> bool:
	var root: Control = dock.call()
	return root != null and root.is_visible_in_tree() and root.get_global_rect().has_point(point)
