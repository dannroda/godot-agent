extends RefCounted
## La UI del juego como la ve un jugador (m15-09): textos en pantalla, controles y actuar sobre ellos.
## Un clic va al viewport como un mouse real, así que un overlay encima lo bloquea; si nadie lo toma
## es un problema que se reporta, no se aprieta el botón por atrás (Autopilot sí, con `via: signal`).
## Basado en lib/ui.gd de Autopilot (ramenvr/autopilot, Apache 2.0).

const NOT_BY_INPUT := "not by input"

var _host: Node


func _init(host: Node) -> void:
	_host = host


## {"<UI>.<nombre>": texto} de lo que se ve en pantalla.
func texts() -> Dictionary:
	var result := {}
	var with_text: Array[Control] = []
	for control: Control in _controls():
		if not _text_of(control).strip_edges().is_empty():
			with_text.append(control)
	for pair: Array in _keyed(with_text):
		result[pair[0]] = _text_of(pair[1])
	return result


## Una línea por control interactivo que se ve: id, tipo, texto, posición en píxeles y estado.
func list() -> PackedStringArray:
	var interactive: Array[Control] = []
	for control: Control in _controls():
		if not _kind(control).is_empty():
			interactive.append(control)
	var lines: PackedStringArray = []
	for pair: Array in _keyed(interactive):
		lines.append(_describe(pair[0], pair[1]))
	return lines


## Actúa sobre el control `id`. {text} o {error}.
func act(params: Dictionary) -> Dictionary:
	var id := str(params.get("id", ""))
	var control := _find(id)
	if control == null:
		return {"error": "No control '%s' on screen. Current ones:\n%s" % [id, "\n".join(list())]}
	if control is BaseButton and (control as BaseButton).disabled:
		return {"error": "%s is disabled." % id}
	var action := str(params.get("action", "click"))
	match action:
		"click":
			return _click(id, control, params)
		"right_click":
			_push_mouse(control, MOUSE_BUTTON_RIGHT)
			return {"text": "Right-clicked %s." % id}
		"double_click":
			_push_mouse(control, MOUSE_BUTTON_LEFT, true)
			return {"text": "Double-clicked %s." % id}
		"focus":
			control.grab_focus()
			return {"text": "%s has the focus: type with game_input {text}." % id}
		"set":
			return _set_value(id, control, params.get("value"))
	return {"error": "Unknown action '%s' (click, right_click, double_click, focus, set)." % action}


func _click(id: String, control: Control, params: Dictionary) -> Dictionary:
	if control is OptionButton:
		var combo := control as OptionButton
		var wanted := str(params.get("value", ""))
		for i: int in combo.item_count:
			if combo.get_item_text(i) == wanted:
				combo.select(i)
				combo.item_selected.emit(i)
				return {"text": "%s: selected '%s' (%s: the popup was not opened)." % [id, wanted, NOT_BY_INPUT]}
		return {"error": "%s has no option '%s'." % [id, wanted]}
	if not control is BaseButton:
		_push_mouse(control, MOUSE_BUTTON_LEFT)
		return {"text": "Clicked %s." % id}
	var state := {"taken": false}
	var mark := func(_on: Variant = null) -> void: state.taken = true
	var button := control as BaseButton
	button.pressed.connect(mark)
	button.toggled.connect(mark)
	_push_mouse(control, MOUSE_BUTTON_LEFT)
	var hovered := control.get_viewport().gui_get_hovered_control()
	if is_instance_valid(button):
		button.pressed.disconnect(mark)
		button.toggled.disconnect(mark)
	if state.taken or not is_instance_valid(button):
		return {"text": "Clicked %s." % id}
	var top := "`%s` is on top of it" % hovered.get_path() if hovered and hovered != button else "nothing took the click"
	return {"error": "The click on %s did nothing: %s. A player could not press it either." % [id, top]}


func _set_value(id: String, control: Control, value: Variant) -> Dictionary:
	var done := "%s set (%s: use a click or game_input to test the control itself)." % [id, NOT_BY_INPUT]
	if control is Range:
		(control as Range).value = float(value)
		return {"text": done}
	if control is LineEdit:
		(control as LineEdit).text = str(value)
		(control as LineEdit).text_changed.emit(str(value))
		return {"text": done}
	if control is TextEdit:
		(control as TextEdit).text = str(value)
		(control as TextEdit).text_changed.emit()
		return {"text": done}
	if control is BaseButton and (control as BaseButton).toggle_mode:
		(control as BaseButton).button_pressed = value == true
		return {"text": done}
	return {"error": "%s takes no value." % id}


func _find(id: String) -> Control:
	for pair: Array in _keyed(_controls()):
		if pair[0] == id:
			return pair[1]
	return null


