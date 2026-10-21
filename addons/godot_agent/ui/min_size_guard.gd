@tool
extends Container
## Envuelve cada superficie del addon (dock, panel inferior, main screen) para que su tamaño mínimo
## no pueda agrandar el editor. Un Label con autowrap dentro de un contenedor oculto nunca se
## acomoda: queda con el ancho de una letra y pide un alto de miles de píxeles. Los slots de docks
## del editor cuentan también las pestañas ocultas, así que ese mínimo estiraba toda la ventana
## (visto en 4.8 con el banner de export en un proyecto real). Con el tope, lo que no entra se recorta
## hasta que la superficie se muestra y se acomoda con su ancho real.

## Tope del mínimo, en píxeles sin escalar (se multiplica por la escala del editor).
const MAX_MIN_SIZE := Vector2(320, 240)

var _cap: Vector2


func _init(content: Control = null, scale: float = 1.0) -> void:
	_cap = MAX_MIN_SIZE * scale
	clip_contents = true
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	if content:
		name = content.name  # con la API vieja, el título de la pestaña es el nombre del nodo
		content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		content.size_flags_vertical = Control.SIZE_EXPAND_FILL
		add_child(content)


func _get_minimum_size() -> Vector2:
	var result := Vector2.ZERO
	for child: Node in get_children():
		var control := child as Control
		if control and control.visible and not control.top_level:
			result = result.max(control.get_combined_minimum_size())
	return result.min(_cap)


func _notification(what: int) -> void:
	if what == NOTIFICATION_SORT_CHILDREN:
		for child: Node in get_children():
			var control := child as Control
			if control and control.visible and not control.top_level:
				fit_child_in_rect(control, Rect2(Vector2.ZERO, size))
