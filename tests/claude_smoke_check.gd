extends SceneTree
## Prueba manual contra un agente real (gasta tokens): conecta el perfil por defecto (Claude Code),
## manda "hola" y muestra la respuesta. Uso:
##   godot --headless --path <repo> --script tests/claude_smoke_check.gd [-- "<prompt>"]

const SessionController := preload("res://addons/godot_agent/session/session_controller.gd")
const SessionModel := preload("res://addons/godot_agent/session/session_model.gd")
const ChatEntry := preload("res://addons/godot_agent/session/chat_entry.gd")
const AgentLog := preload("res://addons/godot_agent/core/agent_log.gd")
const AgentProfile := preload("res://addons/godot_agent/core/agent_profile.gd")

const TIMEOUT_S := 180.0


func _initialize() -> void:
	await process_frame
	create_timer(TIMEOUT_S).timeout.connect(func() -> void:
		printerr("FAIL claude_smoke_check: timeout")
		quit(1)
	)
	var args := OS.get_cmdline_user_args()
	var prompt: String = args[0] if not args.is_empty() else "hola"
	var model := SessionModel.new()
	var log := AgentLog.new()
	log.entry_added.connect(func(entry: Dictionary) -> void:
		if entry.channel == AgentLog.CH_PROC:
			print("  [proc] ", str(entry.message).left(200))
		elif entry.channel == AgentLog.CH_QUOTA:
			print("  [quota] ", entry.message, "\n          ", str(entry.raw).left(600))
	)
	var controller := SessionController.new()
	controller.setup(model, log, ProjectSettings.globalize_path("res://").trim_suffix("/"))
	var profile: AgentProfile = AgentProfile.from_dict(AgentProfile.defaults()[0])
	print("perfil: ", profile.command_line())
	if not await controller.start(profile):
		printerr("FAIL no arrancó: ", model.failure_message)
		quit(1)
		return
	print("agente: %s · modos: %s · modelo: %s" % [model.agent_info, model.current_agent_mode, model.config_option("model").get("currentValue", "?")])
	var stop_reason: String = await controller.send_prompt(prompt)
	var reply := ""
	for entry: ChatEntry in model.entries():
		if entry.kind == ChatEntry.EntryKind.AGENT:
			reply += entry.text
	print("stopReason: %s · uso: %d/%d" % [stop_reason, model.usage_used, model.usage_size])
	print("respuesta: ", reply)
	controller.stop()
	quit(0 if stop_reason == "end_turn" and not reply.strip_edges().is_empty() else 1)
