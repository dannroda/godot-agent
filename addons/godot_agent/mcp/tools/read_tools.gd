@tool
extends RefCounted
## Tools de lectura (grupo read, spec §6): project_info, list_files, find_in_files, scene_tree,
## get_node, editor_state y dependencies. Devuelven texto compacto pensado para el modelo, no JSON crudo.

const McpTool := preload("../mcp_tool.gd")
const UntrustedText := preload("../untrusted_text.gd")
const SceneAccess := preload("scene_access.gd")
const SceneEditTools := preload("scene_edit_tools.gd")
const PermissionPolicy := preload("../../session/permission_policy.gd")
const NativeInstall := preload("../../core/native_install.gd")
const SupervisorState := preload("../../supervisor/supervisor_state.gd")
const ImageHeader := preload("image_header.gd")
const FileTools := preload("file_tools.gd")

const LIST_FILES_LIMIT := 2000
const IMAGE_EXTENSIONS: PackedStringArray = ["png", "jpg", "jpeg", "webp"]
## find_in_files (m11-74): como «Buscar en archivos» del editor.
const FIND_SETTING := "editor/script/search_in_file_extensions"
const FIND_DEFAULT_EXTENSIONS: PackedStringArray = ["gd", "gdshader", "gdshaderinc", "cs", "tscn", "tres", "cfg", "json", "md", "txt"]
const FIND_MAX_MATCHES := 200
const FIND_LINE_CHARS := 240
const FIND_MAX_FILE_BYTES := 4 * 1024 * 1024
const SCENE_TREE_NODE_LIMIT := 600
const DEFAULT_DEPTH := 12
## dependencies (m11-78): hasta 3 niveles, con tope de archivos y de tiempo (el reverso lee el texto de
## todo el proyecto, una vez).
const DEPENDENCY_MAX_DEPTH := 3
const DEPENDENCY_LIMIT := 200
const DEPENDENCY_TIMEOUT_MS := 5000
## Extensiones de las que get_dependencies no da nada útil: se leen sus rutas del texto.
const NAMED_PATH_EXTENSIONS: PackedStringArray = ["gd", "gdshader", "gdshaderinc", "cs"]
## editor_state (m11-77): de dónde sale un sub-recurso del Inspector, sin recorrer de más.
const OWNER_SEARCH_DEPTH := 3
const OWNER_SEARCH_NODES := 2000
const OWNER_SEARCH_OBJECTS := 5000

## Carpeta de estado del supervisor (donde install_extension deja lo preparado); "" = la del
## proyecto abierto. Los tests la cambian.
var supervisor_state_dir: String = ""


