extends CanvasLayer
## HUD of the docs demo.

var score := 0


func _process(_delta: float) -> void:
	get_node("Margin/Score").text = "Score %d" % score
