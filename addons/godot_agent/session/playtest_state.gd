@tool
extends RefCounted
## Lo del playtest en curso que la sesión pone y run_tools.gd lee (m20-07): aparte para que la sesión no
## cargue run_tools, que nombra clases del editor y no parsea en la app exportada.

## Cuándo se acaba el tiempo del playtest en curso (m15-19), como meta de Engine porque hay un solo juego
## corriendo a la vez. No es un `static var`: asignarlo desde otro script es un set sobre el recurso
## GDScript, que en el editor lo marca como editado; el play siguiente guarda los recursos editados,
## reescribe este archivo y lo recarga con _run_scene a mitad de camino, y el editor se cae (m16-03, m16-08).
const DEADLINE_META := &"godot_agent_playtest_deadline_ms"
## m11-49: quién recibe el corte de un playtest en loop (Callable(seen: Dictionary)), puesto por la
## sesión que corre el playtest; meta de Engine por lo mismo que DEADLINE_META. Sin él, no se vigila.
const LOOP_HANDLER_META := &"godot_agent_playtest_loop_handler"
const LOOP_SERIAL_META := &"godot_agent_playtest_loop_serial"
const GAME_TOOLS: PackedStringArray = ["game_tree", "game_get", "game_set", "game_call", "game_wait", "game_input", "game_find", "game_ui", "game_ui_act", "game_script", "game_pause", "game_step", "game_watch", "game_frames", "game_monitors", "game_breakpoint", "game_stack", "game_debug"]


## Pone (o con un Callable vacío, quita) quién recibe el corte de un playtest en loop (m11-49). Cada
## playtest empieza con el historial vacío.
static func set_loop_handler(handler: Callable) -> void:
	if handler.is_valid():
		Engine.set_meta(LOOP_HANDLER_META, handler)
		Engine.set_meta(LOOP_SERIAL_META, int(Engine.get_meta(LOOP_SERIAL_META, 0)) + 1)
	elif Engine.has_meta(LOOP_HANDLER_META):
		Engine.remove_meta(LOOP_HANDLER_META)


## `ms`: en Time.get_ticks_msec; 0 = sin tope.
static func set_deadline(ms: int) -> void:
	if ms > 0:
		Engine.set_meta(DEADLINE_META, ms)
	elif Engine.has_meta(DEADLINE_META):
		Engine.remove_meta(DEADLINE_META)
