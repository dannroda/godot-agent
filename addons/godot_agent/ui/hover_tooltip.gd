@tool
extends RefCounted
## Tooltips que se actualizan solos (m12-51): el anillo de contexto con cada usage_update, el chip
## del agente y los de máquinas con la antigüedad de cada estado, cada segundo. Godot cierra el
## tooltip abierto si, al moverse el mouse un píxel, el texto ya no es el que mostró: se abría y se
## cerraba enseguida. Con el mouse encima, el texto nuevo espera a que salga; el tooltip abierto
## queda con lo que había al entrar, y al volver a pasar el mouse dice lo de ahora.

const PENDING_META := &"_godot_agent_pending_tooltip"
const HOOKED_META := &"_godot_agent_tooltip_hooked"


## Pone `text` como tooltip de `control`, o lo guarda para cuando el mouse salga si está encima.
static func set_text(control: Control, text: String) -> void:
	if control == null:
		return
	if not is_hovered(control):
		control.tooltip_text = text
		if control.has_meta(PENDING_META):
			control.remove_meta(PENDING_META)
		return
	if text == control.tooltip_text:
		if control.has_meta(PENDING_META):
			control.remove_meta(PENDING_META)
		return
	if not control.has_meta(HOOKED_META):
		control.set_meta(HOOKED_META, true)
		control.mouse_exited.connect(_apply_pending.bind(control))
	control.set_meta(PENDING_META, text)


## El texto que tendrá el tooltip (el guardado, si lo hay): para leerlo en las pruebas y armar otros.
static func text_of(control: Control) -> String:
	return str(control.get_meta(PENDING_META)) if control.has_meta(PENDING_META) else control.tooltip_text


static func is_hovered(control: Control) -> bool:
	if not control.is_inside_tree() or not control.is_visible_in_tree():
		return false
	return control.get_viewport().gui_get_hovered_control() == control


static func _apply_pending(control: Control) -> void:
	if not is_instance_valid(control) or not control.has_meta(PENDING_META):
		return
	control.tooltip_text = str(control.get_meta(PENDING_META))
	control.remove_meta(PENDING_META)
