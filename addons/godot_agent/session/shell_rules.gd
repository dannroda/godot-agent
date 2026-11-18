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
## Motivo de la decisión de `classify`.
const CODE_ALLOWED := "allowed"
const CODE_NOT_ALLOWED := "not_allowed"
const CODE_ASK_LIST := "ask_list"
const CODE_SUBSTITUTION := "substitution"
const CODE_REDIRECT := "redirect"
const CODE_QUOTE := "quote"
const CODE_EMPTY := "empty"
## Un `case` o una definición de función: lo que corre depende de patrones o de cuándo se llama.
const CODE_COMPOUND := "compound"

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
## Palabras del shell antes del comando de verdad (`do rm x`, `then ls`, `! grep`): se sacan. Sin esto
## `for f in a; do rm $f; done` quedaba en «for…», «do rm $f» y «done»: la lista ask no veía el rm y
## «Permitir siempre» sugería «do *», que después dejaba pasar cualquier comando dentro de un loop.
const LEAD_KEYWORDS: PackedStringArray = ["do", "then", "else", "elif", "if", "while", "until", "!", "{"]
## Cierran un bloque o lo abren sin correr nada (la lista de un `for` ya pasó por el chequeo de
## sustituciones): no son un comando.
const CLOSE_KEYWORDS: PackedStringArray = ["done", "fi", "esac", "}", ")"]
const HEADER_KEYWORDS: PackedStringArray = ["for", "select"]
## Corren el comando que les sigue: se juzga ese (`… | xargs rm` es un rm). Valor: las opciones que
## toman el argumento siguiente. sudo, su y doas no: están en la lista ask.
const WRAPPERS := {
	"xargs": ["-I", "-n", "-P", "-d", "-L", "-s", "-E", "-a", "--arg-file", "--delimiter", "--max-args", "--max-procs", "--max-chars", "--max-lines", "--replace", "--eof"],
	"env": ["-u", "-C", "-S", "--unset", "--chdir", "--split-string"],
	"timeout": ["-s", "-k", "--signal", "--kill-after"],
	"nice": ["-n", "--adjustment"],
	"nohup": [], "time": [], "command": [], "builtin": [], "exec": [],
	"stdbuf": ["-i", "-o", "-e"],
}


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
## `reason` una frase en inglés para el Agent Log. `code` (CODE_*) y `segment` (la parte del
## comando o el archivo de la redirección) sirven para mostrar el motivo traducido.
static func classify(command: String, rules: Array) -> Dictionary:
	var parsed := split(command)
	if not str(parsed.unsafe).is_empty():
		return {"decision": ASK, "rule": "", "reason": str(parsed.unsafe), "code": parsed.code, "segment": str(parsed.get("target", ""))}
	var segments: PackedStringArray = parsed.segments
	if segments.is_empty():
		return {"decision": ASK, "rule": "", "reason": "empty command", "code": CODE_EMPTY, "segment": ""}
	for segment: String in segments:
		var ask_rule := _matching(segment, rules, LIST_ASK)
		if not ask_rule.is_empty():
			return {"decision": ASK, "rule": ask_rule, "reason": "«%s» is on the ask list (%s)" % [segment, ask_rule], "code": CODE_ASK_LIST, "segment": segment}
	var used: PackedStringArray = []
	for segment: String in segments:
		var allow_rule := _matching(segment, rules, LIST_ALLOW)
		if allow_rule.is_empty():
			return {"decision": ASK, "rule": "", "reason": "«%s» is not on the allowlist" % segment, "code": CODE_NOT_ALLOWED, "segment": segment}
		if not allow_rule in used:
			used.append(allow_rule)
	return {"decision": ALLOW, "rule": ", ".join(used), "reason": "on the allowlist (%s)" % ", ".join(used), "code": CODE_ALLOWED, "segment": ""}


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
			return {"segments": segments, "unsafe": "command substitution", "code": CODE_SUBSTITUTION}
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
			return {"segments": segments, "unsafe": "process substitution", "code": CODE_SUBSTITUTION}
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
				return {"segments": segments, "unsafe": "redirects output to %s" % (target if not target.is_empty() else "a file"), "code": CODE_REDIRECT, "target": target}
			current = _drop_fd(current)
			i = j
			continue
		if c in [";", "\n", "|", "&"]:
			if not _push(segments, current):
				return {"segments": segments, "unsafe": "case statement or function definition", "code": CODE_COMPOUND}
			current = ""
			i += 2 if (c == "&" and next == "&") or (c == "|" and next in ["|", "&"]) else 1
			continue
		current += c
		i += 1
	if not quote.is_empty():
		return {"segments": segments, "unsafe": "unterminated quote", "code": CODE_QUOTE}
	if not _push(segments, current):
		return {"segments": segments, "unsafe": "case statement or function definition", "code": CODE_COMPOUND}
	return {"segments": segments, "unsafe": "", "code": ""}


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


