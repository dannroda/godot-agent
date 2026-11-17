extends "test_case.gd"
## m12-47: los chips junto al estado salen de las máquinas en marcha (`live`), con su antigüedad y
## en alerta cuando piden atención; sin máquinas en marcha no hay chips. m12-56: el texto propio de
## cada máquina, la antigüedad legible, cuándo sigue el One-shot y qué chips hacen algo al clic.

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
	# El ancho que reserva no cambia con los segundos (m12-53): el chip no crece y no corre a los demás.
	var reserve := func(age: int) -> String:
		return AgentDock.machine_chips([{"machine": "Game", "label": "running", "age": age, "live": true}])[0].reserve
	assert_eq([3, 12, 59].map(reserve), [reserve.call(3), reserve.call(3), reserve.call(3)], "la misma reserva en segundos")
	assert_eq([60, 600, 3599].map(reserve), [reserve.call(60), reserve.call(60), reserve.call(60)], "la misma reserva en minutos")
	assert_eq([3600, 7200, 4500].map(reserve), [reserve.call(3600), reserve.call(3600), reserve.call(3600)], "la misma reserva en horas, también en la hora justa («2 h»)")
	assert_eq(AgentDock.machine_chips([{"machine": "Game", "label": "launching", "live": true}])[0].reserve, "Game · launching", "sin edad, el texto mismo")


## m12-56: «▶ Game running · 25 min», no «Game · running · 1503 s»; la acción del clic viaja con el chip.
func test_chip_text_and_action() -> void:
	var game := AgentDock.machine_chips([{"machine": "Game", "label": "running", "chip": "▶ Game running", "age": 1503, "live": true}])[0]
	assert_eq(game.text, "▶ Game running · 25 min", "el texto del chip y la antigüedad legible")
	assert_eq(game.action, "", "el juego corriendo no hace nada al clic")
	var breaked := AgentDock.machine_chips([{"machine": "Game", "label": "stopped in the debugger", "chip": "⏸ Game stopped in the debugger", "age": 4500, "live": true, "alert": true, "action": "debugger"}])[0]
	assert_eq(breaked.text, "⏸ Game stopped in the debugger · 1 h 15 min", "horas y minutos")
	assert_eq(breaked.action, "debugger", "parado, el clic abre el Depurador")


func test_oneshot_chip() -> void:
	var now := 1_000_000
	var paused := AgentDock.oneshot_chip("quota", "Paused for quota", "building", now + 72 * 60, now)
	assert_eq(paused.chip, "⏸ One-shot paused · resumes in 1 h 12 min", "esperando cuota: cuándo sigue, sin la etapa")
	assert_eq(paused.action, "oneshot", "el clic abre el One-shot")
	assert_eq(paused.reserve, "⏸ One-shot paused · resumes in 88 h 88 min", "la reserva de la cuenta regresiva")
	assert_eq(AgentDock.oneshot_chip("quota", "Limited", "building", 0, now).chip, "⏸ One-shot · out of quota", "sin hora de vuelta")
	assert_eq(AgentDock.oneshot_chip("quota", "Limited", "building", now - 5, now).chip, "⏸ One-shot · out of quota", "una hora ya pasada tampoco se muestra")
	assert_eq(AgentDock.oneshot_chip("running", "Running", "building", 0, now).chip, "▶ One-shot · building", "corriendo: la etapa")
	assert_eq(AgentDock.oneshot_chip("waiting", "Ready to resume", "building", 0, now).chip, "⏸ One-shot · Ready to resume", "esperando al usuario: la fase")
	assert_eq(AgentDock.oneshot_chip("other", "Evaluating · QA round 2", "evaluation", 0, now).chip, "▶ One-shot · Evaluating · QA round 2", "otra fase")
	var chip := AgentDock.machine_chips([{"machine": "One-shot", "label": "Paused for quota · building", "age": 1503, "live": true}.merged(paused, true)])[0]
	assert_eq(chip.text, paused.chip, "en el chip, sin la antigüedad de la fase")
	assert_eq(chip.reserve, paused.reserve, "con la reserva del One-shot")
