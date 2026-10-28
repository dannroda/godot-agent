extends "test_case.gd"
## Skills de Claude Code (m7-36): frontmatter, catálogo de usuario, proyecto y plugins, las settings
## que van en session/new, y crear, importar y copiar.

const SkillCatalog := preload("res://addons/godot_agent/extensions/skill_catalog.gd")
const SessionController := preload("res://addons/godot_agent/session/session_controller.gd")


func _fresh(name: String) -> String:
	var path := ProjectSettings.globalize_path("user://unit_tests/skills_%s_%d" % [name, Time.get_ticks_usec()])
	DirAccess.make_dir_recursive_absolute(path)
	return path


func _write(path: String, text: String) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()


func _skill_md(name: String, description: String) -> String:
	return "---\nname: %s\ndescription: %s\n---\n\nBody\n" % [name, description]


func test_frontmatter() -> void:
	var meta := SkillCatalog.parse_frontmatter("---\nname: \"godot-patterns\"\ndescription: \"Use when \\\"x\\\": y\"\nallowed-tools: Read\n---\n# Body\nname: no\n")
	assert_eq(meta.name, "godot-patterns", "nombre entre comillas")
	assert_eq(meta.description, "Use when \"x\": y", "comillas escapadas y dos puntos")
	assert_eq(meta.get("allowed-tools"), "Read", "otras claves")
	assert_false(meta.has("Body"), "el cuerpo no cuenta")
	meta = SkillCatalog.parse_frontmatter("---\r\nname: it's\r\ndescription: >\r\n  Line one\r\n  line two.\r\nother: 'a ''b'''\r\n---\r\n")
	assert_eq(meta.description, "Line one line two.", "bloque plegado con CRLF")
	assert_eq(meta.other, "a 'b'", "comillas simples")
	assert_eq(SkillCatalog.parse_frontmatter("# no frontmatter\nname: x"), {}, "sin frontmatter")


func test_scan() -> void:
	var config := _fresh("config")
	var project := _fresh("project")
	_write(config.path_join("skills/user-skill/SKILL.md"), _skill_md("user-skill", "User one"))
	_write(config.path_join("skills/no-skill/README.md"), "not a skill")
	_write(config.path_join("skills/.trash/old/SKILL.md"), _skill_md("old", "trashed"))
	_write(project.path_join(".claude/skills/folder-name/SKILL.md"), "---\ndescription: Project one\n---\n")
	# Un plugin con skills/ y otro (strict: false) cuyas skills declara el marketplace.
	var own := config.path_join("plugins/cache/mine/gdscript/0.1.0")
	_write(own.path_join(".claude-plugin/plugin.json"), JSON.stringify({"name": "gdscript"}))
	_write(own.path_join("skills/godot-patterns/SKILL.md"), _skill_md("godot-patterns", "Patterns"))
	var upstream := config.path_join("plugins/cache/up/godot/abc")
	_write(upstream.path_join("skills/godot/godot-gdscript/SKILL.md"), _skill_md("godot-gdscript", "GDScript"))
	_write(upstream.path_join("skills/unity/unity-x/SKILL.md"), _skill_md("unity-x", "not listed"))
	_write(config.path_join("plugins/marketplaces/up/.claude-plugin/marketplace.json"), JSON.stringify({"plugins": [
		{"name": "godot", "source": "./", "strict": false, "skills": ["./skills/godot/godot-gdscript"]}]}))
	_write(config.path_join("plugins/installed_plugins.json"), JSON.stringify({"version": 2, "plugins": {
		"gdscript@mine": [{"scope": "user", "installPath": own}],
		"godot@up": [{"scope": "user", "installPath": upstream}],
		"broken@x": "nope"}}))
	var skills := SkillCatalog.scan(config, project)
	var ids := skills.map(func(skill: Dictionary) -> String: return "%s/%s" % [skill.origin, skill.id])
	assert_eq(ids, ["project/folder-name", "user/user-skill", "plugin/gdscript:godot-patterns", "plugin/godot:godot-gdscript"], "orígenes, nombres y skills declaradas")
	assert_eq(skills[0].description, "Project one", "descripción")
	assert_eq(skills[2].plugin, "gdscript@mine", "plugin")
	assert_eq(skills[3].path, upstream.path_join("skills/godot/godot-gdscript"), "carpeta")
	assert_eq(SkillCatalog.scan(_fresh("empty"), _fresh("empty_project")), [], "sin nada")


