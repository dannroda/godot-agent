extends "test_case.gd"
## Conversión de valores JSON a propiedades de Godot (tools de edición, spec §6).

const ValueCoercion := preload("res://addons/godot_agent/mcp/tools/value_coercion.gd")


func _ok(target: Object, property: String, value: Variant) -> Variant:
	var result := ValueCoercion.coerce(target, property, value)
	if not result.ok:
		_fail_check("%s=%s: %s" % [property, value, result.error])
	return result.value


func _fail_check(message: String) -> void:
	assert_true(false, message)


func test_vectors_and_numbers() -> void:
	var node := Node2D.new()
	assert_eq(_ok(node, "position", [10, 20.5]), Vector2(10, 20.5), "array → Vector2")
	assert_eq(_ok(node, "position", {"x": 1, "y": 2}), Vector2(1, 2), "dict → Vector2")
	assert_eq(_ok(node, "position", "Vector2(3, 4)"), Vector2(3, 4), "texto Godot → Vector2")
	assert_eq(_ok(node, "rotation", 1), 1.0, "int → float")
	assert_eq(_ok(node, "z_index", 3.0), 3, "float entero → int")
	assert_eq(_ok(node, "visible", false), false, "bool")
	assert_false(ValueCoercion.coerce(node, "position", [1]).ok, "Vector2 con un componente")
	assert_false(ValueCoercion.coerce(node, "z_index", 1.5).ok, "int con decimales")
	node.free()


func test_colors_strings_enums() -> void:
	var label := Label.new()
	assert_eq(_ok(label, "modulate", "#ff0000"), Color(1, 0, 0), "color html")
	assert_eq(_ok(label, "modulate", "red"), Color.RED, "color por nombre")
	assert_eq(_ok(label, "modulate", [0, 1, 0, 0.5]), Color(0, 1, 0, 0.5), "color array")
	assert_eq(_ok(label, "text", 42), "42", "número → texto")
	assert_eq(_ok(label, "horizontal_alignment", "Center"), HORIZONTAL_ALIGNMENT_CENTER, "enum por nombre")
	assert_eq(_ok(label, "horizontal_alignment", 2), HORIZONTAL_ALIGNMENT_RIGHT, "enum por número")
	label.free()


func test_unknown_property() -> void:
	var label := Label.new()
	var result := ValueCoercion.coerce(label, "txt", "hola")
	assert_false(result.ok, "propiedad inexistente")
	assert_true(str(result.error).contains("text"), "sugiere 'text': %s" % result.error)
	label.free()


func test_resources() -> void:
	var sprite := Sprite2D.new()
	assert_eq(_ok(sprite, "texture", null), null, "null en recurso")
	assert_false(ValueCoercion.coerce(sprite, "texture", "res://no/existe.png").ok, "recurso inexistente")
	assert_false(ValueCoercion.coerce(sprite, "texture", "res://tests/fixtures/main_fixture.tscn").ok, "tipo de recurso incorrecto")
	sprite.free()
