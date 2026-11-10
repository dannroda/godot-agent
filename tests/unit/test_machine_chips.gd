extends "test_case.gd"
## m12-47: los chips junto al estado salen de las máquinas en marcha (`live`), con su antigüedad y
## en alerta cuando piden atención; sin máquinas en marcha no hay chips.

const AgentDock := preload("res://addons/godot_agent/ui/dock/agent_dock.gd")


func test_machine_chips() -> void:
	var states: Array = [
		{"machine": "Game", "label": "running", "age": 12, "live": true, "alert": false},
		{"machine": "One-shot", "label": "paused for quota · building", "age": 3, "live": true, "alert": true},
		{"machine": "Game", "label": "no game launched", "age": -1, "live": false},
		{"machine": "Game", "label": "ended", "age": 40, "live": false, "alert": false},
	]
	var chips := AgentDock.machine_chips(states)
	assert_eq(chips.size(), 2, "solo las máquinas en marcha")
	assert_eq(chips[0].text, "Game · running · 12 s", "máquina, estado y antigüedad")
	assert_false(chips[0].alert, "corriendo no es alerta")
	assert_true(chips[1].alert and chips[1].text.begins_with("One-shot · paused for quota"), "el One-shot esperando va en alerta · %s" % [chips[1]])
	assert_eq(AgentDock.machine_chips([{"machine": "Game", "label": "launching", "live": true}]).size(), 1, "sin edad: igual se muestra")
	assert_eq(AgentDock.machine_chips([{"machine": "Game", "label": "launching", "live": true}])[0].text, "Game · launching", "sin edad no hay segundos")
	assert_true(AgentDock.machine_chips([]).is_empty(), "sin máquinas, sin chips")
