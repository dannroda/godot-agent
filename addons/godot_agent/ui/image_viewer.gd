@tool
extends AcceptDialog
## Visor de una imagen (las capturas del agente y del último playtest): abre ajustada a la ventana;
## la rueda hace zoom hacia el puntero, arrastrar la mueve y el doble clic alterna Ajustar / 100 %.
## Se libera al cerrarse. Uso: `ImageViewer.open(image, "Captura", self)`, o `ImageViewer.attach()`
## para que un clic en una miniatura la abra.

const AgentTheme := preload("agent_theme.gd")
const I18n := preload("../core/i18n.gd")

const MIN_ZOOM := 0.05
const MAX_ZOOM := 16.0
const ZOOM_STEP := 1.2
## Desde este zoom los píxeles se ven como cuadrados (sin filtro), para mirar de cerca.
const NEAREST_FROM_ZOOM := 2.0

var _image: Image
var _texture: Texture2D
var _canvas: Control
var _zoom_label: Label
var _zoom: float = 1.0
## Esquina superior izquierda de la imagen en el canvas.
var _offset: Vector2 = Vector2.ZERO
## Sigue ajustada a la ventana (al cambiar el tamaño se reajusta).
var _fit: bool = true
var _dragging: bool = false
var _save_dialog: FileDialog


static func open(image: Image, title_text: String, near: Node) -> void:
	var viewer: AcceptDialog = new()
	viewer.show_image(image, title_text, near)


## Un clic en la miniatura abre la imagen en grande. `get_image` devuelve la imagen del momento
## (o null si no hay).
static func attach(rect: TextureRect, get_image: Callable) -> void:
	rect.mouse_filter = Control.MOUSE_FILTER_STOP
	rect.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	rect.tooltip_text = I18n.t("Click to view full size")
	rect.gui_input.connect(func(event: InputEvent) -> void:
		var click := event as InputEventMouseButton
		if click == null or not click.pressed or click.button_index != MOUSE_BUTTON_LEFT:
			return
		var image: Image = get_image.call()
		if image != null:
			rect.accept_event()
			open(image, I18n.t("Screenshot"), rect)
	)


func show_image(image: Image, title_text: String, near: Node) -> void:
	_image = image
	_texture = ImageTexture.create_from_image(image)
	title = "%s · %d×%d" % [title_text, image.get_width(), image.get_height()]
	ok_button_text = I18n.t("Close")
	var host: Node = EditorInterface.get_base_control() if AgentTheme.has_editor() else near.get_tree().root
	host.add_child(self)
	popup_centered_ratio(0.85)
	_fit_to_view.call_deferred()


func _init() -> void:
	exclusive = false
	visibility_changed.connect(func() -> void:
		if not visible:
			queue_free()
	)
	var column := VBoxContainer.new()
	add_child(column)

	var toolbar := HBoxContainer.new()
	column.add_child(toolbar)
	var fit_button := Button.new()
	fit_button.text = I18n.t("Fit")
	fit_button.tooltip_text = I18n.t("Fit to the window (double click on the image)")
	fit_button.pressed.connect(_fit_to_view)
	toolbar.add_child(fit_button)
	var actual_button := Button.new()
	actual_button.text = "100 %"
	actual_button.tooltip_text = I18n.t("Actual size")
	actual_button.pressed.connect(func() -> void: _set_zoom(1.0, _canvas.size / 2.0))
	toolbar.add_child(actual_button)
	_zoom_label = Label.new()
	_zoom_label.add_theme_color_override(&"font_color", AgentTheme.MUTED)
	toolbar.add_child(_zoom_label)
	var hint := Label.new()
	hint.text = I18n.t("Wheel: zoom · drag: move")
	hint.add_theme_color_override(&"font_color", AgentTheme.MUTED)
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hint.clip_text = true
	toolbar.add_child(hint)
	var save_button := Button.new()
	save_button.text = I18n.t("Save PNG…")
	save_button.pressed.connect(_ask_save)
	toolbar.add_child(save_button)

	var frame := PanelContainer.new()
	frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	frame.add_theme_stylebox_override(&"panel", AgentTheme.panel(Color(0, 0, 0, 0.35), Color.TRANSPARENT, 4, 0))
	column.add_child(frame)
	_canvas = Control.new()
	_canvas.clip_contents = true
	_canvas.focus_mode = Control.FOCUS_CLICK
	_canvas.mouse_default_cursor_shape = Control.CURSOR_DRAG
	_canvas.custom_minimum_size = Vector2(AgentTheme.px(320), AgentTheme.px(200))
	_canvas.draw.connect(_draw_canvas)
	_canvas.gui_input.connect(_on_canvas_input)
	_canvas.resized.connect(func() -> void:
		if _fit:
			_fit_to_view()
	)
	frame.add_child(_canvas)


