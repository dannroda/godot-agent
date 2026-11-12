extends "test_case.gd"
## HoverTooltip (m12-51): un tooltip que se actualiza solo no cambia mientras el mouse está encima
## (Godot cerraba el abierto al moverse un píxel); el texto nuevo se pone al salir.

const HoverTooltip := preload("res://addons/godot_agent/ui/hover_tooltip.gd")


func test_set_text_waits_for_the_mouse_to_leave() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var button := Button.new()
	button.text = "7 %"
	button.position = Vector2(10, 10)
	button.size = Vector2(80, 30)
	tree.root.add_child(button)
	await tree.process_frame
	HoverTooltip.set_text(button, "Context: 7 %")
	assert_eq(button.tooltip_text, "Context: 7 %", "sin el mouse encima se pone enseguida")
	_move(tree.root, Vector2(40, 20))
	await tree.process_frame
	assert_true(HoverTooltip.is_hovered(button), "el mouse está encima")
	HoverTooltip.set_text(button, "Context: 8 %")
	assert_eq(button.tooltip_text, "Context: 7 %", "con el mouse encima el abierto no cambia")
	assert_eq(HoverTooltip.text_of(button), "Context: 8 %", "y el nuevo queda guardado")
	HoverTooltip.set_text(button, "Context: 9 %")
	assert_eq(HoverTooltip.text_of(button), "Context: 9 %", "el último gana")
	_move(tree.root, Vector2(300, 300))
	await tree.process_frame
	assert_false(HoverTooltip.is_hovered(button), "el mouse salió")
	assert_eq(button.tooltip_text, "Context: 9 %", "al salir se pone el último")
	assert_eq(HoverTooltip.text_of(button), "Context: 9 %", "sin nada guardado")
	# Volver al texto que se ve, con el mouse encima, descarta el guardado.
	_move(tree.root, Vector2(40, 20))
	await tree.process_frame
	HoverTooltip.set_text(button, "Context: 10 %")
	HoverTooltip.set_text(button, "Context: 9 %")
	_move(tree.root, Vector2(300, 300))
	await tree.process_frame
	assert_eq(button.tooltip_text, "Context: 9 %", "lo que se ve ya era lo último")
	button.free()


static func _move(viewport: Viewport, position: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = position
	motion.global_position = position
	viewport.push_input(motion)
