@tool
extends VBoxContainer
## Tarjeta 3D de un modelo en el chat (m11-89), en el resultado de preview_model: el modelo ya
## importado, en un mundo propio con la luz y el fondo de preview_model, que se puede orbitar
## (arrastrar), mover (Shift + arrastrar o botón del medio) y acercar (rueda). Encuadrar lo vuelve a
## centrar sin cambiar el ángulo, Restablecer vuelve al ángulo inicial y Ampliar la abre en una ventana.
##
## Memoria (m7-55): el SubViewport no se dibuja solo; se dibuja una vez cuando algo cambió y la tarjeta
## está en pantalla (fuera de pantalla queda en UPDATE_DISABLED). La geometría y el viewport se sueltan
## cuando la tarjeta se oculta (grupo plegado), sale del árbol o se libera (las entradas que se sueltan
## del chat). Como mucho MAX_LIVE tarjetas vivas en todo el editor: una nueva suelta la más vieja, que
## queda con su miniatura y un botón para volver a verla en 3D. Las de una sesión reanudada arrancan
## con la miniatura sola.

const ModelTools := preload("../../../mcp/tools/model_tools.gd")
const AgentTheme := preload("../../agent_theme.gd")
const I18n := preload("../../../core/i18n.gd")
const EditorWindows := preload("../../editor_windows.gd")

## Grupo de las tarjetas con un modelo cargado (se cuentan entre todos los chats abiertos).
const LIVE_GROUP := &"godot_agent_live_model_cards"
const MAX_LIVE := 3
const HEIGHT := 220
const FOV := 50.0
const START_HEADING := 0.0
const START_ELEVATION := 30.0
const MAX_ELEVATION := 85.0
## Grados por píxel al orbitar.
const ORBIT_SPEED := 0.4
const ZOOM_STEP := 1.15
## Distancia al centro en radios del modelo al encuadrar (la de preview_model).
const FRAME_RADII := ModelTools.PREVIEW_RADII

## El modelo (res://).
var path: String = ""
## La primera vista de preview_model, o null.
var thumbnail: Texture2D
## Debería estar en 3D cuando se ve. false: miniatura y botón «Ver en 3D».
var wanted: bool = false

var _screen: Control
var _thumb_rect: TextureRect
var _overlay: CenterContainer
var _view_button: Button
var _status: Label
var _buttons: Array[Button] = []
var _container: SubViewportContainer
var _viewport: SubViewport
var _camera: Camera3D
var _box: AABB
var _target: Vector3
var _heading: float = START_HEADING
var _elevation: float = START_ELEVATION
var _distance: float = 1.0
var _dirty: bool = false
## Orden de llegada al 3D: la de menor valor es la primera que se suelta.
var _live_since: int = 0
var _dialog: AcceptDialog
var _scroll: ScrollContainer
var _go_live_queued: bool = false


## `live`: arranca en 3D (un resultado nuevo); false, solo la miniatura (una sesión reanudada).
func setup(model_path: String, thumb: Texture2D, live: bool) -> void:
	path = model_path
	thumbnail = thumb
	wanted = live


