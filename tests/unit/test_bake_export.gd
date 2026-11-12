extends "test_case.gd"
## godot.bake y godot.export_project (m11-53), lo que no necesita el editor: qué nodos se hornean, los
## datos de navegación del paso de deshacer, los argumentos del export (nada del agente salvo el preset),
## adónde va el archivo (nunca una ruta del agente), las plantillas y el informe.

const BakeTools := preload("res://addons/godot_agent/mcp/tools/bake_tools.gd")
const ExportTools := preload("res://addons/godot_agent/mcp/tools/export_tools.gd")
const PermissionPolicy := preload("res://addons/godot_agent/session/permission_policy.gd")

const PRESETS := """[preset.0]

name="Linux"
platform="Linux"
export_path="build/linux/game.x86_64"

[preset.0.options]

binary_format/embed_pck=false

[preset.1]

name="Web build"
platform="Web"
export_path=""
"""


func _tmp() -> String:
	var dir := OS.get_cache_dir().path_join("godot_agent_test_export_%d" % OS.get_process_id())
	DirAccess.make_dir_recursive_absolute(dir)
	return dir


static func _remove(dir: String) -> void:
	for sub: String in DirAccess.get_directories_at(dir):
		_remove(dir.path_join(sub))
	for file: String in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(file))
	DirAccess.remove_absolute(dir)


func test_groups() -> void:
	var bake: Array = BakeTools.new().tools()
	var export: Array = ExportTools.new().tools()
	assert_eq([bake[0].name, bake[0].group], ["bake", PermissionPolicy.GROUP_EDIT_SCENE], "bake edita la escena")
	assert_eq([export[0].name, export[0].group], ["export_project", PermissionPolicy.GROUP_PROJECT], "export en el grupo project")
	assert_eq(export[0].input_schema.properties.keys(), ["preset", "mode", "output", "timeout_s"], "ni binario ni argumentos extra")


func test_targets() -> void:
	var root := Node3D.new()
	var region := NavigationRegion3D.new()
	region.name = "Nav"
	root.add_child(region)
	region.owner = root
	var region_2d := NavigationRegion2D.new()
	region_2d.name = "Nav2D"
	root.add_child(region_2d)
	region_2d.owner = root
	var lightmap := LightmapGI.new()
	lightmap.name = "Lights"
	root.add_child(lightmap)
	lightmap.owner = root
	var foreign := NavigationRegion3D.new()
	region.add_child(foreign)  # sin owner: de adentro de una escena instanciada
	assert_eq(BakeTools.targets(root, BakeTools.KIND_NAVIGATION, "").map(func(node: Node) -> String: return node.name), ["Nav", "Nav2D"], "las regiones de la escena, 2D y 3D")
	assert_eq(BakeTools.targets(root, BakeTools.KIND_NAVIGATION, "Lights"), [], "un path que no es del tipo")
	assert_eq(BakeTools.targets(root, BakeTools.KIND_LIGHTMAPS, "")[0], lightmap, "LightmapGI")
	assert_eq(BakeTools.targets(root, BakeTools.KIND_OCCLUDERS, ""), [], "sin occluders")
	root.free()


func test_navigation_data_is_a_copy() -> void:
	var mesh := NavigationMesh.new()
	mesh.vertices = PackedVector3Array([Vector3.ZERO, Vector3.RIGHT, Vector3.BACK])
	mesh.add_polygon(PackedInt32Array([0, 1, 2]))
	var before := BakeTools.navigation_data(mesh)
	mesh.clear_polygons()
	mesh.vertices = PackedVector3Array()
	assert_eq(before.vertices.size(), 3, "los vértices de antes")
	assert_eq((before.polygons as Array).size(), 1, "los polígonos de antes, aunque el recurso cambió")
	mesh.set(&"polygons", before.polygons)
	mesh.set(&"vertices", before.vertices)
	assert_eq(mesh.get_polygon_count(), 1, "se vuelven a poner con set, como el paso de deshacer")


func test_process_args() -> void:
	assert_eq(ExportTools.process_args("/p", "debug", "Linux", "/out/game.x86_64"), PackedStringArray(["--headless", "--path", "/p", "--export-debug", "Linux", "/out/game.x86_64"]), "debug")
	assert_eq(ExportTools.process_args("/p", "release", "Web build", "/o")[3], "--export-release", "release")
	assert_eq(ExportTools.process_args("/p", "pack", "x; rm -rf ~", "/o").slice(3, 5), PackedStringArray(["--export-pack", "x; rm -rf ~"]), "el preset es un argumento solo, sin shell")


