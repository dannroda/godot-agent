@tool
extends RefCounted
## Recetas (m11-30): pedidos que se repiten (un enemigo nuevo, una pantalla de opciones, portar un
## script) con parámetros tipados y checks que el resultado tiene que pasar. Una receta es un .json en
## la carpeta de recetas del proyecto (res://agent_recipes/, configurable): contenido del usuario que
## se comparte por git, como las tools del proyecto. El formato:
##
##   {"version": 1, "title", "description", "mode": "build"|"auto"|"ask", "plan": false,
##    "prompt": "Add an enemy based on {{base}} that {{behavior}}",
##    "parameters": [{"key", "label", "type", "required", "default", "options", "filter"}],
##    "checks": [{"kind": "regressions"|"command", "name", "command", "paths", "timeout_s"}],
##    "max_retries": 2}
##
## Un comando de un check corre solo si se aprobó en esta máquina (la misma aprobación que los checks
## del proyecto): una receta clonada no corre nada sin preguntar.

const ProjectDirs := preload("project_dirs.gd")
const TurnChecks := preload("turn_checks.gd")

const DEFAULT_DIR := "res://agent_recipes"
const EXTENSION := "json"
const VERSION := 1
const MAX_RETRIES := 5
const DEFAULT_RETRIES := 2
const MAX_FILE_BYTES := 256 * 1024
const MODES: PackedStringArray = ["build", "auto", "ask"]
const TYPES: PackedStringArray = ["text", "multiline", "choice", "number", "bool", "scene", "script", "resource", "node", "input_action", "path"]
## Los tipos cuyo valor es una ruta res:// (van al prompt como mención @res://…).
const PATH_TYPES: PackedStringArray = ["scene", "script", "resource", "path"]
const CHECK_KINDS: PackedStringArray = [TurnChecks.KIND_REGRESSIONS, TurnChecks.KIND_COMMAND]
const KEYS: PackedStringArray = ["version", "title", "description", "mode", "plan", "prompt", "parameters", "checks", "max_retries"]
const PARAMETER_KEYS: PackedStringArray = ["key", "label", "type", "required", "default", "options", "filter"]
const CHECK_KEYS: PackedStringArray = ["kind", "name", "command", "paths", "timeout_s", "enabled"]
## Extensiones por tipo de archivo (el filtro del selector; `filter` de la receta las reemplaza).
const TYPE_EXTENSIONS := {
	"scene": ["tscn", "scn"],
	"script": ["gd", "cs"],
	"resource": ["tres", "res"],
}
const PLACEHOLDER_PATTERN := "\\{\\{\\s*([A-Za-z_][A-Za-z0-9_]*)\\s*\\}\\}"
const KEY_PATTERN := "^[A-Za-z_][A-Za-z0-9_]*$"


## La carpeta de recetas del proyecto: la de project_config o, si no sirve, DEFAULT_DIR.
static func resolve_dir(configured: String) -> String:
	return ProjectDirs.resolve(configured, DEFAULT_DIR)


## Lee una receta de su texto. `{recipe, errors}`: `recipe` normalizada (todos los campos, del tipo
## esperado) aunque haya errores; con errores no se puede lanzar.
static func parse(text: String, path: String = "") -> Dictionary:
	var json := JSON.new()
	if json.parse(text) != OK:
		return {"recipe": _empty(path), "errors": PackedStringArray(["Not valid JSON (line %d): %s" % [json.get_error_line(), json.get_error_message()]])}
	return from_data(json.data, path)