func _ready() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_theme_constant_override(&"separation", AgentTheme.px(2))
	var frame := PanelContainer.new()
	frame.add_theme_stylebox_override(&"panel", AgentTheme.panel(Color(0, 0, 0, 0.35), Color(1, 1, 1, 0.08), 4, 0))
	add_child(frame)
	_screen = Control.new()
	_screen.clip_contents = true
	_screen.custom_minimum_size = Vector2(0, AgentTheme.px(HEIGHT))
	_screen.focus_mode = Control.FOCUS_CLICK
	_screen.gui_input.connect(func(event: InputEvent) -> void: handle_input(event, _screen))
	_screen.resized.connect(func() -> void: _dirty = true)
	frame.add_child(_screen)
	_thumb_rect = TextureRect.new()
	_thumb_rect.texture = thumbnail
	_thumb_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_thumb_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_thumb_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_thumb_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_screen.add_child(_thumb_rect)
	_overlay = CenterContainer.new()
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_screen.add_child(_overlay)
	var column := VBoxContainer.new()
	_overlay.add_child(column)
	_view_button = Button.new()
	_view_button.text = I18n.t("View in 3D")
	_view_button.tooltip_text = I18n.t("Load the model to turn it around (at most %d at a time)") % MAX_LIVE
	_view_button.pressed.connect(func() -> void:
		wanted = true
		go_live()
	)
	column.add_child(_view_button)
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.custom_minimum_size.x = AgentTheme.px(200)
	_status.add_theme_color_override(&"font_color", AgentTheme.MUTED)
	_status.visible = false
	column.add_child(_status)
	var toolbar := HBoxContainer.new()
	add_child(toolbar)
	_buttons.append(_tool_button(toolbar, I18n.t("Frame"), I18n.t("Center the model again, from the same angle"), frame_model))
	_buttons.append(_tool_button(toolbar, I18n.t("Reset"), I18n.t("Back to the first angle"), reset_view))
	_buttons.append(_tool_button(toolbar, I18n.t("Enlarge"), I18n.t("Open it in a large window"), enlarge))
	var hint := Label.new()
	hint.text = I18n.t("drag: orbit · Shift+drag: pan · wheel: zoom")
	hint.add_theme_color_override(&"font_color", AgentTheme.MUTED)
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hint.clip_text = true
	hint.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	toolbar.add_child(hint)
	set_process(false)
	_show_state()
	if wanted:
		_queue_go_live()


func _tool_button(toolbar: HBoxContainer, text: String, tooltip: String, action: Callable) -> Button:
	var button := Button.new()
	button.flat = true
	button.text = text
	button.tooltip_text = tooltip
	button.pressed.connect(action)
	toolbar.add_child(button)
	return button


func is_live() -> bool:
	return _viewport != null


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_VISIBILITY_CHANGED:
			if not is_visible_in_tree():
				release(true)
			elif wanted:
				_queue_go_live()
		NOTIFICATION_EXIT_TREE:
			release(true)
		NOTIFICATION_ENTER_TREE:
			_scroll = null
			if wanted and is_node_ready():
				_queue_go_live()


func _queue_go_live() -> void:
	if _go_live_queued:
		return
	_go_live_queued = true
	(func() -> void:
		_go_live_queued = false
		if wanted and is_inside_tree() and is_visible_in_tree():
			go_live()
	).call_deferred()


## Carga el modelo y lo muestra en 3D. Suelta la tarjeta viva más vieja si ya hay MAX_LIVE. false si
## no se pudo (el error queda en la tarjeta).
func go_live() -> bool:
	if is_live():
		return true
	if not is_inside_tree() or not is_node_ready():
		return false
	var plan := ModelTools.plan_preview({"path": path, "angles": 1})
	if plan.has("error"):
		_fail(str(plan.error))
		return false
	var model := ModelTools.model_node(plan.resource)
	plan.clear()
	if model == null:
		_fail(I18n.t("%s is not a 3D scene.") % path)
		return false
	_make_room()
	_viewport = ModelTools.stage()
	_viewport.name = "ModelCardWorld"
	_viewport.add_child(model)
	_camera = Camera3D.new()
	_camera.fov = FOV
	_camera.current = true
	_viewport.add_child(_camera)
	_container = SubViewportContainer.new()
	_container.stretch = true
	_container.mouse_filter = Control.MOUSE_FILTER_IGNORE  # la entrada la toma _screen
	_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_container.add_child(_viewport)
	_screen.add_child(_container)
	_screen.move_child(_container, 0)
	_box = ModelTools.model_box(model)
	if _box.size == Vector3.ZERO:
		release(false)
		_fail(I18n.t("%s has nothing to draw (no visible meshes).") % path)
		return false
	add_to_group(LIVE_GROUP)
	_live_since = Time.get_ticks_usec()
	_status.visible = false
	reset_view()
	set_process(true)
	_show_state()
	return true


