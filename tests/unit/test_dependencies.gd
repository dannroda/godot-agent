extends "test_case.gd"
## dependencies (m11-78) y la línea «Inspector:» de editor_state (m11-77). Sin el editor: las partes
## estáticas de read_tools y el escaneo de referencias de file_tools que comparten.

const ReadTools := preload("res://addons/godot_agent/mcp/tools/read_tools.gd")
const FileTools := preload("res://addons/godot_agent/mcp/tools/file_tools.gd")
const DIR := "res://tests/tmp/unit_dependencies"
const PLAYER_SCRIPT := "res://tests/fixtures/fixture_player.gd"


func _fixture() -> void:
	_remove(ProjectSettings.globalize_path(DIR))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR + "/actors"))
	# level.tscn → actors/hero.tscn → actors/hero.gd → bullet.tscn (relativo) y icon.svg (res://).
	_write(DIR + "/level.tscn", '[gd_scene format=3]\n\n[ext_resource type="PackedScene" path="%s/actors/hero.tscn" id="1"]\n\n[node name="Level" type="Node2D"]\n\n[node name="Hero" parent="." instance=ExtResource("1")]\n' % DIR)
	_write(DIR + "/actors/hero.tscn", '[gd_scene format=3]\n\n[ext_resource type="Script" path="%s/actors/hero.gd" id="1"]\n\n[node name="Hero" type="Node2D"]\nscript = ExtResource("1")\n' % DIR)
	_write(DIR + "/actors/hero.gd", 'extends Node2D\n\nconst Bullet := preload("../bullet.tscn")\nconst ICON := "res://icon.svg"\n')
	_write(DIR + "/bullet.tscn", '[gd_scene format=3]\n\n[node name="Bullet" type="Node2D"]\n')
	# Nombra el script del fixture por uid, sin la ruta.
	var uid := ResourceUID.id_to_text(ResourceLoader.get_resource_uid(PLAYER_SCRIPT))
	_write(DIR + "/by_uid.gd", 'extends Node\n\nconst P := preload("%s")\n' % uid)


func test_line_at() -> void:
	assert_eq(FileTools.line_at("abc\ndef", 0), 1, "posición 0 (count con to=0 contaría todo)")
	assert_eq(FileTools.line_at("abc\ndef", 5), 2, "segunda línea")


func test_references_to() -> void:
	_fixture()
	var users := FileTools.references_to(DIR + "/bullet.tscn", {})
	assert_eq(users, {DIR + "/actors/hero.gd": PackedStringArray(["3"])}, "el preload relativo cuenta, con su línea")
	users = FileTools.references_to(DIR + "/actors/hero.tscn", {})
	assert_eq(users.keys(), [DIR + "/level.tscn"], "por ruta res://")
	assert_true(FileTools.references_to(PLAYER_SCRIPT, {}).has(DIR + "/by_uid.gd"), "por uid")
	# Una carpeta: lo de afuera que la nombra; lo de adentro entre sí no cuenta.
	users = FileTools.references_to(DIR + "/actors", {})
	assert_eq(users.keys(), [DIR + "/level.tscn"], "carpeta · %s" % [users])
	_remove(ProjectSettings.globalize_path(DIR))


func test_named_paths() -> void:
	_fixture()
	var script := DIR + "/actors/hero.gd"
	var named := FileTools.named_paths(script, FileAccess.get_file_as_string(script))
	assert_eq(named, PackedStringArray(["res://icon.svg", DIR + "/bullet.tscn"]), "res:// y relativa")
	var by_uid := FileTools.named_paths(DIR + "/by_uid.gd", FileAccess.get_file_as_string(DIR + "/by_uid.gd"))
	assert_eq(by_uid, PackedStringArray([PLAYER_SCRIPT]), "el uid se resuelve a la ruta")
	_remove(ProjectSettings.globalize_path(DIR))


func test_forward() -> void:
	_fixture()
	var one := ReadTools.dependency_report(DIR + "/level.tscn", false, 1)
	assert_true(one.contains("what it uses (forward), depth 1: 1 file") and one.contains("\n- %s/actors/hero.tscn" % DIR) and not one.contains("hero.gd"), one)
	var three := ReadTools.dependency_report(DIR + "/level.tscn", false, 3)
	assert_true(three.contains("\n  - %s/actors/hero.gd" % DIR), "nivel 2 con sangría · " + three)
	assert_true(three.contains("\n    - %s/bullet.tscn" % DIR) and three.contains("\n    - res://icon.svg"), "nivel 3: lo que el script carga · " + three)
	var leaf := ReadTools.dependency_report(DIR + "/bullet.tscn", false, 2)
	assert_true(leaf.contains("0 files. It uses no other file."), leaf)
	_remove(ProjectSettings.globalize_path(DIR))


