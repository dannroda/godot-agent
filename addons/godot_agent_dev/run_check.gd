@tool
extends "mcp_check.gd"
## Verificación de run_scene, capture_game_frame y stop_scene (M4) dentro del editor, por HTTP real:
## - el probe reproduce inputs y captura frames;
## - un script roto devuelve el error real del debugger;
## - el autoload de playtest no queda en project.godot (ni en memoria) después de cada run,
##   y un run manual no lo lleva;
## - «+ contexto → Captura del juego» del dock adjunta el frame, o avisa por qué no puede;
## - game_tree, game_get, game_set, game_call, game_wait y game_input con el juego vivo (m4-07);
## - detectores, UI, game_script, pausa, watch y filmación con un juego con bugs plantados (M13).

const SessionModel := preload("res://addons/godot_agent/session/session_model.gd")
const PlaytestAutoload := preload("res://addons/godot_agent/playtest/playtest_autoload.gd")
const DOCK_SCRIPT := "res://addons/godot_agent/ui/dock/agent_dock.gd"
const RUN_SCENE := "res://tests/fixtures/run_fixture.tscn"
const BROKEN_SCENE := "res://tests/fixtures/run_broken.tscn"
const QUITS_SCENE := "res://tests/fixtures/run_quits.tscn"
const GAME_SCENE := "res://tests/fixtures/playtest_game/playtest_game.tscn"
const PlaytestMemory := preload("res://addons/godot_agent/review/playtest_memory.gd")
const FlipbookDialog := preload("res://addons/godot_agent/ui/flipbook_dialog.gd")
const RunTools := preload("res://addons/godot_agent/mcp/tools/run_tools.gd")
## Argumentos extra para el juego (p. ej. "--rendering-driver opengl3" bajo Xvfb, sin GPU).
const RUN_ARGS_ENV := "GODOT_AGENT_TEST_RUN_ARGS"
const RUN_ARGS_SETTING := "editor/run/main_run_args"

var _dock: Node


func run_run(tree: SceneTree) -> PackedStringArray:
	_tree = tree
	var model: Object
	var plugin_config: Object
	for node: Node in tree.root.find_children("*", "Node", true, false):
		var script := node.get_script() as Script
		if script and script.resource_path == SERVER_SCRIPT:
			_server = node
		elif script and script.resource_path == DOCK_SCRIPT:
			_dock = node
			model = node.get(&"_model")
		elif script and script.resource_path == "res://addons/godot_agent/plugin.gd":
			plugin_config = node.get(&"_project_config")
	if _server == null or model == null:
		failures.append("no se encontró el server o el modelo")
		return failures
	var previous_args: Variant = ProjectSettings.get_setting(RUN_ARGS_SETTING, "")
	if not OS.get_environment(RUN_ARGS_ENV).is_empty():
		ProjectSettings.set_setting(RUN_ARGS_SETTING, OS.get_environment(RUN_ARGS_ENV))
	# El check de run manual no depende del project_config.tres local de quien lo corre.
	var manual_runs: bool = plugin_config.get(&"playtest_on_manual_runs") if plugin_config else false
	if plugin_config:
		plugin_config.set(&"playtest_on_manual_runs", false)
	await _check_runs(model)
	if plugin_config:
		plugin_config.set(&"playtest_on_manual_runs", manual_runs)
	ProjectSettings.set_setting(RUN_ARGS_SETTING, previous_args)
	return failures


