@tool
extends RefCounted
## m11-53 en el editor: godot.bake y godot.export_project por el registry, en Auto.
## 1. navigation en 3D y 2D: polígonos > 0, deshacer los deja como antes, el .tscn no cambia.
## 2. occluders con el botón del editor (buscado por su texto): escribe el .occ junto a la escena.
## 3. Un nodo sin botón de hornear: error claro, sin colgarse.
## 4. lightmaps (solo con `lightmaps`, va a la suite full si tarda): escribe el .lmbake.
## 5. export_project: sin presets da error; con un proyecto chico de prueba, debug sin plantillas da el
##    error claro y pack escribe el .pck; export_presets.cfg tiene el mismo hash antes y después.
## Las escenas que se hornean con el botón se copian a res://tests/tmp/bake (el editor escribe al lado) y
## la carpeta se borra al final; nada se guarda.

const SessionModel := preload("res://addons/godot_agent/session/session_model.gd")
const BakeTools := preload("res://addons/godot_agent/mcp/tools/bake_tools.gd")
const ExportTools := preload("res://addons/godot_agent/mcp/tools/export_tools.gd")
const PLUGIN_SCRIPT := "res://addons/godot_agent/agent_plugin.gd"
const FIXTURES := "res://tests/fixtures/bake"
const TMP := "res://tests/tmp/bake"

var failures: PackedStringArray = []
var lightmaps := false
var _tree: SceneTree
var _plugin: Node
var _registry: Object


func run(tree: SceneTree) -> PackedStringArray:
	_tree = tree
	for node: Node in tree.root.find_children("*", "Node", true, false):
		if node.get_script() and (node.get_script() as Script).resource_path == PLUGIN_SCRIPT:
			_plugin = node
	if _plugin == null:
		return PackedStringArray(["no se encontró el plugin"])
	_registry = _plugin.get(&"_registry")
	var model: SessionModel = _plugin.get(&"_model")
	var saved_mode := model.harness_mode
	model.set_harness_mode(SessionModel.HarnessMode.AUTO)  # edit_scene y project allow: sin tarjetas
	_copy_fixtures()
	await _frames(2)
	while EditorInterface.get_resource_filesystem().is_scanning():
		await _tree.process_frame
	await _navigation("nav3d.tscn", "Region", NavigationMesh)
	await _navigation("nav2d.tscn", "Region", NavigationPolygon)
	await _occluders()
	if lightmaps:
		await _lightmaps()
	elif RenderingServer.get_current_rendering_method() == "gl_compatibility":
		await _lightmaps_need_forward()
	await _export()
	model.set_harness_mode(saved_mode)
	while EditorInterface.get_edited_scene_root() != null:
		EditorInterface.close_scene()
		await _tree.process_frame
	_remove_tmp()
	return failures


func _navigation(file: String, region_path: String, type: Variant) -> void:
	var scene := FIXTURES.path_join(file)
	var hash_before := FileAccess.get_sha256(scene)
	EditorInterface.open_scene_from_path(scene)
	await _frames(5)
	var root := EditorInterface.get_edited_scene_root()
	var region := root.get_node(region_path)
	var resource: Resource = BakeTools.navigation_resource(region)
	_expect(is_instance_of(resource, type) and int(resource.call(&"get_polygon_count")) == 0, "%s: sin hornear al empezar" % file)
	var report := await _call("bake", {"kind": "navigation"})
	var polygons := int(resource.call(&"get_polygon_count"))
	_expect(polygons > 0 and report.contains("✓ Region:") and report.contains("Undo step"), "%s: horneada (%d polígonos) · %s" % [file, polygons, report])
	var history := EditorInterface.get_editor_undo_redo().get_history_undo_redo(EditorInterface.get_editor_undo_redo().get_object_history_id(root))
	history.undo()
	_expect(int(resource.call(&"get_polygon_count")) == 0, "%s: deshacer la deja sin polígonos (%d)" % [file, int(resource.call(&"get_polygon_count"))])
	history.redo()
	_expect(int(resource.call(&"get_polygon_count")) == polygons, "%s: rehacer vuelve a los %d" % [file, polygons])
	_expect(FileAccess.get_sha256(scene) == hash_before, "%s: el .tscn cambió" % file)
	EditorInterface.close_scene()
	await _frames(3)


func _occluders() -> void:
	var scene := TMP.path_join("occluders.tscn")
	EditorInterface.open_scene_from_path(scene)
	await _frames(5)
	var report := await _call("bake", {"kind": "occluders"})
	_expect(report.contains("✓ Occluder: wrote") and FileAccess.file_exists(TMP.path_join("occluders.occ")), "occluders con el botón · %s" % report)
	var occluder: Variant = EditorInterface.get_edited_scene_root().get_node("Occluder").get(&"occluder")
	_expect(occluder is ArrayOccluder3D and not (occluder as ArrayOccluder3D).vertices.is_empty(), "el OccluderInstance3D apunta al horneado")
	# 3. Un nodo que ningún plugin hornea: el botón no aparece y la tool no se cuelga.
	var tools := BakeTools.new()
	var started := Time.get_ticks_msec()
	var outcome: Dictionary = await tools.press_bake_button(EditorInterface.get_edited_scene_root().get_node("Block"), BakeTools.KIND_OCCLUDERS)
	_expect(str(outcome.get("error", "")).contains("button was not found") and Time.get_ticks_msec() - started < 5000, "sin botón: error claro y rápido · %s" % [outcome])
	var wrong := await _call("bake", {"kind": "lightmaps"})
	_expect(wrong.contains("has no LightmapGI"), "un tipo que la escena no tiene · %s" % wrong)
	EditorInterface.close_scene()
	await _frames(3)


