@tool
extends RefCounted
## m7-36 de punta a punta, en una copia del proyecto y con un CLAUDE_CONFIG_DIR de prueba
## (tests/skills_check.sh): la pestaña Skills de Extensions lista la skill de usuario, la del plugin
## (sin interruptor) y sugiere las skills de Godot; apagar la de usuario la guarda en la config del
## proyecto y la sesión la manda como skillOverrides; crear, copiar al proyecto e importar un zip
## dejan sus carpetas en .claude/skills. Guarda capturas en `<prefijo>_*.png`.

const SkillCatalog := preload("res://addons/godot_agent/extensions/skill_catalog.gd")
const ProjectConfig := preload("res://addons/godot_agent/config/project_config.gd")
const AgentProfile := preload("res://addons/godot_agent/core/agent_profile.gd")

const MAIN_PLUGIN_SCRIPT := "res://addons/godot_agent/plugin.gd"
const TIMEOUT_MS := 20000

var _tree: SceneTree


func run(tree: SceneTree, dock: Control, prefix: String) -> PackedStringArray:
	_tree = tree
	var failures: PackedStringArray = []
	var button: Button = dock.get_node("Header").get_node_or_null("ExtensionsButton")
	button.pressed.emit()
	await tree.create_timer(0.5).timeout
	var window: AcceptDialog = null
	for node: Node in EditorInterface.get_base_control().get_children():
		if node is AcceptDialog and node.get(&"_skills_tab") != null:
			window = node
	if window == null or not window.visible:
		return ["el botón no abrió Extensions"]
	var tabs: TabContainer = window.get(&"_tabs")
	var tab: Control = window.get(&"_skills_tab")
	var opened: Array[String] = []
	tab.set(&"open_file", func(path: String) -> void: opened.append(path))
	tabs.current_tab = tab.get_index()
	await tree.create_timer(0.5).timeout
	var skills: Array = tab.get(&"_skills")
	var ids := skills.map(func(skill: Dictionary) -> String: return "%s/%s" % [skill.origin, skill.id])
	if ids != ["user/fake-user", "plugin/fakeplug:plug-skill"]:
		failures.append("skills listadas: %s" % [ids])
	var box: VBoxContainer = tab.get(&"_box")
	var toggles := box.find_children("*", "CheckButton", true, false)
	if toggles.size() != 1:
		failures.append("interruptores: %d (solo la de usuario lleva)" % toggles.size())
	if not box.find_children("*", "Label", true, false).any(func(label: Label) -> bool: return label.text == "Godot skills"):
		failures.append("no sugiere las skills de Godot")
	window.get_texture().get_image().save_png("%s_list.png" % prefix)
	# Apagar la de usuario: queda en la config del proyecto y la próxima sesión la manda.
	(toggles[0] as CheckButton).button_pressed = false
	await tree.process_frame
	var saved: Resource = ResourceLoader.load(ProjectConfig.PATH, "", ResourceLoader.CACHE_MODE_IGNORE)
	if saved == null or saved.get(&"disabled_skills") != PackedStringArray(["fake-user"]):
		failures.append("la config del proyecto no guardó la skill apagada: %s" % (saved.get(&"disabled_skills") if saved else "sin archivo"))
	if not (window.get(&"_banner") as Control).visible:
		failures.append("no avisa que vale desde la próxima sesión")
	var main_plugin := _find_by_script(MAIN_PLUGIN_SCRIPT)
	var settings := SkillCatalog.session_settings(PackedStringArray(["fake-user"]))
	if main_plugin == null:
		failures.append("no encontré el plugin principal")
	else:
		# Sin sesión abierta no hay perfil: se usa el de Claude Code por defecto, como al conectar.
		var controller: Object = main_plugin.get(&"_controller")
		var previous: Variant = controller.get(&"_profile")
		controller.set(&"_profile", AgentProfile.from_dict(AgentProfile.CLAUDE_CODE))
		var meta: Dictionary = main_plugin.call(&"_session_meta")
		controller.set(&"_profile", previous)
		var expected := settings.duplicate()
		expected["permissions"] = {"ask": ["Agent"]}
		if meta != {"claudeCode": {"options": {"settings": expected}}}:
			failures.append("_meta de la sesión: %s" % meta)
	# Nueva skill en el proyecto.
	(tab.get(&"_where") as OptionButton).select(0)
	tab.call(&"_open_new_dialog")
	(tab.get(&"_new_name") as LineEdit).text = "made-here"
	(tab.get(&"_new_description") as LineEdit).text = "Use when testing"
	var dialog: ConfirmationDialog = tab.get(&"_new_dialog")
	await tree.create_timer(0.3).timeout
	dialog.get_texture().get_image().save_png("%s_new.png" % prefix)
	dialog.get_ok_button().pressed.emit()
	var project_skills := SkillCatalog.project_dir(ProjectSettings.globalize_path("res://").trim_suffix("/"))
	if not FileAccess.file_exists(project_skills.path_join("made-here/SKILL.md")):
		failures.append("no creó .claude/skills/made-here/SKILL.md")
	if opened != [project_skills.path_join("made-here/SKILL.md")]:
		failures.append("no abrió el SKILL.md nuevo: %s" % [opened])
	# Copiar la de usuario al proyecto.
	var user_skill: Dictionary = skills.filter(func(skill: Dictionary) -> bool: return skill.id == "fake-user")[0]
	tab.call(&"_copy_to_project", user_skill)
	if not FileAccess.file_exists(project_skills.path_join("fake-user/references/notes.md")):
		failures.append("no copió la skill de usuario con sus archivos")
	# Importar un zip.
	var zip_path := ProjectSettings.globalize_path("res://tests/tmp/skills_check.zip")
	var packer := ZIPPacker.new()
	packer.open(zip_path)
	packer.start_file("zipped/SKILL.md")
	packer.write_file("---\nname: zipped\ndescription: From a zip\n---\n".to_utf8_buffer())
	packer.close_file()
	packer.close()
	tab.call(&"_import", zip_path)
	if not FileAccess.file_exists(project_skills.path_join("zipped/SKILL.md")):
		failures.append("no importó el zip")
	var status: Label = window.get(&"_status")
	if not status.text.contains("zipped"):
		failures.append("el estado no dice qué importó: %s" % status.text)
	await tree.create_timer(0.5).timeout
	ids = (tab.get(&"_skills") as Array).map(func(skill: Dictionary) -> String: return "%s/%s" % [skill.origin, skill.id])
	for expected: String in ["project/made-here", "project/fake-user", "project/zipped"]:
		if not ids.has(expected):
			failures.append("la lista no tiene %s: %s" % [expected, ids])
	window.get_texture().get_image().save_png("%s_after.png" % prefix)
	window.hide()
	return failures


func _find_by_script(path: String) -> Node:
	for node: Node in _tree.root.find_children("*", "Node", true, false):
		var script := node.get_script() as Script
		if script and script.resource_path == path:
			return node
	return null
