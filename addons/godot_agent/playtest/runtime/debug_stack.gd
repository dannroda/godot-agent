extends RefCounted
## La pila del juego parado en el debugger, del lado del juego (m11-56): el probe la arma cuando el
## editor la pide. Con el juego en BREAKED el bucle del debugger sigue atendiendo las captures de
## mensajes, y el pedido corre encima de la función que paró: Engine.capture_script_backtraces la ve
## debajo de los frames del addon, que se sacan.

## Frames del addon (el probe y su pedido): no son del juego.
const SKIP_PREFIX := "res://addons/godot_agent/"
const MAX_FRAMES := 32
const MAX_VARIABLES := 40
const MAX_VALUE := 200
const MAX_ITEMS := 8


## `params`: {frame: int (0 = donde paró), variables: bool}. Devuelve {text} o {error}.
static func snapshot(params: Dictionary, skip_prefix: String = SKIP_PREFIX) -> Dictionary:
	var with_variables: bool = params.get("variables", true) != false
	var wanted := int(params.get("frame", 0))
	var trace: ScriptBacktrace = null
	for candidate: ScriptBacktrace in Engine.capture_script_backtraces(with_variables):
		if candidate.get_language_name() == "GDScript" and not candidate.is_empty():
			trace = candidate
			break
	if trace == null:
		return {"error": "No GDScript stack: the game did not stop inside a script."}
	var frames: Array[int] = []
	for i in trace.get_frame_count():
		if not trace.get_frame_file(i).begins_with(skip_prefix):
			frames.append(i)
	if frames.is_empty():
		return {"error": "No game frames on the stack."}
	var lines: PackedStringArray = ["Stack (%d frame%s, #0 is where it stopped):" % [frames.size(), "" if frames.size() == 1 else "s"]]
	for n in mini(frames.size(), MAX_FRAMES):
		var i := frames[n]
		lines.append("#%d %s:%d in %s()" % [n, trace.get_frame_file(i), trace.get_frame_line(i), trace.get_frame_function(i)])
	if frames.size() > MAX_FRAMES:
		lines.append("… %d more frames" % (frames.size() - MAX_FRAMES))
	if not with_variables:
		return {"text": "\n".join(lines)}
	if wanted < 0 or wanted >= frames.size():
		lines.append("There is no frame #%d (0–%d)." % [wanted, frames.size() - 1])
		return {"text": "\n".join(lines)}
	var level := frames[wanted]
	lines.append("")
	lines.append("Frame #%d, %s() at %s:%d:" % [wanted, trace.get_frame_function(level), trace.get_frame_file(level), trace.get_frame_line(level)])
	lines.append_array(_section(trace, level, false))
	lines.append_array(_section(trace, level, true))
	return {"text": "\n".join(lines)}


static func _section(trace: ScriptBacktrace, level: int, members: bool) -> PackedStringArray:
	var title := "Members" if members else "Locals"
	var count := trace.get_member_variable_count(level) if members else trace.get_local_variable_count(level)
	var lines: PackedStringArray = ["%s (%d):" % [title, count] if count > 0 else "%s: none" % title]
	for i in mini(count, MAX_VARIABLES):
		var name := trace.get_member_variable_name(level, i) if members else trace.get_local_variable_name(level, i)
		var value: Variant = trace.get_member_variable_value(level, i) if members else trace.get_local_variable_value(level, i)
		lines.append("  %s = %s" % [name, describe(value)])
	if count > MAX_VARIABLES:
		lines.append("  … %d more" % (count - MAX_VARIABLES))
	return lines


## Un valor en una línea, acotado: los nodos con su ruta, las colecciones con su tamaño y los
## primeros elementos.
static func describe(value: Variant) -> String:
	var text := ""
	if typeof(value) == TYPE_OBJECT:
		if not is_instance_valid(value):
			return str(value)  # <null> o <Freed Object>
		var object: Object = value
		if object is Node and (object as Node).is_inside_tree():
			text = "%s %s (%s)" % [object.get_class(), (object as Node).name, (object as Node).get_path()]
		elif object is Resource and not (object as Resource).resource_path.is_empty():
			text = "%s %s" % [object.get_class(), (object as Resource).resource_path]
		else:
			text = "%s#%d" % [object.get_class(), object.get_instance_id()]
	elif value is Array:
		var items: PackedStringArray = []
		for item: Variant in (value as Array).slice(0, MAX_ITEMS):
			items.append(describe(item))
		text = "Array(%d) [%s%s]" % [(value as Array).size(), ", ".join(items), ", …" if (value as Array).size() > MAX_ITEMS else ""]
	elif value is Dictionary:
		var pairs: PackedStringArray = []
		for key: Variant in (value as Dictionary).keys().slice(0, MAX_ITEMS):
			pairs.append("%s: %s" % [describe(key), describe(value[key])])
		text = "Dictionary(%d) {%s%s}" % [(value as Dictionary).size(), ", ".join(pairs), ", …" if (value as Dictionary).size() > MAX_ITEMS else ""]
	elif typeof(value) >= TYPE_PACKED_BYTE_ARRAY and typeof(value) <= TYPE_PACKED_VECTOR4_ARRAY:
		var head: PackedStringArray = []
		for item: Variant in value.slice(0, MAX_ITEMS):
			head.append(describe(item))
		text = "%s(%d) [%s%s]" % [type_string(typeof(value)), value.size(), ", ".join(head), ", …" if value.size() > MAX_ITEMS else ""]
	elif value is String or value is StringName:
		text = "\"%s\"" % str(value).c_escape()
	else:
		text = str(value)
	return text if text.length() <= MAX_VALUE else text.left(MAX_VALUE) + "…"
