@tool
extends RefCounted
## Modos del proyecto (m11-39): un modo con nombre propio («Diseño de niveles», «Shaders», «Solo
## tests») que es una capa sobre un modo fijo (Preguntar, Revisar, Construir o Auto). Los permisos
## salen del modo base; la capa solo resta: los archivos que se pueden escribir, la shell, y suma
## instrucciones para el system prompt. Nunca da más permisos que el base.
##
## Un modo es un .json en la carpeta de modos del proyecto (res://agent_modes/, configurable, con las
## mismas reglas que las recetas): contenido del proyecto que se comparte por git. El formato:
##
##   {"version": 1, "name": "Level design", "base": "build",
##    "when_to_use": "Building and tweaking levels",
##    "instructions": "Only touch level scenes. Reuse the props in res://props/.",
##    "editable": ["res://levels/**", "*.tres"],
##    "shell": "ask"|"deny"|"base", "icon": "TileMap"}
##
## `editable` son globs (los de las reglas de archivos: `**` cualquier cantidad de carpetas, un patrón
## sin «/» vale en cualquier carpeta). Vacío o ausente: sin límite de archivos. Con límite, escribir
## fuera se rechaza siempre, sin tarjeta, y la shell pregunta siempre (también con base Auto), salvo
## `shell: "deny"` (se niega) o `"base"` (sigue al modo base). No lleva modelo: los modelos dependen de
## la cuenta de cada uno (decisión de m11-38); ModeModels lo recuerda por perfil.

const I18n := preload("i18n.gd")
const ProjectDirs := preload("project_dirs.gd")
const PathRules := preload("path_rules.gd")

const DEFAULT_DIR := "res://agent_modes"
const EXTENSION := "json"
const VERSION := 1
const MAX_FILE_BYTES := 64 * 1024
## Las instrucciones van en cada system prompt: con tope.
const MAX_INSTRUCTIONS_CHARS := 4000
const MAX_NAME_CHARS := 40
const MAX_GLOBS := 32
## Los modos base que admite una capa. One-shot no: ahí se elige un modo del proyecto para el constructor.
const BASES: PackedStringArray = ["ask", "review", "build", "auto"]
const SHELL_ASK := "ask"
const SHELL_DENY := "deny"
const SHELL_BASE := "base"
const SHELLS: PackedStringArray = [SHELL_ASK, SHELL_DENY, SHELL_BASE]
const KEYS: PackedStringArray = ["version", "name", "base", "when_to_use", "instructions", "editable", "shell", "icon"]


## La carpeta de modos del proyecto: la de project_config o, si no sirve, DEFAULT_DIR.
static func resolve_dir(configured: String) -> String:
	return ProjectDirs.resolve(configured, DEFAULT_DIR)


## Lee un modo de su texto. `{mode, errors}`: `mode` normalizado (todos los campos, del tipo esperado)
## aunque haya errores; con errores no se puede elegir.
static func parse(text: String, path: String = "") -> Dictionary:
	var json := JSON.new()
	if json.parse(text) != OK:
		return {"mode": _empty(path), "errors": PackedStringArray([I18n.t("Not valid JSON (line %d): %s") % [json.get_error_line(), json.get_error_message()]])}
	return from_data(json.data, path)


