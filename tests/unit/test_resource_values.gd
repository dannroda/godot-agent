extends "test_case.gd"
## Recursos inline y arrays tipados en ValueCoercion, y la descripción de get_resource (m4-13).

const ValueCoercion := preload("res://addons/godot_agent/mcp/tools/value_coercion.gd")
const ResourceTools := preload("res://addons/godot_agent/mcp/tools/resource_tools.gd")


func test_inline_resource() -> void:
	var panel := Panel.new()
	var result := ValueCoercion.coerce(panel, "theme_override_styles/panel", {"type": "StyleBoxFlat", "bg_color": "#202040", "properties": {"corner_radius_top_left": 6}})
	assert_true(result.ok, "StyleBoxFlat inline: " + str(result.error))
	if result.ok:
		var box: StyleBoxFlat = result.value
		assert_eq(box.bg_color, Color.html("#202040"), "propiedad suelta")
		assert_eq(box.corner_radius_top_left, 6, "propiedad en properties")
	var wrong := ValueCoercion.coerce(Sprite2D.new(), "texture", {"type": "StyleBoxFlat"})
	assert_false(wrong.ok, "tipo que no cumple el hint → error")
	assert_true(wrong.error.contains("Texture2D"), "dice el tipo esperado: " + wrong.error)
	assert_false(ValueCoercion.coerce(Sprite2D.new(), "texture", {"type": "Nada"}).ok, "clase inexistente")
	panel.free()


func test_project_class_and_typed_array() -> void:
	var made: Variant = ValueCoercion.new_resource("FixtureLoot")
	assert_true(made is Resource, "class_name del proyecto: %s" % [made])
	if not made is Resource:
		return
	var loot: Resource = made
	var result := ValueCoercion.coerce(loot, "items", [{"type": "FixtureItem", "title": "Sword", "damage": 7}, {"type": "FixtureItem", "title": "Bow"}])
	assert_true(result.ok, "array tipado: " + str(result.error))
	if result.ok:
		loot.set("items", result.value)
		var items: Array = loot.get("items")
		assert_true(items.is_typed() and items.size() == 2, "sigue tipado")
		assert_eq(items[0].get("damage"), 7, "elemento convertido")
	var bad := ValueCoercion.coerce(loot, "items", [{"type": "StyleBoxFlat"}])
	assert_false(bad.ok, "elemento de otro tipo → error")
	var described := "\n".join(ResourceTools._describe(loot, 1))
	assert_true(described.contains("items = [2 items]") and described.contains("title = \"Sword\"") and described.contains("damage = 7"), "describe con sub-recursos: " + described)
	assert_false(described.contains("weights"), "sin defaults")