func test_multi_agent_skills_and_plugins() -> void:
	var home := _fresh("agy_home")
	var project := _fresh("agy_project")
	_write(project.path_join(".agents/skills/level-gen/SKILL.md"), _skill_md("level-gen", "Generate levels"))
	_write(home.path_join(".gemini/config/skills/shader-opt/SKILL.md"), _skill_md("shader-opt", "Optimize shaders"))
	_write(home.path_join(".agents/skills/shared-skill/SKILL.md"), _skill_md("shared-skill", "Shared across agents"))
	_write(project.path_join(".agents/plugins/combat-pack/plugin.json"), JSON.stringify({"name": "combat-pack"}))
	_write(project.path_join(".agents/plugins/combat-pack/skills/hitbox/SKILL.md"), _skill_md("hitbox", "Hitbox setup"))
	var agy_skills := SkillCatalog.scan("", project, "antigravity", {}, home)
	assert_eq(agy_skills.map(func(s: Dictionary) -> String: return "%s/%s" % [s.origin, s.id]), [
		"project/level-gen",
		"user/shader-opt",
		"user/shared-skill",
		"plugin/combat-pack:hitbox",
	], "Antigravity lee .agents/skills, ~/.gemini/config/skills, ~/.agents/skills y plugins")

	var codex_home := home.path_join(".codex")
	_write(codex_home.path_join("skills/codex-helper/SKILL.md"), _skill_md("codex-helper", "Codex skill"))
	var codex_skills := SkillCatalog.scan("", project, "codex", {"CODEX_HOME": codex_home}, home)
	assert_eq(codex_skills.map(func(s: Dictionary) -> String: return "%s/%s" % [s.origin, s.id]), [
		"project/level-gen",
		"user/codex-helper",
		"user/shared-skill",
	], "Codex lee .agents/skills, $CODEX_HOME/skills y ~/.agents/skills")
	assert_eq(SkillCatalog.project_relative_dir("codex"), ".agents/skills", "carpeta del proyecto para Codex")
	assert_eq(SkillCatalog.project_relative_dir("claude"), ".claude/skills", "carpeta del proyecto para Claude")


func test_session_settings() -> void:
	assert_eq(SkillCatalog.session_settings([]), {}, "sin apagadas, nada")
	assert_eq(SkillCatalog.session_settings(["c", "p:a"]), {"skillOverrides": {"c": "off", "p:a": "off"}}, "las apagadas en off")


func test_session_meta() -> void:
	var controller := SessionController.new()
	assert_eq(controller.call(&"_with_meta", {"cwd": "/x"}), {"cwd": "/x"}, "sin proveedor, sin _meta")
	controller.session_meta_provider = func() -> Dictionary: return {"claudeCode": {"options": {"skills": ["a"]}}}
	assert_eq(controller.call(&"_with_meta", {"cwd": "/x"}), {"cwd": "/x", "_meta": {"claudeCode": {"options": {"skills": ["a"]}}}}, "con _meta")


