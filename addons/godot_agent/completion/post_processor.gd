@tool
extends RefCounted
## Post-procesado de candidatos (spec §16.6), común a todas las fuentes y en este orden:
## 1. tokens FIM residuales y lo que sigue a un stop (lo trae un LLM);
## 2. recorte al bloque: una línea con menos sangría que la del caret, una línea vacía o el máximo
##    de líneas lo terminan;
## 3. solapamiento con el suffix (`)` o `")` del autocierre);
## 4. indentación del editor (tabs o espacios) en las líneas siguientes;
## 5. descartes: vacía, solo espacios, o que repite lo que ya está escrito abajo;
## 6. chequeo de balanceo: cierres de más, cruzados o un string sin cerrar descartan.
## Con algo a la derecha del caret (cierres), la sugerencia es de una sola línea: los cierres van al
## final de la línea del caret, no después del bloque.

const CompletionRequest := preload("completion_request.gd")

const CLOSERS := ")]}\"'"
const PAIRS := {"(": ")", "[": "]", "{": "}"}
const DEFAULT_MAX_LINES := 8
## Restos de plantillas FIM y fin de texto de los modelos más comunes.
const FIM_MARKERS: PackedStringArray = [
	"<|fim_prefix|>", "<|fim_suffix|>", "<|fim_middle|>", "<|fim_pad|>", "<|file_sep|>", "<|repo_name|>",
	"<|endoftext|>", "<|im_end|>", "<|im_start|>", "<|end|>", "<fim_prefix>", "<fim_suffix>", "<fim_middle>",
	"<file_sep>", "<|end_of_text|>", "<|eot_id|>", "[PREFIX]", "[SUFFIX]", "[MIDDLE]", "<PRE>", "<SUF>", "<MID>",
	"<EOT>", "</s>",
]


## Texto listo para mostrar, o "" si se descarta. `max_lines` 1 = solo la primera línea; `stops`:
## los stop tokens del perfil LLM.
static func process(text: String, request: CompletionRequest, max_lines: int = DEFAULT_MAX_LINES, stops: PackedStringArray = []) -> String:
	var prefix := request.line_prefix
	var suffix := request.line_suffix
	var lines := strip_fim(text, stops).replace("\r", "").split("\n")
	if not suffix.strip_edges().is_empty():
		max_lines = 1
	var first := lines[0]
	var stripped := strip_suffix_overlap(first, suffix)
	# El solapamiento se quita salvo que justo eso desbalancee una línea que sin quitarlo cierra bien.
	if stripped == first or balanced(prefix + stripped + suffix) or not balanced(prefix + first + suffix):
		first = stripped
	first = first.strip_edges(false, true) if lines.size() > 1 and max_lines > 1 else first
	if first.strip_edges().is_empty() and (lines.size() == 1 or max_lines == 1):
		return ""
	var full_first := (prefix + first + suffix).strip_edges()
	if not request.next_line.strip_edges().is_empty() and full_first == request.next_line.strip_edges():
		return ""
	var block := _block(lines, request, max_lines)
	if not consistent(prefix + first + suffix, prefix.length()):
		return ""
	var out := first
	for line: String in block:
		out += "\n" + line
	if out.strip_edges().is_empty():
		return ""
	if not block.is_empty() and not consistent(prefix + out, prefix.length()):
		return ""
	return out


## Líneas 2 en adelante recortadas al bloque y con la indentación del editor.
static func _block(lines: PackedStringArray, request: CompletionRequest, max_lines: int) -> PackedStringArray:
	var out := PackedStringArray()
	if max_lines <= 1 or lines.size() < 2:
		return out
	var caret_level := level_of(request.line_prefix, request)
	var existing := request.next_line.strip_edges()
	for i in range(1, mini(lines.size(), max_lines)):
		var line := lines[i].strip_edges(false, true)
		if line.strip_edges().is_empty():
			break
		var level := level_of(line, request)
		if level < caret_level:
			break
		# Llegó a lo que ya está escrito debajo del caret.
		if not existing.is_empty() and line.strip_edges() == existing:
			break
		out.append(request.indent_unit().repeat(level) + line.strip_edges(true, false))
	return out


## Nivel de sangría de una línea: tabs, o espacios de a `indent_size` del editor (de a 4 si el
## editor usa tabs).
static func level_of(line: String, request: CompletionRequest) -> int:
	var tabs := 0
	var spaces := 0
	for c in line:
		if c == "\t":
			tabs += 1
		elif c == " ":
			spaces += 1
		else:
			break
	var size := request.indent_size if request.indent_spaces and request.indent_size > 0 else 4
	return tabs + spaces / size


## Corta en el primer token FIM residual o stop.
static func strip_fim(text: String, stops: PackedStringArray = []) -> String:
	var cut := text.length()
	for marker: String in FIM_MARKERS:
		var at := text.find(marker)
		if at >= 0:
			cut = mini(cut, at)
	for stop: String in stops:
		if stop.is_empty():
			continue
		var at := text.find(stop)
		if at >= 0:
			cut = mini(cut, at)
	return text.left(cut)


## Si el final de la sugerencia repite el comienzo del suffix (`)` o `")` del autocierre), lo quita.
static func strip_suffix_overlap(text: String, suffix: String) -> String:
	var tail := suffix.strip_edges(false, true)
	for length in range(mini(tail.length(), text.length()), 0, -1):
		if text.ends_with(tail.left(length)):
			return text.left(text.length() - length)
	return text


## Paréntesis, corchetes, llaves y comillas balanceados (ignora strings y comentarios).
static func balanced(line: String) -> bool:
	return _scan(line, true)


## Como `balanced`, pero admite aperturas sin cerrar (una línea puede abrir un bloque o una lista
## que sigue abajo). Falla con cierres de más, cierres cruzados o un string sin cerrar. Los cierres
## de más antes de `lenient_until` se toleran (la línea puede cerrar algo abierto más arriba).
static func consistent(line: String, lenient_until: int = 0) -> bool:
	return _scan(line, false, lenient_until)


## Recorre una o varias líneas: un string no cruza de línea y un comentario llega hasta el fin de
## la suya.
static func _scan(text: String, require_closed: bool, lenient_until: int = 0) -> bool:
	var stack: Array[String] = []
	var quote := ""
	var i := 0
	while i < text.length():
		var c := text[i]
		if not quote.is_empty():
			if c == "\\":
				i += 1
			elif c == quote:
				quote = ""
			elif c == "\n":
				return false
		elif c == "#":
			var end := text.find("\n", i)
			if end < 0:
				break
			i = end
			continue
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
