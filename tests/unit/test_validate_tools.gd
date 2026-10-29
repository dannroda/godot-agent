extends "test_case.gd"
## Validadores de física y de TileMapLayers (m14-04), sobre árboles armados acá.

const ValidateTools := preload("res://addons/godot_agent/mcp/tools/validate_tools.gd")


func test_physics() -> void:
	var root := Node2D.new()
	var player := CharacterBody2D.new()
	player.name = "Player"
	player.collision_layer = 1
	player.collision_mask = 2
	var shape := CollisionShape2D.new()
	shape.shape = CircleShape2D.new()
	player.add_child(shape)
	root.add_child(player)
	var wall := StaticBody2D.new()
	wall.name = "Wall"
	wall.collision_layer = 4  # el jugador mira la capa 2: no lo toca
	root.add_child(wall)
	var coin := Area2D.new()
	coin.name = "Coin"
	coin.collision_mask = 0
	var empty_shape := CollisionShape2D.new()
	empty_shape.name = "Shape"
	coin.add_child(empty_shape)
	root.add_child(coin)
	var loose := CollisionShape2D.new()
	loose.name = "Loose"
	loose.shape = RectangleShape2D.new()
	root.add_child(loose)
	var report := ValidateTools.physics_issues(root)
	var text := "\n".join(report.issues)
	assert_true(text.contains("Wall (StaticBody2D) has no enabled CollisionShape"), "cuerpo sin forma · " + text)
	assert_true(text.contains("Coin/Shape has no shape"), "forma sin shape")
	assert_true(text.contains("Loose is not a direct child of a body"), "forma suelta")
	assert_true(text.contains("Player's collision_mask (layer 2) matches no collision_layer"), "máscara que no cruza nada")
	assert_true(text.contains("Coin has collision_mask 0: it detects nothing"), "área que no detecta nada")
	assert_eq(report.summary, "3 bodies/areas, 3 shapes", "resumen")
	wall.collision_layer = 2
	var fixed := CollisionShape2D.new()
	fixed.shape = RectangleShape2D.new()
	wall.add_child(fixed)
	var after := "\n".join(ValidateTools.physics_issues(root).issues)
	assert_false(after.contains("Player's collision_mask") or after.contains("Wall (StaticBody2D)"), "arreglado, ya no aparece · " + after)
	root.free()


func test_tilemap() -> void:
	var root := Node2D.new()
	var layer := TileMapLayer.new()
	layer.name = "Ground"
	root.add_child(layer)
	layer.set_cell(Vector2i(0, 0), 0, Vector2i(0, 0))
	assert_true("\n".join(ValidateTools.tilemap_issues(root).issues).contains("Ground has 1 cells but no TileSet"), "sin TileSet")
	var tile_set := TileSet.new()
	tile_set.add_physics_layer()
	var atlas := TileSetAtlasSource.new()
	var image := Image.create(32, 16, false, Image.FORMAT_RGBA8)
	atlas.texture = ImageTexture.create_from_image(image)
	atlas.texture_region_size = Vector2i(16, 16)
	atlas.create_tile(Vector2i(0, 0))
	tile_set.add_source(atlas, 0)
	layer.tile_set = tile_set
	layer.set_cell(Vector2i(1, 0), 0, Vector2i(1, 0))  # el atlas no tiene ese tile
	layer.set_cell(Vector2i(2, 0), 5, Vector2i(0, 0))  # ni esa fuente
	var text := "\n".join(ValidateTools.tilemap_issues(root).issues)
	assert_true(text.contains("Ground: 2 cells use a source or atlas tile") and text.contains("(1, 0)") and text.contains("(2, 0)"), "celdas inválidas · " + text)
	assert_true(text.contains("none of its placed tiles has a collision polygon"), "tiles sin colisión con capas de física")
	layer.erase_cell(Vector2i(1, 0))
	layer.erase_cell(Vector2i(2, 0))
	var data := atlas.get_tile_data(Vector2i(0, 0), 0)
	data.add_collision_polygon(0)
	data.set_collision_polygon_points(0, 0, PackedVector2Array([Vector2(-8, -8), Vector2(8, -8), Vector2(8, 8)]))
	var report := ValidateTools.tilemap_issues(root)
	assert_eq(report.issues, PackedStringArray(), "un mapa sano no tiene problemas")
	assert_eq(report.summary, "1 TileMapLayer, 1 cells", "resumen")
	root.free()