## Dónde mandar un movimiento relativo del mouse (mirar en primera persona): `preferred`, salvo que
## haya encima un control que frena el mouse, porque la GUI lo atiende y el juego no lo ve; entonces
## otro punto libre del viewport. Un clic previo deja el mouse sobre un botón o un overlay.
static func free_point(viewport: Viewport, preferred: Vector2) -> Vector2:
	var size := viewport.get_visible_rect().size
	var stoppers: Array[Control] = []
	for node: Node in viewport.find_children("*", "Control", true, false):
		var control := node as Control
		if control.mouse_filter == Control.MOUSE_FILTER_STOP and control.get_viewport() == viewport and control.is_visible_in_tree():
			stoppers.append(control)
	for point: Vector2 in [preferred, size / 2.0, size * Vector2(0.5, 0.9), size * Vector2(0.9, 0.5), size * Vector2(0.9, 0.9), size * Vector2(0.1, 0.9)]:
		if not stoppers.any(func(control: Control) -> bool: return Rect2(Vector2.ZERO, control.size).has_point(control.get_global_transform_with_canvas().affine_inverse() * point)):
			return point
	return preferred


## Un clic con movimiento antes, adentro del viewport y en sus coordenadas (vale con stretch).
func _push_mouse(control: Control, button: MouseButton, double := false) -> void:
	var viewport := control.get_viewport()
	var at := control.get_global_transform_with_canvas() * (control.size / 2.0)
	var motion := InputEventMouseMotion.new()
	motion.position = at
	motion.global_position = at
	viewport.push_input(motion, true)
	for pressed: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = button
		event.pressed = pressed
		event.double_click = double and pressed
		event.position = at
		event.global_position = at
		if pressed:
			event.button_mask = (1 << (button - 1)) as MouseButtonMask
		viewport.push_input(event, true)


func _describe(id: String, control: Control) -> String:
	var at := control.get_global_transform_with_canvas() * (control.size / 2.0)
	var text := "%s %s" % [id, _kind(control)]
	var label := _text_of(control)
	if label.is_empty():
		for child: Node in control.find_children("*", "Label", true, false):
			label = (child as Label).text
			break
	if not label.is_empty():
		text += " %s" % JSON.stringify(label.left(60))
	text += " at (%d, %d)" % [roundi(at.x), roundi(at.y)]
	if control is BaseButton:
		var button := control as BaseButton
		if button.disabled:
			text += " disabled"
		if button.toggle_mode and not control is OptionButton:
			text += " on" if button.button_pressed else " off"
	if control is OptionButton:
		var combo := control as OptionButton
		var options: PackedStringArray = []
		for i: int in combo.item_count:
			options.append(combo.get_item_text(i))
		text += " options=%s selected=%s" % [JSON.stringify(options), JSON.stringify(combo.get_item_text(combo.selected) if combo.selected >= 0 else "")]
	if control is Range:
		var range_control := control as Range
		text += " value=%s (%s to %s)" % [range_control.value, range_control.min_value, range_control.max_value]
	return text


func _controls() -> Array[Control]:
	var result: Array[Control] = []
	var stack: Array[Node] = [_host.get_tree().root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node == _host or (node is CanvasItem and not (node as CanvasItem).visible) or (node is CanvasLayer and not (node as CanvasLayer).visible):
			continue
		var children := node.get_children()
		children.reverse()
		stack.append_array(children)
		if node is Control and _on_screen(node):
			result.append(node)
	return result


static func _on_screen(control: Control) -> bool:
	if not control.is_visible_in_tree():
		return false
	var alpha := control.self_modulate.a
	var node: Node = control
	while node:
		if node is CanvasItem:
			alpha *= (node as CanvasItem).modulate.a
		node = node.get_parent()
	if alpha <= 0.01:
		return false
	var transform := control.get_global_transform_with_canvas()
	return control.get_viewport().get_visible_rect().intersects(Rect2(transform.origin, control.size * transform.get_scale()), true)


## [id, control]: `<UI>.<nombre>`, con #2, #3 en los repetidos.
func _keyed(controls: Array[Control]) -> Array:
	var seen := {}
	var result: Array = []
	for control: Control in controls:
		var base := "%s.%s" % [_owner_name(control), control.name]
		seen[base] = seen.get(base, 0) + 1
		result.append([base if seen[base] == 1 else "%s#%d" % [base, seen[base]], control])
	return result


func _owner_name(node: Node) -> String:
	var parent := node.get_parent()
	while parent and parent != _host.get_tree().root:
		if parent is CanvasLayer or not parent.scene_file_path.is_empty() or parent == node.owner:
			return str(parent.name)
		parent = parent.get_parent()
	return "Screen"


static func _text_of(control: Control) -> String:
	if control is RichTextLabel:
		return (control as RichTextLabel).get_parsed_text()
	if control is Label or control is Button or control is LineEdit or control is TextEdit:
		return str(control.get("text"))
	return ""


static func _kind(control: Control) -> String:
	if control is OptionButton:
		return "combo"
	if control is CheckBox or control is CheckButton:
		return "checkbox"
	if control is BaseButton:
		return "checkbox" if (control as BaseButton).toggle_mode else "button"
	if control is Slider or control is SpinBox:
		return "slider"
	if control is LineEdit or control is TextEdit:
		return "text_input"
	return ""
