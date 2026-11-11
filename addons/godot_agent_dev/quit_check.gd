@tool
extends RefCounted
## Cerrar el editor no deja procesos del agente (tests/quit_check.sh). Un agente falso que no sale
## al cerrarse stdin y lanza un hijo de larga vida (como npx → node) corre en tres lugares: la sesión
## principal, una pestaña de sesión más y un AgentProcess suelto que solo suelta su dueño al liberarse
## (como el de un hook o una terminal). Anota los pids del agente y de sus hijos en PIDS y cierra el
## editor como lo cierra el usuario; el script de shell mira después que no quede ninguno.

const AgentProfile := preload("res://addons/godot_agent/core/agent_profile.gd")
const AgentProcess := preload("res://addons/godot_agent/transport/agent_process.gd")
const ProcessTree := preload("res://addons/godot_agent/transport/process_tree.gd")
const PLUGIN_SCRIPT := "res://addons/godot_agent/agent_plugin.gd"
const SCENARIO := "res://tests/scripts/quit.json"
const PIDS := "res://tests/tmp/quit_pids.txt"
const WAIT_MS := 15000

var failures: PackedStringArray = []


## `owner` guarda el proceso suelto: se libera con él al cerrar el editor.
func run(tree: SceneTree, dock: Control, owner: Object) -> PackedStringArray:
	var plugin: Node = null
	for node: Node in tree.root.find_children("*", "Node", true, false):
		if node.get_script() and (node.get_script() as Script).resource_path == PLUGIN_SCRIPT:
			plugin = node
	if plugin == null:
		failures.append("no se encontró el plugin")
		return failures
	var pids: Array[int] = []
	var main: Object = dock.get(&"_controller")
	if not await main.call(&"start", _profile()):
		failures.append("la sesión principal no arrancó")
		return failures
	pids.append(_process_pid(main))
	var tab_id: String = plugin.call(&"_create_session_tab")
	var tab: Object = (plugin.get(&"_extra_sessions") as Dictionary)[tab_id].controller
	if not await tab.call(&"start", _profile()):
		failures.append("la pestaña de sesión no arrancó")
		return failures
	pids.append(_process_pid(tab))
	var loose := AgentProcess.new()
	var profile := _profile()
	if not loose.start(profile.command, profile.args):
		failures.append("el proceso suelto no arrancó: %s" % loose.last_error())
		return failures
	owner.set_meta(&"quit_check_process", loose)
	pids.append(loose.pid())
	var all: Array[int] = []
	for pid: int in pids:
		if pid <= 0:
			failures.append("un agente no tiene pid")
			return failures
		all.append(pid)
		var deadline := Time.get_ticks_msec() + WAIT_MS
		while ProcessTree.descendants(pid).is_empty() and Time.get_ticks_msec() < deadline:
			await tree.create_timer(0.2).timeout
		var children := ProcessTree.descendants(pid)
		if children.is_empty():
			failures.append("el agente %d no lanzó su hijo" % pid)
		all.append_array(Array(children))
	var file := FileAccess.open(PIDS, FileAccess.WRITE)
	file.store_string(" ".join(all.map(func(pid: int) -> String: return str(pid))))
	file.close()
	print("[quit-check] procesos: %s" % [all])
	return failures


static func _profile() -> AgentProfile:
	return AgentProfile.from_dict({"id": "fake", "display_name": "Agente falso", "command": OS.get_executable_path(),
		"args": ["--headless", "--no-header", "--path", ProjectSettings.globalize_path("res://"),
			"--script", "res://tests/fake_agent.gd", "--", "--scenario=" + SCENARIO]})


static func _process_pid(controller: Object) -> int:
	var process: Object = controller.get(&"_process")
	return int(process.call(&"pid")) if process else 0