func tools() -> Array:
	var read := PermissionPolicy.GROUP_READ
	return [
		McpTool.create("project_info", read,
			"Project data: Godot version, name, main scene, autoloads, input map actions, enabled plugins and renderer.",
			{}, [], _project_info),
		McpTool.create("list_files", read,
			"Lists project files from the editor's filesystem with their resource type, and width x height for PNG, JPEG and WebP images. Use it instead of ls, find or scripts. `pattern` is a glob on the file name (e.g. \"*.tscn\").",
			{
				"path": {"type": "string", "description": "res:// folder (default res://)"},
				"pattern": {"type": "string", "description": "Glob on the file name"},
				"recursive": {"type": "boolean", "description": "Include subfolders (default true)"},
			}, [], _list_files),
		McpTool.enveloped(McpTool.create("find_in_files", read,
			"Searches the text of the project's files, like the editor's Find in Files: the files the editor knows (no .godot/ nor folders with .gdignore) with the extensions of Godot's text files (.gd, .tscn, .tres, .gdshader, .cs, .cfg, .json, .md…) plus the ones the project adds to Find in Files. Returns path:line: text. Use it instead of grep in the shell.",
			{
				"pattern": {"type": "string", "description": "Text to find (or a regular expression with regex=true)"},
				"regex": {"type": "boolean", "description": "pattern is a regular expression (default false)"},
				"case_sensitive": {"type": "boolean", "description": "Default false"},
				"path": {"type": "string", "description": "res:// folder to search in (default res://)"},
				"extensions": {"type": "array", "items": {"type": "string"}, "description": "Only these extensions, without the dot (e.g. [\"tscn\"])"},
			}, ["pattern"], _find_in_files), McpTool.ENVELOPE_PARTS),
		McpTool.enveloped(McpTool.create("scene_tree", read,
			"Tree of a scene: name, type, script, instanced scene, groups and properties that differ from the default. Without `scene`, the open scene (with its unsaved changes).",
			{
				"scene": {"type": "string", "description": "res://…tscn path (default: the open one)"},
				"depth": {"type": "integer", "description": "Maximum depth (default %d)" % DEFAULT_DEPTH},
			}, [], _scene_tree), McpTool.ENVELOPE_ALL),
		McpTool.enveloped(McpTool.create("get_node", read,
			"Details of a node: all its non-default properties, script, groups, saved signal connections and children.",
			{
				"scene": {"type": "string", "description": "res://…tscn path (default: the open one)"},
				"node_path": {"type": "string", "description": "NodePath relative to the root (\".\" = root)"},
			}, ["node_path"], _get_node), McpTool.ENVELOPE_ALL),
		# Nombres de nodos y rutas del proyecto, como scene_tree: en un sobre (m11-45).
		McpTool.enveloped(McpTool.create("editor_state", read,
			"Editor state: current scene, open scenes, selection, what the Inspector shows (a node, a resource file, or a sub-resource and the property of the node or resource it comes from), open script with the caret line, and whether a game is running.",
			{}, [], _editor_state), McpTool.ENVELOPE_ALL),
		McpTool.create("dependencies", read,
			"What a project file uses (forward: the scenes, scripts, textures… it loads, including a script's preload/load paths) or who uses it (reverse: the files that name it by res:// path, uid or a relative preload/load/extends, like the check delete_file does), up to `depth` levels. Use it instead of grep before changing or deleting a file.",
			{
				"path": {"type": "string", "description": "res:// file (reverse also accepts a folder)"},
				"direction": {"type": "string", "enum": ["forward", "reverse"], "description": "forward = what it uses (default), reverse = who uses it"},
				"depth": {"type": "integer", "description": "Levels, 1-%d (default 1)" % DEPENDENCY_MAX_DEPTH},
			}, ["path"], _dependencies),
	]


func _project_info(_args: Dictionary) -> String:
	var lines: PackedStringArray = []
	lines.append("Godot %s" % Engine.get_version_info().string)
	lines.append("Editor binary (use it to run Godot from the command line): %s" % OS.get_executable_path())
	lines.append("Project: %s" % ProjectSettings.get_setting("application/config/name", ""))
	lines.append("Path: %s" % ProjectSettings.globalize_path("res://").trim_suffix("/"))
	lines.append("Main scene: %s" % ProjectSettings.get_setting("application/run/main_scene", "(none)"))
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
			actions.append("%s: %s" % [key.trim_prefix("input/"), ", ".join(events) if not events.is_empty() else "(no events)"])
	lines.append("Autoloads:" + (" (none)" if autoloads.is_empty() else ""))
	for autoload: String in autoloads:
		lines.append("  " + autoload)
	lines.append("Input map (project actions):" + (" (none)" if actions.is_empty() else ""))
	for action: String in actions:
		lines.append("  " + action)
	var plugins: PackedStringArray = ProjectSettings.get_setting("editor_plugins/enabled", PackedStringArray())
	lines.append("Enabled plugins: %s" % (", ".join(plugins) if not plugins.is_empty() else "(none)"))
	var staged := NativeInstall.pending_line(supervisor_state_dir if not supervisor_state_dir.is_empty() else SupervisorState.state_dir(ProjectSettings.globalize_path("res://")))
	if not staged.is_empty():
		lines.append(staged)
	return "\n".join(lines)


func _list_files(args: Dictionary) -> Dictionary:
	var path := McpTool.str_arg(args, "path", "res://")
	if not path.begins_with("res://"):
		return McpTool.error("`path` must start with res:// (got '%s')." % path)
	var fs := EditorInterface.get_resource_filesystem()
	var dir := fs.get_filesystem_path(path.trim_suffix("/") if path != "res://" else path)
	if dir == null:
		return McpTool.error("The folder %s does not exist (or the editor has not scanned it yet)." % path)
	var pattern := McpTool.str_arg(args, "pattern")
	var recursive: bool = args.get("recursive", true) != false
	var lines: PackedStringArray = []
	var total := _collect_files(dir, pattern, recursive, lines)
	if total == 0:
		return McpTool.text("No files in %s%s." % [path, " matching " + pattern if not pattern.is_empty() else ""])
	var header := "%d files in %s" % [total, path]
	if total > lines.size():
		header += " (showing %d; filter with path or pattern)" % lines.size()
	return McpTool.text(header + "\n" + "\n".join(lines))


