@tool
extends RefCounted
## Reglas por archivo (m11-25): instrucciones del proyecto que valen solo para ciertos archivos, en los
## formatos que ya usan los agentes. El harness las aplica con cualquier agente: cuando el turno toca un
## archivo que coincide, la regla va en el próximo prompt (una vez por sesión), como bloque del harness
## con la misma confianza que CLAUDE.md. Las que el agente activo ya carga solo no se mandan.
##
## - `.claude/rules/**/*.md` con `paths:` (Claude Code las carga solo).
## - `.agents/rules/*.md` y `.agent/rules/*.md` con `trigger: glob` y `globs:` (Antigravity).
## - `.cursor/rules/**/*.mdc` con `globs:` y sin `alwaysApply: true` (Cursor).
## Solo cuentan las reglas por glob: las de siempre ya las carga cada agente como su CLAUDE.md/AGENTS.md,
## y las manuales o «a criterio del modelo» no tienen una forma agnóstica de decidirse.

const SOURCES: Array[Dictionary] = [
	{"dir": ".claude/rules", "ext": "md", "recursive": true, "format": "claude", "native": "claude"},
	{"dir": ".agents/rules", "ext": "md", "recursive": false, "format": "antigravity", "native": "antigravity"},
	{"dir": ".agent/rules", "ext": "md", "recursive": false, "format": "antigravity", "native": "antigravity"},
	{"dir": ".cursor/rules", "ext": "mdc", "recursive": true, "format": "cursor", "native": "cursor"},
]
const MAX_FILE_BYTES := 64 * 1024
## Tope del texto de reglas en un prompt: lo que no entra queda nombrado.
const MAX_BLOCK_CHARS := 4000
const BLOCK_HEADER := "Project rules for files in this turn"
const MAX_DEPTH := 4


## Las reglas por glob del proyecto en `project_dir` (carpeta absoluta): `[{file, name, globs, body,
## native, hash}]`, con `file` relativa al proyecto.
static func load_rules(project_dir: String) -> Array[Dictionary]:
	var rules: Array[Dictionary] = []
	for source: Dictionary in SOURCES:
		var dir := project_dir.path_join(source.dir)
		if not DirAccess.dir_exists_absolute(dir):
			continue
		for file: String in _files(dir, str(source.ext), bool(source.recursive), 0):
			var path := dir.path_join(file)
			var handle := FileAccess.open(path, FileAccess.READ)
			if handle == null or handle.get_length() > MAX_FILE_BYTES:
				continue
			var rule := parse_rule(handle.get_as_text(), str(source.format))
			if rule.is_empty():
				continue
			rule.file = str(source.dir).path_join(file)
			rule.name = file.get_file()
			rule.native = source.native
			rules.append(rule)
	return rules


static func _files(dir: String, extension: String, recursive: bool, depth: int) -> PackedStringArray:
	var result: PackedStringArray = []
	var access := DirAccess.open(dir)
	if access == null:
		return result
	access.include_navigational = false
	for file: String in access.get_files():
		if file.get_extension().to_lower() == extension and not access.is_link(file):
			result.append(file)
	if recursive and depth < MAX_DEPTH:
		for sub: String in access.get_directories():
			if access.is_link(sub):
				continue
			for file: String in _files(dir.path_join(sub), extension, true, depth + 1):
				result.append(sub.path_join(file))
	result.sort()
	return result


## Una regla de su texto: `{globs, body, hash}`, o {} si no es una regla por glob en ese formato.
static func parse_rule(text: String, format: String) -> Dictionary:
	var parsed := frontmatter(text)
	var fields: Dictionary = parsed.fields
	var globs: PackedStringArray = []
	match format:
		"claude":
			globs = _list(fields.get("paths"))
		"antigravity":
			if str(fields.get("trigger", "")).to_lower() != "glob":
				return {}
			globs = _list(fields.get("globs", fields.get("glob")))
		"cursor":
			if str(fields.get("alwaysApply", "")).to_lower() == "true":
				return {}
			globs = _list(fields.get("globs"))
	if globs.is_empty() or str(parsed.body).strip_edges().is_empty():
		return {}
	return {"globs": globs, "body": str(parsed.body).strip_edges(), "hash": text.sha256_text()}


## El front matter YAML simple de un markdown: `{fields, body}`. Entiende `clave: valor`, `clave: [a, b]`
## y listas con `- a` debajo de la clave; los valores entre comillas pierden las comillas.
static func frontmatter(text: String) -> Dictionary:
	var clean := text.trim_prefix(String.chr(0xFEFF)).replace("\r\n", "\n")
	if not clean.begins_with("---\n"):
		return {"fields": {}, "body": clean}
	var end := clean.find("\n---", 4)
	if end < 0:
		return {"fields": {}, "body": clean}
	var fields := {}
	var last_key := ""
	for line: String in clean.substr(4, end - 4).split("\n"):
		var stripped := line.strip_edges()
		if stripped.is_empty() or stripped.begins_with("#"):
			continue
		if stripped.begins_with("- ") and not last_key.is_empty():
			if not fields[last_key] is Array:
				fields[last_key] = [] if str(fields[last_key]).is_empty() else [fields[last_key]]
			(fields[last_key] as Array).append(_unquote(stripped.substr(2)))
			continue
		var colon := stripped.find(":")
		if colon <= 0:
			continue
		last_key = stripped.left(colon).strip_edges()
		var value := stripped.substr(colon + 1).strip_edges()
		if value.begins_with("[") and value.ends_with("]"):
			fields[last_key] = Array(_split_commas(value.substr(1, value.length() - 2))).map(func(v: String) -> String: return _unquote(v))
		else:
			fields[last_key] = _unquote(value)
	var body_start := clean.find("\n", end + 4)
	return {"fields": fields, "body": clean.substr(body_start + 1) if body_start >= 0 else ""}


