extends SceneTree
## Prueba manual contra Claude Code real (m7-36): abre una sesión sin `_meta` y otra con una skill
## apagada (SkillCatalog.session_settings), y en cada una le pregunta al modelo qué skills ve (dos
## turnos cortos): la apagada desaparece y los comandos que trae Claude Code siguen. Uso:
##   godot --headless --path <repo> --script tests/skills_session_check.gd [-- <skill de usuario o proyecto a apagar>]

const SessionController := preload("res://addons/godot_agent/session/session_controller.gd")
const SessionModel := preload("res://addons/godot_agent/session/session_model.gd")
const AgentLog := preload("res://addons/godot_agent/core/agent_log.gd")
const AgentProfile := preload("res://addons/godot_agent/core/agent_profile.gd")
const ChatEntry := preload("res://addons/godot_agent/session/chat_entry.gd")
const SkillCatalog := preload("res://addons/godot_agent/extensions/skill_catalog.gd")

const TIMEOUT_S := 180.0


func _initialize() -> void:
	await process_frame
	create_timer(TIMEOUT_S).timeout.connect(func() -> void:
		printerr("FAIL skills_session_check: timeout")
		quit(1))
	var model := SessionModel.new()
	var controller := SessionController.new()
	var project := ProjectSettings.globalize_path("res://").trim_suffix("/")
	controller.setup(model, AgentLog.new(), project)
	var profile: AgentProfile = AgentProfile.from_dict(AgentProfile.defaults()[0])
	var skills := SkillCatalog.scan(SkillCatalog.config_dir(profile.resolved_env()), project)
	print("skills en disco: ", skills.map(func(skill: Dictionary) -> String: return skill.id))
	if not await controller.start(profile):
		printerr("FAIL no arrancó: ", model.failure_message)
		quit(1)
		return
	var before := await _commands(model)
	print("comandos sin _meta: %d" % before.size())
	var seen_before := await _ask_skills(controller, model)
	print("el modelo ve: ", seen_before)
	var args := OS.get_cmdline_user_args()
	var target: String = args[0] if not args.is_empty() else (skills[0].id if not skills.is_empty() else "")
	var bundled := Array(before).filter(func(name: String) -> bool: return not skills.any(func(skill: Dictionary) -> bool: return skill.id == name))
	var failures: PackedStringArray = []
	if not before.has(target):
		failures.append("Claude Code no anunció %s; anunció: %s" % [target, before])
	var settings := SkillCatalog.session_settings(PackedStringArray([target]))
	controller.session_meta_provider = func() -> Dictionary: return {"claudeCode": {"options": {"settings": settings}}}
	model.commands = []
	if not await controller.open_session():
		printerr("FAIL la segunda sesión no abrió: ", model.failure_message)
		quit(1)
		return
	var after := await _commands(model)
	print("comandos con %s apagada: %d" % [target, after.size()])
	var seen_after := await _ask_skills(controller, model)
	print("el modelo ve: ", seen_after)
	if not seen_before.split("\n").has(target):
		failures.append("sin _meta, el modelo no nombró %s" % target)
	if seen_after.split("\n").has(target):
		failures.append("con %s apagada, el modelo la sigue viendo" % target)
	if after.has(target):
		failures.append("con %s apagada, sigue en el menú de comandos" % target)
	for name: String in bundled:
		if not after.has(name):
			failures.append("desapareció el comando %s, que no estaba apagado" % name)
	controller.stop()
	if failures.is_empty():
		print("PASS skills_session_check: %s oculta, %d comandos de Claude Code siguen" % [target, bundled.size()])
		quit(0)
	else:
		printerr("FAIL skills_session_check:\n  " + "\n  ".join(failures))
		quit(1)


## Le pregunta al modelo qué skills con «patterns» en el nombre puede usar (un turno corto).
func _ask_skills(controller: SessionController, model: SessionModel) -> String:
	await controller.send_prompt("Without using any tool: list the exact names of the skills you can invoke with the Skill tool whose name contains \"patterns\", one per line, nothing else.")
	var text := ""
	for entry: ChatEntry in model.entries():
		if entry.kind == ChatEntry.EntryKind.AGENT:
			text = str(entry.text)
	return text.strip_edges()


## Nombres de los comandos que anuncia la sesión (llegan un rato después de session/new).
func _commands(model: SessionModel) -> PackedStringArray:
	for i in 100:
		if not model.commands.is_empty():
			break
		await create_timer(0.1).timeout
	await create_timer(1.0).timeout  # por si llega una actualización más completa
	var names: PackedStringArray = []
	for command: Variant in model.commands:
		if command is Dictionary:
			names.append(str(command.get("name", "")))
	return names