func _check_runs(model: Object) -> void:
	await _rpc("initialize", {"protocolVersion": "2025-06-18", "capabilities": {}, "clientInfo": {"name": "run-check", "version": "1"}})
	model.call(&"set_harness_mode", SessionModel.HarnessMode.ONESHOT)

	var not_running: Dictionary = await _call("capture_game_frame", {})
	_expect(not_running.get("isError", false), "capture_game_frame sin juego → error")
	var no_game: Dictionary = await _call("game_tree", {})
	_expect(no_game.get("isError", false) and _text(no_game).contains("run_scene"), "game_tree sin juego → error")
	var bad_action: Dictionary = await _call("run_scene", {"scene": RUN_SCENE, "seconds": 1, "inputs": [{"t": 0, "action": "no_existe"}]})
	_expect(bad_action.get("isError", false) and _text(bad_action).contains("no_existe"), "acción inexistente → error")

	# Juego que sigue corriendo: inputs, Output y captura.
	var inputs := [{"t": 0.2, "action": "ui_accept", "pressed": true}, {"t": 0.4, "action": "ui_accept", "pressed": false}]
	var ran := await _call_text("run_scene", {"scene": RUN_SCENE, "seconds": 1.5, "inputs": inputs})
	_expect(ran.contains("still running"), "run_scene: el juego sigue corriendo · " + ran.left(300))
	_expect(ran.contains("Inputs: 2 of 2"), "run_scene: inputs reproducidos")
	_expect(ran.contains("run_fixture listo") and ran.contains("ui_accept recibido") and ran.contains("ui_accept soltado"), "run_scene: Output del juego con los inputs")
	# Sin errores del juego ni de scripts (bajo Xvfb el editor suma ruido de X11 y de V-Sync).
	_expect(not _game_errors(ran), "run_scene: sin errores del juego · " + ran)
	_check_autoload_gone("después de run_scene")
	var frame: Dictionary = await _call("capture_game_frame", {})
	_expect(not frame.get("isError", false) and _frame_is_red(frame), "capture_game_frame: frame rojo del juego")
	await _dock.call(&"_capture_game")
	var images: Dictionary = _dock.get(&"_images")
	_expect(images.size() == 1 and _frame_is_red({"content": [images.values()[0].block]}), "dock: Captura del juego adjunta el frame rojo")
	images.clear()
	await _check_live_game()
	var stopped := await _call_text("stop_scene", {})
	_expect(stopped.contains("stopped") and not EditorInterface.is_playing_scene(), "stop_scene")

	# Grabación (m14-03): el juego cierra solo, el video queda y el Movie Maker vuelve a como estaba.
	var recorded := await _call_text("run_scene", {"scene": RUN_SCENE, "seconds": 1, "record": true})
	var video := RegEx.create_from_string("Recording: (res://\\S+\\.avi)").search(recorded)
	_expect(video != null and FileAccess.file_exists(video.get_string(1)) and not EditorInterface.is_playing_scene(), "run_scene con record: video y juego cerrado · " + recorded.right(300))
	_expect(not EditorInterface.is_movie_maker_enabled(), "record: el Movie Maker vuelve a apagado")
	if video:
		var header := FileAccess.get_file_as_bytes(video.get_string(1)).slice(0, 12)
		_expect(header.slice(0, 4).get_string_from_ascii() == "RIFF" and header.slice(8, 12).get_string_from_ascii() == "AVI ", "record: es un AVI")
		DirAccess.remove_absolute(ProjectSettings.globalize_path(video.get_string(1)))

	# Script roto: el debugger pausa el juego y run_scene devuelve el error real.
	var broken := await _call_text("run_scene", {"scene": BROKEN_SCENE, "seconds": 5})
	_expect(broken.contains("stopped in the debugger") and broken.contains("queue_free"), "run_scene: error real del script roto · " + broken.left(400))
	_expect(broken.contains("run_broken.gd"), "run_scene: ubicación del error")
	await _call_text("stop_scene", {})

	# Lo mismo pidiendo seguir (m15-05): el error se lista y el juego sigue.
	var past := await _call_text("run_scene", {"scene": BROKEN_SCENE, "seconds": 1.5, "continue_on_error": true})
	_expect(past.contains("still running") and past.contains("went past") and past.contains("queue_free"), "continue_on_error: sigue corriendo y lista el error · " + past.left(500))
	await _call_text("stop_scene", {})
	await _check_playtest_game()

	# Juego que termina solo; run_scene reinicia uno que ya corría.
	await _call_text("run_scene", {"scene": RUN_SCENE, "seconds": 0.5})
	var quits := await _call_text("run_scene", {"scene": QUITS_SCENE, "seconds": 10})
	_expect(quits.contains("ended by itself") and quits.contains("run_quits adiós"), "run_scene: juego que termina solo · " + quits.left(300))
	_check_autoload_gone("después de un juego que terminó solo")

	# Run manual: sin el autoload (playtest_on_manual_runs = false).
	EditorInterface.play_custom_scene(RUN_SCENE)
	_expect(not PlaytestAutoload.is_registered(), "run manual no registra el autoload")
	var deadline := Time.get_ticks_msec() + 15000
	while Time.get_ticks_msec() < deadline and not _output_has("run_fixture listo"):
		await _tree.process_frame
	var manual_frame: Dictionary = await _call("capture_game_frame", {})
	_expect(manual_frame.get("isError", false), "run manual: sin probe")
	var entries_before: int = (model.call(&"entries") as Array).size()
	await _dock.call(&"_capture_game")
	var entries: Array = model.call(&"entries")
	_expect((_dock.get(&"_images") as Dictionary).is_empty() and entries.size() == entries_before + 1 and str(entries[-1].text).contains("playtest autoload"),
		"dock: Captura del juego en un run manual avisa que falta el autoload")
	EditorInterface.stop_playing_scene()
	await _tree.create_timer(1.0).timeout
	_check_autoload_gone("después del run manual")


