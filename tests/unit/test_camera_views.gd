extends "test_case.gd"
## capture_game_frame desde otra cámara (m11-52): lo que se arma antes de renderizar.

const CameraViews := preload("res://addons/godot_agent/playtest/runtime/camera_views.gd")


func test_orbit_looks_at_the_center() -> void:
	var center := Vector3(1, 0, -2)
	for heading in [0.0, 90.0, 180.0, 270.0]:
		var view := CameraViews.orbit(center, heading, 30.0, 10.0)
		assert_true(is_equal_approx(view.origin.distance_to(center), 10.0), "a la distancia pedida (%d°)" % heading)
		assert_true(view.origin.y > center.y, "desde arriba")
		var forward := -view.basis.z
		assert_true(forward.dot((center - view.origin).normalized()) > 0.999, "mira al centro (%d°)" % heading)
	assert_true(CameraViews.orbit(center, 0.0, 30.0, 10.0).origin.z > center.z, "0° es desde +Z")


func test_plan() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var root := Node3D.new()
	var box := MeshInstance3D.new()
	box.mesh = BoxMesh.new()
	box.position = Vector3(4, 0, 0)
	root.add_child(box)
	var side := Camera3D.new()
	side.name = "Side"
	side.fov = 40.0
	root.add_child(side)
	tree.root.add_child(root)
	await tree.process_frame  # las transformadas globales valen una vez dentro del árbol
	var viewport: Viewport = tree.root
	assert_true(CameraViews.wants_view({"angles": 2}) and not CameraViews.wants_view({}), "wants_view")
	var by_camera := CameraViews.plan(root, viewport, {"camera": "Side"})
	assert_eq(by_camera.views.size(), 1, "una vista")
	assert_true(by_camera.three_d and by_camera.views[0].source == side, "desde la cámara elegida, con su lente")
	assert_true(CameraViews.plan(root, viewport, {"camera": "Nope"}).error.contains("not a Camera3D"), "cámara inexistente")
	var around := CameraViews.plan(root, viewport, {"angles": 4})
	assert_eq(around.views.size(), 4, "4 ángulos")
	assert_true(str(around.views[0].label).contains("(4.0, 0.0, 0.0)"), "sin look_at orbita el centro de lo dibujado: %s" % around.views[0].label)
	assert_true(CameraViews.plan(root, viewport, {"angles": 9}).error.contains("from 1 to 8"), "fuera de rango")
	assert_true(CameraViews.plan(root, viewport, {"angles": 2, "look_from": [0, 0, 0]}).has("error"), "angles no toma look_from")
	assert_true(CameraViews.plan(root, viewport, {"look_at": [1, 2]}).error.contains("3 numbers"), "3D pide 3 números")
	assert_true(CameraViews.plan(root, viewport, {"look_from": [0, 0, 0], "look_at": [0, 0, 0]}).error.contains("same point"), "mismo punto")
	var looking := CameraViews.plan(root, viewport, {"look_from": [0, 0, 5], "look_at": [4, 0, 0]})
	var transform: Transform3D = looking.views[0].transform
	assert_true((-transform.basis.z).dot((Vector3(4, 0, 0) - Vector3(0, 0, 5)).normalized()) > 0.999, "look_from/look_at")
	root.free()
	var flat := Node2D.new()
	tree.root.add_child(flat)
	assert_true(CameraViews.plan(flat, viewport, {"angles": 2}).error.contains("3D scenes"), "angles en 2D")
	var view_2d := CameraViews.plan(flat, viewport, {"look_at": [10, 20], "zoom": 2})
	assert_true(not view_2d.three_d and view_2d.views[0].position == Vector2(10, 20) and is_equal_approx(view_2d.views[0].zoom, 2.0), "2D con look_at y zoom")
	flat.free()