func _collect_files(dir: EditorFileSystemDirectory, pattern: String, recursive: bool, out: PackedStringArray) -> int:
	var total := 0
	for i in dir.get_file_count():
		var file := dir.get_file(i)
		if not pattern.is_empty() and not file.matchn(pattern):
			continue
		total += 1
		if out.size() < LIST_FILES_LIMIT:
			var path := dir.get_file_path(i)
			var size := ImageHeader.size_of(path) if path.get_extension().to_lower() in IMAGE_EXTENSIONS else Vector2i.ZERO
			out.append("%s  (%s%s)" % [path, dir.get_file_type(i), ", %dx%d" % [size.x, size.y] if size != Vector2i.ZERO else ""])
	if recursive:
		for i in dir.get_subdir_count():
			total += _collect_files(dir.get_subdir(i), pattern, recursive, out)
	return total


func _find_in_files(args: Dictionary) -> Dictionary:
	var pattern := McpTool.str_arg(args, "pattern")
	if pattern.is_empty():
		return McpTool.error("`pattern` is empty.")
	var path := McpTool.str_arg(args, "path", "res://")
	if not path.begins_with("res://"):
		return McpTool.error("`path` must start with res:// (got '%s')." % path)
	var dir := EditorInterface.get_resource_filesystem().get_filesystem_path(path.trim_suffix("/") if path != "res://" else path)
	if dir == null:
		return McpTool.error("The folder %s does not exist (or the editor has not scanned it yet)." % path)
	var case_sensitive: bool = args.get("case_sensitive", false) == true
	var regex: RegEx = null
	if args.get("regex", false) == true:
		regex = RegEx.create_from_string(("" if case_sensitive else "(?i)") + pattern)
		if regex == null or not regex.is_valid():
			return McpTool.error("`pattern` is not a valid regular expression.")
	var extensions := find_extensions(args.get("extensions"))
	var files: PackedStringArray = []
	_collect_searchable(dir, extensions, files)
	var matches: PackedStringArray = []
	var total := 0
	var needle := pattern if case_sensitive else pattern.to_lower()
	for file_path: String in files:
		var file := FileAccess.open(file_path, FileAccess.READ)
		if file == null or file.get_length() > FIND_MAX_FILE_BYTES:
			continue
		var number := 0
		while not file.eof_reached():
			var line := file.get_line()
			number += 1
			var hit := regex.search(line) != null if regex else (line if case_sensitive else line.to_lower()).contains(needle)
			if not hit:
				continue
			total += 1
			if matches.size() < FIND_MAX_MATCHES:
				matches.append("%s:%d: %s" % [file_path, number, line.strip_edges().left(FIND_LINE_CHARS)])
	if total == 0:
		return McpTool.text("No matches for \"%s\" in %d files of %s." % [pattern, files.size(), path])
	var header := "%d matches in %d files searched (%s)" % [total, files.size(), ", ".join(extensions)]
	if total > matches.size():
		header += "; showing the first %d: narrow it with path or extensions" % matches.size()
	return McpTool.text(header + "\n" + UntrustedText.wrap("\n".join(matches)))


## Las extensiones a buscar, sin el punto: las pedidas, o las del proyecto (las de Buscar en archivos,
## que en 4.7 son solo gd y gdshader) más las de texto de Godot: las escenas y recursos importan.
static func find_extensions(requested: Variant) -> PackedStringArray:
	var result: PackedStringArray = []
	var source: Array = []
	if requested is Array and not requested.is_empty():
		source = requested
	else:
		source = Array(ProjectSettings.get_setting(FIND_SETTING, PackedStringArray())) + Array(FIND_DEFAULT_EXTENSIONS)
	for item: Variant in source:
		var extension := str(item).strip_edges().trim_prefix("*").trim_prefix(".").to_lower()
		if not extension.is_empty() and not extension in result:
			result.append(extension)
	return result if not result.is_empty() else FIND_DEFAULT_EXTENSIONS


