extends "test_case.gd"
## Reglas por archivo (m11-25): los tres formatos, los globs, qué se manda y cuándo.

const PathRules := preload("res://addons/godot_agent/core/path_rules.gd")
const AgentLog := preload("res://addons/godot_agent/core/agent_log.gd")
const SessionController := preload("res://addons/godot_agent/session/session_controller.gd")
const SessionModel := preload("res://addons/godot_agent/session/session_model.gd")
const ChatEntry := preload("res://addons/godot_agent/session/chat_entry.gd")
const ToolRegistry := preload("res://addons/godot_agent/mcp/tool_registry.gd")
const McpTool := preload("res://addons/godot_agent/mcp/mcp_tool.gd")
const InstructionsTab := preload("res://addons/godot_agent/ui/extensions/instructions_tab.gd")

const SHADERS := "---\ntrigger: glob\nglobs: \"*.gdshader, shaders/**\"\ndescription: Shader rules\n---\nUse `hint_range` on every float uniform.\n"
const UI := "---\npaths:\n  - \"ui/**/*.tscn\"\n  - ui/theme.tres\n---\n# UI\nAnchor every Control; use the project Theme.\n"
const CSHARP := "---\ndescription: C# rules\nglobs: [\"**/*.cs\", \"*.{csproj,sln}\"]\nalwaysApply: false\n---\nPartial classes only.\n"


func _project(name: String) -> String:
	var dir := ProjectSettings.globalize_path(temp_dir("path_rules_" + name))
	for sub: String in [".agents/rules", ".claude/rules/frontend", ".cursor/rules"]:
		DirAccess.make_dir_recursive_absolute(dir.path_join(sub))
	_write(dir.path_join(".agents/rules/shaders.md"), SHADERS)
	_write(dir.path_join(".agents/rules/always.md"), "---\ntrigger: always_on\n---\nAlways.\n")
	_write(dir.path_join(".agents/rules/broken.md"), "No front matter.\n")
	_write(dir.path_join(".claude/rules/frontend/ui.md"), UI)
	_write(dir.path_join(".claude/rules/general.md"), "Loaded at launch, no paths.\n")
	_write(dir.path_join(".cursor/rules/csharp.mdc"), CSHARP)
	_write(dir.path_join(".cursor/rules/always.mdc"), "---\nglobs: \"*.gd\"\nalwaysApply: true\n---\nAlways.\n")
	return dir


