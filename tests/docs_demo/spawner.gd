extends Node2D
## Asteroid waves of the docs demo.

@export var asteroids_per_wave: int = 4

var wave := 0


func _ready() -> void:
	start_wave()


func start_wave() -> void:
	wave += 1
	for i in asteroids_per_wave + wave:
		var asteroid := Polygon2D.new()
		asteroid.polygon = PackedVector2Array([Vector2(-20, -8), Vector2(-6, -22), Vector2(16, -16), Vector2(22, 4), Vector2(6, 20), Vector2(-16, 14)])
		asteroid.position = Vector2(randf_range(0, 1152), randf_range(0, 648))
		add_child(asteroid)