## Con run_fixture corriendo: leer, cambiar, llamar, esperar y mandar inputs en vivo.
func _check_live_game() -> void:
	var tree := await _call_text("game_tree", {})
	_expect(tree.contains("RunFixture (Node2D) [run_fixture.gd]") and tree.contains("Background (ColorRect)") and tree.contains("run_fixture.tscn"), "game_tree: árbol vivo · " + tree.left(300))
	_expect(not tree.contains("GodotAgentPlaytest"), "game_tree: el probe no aparece")
	var got := await _call_text("game_get", {"path": ""})
	_expect(got.contains("score = 0") and got.contains("speed = 1.5") and got.contains("target = (3.0, 4.0)") and got.contains("position = (0.0, 0.0)"), "game_get: variables del script y comunes · " + got)
	var picked := await _call_text("game_get", {"path": "Background", "properties": ["color", "size:x", "nada"]})
	_expect(picked.contains("color = (1.0, 0.0, 0.0, 1.0)") and picked.contains("size:x = 4000") and picked.contains("nada: (no such property)"), "game_get: propiedades pedidas · " + picked)
	var missing: Dictionary = await _call("game_get", {"path": "NoExiste"})
	_expect(missing.get("isError", false) and _text(missing).contains("NoExiste"), "game_get: nodo inexistente → error")
	var set_text := await _call_text("game_set", {"path": "", "properties": {"speed": 3, "target": [5, 6], "position": [10, 20]}})
	_expect(set_text.contains("speed: 1.5 → 3.0") and set_text.contains("target: (3.0, 4.0) → (5.0, 6.0)") and set_text.contains("live only"), "game_set: cambia en vivo · " + set_text)
	var bad_set: Dictionary = await _call("game_set", {"path": "", "properties": {"target": "verde"}})
	_expect(bad_set.get("isError", false) and _text(bad_set).contains("target"), "game_set: valor inválido → error · " + _text(bad_set))
	var called := await _call_text("game_call", {"path": "", "method": "add_score", "args": [5]})
	_expect(called.contains("add_score(5) → 5"), "game_call: devuelve el resultado · " + called)
	var bad_call: Dictionary = await _call("game_call", {"path": "", "method": "volar"})
	_expect(bad_call.get("isError", false) and _text(bad_call).contains("volar"), "game_call: método inexistente → error")
	var reached := await _call_text("game_wait", {"condition": "score >= 5 and speed == 3.0", "timeout": 2})
	_expect(reached.contains("became true"), "game_wait: condición cumplida · " + reached)
	var timed_out := await _call_text("game_wait", {"condition": "score > 100", "timeout": 0.3})
	_expect(timed_out.contains("Timed out") and timed_out.contains("false"), "game_wait: se vence · " + timed_out)
	var bad_condition: Dictionary = await _call("game_wait", {"condition": "nada_de_nada +", "timeout": 1})
	_expect(bad_condition.get("isError", false), "game_wait: condición rota → error · " + _text(bad_condition))
	# La señal llega mientras se espera: un game_call en paralelo la dispara.
	var box: Dictionary = {}
	_call_into(box, "game_wait", {"signal": "scored", "timeout": 3})
	await _tree.create_timer(0.3).timeout
	await _call_text("game_call", {"path": "", "method": "add_score", "args": [2]})
	var deadline := Time.get_ticks_msec() + 5000
	while not box.has("text") and Time.get_ticks_msec() < deadline:
		await _tree.process_frame
	var emitted: String = box.get("text", "")
	_expect(emitted.contains("'scored' was emitted") and emitted.contains("(7)"), "game_wait: señal con argumentos · " + emitted)
	var played := await _call_text("game_input", {"steps": [{"action": "ui_accept"}, {"key": "Ctrl+S"}, {"click": [40, 30]}]})
	_expect(played.contains("Inputs: 7 of 7"), "game_input: todos los eventos · " + played)
	await _tree.create_timer(0.5).timeout
	_expect(_output_has("ctrl+s recibido") and _output_has("click 1 en (40.0, 30.0)") and _output_has("ui_accept soltado"), "game_input: el juego recibió tecla, click y acción")
	# Por frame de física (m14-01): sostenida exactamente hold_frames y con la fuerza pedida.
	var by_frame := await _call_text("game_input", {"steps": [{"frame": 5, "action": "ui_accept", "hold_frames": 9, "strength": 0.4}], "settle_frames": 3})
	_expect(by_frame.contains("Inputs: 2 of 2 played (by physics frame)"), "game_input por frame · " + by_frame)
	await _tree.create_timer(0.3).timeout
	_expect(_output_has("ui_accept sostenido 9 frames") and _output_has("ui_accept fuerza 0.40"), "game_input por frame: 9 frames y fuerza 0.4 en el juego")


