@tool
extends AcceptDialog
## Visor de una imagen (las capturas del agente y del último playtest): abre ajustada a la ventana;
## la rueda hace zoom hacia el puntero, arrastrar la mueve y el doble clic alterna Ajustar / 100 %.
## Se libera al cerrarse. Uso: `ImageViewer.open(image, "Captura", self)`, o `ImageViewer.attach()`
## para que un clic en una miniatura la abra.

const AgentTheme := preload("agent_theme.gd")
const I18n := preload("../core/i18n.gd")
const EditorWindows := preload("editor_windows.gd")

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
## Modo señalar (m11-37): un clic sin arrastre llama a esto con el punto en [0, 1] y cierra.
var _on_pick: Callable
var _press_at: Vector2 = Vector2.ZERO
## El botón se apretó acá con un clic simple (no el segundo de un doble clic, ni un press que empezó
## antes de abrir el visor) y lo que se arrastró desde entonces: un clic que arrastró, aunque vuelva
## cerca del punto de partida, no señala.
var _pick_press: bool = false
var _dragged: float = 0.0
## Cuánto puede moverse un clic y seguir contando como clic.
const PICK_SLOP_PX := 4.0
var _hint: Label


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


## Abre la imagen para señalar algo en ella (m11-37): un clic llama a `on_pick(uv)` con el punto en
## [0, 1] (origen arriba a la izquierda) y cierra el visor; arrastrar y la rueda siguen funcionando.
static func pick(image: Image, title_text: String, near: Node, on_pick: Callable) -> void:
	var viewer: AcceptDialog = new()
	viewer.set(&"_on_pick", on_pick)
	viewer.show_image(image, title_text, near)


func show_image(image: Image, title_text: String, near: Node) -> void:
	_image = image
	_texture = ImageTexture.create_from_image(image)
	title = "%s · %d×%d" % [title_text, image.get_width(), image.get_height()]
	ok_button_text = I18n.t("Cancel") if _on_pick.is_valid() else I18n.t("Close")
	if _on_pick.is_valid():
		_hint.text = I18n.t("Click on what you want to point at · wheel: zoom · drag: move")
		_canvas.mouse_default_cursor_shape = Control.CURSOR_CROSS
	var host: Node = EditorInterface.get_base_control() if AgentTheme.has_editor() else near.get_tree().root
	host.add_child(self)
	popup_centered_ratio(0.85)
	_fit_to_view.call_deferred()


func _init() -> void:
	exclusive = false
	visibility_changed.connect(func() -> void:
		if not visible:
			EditorWindows.free_later(self)
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
	_hint = Label.new()
	_hint.text = I18n.t("Wheel: zoom · drag: move")
	_hint.add_theme_color_override(&"font_color", AgentTheme.MUTED)
	_hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_hint.clip_text = true
	toolbar.add_child(_hint)
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
					_pick_press = false  # el doble clic cambia el zoom; no señala al soltar
					if _fit:
						_set_zoom(1.0, button.position)
					else:
						_fit_to_view()
				else:
					_dragging = true
					_press_at = button.position
					_pick_press = true
					_dragged = 0.0
	elif button and button.button_index == MOUSE_BUTTON_LEFT:
		_dragging = false
		var was_click := _pick_press and _dragged < PICK_SLOP_PX and button.position.distance_to(_press_at) < PICK_SLOP_PX
		_pick_press = false
		if _on_pick.is_valid() and was_click:
			_pick_at(button.position)
	var motion := event as InputEventMouseMotion
	if motion and _dragging:
		var before := _dragged
		_dragged += motion.relative.length()
		# Al señalar, el temblor de un clic no mueve la imagen: arrastra recién pasado el margen, y
		# entonces con todo lo acumulado desde el press.
		if not _on_pick.is_valid() or before >= PICK_SLOP_PX:
			_offset += motion.relative
		elif _dragged >= PICK_SLOP_PX:
			_offset += motion.position - _press_at
		if not _on_pick.is_valid() or _dragged >= PICK_SLOP_PX:
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


## Un clic en el canvas, en modo señalar: el punto de la imagen en [0, 1], si cae adentro.
func _pick_at(canvas_point: Vector2) -> void:
	var uv := (canvas_point - _offset) / (Vector2(_image.get_size()) * _zoom)
	if uv.x < 0.0 or uv.y < 0.0 or uv.x > 1.0 or uv.y > 1.0:
		return
	var callback := _on_pick
	hide()
	callback.call(uv)


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

