extends Node
## Escena de prueba de run_scene: imprime y cierra el juego enseguida.


func _ready() -> void:
	print("run_quits adiós")
	await get_tree().create_timer(0.5).timeout  # deja salir el Output por el debugger
	get_tree().quit()
