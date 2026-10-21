@tool
extends RefCounted
## Dibuja el ghost text sobre el CodeEdit (spec §16.7), desde su señal `draw`, en un canvas item
## propio hijo del CodeEdit: lo que se dibuja en la señal queda debajo del texto en 4.8 (el `")` del
## autocierre se veía encima de la sugerencia), un hijo siempre va encima. La posición sale del caret
## y de `get_rect_at_line_column`, que ya contemplan scroll, wrap, gutters y zoom; fuente y tamaño
## son los del editor.
## Multilínea: Godot no permite líneas virtuales, así que la primera línea va inline y las demás en
## una caja casi opaca debajo de la línea del caret (o arriba, si abajo no entran), que tapa el código
## sin modificarlo.

const DEFAULT_ALPHA := 0.75
## Opacidad del fondo de la caja de las líneas siguientes (deja intuir lo que tapa). No usa el alpha
## del theme: en 4.4 el fondo del CodeEdit es translúcido y el código de abajo se leía a través.
const BOX_ALPHA := 0.96

## Color del texto (el de comentarios del theme del editor, atenuado). Lo fija CompletionService.
var color: Color = Color(0.6, 0.6, 0.6, DEFAULT_ALPHA)
## Lo ya armado (se rearma solo si cambian texto, fuente o ancho; el CodeEdit redibuja seguido).
## Dónde quedó la caja de las líneas siguientes en el último dibujo (vacío si no hubo; para tests).
var box: Rect2 = Rect2()
var _line: TextLine
var _tail: TextLine
var _rest: Array[TextLine] = []
var _cache_key: Array = []
var _overlay: RID
var _parent: RID


## `suffix`: lo que hay a la derecha del caret (solo cierres, p. ej. `")` del autocierre). El ghost
## text va en el medio, así que el suffix se redibuja después de él, sobre un fondo que tapa el
## original. Con suffix la sugerencia es de una línea (PostProcessor).
func draw(code_edit: CodeEdit, text: String, line: int, column: int, suffix: String = "") -> void:
	clear()
	box = Rect2()
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
	var bottom := code_edit.size.y
	if code_edit.get_h_scroll_bar().visible:
		bottom -= code_edit.get_h_scroll_bar().size.y
	var width := right - anchor.x
	if width <= 0.0:
		return
	var lines := text.split("\n")
	var tail := suffix.strip_edges(false, true)
	var column_zero := line_start_x(code_edit, line, column, anchor.x)
	var key := [text, tail, font, font_size, int(width), int(right - column_zero)]
	if key != _cache_key:
		_cache_key = key
		_line = _text_line(lines[0], font, font_size, width)
		_tail = _text_line(tail, font, font_size, maxf(1.0, width - _line.get_size().x)) if not tail.is_empty() else null
		_rest.clear()
		var tab := " ".repeat(maxi(1, code_edit.get_tab_size()))
		for i in range(1, lines.size()):
			_rest.append(_text_line(lines[i].replace("\t", tab), font, font_size, maxf(1.0, right - column_zero)))
	var line_height := float(code_edit.get_line_height())
	var y := anchor.y + (line_height - _line.get_size().y) / 2.0
	var canvas := _canvas(code_edit)
	# Todo recortado al área de texto: con scroll horizontal, la columna 0 de la caja queda a la
	# izquierda de los números de línea.
	var left := float(code_edit.get_total_gutter_width())
	RenderingServer.canvas_item_set_custom_rect(canvas, true, Rect2(left, 0.0, maxf(0.0, right - left), bottom))
	RenderingServer.canvas_item_set_clip(canvas, true)
	if _tail:
		# Desde después del caret, que queda debajo del overlay.
		var caret_width := float(code_edit.get_theme_constant(&"caret_width"))
		var cover := Rect2(anchor.x + caret_width, anchor.y, minf(width, _line.get_size().x + _tail.get_size().x + 2.0) - caret_width, line_height)
		RenderingServer.canvas_item_add_rect(canvas, cover, background_color(code_edit))
		if code_edit.highlight_current_line and code_edit.get_caret_line() == line:
			RenderingServer.canvas_item_add_rect(canvas, cover, code_edit.get_theme_color(&"current_line_color"))
	_line.draw(canvas, Vector2(anchor.x, y), color)
	if _tail:
		_tail.draw(canvas, Vector2(anchor.x + _line.get_size().x, y), code_edit.get_theme_color(&"font_color"))
	if not _rest.is_empty():
		_draw_box(canvas, Rect2(left, 0.0, right - left, bottom), anchor.y, column_zero, line_height, background_color(code_edit))


## Borra lo dibujado (el overlay no se limpia solo cuando el CodeEdit se redibuja).
func clear() -> void:
	if _overlay.is_valid():
		RenderingServer.canvas_item_clear(_overlay)


func release() -> void:
	if _overlay.is_valid():
		RenderingServer.free_rid(_overlay)
	_overlay = RID()
	_parent = RID()


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and _overlay.is_valid():
		RenderingServer.free_rid(_overlay)


func _canvas(code_edit: CodeEdit) -> RID:
	if _overlay.is_valid() and _parent == code_edit.get_canvas_item():
		return _overlay
	release()
	_parent = code_edit.get_canvas_item()
	_overlay = RenderingServer.canvas_item_create()
	RenderingServer.canvas_item_set_parent(_overlay, _parent)
	return _overlay


## Las líneas siguientes en una caja desde el borde del área de texto, debajo de la línea del caret;
## si abajo no entran y arriba hay más lugar (caret en la última fila visible), arriba. Recortada al
## alto visible.
func _draw_box(canvas: RID, area: Rect2, line_y: float, column_zero: float, line_height: float, background: Color) -> void:
	var below := int((area.end.y - line_y - line_height) / line_height)
	var above := int(line_y / line_height)
	var rows := mini(_rest.size(), below)
	var top := line_y + line_height
	if below < _rest.size() and above > below:
		rows = mini(_rest.size(), above)
		top = line_y - rows * line_height
	if rows <= 0:
		return
	box = Rect2(area.position.x, top, area.size.x, rows * line_height)
	RenderingServer.canvas_item_add_rect(canvas, box, Color(background, BOX_ALPHA))
	var corners := PackedVector2Array([box.position, Vector2(box.end.x, box.position.y), box.end, Vector2(box.position.x, box.end.y), box.position])
	RenderingServer.canvas_item_add_polyline(canvas, corners, PackedColorArray([Color(color, color.a * 0.35)]), 1.0)
	for i in rows:
		var row_y := top + i * line_height + (line_height - _rest[i].get_size().y) / 2.0
		_rest[i].draw(canvas, Vector2(column_zero, row_y), color)


## El fondo del área de texto: el Script Editor deja `background_color` transparente y pinta el
## fondo con el stylebox `normal`.
static func background_color(code_edit: CodeEdit) -> Color:
	var background := code_edit.get_theme_color(&"background_color")
	if background.a > 0.0:
		return background
	var style := code_edit.get_theme_stylebox(&"normal") as StyleBoxFlat
	return style.bg_color if style else Color(0.12, 0.12, 0.12)


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


## x de la columna 0 de la línea (con el scroll horizontal): la del primer carácter, o la del caret
## si la línea está vacía o el caret está en la columna 0.
static func line_start_x(code_edit: CodeEdit, line: int, column: int, caret_x: float) -> float:
	if column == 0 or code_edit.get_line(line).is_empty():
		return caret_x
	return code_edit.get_rect_at_line_column(line, 0).position.x
