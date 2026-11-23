@tool
extends "../tool_loop_guard.gd"
## m11-49: corta un playtest cuando el agente entra en loop, con el detector de tool_loop_guard.gd
## sobre las tools del juego. Con WARN_REPEATS vueltas el resultado de la tool se lo dice al agente;
## con CUT_REPEATS el harness corta el playtest como «could not test».

const MAX_PERIOD := 3
const WARN_REPEATS := 3
const CUT_REPEATS := 4


func _init() -> void:
	max_period = MAX_PERIOD
	cut_repeats = CUT_REPEATS
	keep_repeats = CUT_REPEATS