## Suelta la geometría y el viewport; queda la miniatura. `keep_wanted`: vuelve sola al 3D cuando la
## tarjeta se vuelva a ver (se ocultó); si no, hace falta el botón (la soltó otra tarjeta).
func release(keep_wanted: bool) -> void:
	wanted = wanted and keep_wanted
	if _dialog:
		var dialog := _dialog
		_dialog = null
		_close_dialog(dialog)
	if not is_live():
		return
	if is_in_group(LIVE_GROUP):
		remove_from_group(LIVE_GROUP)
	_container.get_parent().remove_child(_container)
	_container.queue_free()
	_container = null
	_viewport = null
	_camera = null
	set_process(false)
	if is_node_ready():
		_show_state()


## Las tarjetas vivas que hay que soltar para que entre una más.
func _make_room() -> void:
	if not is_inside_tree():
		return
	var live: Array = get_tree().get_nodes_in_group(LIVE_GROUP).filter(func(card: Node) -> bool:
		return card != self and not card.is_queued_for_deletion())
	live.sort_custom(func(a: Node, b: Node) -> bool: return int(a.get(&"_live_since")) < int(b.get(&"_live_since")))
	while live.size() >= MAX_LIVE:
		live.pop_front().call(&"release", false)


func _fail(message: String) -> void:
	wanted = false
	_status.text = message
	_status.visible = true
	_show_state()


func _show_state() -> void:
	var live := is_live()
	_thumb_rect.visible = not live and thumbnail != null
	_overlay.visible = not live
	_view_button.visible = not live and not _status.visible
	for button: Button in _buttons:
		button.disabled = not live
	_screen.mouse_default_cursor_shape = Control.CURSOR_DRAG if live else Control.CURSOR_ARROW


## Centra el modelo y lo acerca hasta que entra, sin cambiar el ángulo.
func frame_model() -> void:
	if not is_live():
		return
	_target = _box.get_center()
	_distance = maxf(_box.size.length() / 2.0, 0.001) * FRAME_RADII
	_place_camera()


## El ángulo inicial (el de la primera vista de preview_model), encuadrado.
func reset_view() -> void:
	_heading = START_HEADING
	_elevation = START_ELEVATION
	frame_model()


func orbit(degrees: Vector2) -> void:
	_heading = fposmod(_heading - degrees.x, 360.0)
	_elevation = clampf(_elevation + degrees.y, -MAX_ELEVATION, MAX_ELEVATION)
	_place_camera()


## Mueve el centro de la vista `pixels` en pantalla (el modelo sigue al puntero).
func pan(pixels: Vector2) -> void:
	if not is_live():
		return
	var height := maxf(_screen.size.y, 1.0)
	var per_pixel := 2.0 * _distance * tan(deg_to_rad(FOV) / 2.0) / height
	var basis := _camera.global_transform.basis
	_target += (-basis.x * pixels.x + basis.y * pixels.y) * per_pixel
	_place_camera()


## factor < 1 acerca.
func zoom(factor: float) -> void:
	var radius := maxf(_box.size.length() / 2.0, 0.001)
	_distance = clampf(_distance * factor, radius * 0.05, radius * 50.0)
	_place_camera()


func camera_transform() -> Transform3D:
	return _camera.global_transform if is_live() else Transform3D()


func _place_camera() -> void:
	if not is_live():
		return
	var radius := maxf(_box.size.length() / 2.0, 0.001)
	_camera.near = maxf(_distance / 1000.0, 0.0005)
	_camera.far = _distance + radius * 4.0
	var heading := deg_to_rad(_heading)
	var elevation := deg_to_rad(_elevation)
	var offset := Vector3(sin(heading) * cos(elevation), sin(elevation), cos(heading) * cos(elevation)) * _distance
	_camera.global_transform = Transform3D(Basis.looking_at(-offset, Vector3.UP), _target + offset)
	_dirty = true


