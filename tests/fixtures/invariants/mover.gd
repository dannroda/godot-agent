extends Node2D
## Fixture de m11-44: se mueve a la derecha y se frena en 100. Un mutante que da vuelta la suma lo
## saca de la pantalla por la izquierda, y solo el invariante de la regresión lo ve.

const SPEED := 400.0


func _physics_process(delta: float) -> void:
	position.x = minf(position.x + SPEED * delta, 100.0)
