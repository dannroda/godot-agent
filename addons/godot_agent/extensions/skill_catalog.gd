@tool
extends RefCounted
## Skills de Claude Code (m7-36): carpetas con SKILL.md del usuario (<config>/skills), del proyecto
## (.claude/skills) y de los plugins instalados. Las lee del disco, sin el CLI, porque la sesión
## necesita saber cuáles hay al abrirse: apagar una skill en un proyecto es mandarla en session/new
## como `skillOverrides: {nombre: "off"}` en las settings de la sesión (session_settings), que la
## oculta del modelo y del menú de comandos. Las de plugins no: Claude Code (2.1.310) no les aplica
## skillOverrides, se prenden y apagan con su plugin.
## También crea, importa (carpeta o zip), copia y borra skills de usuario y de proyecto.

const ORIGIN_USER := "user"
const ORIGIN_PROJECT := "project"
const ORIGIN_PLUGIN := "plugin"
const ORIGINS: PackedStringArray = [ORIGIN_PROJECT, ORIGIN_USER, ORIGIN_PLUGIN]
const SKILL_FILE := "SKILL.md"
## Nombre de una skill: lo que acepta Claude Code (minúsculas, números y guiones).
const NAME_PATTERN := "^[a-z0-9][a-z0-9-]{0,63}$"


## Carpeta de skills del usuario: <CLAUDE_CONFIG_DIR>/skills para Claude Code, o la carpeta de
## usuario del agente activo (`~/.codex/skills`, `~/.gemini/config/skills`, `~/.agents/skills`…).
static func user_dir(config_dir: String, agent_kind: String = "claude", env: Dictionary = {}, home_dir: String = "") -> String:
	var home := home_dir if not home_dir.is_empty() else OS.get_environment("HOME")
	match agent_kind:
		"claude", "":
			if config_dir.is_empty():
				config_dir = home.path_join(".claude")
			return config_dir.path_join("skills")
		"codex":
			var codex_home := str(env.get("CODEX_HOME", OS.get_environment("CODEX_HOME")))
			if codex_home.is_empty():
				codex_home = home.path_join(".codex")
			return codex_home.path_join("skills")
		"antigravity":
			return home.path_join(".gemini").path_join("config").path_join("skills")
		"opencode":
			return home.path_join(".config").path_join("opencode").path_join("skills")
		"copilot":
			return home.path_join(".copilot").path_join("skills")
		"cursor":
			return home.path_join(".cursor").path_join("skills")
		_:
			return home.path_join(".agents").path_join("skills")


## Todas las carpetas de skills del usuario que lee `agent_kind`, en orden de prioridad.
static func user_dirs(config_dir: String, agent_kind: String = "claude", env: Dictionary = {}, home_dir: String = "") -> PackedStringArray:
	var primary := user_dir(config_dir, agent_kind, env, home_dir)
	var dirs: PackedStringArray = [primary]
	if agent_kind in ["claude", ""] and home_dir.is_empty():
		return dirs
	var home := home_dir if not home_dir.is_empty() else OS.get_environment("HOME")
	var extras: PackedStringArray = []
	if agent_kind == "antigravity":
		extras.append(home.path_join(".gemini").path_join("antigravity").path_join("skills"))
	extras.append(home.path_join(".agents").path_join("skills"))
	for extra: String in extras:
		if not extra in dirs:
			dirs.append(extra)
	return dirs


## Carpeta de configuración de Claude Code: la del perfil del agente, la del entorno o ~/.claude.
static func config_dir(env: Dictionary) -> String:
	var dir := str(env.get("CLAUDE_CONFIG_DIR", OS.get_environment("CLAUDE_CONFIG_DIR")))
	return dir if not dir.is_empty() else OS.get_environment("HOME").path_join(".claude")


## Ruta relativa de la carpeta de skills del proyecto según el agente (`.claude/skills` o `.agents/skills`).
static func project_relative_dir(agent_kind: String = "claude") -> String:
	return ".claude/skills" if agent_kind in ["claude", ""] else ".agents/skills"


static func project_dir(project_path: String, agent_kind: String = "claude") -> String:
	if agent_kind in ["claude", ""]:
		return project_path.path_join(".claude").path_join("skills")
	if agent_kind == "antigravity" and DirAccess.dir_exists_absolute(project_path.path_join(".agent").path_join("skills")) and not DirAccess.dir_exists_absolute(project_path.path_join(".agents").path_join("skills")):
		return project_path.path_join(".agent").path_join("skills")
	return project_path.path_join(".agents").path_join("skills")


