@tool
extends EditorPlugin
## Fuga a propósito (m16-12): un RefCounted por enable que nadie suelta (la variable estática vive con
## el script, que queda en caché al deshabilitar el plugin). El check de ciclos tiene que detectarla.

static var kept: Array[RefCounted] = []


func _enter_tree() -> void:
	kept.append(RefCounted.new())
