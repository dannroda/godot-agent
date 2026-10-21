@tool
extends RefCounted
## Post-procesado de candidatos (spec §16.6), común a todas las fuentes. En M8a: una sola línea,
## solapamiento con el suffix, descartes (vacía, repite la línea siguiente) y chequeo de balanceo.

const CLOSERS := ")]}\"'"
const PAIRS := {"(": ")", "[": "]", "{": "}"}


## Texto listo para mostrar, o "" si se descarta. `prefix`/`suffix`: la línea antes y después del caret.
static func process(text: String, prefix: String, suffix: String, next_line: String = "") -> String:
	var out := text.get_slice("\n", 0).replace("\r", "")
	var stripped := strip_suffix_overlap(out, suffix)
	# El solapamiento se quita salvo que justo eso desbalancee una línea que sin quitarlo cierra bien.
	if stripped == out or balanced(prefix + stripped + suffix) or not balanced(prefix + out + suffix):
		out = stripped
	if out.strip_edges().is_empty():
		return ""
	var full := (prefix + out + suffix).strip_edges()
	if not next_line.strip_edges().is_empty() and full == next_line.strip_edges():
		return ""
	if not consistent(prefix + out + suffix, prefix.length()):
		return ""
	return out


## Si el final de la sugerencia repite el comienzo del suffix (`)` o `")` del autocierre), lo quita.
static func strip_suffix_overlap(text: String, suffix: String) -> String:
	var tail := suffix.strip_edges(false, true)
	for length in range(mini(tail.length(), text.length()), 0, -1):
		if text.ends_with(tail.left(length)):
			return text.left(text.length() - length)
	return text


## Paréntesis, corchetes, llaves y comillas balanceados en una línea (ignora strings y comentarios).
static func balanced(line: String) -> bool:
	return _scan(line, true)


## Como `balanced`, pero admite aperturas sin cerrar (una línea puede abrir un bloque o una lista
## que sigue abajo). Falla con cierres de más, cierres cruzados o un string sin cerrar. Los cierres
## de más antes de `lenient_until` se toleran (la línea puede cerrar algo abierto más arriba).
static func consistent(line: String, lenient_until: int = 0) -> bool:
	return _scan(line, false, lenient_until)


static func _scan(line: String, require_closed: bool, lenient_until: int = 0) -> bool:
	var stack: Array[String] = []
	var quote := ""
	var i := 0
	while i < line.length():
		var c := line[i]
		if not quote.is_empty():
			if c == "\\":
				i += 1
			elif c == quote:
				quote = ""
		elif c == "#":
			break
		elif c == "\"" or c == "'":
			quote = c
		elif PAIRS.has(c):
			stack.append(PAIRS[c])
		elif c in ")]}":
			if stack.is_empty():
				if i >= lenient_until:
					return false
			elif stack.pop_back() != c:
				return false
		i += 1
	return quote.is_empty() and (stack.is_empty() or not require_closed)