## Agrega el comando que corre de verdad: sin las asignaciones de variables del principio
## (`FOO=1 cmd`), sin las palabras del shell que lo preceden (LEAD_KEYWORDS) y sin los envoltorios
## (WRAPPERS). Lo que no corre nada (`done`, la cabecera de un `for`) no se agrega. false si es un
## `case` o una definición de función, que las listas no pueden juzgar.
static func _push(segments: PackedStringArray, raw: String) -> bool:
	var words := normalize(raw.replace("\n", " ")).split(" ", false)
	var assignment := RegEx.create_from_string("^[A-Za-z_][A-Za-z0-9_]*=")
	var opened := 0  # `(` de subshell sacados del principio
	while not words.is_empty():
		var first := words[0]
		if assignment.search(first) or first in LEAD_KEYWORDS:
			words.remove_at(0)
		elif first.begins_with("(") and not first.begins_with("(("):
			words[0] = first.substr(1)
			opened += 1
			if words[0].is_empty():
				words.remove_at(0)
		elif WRAPPERS.has(first):
			var inner := _wrapped_start(words)
			if inner < 0:
				break
			words = words.slice(inner)
		else:
			break
	if words.is_empty() or words[0] in CLOSE_KEYWORDS or words[0] in HEADER_KEYWORDS:
		return true
	var head := words[0]
	if head == "case" or head == "function" or head.begins_with("((") or head.ends_with("()") or (words.size() > 1 and words[1].begins_with("()")):
		return false
	# El `)` que cierra un subshell abierto en este u otro comando: `(cd x; ls)` → «cd x», «ls».
	var joined := " ".join(words)
	if words[words.size() - 1].ends_with(")") and (opened > 0 or joined.count(")") > joined.count("(")):
		words[words.size() - 1] = words[words.size() - 1].trim_suffix(")")
		if words[words.size() - 1].is_empty():
			words.remove_at(words.size() - 1)
	if not words.is_empty():
		segments.append(" ".join(words))
	return true


## Dónde empieza el comando que corre el envoltorio de `words[0]`, o -1 si no tiene (`xargs` solo,
## `env` solo): ahí queda como está y se juzga el envoltorio.
static func _wrapped_start(words: PackedStringArray) -> int:
	var takes_value: Array = WRAPPERS[words[0]]
	var assignment := RegEx.create_from_string("^[A-Za-z_][A-Za-z0-9_]*=")
	var positional := 1 if words[0] == "timeout" else 0  # timeout DURACIÓN cmd
	var i := 1
	while i < words.size():
		var word := words[i]
		if word == "--":
			i += 1
			break
		if word.begins_with("-") and word.length() > 1:
			i += 2 if word in takes_value else 1
		elif words[0] == "env" and assignment.search(word):
			i += 1
		elif positional > 0:
			positional -= 1
			i += 1
		else:
			break
	return i if i < words.size() else -1


## Saca el número de descriptor pegado a una redirección (`ls 2>/dev/null` → `ls`).
static func _drop_fd(text: String) -> String:
	var trimmed := text
	while not trimmed.is_empty() and trimmed[-1].is_valid_int():
		trimmed = trimmed.left(-1)
	return trimmed if trimmed.is_empty() or trimmed[-1] == " " else text
