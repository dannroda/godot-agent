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
