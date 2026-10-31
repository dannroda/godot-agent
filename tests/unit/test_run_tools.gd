extends "test_case.gd"
## Partes puras de run_scene (spec §6): normalización de los pasos de input y Output nuevo del panel.

const RunTools := preload("res://addons/godot_agent/mcp/tools/run_tools.gd")


func test_normalize_steps() -> void:
	var steps: Array = []
	assert_eq(RunTools.normalize_steps([{"t": 0.5, "action": "ui_accept", "pressed": true}, {"t": -1, "action": "ui_cancel", "pressed": false}], steps), "", "pasos válidos")
	assert_eq(steps, [{"kind": "action", "action": "ui_accept", "t": 0.5, "pressed": true}, {"kind": "action", "action": "ui_cancel", "t": 0.0, "pressed": false}], "pressed explícito y t negativo")
	assert_eq(RunTools.normalize_steps(null, []), "", "sin inputs")
	assert_true(RunTools.normalize_steps("ui_accept", []).contains("list"), "no es lista")
	assert_true(RunTools.normalize_steps([{"t": "x", "action": "ui_accept"}], []).contains("`t`"), "t no numérico")
	assert_true(RunTools.normalize_steps([{"t": 0, "action": "no_existe"}], []).contains("no_existe"), "acción inexistente")
	assert_true(RunTools.normalize_steps([{"t": 0}], []).contains("Step without"), "paso vacío")
	assert_true(RunTools.normalize_steps([{"key": "Nada"}], []).contains("Unknown key"), "tecla inexistente")
	assert_true(RunTools.normalize_steps([{"click": [1]}], []).contains("[x, y]"), "click mal formado")


func test_normalize_taps_and_kinds() -> void:
	var steps: Array = []
	assert_eq(RunTools.normalize_steps([{"action": "ui_accept"}, {"key": "Ctrl+S"}, {"click": [10, 20], "button": "right"}, {"event": "joy_axis:left_x:-", "t": 2}], steps), "", "pasos válidos")
	var gap := RunTools.TAP_HOLD_S + RunTools.STEP_GAP_S
	assert_eq(steps.size(), 9, "taps: apretar y soltar; el click lleva un movimiento antes")
	assert_eq([steps[0].t, steps[1].t, steps[1].pressed], [0.0, RunTools.TAP_HOLD_S, false], "acción: tap")
	assert_eq(steps[2].kind, "key", "tecla")
	assert_true(absf(float(steps[2].t) - gap) < 0.001, "el paso sin t va después del anterior")
	assert_eq([steps[2].keycode, steps[2].ctrl, steps[2].shift], [KEY_S, true, false], "Ctrl+S")
	assert_eq([steps[4].kind, steps[4].x, steps[4].y], ["mouse_motion", 10.0, 20.0], "click: primero se mueve")
	assert_eq([steps[5].kind, steps[5].button, steps[5].pressed], ["mouse_button", MOUSE_BUTTON_RIGHT, true], "click derecho")
	assert_eq([steps[7].kind, steps[7].axis, steps[7].value, steps[7].t], ["joy_axis", JOY_AXIS_LEFT_X, -1.0, 2.0], "eje con t explícito")


## m14-01: por frame de física, con soltar a los hold_frames y fuerza en las acciones.
func test_normalize_by_frame() -> void:
	var steps: Array = []
	assert_eq(RunTools.normalize_steps([{"frame": 10, "action": "ui_accept", "strength": 0.5}, {"action": "ui_cancel", "hold_frames": 2}, {"frame": 40, "action": "ui_left", "pressed": true}], steps), "", "pasos por frame")
	assert_eq(steps.map(func(step: Dictionary) -> String: return "%s@%d:%s" % [step.action, step.frame, step.pressed]),
		["ui_accept@10:true", "ui_accept@16:false", "ui_cancel@17:true", "ui_cancel@19:false", "ui_left@40:true"], "frames: tap de 6, el siguiente justo después, hold_frames propio")
	assert_eq(steps[0].strength, 0.5, "fuerza de la acción")
	assert_false(steps.any(func(step: Dictionary) -> bool: return step.has("t")), "sin t en modo frame")
	assert_true(RunTools.normalize_steps([{"frame": 1, "action": "ui_accept"}, {"t": 2, "action": "ui_accept"}], []).contains("either `t` or `frame`"), "no se mezclan t y frame")
	assert_true(RunTools.normalize_steps([{"frame": 1.5, "action": "ui_accept"}], []).contains("whole number"), "frame entero")
	assert_eq(RunTools.step_seconds({"frame": 120}), 120.0 / RunTools.physics_fps(), "frame a segundos con los ticks del proyecto")


