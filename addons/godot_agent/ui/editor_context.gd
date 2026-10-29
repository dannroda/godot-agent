@tool
extends RefCounted
## Lo que la UI necesita leer del editor para armar el contexto de un prompt: escena abierta,
## selección, menciones (`@`), captura del viewport y saltar a un archivo/línea.

const MAX_IMAGE_SIDE := 1280
const MENTION_FILE_LIMIT := 3000
const MENTION_EXTENSIONS: PackedStringArray = ["gd", "cs", "tscn", "tres", "gdshader", "cfg", "json", "md", "txt", "csv"]


static func project_path() -> String:
	return ProjectSettings.globalize_path("res://").trim_suffix("/")


static func file_uri(res_path: String) -> String:
	return "file://" + ProjectSettings.globalize_path(res_path)


static func scene_root() -> Node:
	return EditorInterface.get_edited_scene_root()


static func current_scene_path() -> String:
	var root := scene_root()
	return root.scene_file_path if root else ""


## Nodos seleccionados como rutas relativas a la raíz de la escena.
static func selected_node_paths() -> PackedStringArray:
	var paths: PackedStringArray = []
	var root := scene_root()
	if root == null:
		return paths
	for node: Node in EditorInterface.get_selection().get_selected_nodes():
		if node == root or root.is_ancestor_of(node):
			paths.append(String(root.get_path_to(node)))
	return paths


static func selection_description() -> String:
	var root := scene_root()
	var parts: PackedStringArray = []
	for node: Node in EditorInterface.get_selection().get_selected_nodes():
		if root and (node == root or root.is_ancestor_of(node)):
			parts.append("%s (%s)" % [String(root.get_path_to(node)), node.get_class()])
	return ", ".join(parts)


## Opciones de `@`: nodos de la escena abierta y archivos del proyecto.
static func mention_options() -> Array[Dictionary]:
	var options: Array[Dictionary] = []
	var root := scene_root()
	if root:
		_collect_nodes(root, root, options)
	var files: PackedStringArray = []
	_collect_files(EditorInterface.get_resource_filesystem().get_filesystem(), files)
	for path: String in files:
		options.append({"label": path, "insert": path})
	return options


static func _collect_nodes(root: Node, node: Node, out: Array[Dictionary]) -> void:
	if out.size() > 500:
		return
	var path := "." if node == root else String(root.get_path_to(node))
	out.append({"label": "%s  (%s)" % [path, node.get_class()], "insert": path})
	for child: Node in node.get_children():
		if child.owner == root:
			_collect_nodes(root, child, out)


static func _collect_files(dir: EditorFileSystemDirectory, out: PackedStringArray) -> void:
	if dir == null or out.size() >= MENTION_FILE_LIMIT:
		return
	if dir.get_path().begins_with("res://addons/godot_agent"):
		return
	for i in dir.get_file_count():
		var path := dir.get_file_path(i)
		if path.get_extension() in MENTION_EXTENSIONS:
			out.append(path)
	for i in dir.get_subdir_count():
		_collect_files(dir.get_subdir(i), out)


## Captura del viewport (2D o 3D según la escena), o null.
static func capture_scene_viewport() -> Image:
	return capture_viewport(_prefers_3d())


static func capture_viewport(three_d: bool) -> Image:
	var viewport: SubViewport = EditorInterface.get_editor_viewport_3d(0) if three_d else EditorInterface.get_editor_viewport_2d()
	if viewport == null:
		return null
	var image := viewport.get_texture().get_image()
	if image == null or image.is_empty():
		return null
	return fit_image(image, MAX_IMAGE_SIDE)


static func fit_image(image: Image, max_side: int) -> Image:
	var longest := maxi(image.get_width(), image.get_height())
	if longest > max_side:
		var factor := float(max_side) / float(longest)
		image.resize(maxi(1, int(image.get_width() * factor)), maxi(1, int(image.get_height() * factor)), Image.INTERPOLATE_LANCZOS)
	return image


static func _prefers_3d() -> bool:
	return scene_root() is Node3D


## Abre un archivo del proyecto (ruta absoluta o res://) en el Script Editor o como escena.
static func open_location(path: String, line: int = 0) -> bool:
	var res_path := to_res_path(path)
	if res_path.is_empty() or not FileAccess.file_exists(res_path):
		return false
	if res_path.get_extension() in ["tscn", "scn"]:
		EditorInterface.open_scene_from_path(res_path)
		return true
	if not ResourceLoader.exists(res_path):  # .md, .txt…: load() escribiría un error en Output
		return false
	var resource := load(res_path)
	if resource is Script:
		EditorInterface.edit_script(resource, maxi(line, 1) if line > 0 else -1)
		if not opens_externally(res_path):
			EditorInterface.set_main_screen_editor("Script")
		return true
	if resource:
		EditorInterface.edit_resource(resource)
		return true
	return false


## Si `edit_script` lo abre en un editor externo (VS Code, Rider…) en lugar del Script Editor: el
## externo general, o el de C# (`dotnet/editor/external_editor`, 0 = ninguno) para los .cs (m14-07).
static func opens_externally(res_path: String) -> bool:
	var settings := EditorInterface.get_editor_settings()
	if settings.get_setting("text_editor/external/use_external_editor"):
		return true
	return res_path.get_extension() == "cs" and settings.has_setting("dotnet/editor/external_editor") and int(settings.get_setting("dotnet/editor/external_editor")) != 0


## Ruta `res://` para una ruta absoluta dentro del proyecto, o "" si queda afuera.
static func to_res_path(path: String) -> String:
	if path.begins_with("res://"):
		return path
	var root := ProjectSettings.globalize_path("res://")
	var normalized := path.simplify_path()
	if normalized.begins_with(root):
		return "res://" + normalized.substr(root.length())
	if (normalized + "/") == root:
		return "res://"
	return ""
