extends "test_case.gd"
## m16-11: los gamepads reales fuera de los juegos que lanza el agente y de los scripts headless.

const RealGamepads := preload("res://addons/godot_agent/playtest/real_gamepads.gd")


func test_ignore_and_restore_environment() -> void:
	var outer: Variant = OS.get_environment(RealGamepads.ENV) if OS.has_environment(RealGamepads.ENV) else null
	OS.unset_environment(RealGamepads.ENV)
	var previous: Variant = RealGamepads.ignore_in_children()
	assert_eq(previous, null, "no había nada")
	assert_eq(OS.get_environment(RealGamepads.ENV), RealGamepads.NONE, "los procesos que se lancen no abren ninguno")
	RealGamepads.restore(previous)
	assert_false(OS.has_environment(RealGamepads.ENV), "sin nada antes, se saca")
	OS.set_environment(RealGamepads.ENV, "0x057e/0x2009")
	previous = RealGamepads.ignore_in_children()
	RealGamepads.restore(previous)
	assert_eq(OS.get_environment(RealGamepads.ENV), "0x057e/0x2009", "lo que puso el usuario vuelve")
	RealGamepads.restore(outer)


func test_suite_runs_without_real_gamepads() -> void:
	# run_all se relanza sin ellos si había alguno: acá adentro no queda ninguno conectado.
	assert_eq(Input.get_connected_joypads(), [], "sin gamepads reales en los tests")
