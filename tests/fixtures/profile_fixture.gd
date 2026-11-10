extends Node
## m13-27: escena de profile_check. `_hot()` es caliente a propósito: llama a `_step()`
## CALLS_PER_FRAME veces por frame. El juego mide su propio costo (Time.get_ticks_usec alrededor de
## `_hot()`) y cada WINDOW frames manda el promedio al editor por un mensaje propio, para comparar
## con el profiler apagado y prendido.

const CALLS_PER_FRAME := 2000
const WINDOW := 20

var _acc := 0.0
var _window_us := 0
var _window_frames := 0


func _process(_delta: float) -> void:
	var start := Time.get_ticks_usec()
	_hot()
	_window_us += Time.get_ticks_usec() - start
	_window_frames += 1
	if _window_frames == WINDOW:
		if EngineDebugger.is_active():
			EngineDebugger.send_message("profcheck:window", [float(_window_us) / WINDOW])
		_window_us = 0
		_window_frames = 0


func _hot() -> void:
	for i in CALLS_PER_FRAME:
		_acc += _step(i)


func _step(i: int) -> float:
	return sqrt(float(i)) * 0.5