func _lightmaps() -> void:
	var scene := TMP.path_join("lights.tscn")
	EditorInterface.open_scene_from_path(scene)
	await _frames(5)
	var started := Time.get_ticks_msec()
	var report := await _call("bake", {"kind": "lightmaps"})
	var seconds := (Time.get_ticks_msec() - started) / 1000.0
	print("[bake-check] lightmaps en %.1f s" % seconds)
	_expect(report.contains("✓ LightmapGI: wrote") and FileAccess.file_exists(TMP.path_join("lights.lmbake")), "lightmaps con el botón · %s" % report)
	EditorInterface.close_scene()
	await _frames(3)


## Con Compatibility (los checks de ci) el editor no hornea lightmaps: error claro, sin apretar nada.
func _lightmaps_need_forward() -> void:
	EditorInterface.open_scene_from_path(TMP.path_join("lights.tscn"))
	await _frames(5)
	var report := await _call("bake", {"kind": "lightmaps"})
	_expect(report.contains("Compatibility renderer") and not FileAccess.file_exists(TMP.path_join("lights.lmbake")), "lightmaps con Compatibility · %s" % report)
	EditorInterface.close_scene()
	await _frames(3)


func _export() -> void:
	var none := await _call("export_project", {"preset": "Linux", "mode": "pack"})
	_expect(none.contains("no export presets") or none.contains("There is no export preset"), "sin presets en el proyecto · %s" % none)
	var dir := OS.get_cache_dir().path_join("godot_agent_bake_check_%d" % OS.get_process_id())
	DirAccess.make_dir_recursive_absolute(dir)
	_write(dir.path_join("project.godot"), "config_version=5\n\n[application]\n\nconfig/name=\"Export Probe\"\nrun/main_scene=\"res://main.tscn\"\n")
	_write(dir.path_join("main.tscn"), "[gd_scene format=3]\n\n[node name=\"Main\" type=\"Node2D\"]\n")
	_write(dir.path_join("export_presets.cfg"), "[preset.0]\n\nname=\"Linux\"\nplatform=\"Linux\"\nrunnable=true\nexport_filter=\"all_resources\"\nexport_path=\"build/probe.x86_64\"\n\n[preset.0.options]\n\nbinary_format/embed_pck=false\n")
	var hash_before := FileAccess.get_sha256(dir.path_join("export_presets.cfg"))
	var tools := ExportTools.new()
	tools.project_dir = dir
	tools.exports_dir = dir.path_join("exports")
	tools.templates_dir = dir.path_join("templates-none")
	var no_templates: Dictionary = await tools.call(&"_export_project", {"preset": "Linux"})
	_expect(no_templates.get("isError", false) and str(no_templates.content[0].text).contains("Manage Export Templates"), "debug sin plantillas · %s" % [no_templates])
	var pack: Dictionary = await tools.call(&"_export_project", {"preset": "Linux", "mode": "pack"})
	var text := str(pack.content[0].text)
	var pck := dir.path_join("exports/Linux/probe.pck")
	_expect(not pack.get("isError", false) and text.contains("done in") and FileAccess.file_exists(pck), "pack · %s" % text)
	_expect(FileAccess.get_sha256(dir.path_join("export_presets.cfg")) == hash_before, "export_presets.cfg cambió")
	_expect(not DirAccess.dir_exists_absolute(dir.path_join("build")), "escribió en la ruta del preset sin pedirlo")
	_remove(dir)


## El texto de una tool (o el del error).
func _call(tool_name: String, args: Dictionary) -> String:
	var result: Dictionary = await _registry.call(&"call_tool", tool_name, args, "")
	var texts: PackedStringArray = []
	for block: Variant in result.get("content", []):
		if block is Dictionary and block.get("type") == "text":
			texts.append(str(block.text))
	return "\n".join(texts)


func _copy_fixtures() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(TMP))
	for file: String in ["occluders.tscn", "lights.tscn"]:
		DirAccess.copy_absolute(ProjectSettings.globalize_path(FIXTURES.path_join(file)), ProjectSettings.globalize_path(TMP.path_join(file)))
	# Un escaneo completo: en 4.7 el reimport del .exr falla en una carpeta que el editor no conoce, y
	# la escena de un usuario siempre está en una que ya escaneó.
	EditorInterface.get_resource_filesystem().scan()


func _remove_tmp() -> void:
	_remove(ProjectSettings.globalize_path(TMP))
	EditorInterface.get_resource_filesystem().scan()


static func _remove(dir: String) -> void:
	for sub: String in DirAccess.get_directories_at(dir):
		_remove(dir.path_join(sub))
	for file: String in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(file))
	DirAccess.remove_absolute(dir)


static func _write(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()


func _frames(count: int) -> void:
	for i in count:
		await _tree.process_frame


func _expect(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
