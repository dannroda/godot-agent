@tool
extends PanelContainer
## Lista de sugerencias del composer, arriba del texto (como la del chat de VS Code): título, una fila
## por opción con el detalle atenuado, hasta MAX_ROWS filas visibles y scroll. No toma el foco: el
## composer le pasa las flechas, Enter, Tab y Esc mientras sigue escribiendo en su CodeEdit.

signal picked(item: Dictionary)

const AgentTheme := preload("../agent_theme.gd")

const MAX_ROWS := 10
## Parte del ancho que puede ocupar el nombre cuando hay detalle (el resto es la descripción).
const NAME_SHARE := 0.55
## Ancho mínimo (sin escalar) para mostrar el detalle; más angosta, queda solo en el tooltip.
const DETAIL_MIN_WIDTH := 380.0

var _title: Label
var _tree: Tree
var _root: TreeItem
var _name_width: float = 0.0
var _has_detail: bool = false


func _init() -> void:
	visible = false
	focus_mode = Control.FOCUS_NONE
	var column := VBoxContainer.new()
	column.add_theme_constant_override(&"separation", AgentTheme.px(2))
	add_child(column)
	_title = Label.new()
	_title.add_theme_color_override(&"font_color", AgentTheme.MUTED)
	_title.add_theme_font_size_override(&"font_size", AgentTheme.px(12))
	column.add_child(_title)
	_tree = Tree.new()
	_tree.columns = 2
	_tree.hide_root = true
	_tree.focus_mode = Control.FOCUS_NONE
	_tree.select_mode = Tree.SELECT_ROW
	_tree.scroll_horizontal_enabled = false
	_tree.set_column_clip_content(0, true)
	_tree.set_column_clip_content(1, true)
	_tree.resized.connect(_size_columns)
	_tree.add_theme_stylebox_override(&"panel", StyleBoxEmpty.new())
	_tree.add_theme_stylebox_override(&"focus", StyleBoxEmpty.new())
	_tree.add_theme_constant_override(&"h_separation", AgentTheme.px(12))
	_tree.item_mouse_selected.connect(func(_position: Vector2, button: int) -> void:
		if button == MOUSE_BUTTON_LEFT:
			_pick_selected())
	column.add_child(_tree)


func _ready() -> void:
	add_theme_stylebox_override(&"panel", AgentTheme.panel(
		get_theme_color(&"base_color", &"Editor").lightened(0.04) if has_theme_color(&"base_color", &"Editor") else Color(0.13, 0.14, 0.16),
		Color(1, 1, 1, 0.12), 6, 6))


## Muestra `items` ({label, detail?, insert}) con `title` arriba; con `empty_message` y sin items,
## una fila que no se puede elegir. Sin items ni mensaje, se oculta.
func show_items(title: String, items: Array[Dictionary], empty_message: String = "") -> void:
	if items.is_empty() and empty_message.is_empty():
		close()
		return
	_title.text = title
	_tree.clear()
	_root = _tree.create_item()
	_has_detail = false
	_name_width = 0.0
	var font := _tree.get_theme_font(&"font")
	var font_size := _tree.get_theme_font_size(&"font_size")
	if items.is_empty():
		var row := _tree.create_item(_root)
		row.set_text(0, empty_message)
		row.set_custom_color(0, AgentTheme.MUTED)
		row.set_selectable(0, false)
		row.set_selectable(1, false)
	for item: Dictionary in items:
		var row := _tree.create_item(_root)
		row.set_text(0, str(item.label))
		row.set_metadata(0, item)
		row.set_text_overrun_behavior(0, TextServer.OVERRUN_TRIM_ELLIPSIS)
		row.set_tooltip_text(0, str(item.label))
		if font:
			_name_width = maxf(_name_width, font.get_string_size(str(item.label), HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x)
		var detail := str(item.get("detail", ""))
		if not detail.is_empty():
			_has_detail = true
			row.set_text(1, detail)
			row.set_custom_color(1, AgentTheme.MUTED)
			row.set_text_overrun_behavior(1, TextServer.OVERRUN_TRIM_ELLIPSIS)
			row.set_tooltip_text(1, detail)
			row.set_tooltip_text(0, "%s\n%s" % [item.label, detail])
	visible = true
	_size_columns()
	var first := _root.get_first_child()
	if first and first.is_selectable(0):
		first.select(0)
		_tree.scroll_to_item(first)
	_fit.call_deferred(maxi(items.size(), 1))


func close() -> void:
	visible = false
	_tree.clear()
	_root = null


func is_open() -> bool:
	return visible and _root != null


## Mueve la selección `delta` filas (con vuelta al otro extremo).
func move(delta: int) -> void:
	var count := item_count()
	if count == 0:
		return
	var index := (selected_index() + delta) % count
	if index < 0:
		index += count
	var row := _root.get_child(index)
	row.select(0)
	_tree.scroll_to_item(row)


func item_count() -> int:
	if _root == null or _root.get_first_child() == null or not _root.get_first_child().is_selectable(0):
		return 0
	return _root.get_child_count()


func selected_index() -> int:
	var row := _tree.get_selected()
	return row.get_index() if row else -1


## La opción elegida, o {} si no hay.
func selected_item() -> Dictionary:
	var row := _tree.get_selected()
	return row.get_metadata(0) if row and row.get_metadata(0) is Dictionary else {}


func pick_selected() -> bool:
	return _pick_selected()


func _pick_selected() -> bool:
	var item := selected_item()
	if item.is_empty():
		return false
	picked.emit(item)
	return true


## Alto para mostrar hasta MAX_ROWS filas; con más, scroll.
func _fit(rows: int) -> void:
	if _root == null or _root.get_first_child() == null:
		return
	var row_height := _tree.get_item_area_rect(_root.get_first_child()).size.y + _tree.get_theme_constant(&"v_separation")
	if row_height <= 0.0:
		row_height = AgentTheme.px(26)
	_tree.custom_minimum_size = Vector2(0, mini(rows, MAX_ROWS) * row_height + AgentTheme.px(6))


## Con detalle y lugar: el nombre toma lo que necesita, hasta NAME_SHARE del ancho. Si no, el
## nombre ocupa todo y el detalle queda en el tooltip.
func _size_columns() -> void:
	var detail := _has_detail and _tree.size.x >= AgentTheme.px(DETAIL_MIN_WIDTH)
	_tree.set_column_expand(0, not detail)
	_tree.set_column_expand(1, detail)
	var padding := AgentTheme.px(24)
	_tree.set_column_custom_minimum_width(0, int(minf(_name_width + padding, _tree.size.x * NAME_SHARE)) if detail else 0)
	_tree.set_column_custom_minimum_width(1, 0)
