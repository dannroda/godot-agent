extends Node2D
## Fixture de m11-62: una puerta que cuenta los ticks de su Timer. Sus sabotajes de escena: speed a 0,
## la raíz oculta, Panel oculto, la señal del Timer desconectada; Zone y Shape no los nombra la regresión.
## max_health solo se lee en _ready (m11-63): su sabotaje se ve porque se pone antes de que entre al árbol.

@export var speed := 200.0

@export var max_health := 3

var opened_count := 0
var health := 0


func _ready() -> void:
	health = max_health


func _on_timer_timeout() -> void:
	opened_count += 1