func _collect_searchable(dir: EditorFileSystemDirectory, extensions: PackedStringArray, out: PackedStringArray) -> void:
	for i in dir.get_file_count():
		if dir.get_file(i).get_extension().to_lower() in extensions:
			out.append(dir.get_file_path(i))
	for i in dir.get_subdir_count():
		_collect_searchable(dir.get_subdir(i), extensions, out)


func _scene_tree(args: Dictionary) -> Dictionary:
	var resolved := SceneAccess.resolve(McpTool.str_arg(args, "scene"))
	if not resolved.error.is_empty():
		return McpTool.error(resolved.error)
	var depth := maxi(McpTool.int_arg(args, "depth", DEFAULT_DEPTH), 0)
	var lines: PackedStringArray = []
	var counter := {"nodes": 0, "shown": 0}
	_describe_tree(resolved.root, resolved.root, 0, depth, lines, counter)
	resolved.release()
	var header := "%s · %d nodes" % [resolved.path if not resolved.path.is_empty() else "(unsaved scene)", counter.nodes]
	if counter.shown < counter.nodes:
		header += " (showing %d; use depth or get_node to see more)" % counter.shown
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
		parts.append("[instance of %s]" % node.scene_file_path)
	var script := node.get_script() as Script
	if script:
		parts.append("script=%s" % (script.resource_path if not script.resource_path.contains("::") else "<built-in>"))
	var groups := _groups(node)
	if not groups.is_empty():
		parts.append("groups=[%s]" % ", ".join(groups))
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
		# Los nombres de los hijos son texto de la escena: los errores no van en sobre entero (m11-45).
		return McpTool.error("There is no node '%s'. Paths are relative to the root; children of the root: %s. Use scene_tree to see the tree." % [node_path, UntrustedText.wrap(", ".join(children))])
	var root := resolved.root
	var lines: PackedStringArray = []
	lines.append("%s (%s) · path %s" % [node.name, node.get_class(), SceneAccess.relative_path(root, node)])
	if node != root and not node.scene_file_path.is_empty():
		lines.append("Instance of: %s" % node.scene_file_path)
	var script := node.get_script() as Script
	lines.append("Script: %s" % (script.resource_path if script else "(none)"))
	var groups := _groups(node)
	lines.append("Groups: %s" % (", ".join(groups) if not groups.is_empty() else "(none)"))
	var props := SceneAccess.changed_properties(node, 400)
	lines.append("Non-default properties:" + (" (none)" if props.is_empty() else ""))
	for key: String in props:
		lines.append("  %s = %s" % [key, props[key]])
	var buttons := SceneEditTools.tool_buttons(node)
	if not buttons.is_empty():
		var names: PackedStringArray = []
		for button: Dictionary in buttons:
			names.append("%s («%s»)" % [button.name, button.text])
		lines.append("Tool buttons (press_tool_button): %s" % ", ".join(names))
	var connections := SceneAccess.persistent_connections(root, node)
	lines.append("Connected signals:" + (" (none)" if connections.is_empty() else ""))
	for connection: String in connections:
		lines.append("  " + connection)
	var children: PackedStringArray = []
	for child: Node in SceneAccess.scene_children(root, node):
		children.append("%s (%s)" % [child.name, child.get_class()])
	lines.append("Children: %s" % (", ".join(children) if not children.is_empty() else "(none)"))
	resolved.release()
	return McpTool.text("\n".join(lines))


