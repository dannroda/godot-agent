@tool
extends RefCounted
## Clasificador de comandos de shell del modo Auto (D57). Dos listas de patrones que el usuario
## revisa en Settings → Permisos:
## - "allow": se corre sin preguntar si cada parte del comando coincide con alguno;
## - "ask": se pregunta siempre, aunque coincida con la allowlist (rm, git push, curl…).
## Lo que no coincide con ninguno también se pregunta. Cada regla es
## `{pattern, list, origin, added}`; `*` en el patrón vale por cualquier texto y `cmd *` también
## coincide con `cmd` solo.
## Escribir el proyecto por fuera del editor lo rechaza antes ProjectWriteGuard (D48).

const LIST_ALLOW := "allow"
const LIST_ASK := "ask"
const ORIGIN_DEFAULT := "default"
const ORIGIN_USER := "user"
## Agregada desde una tarjeta de permiso («Permitir siempre»).
const ORIGIN_CARD := "card"

const ALLOW := "allow"
const ASK := "ask"

const DEFAULT_ALLOW: PackedStringArray = [
	"ls *", "cat *", "head *", "tail *", "wc *", "grep *", "rg *", "find *", "pwd", "cd *", "echo *",
	"which *", "stat *", "du *", "df *", "diff *",
	"git status *", "git diff *", "git log *", "git show *", "git branch", "git rev-parse *",
	"git ls-files *", "git blame *",
	"godot --version", "godot --headless *",
]
const DEFAULT_ASK: PackedStringArray = [
	"rm *", "rmdir *", "mv *", "dd *", "shred *", "sudo *", "su *", "doas *", "chmod *", "chown *",
	"kill *", "pkill *", "killall *",
	"git push *", "git reset *", "git checkout *", "git restore *", "git clean *", "git rebase *",
	"git *--output*",
	"curl *", "wget *", "ssh *", "scp *", "rsync *",
	"npm install *", "npm i *", "pip install *", "apt *", "apt-get *", "pacman *", "brew *",
	"find *-delete*", "find *-exec*", "find *-ok*", "find *-fprint*", "rg *--pre*",
]
## Destinos de redirección que no escriben archivos.
const SAFE_TARGETS: PackedStringArray = ["/dev/null", "/dev/stdout", "/dev/stderr", "/dev/tty"]
## Comandos cuyo patrón sugerido toma también el subcomando (`git log *` y no `git *`).
const SUBCOMMAND_TOOLS: PackedStringArray = ["git", "npm", "npx", "pnpm", "yarn", "cargo", "go", "dotnet", "pip", "uv", "docker", "godot", "gh", "make"]


static func default_rules() -> Array:
	var rules: Array = []
	for pattern: String in DEFAULT_ALLOW:
		rules.append(make_rule(pattern, LIST_ALLOW, ORIGIN_DEFAULT, ""))
	for pattern: String in DEFAULT_ASK:
		rules.append(make_rule(pattern, LIST_ASK, ORIGIN_DEFAULT, ""))
	return rules


static func make_rule(pattern: String, list: String, origin: String, added: String = "") -> Dictionary:
	return {"pattern": normalize(pattern), "list": list, "origin": origin, "added": added}


## Fecha de hoy para `added` (YYYY-MM-DD).
static func today() -> String:
	return Time.get_date_string_from_system()


## `{decision: "allow"|"ask", rule, reason}`. `rule` es el patrón que decidió ("" si ninguno) y
## `reason` una frase en inglés para el Agent Log.
static func classify(command: String, rules: Array) -> Dictionary:
	var parsed := split(command)
	if not str(parsed.unsafe).is_empty():
		return {"decision": ASK, "rule": "", "reason": str(parsed.unsafe)}
	var segments: PackedStringArray = parsed.segments
	if segments.is_empty():
		return {"decision": ASK, "rule": "", "reason": "empty command"}
	for segment: String in segments:
		var ask_rule := _matching(segment, rules, LIST_ASK)
		if not ask_rule.is_empty():
			return {"decision": ASK, "rule": ask_rule, "reason": "«%s» is on the ask list (%s)" % [segment, ask_rule]}
	var used: PackedStringArray = []
	for segment: String in segments:
		var allow_rule := _matching(segment, rules, LIST_ALLOW)
		if allow_rule.is_empty():
			return {"decision": ASK, "rule": "", "reason": "«%s» is not on the allowlist" % segment}
		if not allow_rule in used:
			used.append(allow_rule)
	return {"decision": ALLOW, "rule": ", ".join(used), "reason": "on the allowlist (%s)" % ", ".join(used)}


## true si `pattern` coincide con el comando simple `segment` (ya normalizado).
static func matches(pattern: String, segment: String) -> bool:
	var normalized := normalize(pattern)
	if normalized.is_empty():
		return false
	for candidate: String in _candidates(segment):
		if candidate.match(normalized):
			return true
		if normalized.ends_with(" *") and candidate == normalized.trim_suffix(" *"):
			return true
	return false


