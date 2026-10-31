@tool
extends RefCounted
## Corre tests/playtest_suite.json con un agente real (m16-03): manda cada pedido como lo manda
## «Playtest…» en Revisar y compara el veredicto con el esperado. Gasta cuota: no entra en CI.
## Deja el detalle en tests/tmp/playtest_suite_result.json.

const ReviewStore := preload("res://addons/godot_agent/review/review_store.gd")
const PlaytestMemory := preload("res://addons/godot_agent/review/playtest_memory.gd")
const AgentProfile := preload("res://addons/godot_agent/core/agent_profile.gd")
const SessionModel := preload("res://addons/godot_agent/session/session_model.gd")
const ChatEntry := preload("res://addons/godot_agent/session/chat_entry.gd")
const PermissionPolicy := preload("res://addons/godot_agent/session/permission_policy.gd")

const DOCK_SCRIPT := "res://addons/godot_agent/ui/dock/agent_dock.gd"
const SUITE := "res://tests/playtest_suite.json"
const RESULT := "res://tests/tmp/playtest_suite_result.json"
const SCENE := "res://tests/fixtures/playtest_game/playtest_game.tscn"
const MINUTES := 5
const RUN_ARGS_ENV := "GODOT_AGENT_TEST_RUN_ARGS"
const RUN_ARGS_SETTING := "editor/run/main_run_args"
## Un poco más que el tope: el agente tiene que poder contestar al vencerse.
const TURN_TIMEOUT_S := MINUTES * 60.0 + 120.0
const VERDICTS := {"Playtest: passed": "pass", "Playtest: failed": "fail", "Playtest: could not test": "blocked", "Playtest: explored": "explored"}

var failures: PackedStringArray = []


## `only`: ids separados por coma ("" = todos).
func run(tree: SceneTree, profile: AgentProfile, only: String) -> PackedStringArray:
	var dock: Node = null
	for node: Node in tree.root.find_children("*", "Node", true, false):
		var script := node.get_script() as Script
		if script and script.resource_path == DOCK_SCRIPT:
			dock = node
	if dock == null:
		failures.append("no se encontró el dock")
		return failures
	var controller: Object = dock.get(&"_controller")
	var model: Object = dock.get(&"_model")
	var suite: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SUITE))
	var wanted := only.split(",", false)
	# Bajo Xvfb el juego necesita estos argumentos, como en run_check; si no, se cierra al arrancar.
	var previous_args: Variant = ProjectSettings.get_setting(RUN_ARGS_SETTING, "")
	if not OS.get_environment(RUN_ARGS_ENV).is_empty():
		ProjectSettings.set_setting(RUN_ARGS_SETTING, OS.get_environment(RUN_ARGS_ENV))
	var results: Array[Dictionary] = []
	for item: Dictionary in suite.prompts:
		if not wanted.is_empty() and not str(item.id) in wanted:
			continue
		# En frío: lo que aprendió un pedido no ayuda al siguiente.
		for file: String in [PlaytestMemory.NOTES_FILE, PlaytestMemory.SEEN_FILE]:
			DirAccess.remove_absolute(ProjectSettings.globalize_path(PlaytestMemory.DIR.path_join(file)))
		results.append(await _run_one(tree, dock, controller, model, profile, item))
		var last := results[-1]
		print("[playtest-suite] %s esperado=%s obtenido=%s %.0f s · %s" % [last.id, last.expected, last.got, last.seconds, last.prompt])
		if last.got != last.expected:
			failures.append("%s: esperado %s, obtenido %s" % [last.id, last.expected, last.got])
	ProjectSettings.set_setting(RUN_ARGS_SETTING, previous_args)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(RESULT.get_base_dir()))
	var file := FileAccess.open(RESULT, FileAccess.WRITE)
	file.store_string(JSON.stringify(results, "\t"))
	file.close()
	return failures


## Un playtest tiene que jugar: si el agente pide aprobar un plan no va a seguir solo, y esperar gasta cuota.
static func _waits_for_plan(model: Object) -> bool:
	for entry: ChatEntry in model.call(&"entries"):
		if entry.kind == ChatEntry.EntryKind.TOOL_GROUP:
			for id: String in entry.tool_call_ids:
				var call: Object = model.call(&"tool_call", id)
				if call and str(call.get(&"title")) == "Approve Plan" and not call.call(&"is_finished"):
					return true
	return false


func _run_one(tree: SceneTree, dock: Node, controller: Object, model: Object, profile: AgentProfile, item: Dictionary) -> Dictionary:
	var started := Time.get_ticks_msec()
	var result := {"id": item.id, "prompt": item.prompt, "expected": item.get("expected", ""), "got": "(no verdict)", "seconds": 0.0, "notice": "", "tools": []}
	if not await controller.call(&"start", profile):
		result.got = "(no session: %s)" % model.get(&"failure_message")
		return result
	model.call(&"set_harness_mode", SessionModel.HarnessMode.REVIEW)
	# Lo que el usuario concede en la tarjeta de permiso.
	(controller.get(&"policy") as Object).call(&"grant_for_session", PermissionPolicy.GROUP_RUN)
	dock.call(&"_on_submitted", ReviewStore.playtest_prompt("%s. The scene is %s." % [item.prompt, SCENE], false, MINUTES))
	var deadline := Time.get_ticks_msec() + int(TURN_TIMEOUT_S * 1000.0)
	await tree.create_timer(1.0).timeout
	var waiting_plan := false
	var seen_mode := ""
	var modes: PackedStringArray = []
	for mode: Variant in model.get(&"agent_modes"):
		modes.append(str(mode.get("id", "")) if mode is Dictionary else str(mode))
	print("[playtest-suite] modos del agente: %s" % ", ".join(modes))
	while int(model.get(&"state")) != SessionModel.SessionState.READY and Time.get_ticks_msec() < deadline and not waiting_plan:
		await tree.create_timer(0.25).timeout
		waiting_plan = _waits_for_plan(model)
		if str(model.get(&"current_agent_mode")) != seen_mode:
			seen_mode = str(model.get(&"current_agent_mode"))
			print("[playtest-suite] modo a los %.1f s: %s" % [(Time.get_ticks_msec() - started) / 1000.0, seen_mode])
	result["agent_mode"] = model.get(&"current_agent_mode")
	if waiting_plan:
		result.got = "(asked to approve a plan)"
		controller.call(&"cancel")
	elif int(model.get(&"state")) != SessionModel.SessionState.READY:
		result.got = "(timed out)"
		controller.call(&"cancel")
	for entry: ChatEntry in model.call(&"entries"):
		if entry.kind == ChatEntry.EntryKind.NOTICE:
			for title: String in VERDICTS:
				if entry.text.begins_with(title):
					result.got = VERDICTS[title]
					result.notice = entry.text
		elif entry.kind == ChatEntry.EntryKind.TOOL_GROUP:
			for id: String in entry.tool_call_ids:
				var call: Object = model.call(&"tool_call", id)
				if call:
					result.tools.append("%s:%s" % [call.call(&"display_name"), call.get(&"status")])
		elif entry.kind == ChatEntry.EntryKind.AGENT and result.got == "(no verdict)":
			result["last_text"] = entry.text.right(600)
	result.seconds = (Time.get_ticks_msec() - started) / 1000.0
	result["usage"] = controller.get(&"last_turn_usage")
	controller.call(&"stop")
	await tree.create_timer(1.0).timeout
	if EditorInterface.is_playing_scene():
		EditorInterface.stop_playing_scene()
	return result