func _editor_state(_args: Dictionary) -> String:
	var lines: PackedStringArray = []
	var edited := EditorInterface.get_edited_scene_root()
	lines.append("Current scene: %s" % (edited.scene_file_path if edited and not edited.scene_file_path.is_empty() else ("(unsaved)" if edited else "(none)")))
	lines.append("Open scenes: %s" % ", ".join(EditorInterface.get_open_scenes()))
	var selected: PackedStringArray = []
	if edited:
		for node: Node in EditorInterface.get_selection().get_selected_nodes():
			if node == edited or edited.is_ancestor_of(node):
				selected.append("%s (%s)" % [SceneAccess.relative_path(edited, node), node.get_class()])
	lines.append("Selection: %s" % (", ".join(selected) if not selected.is_empty() else "(nothing)"))
	var inspector := EditorInterface.get_inspector()
	var inspected := inspector.get_edited_object() if inspector else null
	var host: Resource = null
	var nodes: Array[Node] = []
	# Solo un sub-recurso o un recurso sin archivo busca de dónde sale: la selección primero.
	if inspected is Resource and ((inspected as Resource).resource_path.is_empty() or (inspected as Resource).resource_path.contains("::")):
		var host_path := (inspected as Resource).resource_path.get_slice("::", 0)
		if not host_path.is_empty() and ResourceLoader.has_cached(host_path):
			host = ResourceLoader.get_cached_ref(host_path)
		if edited:
			var listed := {}
			for node: Node in EditorInterface.get_selection().get_selected_nodes():
				if node == edited or edited.is_ancestor_of(node):
					nodes.append(node)
					listed[node] = true
			_scene_nodes(edited, edited, nodes, listed)
	lines.append(inspector_line(inspected, edited, nodes, host))
	var script_editor := EditorInterface.get_script_editor()
	var script := script_editor.get_current_script() if script_editor else null
	if script:
		var line := 0
		var current := script_editor.get_current_editor()
		if current and current.get_base_editor() is CodeEdit:
			line = (current.get_base_editor() as CodeEdit).get_caret_line() + 1
		lines.append("Open script: %s (line %d)" % [script.resource_path, line])
	else:
		lines.append("Open script: (none)")
	var open_scripts: PackedStringArray = []
	if script_editor:
		for open: Script in script_editor.get_open_scripts():
			open_scripts.append(open.resource_path)
	lines.append("Open scripts: %s" % (", ".join(open_scripts) if not open_scripts.is_empty() else "(none)"))
	lines.append("Game running: %s" % (EditorInterface.get_playing_scene() if EditorInterface.is_playing_scene() else "no"))
	return "\n".join(lines)


static func _groups(node: Node) -> PackedStringArray:
	var result: PackedStringArray = []
	for group: StringName in node.get_groups():
		if not String(group).begins_with("_"):
			result.append(String(group))
	return result


func _scene_nodes(root: Node, node: Node, out: Array[Node], listed: Dictionary) -> void:
	if out.size() >= OWNER_SEARCH_NODES:
		return
	if not listed.has(node):
		out.append(node)
		listed[node] = true
	for child: Node in SceneAccess.scene_children(root, node):
		_scene_nodes(root, child, out, listed)


## La línea «Inspector:» de editor_state (m11-77): qué objeto muestra el Inspector. Un nodo, por su
## ruta en la escena; un recurso con archivo, por su ruta; un sub-recurso (un StyleBox de un tema, el
## material de un mesh) o un recurso sin guardar, con el recurso o nodo y la propiedad de donde sale,
## buscando en `nodes` (la selección primero) y en `host`, el recurso que lo guarda. Sin valores: para
## eso están get_node y get_resource. Idea de Orca (editor_context.gd, inspector_target; MIT).
static func inspector_line(target: Object, scene_root: Node, nodes: Array[Node], host: Resource) -> String:
	if not is_instance_valid(target):
		return "Inspector: (nothing)"
	var type := _type_name(target)
	if target.get_class() == "MultiNodeEdit":
		return "Inspector: several nodes at once (the Selection)"
	if target is Node:
		var node := target as Node
		if scene_root and (node == scene_root or scene_root.is_ancestor_of(node)):
			return "Inspector: node %s (%s)" % [SceneAccess.relative_path(scene_root, node), type]
		return "Inspector: a %s node outside the current scene" % type
	if not target is Resource:
		return "Inspector: %s" % type
	var resource := target as Resource
	var path := resource.resource_path
	if not path.is_empty() and not path.contains("::"):
		return "Inspector: resource %s (%s)" % [path, type]
	var line := "Inspector: %s, %s" % [type, "a sub-resource saved inside %s" % path.get_slice("::", 0) if not path.is_empty() else "not saved to its own file"]
	var owner := resource_owner(resource, scene_root, nodes, host)
	if not owner.is_empty():
		line += " · comes from %s" % owner
	return line


