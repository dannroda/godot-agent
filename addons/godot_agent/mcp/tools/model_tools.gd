@tool
extends RefCounted
## import_model (m11-85): trae un modelo exportado (de Blender u otro programa) al proyecto sin la
## shell. Lo valida antes de copiar (model_validator.gd: glTF 2.0 acotado, sin URIs afuera ni
## extensiones requeridas), lo copia como copy_file, espera el reimport y devuelve lo que importó:
## nodos, mallas, materiales, animaciones y el AABB del modelo instanciado. Los errores del import
## los suma el registro (errores nuevos desde el inicio de la llamada).
## .fbx queda afuera por ahora: en 4.7 lo importa ufbx y se puede sumar después.
## preview_model (m11-87): el modelo en un mundo propio fuera de pantalla, con luz y entorno neutros,
## visto desde 1 a 8 ángulos alrededor de su caja (las mismas órbitas que capture_editor_viewport).

const McpTool := preload("../mcp_tool.gd")
const WriteTargets := preload("../write_targets.gd")
const PermissionPolicy := preload("../../session/permission_policy.gd")
const FileTools := preload("file_tools.gd")
const ModelValidator := preload("../model_validator.gd")
const CameraViews := preload("../../playtest/runtime/camera_views.gd")

const EXTENSIONS: PackedStringArray = ["glb", "gltf"]
## Segundos que se espera el reimport antes de devolver igual (el import sigue en el editor).
const IMPORT_TIMEOUT_S := 120.0
## El import puede no avisar con resources_reimported (archivo nuevo): pasado esto, alcanza con que
## el .import esté escrito y el editor no esté escaneando ni importando.
const SETTLE_S := 0.5

## Tamaño de cada vista de preview_model.
const PREVIEW_SIZE := Vector2i(640, 480)
const PREVIEW_DEFAULT_ANGLES := 4
## Distancia al centro en radios del modelo (con fov 50°, el modelo entero entra con margen).
const PREVIEW_RADII := 2.6
const PREVIEW_BACKGROUND := Color(0.32, 0.33, 0.36)

## Callable(abs_path: String): un archivo del proyecto cambió en disco.
var on_file_written: Callable

var _files := FileTools.new()


func tools() -> Array:
	var tool := McpTool.create("import_model", PermissionPolicy.GROUP_EDIT_FILES,
		"Imports a 3D model (.glb, or .gltf with its .bin and textures next to it) into the project, e.g. a Blender export. Validates it first (glTF 2.0, at most 16 MB, no files outside its folder, no data: URIs, no required extensions, bounded node/mesh/accessor counts), copies it as a new resource, waits for the editor to import it and returns the nodes, meshes, materials, skins, animation names and the bounding box of the imported scene, plus any import errors. `replace: true` overwrites a model already in the project in place (it keeps its uid, so the scenes that use it update) and asks the user first. .fbx is not supported: export glTF Binary (.glb).",
		{
			"from": {"type": "string", "description": "Absolute path of the exported file, or a res:// path"},
			"to": {"type": "string", "description": "res:// folder, or res:// file path with the same extension"},
			"replace": {"type": "boolean", "description": "Overwrite the model at `to` (default false)"},
		},
		["from", "to"], _import_model) as McpTool
	# Leer un archivo de afuera del proyecto, o pisar un modelo que usan otras escenas: pregunta (en
	# Construir, One-shot y Auto también), como copy_file desde afuera.
	tool.group_resolver = func(args: Dictionary) -> String:
		var from := str(args.get("from", "")).strip_edges()
		return PermissionPolicy.GROUP_EDIT_FILES if from.begins_with("res://") and not bool(args.get("replace", false)) else PermissionPolicy.GROUP_SHELL
	tool.describer = _describe
	var preview := McpTool.create("preview_model", PermissionPolicy.GROUP_READ,
		"Renders a 3D model of the project (an imported .glb/.gltf/.blend/.obj, a scene without scripts, or a Mesh resource) on its own, off screen, with neutral light and background, from 1-8 angles orbiting its bounding box (30° up), and returns the views as images. Use it after import_model to check the model before placing it. Nothing in the open scene changes.",
		{
			"path": {"type": "string", "description": "res:// path of the model"},
			"angles": {"type": "integer", "minimum": 1, "maximum": CameraViews.MAX_ANGLES, "description": "How many views around it (default %d)" % PREVIEW_DEFAULT_ANGLES},
			"distance": {"type": "number", "description": "Orbit distance (default: far enough to fit it)"},
		},
		["path"], _preview_model)
	return WriteTargets.declare([tool, preview], {
		"import_model": func(args: Dictionary) -> PackedStringArray: return WriteTargets.keys(args, ["to"]),
	})


