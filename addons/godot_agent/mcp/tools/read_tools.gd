@tool
extends RefCounted
## Tools de lectura (grupo read, spec §6): project_info, list_files, scene_tree, get_node y
## editor_state. Devuelven texto compacto pensado para el modelo, no JSON crudo.

const McpTool := preload("../mcp_tool.gd")
const SceneAccess := preload("scene_access.gd")
const PermissionPolicy := preload("../../session/permission_policy.gd")

const LIST_FILES_LIMIT := 2000
const SCENE_TREE_NODE_LIMIT := 600
const DEFAULT_DEPTH := 12


func tools() -> Array:
	var read := PermissionPolicy.GROUP_READ
	return [
		McpTool.create("project_info", read,
			"Datos del proyecto: versión de Godot, nombre, escena principal, autoloads, acciones del input map, plugins activos y renderer.",
			{}, [], _project_info),
		McpTool.create("list_files", read,
			"Lista archivos del proyecto con su tipo de recurso. `pattern` es un glob sobre el nombre (p. ej. \"*.tscn\").",
			{
				"path": {"type": "string", "description": "Carpeta res:// (default res://)"},
				"pattern": {"type": "string", "description": "Glob sobre el nombre del archivo"},
				"recursive": {"type": "boolean", "description": "Incluir subcarpetas (default true)"},
			}, [], _list_files),
		McpTool.create("scene_tree", read,
			"Árbol de una escena: nombre, tipo, script, escena instanciada, grupos y propiedades que difieren del default. Sin `scene`, la escena abierta (con sus cambios sin guardar).",
			{
				"scene": {"type": "string", "description": "Ruta res://…tscn (default: la abierta)"},
				"depth": {"type": "integer", "description": "Profundidad máxima (default %d)" % DEFAULT_DEPTH},
			}, [], _scene_tree),
		McpTool.create("get_node", read,
			"Detalle de un nodo: todas sus propiedades no default, script, grupos, conexiones de señales guardadas e hijos.",
			{
				"scene": {"type": "string", "description": "Ruta res://…tscn (default: la abierta)"},
				"node_path": {"type": "string", "description": "NodePath relativo a la raíz (\".\" = raíz)"},
			}, ["node_path"], _get_node),
		McpTool.create("editor_state", read,
			"Estado del editor: escena actual, escenas abiertas, selección, script abierto con la línea del cursor y si hay un juego corriendo.",
			{}, [], _editor_state),
	]


func _project_info(_args: Dictionary) -> String:
	var lines: PackedStringArray = []
	lines.append("Godot %s" % Engine.get_version_info().string)
	lines.append("Binario del editor (usalo para correr Godot por línea de comandos): %s" % OS.get_executable_path())
	lines.append("Proyecto: %s" % ProjectSettings.get_setting("application/config/name", ""))
	lines.append("Ruta: %s" % ProjectSettings.globalize_path("res://").trim_suffix("/"))
	lines.append("Escena principal: %s" % ProjectSettings.get_setting("application/run/main_scene", "(ninguna)"))
	lines.append("Renderer: %s" % ProjectSettings.get_setting("rendering/renderer/rendering_method", "?"))
	var features: PackedStringArray = ProjectSettings.get_setting("application/config/features", PackedStringArray())
	lines.append("Features: %s" % ", ".join(features))
	var autoloads: PackedStringArray = []
	var actions: PackedStringArray = []
	for property: Dictionary in ProjectSettings.get_property_list():
		var key: String = property.name
		if key.begins_with("autoload/"):
			autoloads.append("%s = %s" % [key.trim_prefix("autoload/"), str(ProjectSettings.get_setting(key)).trim_prefix("*")])
		elif key.begins_with("input/"):
			var action: Dictionary = ProjectSettings.get_setting(key, {})
			var events: PackedStringArray = []
			for event: Variant in action.get("events", []):
				if event is InputEvent:
					events.append((event as InputEvent).as_text())
			actions.append("%s: %s" % [key.trim_prefix("input/"), ", ".join(events) if not events.is_empty() else "(sin eventos)"])
	lines.append("Autoloads:" + (" (ninguno)" if autoloads.is_empty() else ""))
	for autoload: String in autoloads:
		lines.append("  " + autoload)
	lines.append("Input map (acciones del proyecto):" + (" (ninguna)" if actions.is_empty() else ""))
	for action: String in actions:
		lines.append("  " + action)
	var plugins: PackedStringArray = ProjectSettings.get_setting("editor_plugins/enabled", PackedStringArray())
	lines.append("Plugins activos: %s" % (", ".join(plugins) if not plugins.is_empty() else "(ninguno)"))
	return "\n".join(lines)