## Valida y normaliza un modo ya leído. Ver parse.
static func from_data(data: Variant, path: String = "") -> Dictionary:
	var errors: PackedStringArray = []
	var mode := _empty(path)
	if not data is Dictionary:
		errors.append(I18n.t("The mode must be a JSON object."))
		return {"mode": mode, "errors": errors}
	var source: Dictionary = data
	for key: Variant in source:
		if not str(key) in KEYS:
			errors.append(I18n.t("Unknown field «%s».") % key)
	var version_value: Variant = source.get("version", VERSION)
	var version := int(version_value) if version_value is int or version_value is float else -1
	if version < 1:
		errors.append(I18n.t("«version» must be a number."))
	elif version > VERSION:
		errors.append(I18n.t("Made for a newer version of the harness (version %d).") % version)
	mode.name = _string(source, "name", errors).strip_edges()
	if mode.name.is_empty():
		errors.append(I18n.t("«name» is missing."))
	elif mode.name.length() > MAX_NAME_CHARS:
		errors.append(I18n.t("«name» is too long (at most %d characters).") % MAX_NAME_CHARS)
	mode.base = _string(source, "base", errors).strip_edges().to_lower()
	if not mode.base in BASES:
		errors.append(I18n.t("«base» must be one of: %s.") % ", ".join(BASES))
		mode.base = "ask"  # el más restrictivo, por si alguien lo usa igual
	mode.when_to_use = _string(source, "when_to_use", errors).strip_edges()
	mode.instructions = _string(source, "instructions", errors).strip_edges()
	if mode.instructions.length() > MAX_INSTRUCTIONS_CHARS:
		errors.append(I18n.t("«instructions» is too long (at most %d characters).") % MAX_INSTRUCTIONS_CHARS)
	mode.icon = _string(source, "icon", errors).strip_edges()
	if source.has("editable") and not source.editable is Array:
		errors.append(I18n.t("«editable» must be a list of res:// patterns."))
	elif source.has("editable"):
		for item: Variant in source.editable:
			var glob := str(item).strip_edges() if item is String else ""
			var problem := glob_problem(glob) if item is String else I18n.t("must be text")
			if not problem.is_empty():
				errors.append(I18n.t("«editable»: «%s» %s.") % [str(item), problem])
			elif not glob in mode.editable:
				mode.editable.append(glob)
		if mode.editable.size() > MAX_GLOBS:
			errors.append(I18n.t("«editable» has too many patterns (at most %d).") % MAX_GLOBS)
	mode.shell = _string(source, "shell", errors, SHELL_ASK).strip_edges().to_lower()
	if not mode.shell in SHELLS:
		errors.append(I18n.t("«shell» must be one of: %s.") % ", ".join(SHELLS))
		mode.shell = SHELL_ASK
	return {"mode": mode, "errors": errors}


## Por qué no sirve un glob de `editable` ("" si sirve): vacío, fuera del proyecto o con «..».
static func glob_problem(glob: String) -> String:
	if glob.is_empty():
		return I18n.t("is empty")
	if glob.begins_with("/") or glob.begins_with("~") or (glob.contains("://") and not glob.begins_with("res://")):
		return I18n.t("must be a res:// path")
	if ".." in glob.trim_prefix("res://").split("/"):
		return I18n.t("can't use «..»")
	return ""


static func _empty(path: String) -> Dictionary:
	return {"path": path, "slug": path.get_file().get_basename(), "name": "", "base": "ask", "when_to_use": "",
		"instructions": "", "editable": PackedStringArray(), "shell": SHELL_ASK, "icon": ""}


static func _string(source: Dictionary, key: String, errors: PackedStringArray, default: String = "") -> String:
	if not source.has(key):
		return default
	if not source[key] is String:
		errors.append(I18n.t("«%s» must be text.") % key)
		return default
	return str(source[key])


## Los modos de la carpeta, `[{mode, errors}]` ordenados por nombre.
static func load_dir(dir: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not DirAccess.dir_exists_absolute(dir):
		return result
	var files := Array(DirAccess.get_files_at(dir)).filter(func(f: String) -> bool: return f.get_extension().to_lower() == EXTENSION)
	var names := {}
	for file: String in files:
		var item := load_file(dir.path_join(file))
		var key := str(item.mode.name).to_lower()
		if not key.is_empty() and names.has(key):
			var errors: PackedStringArray = item.errors  # PackedStringArray es un valor: se copia y se vuelve a poner
			errors.append(I18n.t("Another mode («%s») already has this name.") % names[key])
			item.errors = errors
		elif not key.is_empty():
			names[key] = file
		result.append(item)
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return label_key(a.mode) < label_key(b.mode))
	return result


static func label_key(mode: Dictionary) -> String:
	return str(mode.name if not str(mode.name).is_empty() else mode.slug).to_lower()


static func load_file(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"mode": _empty(path), "errors": PackedStringArray([I18n.t("Can't read the file: %s") % error_string(FileAccess.get_open_error())])}
	if file.get_length() > MAX_FILE_BYTES:
		return {"mode": _empty(path), "errors": PackedStringArray([I18n.t("The file is too big for a mode (more than %d KB).") % (MAX_FILE_BYTES / 1024)])}
	return parse(file.get_as_text(), path)


## Solo los que se pueden elegir (sin errores), en orden.
static func usable(loaded: Array[Dictionary]) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for item: Dictionary in loaded:
		if (item.errors as PackedStringArray).is_empty():
			result.append(item.mode)
	return result


