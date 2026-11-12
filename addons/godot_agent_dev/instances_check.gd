@tool
extends RefCounted
## m11-50 en el editor: run_scene con dos instancias de un juego ENet (tests/fixtures/instances), por el
## registry y en Auto, como las llama el agente.
## 1. run_scene con instances [{args: [--client]}]: la 2 arranca con su probe y su error sale como game#2.
## 2. game_get en la 1 ve al cliente conectado y en la 2 ve que se conectó; cada una con su user://.
## 3. capture_game_frame de la 2 da su ventana (640×360).
## 4. game_instance list las muestra; stop 2 → el server ve la desconexión; add vuelve a entrar.
## 0. suite.sh deja el puerto 6007 tomado, como otro editor abierto: las extra van al de este editor.
## 5. Una instancia que no corre da error. Stop corta todas: ningún proceso queda vivo, y el autoload
##    de playtest no queda en project.godot.

const SessionModel := preload("res://addons/godot_agent/session/session_model.gd")
const PlaytestAutoload := preload("res://addons/godot_agent/playtest/playtest_autoload.gd")
const GameInstances := preload("res://addons/godot_agent/playtest/game_instances.gd")
const PLUGIN_SCRIPT := "res://addons/godot_agent/agent_plugin.gd"
const SCENE := "res://tests/fixtures/instances/main.tscn"
const WAIT_MS := 20000

var failures: PackedStringArray = []
var _tree: SceneTree
var _plugin: Node
var _registry: Object


func run(tree: SceneTree) -> PackedStringArray:
	_tree = tree
	for node: Node in tree.root.find_children("*", "Node", true, false):
		if node.get_script() and (node.get_script() as Script).resource_path == PLUGIN_SCRIPT:
			_plugin = node
	if _plugin == null:
		return PackedStringArray(["no se encontró el plugin"])
	_registry = _plugin.get(&"_registry")
	var model: SessionModel = _plugin.get(&"_model")
	var saved_mode := model.harness_mode
	model.set_harness_mode(SessionModel.HarnessMode.AUTO)  # run allow: sin tarjetas
	OS.set_environment("GODOT_AGENT_FIXTURE_PORT", str(20000 + randi() % 20000))
	await _run()
	OS.unset_environment("GODOT_AGENT_FIXTURE_PORT")
	var instances: Object = _plugin.get(&"_run_tools").get(&"instances")
	var pids: Array = (instances.get(&"entries") as Dictionary).values().map(func(e: Dictionary) -> int: return int(e.pid))
	await _call("stop_scene", {})
	instances.call(&"stop_all")
	model.set_harness_mode(saved_mode)
	for pid: int in pids:
		_expect(not OS.is_process_running(pid), "el proceso %d de una instancia sigue vivo" % pid)
	return failures


func _run() -> void:
	var report := await _call("run_scene", {"scene": SCENE, "seconds": 3, "instances": [{"args": ["--client"]}]})
	_expect(report.contains("Instance 2 is running"), "la instancia 2 no arrancó · %s" % report.replace("\n", " ¶ ").left(3000))
	_expect(report.contains("[game#2/error]") and report.contains("fixture client error"), "el error de la 2 no sale como game#2 · %s" % report.right(600))
	_expect(not PlaytestAutoload.is_registered(), "el autoload quedó en project.godot con el juego corriendo")
	# suite.sh toma el 6007: el debugger de este editor está en otro puerto, y la 2 tiene que haber ido ahí.
	var game_pid := int(_plugin.get(&"_run_tools").get(&"debugger").get(&"editor_game_pid"))
	var editor_uri := GameInstances.editor_debugger_uri(game_pid)
	print("[instances-check] el juego del editor (PID %d) usa el debugger en %s" % [game_pid, editor_uri])
	_expect(editor_uri.begins_with("tcp://"), "no se supo adónde se conectó el juego del editor (PID %d) · «%s»" % [game_pid, editor_uri])
	if not report.contains("Instance 2 is running"):
		return

	# 2. Las dos se ven.
	var server := ""
	await _until(func() -> bool:
		server = await _call("game_get", {"path": ".", "properties": ["role", "peer_count", "user_dir"]})
		return server.contains("peer_count = 1"), "el server no ve al cliente")
	server = await _call("game_get", {"path": ".", "properties": ["role", "peer_count", "user_dir"]})  # la lambda no cambia `server`
	var client := await _call("game_get", {"path": ".", "properties": ["role", "connected", "user_dir"], "instance": 2})
	_expect(server.contains("role = \"server\"") and client.contains("role = \"client\"") and client.contains("connected = true"), "server y cliente · %s · %s" % [server, client])
	_expect(client.contains("/instances/2") and not server.contains("/instances/"), "cada una con su user:// · %s · %s" % [server, client])

	# 3. La ventana de la 2.
	var frame: Dictionary = await _registry.call(&"call_tool", "capture_game_frame", {"instance": 2}, "")
	# Todos los bloques de texto: un error del editor entre llamadas (BadWindow de X11 bajo Xvfb) agrega
	# «New in the editor since your previous godot.* call…» después del de la captura.
	var caption := ""
	for block: Variant in frame.get("content", []):
		if block is Dictionary and block.get("type") == "text":
			caption += str(block.text) + "\n"
	_expect(not frame.get("isError", true) and caption.contains("640x360"), "la captura de la 2 · %s" % caption)

	# 4. list, stop y add.
	var listing := await _call("game_instance", {"action": "list"})
	_expect(listing.contains("Instance 1") and listing.contains("Instance 2: own window, --client"), "list · %s" % listing)
	var stopped := await _call("game_instance", {"action": "stop", "instance": 2})
	_expect(stopped.contains("Instance 2 stopped"), "stop · %s" % stopped)
	await _until(func() -> bool:
		server = await _call("game_get", {"path": ".", "properties": ["peer_count"]})
		return server.contains("peer_count = 0"), "el server no vio la desconexión de la 2")
	var added := await _call("game_instance", {"action": "add", "args": ["--client"]})
	_expect(added.contains("Instance 2 is running"), "add · %s" % added)
	await _until(func() -> bool:
		server = await _call("game_get", {"path": ".", "properties": ["peer_count"]})
		return server.contains("peer_count = 1"), "el cliente nuevo no se conectó")

	# 5. Una que no corre.
	var missing: Dictionary = await _registry.call(&"call_tool", "game_get", {"path": ".", "instance": 3}, "")
	_expect(missing.get("isError", false) and str(missing.content[0].text).contains("Instance 3 is not running"), "la 3 no corre · %s" % [missing])


## El texto de una tool (o el del error).
func _call(tool_name: String, args: Dictionary) -> String:
	var result: Dictionary = await _registry.call(&"call_tool", tool_name, args, "")
	var texts: PackedStringArray = []
	for block: Variant in result.get("content", []):
		if block is Dictionary and block.get("type") == "text":
			texts.append(str(block.text))
	return "\n".join(texts)


func _expect(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)


func _until(condition: Callable, failure: String) -> bool:
	var deadline := Time.get_ticks_msec() + WAIT_MS
	while Time.get_ticks_msec() < deadline:
		if await condition.call():
			return true
		await _tree.create_timer(0.3).timeout
	failures.append(failure)
	return false
