@tool
extends RefCounted
## ui-path-rules (m11-25) con el agente falso (tests/scripts/ui_path_rules.json):
## 1. Una regla temporal en .agents/rules (trigger: glob) para los .gdshader de tests/tmp/path_rules.
## 2. El agente edita water.gdshader con una tool propia (tool_call con locations).
## 3. El próximo prompt lleva la regla, como bloque del harness sin sobre, y el chat la muestra como
##    adjunto «rules: …»; el siguiente ya no la lleva.

const PathRules := preload("res://addons/godot_agent/core/path_rules.gd")
const MAIN_PLUGIN_SCRIPT := "res://addons/godot_agent/agent_plugin.gd"
const RULE := "res://.agents/rules/zz_path_rules_check.md"
const WAIT_S := 30.0

var failures: Array[String] = []
var _tree: SceneTree


func run(tree: SceneTree, plugin: Object, dock: Control, shot_path: String) -> Array[String]:
	_tree = tree
	var created_dir := not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(RULE.get_base_dir()))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(RULE.get_base_dir()))
	var file := FileAccess.open(RULE, FileAccess.WRITE)
	file.store_string("---\ntrigger: glob\nglobs: tests/tmp/path_rules/*.gdshader\n---\nEvery float uniform takes a hint_range.\n")
	file.close()
	await _check(plugin, dock, shot_path)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(RULE))
	if created_dir:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(RULE.get_base_dir()))
		DirAccess.remove_absolute(ProjectSettings.globalize_path(RULE.get_base_dir().get_base_dir()))
	return failures


func _check(plugin: Object, dock: Control, shot_path: String) -> void:
	var model: Object = dock.get(&"_model")
	var log: Object = plugin.get(&"_log")
	var prompts: Array[String] = []
	for text: String in ["Fix the water shader", "Now the uniforms", "Anything else?"]:
		var first_log := (log.call(&"entries") as Array).size()
		dock.call(&"_on_submitted", text)
		var deadline := Time.get_ticks_msec() + int(WAIT_S * 1000)
		while Time.get_ticks_msec() < deadline and (model.call(&"is_busy") or _prompt_since(log, first_log).is_empty()):
			await _tree.process_frame
		prompts.append(_prompt_since(log, first_log))
	_expect(not prompts[0].contains(PathRules.BLOCK_HEADER), "el primer prompt no lleva reglas")
	_expect(prompts[1].contains(PathRules.BLOCK_HEADER) and prompts[1].contains("Every float uniform takes a hint_range.") and prompts[1].contains("(from .agents/rules/zz_path_rules_check.md)"),
		"el prompt después de editar el shader lleva la regla: %s" % prompts[1].left(400))
	_expect(not prompts[1].contains("zz_path_rules_check.md\n<untrusted"), "sin sobre")
	_expect(not prompts[2].contains(PathRules.BLOCK_HEADER), "el siguiente ya no")
	var users: Array = (model.call(&"entries") as Array).filter(func(e: Variant) -> bool: return int(e.get(&"kind")) == 0)
	_expect(users.size() >= 2 and (users[1].get(&"attachments") as Array).any(func(b: Dictionary) -> bool: return str(b.get("text", "")).begins_with(PathRules.BLOCK_HEADER)), "el chat lo muestra como adjunto")
	if not shot_path.is_empty():
		for i in 10:
			await _tree.process_frame
		dock.get_viewport().get_texture().get_image().save_png(shot_path.get_basename() + "_path_rules.png")


func _prompt_since(log: Object, first: int) -> String:
	for entry: Dictionary in (log.call(&"entries") as Array).slice(first):
		if str(entry.message).contains("fake_agent: prompt"):
			return str(entry.message)
	return ""


func _expect(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