func _list_files(args: Dictionary) -> Dictionary:
	var path := McpTool.str_arg(args, "path", "res://")
	if not path.begins_with("res://"):
		return McpTool.error("`path` tiene que empezar con res:// (recibí '%s')." % path)
	var fs := EditorInterface.get_resource_filesystem()
	var dir := fs.get_filesystem_path(path.trim_suffix("/") if path != "res://" else path)
	if dir == null:
		return McpTool.error("No existe la carpeta %s (o el editor todavía no la escaneó)." % path)
	var pattern := McpTool.str_arg(args, "pattern")
	var recursive: bool = args.get("recursive", true) != false
	var lines: PackedStringArray = []
	var total := _collect_files(dir, pattern, recursive, lines)
	if total == 0:
		return McpTool.text("Sin archivos en %s%s." % [path, " que coincidan con " + pattern if not pattern.is_empty() else ""])
	var header := "%d archivos en %s" % [total, path]
	if total > lines.size():
		header += " (se muestran %d; filtrá con path o pattern)" % lines.size()
	return McpTool.text(header + "\n" + "\n".join(lines))


func _collect_files(dir: EditorFileSystemDirectory, pattern: String, recursive: bool, out: PackedStringArray) -> int:
	var total := 0
	for i in dir.get_file_count():
		var file := dir.get_file(i)
		if not pattern.is_empty() and not file.matchn(pattern):
			continue
		total += 1
		if out.size() < LIST_FILES_LIMIT:
			out.append("%s  (%s)" % [dir.get_file_path(i), dir.get_file_type(i)])
	if recursive:
		for i in dir.get_subdir_count():
			total += _collect_files(dir.get_subdir(i), pattern, recursive, out)
	return total


func _scene_tree(args: Dictionary) -> Dictionary:
	var resolved := SceneAccess.resolve(McpTool.str_arg(args, "scene"))
	if not resolved.error.is_empty():
		return McpTool.error(resolved.error)
	var depth := maxi(McpTool.int_arg(args, "depth", DEFAULT_DEPTH), 0)
	var lines: PackedStringArray = []
	var counter := {"nodes": 0, "shown": 0}
	_describe_tree(resolved.root, resolved.root, 0, depth, lines, counter)
	resolved.release()
	var header := "%s · %d nodos" % [resolved.path if not resolved.path.is_empty() else "(escena sin guardar)", counter.nodes]
	if counter.shown < counter.nodes:
		header += " (se muestran %d; usá depth o get_node para ver más)" % counter.shown
	return McpTool.text(header + "\n" + "\n".join(lines))


func _describe_tree(root: Node, node: Node, level: int, max_depth: int, lines: PackedStringArray, counter: Dictionary) -> void:
	counter.nodes += 1
	if level <= max_depth and counter.shown < SCENE_TREE_NODE_LIMIT:
		counter.shown += 1
		lines.append("  ".repeat(level) + _node_line(root, node))
	for child: Node in SceneAccess.scene_children(root, node):
		_describe_tree(root, child, level + 1, max_depth, lines, counter)


func _node_line(root: Node, node: Node) -> String:
	var parts: PackedStringArray = ["%s (%s)" % [node.name, node.get_class()]]
	if node != root and not node.scene_file_path.is_empty():
		parts.append("[instancia de %s]" % node.scene_file_path)
	var script := node.get_script() as Script
	if script:
		parts.append("script=%s" % (script.resource_path if not script.resource_path.contains("::") else "<built-in>"))
	var groups := _groups(node)
	if not groups.is_empty():
		parts.append("grupos=[%s]" % ", ".join(groups))
	var props := SceneAccess.changed_properties(node, 60)
	for key: String in props:
		parts.append("%s=%s" % [key, props[key]])
	return " ".join(parts)


