extends "test_case.gd"
## Eventos de input de set_input_action (m4-09).

const ProjectTools := preload("res://addons/godot_agent/mcp/tools/project_tools.gd")


func test_key_events() -> void:
	var space: InputEventKey = ProjectTools.parse_event("Space")
	assert_eq(space.physical_keycode, KEY_SPACE, "tecla sola")
	var save: InputEventKey = ProjectTools.parse_event("key:Ctrl+Shift+S")
	assert_true(save.ctrl_pressed and save.shift_pressed and save.physical_keycode == KEY_S, "con modificadores")
	assert_eq(ProjectTools.describe_event(save), "key Ctrl+Shift+S (physical)", "descripción")
	var portable: InputEventKey = ProjectTools.parse_event("CmdOrCtrl+Z")
	assert_true(portable.command_or_control_autoremap, "CmdOrCtrl")
	assert_true(ProjectTools.parse_event("Spcae") is String, "tecla inexistente → error")
	assert_true(ProjectTools.parse_event("Hyper+A") is String, "modificador inexistente → error")


func test_mouse_and_joypad() -> void:
	var click: InputEventMouseButton = ProjectTools.parse_event("mouse:left")
	assert_eq(click.button_index, MOUSE_BUTTON_LEFT, "mouse")
	var jump: InputEventJoypadButton = ProjectTools.parse_event("joy_button:a")
	assert_eq(jump.button_index, JOY_BUTTON_A, "botón por nombre")
	assert_eq((ProjectTools.parse_event("joy_button:3") as InputEventJoypadButton).button_index, 3, "botón por número")
	var left: InputEventJoypadMotion = ProjectTools.parse_event("joy_axis:left_x:-")
	assert_true(left.axis == JOY_AXIS_LEFT_X and left.axis_value < 0, "eje con signo")
	assert_eq(ProjectTools.describe_event(left), "joy_axis left_x-", "descripción del eje")
	assert_true(ProjectTools.parse_event("joy_axis:left_x") is String, "eje sin signo → error")
	assert_true(ProjectTools.parse_event("wheel:up") is String, "tipo desconocido → error")
	assert_true(ProjectTools.parse_event(5) is String, "no string → error")