func test_presets_and_prepare() -> void:
	var dir := _tmp()
	var file := FileAccess.open(dir.path_join("export_presets.cfg"), FileAccess.WRITE)
	file.store_string(PRESETS)
	file.close()
	var hash_before := FileAccess.get_sha256(dir.path_join("export_presets.cfg"))
	var presets := ExportTools.read_presets(dir.path_join("export_presets.cfg"))
	assert_eq(presets.map(func(item: Dictionary) -> String: return item.name), ["Linux", "Web build"], "las secciones preset.N, no las .options")
	var tools := ExportTools.new()
	tools.project_dir = dir
	tools.templates_dir = dir.path_join("no_templates")
	tools.exports_dir = dir.path_join("exports")
	assert_true(str(tools.prepare({"preset": "Mac"}).get("error", "")).contains("«Linux», «Web build»"), "un preset que no está lista los que hay")
	var no_templates := str(tools.prepare({"preset": "Linux"}).get("error", ""))
	assert_true(no_templates.contains("Manage Export Templates") and no_templates.contains("pack"), "sin plantillas, error claro · %s" % no_templates)
	var pack := tools.prepare({"preset": "Linux", "mode": "pack"})
	assert_false(pack.has("error"), "pack no necesita plantillas · %s" % pack.get("error", ""))
	assert_eq(pack.program, OS.get_executable_path(), "el binario del editor")
	assert_eq(pack.output, dir.path_join("exports/Linux/game.pck"), "en la carpeta de exports, con .pck")
	assert_true(str(tools.prepare({"preset": "Linux", "mode": "pack", "output": "/etc/passwd"}).get("error", "")).contains("not a path of its own"), "una ruta absoluta, no")
	assert_true(tools.prepare({"preset": "Linux", "mode": "pack", "output": "../../x.pck"}).has("error"), "con .., no")
	assert_true(tools.prepare({"preset": "Linux", "mode": "pack", "output": "res://x.pck"}).has("error"), "res://, no")
	assert_eq(tools.prepare({"preset": "Linux", "mode": "pack", "output": "preset"}).output, dir.path_join("build/linux/game.pck"), "la ruta del preset, relativa al proyecto")
	assert_true(str(tools.prepare({"preset": "Web build", "mode": "pack", "output": "preset"}).get("error", "")).contains("no export path"), "un preset sin ruta")
	assert_eq(str(tools.prepare({"preset": "Web build", "mode": "pack"}).output).get_file(), "Web_build.pck", "sin ruta, el nombre del preset")
	DirAccess.make_dir_recursive_absolute(tools.templates_dir)
	FileAccess.open(tools.templates_dir.path_join("version.txt"), FileAccess.WRITE).store_string("x")
	assert_eq(tools.prepare({"preset": "Linux"}).args[3], "--export-debug", "con plantillas, debug")
	assert_eq(FileAccess.get_sha256(dir.path_join("export_presets.cfg")), hash_before, "export_presets.cfg no cambió")
	_remove(dir)


func test_templates_version() -> void:
	var info := Engine.get_version_info()
	var version := ExportTools.templates_version()
	assert_true(version.begins_with("%d.%d" % [info.major, info.minor]) and version.contains("." + str(info.status)), "versión.estado · %s" % version)
	assert_eq(version.contains(".0."), false, "sin el .0 del patch")


func test_report_helpers() -> void:
	var lines := PackedStringArray(["Godot Engine v4.7.2", "savepack: begin", "ERROR: Cannot export project with preset \"Linux\" due to configuration errors:", "No export template found at the expected path:", "WARNING: something", "done"])
	var found := ExportTools.problems(lines)
	assert_eq(found.size(), 3, "las líneas de error, aviso y plantillas · %s" % [found])
	assert_eq([ExportTools.format_size(512), ExportTools.format_size(2048), ExportTools.format_size(3 * 1048576)], ["512 B", "2.0 KB", "3.0 MB"], "tamaños")
	var dir := _tmp()
	var since := int(Time.get_unix_time_from_system()) - 1
	FileAccess.open(dir.path_join("game.x86_64"), FileAccess.WRITE).store_string("12345")
	FileAccess.open(dir.path_join("game.pck"), FileAccess.WRITE).store_string("123")
	FileAccess.open(dir.path_join("other.txt"), FileAccess.WRITE).store_string("1")
	var sizes := ExportTools.written_files(dir.path_join("game.x86_64"), since)
	assert_eq(sizes, {dir.path_join("game.x86_64"): 5, dir.path_join("game.pck"): 3}, "el archivo y el .pck de al lado")
	_remove(dir)