## Lo que se ve en el pedido de permiso: de dónde a dónde, y al reemplazar, quién lo usa.
func _describe(args: Dictionary) -> String:
	var plan := plan_import(args)
	if plan.has("error"):
		return "Import %s → %s" % [args.get("from", ""), args.get("to", "")]
	var text := "Import %s → %s" % [plan.source, plan.target]
	if plan.replace:
		var users := FileTools.references_to(plan.target, {}).keys()
		text = "Replace %s with %s" % [plan.target, plan.source]
		if not users.is_empty():
			users.sort()
			text += "\nUsed by: " + ", ".join(users.slice(0, FileTools.REFERENCE_LIST_LIMIT))
	return text


## Revisa los argumentos sin tocar nada: {source (absoluta), target (res://), replace, validation,
## copies: [[origen absoluto, destino res://]]} o {error}. Sin editor: los tests lo usan directo.
func plan_import(args: Dictionary) -> Dictionary:
	var raw_from := str(args.get("from", "")).strip_edges()
	var raw_to := str(args.get("to", "")).strip_edges()
	var replace := bool(args.get("replace", false))
	if raw_from.is_empty() or raw_to.is_empty():
		return {"error": "Both `from` and `to` are required."}
	var source := ProjectSettings.globalize_path(raw_from) if raw_from.begins_with("res://") else raw_from
	var extension := source.get_extension().to_lower()
	if extension == "fbx":
		return {"error": "import_model does not take .fbx yet: export glTF Binary (.glb) instead (in Blender: File > Export > glTF 2.0, Format: glTF Binary)."}
	if not extension in EXTENSIONS:
		return {"error": "import_model takes a .glb, or a .gltf with its files next to it."}
	if not source.is_absolute_path() or not FileAccess.file_exists(source):
		return {"error": "%s does not exist (use an absolute path or res://)." % raw_from}
	var to := FileTools._normalize(raw_to)
	var target := to if to.get_extension().to_lower() in EXTENSIONS else to.path_join(source.get_file())
	if target.get_extension().to_lower() != extension:
		return {"error": "%s and %s must have the same extension." % [raw_from, target]}
	var exists := FileAccess.file_exists(target)
	if exists and not replace:
		var users := FileTools.references_to(target, {}).keys()
		var used := " It is used by %s." % ", ".join(users.slice(0, FileTools.REFERENCE_LIST_LIMIT)) if not users.is_empty() else ""
		return {"error": "%s already exists.%s Pass replace: true to overwrite it in place (it keeps its uid), or pick another `to`." % [target, used]}
	if replace and not exists:
		return {"error": "replace: true needs an existing model at %s." % target}
	if ProjectSettings.globalize_path(target) == source:
		return {"error": "%s is already that file." % target}
	var refused := _import_script(source)
	if refused.is_empty() and exists:
		refused = _import_script(ProjectSettings.globalize_path(target))
	if not refused.is_empty():
		return {"error": "%s.import runs the import script %s: import_model does not import models with an import script (it would run code on every reimport). Remove it from the import settings first." % [refused[0], refused[1]]}
	var validation := ModelValidator.inspect_file(source)
	if not validation.success:
		return {"error": "%s was not imported: %s" % [raw_from, validation.error]}
	var copies: Array = [[source, target]]
	var folder := source.get_base_dir()
	for file: String in validation.get("files", PackedStringArray()):
		copies.append([file, target.get_base_dir().path_join(file.trim_prefix(folder + "/"))])
	for pair: Array in copies:
		var invalid := _check(pair[1], replace)
		if not invalid.is_empty():
			return {"error": invalid}
	return {"source": source, "target": target, "replace": replace, "validation": validation, "copies": copies}


