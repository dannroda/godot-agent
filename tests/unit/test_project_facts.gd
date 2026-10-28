extends "test_case.gd"
## Datos del proyecto para las instrucciones (m11-07): la sección y reemplazarla sin tocar el resto.

const ProjectFacts := preload("res://addons/godot_agent/core/project_facts.gd")


func test_section() -> void:
	var settings := {
		"application/config/name": "Pong",
		"application/run/main_scene": "res://main.tscn",
		"autoload/Events": "*res://core/events.gd",
		"layer_names/2d_physics/layer_1": "world",
		"layer_names/2d_physics/layer_2": "",
		"layer_names/2d_navigation/layer_1": "ground",
		"input/jump": {},
		"input/ui_accept": {},
	}
	var text := ProjectFacts.section(settings, "4.7.2", PackedStringArray(["core", "levels"]))
	assert_true(text.begins_with(ProjectFacts.BEGIN) and text.ends_with(ProjectFacts.END), "entre marcadores")
	for expected: String in ["Godot 4.7.2, project \"Pong\"", "Main scene: `res://main.tscn`", "`Events` (res://core/events.gd)", "2D physics 1: world", "2D navigation 1: ground", "Input actions: `jump`.", "`core/`, `levels/`"]:
		assert_true(text.contains(expected), "contiene %s: %s" % [expected, text])
	assert_false(text.contains("ui_accept"), "sin las acciones del motor")
	assert_false(text.contains("2D physics 2"), "sin capas sin nombre")


func test_merge() -> void:
	var facts := ProjectFacts.section({}, "4.7.2", PackedStringArray())
	assert_eq(ProjectFacts.merge("", facts), facts + "\n", "archivo vacío")
	var mine := "# Rules\n\nUse tabs.\n"
	var merged := ProjectFacts.merge(mine, facts)
	assert_true(merged.begins_with("# Rules\n\nUse tabs.\n\n" + ProjectFacts.BEGIN), "se agrega al final")
	var updated := ProjectFacts.merge(merged + "\nMore rules.\n", ProjectFacts.section({}, "4.8", PackedStringArray()))
	assert_true(updated.contains("Godot 4.8") and not updated.contains("Godot 4.7.2"), "se reemplaza")
	assert_true(updated.begins_with("# Rules") and updated.ends_with("More rules.\n"), "lo del usuario queda")
	assert_eq(updated.count(ProjectFacts.BEGIN), 1, "una sola sección")
