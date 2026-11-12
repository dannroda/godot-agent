extends Node2D
## Fixture de m11-62: una puerta que cuenta los ticks de su Timer. Sus sabotajes de escena: speed a 0,
## la raíz oculta, Panel oculto, la señal del Timer desconectada; Zone y Shape no los nombra la regresión.

@export var speed := 200.0

var opened_count := 0


func _on_timer_timeout() -> void:
	opened_count += 1
