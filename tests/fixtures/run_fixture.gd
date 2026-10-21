extends Node2D
## Escena de prueba de run_scene: imprime al arrancar y al recibir ui_accept; pinta todo de rojo.


func _ready() -> void:
	print("run_fixture listo")


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_accept"):
		print("ui_accept recibido")
	elif event.is_action_released("ui_accept"):
		print("ui_accept soltado")
