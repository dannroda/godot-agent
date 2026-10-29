extends "test_case.gd"
## Formulario de la pantalla One-shot: qué falta para iniciar (m12-33).

const AgentMainScreen := preload("res://addons/godot_agent/ui/main_screen/agent_main_screen.gd")


func test_start_blocker() -> void:
	assert_eq(AgentMainScreen.start_blocker("Claude Code", "Pong", false), "", "con agente y objetivo, nada")
	assert_eq(AgentMainScreen.start_blocker("Claude Code", "  \n", false), "Write the goal first.", "sin objetivo")
	assert_eq(AgentMainScreen.start_blocker("", "Pong", false), "Set up an agent first.", "sin agente")
	assert_eq(AgentMainScreen.start_blocker("", "", true), "A One-shot is already running.", "en curso gana")
