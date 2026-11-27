extends "test_case.gd"
## m21-11: el primer uso con la forma del rediseño: los pasos, elegir el agente y un solo botón.

const FirstRunGuide := preload("res://addons/godot_agent/ui/dock/first_run_guide.gd")
const SuggestedAgents := preload("res://addons/godot_agent/core/suggested_agents.gd")


func test_pick_then_add() -> void:
	var guide := FirstRunGuide.new()
	guide.setup(Color.ORANGE)
	var added: Array = []
	guide.add_requested.connect(func(agent: Dictionary) -> void: added.append(agent))
	var button := guide.find_child("AddAgentButton", true, false) as Button
	assert_true(button.text.contains(str(SuggestedAgents.AGENTS[0].name)), "el recomendado, elegido de entrada · " + button.text)
	assert_eq((guide.find_child("Steps", true, false) as Control).get_child_count(), 3, "los tres pasos")
	var second: Button = guide._cards[1]
	second.pressed.emit()
	assert_true(second.button_pressed and not guide._cards[0].button_pressed, "una sola elegida")
	assert_true(button.text.contains(str(SuggestedAgents.AGENTS[1].name)), "el botón dice cuál agrega")
	button.pressed.emit()
	assert_eq(added, [SuggestedAgents.AGENTS[1]], "y agrega ese")
	guide.free()


## Los pasos no fuerzan un ancho mayor que el dock angosto.
func test_steps_fit_a_narrow_dock() -> void:
	var guide := FirstRunGuide.new()
	guide.setup(Color.ORANGE)
	var steps := guide.find_child("Steps", true, false) as Control
	assert_true(steps.get_combined_minimum_size().x < 120, "los pasos se achican · %s" % steps.get_combined_minimum_size().x)
	guide.free()
