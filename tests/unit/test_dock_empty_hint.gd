extends "test_case.gd"
## m12-59: el dock sin sesión dice qué hace el harness, el modo elegido con lo que permite y cómo empezar.

const AgentDock := preload("res://addons/godot_agent/ui/dock/agent_dock.gd")


func test_empty_hint() -> void:
	var text := AgentDock.empty_hint("Build", "The agent edits scenes.", true)
	var parts := text.split("\n\n")
	assert_eq(parts.size(), 3, "tres partes · " + text)
	assert_true(parts[0].contains("from the editor"), "qué hace el harness")
	assert_eq(parts[1], "Mode Build: The agent edits scenes.", "el modo con lo que permite")
	assert_true(parts[2].contains("box below"), "cómo empezar")
	assert_eq(AgentDock.empty_hint("Level design (Build)", "").split("\n\n")[1], "Mode Level design (Build).", "modo sin descripción")
	assert_true(AgentDock.empty_hint("Build", "", false).split("\n\n")[0].contains("while the editor is open"), "fuera del editor no promete sus tools")


## m21-22: el contexto y el turno del encabezado de la app, cada uno si hay dato.
func test_context_text() -> void:
	assert_eq(AgentDock.context_text(38, 100, 4), "Context 38 % · turn 4", "los dos")
	assert_eq(AgentDock.context_text(0, 0, 2), "turn 2", "sin dato de contexto")
	assert_eq(AgentDock.context_text(0, 0, 0), "", "nada")