## Parte el comando en comandos simples (`&&`, `||`, `;`, `|`, `&`, saltos de línea), respetando
## comillas. `{segments, unsafe}`: `unsafe` no vacío si hay algo que las listas no pueden juzgar
## (sustitución de comandos, redirección a un archivo).
static func split(command: String) -> Dictionary:
	var segments: PackedStringArray = []
	var current := ""
	var quote := ""
	var i := 0
	var n := command.length()
	while i < n:
		var c := command[i]
		var next := command[i + 1] if i + 1 < n else ""
		if quote == "'":
			current += c
			if c == "'":
				quote = ""
			i += 1
			continue
		if c == "\\" and i + 1 < n:
			current += c + next
			i += 2
			continue
		if c == "`" or (c == "$" and next == "("):
			return {"segments": segments, "unsafe": "command substitution"}
		if quote == "\"":
			current += c
			if c == "\"":
				quote = ""
			i += 1
			continue
		if c == "'" or c == "\"":
			quote = c
			current += c
			i += 1
			continue
		if (c == "<" or c == ">") and next == "(":
			return {"segments": segments, "unsafe": "process substitution"}
		if c == ">" or (c == "&" and next == ">"):
			# n>destino, >>destino, &>destino: solo vale si no escribe un archivo.
			var j := i + 1 if c == ">" else i + 2
			if j < n and command[j] == ">":
				j += 1
			while j < n and command[j] == " ":
				j += 1
			var target := ""
			while j < n:
				var ch := command[j]
				if ch in [" ", ";", "|", "&", "\n", "<", ">", ")"] and not (ch == "&" and target.is_empty()):
					break
				target += ch
				j += 1
			target = target.trim_prefix("\"").trim_suffix("\"").trim_prefix("'").trim_suffix("'")
			if not target.begins_with("&") and not target in SAFE_TARGETS:
				return {"segments": segments, "unsafe": "redirects output to %s" % (target if not target.is_empty() else "a file")}
			current = _drop_fd(current)
			i = j
			continue
		if c in [";", "\n", "|", "&"]:
			_push(segments, current)
			current = ""
			i += 2 if (c == "&" and next == "&") or (c == "|" and next in ["|", "&"]) else 1
			continue
		current += c
		i += 1
	if not quote.is_empty():
		return {"segments": segments, "unsafe": "unterminated quote"}
	_push(segments, current)
	return {"segments": segments, "unsafe": ""}


## Patrón para «Permitir siempre» a partir del primer comando que no está en la allowlist:
## el programa (con su subcomando para git, npm…) más ` *`. "" si ninguna regla de la allowlist
## lo haría pasar: hay algo que las listas no juzgan (redirección, sustitución) o una parte está
## en la lista ask, que gana siempre.
static func suggest_pattern(command: String, rules: Array = []) -> String:
	var parsed := split(command)
	var segments: PackedStringArray = parsed.segments
	if not str(parsed.unsafe).is_empty() or segments.is_empty():
		return ""
	for candidate: String in segments:
		if not _matching(candidate, rules, LIST_ASK).is_empty():
			return ""
	var segment := segments[0]
	for candidate: String in segments:
		if _matching(candidate, rules, LIST_ALLOW).is_empty():
			segment = candidate
			break
	var candidates := _candidates(segment)
	var words := candidates[candidates.size() - 1].split(" ", false)
	var take := 2 if words.size() > 1 and words[0] in SUBCOMMAND_TOOLS and not words[1].begins_with("-") else 1
	var prefix := " ".join(words.slice(0, take))
	return prefix if words.size() == take else prefix + " *"


## Espacios colapsados y sin bordes.
static func normalize(text: String) -> String:
	return " ".join(text.replace("\t", " ").strip_edges().split(" ", false))


static func _matching(segment: String, rules: Array, list: String) -> String:
	for rule: Variant in rules:
		if rule is Dictionary and rule.get("list") == list and matches(str(rule.get("pattern", "")), segment):
			return str(rule.pattern)
	return ""


## El comando tal cual y, si el programa viene con ruta, con su nombre solo (`/opt/x/godot` → `godot`).
static func _candidates(segment: String) -> PackedStringArray:
	var result: PackedStringArray = [segment]
	var words := segment.split(" ", false)
	if not words.is_empty() and "/" in words[0]:
		words[0] = words[0].get_file()
		result.append(" ".join(words))
	return result


## Agrega un comando simple sin las asignaciones de variables del principio (`FOO=1 cmd`).
static func _push(segments: PackedStringArray, raw: String) -> void:
	var words := normalize(raw.replace("\n", " ")).split(" ", false)
	var assignment := RegEx.create_from_string("^[A-Za-z_][A-Za-z0-9_]*=")
	while not words.is_empty() and assignment.search(words[0]):
		words.remove_at(0)
	if not words.is_empty():
		segments.append(" ".join(words))


## Saca el número de descriptor pegado a una redirección (`ls 2>/dev/null` → `ls`).
static func _drop_fd(text: String) -> String:
	var trimmed := text
	while not trimmed.is_empty() and trimmed[-1].is_valid_int():
		trimmed = trimmed.left(-1)
	return trimmed if trimmed.is_empty() or trimmed[-1] == " " else text