## Valida y normaliza una receta ya leída. Ver parse.
static func from_data(data: Variant, path: String = "") -> Dictionary:
	var errors: PackedStringArray = []
	var recipe := _empty(path)
	if not data is Dictionary:
		errors.append("The recipe must be a JSON object.")
		return {"recipe": recipe, "errors": errors}
	var source: Dictionary = data
	for key: Variant in source:
		if not str(key) in KEYS:
			errors.append("Unknown field «%s»." % key)
	var version := int(source.get("version", VERSION)) if _is_number(source.get("version", VERSION)) else -1
	if version < 1:
		errors.append("«version» must be a number.")
	elif version > VERSION:
		errors.append("Made for a newer version of the harness (version %d)." % version)
	recipe.title = _string(source, "title", errors).strip_edges()
	if recipe.title.is_empty():
		errors.append("«title» is missing.")
	recipe.description = _string(source, "description", errors).strip_edges()
	recipe.prompt = _string(source, "prompt", errors)
	if recipe.prompt.strip_edges().is_empty():
		errors.append("«prompt» is missing.")
	recipe.mode = _string(source, "mode", errors, "build").strip_edges().to_lower()
	if not recipe.mode in MODES:
		errors.append("«mode» must be one of: %s." % ", ".join(MODES))
		recipe.mode = "build"
	if source.has("plan") and not source.plan is bool:
		errors.append("«plan» must be true or false.")
	recipe.plan = bool(source.get("plan", false)) if source.get("plan", false) is bool else false
	if source.has("max_retries") and not _is_number(source.max_retries):
		errors.append("«max_retries» must be a number.")
	elif source.has("max_retries") and (int(source.max_retries) < 0 or int(source.max_retries) > MAX_RETRIES):
		errors.append("«max_retries» must be between 0 and %d." % MAX_RETRIES)
	recipe.max_retries = clampi(int(source.get("max_retries", DEFAULT_RETRIES)) if _is_number(source.get("max_retries", DEFAULT_RETRIES)) else DEFAULT_RETRIES, 0, MAX_RETRIES)
	var keys := {}
	if source.has("parameters") and not source.parameters is Array:
		errors.append("«parameters» must be a list.")
	elif source.has("parameters"):
		for item: Variant in source.parameters:
			var parameter := _parameter(item, recipe.parameters.size() + 1, errors)
			if parameter.is_empty():
				continue
			if keys.has(parameter.key):
				errors.append("Parameter «%s» appears twice." % parameter.key)
				continue
			keys[parameter.key] = true
			recipe.parameters.append(parameter)
	for key: String in placeholders(recipe.prompt):
		if not keys.has(key):
			errors.append("The prompt uses {{%s}}, which isn't a parameter." % key)
	if source.has("checks") and not source.checks is Array:
		errors.append("«checks» must be a list.")
	elif source.has("checks"):
		for item: Variant in source.checks:
			var check := _check(item, recipe.checks.size() + 1, errors)
			if not check.is_empty():
				recipe.checks.append(check)
	return {"recipe": recipe, "errors": errors}


static func _empty(path: String) -> Dictionary:
	return {"path": path, "slug": path.get_file().get_basename(), "title": "", "description": "", "mode": "build", "plan": false,
		"prompt": "", "parameters": [], "checks": [], "max_retries": DEFAULT_RETRIES}


