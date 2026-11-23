@tool
extends RefCounted
## import_model (m11-85): trae un modelo exportado (de Blender u otro programa) al proyecto sin la
## shell. Lo valida antes de copiar (model_validator.gd: glTF 2.0 acotado, sin URIs afuera ni
## extensiones requeridas), lo copia como copy_file, espera el reimport y devuelve lo que importó:
## nodos, mallas, materiales, animaciones y el AABB del modelo instanciado. Los errores del import
## los suma el registro (errores nuevos desde el inicio de la llamada).
## .fbx queda afuera por ahora: en 4.7 lo importa ufbx y se puede sumar después.

const McpTool := preload("../mcp_tool.gd")
const WriteTargets := preload("../write_targets.gd")
const PermissionPolicy := preload("../../session/permission_policy.gd")
const FileTools := preload("file_tools.gd")
const ModelValidator := preload("../model_validator.gd")

const EXTENSIONS: PackedStringArray = ["glb", "gltf"]
## Segundos que se espera el reimport antes de devolver igual (el import sigue en el editor).
const IMPORT_TIMEOUT_S := 120.0
## El import puede no avisar con resources_reimported (archivo nuevo): pasado esto, alcanza con que
## el .import esté escrito y el editor no esté escaneando ni importando.
const SETTLE_S := 0.5

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
	return WriteTargets.declare([tool], {
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