func _fit_to_view() -> void:
	if _image == null or _canvas.size.x <= 0.0 or _canvas.size.y <= 0.0:
		return
	var image_size := Vector2(_image.get_size())
	_zoom = clampf(minf(_canvas.size.x / image_size.x, _canvas.size.y / image_size.y), MIN_ZOOM, MAX_ZOOM)
	_offset = ((_canvas.size - image_size * _zoom) / 2.0).floor()
	_fit = true
	_update_view()


## Zoom manteniendo fijo el punto `anchor` del canvas.
func _set_zoom(zoom: float, anchor: Vector2) -> void:
	zoom = clampf(zoom, MIN_ZOOM, MAX_ZOOM)
	_offset = anchor - (anchor - _offset) * (zoom / _zoom)
	_zoom = zoom
	_fit = false
	_update_view()


func _update_view() -> void:
	_canvas.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST if _zoom >= NEAREST_FROM_ZOOM else CanvasItem.TEXTURE_FILTER_LINEAR
	_zoom_label.text = "%d %%" % roundi(_zoom * 100.0)
	_canvas.queue_redraw()


func _draw_canvas() -> void:
	if _texture:
		_canvas.draw_texture_rect(_texture, Rect2(_offset, Vector2(_image.get_size()) * _zoom), false)


func _on_canvas_input(event: InputEvent) -> void:
	var button := event as InputEventMouseButton
	if button and button.pressed:
		match button.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				_set_zoom(_zoom * ZOOM_STEP, button.position)
				_canvas.accept_event()
			MOUSE_BUTTON_WHEEL_DOWN:
				_set_zoom(_zoom / ZOOM_STEP, button.position)
				_canvas.accept_event()
			MOUSE_BUTTON_LEFT:
				if button.double_click:
					if _fit:
						_set_zoom(1.0, button.position)
					else:
						_fit_to_view()
				else:
					_dragging = true
	elif button and button.button_index == MOUSE_BUTTON_LEFT:
		_dragging = false
	var motion := event as InputEventMouseMotion
	if motion and _dragging:
		_offset += motion.relative
		_fit = false
		_canvas.queue_redraw()
	var key := event as InputEventKey
	if key and key.pressed:
		match key.keycode:
			KEY_PLUS, KEY_EQUAL, KEY_KP_ADD:
				_set_zoom(_zoom * ZOOM_STEP, _canvas.size / 2.0)
			KEY_MINUS, KEY_KP_SUBTRACT:
				_set_zoom(_zoom / ZOOM_STEP, _canvas.size / 2.0)
			KEY_0, KEY_KP_0:
				_fit_to_view()
			KEY_1, KEY_KP_1:
				_set_zoom(1.0, _canvas.size / 2.0)


func _ask_save() -> void:
	if _save_dialog == null:
		_save_dialog = FileDialog.new()
		_save_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
		_save_dialog.access = FileDialog.ACCESS_FILESYSTEM
		_save_dialog.filters = PackedStringArray(["*.png ; PNG"])
		_save_dialog.current_dir = ProjectSettings.globalize_path("res://")
		_save_dialog.current_file = "screenshot.png"
		_save_dialog.file_selected.connect(func(path: String) -> void:
			var error := _image.save_png(path)
			if error != OK:
				push_warning("Godot Agent: could not save %s (%s)" % [path, error_string(error)])
			elif AgentTheme.has_editor() and path.begins_with(ProjectSettings.globalize_path("res://")):
				EditorInterface.get_resource_filesystem().scan()
		)
		add_child(_save_dialog)
	_save_dialog.popup_centered_ratio(0.6)