func test_create_copy_remove() -> void:
	var dir := _fresh("create")
	assert_true(SkillCatalog.is_valid_name("level-design2"), "nombre válido")
	assert_false(SkillCatalog.is_valid_name("Level Design"), "mayúsculas y espacios")
	assert_false(SkillCatalog.is_valid_name("../x"), "ruta")
	var file := SkillCatalog.create(dir, "level-design", "Use when \"designing\" levels")
	assert_eq(file, dir.path_join("level-design/SKILL.md"), "archivo")
	var skill := SkillCatalog.read_skill(dir.path_join("level-design"), SkillCatalog.ORIGIN_USER)
	assert_eq([skill.name, skill.description], ["level-design", "Use when \"designing\" levels"], "la plantilla se lee de vuelta")
	assert_eq(SkillCatalog.create(dir, "level-design", ""), "", "no pisa una que existe")
	_write(dir.path_join("level-design/references/a.md"), "ref")
	var dest := _fresh("copy_dest")
	assert_eq(SkillCatalog.copy_skill(dir.path_join("level-design"), dest), "", "copia")
	assert_true(FileAccess.file_exists(dest.path_join("level-design/references/a.md")), "con sus subcarpetas")
	assert_true(SkillCatalog.copy_skill(dir.path_join("level-design"), dest).contains("already exists"), "no pisa")


func test_import() -> void:
	var source := _fresh("import_src")
	_write(source.path_join("one/SKILL.md"), _skill_md("one", "1"))
	_write(source.path_join("two/SKILL.md"), _skill_md("two", "2"))
	_write(source.path_join("two/references/r.md"), "r")
	var dest := _fresh("import_dest")
	var result := SkillCatalog.import_path(source.path_join("one"), dest)
	assert_eq(result.imported, ["one"], "la carpeta de una skill")
	result = SkillCatalog.import_path(source, dest)
	assert_eq([result.imported, result.skipped], [["two"], ["one"]], "una carpeta con varias, sin pisar")
	assert_true(FileAccess.file_exists(dest.path_join("two/references/r.md")), "con sus archivos")
	assert_true(str(SkillCatalog.import_path(_fresh("nothing"), dest).error).contains("no SKILL.md"), "sin skills")
	# Zip con dos skills en carpetas, otro con la skill en la raíz.
	var zip_path := source.path_join("pack.zip")
	var packer := ZIPPacker.new()
	packer.open(zip_path)
	for entry: Array in [["pack/three/SKILL.md", _skill_md("three", "3")], ["pack/three/scripts/x.py", "print()"], ["pack/four/SKILL.md", _skill_md("four", "4")], ["pack/README.md", "readme"]]:
		packer.start_file(entry[0])
		packer.write_file((entry[1] as String).to_utf8_buffer())
		packer.close_file()
	packer.close()
	result = SkillCatalog.import_path(zip_path, dest)
	result.imported.sort()
	assert_eq(result.imported, ["four", "three"], "las skills del zip")
	assert_true(FileAccess.file_exists(dest.path_join("three/scripts/x.py")), "con sus archivos")
	assert_false(FileAccess.file_exists(dest.path_join("README.md")), "lo de afuera de las skills no")
	var root_zip := source.path_join("solo-skill.zip")
	packer = ZIPPacker.new()
	packer.open(root_zip)
	packer.start_file("SKILL.md")
	packer.write_file(_skill_md("solo", "s").to_utf8_buffer())
	packer.close_file()
	packer.close()
	assert_eq(SkillCatalog.import_path(root_zip, dest).imported, ["solo-skill"], "en la raíz del zip, con el nombre del zip")


## Cada agente lista solo las carpetas de skills del proyecto que lee (Claude, solo .claude/skills).
func test_project_dirs_per_agent() -> void:
	var project := _fresh("per_agent")
	_write(project.path_join(".agents/skills/shared/SKILL.md"), _skill_md("shared", "Shared"))
	_write(project.path_join(".claude/skills/mine/SKILL.md"), _skill_md("mine", "Claude"))
	var claude_ids := SkillCatalog.scan(_fresh("cfg_claude"), project).map(func(skill: Dictionary) -> String: return skill.id)
	assert_eq(claude_ids, ["mine"], "Claude no ve .agents/skills")
	var codex_ids := SkillCatalog.scan(_fresh("cfg_codex"), project, "codex", {}, _fresh("home_codex")).map(func(skill: Dictionary) -> String: return skill.id)
	assert_eq(codex_ids, ["shared"], "Codex no ve .claude/skills")
