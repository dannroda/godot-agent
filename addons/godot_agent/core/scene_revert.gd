@tool
extends RefCounted
## Rechazar por nodo los cambios de un turno en una escena .tscn (m11-34 y m11-59): una propiedad
## vuelve a su valor de antes, un nodo agregado se va con sus descendientes y sus conexiones, uno
## borrado vuelve a su lugar entre sus hermanos, uno movido o renombrado vuelve a donde estaba, y lo
## mismo con el encabezado de un nodo (nombre de la raíz, type o instance, groups) y las conexiones.
##
## Trabaja sobre el texto actual del archivo y antes de tocarlo verifica que lo que va a deshacer siga
## como lo dejó el turno; si cambió después, no escribe nada (queda stale). «Deshacer» es la
## operación inversa, con la misma verificación. Cada cambio lleva los dos textos del turno, así que
## las dos direcciones son la misma operación: llevar algo del texto de un lado al actual.
##
## Lo que vuelve trae los recursos que nombra (ext_resource y sub_resource): un ext_resource que ya
## está (mismo uid o misma ruta) se reusa; lo demás se copia, con su id de antes si está libre o con
## uno nuevo que no choca. Los recursos que una operación deja sin usar se borran. Antes de escribir,
## validate() carga el texto nuevo como escena (lo usa TurnChanges).

const SceneDiff := preload("scene_diff.gd")

const PROP := "prop"
const ADDED := "added"
const REMOVED := "removed"
const MOVED := "moved"
const HEADER := "header"
const CONNECTION := "connection"
const OTHER := "other"
## Propiedades del diff que están en el encabezado del nodo, no en una línea `nombre = valor`.
const HEADER_PROPS: PackedStringArray = ["type", "name", "groups"]
## Dónde validate() escribe la copia que carga.
const CHECK_PATH := "user://godot_agent_scene_check.tscn"
const ID_CHARS := "abcdefghijklmnopqrstuvwxyz0123456789"

## Para los ids nuevos (las pruebas le fijan la semilla).
static var rng := RandomNumberGenerator.new()
static var _ref_re: RegEx
static var _attr_re: RegEx
static var _whole_sub_re: RegEx