## Todas las carpetas de skills del proyecto que pueden existir (estándar `.agents/skills`, `.claude/skills`, etc.).
static func project_dirs(project_path: String, agent_kind: String = "claude") -> PackedStringArray:
	var dirs: PackedStringArray = [project_dir(project_path, agent_kind)]
	for rel: String in [".agents/skills", ".agent/skills", ".claude/skills", ".codex/skills", ".opencode/skills", ".github/skills", ".cursor/skills"]:
		var candidate := project_path.path_join(rel)
		if not candidate in dirs:
			dirs.append(candidate)
	return dirs


## Todas las skills: [{name, id, origin, plugin, path, description}]. `id` es el nombre que usa
## el agente (`plugin:skill` para las de plugins); `path` es la carpeta de la skill.
static func scan(claude_config_dir: String, project_path: String, agent_kind: String = "claude", env: Dictionary = {}, home_dir: String = "") -> Array[Dictionary]:
	var skills: Array[Dictionary] = []
	var seen_project: Dictionary = {}
	for dir: String in project_dirs(project_path, agent_kind):
		for skill: Dictionary in _scan_dir(dir, ORIGIN_PROJECT):
			if not seen_project.has(skill.id):
				seen_project[skill.id] = true
				skills.append(skill)
	var seen_user: Dictionary = {}
	for dir: String in user_dirs(claude_config_dir, agent_kind, env, home_dir):
		for skill: Dictionary in _scan_dir(dir, ORIGIN_USER):
			if not seen_user.has(skill.id):
				seen_user[skill.id] = true
				skills.append(skill)
	if agent_kind in ["claude", ""]:
		for plugin: Dictionary in installed_plugins(claude_config_dir):
			for folder: String in plugin_skill_dirs(plugin, claude_config_dir):
				var skill := read_skill(folder, ORIGIN_PLUGIN)
				if not skill.is_empty():
					skill.plugin = plugin.id
					skill.id = "%s:%s" % [str(plugin.id).get_slice("@", 0), skill.name]
					skills.append(skill)
	elif agent_kind == "antigravity":
		for plugin: Dictionary in antigravity_plugins(project_path, home_dir):
			for folder: String in plugin_skill_dirs(plugin, ""):
				var skill := read_skill(folder, ORIGIN_PLUGIN)
				if not skill.is_empty():
					skill.plugin = plugin.id
					skill.id = "%s:%s" % [plugin.id, skill.name]
					skills.append(skill)
	return skills


## Plugins de Antigravity en `.agents/plugins/*`, `.agent/plugins/*` y `~/.gemini/config/plugins/*`: `[{id, path}]`.
static func antigravity_plugins(project_path: String, home_dir: String = "") -> Array[Dictionary]:
	var plugins: Array[Dictionary] = []
	var seen: Dictionary = {}
	var home := home_dir if not home_dir.is_empty() else OS.get_environment("HOME")
	var roots: PackedStringArray = []
	if not project_path.is_empty():
		roots.append(project_path.path_join(".agents").path_join("plugins"))
		roots.append(project_path.path_join(".agent").path_join("plugins"))
	if not home.is_empty():
		roots.append(home.path_join(".gemini").path_join("config").path_join("plugins"))
	for root: String in roots:
		if not DirAccess.dir_exists_absolute(root):
			continue
		for child: String in DirAccess.get_directories_at(root):
			if child.begins_with(".") or seen.has(child):
				continue
			var folder := root.path_join(child)
			var manifest: Variant = _read_json(folder.path_join("plugin.json"))
			if manifest is Dictionary or DirAccess.dir_exists_absolute(folder.path_join("skills")):
				var plugin_id := str((manifest as Dictionary).get("name", child)) if manifest is Dictionary else child
				seen[child] = true
				plugins.append({"id": plugin_id, "path": folder})
	return plugins


## Plugins instalados según <config>/plugins/installed_plugins.json: [{id, path}].
static func installed_plugins(claude_config_dir: String) -> Array[Dictionary]:
	var plugins: Array[Dictionary] = []
	var data: Variant = _read_json(claude_config_dir.path_join("plugins").path_join("installed_plugins.json"))
	if not data is Dictionary or not data.get("plugins") is Dictionary:
		return plugins
	for id: Variant in data.plugins:
		var installs: Variant = data.plugins[id]
		if installs is Array and not installs.is_empty() and installs[0] is Dictionary and installs[0].get("installPath") is String:
			plugins.append({"id": str(id), "path": installs[0].installPath})
	return plugins


