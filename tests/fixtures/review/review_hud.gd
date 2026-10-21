extends CanvasLayer
## HUD con el puntaje (revisión de prueba, M5).

var score: int = 0


func add_points(points: int) -> void:
	score += points


func _process(_delta: float) -> void:
	get_node("Margin/ScoreLabel").text = "Puntos: %d" % score