func test_output_delta() -> void:
	assert_eq(RunTools._output_delta("a\nb\n", "a\nb\nc\n\nd"), "c\nd", "solo lo nuevo, sin líneas vacías")
	assert_eq(RunTools._output_delta("viejo\n", "nuevo"), "nuevo", "panel limpiado al correr: todo")
	var many: PackedStringArray = []
	for i in RunTools.OUTPUT_LINE_LIMIT + 5:
		many.append("l%d" % i)
	var delta := RunTools._output_delta("", "\n".join(many))
	assert_true(delta.begins_with("(… 5 earlier lines)"), "recorta y avisa")
	assert_true(delta.ends_with("l%d" % (RunTools.OUTPUT_LINE_LIMIT + 4)), "conserva las últimas")


## m15-04: mira relativa y texto tecleado carácter por carácter.
func test_normalize_look_and_text() -> void:
	var steps: Array = []
	assert_eq(RunTools.normalize_steps([{"look": [30, -5]}], steps), "", "look")
	assert_eq([steps[0].kind, steps[0].rel_x, steps[0].rel_y], ["mouse_motion", 30.0, -5.0], "movimiento relativo")
	assert_eq(steps.size(), 1, "look no aprieta nada")
	assert_true(RunTools.normalize_steps([{"look": [1]}], []).contains("[dx, dy]"), "look mal formado")
	steps.clear()
	assert_eq(RunTools.normalize_steps([{"text": "aB ñ"}], steps), "", "text")
	assert_eq(steps.size(), 8, "apretar y soltar cada carácter")
	assert_eq([steps[0].kind, steps[0].unicode, steps[0].keycode, steps[0].shift, steps[0].pressed], ["key", "a".unicode_at(0), KEY_A, false, true], "a")
	assert_true(steps[2].shift, "B lleva shift")
	assert_eq(steps[6].unicode, "ñ".unicode_at(0), "fuera del teclado inglés también")
	assert_true(RunTools.normalize_steps([{"text": "x".repeat(RunTools.INPUT_MAX_STEPS + 1)}], []).contains("At most"), "el tope cuenta los caracteres")


## m15-12: lo que game_script no puede usar.
func test_blocked_api() -> void:
	assert_eq(RunTools.blocked_api("func run(game):\n\treturn game.player().position"), "", "jugar y leer")
	assert_eq(RunTools.blocked_api("var f = FileAccess.open('x', FileAccess.WRITE)"), "FileAccess", "archivos")
	assert_true(RunTools.blocked_api("OS.execute('rm', [])").begins_with("OS"), "procesos")
	assert_eq(RunTools.blocked_api("OS.get_name()"), "", "el resto de OS se puede")
	assert_true(RunTools.blocked_api("ProjectSettings.save()").begins_with("ProjectSettings"), "guardar el proyecto")
	assert_false(RunTools.blocked_api("get_viewport().get_texture().get_image().save_png('a.png')").is_empty(), "escribir una imagen")


## m16-03: un run_scene que murió no bloquea a los siguientes para siempre.
func test_busy_expires() -> void:
	assert_false(RunTools.busy_is_stale(1000, 1000 + int(RunTools.MAX_SECONDS * 1000.0)), "uno largo sigue en curso")
	assert_true(RunTools.busy_is_stale(1000, 1000 + 3600000), "una hora después ya no")


## m15-22: frames repartidos en la ventana pedida.
func test_pick_frames() -> void:
	var frames: Array[Dictionary] = []
	for i in 21:
		frames.append({"t": i * 0.5, "path": "f%d" % i})
	var picked := RunTools.pick_frames(frames, 2.0, 3)
	assert_eq(picked.map(func(frame: Dictionary) -> float: return frame.t), [8.0, 9.0, 10.0], "los últimos 2 s, parejos")
	assert_eq(RunTools.pick_frames(frames, 1.0, 12).size(), 3, "menos que los pedidos: todos")