## Carpetas de skills de un plugin: las que declara (plugin.json o, si no tiene, su entrada del
## marketplace con `skills`), o las de skills/.
static func plugin_skill_dirs(plugin: Dictionary, claude_config_dir: String) -> PackedStringArray:
	var root := str(plugin.path)
	var declared: Variant = null
	var manifest: Variant = _read_json(root.path_join(".claude-plugin").path_join("plugin.json"))
	if manifest == null:
		manifest = _read_json(root.path_join("plugin.json"))
	if manifest is Dictionary:
		declared = manifest.get("skills")
	if declared == null:
		var market := str(plugin.id).get_slice("@", 1)
		var catalog: Variant = _read_json(claude_config_dir.path_join("plugins").path_join("marketplaces").path_join(market).path_join(".claude-plugin").path_join("marketplace.json"))
		if catalog is Dictionary and catalog.get("plugins") is Array:
			for entry: Variant in catalog.plugins:
				if entry is Dictionary and entry.get("name") == str(plugin.id).get_slice("@", 0):
					declared = entry.get("skills")
	var dirs: PackedStringArray = []
	var listed: Array = [declared] if declared is String else (declared if declared is Array else ["./skills"])
	for item: Variant in listed:
		var folder := root.path_join(str(item).trim_prefix("./")).simplify_path()
		if FileAccess.file_exists(folder.path_join(SKILL_FILE)):
			dirs.append(folder)
		elif DirAccess.dir_exists_absolute(folder):
			for child: String in DirAccess.get_directories_at(folder):
				if FileAccess.file_exists(folder.path_join(child).path_join(SKILL_FILE)):
					dirs.append(folder.path_join(child))
	return dirs


## La skill de una carpeta, o {} si no tiene SKILL.md.
static func read_skill(folder: String, origin: String) -> Dictionary:
	var file := folder.path_join(SKILL_FILE)
	if not FileAccess.file_exists(file):
		return {}
	var meta := parse_frontmatter(FileAccess.get_file_as_string(file))
	var name := str(meta.get("name", "")).strip_edges()
	if name.is_empty():
		name = folder.get_file()
	return {"name": name, "id": name, "origin": origin, "plugin": "", "path": folder, "description": str(meta.get("description", ""))}


## Claves simples del frontmatter YAML (`name`, `description`…), con comillas o en bloque (`>`, `|`).
static func parse_frontmatter(text: String) -> Dictionary:
	var meta := {}
	var lines := text.replace("\r\n", "\n").split("\n")
	if lines.is_empty() or lines[0].strip_edges() != "---":
		return meta
	var key := ""
	var block: PackedStringArray = []
	for i in range(1, lines.size()):
		var line := lines[i]
		if line.strip_edges() == "---":
			break
		if not key.is_empty() and (line.begins_with(" ") or line.begins_with("\t") or line.strip_edges().is_empty()):
			block.append(line.strip_edges())
			continue
		if not key.is_empty():
			meta[key] = " ".join(block).strip_edges()
			key = ""
		var colon := line.find(":")
		if colon <= 0 or line.begins_with(" "):
			continue
		var name := line.substr(0, colon).strip_edges()
		var value := line.substr(colon + 1).strip_edges()
		if value in [">", "|", ">-", "|-"]:
			key = name
			block = []
		else:
			meta[name] = _unquote(value)
	if not key.is_empty():
		meta[key] = " ".join(block).strip_edges()
	return meta


## Settings de la sesión (`_meta.claudeCode.options.settings`) con las skills apagadas, o {} si no
## hay ninguna. Las de Claude Code (simplify, loop…) no se tocan.
static func session_settings(disabled: PackedStringArray) -> Dictionary:
	if disabled.is_empty():
		return {}
	var overrides := {}
	for name: String in disabled:
		overrides[name] = "off"
	return {"skillOverrides": overrides}


static func is_valid_name(name: String) -> bool:
	var regex := RegEx.create_from_string(NAME_PATTERN)
	return regex.search(name) != null


## Crea <dir>/<name>/SKILL.md con una plantilla. Devuelve la ruta del archivo o "" si falló.
static func create(dir: String, name: String, description: String) -> String:
	if not is_valid_name(name) or DirAccess.dir_exists_absolute(dir.path_join(name)):
		return ""
	var folder := dir.path_join(name)
	if DirAccess.make_dir_recursive_absolute(folder) != OK:
		return ""
	var file := FileAccess.open(folder.path_join(SKILL_FILE), FileAccess.WRITE)
	if file == null:
		return ""
	file.store_string(template(name, description))
	file.close()
	return folder.path_join(SKILL_FILE)


static func template(name: String, description: String) -> String:
	if description.strip_edges().is_empty():
		description = "Use when …"
	return "---\nname: %s\ndescription: %s\n---\n\n# %s\n\nWhat the agent should do, step by step. Keep this file short and move long material to files next to it (references/…), linked from here.\n" % [name, JSON.stringify(description.strip_edges()), name.capitalize()]