## El modo por slug (nombre del archivo) o nombre, sin distinguir mayúsculas; {} si no está.
static func find(modes: Array[Dictionary], name: String) -> Dictionary:
	var wanted := name.strip_edges().to_lower()
	for mode: Dictionary in modes:
		if str(mode.slug).to_lower() == wanted or str(mode.name).to_lower() == wanted:
			return mode
	return {}


## true si el modo limita los archivos que se escriben.
static func limits_files(mode: Dictionary) -> bool:
	return not mode.is_empty() and not (mode.get("editable", PackedStringArray()) as PackedStringArray).is_empty()


## true si la shell (y lo que corre código que puede escribir cualquier cosa: tools del proyecto,
## build_extension) tiene que preguntar siempre, también con base Auto.
static func shell_always_asks(mode: Dictionary) -> bool:
	return limits_files(mode) and mode.get("shell", SHELL_ASK) == SHELL_ASK


static func shell_denied(mode: Dictionary) -> bool:
	return not mode.is_empty() and mode.get("shell", SHELL_ASK) == SHELL_DENY


## true si el modo deja escribir `path` (res://, absoluta del proyecto o file://). Sin límite, todo.
## Con límite: fuera del proyecto, nunca; la carpeta de donde salió el modo, nunca (un agente no
## ensancha su propio modo); el resto, si entra en algún glob de `editable`.
static func allows_write(mode: Dictionary, path: String, project_dir: String) -> bool:
	if not limits_files(mode):
		return true
	var relative := relative_path(path, project_dir)
	if relative.is_empty():
		return false
	var protected := relative_path(str(mode.get("path", "")).get_base_dir(), project_dir) if not str(mode.get("path", "")).is_empty() else ""
	if not protected.is_empty() and (relative == protected or relative.begins_with(protected + "/")):
		return false
	for glob: String in mode.editable:
		if RegEx.create_from_string(PathRules.glob_regex(glob)).search(relative):
			return true
	return false


## La primera de `paths` que el modo no deja escribir, o "" si todas pasan.
static func first_refused(mode: Dictionary, paths: PackedStringArray, project_dir: String) -> String:
	for path: String in paths:
		if not allows_write(mode, path, project_dir):
			return path
	return ""


## La ruta relativa al proyecto (sin res://), o "" si es de afuera o se escapa con «..».
static func relative_path(path: String, project_dir: String) -> String:
	var relative := PathRules.relative(path, project_dir)
	if relative.is_empty() or relative == "." or relative.begins_with("../") or relative == ".." or relative.begins_with("/"):
		return ""
	return relative


## «Diseño de niveles (Construir)»: el nombre y el base, ya traducido.
static func label(mode: Dictionary, base_label: String) -> String:
	return "%s (%s)" % [mode.name, base_label]


## «basado en Construir · edita res://levels/**»: para el tooltip del selector.
static func summary(mode: Dictionary, base_label: String) -> String:
	var parts: PackedStringArray = []
	if not str(mode.get("when_to_use", "")).is_empty():
		parts.append(str(mode.when_to_use))
	parts.append(I18n.t("Based on %s") % base_label)
	if limits_files(mode):
		parts.append(I18n.t("edits only %s") % ", ".join(mode.editable))
		match str(mode.shell):
			SHELL_ASK: parts.append(I18n.t("shell always asks"))
			SHELL_DENY: parts.append(I18n.t("no shell"))
	elif shell_denied(mode):
		parts.append(I18n.t("no shell"))
	return " · ".join(parts)


## El bloque para mode_rules del system prompt: las reglas del base, los archivos que se pueden
## escribir y las instrucciones del modo (texto del proyecto, como CLAUDE.md: no va en sobre no confiable).
static func prompt_rules(mode: Dictionary, base_rules: String) -> String:
	var lines: PackedStringArray = [base_rules]
	if limits_files(mode):
		lines.append("Project mode «%s»: you may only write files matching %s. Writes anywhere else are rejected without asking, by the harness; shell commands %s." % [
			mode.name, ", ".join(mode.editable), "are denied" if shell_denied(mode) else ("always ask the user" if shell_always_asks(mode) else "follow the base mode")])
	elif shell_denied(mode):
		lines.append("Project mode «%s»: shell commands are denied." % mode.name)
	var instructions := str(mode.get("instructions", "")).strip_edges().left(MAX_INSTRUCTIONS_CHARS)
	if not instructions.is_empty():
		lines.append("Project mode instructions («%s», written by the project's team):\n%s" % [mode.name, instructions])
	return "\n".join(lines)