func test_reverse() -> void:
	_fixture()
	var report := ReadTools.dependency_report(DIR + "/bullet.tscn", true, 3)
	assert_true(report.contains("who uses it (reverse), depth 3: 3 files"), report)
	assert_true(report.contains("\n- %s/actors/hero.gd (line 3)" % DIR), "quién lo precarga, con la línea · " + report)
	assert_true(report.contains("\n  - %s/actors/hero.tscn" % DIR) and report.contains("\n    - %s/level.tscn" % DIR), "y quién usa a ése · " + report)
	assert_true(ReadTools.dependency_report(DIR + "/level.tscn", true, 1).contains("Nothing in the project names it."), "nadie")
	_remove(ProjectSettings.globalize_path(DIR))


func test_missing_dependency() -> void:
	_fixture()
	_write(DIR + "/broken.gd", 'extends Node\nconst GONE := preload("res://tests/tmp/unit_dependencies/gone.tscn")\n')
	var report := ReadTools.dependency_report(DIR + "/broken.gd", false, 2)
	assert_true(report.contains("gone.tscn (missing)"), report)
	_remove(ProjectSettings.globalize_path(DIR))


func test_inspector_node_and_file() -> void:
	var root := Node2D.new()
	root.name = "Level"
	var child := Sprite2D.new()
	child.name = "Hero"
	root.add_child(child)
	assert_eq(ReadTools.inspector_line(null, root, [], null), "Inspector: (nothing)")
	assert_eq(ReadTools.inspector_line(child, root, [], null), "Inspector: node Hero (Sprite2D)")
	var stray := Node.new()
	assert_eq(ReadTools.inspector_line(stray, root, [], null), "Inspector: a Node node outside the current scene")
	assert_eq(ReadTools.inspector_line(load(PLAYER_SCRIPT), root, [], null), "Inspector: resource %s (GDScript)" % PLAYER_SCRIPT)
	stray.free()
	root.free()


func test_inspector_sub_resource() -> void:
	# El material del mesh de un nodo, sin archivo propio.
	var root := Node3D.new()
	root.name = "Level"
	var mesh_node := MeshInstance3D.new()
	mesh_node.name = "Crate"
	root.add_child(mesh_node)
	var box := BoxMesh.new()
	var material := StandardMaterial3D.new()
	box.material = material
	mesh_node.mesh = box
	var nodes: Array[Node] = [root, mesh_node]
	assert_eq(ReadTools.inspector_line(material, root, nodes, null),
		"Inspector: StandardMaterial3D, not saved to its own file · comes from node Crate (MeshInstance3D), property mesh → material")
	# Un StyleBox dentro de un tema guardado: el dueño es el recurso que lo guarda.
	var theme := Theme.new()
	theme.set_path_cache("res://ui/theme.tres")
	var box_style := StyleBoxFlat.new()
	box_style.set_path_cache("res://ui/theme.tres::StyleBoxFlat_1")
	theme.set_stylebox("normal", "Button", box_style)
	assert_eq(ReadTools.inspector_line(box_style, root, nodes, theme),
		"Inspector: StyleBoxFlat, a sub-resource saved inside res://ui/theme.tres · comes from res://ui/theme.tres, property Button/styles/normal")
	# Si no aparece, solo lo que es.
	assert_eq(ReadTools.inspector_line(StyleBoxFlat.new(), root, nodes, null), "Inspector: StyleBoxFlat, not saved to its own file")
	root.free()


static func _write(path: String, text: String) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()


static func _remove(absolute: String) -> void:
	if not DirAccess.dir_exists_absolute(absolute):
		return
	for file: String in DirAccess.get_files_at(absolute):
		DirAccess.remove_absolute(absolute.path_join(file))
	for sub: String in DirAccess.get_directories_at(absolute):
		_remove(absolute.path_join(sub))
	DirAccess.remove_absolute(absolute)