## Copia la carpeta de una skill a <dest_dir>/<su nombre>. Devuelve "" o el error.
static func copy_skill(folder: String, dest_dir: String) -> String:
	var dest := dest_dir.path_join(folder.get_file())
	if DirAccess.dir_exists_absolute(dest):
		return "a skill named %s already exists there" % folder.get_file()
	return _copy_dir(folder, dest)


## Importa skills de una carpeta (la skill misma o una carpeta con varias) o de un zip a `dest_dir`.
## Devuelve {imported: [nombres], skipped: [nombres que ya estaban], error}.
static func import_path(source: String, dest_dir: String) -> Dictionary:
	var result := {"imported": [], "skipped": [], "error": ""}
	if source.get_extension().to_lower() == "zip":
		return _import_zip(source, dest_dir)
	var folders: PackedStringArray = []
	if FileAccess.file_exists(source.path_join(SKILL_FILE)):
		folders.append(source)
	else:
		for child: String in DirAccess.get_directories_at(source):
			if FileAccess.file_exists(source.path_join(child).path_join(SKILL_FILE)):
				folders.append(source.path_join(child))
	if folders.is_empty():
		result.error = "no SKILL.md in %s" % source
		return result
	for folder: String in folders:
		if DirAccess.dir_exists_absolute(dest_dir.path_join(folder.get_file())):
			result.skipped.append(folder.get_file())
			continue
		var error := _copy_dir(folder, dest_dir.path_join(folder.get_file()))
		if not error.is_empty():
			result.error = error
			return result
		result.imported.append(folder.get_file())
	return result


## Manda la carpeta de una skill a la papelera.
static func remove_skill(folder: String) -> bool:
	return OS.move_to_trash(ProjectSettings.globalize_path(folder)) == OK


static func _import_zip(zip_path: String, dest_dir: String) -> Dictionary:
	var result := {"imported": [], "skipped": [], "error": ""}
	var zip := ZIPReader.new()
	if zip.open(zip_path) != OK:
		result.error = "could not open %s" % zip_path
		return result
	var files := zip.get_files()
	# Cada SKILL.md marca una skill: su carpeta dentro del zip (o la raíz, con el nombre del zip).
	var roots: Dictionary = {}  # prefijo en el zip -> nombre de la skill
	for path: String in files:
		if path.get_file() == SKILL_FILE and not path.contains(".."):
			var prefix := path.get_base_dir()
			roots[prefix] = prefix.get_file() if not prefix.is_empty() else zip_path.get_file().get_basename()
	if roots.is_empty():
		result.error = "no SKILL.md in %s" % zip_path.get_file()
		zip.close()
		return result
	for prefix: String in roots:
		var name: String = roots[prefix]
		var dest := dest_dir.path_join(name)
		if DirAccess.dir_exists_absolute(dest):
			result.skipped.append(name)
			continue
		for path: String in files:
			if path.ends_with("/") or path.contains("..") or (not prefix.is_empty() and not path.begins_with(prefix + "/")):
				continue
			var relative := path.substr(prefix.length() + 1) if not prefix.is_empty() else path
			var target := dest.path_join(relative)
			DirAccess.make_dir_recursive_absolute(target.get_base_dir())
			var out := FileAccess.open(target, FileAccess.WRITE)
			if out == null:
				result.error = "could not write %s" % target
				zip.close()
				return result
			out.store_buffer(zip.read_file(path))
			out.close()
		result.imported.append(name)
	zip.close()
	return result


static func _copy_dir(from: String, to: String) -> String:
	if DirAccess.make_dir_recursive_absolute(to) != OK:
		return "could not create %s" % to
	for file: String in DirAccess.get_files_at(from):
		if DirAccess.copy_absolute(from.path_join(file), to.path_join(file)) != OK:
			return "could not copy %s" % from.path_join(file)
	for child: String in DirAccess.get_directories_at(from):
		var error := _copy_dir(from.path_join(child), to.path_join(child))
		if not error.is_empty():
			return error
	return ""


static func _scan_dir(dir: String, origin: String) -> Array[Dictionary]:
	var skills: Array[Dictionary] = []
	if not DirAccess.dir_exists_absolute(dir):
		return skills
	for child: String in DirAccess.get_directories_at(dir):
		if child.begins_with("."):
			continue
		var skill := read_skill(dir.path_join(child), origin)
		if not skill.is_empty():
			skills.append(skill)
	return skills


static func _unquote(value: String) -> String:
	if value.length() >= 2 and value.begins_with("\"") and value.ends_with("\""):
		var parsed: Variant = JSON.parse_string(value)
		return parsed if parsed is String else value.substr(1, value.length() - 2)
	if value.length() >= 2 and value.begins_with("'") and value.ends_with("'"):
		return value.substr(1, value.length() - 2).replace("''", "'")
	return value


static func _read_json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	return JSON.parse_string(FileAccess.get_file_as_string(path))
