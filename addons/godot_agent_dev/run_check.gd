@tool
extends "mcp_check.gd"
## Verificación de run_scene, capture_game_frame y stop_scene (M4) dentro del editor, por HTTP real:
## - el probe reproduce inputs y captura frames;
## - un script roto devuelve el error real del debugger;
## - el autoload de playtest no queda en project.godot (ni en memoria) después de cada run,
##   y un run manual no lo lleva.

const SessionModel := preload("res://addons/godot_agent/session/session_model.gd")
const PlaytestAutoload := preload("res://addons/godot_agent/playtest/playtest_autoload.gd")
const DOCK_SCRIPT := "res://addons/godot_agent/ui/dock/agent_dock.gd"
const RUN_SCENE := "res://tests/fixtures/run_fixture.tscn"
const BROKEN_SCENE := "res://tests/fixtures/run_broken.tscn"
const QUITS_SCENE := "res://tests/fixtures/run_quits.tscn"
## Argumentos extra para el juego (p. ej. "--rendering-driver opengl3" bajo Xvfb, sin GPU).
const RUN_ARGS_ENV := "GODOT_AGENT_TEST_RUN_ARGS"
const RUN_ARGS_SETTING := "editor/run/main_run_args"


func run_run(tree: SceneTree) -> PackedStringArray:
	_tree = tree
	var model: Object
	for node: Node in tree.root.find_children("*", "Node", true, false):
		var script := node.get_script() as Script
		if script and script.resource_path == SERVER_SCRIPT:
			_server = node
		elif script and script.resource_path == DOCK_SCRIPT:
			model = node.get(&"_model")
	if _server == null or model == null:
		failures.append("no se encontró el server o el modelo")
		return failures
	var previous_args: Variant = ProjectSettings.get_setting(RUN_ARGS_SETTING, "")
	if not OS.get_environment(RUN_ARGS_ENV).is_empty():
		ProjectSettings.set_setting(RUN_ARGS_SETTING, OS.get_environment(RUN_ARGS_ENV))
	await _check_runs(model)
	ProjectSettings.set_setting(RUN_ARGS_SETTING, previous_args)
	return failures


func _check_runs(model: Object) -> void:
	await _rpc("initialize", {"protocolVersion": "2025-06-18", "capabilities": {}, "clientInfo": {"name": "run-check", "version": "1"}})
	model.call(&"set_harness_mode", SessionModel.HarnessMode.ONESHOT)

	var not_running: Dictionary = await _call("capture_game_frame", {})
	_expect(not_running.get("isError", false), "capture_game_frame sin juego → error")
	var bad_action: Dictionary = await _call("run_scene", {"scene": RUN_SCENE, "seconds": 1, "inputs": [{"t": 0, "action": "no_existe"}]})
	_expect(bad_action.get("isError", false) and _text(bad_action).contains("no_existe"), "acción inexistente → error")

	# Juego que sigue corriendo: inputs, Output y captura.
	var inputs := [{"t": 0.2, "action": "ui_accept", "pressed": true}, {"t": 0.4, "action": "ui_accept", "pressed": false}]
	var ran := await _call_text("run_scene", {"scene": RUN_SCENE, "seconds": 1.5, "inputs": inputs})
	_expect(ran.contains("sigue corriendo"), "run_scene: el juego sigue corriendo · " + ran.left(300))
	_expect(ran.contains("Inputs: 2 de 2"), "run_scene: inputs reproducidos")
	_expect(ran.contains("run_fixture listo") and ran.contains("ui_accept recibido") and ran.contains("ui_accept soltado"), "run_scene: Output del juego con los inputs")
	# Sin errores del juego ni de scripts (bajo Xvfb el editor suma ruido de X11 y de V-Sync).
	_expect(not ran.contains("[juego/error]") and not ran.contains("/script]"), "run_scene: sin errores del juego · " + ran)
	_check_autoload_gone("después de run_scene")
	var frame: Dictionary = await _call("capture_game_frame", {})
	_expect(not frame.get("isError", false) and _frame_is_red(frame), "capture_game_frame: frame rojo del juego")
	var stopped := await _call_text("stop_scene", {})
	_expect(stopped.contains("detenido") and not EditorInterface.is_playing_scene(), "stop_scene")

	# Script roto: el debugger pausa el juego y run_scene devuelve el error real.
	var broken := await _call_text("run_scene", {"scene": BROKEN_SCENE, "seconds": 5})
	_expect(broken.contains("se detuvo en el debugger") and broken.contains("queue_free"), "run_scene: error real del script roto · " + broken.left(400))
	_expect(broken.contains("run_broken.gd"), "run_scene: ubicación del error")
	await _call_text("stop_scene", {})

	# Juego que termina solo; run_scene reinicia uno que ya corría.
	await _call_text("run_scene", {"scene": RUN_SCENE, "seconds": 0.5})
	var quits := await _call_text("run_scene", {"scene": QUITS_SCENE, "seconds": 10})
	_expect(quits.contains("terminó solo") and quits.contains("run_quits adiós"), "run_scene: juego que termina solo · " + quits.left(300))
	_check_autoload_gone("después de un juego que terminó solo")

	# Run manual: sin el autoload (playtest_on_manual_runs = false).
	EditorInterface.play_custom_scene(RUN_SCENE)
	_expect(not PlaytestAutoload.is_registered(), "run manual no registra el autoload")
	var deadline := Time.get_ticks_msec() + 15000
	while Time.get_ticks_msec() < deadline and not _output_has("run_fixture listo"):
		await _tree.process_frame
	var manual_frame: Dictionary = await _call("capture_game_frame", {})
	_expect(manual_frame.get("isError", false), "run manual: sin probe")
	EditorInterface.stop_playing_scene()
	await _tree.create_timer(1.0).timeout
	_check_autoload_gone("después del run manual")


func _check_autoload_gone(label: String) -> void:
	_expect(not PlaytestAutoload.is_registered(), "autoload en memoria " + label)
	var config := ConfigFile.new()
	config.load("res://project.godot")
	_expect(not config.has_section_key("autoload", PlaytestAutoload.NAME), "autoload en project.godot " + label)


func _frame_is_red(result: Dictionary) -> bool:
	for block: Dictionary in result.get("content", []):
		if block.get("type") == "image":
			var image := Image.new()
			if image.load_png_from_buffer(Marshalls.base64_to_raw(block.data)) != OK:
				return false
			var pixel := image.get_pixel(image.get_width() / 2, image.get_height() / 2)
			return pixel.r > 0.9 and pixel.g < 0.1 and pixel.b < 0.1
	return false


func _output_has(text: String) -> bool:
	for log_node: Node in EditorInterface.get_base_control().find_children("*", "EditorLog", true, false):
		for label: Node in log_node.find_children("*", "RichTextLabel", true, false):
			return (label as RichTextLabel).get_parsed_text().contains(text)
	return false