## Los cambios de una escena entre dos textos, en el orden del diff por nodos: [{kind, label (para
## mostrar), rejectable, path, uid, before_text, after_text, ...}]. PROP y HEADER llevan name,
## before y after (los valores comparables de SceneDiff) y shown_before/shown_after; ADDED y REMOVED
## llevan type y children; MOVED, from y to; CONNECTION, line y added.
static func changes(before_text: String, after_text: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var diff := SceneDiff.diff(before_text, after_text)
	if not str(diff.error).is_empty():
		return result
	var before := SceneDiff._nodes(SceneDiff.parse(before_text))
	var after := SceneDiff._nodes(SceneDiff.parse(after_text))
	var pairs := SceneDiff._match(before, after)
	var after_scene := SceneDiff.parse(after_text)
	var texts := {"before_text": before_text, "after_text": after_text}
	for node: Dictionary in diff.added:
		var now: Dictionary = after.list[after.by_path[node.path]]
		result.append(_with(texts, {"kind": ADDED, "path": node.path, "uid": now.uid, "type": node.type, "children": node.children,
			"rejectable": node.path != ".", "label": "+ %s" % node.path}))
	for node: Dictionary in diff.removed:
		var was: Dictionary = before.list[before.by_path[node.path]]
		result.append(_with(texts, {"kind": REMOVED, "path": node.path, "uid": was.uid, "type": node.type, "children": node.children,
			"rejectable": node.path != ".", "label": "− %s" % node.path}))
	for node: Dictionary in diff.moved:
		var now: Dictionary = after.list[after.by_path[node.to]]
		result.append(_with(texts, {"kind": MOVED, "path": node.to, "from": node.from, "to": node.to, "uid": now.uid, "type": node.type,
			"rejectable": true, "label": "→ %s ← %s" % [node.to, node.from]}))
	for node: Dictionary in diff.changed:
		var i: int = after.by_path[node.path]
		var now: Dictionary = after.list[i]
		var was: Dictionary = before.list[pairs.before_of[i]]
		for prop: Dictionary in node.props:
			var name := str(prop.name)
			var change := _with(texts, {"kind": HEADER if name in HEADER_PROPS else PROP, "path": node.path, "from": was.path, "uid": now.uid,
				"name": name, "before": prop.before, "after": prop.after, "rejectable": true,
				"label": "~ %s · %s" % [node.path, name], "shown_before": prop.before, "shown_after": prop.after})
			if name.contains(".") and _sub_section(after_text, after_scene, now.raw, name).is_empty():
				change.rejectable = false  # dentro de un sub_resource compartido: solo con «Volver atrás»
			result.append(change)
	for connection: String in diff.connections_added:
		result.append(_with(texts, {"kind": CONNECTION, "line": connection, "added": true, "rejectable": true, "label": "+ " + connection}))
	for connection: String in diff.connections_removed:
		result.append(_with(texts, {"kind": CONNECTION, "line": connection, "added": false, "rejectable": true, "label": "− " + connection}))
	return result


static func _with(texts: Dictionary, change: Dictionary) -> Dictionary:
	change.merge(texts)
	return change


## Deshace `change` en `text` (o, con `undo`, lo vuelve a hacer). {ok, text, error, expect}: si lo
## que había que deshacer ya no está como lo dejó el turno, ok es false y text queda igual. expect es
## {present: [rutas], absent: [rutas]}: lo que validate() tiene que encontrar en el árbol.
static func apply(text: String, change: Dictionary, undo: bool = false) -> Dictionary:
	if not change.get("rejectable", false):
		return _fail(text, "not rejectable")
	# `target`: el texto del turno donde está lo que se quiere; `current`: el que dejó el turno.
	var target: String = change.after_text if undo else change.before_text
	match str(change.kind):
		PROP:
			return _prop(text, change, change.before if undo else change.after, target, change.path if undo else change.from)
		HEADER:
			return _header(text, change, change.before if undo else change.after, target, change.path if undo else change.from)
		ADDED:
			return _restore(text, change, target, change.path) if undo else _remove(text, change, change.path)
		REMOVED:
			return _remove(text, change, change.path) if undo else _restore(text, change, target, change.path)
		MOVED:
			return _move(text, change, change.from if undo else change.to, target, change.to if undo else change.from)
		CONNECTION:
			var drop: bool = change.added != undo
			return _drop_connection(text, change) if drop else _add_connection(text, change, target)
	return _fail(text, "not rejectable")


static func _fail(text: String, error: String) -> Dictionary:
	return {"ok": false, "text": text, "error": error, "expect": {}}


static func _done(text: String, present: Array = [], absent: Array = []) -> Dictionary:
	return {"ok": true, "text": text, "error": "", "expect": {"present": present, "absent": absent}}


## Carga `text` como escena (una copia en user://, sin la caché) y la instancia: "" si carga y el
## árbol tiene lo que espera `expect` ({present, absent}: rutas desde la raíz), o el motivo.
static func validate(text: String, expect: Dictionary = {}) -> String:
	var file := FileAccess.open(CHECK_PATH, FileAccess.WRITE)
	if file == null:
		return "could not write a copy to check it"
	# Sin el uid de la escena: la copia no es el archivo de verdad.
	var lines := text.split("\n")
	if not lines.is_empty() and lines[0].begins_with("[gd_scene"):
		lines[0] = _set_attr(lines[0], "uid", null)
	file.store_string("\n".join(lines))
	file.close()
	var packed := ResourceLoader.load(CHECK_PATH, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	DirAccess.remove_absolute(ProjectSettings.globalize_path(CHECK_PATH))
	if packed == null:
		return "the scene does not load"
	var root := packed.instantiate()
	if root == null:
		return "the scene does not instantiate"
	var error := ""
	for path: String in expect.get("present", []):
		if root.get_node_or_null(NodePath(path)) == null:
			error = "%s is not in the scene tree" % path
			break
	if error.is_empty():
		for path: String in expect.get("absent", []):
			if root.get_node_or_null(NodePath(path)) != null:
				error = "%s is still in the scene tree" % path
				break
	root.free()
	return error


# --- secciones con sus líneas --------------------------------------------------------------------

## Las secciones de un .tscn con dónde están: [{kind, attrs, path (los nodos), start, end (líneas,
## end exclusivo, sin las líneas vacías del final), props: {nombre: {start, end, value}}}].
static func sections(text: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var lines := text.split("\n")
	var current: Dictionary = {}
	var key := ""
	var key_start := 0
	var value := ""
	var state := [0, false]
	for i in lines.size():
		var line: String = lines[i]
		if not key.is_empty():
			value += "\n" + line
			state = SceneDiff._scan(line, state)
			if state[0] <= 0 and not state[1]:
				current.props[key] = {"start": key_start, "end": i + 1, "value": value}
				current.end = i + 1
				key = ""
			continue
		if line.begins_with("["):
			var kind := line.substr(1).get_slice(" ", 0).trim_suffix("]")
			if kind in SceneDiff.SECTIONS:
				var attrs := SceneDiff._attrs(line)
				current = {"kind": kind, "attrs": attrs, "start": i, "end": i + 1, "props": {}, "path": ""}
				if kind == "node":
					current.path = "." if not attrs.has("parent") else _join(str(attrs.parent), str(attrs.name))
				result.append(current)
				continue
		var equals := line.find(" = ")
		if equals <= 0 or current.is_empty() or line.begins_with(" ") or line.begins_with("\t"):
			continue
		key = line.substr(0, equals)
		key_start = i
		value = line.substr(equals + 3)
		state = SceneDiff._scan(value, [0, false])
		if state[0] <= 0 and not state[1]:
			current.props[key] = {"start": i, "end": i + 1, "value": value}
			current.end = i + 1
			key = ""
	return result


## La ruta de un hijo: `parent` es como el atributo parent= ("." para los hijos de la raíz).
static func _join(parent: String, name: String) -> String:
	return name if parent == "." else "%s/%s" % [parent, name]


## El atributo parent= de un nodo con esa ruta.
static func _parent_of(path: String) -> String:
	return path.get_base_dir() if path.contains("/") else "."


static func _under(path: String, top: String) -> bool:
	return path == top or path.begins_with(top + "/")


## Una ruta con `old` (o algo debajo) cambiada a `new`.
static func _rebase(path: String, old: String, new: String) -> String:
	if path == old:
		return new
	if path.begins_with(old + "/"):
		return new + path.substr(old.length())
	return path


## La sección de un nodo: por unique_id si lo tiene, si no por ruta.
static func _find_node(all: Array[Dictionary], uid: String, path: String) -> Dictionary:
	for section: Dictionary in all:
		if section.kind != "node":
			continue
		if uid.is_empty() and section.path == path:
			return section
		if not uid.is_empty() and str(section.attrs.get("unique_id", "")) == uid:
			return section
	return {}


static func _node_at(all: Array[Dictionary], path: String) -> Dictionary:
	for section: Dictionary in all:
		if section.kind == "node" and section.path == path:
			return section
	return {}


## El valor comparable (de SceneDiff) de una propiedad o del encabezado de un nodo en un texto.
static func _value_now(text: String, uid: String, path: String, name: String) -> Dictionary:
	var nodes := SceneDiff._nodes(SceneDiff.parse(text))
	var i: int = nodes.by_uid.get(uid, -1) if not uid.is_empty() else nodes.by_path.get(path, -1)
	if i < 0:
		return {}
	var node: Dictionary = nodes.list[i]
	var value: Variant
	match name:
		"name":
			value = node.name
		"type":
			value = node.type
		_:
			value = node.props.get(name)
	return {"node": node, "value": value}


# --- atributos del encabezado --------------------------------------------------------------------

## Las posiciones de los atributos de un encabezado: {nombre: Vector2i(inicio, fin)}.
static func _attr_spans(header: String) -> Dictionary:
	if _attr_re == null:
		_attr_re = RegEx.create_from_string("(\\w+)=(\"(?:[^\"\\\\]|\\\\.)*\"|\\[[^\\]]*\\]|\\w+\\(\"[^\"]*\"\\)|[^\\s\\]]+)")
	var spans := {}
	for found: RegExMatch in _attr_re.search_all(header):
		spans[found.get_string(1)] = Vector2i(found.get_start(0), found.get_end(0))
	return spans


## El texto crudo de un atributo (con sus comillas), o null.
static func _raw_attr(header: String, key: String) -> Variant:
	var spans := _attr_spans(header)
	if not spans.has(key):
		return null
	var span: Vector2i = spans[key]
	return header.substr(span.x + key.length() + 1, span.y - span.x - key.length() - 1)


## El encabezado con un atributo cambiado (`raw` con sus comillas) o sacado (null).
static func _set_attr(header: String, key: String, raw: Variant) -> String:
	var spans := _attr_spans(header)
	if spans.has(key):
		var span: Vector2i = spans[key]
		if raw == null:
			return header.substr(0, span.x).rstrip(" ") + header.substr(span.y)
		return header.substr(0, span.x) + "%s=%s" % [key, raw] + header.substr(span.y)
	if raw == null:
		return header
	if key == "type" and spans.has("name"):  # donde lo pone Godot: después del nombre
		var after_name: int = spans.name.y
		return header.substr(0, after_name) + " type=%s" % raw + header.substr(after_name)
	var close := header.rfind("]")
	return header.substr(0, close) + " %s=%s" % [key, raw] + header.substr(close)


static func _quote(text: String) -> String:
	return "\"%s\"" % text.c_escape()


# --- recursos ------------------------------------------------------------------------------------

## Los recursos que nombra un texto: {"ExtResource:id" o "SubResource:id": veces}.
static func _refs(text: String) -> Dictionary:
	if _ref_re == null:
		_ref_re = RegEx.create_from_string("(ExtResource|SubResource)\\(\"([^\"]+)\"\\)")
	var refs := {}
	if not text.contains("Resource(\""):
		return refs
	for found: RegExMatch in _ref_re.search_all(text):
		var key := "%s:%s" % [found.get_string(1), found.get_string(2)]
		refs[key] = int(refs.get(key, 0)) + 1
	return refs


## Un texto con los ids de sus ExtResource("…") y SubResource("…") cambiados según los mapas.
static func _remap(text: String, ext_map: Dictionary, sub_map: Dictionary) -> String:
	if not text.contains("Resource(\""):
		return text
	_refs("")
	var out := ""
	var last := 0
	for found: RegExMatch in _ref_re.search_all(text):
		var map: Dictionary = ext_map if found.get_string(1) == "ExtResource" else sub_map
		out += text.substr(last, found.get_start(0) - last)
		out += "%s(\"%s\")" % [found.get_string(1), map.get(found.get_string(2), found.get_string(2))]
		last = found.get_end(0)
	return out + text.substr(last)


static func _new_ext_id(used: Dictionary) -> String:
	var top := 0
	for id: String in used:
		var prefix := id.get_slice("_", 0)
		if prefix.is_valid_int():
			top = maxi(top, prefix.to_int())
	while true:
		var id := "%d_%s" % [top + 1, _random_suffix()]
		if not used.has(id):
			return id
	return ""


static func _new_sub_id(type: String, used: Dictionary) -> String:
	while true:
		var id := "%s_%s" % [type if not type.is_empty() else "Resource", _random_suffix()]
		if not used.has(id):
			return id
	return ""


static func _random_suffix() -> String:
	var out := ""
	for i in 5:
		out += ID_CHARS[rng.randi_range(0, ID_CHARS.length() - 1)]
	return out


## Lleva a `text` los recursos que nombra `value` (un pedazo de `source`): {text, value}, con el
## texto con los ext_resource y sub_resource que faltaban y el valor con los ids que quedaron.
static func _import(text: String, value: String, source: String) -> Dictionary:
	if _refs(value).is_empty():
		return {"text": text, "value": value}
	var source_all := sections(source)
	var source_lines := source.split("\n")
	var source_scene := SceneDiff.parse(source)
	var source_ext := {}
	var source_sub := {}
	for section: Dictionary in source_all:
		if section.kind == "ext_resource":
			source_ext[str(section.attrs.get("id", ""))] = section
		elif section.kind == "sub_resource":
			source_sub[str(section.attrs.get("id", ""))] = section
	var all := sections(text)
	var scene := SceneDiff.parse(text)
	var used_ext := {}
	var used_sub := {}
	for section: Dictionary in all:
		if section.kind == "ext_resource":
			used_ext[str(section.attrs.get("id", ""))] = section
		elif section.kind == "sub_resource":
			used_sub[str(section.attrs.get("id", ""))] = section
	var state := {"ext_map": {}, "sub_map": {}, "ext_blocks": [], "sub_blocks": []}
	var context := {"source_ext": source_ext, "source_sub": source_sub, "source_lines": source_lines, "source_scene": source_scene,
		"used_ext": used_ext, "used_sub": used_sub, "scene": scene}
	_visit(value, context, state)
	var ext_blocks: Array = state.ext_blocks
	var sub_blocks: Array = state.sub_blocks
	if ext_blocks.is_empty() and sub_blocks.is_empty():
		return {"text": text, "value": _remap(value, state.ext_map, state.sub_map)}
	# Dónde: los ext después del último ext_resource (o del encabezado); los sub después del último
	# sub_resource (o antes del primer nodo).
	var lines := text.split("\n")
	var ext_at := _after_last(all, ["ext_resource"], ["gd_scene"])
	var sub_at := _after_last(all, ["sub_resource"], ["ext_resource", "gd_scene"])
	var inserts: Array = [[sub_at, sub_blocks], [ext_at, ext_blocks]]  # de abajo hacia arriba
	if sub_at < ext_at:
		inserts.reverse()
	for insert: Array in inserts:
		var block: PackedStringArray = []
		for section_lines: PackedStringArray in insert[1]:
			block.append_array(section_lines)
			block.append("")
		if block.is_empty():
			continue
		lines = _insert_lines(lines, int(insert[0]), block)
	var result := "\n".join(lines)
	result = _bump_load_steps(result, ext_blocks.size() + sub_blocks.size())
	return {"text": result, "value": _remap(value, state.ext_map, state.sub_map)}


## La línea donde empieza la sección que sigue a la última de `kinds` (o, si no hay ninguna, a la
## última de `fallback`), o -1 si no sigue ninguna.
static func _after_last(all: Array[Dictionary], kinds: Array, fallback: Array) -> int:
	for wanted: Array in [kinds, fallback]:
		var last := -1
		for i in all.size():
			if all[i].kind in wanted:
				last = i
		if last >= 0:
			return all[last + 1].start if last + 1 < all.size() else -1
	return all[0].start if not all.is_empty() else -1


## `block` (que termina en una línea vacía) antes de la línea `at`, o al final si es -1.
static func _insert_lines(lines: PackedStringArray, at: int, block: PackedStringArray) -> PackedStringArray:
	var out: PackedStringArray = []
	if at >= 0:
		out.append_array(lines.slice(0, at))
		out.append_array(block)
		out.append_array(lines.slice(at))
		return out
	var end := lines.size()
	while end > 0 and lines[end - 1].is_empty():
		end -= 1
	out.append_array(lines.slice(0, end))
	out.append("")
	out.append_array(block)  # termina en "": el salto de línea del final del archivo
	return out


static func _visit(value: String, context: Dictionary, state: Dictionary) -> void:
	for key: String in _refs(value):
		var kind := key.get_slice(":", 0)
		var id := key.substr(kind.length() + 1)
		if kind == "ExtResource":
			if not state.ext_map.has(id):
				_map_ext(id, context, state)
		elif not state.sub_map.has(id):
			_map_sub(id, context, state)


static func _map_ext(id: String, context: Dictionary, state: Dictionary) -> void:
	var section: Dictionary = context.source_ext.get(id, {})
	if section.is_empty():
		state.ext_map[id] = id
		return
	var uid := str(section.attrs.get("uid", ""))
	var path := str(section.attrs.get("path", ""))
	for existing: String in context.used_ext:
		var other: Dictionary = context.used_ext[existing]
		if other.is_empty():
			continue  # uno que agrega esta operación
		if (not uid.is_empty() and str(other.attrs.get("uid", "")) == uid) or str(other.attrs.get("path", "")) == path:
			state.ext_map[id] = existing
			return
	var new_id := id if not context.used_ext.has(id) else _new_ext_id(context.used_ext)
	context.used_ext[new_id] = {}
	state.ext_map[id] = new_id
	var lines: PackedStringArray = context.source_lines.slice(section.start, section.end)
	lines[0] = _set_attr(lines[0], "id", _quote(new_id))
	state.ext_blocks.append(lines)


static func _map_sub(id: String, context: Dictionary, state: Dictionary) -> void:
	var section: Dictionary = context.source_sub.get(id, {})
	if section.is_empty():
		state.sub_map[id] = id
		return
	var source_sub: Dictionary = context.source_scene.sub.get(id, {})
	var here: Dictionary = context.scene.sub.get(id, {})
	if not here.is_empty() and not source_sub.is_empty() \
			and SceneDiff._content(here, context.scene) == SceneDiff._content(source_sub, context.source_scene):
		state.sub_map[id] = id  # el mismo, ya está
		return
	var new_id := id if not context.used_sub.has(id) else _new_sub_id(str(section.attrs.get("type", "")), context.used_sub)
	context.used_sub[new_id] = {}
	state.sub_map[id] = new_id
	var lines: PackedStringArray = context.source_lines.slice(section.start, section.end)
	var body := "\n".join(lines.slice(1))
	_visit(body, context, state)  # lo que nombra va antes, como lo escribe Godot
	var header := _set_attr(lines[0], "id", _quote(new_id))
	var out: PackedStringArray = [header]
	if lines.size() > 1:
		out.append_array(_remap(body, state.ext_map, state.sub_map).split("\n"))
	state.sub_blocks.append(out)


## Suma `delta` a load_steps del encabezado, si lo tiene.
static func _bump_load_steps(text: String, delta: int) -> String:
	if delta == 0 or not text.begins_with("[gd_scene"):
		return text
	var newline := text.find("\n")
	var header := text.substr(0, newline) if newline >= 0 else text
	var steps: Variant = _raw_attr(header, "load_steps")
	if steps == null or not str(steps).is_valid_int():
		return text
	header = _set_attr(header, "load_steps", str(maxi(1, str(steps).to_int() + delta)))
	return header + (text.substr(newline) if newline >= 0 else "")


## Borra los recursos que nadie nombra en `text` y que sí se nombraban en el texto de antes de la
## operación (`refs_before`, de _refs()): los que dejó sin usar esta operación, y en cascada.
static func _collect(text: String, refs_before: Dictionary) -> String:
	while true:
		var refs := _refs(text)
		var all := sections(text)
		var drop := {}
		for section: Dictionary in all:
			if section.kind != "ext_resource" and section.kind != "sub_resource":
				continue
			var key := "%s:%s" % ["ExtResource" if section.kind == "ext_resource" else "SubResource", section.attrs.get("id", "")]
			if not refs.has(key) and refs_before.has(key):
				drop[section.start] = section.end
		if drop.is_empty():
			return text
		text = _bump_load_steps(_drop_spans(text, drop), -drop.size())
	return text


## El texto sin las secciones que empiezan en las líneas de `spans` ({inicio: fin}), cada una con
## la línea vacía que la separa de la siguiente.
static func _drop_spans(text: String, spans: Dictionary) -> String:
	var lines := text.split("\n")
	var keep: PackedStringArray = []
	var i := 0
	while i < lines.size():
		if spans.has(i):
			i = spans[i]
			if i < lines.size() and lines[i].is_empty():
				i += 1
			continue
		keep.append(lines[i])
		i += 1
	return "\n".join(keep)


# --- propiedades ---------------------------------------------------------------------------------

## Una propiedad (o una de un sub_resource, «shape.size») vuelve a como está en `target`.
static func _prop(text: String, change: Dictionary, expected: Variant, target: String, target_path: String) -> Dictionary:
	var name := str(change.name)
	var now := _value_now(text, str(change.uid), str(change.path), name)
	if now.is_empty():
		return _fail(text, "the node is not there")
	if now.value != expected:
		return _fail(text, "changed after the turn")
	var path: String = now.node.path
	var source := _value_now(target, str(change.uid), target_path, name)
	if source.is_empty():
		return _fail(text, "the node is not in the other scene")
	var refs_before := _refs(text)
	var key := name
	var owner_id := ""  # "" = la sección del nodo; si no, el id de un sub_resource
	var wanted: Variant = source.node.raw.get(name)
	if name.contains("."):
		var here := _sub_section(text, SceneDiff.parse(text), now.node.raw, name)
		if here.is_empty():
			return _fail(text, "the resource is shared")
		var there := _sub_section(target, SceneDiff.parse(target), source.node.raw, name, false)
		if there.is_empty():
			return _fail(text, "the resource is not in the other scene")
		key = name.get_slice(".", name.get_slice_count(".") - 1)
		owner_id = here.id
		wanted = there.section.props.get(key)
	if wanted != null:
		var imported := _import(text, str(wanted), target)
		text = imported.text
		wanted = imported.value
	var all := sections(text)
	var section := {}
	if owner_id.is_empty():
		section = _find_node(all, str(change.uid), path)
	else:
		for candidate: Dictionary in all:
			if candidate.kind == "sub_resource" and str(candidate.attrs.get("id", "")) == owner_id:
				section = candidate
	text = _write_prop(text, section, key, wanted)
	return _done(_collect(text, refs_before), [path])


## El sub_resource que tiene la última parte de `name` («shape.size»: el de shape), siguiendo las
## propiedades desde `raw` (las del nodo): {id, section} (con las secciones de parse()), o {} si en el
## camino hay algo que no es un sub_resource o (con `alone`) uno que se nombra más de una vez.
static func _sub_section(text: String, scene: Dictionary, raw: Dictionary, name: String, alone: bool = true) -> Dictionary:
	if _whole_sub_re == null:
		_whole_sub_re = RegEx.create_from_string("^SubResource\\(\"([^\"]+)\"\\)$")
	var parts := name.split(".")
	var props := raw
	var found := {}
	var refs := _refs(text) if alone else {}
	for k in parts.size() - 1:
		var whole := _whole_sub_re.search(str(props.get(parts[k], "")))
		if whole == null or not scene.sub.has(whole.get_string(1)):
			return {}
		var id := whole.get_string(1)
		if alone and int(refs.get("SubResource:" + id, 0)) != 1:
			return {}
		found = {"id": id, "section": scene.sub[id]}
		props = found.section.props
	return found


## Escribe `name = value` en una sección (o saca la línea si value es null).
static func _write_prop(text: String, section: Dictionary, name: String, value: Variant) -> String:
	var lines := text.split("\n")
	var out: PackedStringArray = []
	if section.props.has(name):
		var prop: Dictionary = section.props[name]
		out.append_array(lines.slice(0, prop.start))
		if value != null:
			out.append_array(("%s = %s" % [name, value]).split("\n"))
		out.append_array(lines.slice(prop.end))
	elif value != null:
		out.append_array(lines.slice(0, section.end))
		out.append_array(("%s = %s" % [name, value]).split("\n"))
		out.append_array(lines.slice(section.end))
	else:
		return text
	return "\n".join(out)


# --- encabezado ----------------------------------------------------------------------------------

## El nombre de la raíz, el tipo (o la escena instanciada) o los grupos vuelven a como están en `target`.
static func _header(text: String, change: Dictionary, expected: Variant, target: String, target_path: String) -> Dictionary:
	var name := str(change.name)
	var now := _value_now(text, str(change.uid), str(change.path), name)
	if now.is_empty():
		return _fail(text, "the node is not there")
	if now.value != expected:
		return _fail(text, "changed after the turn")
	var path: String = now.node.path
	var source := _find_node(sections(target), str(change.uid), target_path)
	if source.is_empty():
		return _fail(text, "the node is not in the other scene")
	var source_header: String = target.split("\n")[source.start]
	var refs_before := _refs(text)
	var keys: Array = ["type", "instance"] if name == "type" else [name]
	var values := {}
	for key: String in keys:
		var raw: Variant = _raw_attr(source_header, key)
		if raw != null and key == "instance":
			var imported := _import(text, str(raw), target)
			text = imported.text
			raw = imported.value
		values[key] = raw
	var lines := text.split("\n")
	var section := _find_node(sections(text), str(change.uid), path)
	var header: String = lines[section.start]
	for key: String in keys:
		header = _set_attr(header, key, values[key])
	lines[section.start] = header
	return _done(_collect("\n".join(lines), refs_before), ["."] if name == "name" else [path])


# --- nodos ---------------------------------------------------------------------------------------

## Las secciones de un nodo y sus descendientes, y las conexiones y [editable] que los nombran.
static func _subtree(all: Array[Dictionary], path: String) -> Dictionary:
	var nodes: Array[Dictionary] = []
	var related: Array[Dictionary] = []
	for section: Dictionary in all:
		if section.kind == "node" and _under(section.path, path):
			nodes.append(section)
		elif _names(section, path):
			related.append(section)
	return {"nodes": nodes, "related": related}


## Si una conexión o un [editable] nombra un nodo o algo debajo.
static func _names(section: Dictionary, path: String) -> bool:
	var keys: Array = ["from", "to"] if section.kind == "connection" else (["path"] if section.kind == "editable" else [])
	for key: String in keys:
		if _under(str(section.attrs.get(key, "")), path):
			return true
	return false


## Un nodo (con sus descendientes, conexiones y [editable]) se va.
static func _remove(text: String, change: Dictionary, path: String) -> Dictionary:
	var all := sections(text)
	var node := _find_node(all, str(change.uid), path)
	if node.is_empty():
		return _fail(text, "the node is not there")
	var subtree := _subtree(all, node.path)
	var spans := {}
	for section: Dictionary in subtree.nodes + subtree.related:
		spans[section.start] = section.end
	var result := _collect(_drop_spans(text, spans), _refs(text))
	# Una sección sin type ni instance solo cambia un nodo de una escena instanciada: ese sigue.
	var overrides: bool = not node.attrs.has("type") and not node.attrs.has("instance")
	return _done(result, [], [] if overrides else [node.path])


## Un nodo vuelve desde `source` (donde está en `source_path`), con sus descendientes, sus
## conexiones y sus recursos, en el mismo lugar entre sus hermanos.
static func _restore(text: String, change: Dictionary, source: String, source_path: String) -> Dictionary:
	var source_all := sections(source)
	var node := _find_node(source_all, str(change.uid), source_path)
	if node.is_empty():
		return _fail(text, "the node is not in the other scene")
	var all := sections(text)
	if not str(change.uid).is_empty() and not _find_node(all, str(change.uid), "").is_empty():
		return _fail(text, "the node is already there")
	var source_parent := _node_at(source_all, _parent_of(node.path))
	var parent := _find_node(all, str(source_parent.get("attrs", {}).get("unique_id", "")), source_parent.get("path", ""))
	if source_parent.is_empty() or parent.is_empty():
		return _fail(text, "its parent is not there")
	var path := _join(parent.path, str(node.attrs.name))
	if not _node_at(all, path).is_empty():
		return _fail(text, "there is another node with that name there")
	var subtree := _subtree(source_all, node.path)
	var source_lines := source.split("\n")
	var block: PackedStringArray = []
	for section: Dictionary in subtree.nodes:
		var lines: PackedStringArray = source_lines.slice(section.start, section.end)
		lines[0] = _rebase_header(lines[0], section, node.path, path)
		block.append_array(lines)
		block.append("")
	# Sus conexiones, con las rutas al día, si el otro extremo está y no están ya.
	var paths := {}
	var lines_now := {}
	for section: Dictionary in all:
		if section.kind == "node":
			paths[section.path] = true
		elif section.kind == "connection":
			lines_now[SceneDiff.connection_line(section.attrs)] = true
	var related: Array[PackedStringArray] = []
	for section: Dictionary in subtree.related:
		var lines: PackedStringArray = source_lines.slice(section.start, section.end)
		lines[0] = _rebase_header(lines[0], section, node.path, path)
		var attrs := SceneDiff._attrs(lines[0])
		if section.kind == "connection":
			if lines_now.has(SceneDiff.connection_line(attrs)):
				continue
			var ends := true
			for key: String in ["from", "to"]:
				var end := str(attrs.get(key, ""))
				ends = ends and (_under(end, path) or end == "." or paths.has(end))
			if not ends:
				continue
		related.append(lines)
	var refs_before := _refs(text)
	var imported := _import(text, "\n".join(block), source)
	text = imported.text
	var block_now: PackedStringArray = str(imported.value).split("\n")
	all = sections(text)
	parent = _find_node(all, str(parent.attrs.get("unique_id", "")), parent.path)
	var at := _place(all, source_all, node, parent.path, "")
	text = "\n".join(_insert_lines(text.split("\n"), at, block_now))
	for lines: PackedStringArray in related:
		var more := _import(text, "\n".join(lines), source)
		text = _append_related(more.text, str(more.value).split("\n"), lines[0].begins_with("[editable"))
	return _done(_collect(text, refs_before), [path])


## Un encabezado de nodo, conexión o [editable] con las rutas que empiezan en `old` cambiadas a `new`
## (el nodo de `old` toma el nombre y el padre de `new`).
static func _rebase_header(header: String, section: Dictionary, old: String, new: String) -> String:
	match str(section.kind):
		"node":
			if section.path == old:
				header = _set_attr(header, "name", _quote(new.get_file()))
				return _set_attr(header, "parent", _quote(_parent_of(new)))
			var parent := str(section.attrs.get("parent", ""))
			return _set_attr(header, "parent", _quote(_rebase(parent, old, new)))
		"connection":
			for key: String in ["from", "to"]:
				var value := str(section.attrs.get(key, ""))
				if _under(value, old):
					header = _set_attr(header, key, _quote(_rebase(value, old, new)))
			return header
		"editable":
			return _set_attr(header, "path", _quote(_rebase(str(section.attrs.get("path", "")), old, new)))
	return header


## La línea antes de la que va un nodo que en `source_all` es `node`, debajo de `parent` (su ruta en
## `all`): después del subárbol del hermano anterior más cercano que siga ahí, o, si no hay, justo
## después del padre. -1 = al final. `skip`: la ruta de un nodo que no cuenta como hermano.
static func _place(all: Array[Dictionary], source_all: Array[Dictionary], node: Dictionary, parent: String, skip: String) -> int:
	var siblings: Array[Dictionary] = []
	for section: Dictionary in source_all:
		if section == node:
			break
		if section.kind == "node" and section.attrs.has("parent") and section.attrs.parent == node.attrs.get("parent"):
			siblings.append(section)
	siblings.reverse()
	for sibling: Dictionary in siblings:
		var uid := str(sibling.attrs.get("unique_id", ""))
		var here := _find_node(all, uid, _join(parent, str(sibling.attrs.name)))
		if here.is_empty() or here.path == skip or _parent_of(here.path) != parent:
			continue
		var i := all.find(here) + 1
		while i < all.size() and all[i].kind == "node" and _under(all[i].path, here.path):
			i += 1
		return all[i].start if i < all.size() else -1
	for i in all.size():
		if all[i].kind == "node" and all[i].path == parent:
			return all[i + 1].start if i + 1 < all.size() else -1
	return -1


## Una conexión va después de la última (o antes del primer [editable]); un [editable], al final.
static func _append_related(text: String, lines: PackedStringArray, editable: bool) -> String:
	var all := sections(text)
	var at := -1
	if not editable:
		var last := -1
		for i in all.size():
			if all[i].kind == "connection":
				last = i
		if last >= 0:
			at = all[last + 1].start if last + 1 < all.size() else -1
		else:
			for section: Dictionary in all:
				if section.kind == "editable":
					at = section.start
					break
	var block := lines.duplicate()
	block.append("")
	return "\n".join(_insert_lines(text.split("\n"), at, block))


## Un nodo movido o renombrado vuelve a donde está en `source` (en `source_path`), con su subárbol
## (como está ahora) y las conexiones que lo nombran al día.
static func _move(text: String, change: Dictionary, expected: String, source: String, source_path: String) -> Dictionary:
	var all := sections(text)
	var node := _find_node(all, str(change.uid), expected)
	if node.is_empty():
		return _fail(text, "the node is not there")
	if node.path != expected:
		return _fail(text, "changed after the turn")
	var source_all := sections(source)
	var there := _find_node(source_all, str(change.uid), source_path)
	if there.is_empty():
		return _fail(text, "the node is not in the other scene")
	var source_parent := _node_at(source_all, _parent_of(there.path))
	var parent := _find_node(all, str(source_parent.get("attrs", {}).get("unique_id", "")), source_parent.get("path", ""))
	if source_parent.is_empty() or parent.is_empty():
		return _fail(text, "its parent is not there")
	if _under(parent.path, node.path):
		return _fail(text, "its parent is inside it now")
	var path := _join(parent.path, str(there.attrs.name))
	if path != node.path and not _node_at(all, path).is_empty():
		return _fail(text, "there is another node with that name there")
	var lines := text.split("\n")
	var subtree := _subtree(all, node.path)
	var block: PackedStringArray = []
	var spans := {}
	for section: Dictionary in subtree.nodes:
		var section_lines: PackedStringArray = lines.slice(section.start, section.end)
		section_lines[0] = _rebase_header(section_lines[0], section, node.path, path)
		block.append_array(section_lines)
		block.append("")
		spans[section.start] = section.end
	for section: Dictionary in subtree.related:
		lines[section.start] = _rebase_header(lines[section.start], section, node.path, path)
	text = _drop_spans("\n".join(lines), spans)
	all = sections(text)
	var at := _place(all, source_all, there, parent.path, "")
	return _done("\n".join(_insert_lines(text.split("\n"), at, block)), [path])


# --- conexiones ----------------------------------------------------------------------------------

static func _drop_connection(text: String, change: Dictionary) -> Dictionary:
	for section: Dictionary in sections(text):
		if section.kind == "connection" and SceneDiff.connection_line(section.attrs) == change.line:
			return _done(_collect(_drop_spans(text, {section.start: section.end}), _refs(text)))
	return _fail(text, "the connection is not there")


static func _add_connection(text: String, change: Dictionary, source: String) -> Dictionary:
	var paths := {".": true}
	for section: Dictionary in sections(text):
		if section.kind == "node":
			paths[section.path] = true
		elif section.kind == "connection" and SceneDiff.connection_line(section.attrs) == change.line:
			return _fail(text, "the connection is already there")
	var source_lines := source.split("\n")
	for section: Dictionary in sections(source):
		if section.kind != "connection" or SceneDiff.connection_line(section.attrs) != change.line:
			continue
		var ends: Array = [str(section.attrs.get("from", "")), str(section.attrs.get("to", ""))]
		for end: String in ends:
			if not paths.has(end):
				return _fail(text, "%s is not there" % end)
		var imported := _import(text, "\n".join(source_lines.slice(section.start, section.end)), source)
		return _done(_append_related(imported.text, str(imported.value).split("\n"), false), ends)
	return _fail(text, "the connection is not in the other scene")
