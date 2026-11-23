extends "test_case.gd"
## m12-59: el dock sin sesión dice qué hace el harness, el modo elegido con lo que permite y cómo empezar.

const AgentDock := preload("res://addons/godot_agent/ui/dock/agent_dock.gd")


func test_empty_hint() -> void:
	var text := AgentDock.empty_hint("Build", "The agent edits scenes.")
	var parts := text.split("\n\n")
	assert_eq(parts.size(), 3, "tres partes · " + text)
	assert_true(parts[0].contains("from the editor"), "qué hace el harness")
	assert_eq(parts[1], "Mode Build: The agent edits scenes.", "el modo con lo que permite")
	assert_true(parts[2].contains("box below"), "cómo empezar")
	assert_eq(AgentDock.empty_hint("Level design (Build)", "").split("\n\n")[1], "Mode Level design (Build).", "modo sin descripción")