func _import_model(args: Dictionary) -> Dictionary:
	var plan := plan_import(args)
	if plan.has("error"):
		return McpTool.error(plan.error)
	var started := Time.get_unix_time_from_system()
	for pair: Array in plan.copies:
		var target := ProjectSettings.globalize_path(pair[1])
		DirAccess.make_dir_recursive_absolute(target.get_base_dir())
		var error := DirAccess.copy_absolute(pair[0], target)
		if error != OK:
			return McpTool.error("Could not copy %s: %s." % [pair[0], error_string(error)])
		if on_file_written.is_valid():
			on_file_written.call(target)
	var imported: bool = await _wait_for_import(plan.target, started)
	var summary: Dictionary = plan.validation.summary
	var lines: PackedStringArray = []
	lines.append("%s %s (%s): %d nodes, %d meshes, %d materials, %d skins, %d images." % [
		"Replaced" if plan.replace else "Imported", plan.target, String.humanize_size(int(summary.bytes)),
		summary.nodes, summary.meshes, summary.materials, summary.skins, summary.images])
	if plan.copies.size() > 1:
		lines.append("Copied with it: " + ", ".join(plan.copies.slice(1).map(func(pair: Array) -> String: return pair[1])))
	if not imported:
		lines.append("The editor has not finished importing it after %d s: wait with editor_wait or check get_errors before using it." % int(IMPORT_TIMEOUT_S))
	else:
		var scene := ResourceLoader.load(plan.target, "", ResourceLoader.CACHE_MODE_REPLACE) as PackedScene
		if scene == null:
			lines.append("The editor imported it, but it does not load as a scene: check get_errors.")
		else:
			var info := scene_info(scene)
			var names: PackedStringArray = info.animations if not info.animations.is_empty() else summary.animations
			lines.append("Animations: %s." % (", ".join(names) if not names.is_empty() else "none"))
			var box: AABB = info.aabb
			lines.append("AABB: position (%.3f, %.3f, %.3f), size (%.3f, %.3f, %.3f)." % [box.position.x, box.position.y, box.position.z, box.size.x, box.size.y, box.size.z])
	if plan.replace:
		var users := FileTools.references_to(plan.target, {}).keys()
		if not users.is_empty():
			users.sort()
			lines.append("Scenes and resources that use it (they get the new version): " + ", ".join(users.slice(0, FileTools.REFERENCE_LIST_LIMIT)))
	for warning: String in extension_warnings():
		lines.append(warning)
	if imported:
		lines.append("Look at it with preview_model (path %s) before placing it in a scene." % plan.target)
	return McpTool.text("\n".join(lines))


## Espera a que el editor importe `target`: el aviso de resources_reimported, o el .import escrito
## después de copiar sin escaneo ni import en curso. false si pasa el tiempo límite.
func _wait_for_import(target: String, started: float) -> bool:
	var filesystem := EditorInterface.get_resource_filesystem()
	var reimported := [false]
	var on_reimported := func(paths: PackedStringArray) -> void:
		if target in paths:
			reimported[0] = true
	filesystem.resources_reimported.connect(on_reimported)
	filesystem.scan()
	var tree := Engine.get_main_loop() as SceneTree
	var begin := Time.get_ticks_msec()
	var done := false
	while not done and Time.get_ticks_msec() - begin < IMPORT_TIMEOUT_S * 1000.0:
		await tree.process_frame
		var settled := Time.get_ticks_msec() - begin > SETTLE_S * 1000.0 and not filesystem.is_scanning() and not filesystem.is_importing()
		done = reimported[0] or (settled and FileAccess.get_modified_time(target + ".import") >= int(started) and ResourceLoader.exists(target))
	filesystem.resources_reimported.disconnect(on_reimported)
	return done