func _write(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()


func test_frontmatter_and_formats() -> void:
	var parsed := PathRules.frontmatter(UI)
	assert_eq(parsed.fields.paths, ["ui/**/*.tscn", "ui/theme.tres"], "lista con guiones")
	assert_true(str(parsed.body).begins_with("# UI"), "el cuerpo sin el front matter")
	assert_eq(PathRules.parse_rule(SHADERS, "antigravity").globs, PackedStringArray(["*.gdshader", "shaders/**"]), "globs separados por comas")
	assert_eq(PathRules.parse_rule(CSHARP, "cursor").globs, PackedStringArray(["**/*.cs", "*.{csproj,sln}"]), "lista entre corchetes, con llaves")
	assert_true(PathRules.parse_rule("---\ntrigger: manual\nglobs: x\n---\nbody", "antigravity").is_empty(), "manual no cuenta")
	assert_true(PathRules.parse_rule("---\npaths: []\n---\nbody", "claude").is_empty(), "sin patrones no es por archivo")
	var rules := PathRules.load_rules(_project("load"))
	var files := rules.map(func(r: Dictionary) -> String: return r.file)
	assert_eq(files, [".claude/rules/frontend/ui.md", ".agents/rules/shaders.md", ".cursor/rules/csharp.mdc"], "solo las reglas por glob, de las tres carpetas: %s" % [files])
	assert_eq(rules.map(func(r: Dictionary) -> String: return r.native), ["claude", "antigravity", "cursor"])


func test_globs() -> void:
	var rule := {"globs": PackedStringArray(["*.gdshader"])}
	assert_true(PathRules.matches(rule, "fx/water.gdshader"), "sin / vale en cualquier carpeta")
	assert_true(PathRules.matches(rule, "water.gdshader"))
	assert_false(PathRules.matches(rule, "water.gdshaderinc"))
	rule.globs = PackedStringArray(["ui/**/*.tscn"])
	assert_true(PathRules.matches(rule, "ui/menu.tscn"), "** también cero carpetas")
	assert_true(PathRules.matches(rule, "ui/a/b/menu.tscn"))
	assert_false(PathRules.matches(rule, "levels/ui/menu.tscn"), "anclado a la raíz")
	rule.globs = PackedStringArray(["res://scripts/*.{gd,cs}"])
	assert_true(PathRules.matches(rule, "scripts/player.cs"), "res:// y llaves")
	assert_false(PathRules.matches(rule, "scripts/ai/player.gd"), "* no cruza carpetas")
	assert_eq(PathRules.relative("res://a/b.gd", "/p"), "a/b.gd")
	assert_eq(PathRules.relative("/p/a/b.gd", "/p"), "a/b.gd")
	assert_eq(PathRules.relative("file:///p/a.gd", "/p/"), "a.gd")
	assert_eq(PathRules.relative("/other/a.gd", "/p"), "", "de afuera del proyecto no")
	assert_eq(PathRules.paths_in_text("Fix @res://fx/water.gdshader, and `res://ui/menu.tscn`."), PackedStringArray(["res://fx/water.gdshader", "res://ui/menu.tscn"]))


func test_pending_and_block() -> void:
	var rules := PathRules.load_rules(_project("pending"))
	var paths := PackedStringArray(["fx/water.gdshader", "ui/menu.tscn", "Player.cs"])
	var for_codex := PathRules.pending(rules, paths, "codex", {})
	assert_eq(for_codex.size(), 3, "Codex no carga ninguna sola")
	var for_claude := PathRules.pending(rules, paths, "claude", {})
	assert_false(for_claude.any(func(r: Dictionary) -> bool: return r.file.begins_with(".claude/")), "Claude Code ya carga .claude/rules")
	assert_eq(for_claude.size(), 2)
	var sent := {".agents/rules/shaders.md": rules[1].hash}
	assert_eq(PathRules.pending(rules, paths, "codex", sent).size(), 2, "la ya mandada no vuelve")
	assert_eq(PathRules.pending(rules, paths, "codex", {".agents/rules/shaders.md": "old"}).size(), 3, "si cambió, vuelve")
	var built := PathRules.block(for_codex)
	assert_true(str(built.text).begins_with(PathRules.BLOCK_HEADER), built.text)
	assert_true(str(built.text).contains("### Project rules for *.gdshader, shaders/** (from .agents/rules/shaders.md)\nUse `hint_range`"), built.text)
	assert_false(str(built.text).contains("untrusted"), "como CLAUDE.md: sin sobre")
	var small := PathRules.block(for_codex, 260)
	assert_true(small.sent.size() < 3 and str(small.text).contains("didn't fit here"), "lo que no entra queda nombrado: %s" % small.text)


func test_controller_sends_once() -> void:
	var dir := _project("controller")
	var sent: Array = []
	var controller := SessionController.new()
	controller.setup(SessionModel.new(), AgentLog.new(), dir)
	controller.model.session_id = "s"
	controller.model.set_state(SessionModel.SessionState.READY)
	controller.adapter.kind = "codex"
	controller.client.setup(func(line: String) -> bool:
		sent.append(JSON.parse_string(line))
		return true, controller.agent_log)
	controller.send_prompt("Hello")
	await _end_turn(controller)
	assert_false(_prompt_text(sent).contains(PathRules.BLOCK_HEADER), "sin archivos, sin reglas")
	# El agente edita un shader con su propia tool, y lee una escena con una tool godot.*.
	controller.model.apply_update({"sessionUpdate": "tool_call", "toolCallId": "edit", "title": "Edit water.gdshader", "status": "completed",
		"locations": [{"path": dir.path_join("fx/water.gdshader")}]})
	controller.model.apply_update({"sessionUpdate": "tool_call", "toolCallId": "scene", "title": "godot.get_scene_tree", "status": "completed",
		"rawInput": {"scene_path": "res://ui/menu.tscn"}})
	var touched := controller.touched_paths(0)
	touched.sort()
	assert_eq(touched, PackedStringArray(["fx/water.gdshader", "ui/menu.tscn"]), "lo que tocaron sus tools")
	controller.send_prompt("Next")
	await _end_turn(controller)
	var text := _prompt_text(sent)
	assert_true(text.contains("(from .agents/rules/shaders.md)") and text.contains("(from .claude/rules/frontend/ui.md)"), "las dos reglas en el próximo prompt: %s" % text.left(300))
	assert_true(text.find(PathRules.BLOCK_HEADER) < text.find("Next"), "antes del pedido")
	var user: Array = controller.model.entries().filter(func(e: ChatEntry) -> bool: return e.kind == ChatEntry.EntryKind.USER)
	assert_true((user[-1].attachments as Array).any(func(b: Dictionary) -> bool: return str(b.get("text", "")).begins_with(PathRules.BLOCK_HEADER)), "el chat lo muestra como adjunto")
	# Otra vez el mismo shader: ya se mandó.
	controller.model.apply_update({"sessionUpdate": "tool_call", "toolCallId": "edit2", "title": "Edit water.gdshader", "status": "completed",
		"locations": [{"path": dir.path_join("fx/water.gdshader")}]})
	controller.send_prompt("Again, with @res://scripts/Player.cs")
	await _end_turn(controller)
	text = _prompt_text(sent)
	assert_false(text.contains("shaders.md"), "una vez por sesión")
	assert_true(text.contains("(from .cursor/rules/csharp.mdc)"), "una mención del pedido también cuenta")
	# Apagado en Settings: nada.
	controller.path_rules_on = func() -> bool: return false
	_write(dir.path_join(".agents/rules/shaders.md"), SHADERS + "Changed.\n")
	controller.send_prompt("Off, res://fx/water.gdshader")
	await _end_turn(controller)
	assert_false(_prompt_text(sent).contains(PathRules.BLOCK_HEADER), "apagado")
	controller.path_rules_on = Callable()
	controller.send_prompt("On, res://fx/water.gdshader")
	await _end_turn(controller)
	assert_true(_prompt_text(sent).contains("Changed."), "la regla cambiada se manda de nuevo")
	controller.client.fail_all_pending("end of test")


func test_rules_in_tool_result() -> void:
	var dir := _project("tool")
	var controller := SessionController.new()
	controller.setup(SessionModel.new(), AgentLog.new(), dir)
	controller.adapter.kind = "codex"
	var registry := ToolRegistry.new()
	registry.agent_log = AgentLog.new()
	registry.register(McpTool.create("read_file", "read", "Lee", {"path": {"type": "string"}}, ["path"], func(args: Dictionary) -> String: return "contents of " + str(args.path)))
	registry.result_note = func(_caller: String, _tool: String, args: Dictionary) -> String: return controller.path_rules_for_tool(args)
	var result: Dictionary = await registry.call_tool("read_file", {"path": "res://fx/water.gdshader"})
	var texts := PackedStringArray((result.content as Array).map(func(b: Dictionary) -> String: return str(b.get("text", ""))))
	assert_eq(texts.size(), 2, "el resultado y las reglas")
	assert_true(texts[-1].begins_with(PathRules.BLOCK_HEADER) and texts[-1].contains("hint_range"), texts[-1])
	assert_false(texts[-1].contains("<untrusted"), "fuera de los sobres del resultado")
	result = await registry.call_tool("read_file", {"path": "res://fx/water.gdshader"})
	assert_eq((result.content as Array).size(), 1, "una vez por sesión")
	assert_true(controller.path_rules_block("res://fx/water.gdshader").is_empty(), "y el próximo prompt no la repite")


func test_instructions_tab() -> void:
	assert_true(InstructionsTab.rule_summary(".agents/rules/shaders.md", SHADERS).contains("*.gdshader, shaders/**") and InstructionsTab.rule_summary(".agents/rules/shaders.md", SHADERS).contains("Google Antigravity"), "patrones y quién la lee sola")
	assert_eq(InstructionsTab.rule_summary("AGENTS.md", SHADERS), "", "AGENTS.md no es una regla por archivo")
	assert_eq(InstructionsTab.rule_summary(".agents/rules/always.md", "---\ntrigger: always_on\n---\nx"), "")
	for dir: String in InstructionsTab.RULE_TEMPLATES:
		var format: String = PathRules.SOURCES.filter(func(s: Dictionary) -> bool: return s.dir == dir)[0].format
		assert_eq(PathRules.parse_rule(InstructionsTab.RULE_TEMPLATES[dir] + "Rule text.", format).globs, PackedStringArray(["**/*.gdshader"]), "la plantilla de %s es una regla por archivo" % dir)
	var tab := InstructionsTab.new()
	tab.project_path = _project("tab")
	var statuses: Array = []
	tab.status_changed.connect(func(text: String, _color: Color) -> void: statuses.append(text))
	assert_eq(tab.test_rules("res://fx/water.gdshader"), PackedStringArray([".agents/rules/shaders.md (Google Antigravity)"]))
	assert_eq(tab.test_rules("ui/menu.tscn").size(), 1, "sin res:// también")
	assert_true(tab.test_rules("main.gd").is_empty() and str(statuses[-1]).contains("No rule"), str(statuses[-1]))
	tab.free()


func _prompt_text(sent: Array) -> String:
	var prompts := sent.filter(func(m: Variant) -> bool: return m is Dictionary and m.get("method") == "session/prompt")
	if prompts.is_empty():
		return ""
	return "\n".join(PackedStringArray((prompts[-1].params.prompt as Array).map(func(b: Dictionary) -> String: return str(b.get("text", "")))))


func _end_turn(controller: SessionController) -> void:
	controller.client.fail_all_pending("end of turn")
	for i in 2:
		await Engine.get_main_loop().process_frame
	controller.model.set_state(SessionModel.SessionState.READY)