## Dónde está `target`: «node Player/Mesh, property mesh → material» o «res://ui/theme.tres, property
## Button/styles/normal». Busca hasta OWNER_SEARCH_DEPTH recursos de profundidad en las propiedades
## guardadas o del Inspector; "" si no aparece.
static func resource_owner(target: Resource, scene_root: Node, nodes: Array[Node], host: Resource) -> String:
	var visited := {}
	if host and host != target:
		var chain := _find_in_properties(host, target, OWNER_SEARCH_DEPTH, visited)
		if not chain.is_empty():
			return "%s, property %s" % [host.resource_path, " → ".join(chain)]
	for node: Node in nodes:
		if not is_instance_valid(node):
			continue
		var chain := _find_in_properties(node, target, OWNER_SEARCH_DEPTH, visited)
		if not chain.is_empty():
			var where := SceneAccess.relative_path(scene_root, node) if scene_root and (node == scene_root or scene_root.is_ancestor_of(node)) else String(node.name)
			return "node %s (%s), property %s" % [where, node.get_class(), " → ".join(chain)]
	return ""


## Las propiedades de `object` (y de sus recursos, hasta `depth`) que llevan a `target`; [] si ninguna.
static func _find_in_properties(object: Object, target: Resource, depth: int, visited: Dictionary) -> PackedStringArray:
	if depth <= 0 or visited.size() >= OWNER_SEARCH_OBJECTS or visited.has(object.get_instance_id()):
		return PackedStringArray()
	visited[object.get_instance_id()] = true
	var nested: Array = []
	for property: Dictionary in object.get_property_list():
		if property.type != TYPE_OBJECT or not (property.usage & (PROPERTY_USAGE_STORAGE | PROPERTY_USAGE_EDITOR)):
			continue
		var value: Variant = object.get(property.name)
		if not value is Resource:
			continue
		if value == target:
			return PackedStringArray([property.name])
		nested.append([property.name, value])
	for pair: Array in nested:
		var chain := _find_in_properties(pair[1], target, depth - 1, visited)
		if not chain.is_empty():
			chain.insert(0, pair[0])
			return chain
	return PackedStringArray()


## Tipo para el modelo: el class_name del script si tiene, si no la clase nativa.
static func _type_name(object: Object) -> String:
	var script := object.get_script() as Script
	var global := String(script.get_global_name()) if script else ""
	return "%s (%s)" % [global, object.get_class()] if not global.is_empty() else object.get_class()


func _dependencies(args: Dictionary) -> Dictionary:
	var path := McpTool.str_arg(args, "path").strip_edges().simplify_path().trim_suffix("/")
	if not path.begins_with("res://") or path == "res:":
		return McpTool.error("`path` must be a res:// file of the project (got '%s')." % path)
	var direction := McpTool.str_arg(args, "direction", "forward")
	if not direction in ["forward", "reverse"]:
		return McpTool.error("`direction` is forward (what it uses) or reverse (who uses it), not '%s'." % direction)
	var is_dir := DirAccess.dir_exists_absolute(path)
	if not is_dir and not FileAccess.file_exists(path):
		return McpTool.error("%s does not exist." % path)
	if is_dir and direction == "forward":
		return McpTool.error("forward needs a file: %s is a folder (reverse accepts folders)." % path)
	var depth := clampi(McpTool.int_arg(args, "depth", 1), 1, DEPENDENCY_MAX_DEPTH)
	return McpTool.text(dependency_report(path, direction == "reverse", depth))


## El informe de dependencies: un árbol desde `path`, hasta `depth` niveles, cada archivo una vez (si
## vuelve a aparecer, «(listed above)» y no se abre de nuevo). Sin el editor: los tests lo llaman.
static func dependency_report(path: String, reverse: bool, depth: int) -> String:
	var graph := dependency_graph(path, reverse, depth)
	var children: Dictionary = graph.children
	var lines: PackedStringArray = []
	var shown := {path: true}
	_dependency_lines(path, children, 0, shown, lines)
	var count := shown.size() - 1
	var header := "%s · %s, depth %d: %d file%s" % [path, "who uses it (reverse)" if reverse else "what it uses (forward)", depth, count, "" if count == 1 else "s"]
	if count == 0:
		header += ". " + ("Nothing in the project names it." if reverse else "It uses no other file.")
	if not graph.stopped.is_empty():
		header += " (stopped early: %s)" % graph.stopped
	return header + ("\n" + "\n".join(lines) if not lines.is_empty() else "")