## Animaciones y AABB del modelo instanciado (sin agregarlo al árbol).
static func scene_info(scene: PackedScene) -> Dictionary:
	var root := scene.instantiate()
	var animations: PackedStringArray = []
	var box := AABB()
	var first := true
	var stack: Array = [[root, Transform3D.IDENTITY]]
	while not stack.is_empty():
		var item: Array = stack.pop_back()
		var node: Node = item[0]
		var transform: Transform3D = item[1]
		if node is Node3D and node != root:
			transform = transform * (node as Node3D).transform
		if node is AnimationPlayer:
			for name: StringName in (node as AnimationPlayer).get_animation_list():
				if not str(name) in animations:
					animations.append(str(name))
		if node is VisualInstance3D:
			var local := transform * (node as VisualInstance3D).get_aabb()
			box = local if first else box.merge(local)
			first = false
		for child: Node in node.get_children():
			stack.append([child, transform])
	root.free()
	return {"animations": animations, "aabb": box}


## Plugins habilitados que registran una GLTFDocumentExtension: corren código propio en cada import
## de glTF, así que se avisa (no se bloquea: es código del proyecto).
static func extension_warnings() -> PackedStringArray:
	var warnings: PackedStringArray = []
	for config: String in ProjectSettings.get_setting("editor_plugins/enabled", PackedStringArray()):
		var folder := config.get_base_dir()
		if folder.begins_with("res://addons/godot_agent"):
			continue
		var scripts: PackedStringArray = []
		FileTools._collect(folder, scripts, true)
		for script: String in scripts:
			if script.get_extension() == "gd" and FileAccess.get_file_as_string(script).contains("register_gltf_document_extension"):
				warnings.append("Note: the enabled plugin %s registers a GLTFDocumentExtension (%s), which runs its own code on every glTF import." % [folder, script])
				break
	return warnings


## [archivo, script] si el .import de `absolute` tiene un import_script, o [].
static func _import_script(absolute: String) -> PackedStringArray:
	var config := ConfigFile.new()
	if config.load(absolute + ".import") != OK:
		return PackedStringArray()
	var script := str(config.get_value("params", "import_script/path", ""))
	return PackedStringArray([absolute, script]) if not script.is_empty() else PackedStringArray()


## "" si se puede escribir en `path` (al reemplazar, existe y se pisa; si no, no tiene que existir).
func _check(path: String, replace: bool) -> String:
	if replace and FileAccess.file_exists(path):
		return _files._check_target(path, true)
	return _files._check_target(path, false)


## Revisa lo pedido a preview_model sin dibujar: {path, resource, angles, distance (-1 = la que
## entre)} o {error}. Una escena con scripts no: instanciarla en el editor correría sus @tool.
static func plan_preview(args: Dictionary) -> Dictionary:
	var path := str(args.get("path", "")).strip_edges()
	if not path.begins_with("res://"):
		return {"error": "`path` must be a res:// path of a model in the project."}
	if not ResourceLoader.exists(path):
		return {"error": "%s does not exist or has not been imported yet (wait with editor_wait idle: true)." % path}
	var angles := int(args.get("angles", PREVIEW_DEFAULT_ANGLES))
	if angles < 1 or angles > CameraViews.MAX_ANGLES:
		return {"error": "angles goes from 1 to %d." % CameraViews.MAX_ANGLES}
	var distance := float(args.get("distance", -1.0))
	if args.has("distance") and not (distance > 0.0 and is_finite(distance)):
		return {"error": "distance must be a positive number."}
	var resource := ResourceLoader.load(path)
	if resource is PackedScene:
		var state := (resource as PackedScene).get_state()
		for node in state.get_node_count():
			for property in state.get_node_property_count(node):
				if state.get_node_property_name(node, property) == &"script" and state.get_node_property_value(node, property) != null:
					return {"error": "%s has scripts (node %s): preview_model only shows models. To see a scene, open it and use capture_editor_viewport with angles." % [path, state.get_node_path(node)]}
	elif not resource is Mesh:
		return {"error": "%s is a %s, not a 3D model (a scene or a Mesh)." % [path, resource.get_class() if resource else "file Godot can't load"]}
	return {"path": path, "resource": resource, "angles": angles, "distance": distance}


