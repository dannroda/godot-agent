extends "test_case.gd"
## Comandos del agente: van solos y primero en el prompt (m7-21).

const SessionController := preload("res://addons/godot_agent/session/session_controller.gd")


func test_is_slash_command() -> void:
	for text: String in ["/remote-control", "/remote-control mi sesión", "  /compact  ", "/godot:godot-gdscript", "/remote-control off\n"]:
		assert_true(SessionController.is_slash_command(text), text)
	for text: String in ["hola /remote-control", "/home/drod/x.gd", "/", "/ algo", "res://a.gd", ""]:
		assert_false(SessionController.is_slash_command(text), text)
