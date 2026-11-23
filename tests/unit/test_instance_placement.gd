extends "test_case.gd"
## instantiate_scene ubica la instancia antes de agregarla (m11-86): un solo paso de undo.

const SceneEditTools := preload("res://addons/godot_agent/mcp/tools/scene_edit_tools.gd")


func test_place_3d() -> void:
	var node := Node3D.new()
	assert_eq(SceneEditTools.place_instance(node, {"position": [1, 2, 3], "rotation_degrees": [0, 90, 0], "scale": [2]}), "", "sin error")
	assert_eq(node.position, Vector3(1, 2, 3), "posición")
	assert_true(node.rotation_degrees.is_equal_approx(Vector3(0, 90, 0)), "rotación")
	assert_eq(node.scale, Vector3(2, 2, 2), "[n] escala parejo")
	assert_eq(SceneEditTools.place_instance(node, {"scale": 3}), "", "un número suelto también")
	assert_eq(node.scale, Vector3(3, 3, 3), "escala 3")
	assert_true(SceneEditTools.place_instance(node, {"position": [1, 2]}).contains("[x, y, z]"), "2D en un nodo 3D")
	assert_false(SceneEditTools.place_instance(node, {"position": ["a", "b", "c"]}).is_empty(), "no son números")
	node.free()


func test_place_2d_and_others() -> void:
	var node := Node2D.new()
	assert_eq(SceneEditTools.place_instance(node, {"position": [10, 20], "rotation_degrees": [45], "scale": [0.5]}), "", "sin error")
	assert_eq([node.position, node.scale], [Vector2(10, 20), Vector2(0.5, 0.5)], "posición y escala")
	assert_true(is_equal_approx(node.rotation_degrees, 45.0), "rotación de un número")
	assert_true(SceneEditTools.place_instance(node, {"position": [1, 2, 3]}).contains("[x, y]"), "3D en un nodo 2D")
	node.free()
	var plain := Node.new()
	assert_true(SceneEditTools.place_instance(plain, {"position": [1, 2, 3]}).contains("only a Node3D, Node2D or Control"), "un Node no se ubica")
	assert_eq(SceneEditTools.place_instance(plain, {}), "", "sin transformación, nada que hacer")
	plain.free()
