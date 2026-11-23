extends "test_case.gd"
## m11-87: preview_model revisa lo pedido sin dibujar (ruta, ángulos, distancia, escenas con scripts)
## y arma las órbitas alrededor de la caja del modelo. El dibujo de verdad lo mira mcp_check en el
## editor (acá no hay GPU).

const ModelTools := preload("res://addons/godot_agent/mcp/tools/model_tools.gd")
const CameraViews := preload("res://addons/godot_agent/playtest/runtime/camera_views.gd")

const DIR := "res://tests/tmp/preview_model"


func _mesh() -> String:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))
	var path := DIR.path_join("box.tres")
	ResourceSaver.save(BoxMesh.new(), path)
	return path


func test_plan_refuses_what_it_cannot_show() -> void:
	assert_true(ModelTools.plan_preview({"path": "/tmp/model.glb"}).error.contains("res://"), "solo del proyecto")
	assert_true(ModelTools.plan_preview({"path": "res://nowhere/model.glb"}).error.contains("does not exist"), "que exista")
	var mesh := _mesh()
	assert_true(ModelTools.plan_preview({"path": mesh, "angles": 0}).error.contains("1 to 8"), "ángulos de 1 a 8")
	assert_true(ModelTools.plan_preview({"path": mesh, "angles": 9}).has("error"), "no más de 8")
	assert_true(ModelTools.plan_preview({"path": mesh, "distance": -2}).error.contains("positive"), "distancia positiva")
	assert_true(ModelTools.plan_preview({"path": "res://tests/fixtures/debug_fixture.tscn"}).error.contains("has scripts"), "una escena con scripts no se instancia")
	var gradient := DIR.path_join("gradient.tres")
	ResourceSaver.save(Gradient.new(), gradient)
	assert_true(ModelTools.plan_preview({"path": gradient}).error.contains("not a 3D model"), "otro recurso no es un modelo")


func test_plan_takes_meshes_and_scenes_without_scripts() -> void:
	var plan := ModelTools.plan_preview({"path": _mesh()})
	assert_false(plan.has("error"), "una malla: %s" % plan.get("error", ""))
	assert_true(plan.resource is Mesh, "cargada")
	assert_eq(plan.angles, ModelTools.PREVIEW_DEFAULT_ANGLES, "ángulos por defecto")
	assert_eq(plan.distance, -1.0, "distancia: la que entre")
	var scene := PackedScene.new()
	var root := Node3D.new()
	var child := MeshInstance3D.new()
	child.mesh = BoxMesh.new()
	root.add_child(child)
	child.owner = root
	scene.pack(root)
	root.free()
	var path := DIR.path_join("plain.tscn")
	ResourceSaver.save(scene, path)
	plan = ModelTools.plan_preview({"path": path, "angles": 8, "distance": 3})
	assert_false(plan.has("error"), "una escena sin scripts: %s" % plan.get("error", ""))
	assert_eq([plan.angles, plan.distance], [8, 3.0], "con lo pedido")


func test_orbits_fit_the_box() -> void:
	var box := AABB(Vector3(-1, 0, -1), Vector3(2, 4, 2))
	var planned := ModelTools.preview_views(box, 4, -1.0)
	assert_eq(planned.views.size(), 4, "una vista por ángulo")
	var center := box.get_center()
	var radius := box.size.length() / 2.0
	for view: Dictionary in planned.views:
		var transform: Transform3D = view.transform
		assert_true(is_equal_approx(transform.origin.distance_to(center), radius * ModelTools.PREVIEW_RADII), "a la distancia en que entra")
		assert_true((-transform.basis.z).dot((center - transform.origin).normalized()) > 0.999, "mirando al centro")
		assert_true(transform.origin.y > center.y, "desde arriba")
	assert_true(planned.views[1].label.begins_with("angle 2 of 4: heading 90°"), "etiqueta: " + planned.views[1].label)
	assert_true(planned.near < radius and planned.far > radius * ModelTools.PREVIEW_RADII + radius, "near y far a la escala del modelo")
	var fixed := ModelTools.preview_views(box, 1, 10.0)
	assert_true(is_equal_approx((fixed.views[0].transform as Transform3D).origin.distance_to(center), 10.0), "o a la distancia pedida")
	var tiny := ModelTools.preview_views(AABB(Vector3.ZERO, Vector3(0.01, 0.01, 0.01)), 1, -1.0)
	assert_true(tiny.near < 0.01, "un modelo chico no queda detrás del near (%f)" % tiny.near)
	for file: String in DirAccess.get_files_at(DIR):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(DIR.path_join(file)))