static func _parameter(item: Variant, number: int, errors: PackedStringArray) -> Dictionary:
	if not item is Dictionary:
		errors.append("Parameter %d must be an object." % number)
		return {}
	var source: Dictionary = item
	for key: Variant in source:
		if not str(key) in PARAMETER_KEYS:
			errors.append("Parameter %d: unknown field «%s»." % [number, key])
	var key := str(source.get("key", "")).strip_edges()
	if not RegEx.create_from_string(KEY_PATTERN).search(key):
		errors.append("Parameter %d: «key» must be a name (letters, digits and _)." % number)
		return {}
	var type := str(source.get("type", "text")).strip_edges().to_lower()
	if not type in TYPES:
		errors.append("Parameter «%s»: unknown type «%s» (one of: %s)." % [key, type, ", ".join(TYPES)])
		type = "text"
	var parameter := {"key": key, "label": str(source.get("label", "")).strip_edges(), "type": type,
		"required": bool(source.get("required", true)) if source.get("required", true) is bool else true,
		"default": source.get("default", null), "options": PackedStringArray(), "filter": PackedStringArray()}
	if parameter.label.is_empty():
		parameter.label = key.capitalize()
	if source.has("options"):
		if not source.options is Array:
			errors.append("Parameter «%s»: «options» must be a list." % key)
		else:
			for option: Variant in source.options:
				if not str(option).strip_edges().is_empty():
					parameter.options.append(str(option).strip_edges())
	if type == "choice" and parameter.options.is_empty():
		errors.append("Parameter «%s»: a choice needs «options»." % key)
	if source.has("filter"):
		var filter: Variant = source.filter
		if filter is String:
			filter = [filter]
		if not filter is Array:
			errors.append("Parameter «%s»: «filter» must be a list of extensions." % key)
		else:
			for extension: Variant in filter:
				var clean := str(extension).strip_edges().trim_prefix("*").trim_prefix(".")
				if not clean.is_empty():
					parameter.filter.append(clean)
	if parameter.default != null:
		var problem := value_error(parameter, parameter.default)
		if not problem.is_empty():
			errors.append("Parameter «%s»: the default %s" % [key, problem])
	return parameter


static func _check(item: Variant, number: int, errors: PackedStringArray) -> Dictionary:
	if not item is Dictionary:
		errors.append("Check %d must be an object." % number)
		return {}
	var source: Dictionary = item
	for key: Variant in source:
		if not str(key) in CHECK_KEYS:
			errors.append("Check %d: unknown field «%s»." % [number, key])
	var kind := str(source.get("kind", TurnChecks.KIND_COMMAND))
	if not kind in CHECK_KINDS:
		errors.append("Check %d: unknown kind «%s» (one of: %s)." % [number, kind, ", ".join(CHECK_KINDS)])
		return {}
	var check := TurnChecks.normalize(source)
	if kind == TurnChecks.KIND_COMMAND:
		var parsed := TurnChecks.parse_command(str(check.command))
		if not str(parsed.error).is_empty():
			errors.append("Check «%s»: %s" % [check.name if not str(check.name).is_empty() else str(number), parsed.error])
	return check


static func _string(source: Dictionary, key: String, errors: PackedStringArray, default: String = "") -> String:
	var value: Variant = source.get(key, default)
	if value is String:
		return value
	errors.append("«%s» must be text." % key)
	return default


static func _is_number(value: Variant) -> bool:
	return value is int or value is float


## Las claves {{x}} que usa un texto, sin repetir y en orden.
static func placeholders(text: String) -> PackedStringArray:
	var result: PackedStringArray = []
	for found: RegExMatch in RegEx.create_from_string(PLACEHOLDER_PATTERN).search_all(text):
		if not found.get_string(1) in result:
			result.append(found.get_string(1))
	return result


## Las recetas de la carpeta (`res://` o absoluta), ordenadas por título: `[{recipe, errors}]`.
static func load_dir(dir: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not DirAccess.dir_exists_absolute(dir):
		return result
	var files := Array(DirAccess.get_files_at(dir)).filter(func(f: String) -> bool: return f.get_extension().to_lower() == EXTENSION)
	for file: String in files:
		result.append(load_file(dir.path_join(file)))
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var ta := str(a.recipe.title if not str(a.recipe.title).is_empty() else a.recipe.slug).to_lower()
		var tb := str(b.recipe.title if not str(b.recipe.title).is_empty() else b.recipe.slug).to_lower()
		return ta < tb)
	return result


static func load_file(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"recipe": _empty(path), "errors": PackedStringArray(["Can't read the file: %s" % error_string(FileAccess.get_open_error())])}
	if file.get_length() > MAX_FILE_BYTES:
		return {"recipe": _empty(path), "errors": PackedStringArray(["The file is too big for a recipe (more than %d KB)." % (MAX_FILE_BYTES / 1024)])}
	return parse(file.get_as_text(), path)


