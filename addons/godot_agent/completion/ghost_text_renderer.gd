@tool
extends RefCounted
## Dibuja el ghost text sobre el CodeEdit (spec §16.7), desde su señal `draw`, que se emite después
## de que el CodeEdit dibujó su texto. La posición sale del caret y de `get_rect_at_line_column`,
## que ya contemplan scroll, wrap, gutters y zoom; fuente y tamaño son los del editor.

const DEFAULT_ALPHA := 0.75

## Color del texto (el de comentarios del theme del editor, atenuado). Lo fija CompletionService.
var color: Color = Color(0.6, 0.6, 0.6, DEFAULT_ALPHA)
## La línea ya armada (se rearma solo si cambian texto, fuente o ancho; el CodeEdit redibuja seguido).
var _line: TextLine
var _tail: TextLine
var _cache_key: Array = []


## `suffix`: lo que hay a la derecha del caret (solo cierres, p. ej. `")` del autocierre). El ghost
## text va en el medio, así que el suffix se redibuja después de él, sobre un fondo que tapa el
## original.
func draw(code_edit: CodeEdit, text: String, line: int, column: int, suffix: String = "") -> void:
	var anchor := anchor_position(code_edit, line, column)
	if anchor.x < 0.0:
		return
	var font := code_edit.get_theme_font(&"font")
	var font_size := code_edit.get_theme_font_size(&"font_size")
	if font == null:
		return
	# Recortado al área de texto: sin pisar el minimapa ni la barra de scroll.
	var right := code_edit.size.x
	if code_edit.is_drawing_minimap():
		right -= code_edit.get_minimap_width()
	if code_edit.get_v_scroll_bar().visible:
		right -= code_edit.get_v_scroll_bar().size.x
	var width := right - anchor.x
	if width <= 0.0:
		return
	var shown := text.get_slice("\n", 0)
	var tail := suffix.strip_edges(false, true)
	var key := [shown, tail, font, font_size, int(width)]
	if key != _cache_key:
		_cache_key = key
		_line = _text_line(shown, font, font_size, width)
		_tail = _text_line(tail, font, font_size, maxf(1.0, width - _line.get_size().x)) if not tail.is_empty() else null
	var line_height := float(code_edit.get_line_height())
	var y := anchor.y + (line_height - _line.get_size().y) / 2.0
	var canvas := code_edit.get_canvas_item()
	if _tail:
		var cover := Rect2(anchor.x, anchor.y, minf(width, _line.get_size().x + _tail.get_size().x + 2.0), line_height)
		code_edit.draw_rect(cover, code_edit.get_theme_color(&"background_color"))
		if code_edit.highlight_current_line and code_edit.get_caret_line() == line:
			code_edit.draw_rect(cover, code_edit.get_theme_color(&"current_line_color"))
	_line.draw(canvas, Vector2(anchor.x, y), color)
	if _tail:
		_tail.draw(canvas, Vector2(anchor.x + _line.get_size().x, y), code_edit.get_theme_color(&"font_color"))


static func _text_line(text: String, font: Font, font_size: int, width: float) -> TextLine:
	var text_line := TextLine.new()
	text_line.add_string(text, font, font_size)
	text_line.width = width
	text_line.text_overrun_behavior = TextServer.OVERRUN_TRIM_CHAR
	return text_line


## Esquina superior izquierda donde empieza el ghost text, o x < 0 si no está a la vista.
## El ghost solo se dibuja con el caret en su ancla (moverlo lo invalida), así que la x es la del
## caret dibujado: `get_rect_at_line_column` al final de la línea devuelve el carácter anterior
## (medido en 4.4 y 4.8) y no sirve para la x. La y es la de la fila del caret.
static func anchor_position(code_edit: CodeEdit, line: int, column: int) -> Vector2:
	if line < 0 or line >= code_edit.get_line_count() or not code_edit.is_caret_visible():
		return Vector2(-1, -1)
	var row := code_edit.get_rect_at_line_column(line, mini(column, code_edit.get_line(line).length()))
	if row.position.x < 0:
		return Vector2(-1, -1)
	return Vector2(code_edit.get_caret_draw_pos().x, row.position.y)