## Las vistas en órbita alrededor de `box`, para CameraViews.render. `distance` < 0: la que entra.
static func preview_views(box: AABB, angles: int, distance: float) -> Dictionary:
	var center := box.get_center()
	var radius := maxf(box.size.length() / 2.0, 0.001)
	var orbit := distance if distance > 0.0 else radius * PREVIEW_RADII
	var views: Array[Dictionary] = []
	for i in angles:
		var heading := 360.0 * i / angles
		views.append({"label": "angle %d of %d: heading %d°, %d° up, %.2f m from the center" % [i + 1, angles, roundi(heading), roundi(CameraViews.ELEVATION_DEG), orbit],
			"transform": CameraViews.orbit(center, heading, CameraViews.ELEVATION_DEG, orbit)})
	return {"views": views, "three_d": true, "near": maxf(orbit / 1000.0, 0.001), "far": orbit + radius * 4.0}


func _preview_model(args: Dictionary) -> Dictionary:
	var plan := plan_preview(args)
	if plan.has("error"):
		return McpTool.error(str(plan.error))
	var stage := _stage()
	var model: Node3D
	if plan.resource is PackedScene:
		var instance := (plan.resource as PackedScene).instantiate()
		if not instance is Node3D:
			instance.free()
			stage.free()
			return McpTool.error("%s is not a 3D scene (its root is a %s)." % [plan.path, instance.get_class()])
		model = instance
	else:
		var mesh_instance := MeshInstance3D.new()
		mesh_instance.mesh = plan.resource
		model = mesh_instance
	stage.add_child(model)
	var host := EditorInterface.get_base_control()
	host.add_child(stage)
	var box := _box(model)
	if box.size == Vector3.ZERO:
		stage.queue_free()
		return McpTool.error("%s has nothing to draw (no visible meshes)." % plan.path)
	var planned := preview_views(box, int(plan.angles), float(plan.distance))
	# Una cámara de referencia con near y far a la escala del modelo: CameraViews copia su lente.
	var lens := Camera3D.new()
	lens.fov = 50.0
	lens.near = planned.near
	lens.far = planned.far
	for view: Dictionary in planned.views:
		view["source"] = lens
	var shots: Variant = await CameraViews.render(host, planned, 0, stage)
	lens.free()
	stage.queue_free()
	if shots is Dictionary:
		return McpTool.error(str(shots.error))
	var content: Array = [{"type": "text", "text": "%s: size (%.3f, %.3f, %.3f) m, center (%.3f, %.3f, %.3f)." % [plan.path, box.size.x, box.size.y, box.size.z, box.get_center().x, box.get_center().y, box.get_center().z]}]
	for shot: Dictionary in shots:
		content.append({"type": "text", "text": "%s (%dx%d)" % [shot.label, PREVIEW_SIZE.x, PREVIEW_SIZE.y]})
		content.append({"type": "image", "mimeType": "image/png", "data": Marshalls.raw_to_base64(shot.png)})
	return {"content": content, "isError": false}


## El mundo propio de la vista previa: fondo gris, luz ambiente pareja, una luz principal y una de
## relleno. No se dibuja por su cuenta: CameraViews renderiza con cámaras en otro SubViewport que
## comparte este mundo.
static func _stage() -> SubViewport:
	var stage := SubViewport.new()
	stage.name = "PreviewModelStage"
	stage.own_world_3d = true
	stage.size = PREVIEW_SIZE
	stage.render_target_update_mode = SubViewport.UPDATE_DISABLED
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = PREVIEW_BACKGROUND
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.75, 0.75, 0.78)
	environment.ambient_light_energy = 0.3
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var world := WorldEnvironment.new()
	world.environment = environment
	stage.add_child(world)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-50.0, -35.0, 0.0)
	key.light_energy = 0.8
	stage.add_child(key)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-20.0, 145.0, 0.0)
	fill.light_energy = 0.25
	stage.add_child(fill)
	return stage


## La caja de las mallas visibles del modelo, ya en el árbol (en coordenadas del mundo propio).
static func _box(model: Node3D) -> AABB:
	var box := AABB()
	var first := true
	var visuals: Array = model.find_children("*", "VisualInstance3D", true, false)
	if model is VisualInstance3D:
		visuals.append(model)
	for node: Node in visuals:
		var visual := node as VisualInstance3D
		if not visual.is_visible_in_tree() or visual is Light3D:
			continue
		var global_box := visual.global_transform * visual.get_aabb()
		box = global_box if first else box.merge(global_box)
		first = false
	return box
