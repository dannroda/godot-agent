@tool
extends RefCounted
## Liberar ventanas propias sin llevarse el ProgressDialog del editor (m16-08). Al mostrar un progreso
## (play, reimport, guardar) Godot lo cuelga de la última ventana exclusiva y no lo devuelve: si esa
## ventana es nuestra y se libera, se lo lleva puesto y el editor se cae en el progreso siguiente, o en
## ese mismo si se libera durante la iteración anidada del progreso.


## Libera la ventana al final del frame, devolviendo antes el ProgressDialog si quedó adentro.
static func free_later(window: Node) -> void:
	rescue_progress(window)
	window.queue_free()


## Devuelve a la raíz el ProgressDialog del editor si quedó dentro de `under`. Es donde lo pone Godot
## cuando no hay ventanas exclusivas abiertas.
static func rescue_progress(under: Node) -> void:
	if not under.is_inside_tree():
		return
	var root := under.get_tree().root
	for dialog: Node in under.find_children("*", "ProgressDialog", true, false):
		dialog.reparent(root, false)