static func _unquote(value: String) -> String:
	var clean := value.strip_edges()
	if clean.length() >= 2 and ((clean.begins_with("\"") and clean.ends_with("\"")) or (clean.begins_with("'") and clean.ends_with("'"))):
		return clean.substr(1, clean.length() - 2)
	return clean


## Los patrones de un campo: una lista, o un texto con patrones separados por comas.
static func _list(value: Variant) -> PackedStringArray:
	var items: Array = value if value is Array else (Array(_split_commas(str(value))) if value != null else [])
	var result: PackedStringArray = []
	for item: Variant in items:
		var clean := _unquote(str(item))
		if not clean.is_empty():
			result.append(clean)
	return result


## Separa por comas fuera de llaves: `*.{gd,cs}, ui/**` son dos patrones.
static func _split_commas(text: String) -> PackedStringArray:
	var result: PackedStringArray = []
	var current := ""
	var depth := 0
	for c: String in text:
		if c == "{":
			depth += 1
		elif c == "}":
			depth = maxi(0, depth - 1)
		if c == "," and depth == 0:
			result.append(current)
			current = ""
		else:
			current += c
	result.append(current)
	return result


## La expresión regular de un glob: `**` cualquier cantidad de carpetas, `*` y `?` dentro de un nombre,
## `{a,b}` alternativas. Un patrón sin `/` (`*.gdshader`) vale en cualquier carpeta, como en Cursor.
static func glob_regex(glob: String) -> String:
	var pattern := glob.strip_edges().trim_prefix("res://").trim_prefix("./").trim_prefix("/")
	if not "/" in pattern:
		pattern = "**/" + pattern
	var out := "^"
	var i := 0
	var braces := 0
	while i < pattern.length():
		var c := pattern[i]
		if c == "*":
			if i + 1 < pattern.length() and pattern[i + 1] == "*":
				if i + 2 < pattern.length() and pattern[i + 2] == "/":
					out += "(?:.*/)?"
					i += 3
					continue
				out += ".*"
				i += 2
				continue
			out += "[^/]*"
		elif c == "?":
			out += "[^/]"
		elif c == "{":
			braces += 1
			out += "(?:"
		elif c == "}" and braces > 0:
			braces -= 1
			out += ")"
		elif c == "," and braces > 0:
			out += "|"
		elif c in ".+()|^$[]\\":
			out += "\\" + c
		else:
			out += c
		i += 1
	return out + "$"


## La ruta relativa al proyecto de `path` (res://, absoluta dentro del proyecto o file://); "" si es
## de afuera.
static func relative(path: String, project_dir: String) -> String:
	var clean := path.strip_edges().trim_prefix("file://")
	if clean.begins_with("res://"):
		return clean.trim_prefix("res://").simplify_path()
	var root := project_dir.simplify_path().trim_suffix("/") + "/"
	var absolute := clean.simplify_path()
	return absolute.trim_prefix(root) if absolute.begins_with(root) else ""


static func matches(rule: Dictionary, relative_path: String) -> bool:
	if relative_path.is_empty():
		return false
	for glob: String in rule.globs:
		if RegEx.create_from_string(glob_regex(glob)).search(relative_path):
			return true
	return false


## Las reglas que tocan alguno de `paths` (relativas), sin las que el agente `agent_kind` ya carga solo
## ni las ya mandadas (`sent`: file -> hash). Cada una con `paths`: los archivos que la activaron.
static func pending(rules: Array[Dictionary], paths: PackedStringArray, agent_kind: String, sent: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for rule: Dictionary in rules:
		if rule.native == agent_kind or str(sent.get(rule.file, "")) == rule.hash:
			continue
		var hit: PackedStringArray = []
		for path: String in paths:
			if matches(rule, path):
				hit.append(path)
		if not hit.is_empty():
			var item := rule.duplicate()
			item.paths = hit
			result.append(item)
	return result


## El bloque del prompt: una línea del harness y cada regla con su etiqueta. Son instrucciones del
## proyecto, como CLAUDE.md: van sin sobre. Lo que no entra en `max_chars` queda nombrado. `{text, sent}`
## con las reglas que entraron enteras.
static func block(rules: Array[Dictionary], max_chars: int = MAX_BLOCK_CHARS) -> Dictionary:
	var parts: PackedStringArray = ["%s. They come from the project's rule files and are instructions for you, like CLAUDE.md or AGENTS.md: follow them when you work on those files." % BLOCK_HEADER]
	var used := parts[0].length()
	var sent: Array[Dictionary] = []
	var left_out: PackedStringArray = []
	for rule: Dictionary in rules:
		var section := "\n### Project rules for %s (from %s)\n%s" % [", ".join(rule.globs), rule.file, rule.body]
		if used + section.length() > max_chars:
			left_out.append(rule.file)
			continue
		parts.append(section)
		used += section.length()
		sent.append(rule)
	if not left_out.is_empty():
		parts.append("\nMore rules apply but didn't fit here; read them if you work on those files: %s" % ", ".join(left_out))
	return {"text": "\n".join(parts), "sent": sent}


## Rutas res:// y de archivo en un texto (menciones @res://…, bloques de código del inline edit).
static func paths_in_text(text: String) -> PackedStringArray:
	var result: PackedStringArray = []
	for found: RegExMatch in RegEx.create_from_string("res://[^\\s`'\"()\\[\\]<>,;]+").search_all(text):
		var path := found.get_string().trim_suffix(".").trim_suffix(":")
		if not path in result:
			result.append(path)
	return result
