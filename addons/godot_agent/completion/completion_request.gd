@tool
extends RefCounted
## Pedido de sugerencia (spec §16.1): lo que hay alrededor del caret en un script, sin el CodeEdit.

## Ruta `res://` del script.
var path: String = ""
## Texto completo del buffer (sin guardar incluido).
var text: String = ""
## Línea del caret (0-based) y lo que hay antes y después del caret en esa línea.
var line: int = 0
var line_prefix: String = ""
var line_suffix: String = ""
## Línea siguiente a la del caret ("" si no hay), para descartar sugerencias que la repiten.
var next_line: String = ""
## Pedido manual (Alt+\): ignora el debounce y la condición de fin de línea.
var manual: bool = false
var seq: int = 0


static func make(p_path: String, p_text: String, p_line: int, p_column: int) -> RefCounted:
	var request := new()
	request.path = p_path
	request.text = p_text
	request.line = p_line
	var lines := p_text.split("\n")
	var current: String = lines[p_line] if p_line < lines.size() else ""
	request.line_prefix = current.left(p_column)
	request.line_suffix = current.substr(p_column)
	request.next_line = lines[p_line + 1] if p_line + 1 < lines.size() else ""
	return request


## Igual que `make`, con la línea del caret y la siguiente ya leídas del CodeEdit (sin partir el
## buffer entero en cada tecla).
static func from_lines(p_path: String, p_text: String, p_line: int, p_column: int, current: String, next: String) -> RefCounted:
	var request := new()
	request.path = p_path
	request.text = p_text
	request.line = p_line
	request.line_prefix = current.left(p_column)
	request.line_suffix = current.substr(p_column)
	request.next_line = next
	return request
