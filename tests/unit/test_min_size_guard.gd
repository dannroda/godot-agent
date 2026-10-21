extends "test_case.gd"
## MinSizeGuard: una superficie oculta con un Label con autowrap (que nunca se acomodó y pide un alto
## enorme) no puede agrandar el slot del editor que la contiene.

const MinSizeGuard := preload("res://addons/godot_agent/ui/min_size_guard.gd")


func test_caps_minimum_of_hidden_content() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var tabs := TabContainer.new()
	tabs.use_hidden_tabs_for_min_size = true  # como los slots de docks del editor
	tabs.size = Vector2(300, 400)
	tree.root.add_child(tabs)
	tabs.add_child(Control.new())  # pestaña visible
	var content := VBoxContainer.new()
	content.name = "Agent"
	var label := Label.new()
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.text = "Los presets de export Android, Android (bench) no excluyen el addon: agregalo a sus filtros. ".repeat(4)
	content.add_child(label)
	var guard := MinSizeGuard.new(content)
	tabs.add_child(guard)
	await tree.process_frame
	await tree.process_frame
	assert_eq(guard.name, &"Agent", "toma el nombre del contenido (título de la pestaña con la API vieja)")
	assert_false(guard.is_visible_in_tree(), "la pestaña del contenido está oculta")
	assert_true(content.get_combined_minimum_size().y > 1000, "sin acomodar, el label pide un alto enorme (%s)" % content.get_combined_minimum_size())
	assert_true(guard.get_combined_minimum_size().y <= MinSizeGuard.MAX_MIN_SIZE.y, "el guard lo topea (%s)" % guard.get_combined_minimum_size())
	assert_true(tabs.get_combined_minimum_size().y < 400, "el slot no crece (%s)" % tabs.get_combined_minimum_size())

	# Visible: el contenido ocupa el guard, toma el ancho real y el label vuelve a un alto normal.
	tabs.current_tab = 1
	await tree.process_frame
	await tree.process_frame
	assert_eq(content.size.x, guard.size.x, "el contenido ocupa todo el ancho")
	assert_true(content.get_combined_minimum_size().y < 300, "acomodado, el alto es normal (%s)" % content.get_combined_minimum_size())
	tabs.free()