## El juego con bugs plantados (M13).
func _check_playtest_game() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://.godot_agent/playtests"))
	var photos_before := DirAccess.get_files_at("res://.godot_agent/playtests")
	# Con tope de tiempo, como un Playtest: el segundo run_scene con tope hacía caer el editor (m16-03).
	RunTools.set_playtest_deadline(Time.get_ticks_msec() + 300000)
	await _call_text("run_scene", {"scene": GAME_SCENE, "seconds": 1, "continue_on_error": true, "film_fps": 5})
	var ran := await _call_text("run_scene", {"scene": GAME_SCENE, "seconds": 3.5, "continue_on_error": true, "film_fps": 5})
	_expect(ran.contains("Playtest time left"), "run_scene: dice cuánto queda · " + ran.right(200))
	RunTools.set_playtest_deadline(0)
	_expect(ran.contains("Now in the game") and ran.contains("Player: /root/PlaytestGame/Player") and ran.contains("HUD.Basket") and ran.contains("Filming: res://"), "run_scene: foto de lo que hay · " + ran.left(900))
	var found := await _call_text("game_find", {"class": "CharacterBody3D"})
	_expect(found.contains("/root/PlaytestGame/Player"), "game_find por clase · " + found)
	_expect((await _call_text("game_find", {"class": "group:player"})).contains("Player"), "game_find por grupo")
	_expect((await _call_text("game_find", {"name": "gat"})).contains("Gate"), "game_find por nombre")

	# UI (m15-09)
	var ui := await _call_text("game_ui", {})
	_expect(ui.contains("HUD.Start button \"Start\" at (") and ui.contains("HUD.Sound checkbox") and ui.contains("options=[\"Easy\",\"Hard\"]") and ui.contains("HUD.Basket: \"Basket 0 / 10\""), "game_ui: controles y textos · " + ui)
	var clicked := await _call_text("game_ui_act", {"id": "HUD.Start"})
	_expect(clicked.contains("Clicked") and (await _call_text("game_get", {"path": "", "properties": ["start_presses"]})).contains("start_presses = 1"), "game_ui_act: el clic aprieta el botón · " + clicked)
	var covered: Dictionary = await _call("game_ui_act", {"id": "HUD.Covered"})
	_expect(covered.get("isError", false) and _text(covered).contains("Overlay") and _text(covered).contains("could not press"), "game_ui_act: un overlay bloquea el clic · " + _text(covered))
	var chosen := await _call_text("game_ui_act", {"id": "HUD.Level", "value": "Hard"})
	_expect(chosen.contains("not by input"), "game_ui_act: elegir una opción avisa que no es input · " + chosen)

	# Input (m15-04): escribir y mirar con el mouse.
	await _call_text("game_ui_act", {"id": "HUD.Name", "action": "focus"})
	await _call_text("game_input", {"steps": [{"text": "Ana b"}]})
	var typed := await _call_text("game_get", {"path": "", "properties": ["last_text"]})
	_expect(typed.contains("Ana b"), "game_input text: escribe en el LineEdit · " + typed)
	await _call_text("game_ui_act", {"id": "HUD.Start"})  # saca el foco del LineEdit: si no, se come el mouse
	var before_look := await _call_text("game_get", {"path": "Player", "properties": ["rotation:y"]})
	await _call_text("game_input", {"steps": [{"look": [300, 0]}]})
	var after_look := await _call_text("game_get", {"path": "Player", "properties": ["rotation:y"]})
	_expect(before_look.contains("rotation:y = 0.0") and not after_look.contains("rotation:y = 0.0"), "game_input look: la mira gira · " + after_look)

	# Errores (m15-05): el clic dispara un error y el juego sigue.
	var mailbox := await _call_text("game_ui_act", {"id": "HUD.Mailbox"})
	await _tree.create_timer(0.5).timeout
	var after_mailbox := mailbox + await _call_text("game_get", {"path": "", "properties": ["basket"]})
	_expect(after_mailbox.contains("basket = 0") and after_mailbox.contains("queue_free"), "el juego sigue después de un error · " + after_mailbox)

	# Detectores y foto del momento (m15-07, m15-08)
	PlaytestMemory.new().mark_not_a_bug("nan:Lamp")
	var all_findings: String = await _call_text("game_call", {"path": "", "method": "collect", "args": [12]})
	all_findings += await _call_text("game_call", {"path": "", "method": "pull_lever"})
	all_findings += await _call_text("game_call", {"path": "", "method": "break_lamp"})
	all_findings += await _call_text("game_call", {"path": "", "method": "stutter"})
	var deadline := Time.get_ticks_msec() + 3000
	while Time.get_ticks_msec() < deadline:
		all_findings += await _call_text("game_wait", {"timeout": 0.3})
	_expect(all_findings.contains("[sig=hud_fraction:HUD.Basket]"), "detector: HUD por encima del máximo · " + all_findings.left(700))
	_expect(all_findings.contains("[sig=out_of_world:Gate]"), "detector: fuera del mundo · " + all_findings.right(600))
	_expect(all_findings.contains("Detector hitch"), "detector: frame largo")
	_expect(not all_findings.contains("nan:Lamp"), "no es un bug: ya no se reporta")
	# Saca una cada 5 s: puede ser de cualquier hallazgo del run, no siempre de estos.
	var new_photos := Array(DirAccess.get_files_at("res://.godot_agent/playtests")).filter(func(file: String) -> bool: return file.begins_with("finding_") and file.ends_with(".png") and not file in photos_before)
	_expect(not new_photos.is_empty(), "la foto del hallazgo queda en disco")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PlaytestMemory.DIR.path_join(PlaytestMemory.NOT_A_BUG_FILE)))

	# Pausa y avance por frames (m15-13)
	_expect((await _call_text("game_pause", {"paused": true})).contains("paused"), "game_pause")
	var ticks_before := _number_of(await _call_text("game_get", {"path": "", "properties": ["ticks"]}), "ticks")
	await _tree.create_timer(0.3).timeout
	_expect(_number_of(await _call_text("game_get", {"path": "", "properties": ["ticks"]}), "ticks") == ticks_before, "en pausa el juego no avanza")
	var stepped := await _call_text("game_step", {"frames": 10})
	_expect(_number_of(await _call_text("game_get", {"path": "", "properties": ["ticks"]}), "ticks") - ticks_before == 10 and stepped.contains("paused again"), "game_step avanza esos frames y vuelve a pausar · " + stepped)
	_expect((await _call_text("game_wait", {"condition": "false", "timeout": 0.1})).contains("The game is paused"), "game_wait en pausa lo avisa")
	var y_before := await _call_text("game_get", {"path": "Player", "properties": ["velocity:y"]})
	await _call_text("game_step", {"frames": 2, "steps": [{"action": "ui_accept", "hold_frames": 1}]})
	var y_after := await _call_text("game_get", {"path": "Player", "properties": ["velocity:y"]})
	_expect(y_before != y_after, "game_step: el input por frame llega · " + y_after)
	await _call_text("game_pause", {"paused": false})

	# game_script (m15-12, m15-14)
	var jumped := await _call_text("game_script", {"code": "func run(game):\n\tvar pressed = await game.press(\"ui_left\", 2)\n\tgame.say(\"moved\", pressed.ok)\n\treturn game.movement()"})
	_expect(jumped.contains("moved true") and jumped.contains("\"jump_speed\": 4.5") and jumped.contains("JUMP_VELOCITY"), "game_script: input, say y movement · " + jumped)
	var aimed := await _call_text("game_script", {"code": "func run(game):\n\tvar r = await game.look_at(Vector3(4, 1.5, -8))\n\treturn [r.ok, r.why]"})
	_expect(aimed.contains("[true") or aimed.contains("didn't get there"), "game_script: look_at mide y apunta · " + aimed)
	var syntax: Dictionary = await _call("game_script", {"code": "func run(game):\n\testo no compila"})
	_expect(syntax.get("isError", false) and _text(syntax).contains("does not compile"), "game_script: no compila → error · " + _text(syntax))
	var blocked: Dictionary = await _call("game_script", {"code": "func run(game):\n\tFileAccess.open(\"res://a\", FileAccess.WRITE)"})
	_expect(blocked.get("isError", false) and _text(blocked).contains("FileAccess"), "game_script: no puede tocar archivos")
	var crashed := await _call_text("game_script", {"code": "func run(game):\n\tvar nothing = null\n\tnothing.boom()\n\treturn 1"})
	_expect(crashed.contains("Script error") and (await _call_text("game_get", {"path": "", "properties": ["basket"]})).contains("basket"), "game_script: su error no frena el juego · " + crashed)
	var timed := await _call_text("game_script", {"code": "func run(game):\n\tgame.hold(\"ui_right\")\n\twhile true:\n\t\tawait game.wait_frames(1)", "timeout": 0.5})
	_expect(timed.contains("timed out") and timed.contains("paused"), "game_script: vencido suelta y pausa · " + timed)
	var free := await _call_text("game_script", {"code": "func run(game):\n\treturn Input.is_action_pressed(\"ui_right\")"})
	_expect(free.contains("returned: false"), "game_script: soltó lo que tenía apretado · " + free)
	await _call_text("game_pause", {"paused": false})

	# game_watch (m15-20)
	var watched := await _call_text("game_watch", {"paths": ["HUD/Flash", ""], "seconds": 0.6, "properties": ["ticks"], "steps": [{"action": "ui_accept"}]})
	_expect(watched.contains("Flash was hidden") and watched.contains("Flash was shown"), "game_watch: ve lo que dura 0,2 s · " + watched.left(500))

	# Filmación (m15-22, m15-23)
	await _tree.create_timer(0.6).timeout
	var frames: Dictionary = await _call("game_frames", {"seconds": 5, "count": 3})
	var images: Array = (frames.get("content", []) as Array).filter(func(block: Dictionary) -> bool: return block.get("type") == "image")
	_expect(images.size() == 3 and images[0].mimeType == "image/jpeg", "game_frames: los últimos frames · %d" % images.size())
	var film := RegEx.create_from_string("Filming: (res://\\S+)").search(ran)
	if film:
		_expect(FlipbookDialog.frames_of(film.get_string(1)).size() > 3, "la filmación queda en su carpeta")
		_expect(FlipbookDialog.open(film.get_string(1), _dock), "el reproductor abre la filmación")
		var player: Node = EditorInterface.get_base_control().get_children().filter(func(node: Node) -> bool: return node.get_script() == FlipbookDialog).back()
		await _tree.create_timer(0.5).timeout
		_expect(player.get(&"_index") > 0 and (player.get(&"_picture") as TextureRect).texture != null, "el reproductor avanza y muestra")
		player.queue_free()

	# Un breakpoint sí frena, aunque el run siga después de los errores (m16-05).
	var stopped_at: Dictionary = await _call("game_call", {"path": "", "method": "stop_here"})
	await _tree.create_timer(0.5).timeout
	_expect(stopped_at.get("isError", false) and _text(stopped_at).contains("debugger"), "un breakpoint frena el run · " + _text(stopped_at))
	var after_breakpoint: Dictionary = await _call("game_get", {"path": ""})
	_expect(after_breakpoint.get("isError", false) and _text(after_breakpoint).contains("stopped in the debugger"), "sigue parado en el breakpoint · " + _text(after_breakpoint))
	await _call_text("stop_scene", {})


static func _number_of(text: String, property: String) -> int:
	var found := RegEx.create_from_string("%s = (-?\\d+)" % property).search(text)
	return int(found.get_string(1)) if found else -999


## Llamada sin esperar: deja el texto en `box.text` cuando termina.
func _call_into(box: Dictionary, tool_name: String, arguments: Dictionary) -> void:
	box["text"] = await _call_text(tool_name, arguments)


## Si el reporte trae errores del juego o de scripts. En 4.6 y 4.7 el debugger atiende mensajes del
## editor en medio de la inicialización de las variables de un script y eso deja un error de get_node
## con ruta absoluta (del motor, también sin el harness; en 4.8 ya no pasa): no cuenta.
static func _game_errors(report: String) -> bool:
	for line: String in report.split("\n"):
		if (line.contains("[game/error]") or line.contains("/script]")) and not (line.contains("@implicit_new()") and line.contains("absolute paths from outside the active scene tree")):
			return true
	return false


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