## La receta por slug (nombre del archivo) o título, sin distinguir mayúsculas; {} si no está.
static func find(loaded: Array[Dictionary], name: String) -> Dictionary:
	var wanted := name.strip_edges().to_lower()
	for item: Dictionary in loaded:
		if str(item.recipe.slug).to_lower() == wanted or str(item.recipe.title).to_lower() == wanted:
			return item
	return {}


## Qué tiene de malo un valor para el parámetro ("" si sirve). Un valor vacío es un error solo si es
## obligatorio (eso lo dice values_errors).
static func value_error(parameter: Dictionary, value: Variant) -> String:
	var text := _text(value)
	if text.is_empty():
		return ""
	match str(parameter.type):
		"choice":
			if not text in parameter.options:
				return "must be one of: %s." % ", ".join(parameter.options)
		"number":
			if not (value is int or value is float or text.is_valid_float()):
				return "must be a number."
		"bool":
			if not (value is bool or text.to_lower() in ["true", "false"]):
				return "must be true or false."
		"scene", "script", "resource", "path":
			if not text.begins_with("res://") or ".." in text.split("/"):
				return "must be a res:// path in the project."
			var extensions := extensions_for(parameter)
			if not extensions.is_empty() and not text.get_extension().to_lower() in extensions:
				return "must be a %s file." % ", ".join(extensions)
	return ""


## Las extensiones que acepta un parámetro de archivo (vacío: cualquiera).
static func extensions_for(parameter: Dictionary) -> PackedStringArray:
	if not (parameter.filter as PackedStringArray).is_empty():
		return parameter.filter
	return PackedStringArray(TYPE_EXTENSIONS.get(str(parameter.type), []))


## Los problemas de los valores del formulario (`{key: value}`), uno por parámetro.
static func values_errors(recipe: Dictionary, values: Dictionary) -> PackedStringArray:
	var errors: PackedStringArray = []
	for parameter: Dictionary in recipe.parameters:
		var value: Variant = values.get(parameter.key, parameter.default)
		if _text(value).is_empty():
			if parameter.required and parameter.type != "bool":
				errors.append("%s: %s" % [parameter.label, "required"])
			continue
		var problem := value_error(parameter, value)
		if not problem.is_empty():
			errors.append("%s: %s" % [parameter.label, problem])
	return errors


## El prompt con los {{x}} reemplazados. Una ruta va como mención (@res://…) y un nodo como @ruta,
## como los menciona el composer; un sí/no, como yes/no.
static func expand(recipe: Dictionary, values: Dictionary) -> String:
	var by_key := {}
	for parameter: Dictionary in recipe.parameters:
		by_key[parameter.key] = parameter
	var text: String = recipe.prompt
	var regex := RegEx.create_from_string(PLACEHOLDER_PATTERN)
	var result := ""
	var at := 0
	for found: RegExMatch in regex.search_all(text):
		result += text.substr(at, found.get_start() - at)
		var key := found.get_string(1)
		result += _rendered(by_key.get(key, {}), values.get(key, by_key.get(key, {}).get("default")))
		at = found.get_end()
	return result + text.substr(at)


static func _rendered(parameter: Dictionary, value: Variant) -> String:
	var text := _text(value)
	match str(parameter.get("type", "text")):
		"bool":
			return "yes" if text.to_lower() == "true" else "no"
		"scene", "script", "resource", "path", "node":
			return "@" + text if not text.is_empty() else ""
		"number":
			return text.trim_suffix(".0") if text.is_valid_float() else text
	return text


static func _text(value: Variant) -> String:
	if value == null:
		return ""
	if value is bool:
		return "true" if value else "false"
	return str(value).strip_edges()


## Lo que lleva una corrida de receta al controller: título, checks y tope de reintentos.
static func run_spec(recipe: Dictionary) -> Dictionary:
	return {"title": str(recipe.title), "slug": str(recipe.slug), "checks": (recipe.checks as Array).duplicate(true), "max_retries": int(recipe.max_retries)}