## Arrastrar orbita, Shift + arrastrar o el botón del medio mueven, la rueda acerca. `on`: el
## control que recibió el evento (la tarjeta o la ventana ampliada).
func handle_input(event: InputEvent, on: Control) -> void:
	if not is_live():
		return
	var button := event as InputEventMouseButton
	if button and button.pressed:
		match button.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				zoom(1.0 / ZOOM_STEP)
				on.accept_event()
			MOUSE_BUTTON_WHEEL_DOWN:
				zoom(ZOOM_STEP)
				on.accept_event()
			MOUSE_BUTTON_LEFT, MOUSE_BUTTON_MIDDLE:
				on.grab_focus()
				on.accept_event()
		return
	var motion := event as InputEventMouseMotion
	if motion == null:
		return
	if motion.button_mask & MOUSE_BUTTON_MASK_MIDDLE or (motion.button_mask & MOUSE_BUTTON_MASK_LEFT and motion.shift_pressed):
		pan(motion.relative)
		on.accept_event()
	elif motion.button_mask & MOUSE_BUTTON_MASK_LEFT:
		orbit(motion.relative * ORBIT_SPEED)
		on.accept_event()


## Se dibuja una vez por cambio y solo en pantalla: fuera queda en UPDATE_DISABLED. UPDATE_ONCE dibuja
## al final del frame pero la propiedad no vuelve sola a DISABLED: se la vuelve en el frame siguiente.
func _process(_delta: float) -> void:
	if not is_live():
		return
	if _dirty and is_on_screen():
		_dirty = false
		_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	elif _viewport.render_target_update_mode == SubViewport.UPDATE_ONCE:
		_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED


## Se ve algo de la vista 3D: dentro del área visible del chat (o de la ventana ampliada).
func is_on_screen() -> bool:
	if not is_live() or not _container.is_visible_in_tree():
		return false
	var rect := _container.get_global_rect()
	if _dialog:
		return true
	if _scroll == null or not is_instance_valid(_scroll):
		_scroll = _scroll_ancestor()
	var visible_rect := _scroll.get_global_rect() if _scroll else get_viewport_rect()
	return rect.intersects(visible_rect)


func _scroll_ancestor() -> ScrollContainer:
	var node := get_parent()
	while node:
		if node is ScrollContainer:
			return node
		node = node.get_parent()
	return null


## La vista 3D en una ventana grande; al cerrarla vuelve a la tarjeta.
func enlarge() -> void:
	if not is_live() or _dialog:
		return
	_dialog = AcceptDialog.new()
	_dialog.exclusive = false
	_dialog.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED  # cuelga del editor: los textos ya pasan por I18n
	_dialog.title = "%s · %s" % [path.get_file(), I18n.t("drag: orbit · Shift+drag: pan · wheel: zoom")]
	_dialog.ok_button_text = I18n.t("Close")
	var dialog := _dialog
	dialog.visibility_changed.connect(func() -> void:
		if not dialog.visible and _dialog == dialog:
			_dialog = null
			_close_dialog(dialog)
	)
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(AgentTheme.px(480), AgentTheme.px(360))
	dialog.add_child(holder)
	_screen.remove_child(_container)
	holder.add_child(_container)
	holder.mouse_default_cursor_shape = Control.CURSOR_DRAG
	holder.focus_mode = Control.FOCUS_CLICK
	holder.gui_input.connect(func(event: InputEvent) -> void: handle_input(event, holder))
	holder.resized.connect(func() -> void: _dirty = true)
	_status.text = I18n.t("Shown in the large window")
	_status.visible = true
	_overlay.visible = true
	_view_button.visible = false
	var host: Node = AgentTheme.editor().get_base_control() if AgentTheme.has_editor() else get_tree().root
	host.add_child(dialog)
	dialog.popup_centered_ratio(0.75)
	_dirty = true


## Vuelve a poner la vista 3D en la tarjeta (si sigue viva) y libera la ventana.
func _close_dialog(dialog: AcceptDialog) -> void:
	if _container and _container.get_parent() != _screen:
		_container.get_parent().remove_child(_container)
		_screen.add_child(_container)
		_screen.move_child(_container, 0)
		_dirty = true
	if is_node_ready():
		_status.visible = false
		_show_state()
	if is_instance_valid(dialog):
		if dialog.is_inside_tree():
			EditorWindows.free_later(dialog)
		else:
			dialog.queue_free()
