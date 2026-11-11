extends Node2D
## Usa un autoload por uid (State), uno en minúscula (tracker) y una clase de un plugin.


func _ready() -> void:
	State.level += 1
	tracker.count += 1
	var button := FancyButton.new()
	add_child(button)
