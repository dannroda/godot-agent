@tool
extends RefCounted
## Pedido de sugerencia (spec §16.1): lo que hay alrededor del caret en un script, sin el CodeEdit.

## Líneas de contexto a cada lado del caret que lleva el pedido.
const CONTEXT_ABOVE := 3
const CONTEXT_BELOW := 8

## Ruta `res://` del script.
var path: String = ""
## Texto completo del buffer (sin guardar incluido).
var text: String = ""
## Línea del caret (0-based) y lo que hay antes y después del caret en esa línea.
var line: int = 0
var line_prefix: String = ""
var line_suffix: String = ""
## Hasta CONTEXT_ABOVE líneas justo arriba del caret, la más cercana al final.
var previous_lines: PackedStringArray = []
## Hasta CONTEXT_BELOW líneas justo debajo, para descartar lo que ya está escrito.
var following: PackedStringArray = []
## La primera de `following` ("" si no hay).
var next_line: String = ""
## Indentación del editor (spec §16.6 paso 4).
var indent_spaces: bool = false
var indent_size: int = 4
## Pedido manual (Alt+\): ignora el debounce y la condición de fin de línea.
var manual: bool = false
var seq: int = 0


static func make(p_path: String, p_text: String, p_line: int, p_column: int) -> RefCounted:
	var lines := p_text.split("\n")
	var current: String = lines[p_line] if p_line < lines.size() else ""
	return from_lines(p_path, p_text, p_line, p_column, current,
		lines.slice(maxi(0, p_line - CONTEXT_ABOVE), p_line), lines.slice(p_line + 1, p_line + 1 + CONTEXT_BELOW))


## Igual que `make`, con las líneas ya leídas del CodeEdit (sin partir el buffer entero en cada tecla).
static func from_lines(p_path: String, p_text: String, p_line: int, p_column: int, current: String, above: PackedStringArray, below: PackedStringArray) -> RefCounted:
	var request := new()
	request.path = p_path
	request.text = p_text
	request.line = p_line
	request.line_prefix = current.left(p_column)
	request.line_suffix = current.substr(p_column)
	request.previous_lines = above
	request.following = below
	request.next_line = below[0] if not below.is_empty() else ""
	return request


## La indentación de un nivel según el editor.
func indent_unit() -> String:
	return " ".repeat(indent_size) if indent_spaces else "\t"


## La línea de arriba que no está vacía ("" si no hay en el contexto).
func previous_code_line() -> String:
	for i in range(previous_lines.size() - 1, -1, -1):
		if not previous_lines[i].strip_edges().is_empty():
			return previous_lines[i]
	return ""