static func _dependency_lines(path: String, children: Dictionary, level: int, shown: Dictionary, lines: PackedStringArray) -> void:
	for child: Dictionary in children.get(path, []):
		var child_path: String = child.path
		var text := "  ".repeat(level) + "- " + child_path
		if not child.lines.is_empty():
			text += " (line %s)" % ", ".join(child.lines)
		if not child_path.begins_with("res://") or not (FileAccess.file_exists(child_path) or DirAccess.dir_exists_absolute(child_path)):
			text += " (missing)"
		elif shown.has(child_path):
			text += " (listed above)"
			lines.append(text)
			continue
		shown[child_path] = true
		lines.append(text)
		_dependency_lines(child_path, children, level + 1, shown, lines)


## {children: {path: [{path, lines}]}, stopped: ""}: lo que usa (o quién usa) cada archivo, a lo ancho,
## hasta `depth` niveles, DEPENDENCY_LIMIT archivos o DEPENDENCY_TIMEOUT_MS.
static func dependency_graph(path: String, reverse: bool, depth: int) -> Dictionary:
	var children := {}
	var seen := {path: true}
	var frontier: PackedStringArray = [path]
	var cache := {}
	var deadline := Time.get_ticks_msec() + DEPENDENCY_TIMEOUT_MS
	var stopped := ""
	for level in depth:
		var next: PackedStringArray = []
		for current: String in frontier:
			if seen.size() > DEPENDENCY_LIMIT:
				stopped = "more than %d files" % DEPENDENCY_LIMIT
				break
			if Time.get_ticks_msec() > deadline:
				stopped = "took more than %d s" % (DEPENDENCY_TIMEOUT_MS / 1000)
				break
			var found: Array[Dictionary] = _used_by(current, cache) if reverse else _uses(current, cache)
			children[current] = found
			for child: Dictionary in found:
				if not seen.has(child.path) and FileAccess.file_exists(child.path):
					seen[child.path] = true
					next.append(child.path)
		if not stopped.is_empty():
			break
		frontier = next
	return {"children": children, "stopped": stopped}


## Quién nombra `path`: el mismo escaneo con el que delete_file se niega (FileTools.references_to).
static func _used_by(path: String, cache: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var users := FileTools.references_to(path, cache)
	var sorted: Array = users.keys()
	sorted.sort()
	for user: String in sorted:
		result.append({"path": user, "lines": users[user]})
	return result


## Lo que usa `path`: ResourceLoader.get_dependencies (escenas, recursos) y, en scripts y shaders,
## las rutas de su texto (a un .gd get_dependencies le da []).
static func _uses(path: String, cache: Dictionary) -> Array[Dictionary]:
	var paths: PackedStringArray = []
	for descriptor: String in ResourceLoader.get_dependencies(path):
		var dependency := _dependency_path(descriptor)
		if not dependency.is_empty() and dependency != path and not dependency in paths:
			paths.append(dependency)
	if path.get_extension() in NAMED_PATH_EXTENSIONS:
		for named: String in FileTools.named_paths(path, FileTools._cached_text(cache, path)):
			if not named in paths:
				paths.append(named)
	paths.sort()
	var result: Array[Dictionary] = []
	for dependency: String in paths:
		result.append({"path": dependency, "lines": PackedStringArray()})
	return result


## «uid://…::Tipo::res://…» de get_dependencies → la ruta: por el uid si se resuelve (la ruta escrita
## puede ser vieja), si no la res://. Como _normalize_dependency_descriptor de Orca
## (dependency_inspector.gd, MIT).
static func _dependency_path(descriptor: String) -> String:
	var fallback := ""
	for part: String in descriptor.split("::", false):
		if part.begins_with("uid://"):
			var id := ResourceUID.text_to_id(part)
			if id != ResourceUID.INVALID_ID and ResourceUID.has_id(id):
				return ResourceUID.get_id_path(id)
		elif part.begins_with("res://") and fallback.is_empty():
			fallback = part
	return fallback