func _get_node(args: Dictionary) -> Dictionary:
	var resolved := SceneAccess.resolve(McpTool.str_arg(args, "scene"))
	if not resolved.error.is_empty():
		return McpTool.error(resolved.error)
	var node_path := McpTool.str_arg(args, "node_path")
	var node := SceneAccess.find_node(resolved.root, node_path)
	if node == null:
		var children: PackedStringArray = []
		for child: Node in SceneAccess.scene_children(resolved.root, resolved.root):
			children.append(String(child.name))
		resolved.release()
		return McpTool.error("No existe el nodo '%s'. Los paths son relativos a la raíz; hijos de la raíz: %s. Usá scene_tree para ver el árbol." % [node_path, ", ".join(children)])
	var root := resolved.root
	var lines: PackedStringArray = []
	lines.append("%s (%s) · path %s" % [node.name, node.get_class(), SceneAccess.relative_path(root, node)])
	if node != root and not node.scene_file_path.is_empty():
		lines.append("Instancia de: %s" % node.scene_file_path)
	var script := node.get_script() as Script
	lines.append("Script: %s" % (script.resource_path if script else "(ninguno)"))
	var groups := _groups(node)
	lines.append("Grupos: %s" % (", ".join(groups) if not groups.is_empty() else "(ninguno)"))
	var props := SceneAccess.changed_properties(node, 400)
	lines.append("Propiedades no default:" + (" (ninguna)" if props.is_empty() else ""))
	for key: String in props:
		lines.append("  %s = %s" % [key, props[key]])
	var connections := SceneAccess.persistent_connections(root, node)
	lines.append("Señales conectadas:" + (" (ninguna)" if connections.is_empty() else ""))
	for connection: String in connections:
		lines.append("  " + connection)
	var children: PackedStringArray = []
	for child: Node in SceneAccess.scene_children(root, node):
		children.append("%s (%s)" % [child.name, child.get_class()])
	lines.append("Hijos: %s" % (", ".join(children) if not children.is_empty() else "(ninguno)"))
	resolved.release()
	return McpTool.text("\n".join(lines))


func _editor_state(_args: Dictionary) -> String:
	var lines: PackedStringArray = []
	var edited := EditorInterface.get_edited_scene_root()
	lines.append("Escena actual: %s" % (edited.scene_file_path if edited and not edited.scene_file_path.is_empty() else ("(sin guardar)" if edited else "(ninguna)")))
	lines.append("Escenas abiertas: %s" % ", ".join(EditorInterface.get_open_scenes()))
	var selected: PackedStringArray = []
	if edited:
		for node: Node in EditorInterface.get_selection().get_selected_nodes():
			if node == edited or edited.is_ancestor_of(node):
				selected.append("%s (%s)" % [SceneAccess.relative_path(edited, node), node.get_class()])
	lines.append("Selección: %s" % (", ".join(selected) if not selected.is_empty() else "(nada)"))
	var script_editor := EditorInterface.get_script_editor()
	var script := script_editor.get_current_script() if script_editor else null
	if script:
		var line := 0
		var current := script_editor.get_current_editor()
		if current and current.get_base_editor() is CodeEdit:
			line = (current.get_base_editor() as CodeEdit).get_caret_line() + 1
		lines.append("Script abierto: %s (línea %d)" % [script.resource_path, line])
	else:
		lines.append("Script abierto: (ninguno)")
	var open_scripts: PackedStringArray = []
	if script_editor:
		for open: Script in script_editor.get_open_scripts():
			open_scripts.append(open.resource_path)
	lines.append("Scripts abiertos: %s" % (", ".join(open_scripts) if not open_scripts.is_empty() else "(ninguno)"))
	lines.append("Juego corriendo: %s" % (EditorInterface.get_playing_scene() if EditorInterface.is_playing_scene() else "no"))
	return "\n".join(lines)


static func _groups(node: Node) -> PackedStringArray:
	var result: PackedStringArray = []
	for group: StringName in node.get_groups():
		if not String(group).begins_with("_"):
			result.append(String(group))
	return result
