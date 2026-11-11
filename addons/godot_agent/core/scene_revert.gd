@tool
extends RefCounted
## Rechazar por nodo los cambios de un turno en una escena .tscn (m11-34, fase 1): una propiedad
## cambiada vuelve a su valor de antes y un nodo agregado se va con sus descendientes y sus
## conexiones. Trabaja sobre el texto actual del archivo y antes de tocarlo verifica que lo que va a
## deshacer siga como lo dejó el turno; si cambió después, no escribe nada (queda stale). «Deshacer»
## es la operación inversa, con la misma verificación.
##
## Lo demás (nodos borrados o movidos, propiedades con recursos, conexiones, grupos) sale en la lista
## sin poder rechazarse: para eso está «Volver atrás» del archivo (fase 2: m11-59).

const SceneDiff := preload("scene_diff.gd")

const PROP := "prop"
const ADDED := "added"
const OTHER := "other"
## Propiedades que no se rechazan por línea: no son una línea `nombre = valor` del nodo.
const NOT_LINES: PackedStringArray = ["type", "name", "groups"]


## Los cambios de una escena entre dos textos, en el orden del diff por nodos: [{kind (PROP, ADDED u
## OTHER), label (para mostrar), rejectable, path, uid, ...}]. PROP lleva name, before y after (el
## texto del valor como está en el archivo, null si no estaba); ADDED lleva children y lines (sus
## secciones y conexiones en el texto de después, para volver a ponerlas).
static func changes(before_text: String, after_text: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var diff := SceneDiff.diff(before_text, after_text)
	if not str(diff.error).is_empty():
		return result
	var before := SceneDiff._nodes(SceneDiff.parse(before_text))
	var after := SceneDiff._nodes(SceneDiff.parse(after_text))
	var pairs := SceneDiff._match(before, after)
	for node: Dictionary in diff.added:
		var now: Dictionary = after.list[after.by_path[node.path]]
		result.append({"kind": ADDED, "path": node.path, "uid": now.uid, "type": node.type, "children": node.children,
			"lines": _subtree_lines(after_text, node.path), "rejectable": node.path != ".",
			"label": "+ %s" % node.path})
	for node: Dictionary in diff.removed:
		result.append({"kind": OTHER, "path": node.path, "rejectable": false, "label": "− %s" % node.path})
	for node: Dictionary in diff.moved:
		result.append({"kind": OTHER, "path": node.to, "rejectable": false, "label": "→ %s ← %s" % [node.to, node.from]})
	for node: Dictionary in diff.changed:
		var i: int = after.by_path[node.path]
		var now: Dictionary = after.list[i]
		var was: Dictionary = before.list[pairs.before_of[i]]
		for prop: Dictionary in node.props:
			var name := str(prop.name)
			var raw_before: Variant = was.raw.get(name)
			var raw_after: Variant = now.raw.get(name)
			var simple := not name in NOT_LINES and not name.contains(".") \
				and not str(raw_before).contains("Resource(") and not str(raw_after).contains("Resource(")
			result.append({"kind": PROP if simple else OTHER, "path": node.path, "uid": now.uid, "name": name,
				"before": raw_before, "after": raw_after, "rejectable": simple,
				"label": "~ %s · %s" % [node.path, name], "shown_before": prop.before, "shown_after": prop.after})
	for connection: String in diff.connections_added:
		result.append({"kind": OTHER, "rejectable": false, "label": "+ " + connection})
	for connection: String in diff.connections_removed:
		result.append({"kind": OTHER, "rejectable": false, "label": "− " + connection})
	return result


## Deshace `change` en `text` (o, con `undo`, lo vuelve a hacer). {ok, text, error}: si lo que
## había que deshacer ya no está como lo dejó el turno, ok es false y text queda igual.
static func apply(text: String, change: Dictionary, undo: bool = false) -> Dictionary:
	if not change.get("rejectable", false):
		return {"ok": false, "text": text, "error": "not rejectable"}
	match str(change.kind):
		PROP:
			var expected: Variant = change.before if undo else change.after
			var wanted: Variant = change.after if undo else change.before
			return _set_property(text, change, expected, wanted)
		ADDED:
			return _insert_subtree(text, change) if undo else _remove_subtree(text, change)
	return {"ok": false, "text": text, "error": "not rejectable"}


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
					current.path = "." if not attrs.has("parent") else (str(attrs.name) if attrs.parent == "." else "%s/%s" % [attrs.parent, attrs.name])
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


## La sección del nodo de un cambio en el texto actual: por unique_id si lo tiene, si no por ruta.
static func _find_node(all: Array[Dictionary], change: Dictionary) -> Dictionary:
	var uid := str(change.get("uid", ""))
	for section: Dictionary in all:
		if section.kind != "node":
			continue
		if not uid.is_empty() and str(section.attrs.get("unique_id", "")) == uid:
			return section
	if uid.is_empty():
		for section: Dictionary in all:
			if section.kind == "node" and section.path == change.path:
				return section
	return {}


static func _set_property(text: String, change: Dictionary, expected: Variant, wanted: Variant) -> Dictionary:
	var all := sections(text)
	var node := _find_node(all, change)
	if node.is_empty():
		return {"ok": false, "text": text, "error": "the node is not there"}
	var name := str(change.name)
	var current: Variant = node.props[name].value if node.props.has(name) else null
	if current != expected:
		return {"ok": false, "text": text, "error": "changed after the turn"}
	var lines := text.split("\n")
	var out: PackedStringArray = []
	if node.props.has(name):
		var prop: Dictionary = node.props[name]
		out.append_array(lines.slice(0, prop.start))
		if wanted != null:
			out.append_array(("%s = %s" % [name, wanted]).split("\n"))
		out.append_array(lines.slice(prop.end))
	else:
		out.append_array(lines.slice(0, node.end))
		out.append_array(("%s = %s" % [name, wanted]).split("\n"))
		out.append_array(lines.slice(node.end))
	return {"ok": true, "text": "\n".join(out), "error": ""}


## Las líneas de un nodo y sus descendientes (y las conexiones que los nombran) en un texto, para
## volver a ponerlas: {nodes: [líneas por sección], connections: [líneas], after: ruta del nodo que
## venía justo después de la última sección, o ""}.
static func _subtree_lines(text: String, path: String) -> Dictionary:
	var all := sections(text)
	var lines := text.split("\n")
	var nodes: Array = []
	var connections: Array = []
	var next := ""
	var inside := false
	for section: Dictionary in all:
		if section.kind == "node":
			var mine: bool = section.path == path or str(section.path).begins_with(path + "/")
			if mine:
				nodes.append(lines.slice(section.start, section.end))
				inside = true
			elif inside and next.is_empty():
				next = section.path
				inside = false
		elif section.kind == "connection" and _names(section, path):
			connections.append(lines.slice(section.start, section.end))
	return {"nodes": nodes, "connections": connections, "after": next}


static func _names(connection: Dictionary, path: String) -> bool:
	for key: String in ["from", "to"]:
		var target := str(connection.attrs.get(key, ""))
		if target == path or target.begins_with(path + "/"):
			return true
	return false


static func _remove_subtree(text: String, change: Dictionary) -> Dictionary:
	var all := sections(text)
	var node := _find_node(all, change)
	if node.is_empty():
		return {"ok": false, "text": text, "error": "the node is not there"}
	var path: String = node.path
	var drop: Array[Vector2i] = []
	for section: Dictionary in all:
		var mine := false
		if section.kind == "node":
			mine = section.path == path or str(section.path).begins_with(path + "/")
		elif section.kind == "connection":
			mine = _names(section, path)
		if mine:
			drop.append(Vector2i(section.start, section.end))
	var lines := text.split("\n")
	var keep: PackedStringArray = []
	var i := 0
	while i < lines.size():
		var skipped := false
		for span: Vector2i in drop:
			if i == span.x:
				i = span.y
				# y la línea vacía que separa la sección de la siguiente
				if i < lines.size() and lines[i].is_empty():
					i += 1
				skipped = true
				break
		if not skipped:
			keep.append(lines[i])
			i += 1
	return {"ok": true, "text": "\n".join(keep), "error": ""}


static func _insert_subtree(text: String, change: Dictionary) -> Dictionary:
	var all := sections(text)
	if not _find_node(all, change).is_empty():
		return {"ok": false, "text": text, "error": "the node is already there"}
	var saved: Dictionary = change.lines
	var parent := str(change.path).get_base_dir() if str(change.path).contains("/") else "."
	var has_parent := false
	for section: Dictionary in all:
		if section.kind == "node" and section.path == parent:
			has_parent = true
	if not has_parent:
		return {"ok": false, "text": text, "error": "its parent is not there"}
	var block: PackedStringArray = []
	for node_lines: PackedStringArray in saved.nodes:
		block.append_array(node_lines)
		block.append("")
	var lines := text.split("\n")
	# Donde estaba: antes del nodo que le seguía, si sigue; si no, después del último nodo.
	var at := -1
	var last_node_end := 0
	for section: Dictionary in all:
		if section.kind == "node":
			last_node_end = section.end
			if section.path == saved.after and at < 0:
				at = section.start
	var out: PackedStringArray = []
	if at >= 0:
		out.append_array(lines.slice(0, at))
		out.append_array(block)  # termina en una línea vacía, antes del nodo que sigue
		out.append_array(lines.slice(at))
	else:
		out.append_array(lines.slice(0, last_node_end))
		out.append("")
		block.resize(block.size() - 1)
		out.append_array(block)
		out.append_array(lines.slice(last_node_end))
	var result := "\n".join(out)
	for connection: PackedStringArray in saved.connections:
		result = result.rstrip("\n") + "\n\n" + "\n".join(connection) + "\n"
	return {"ok": true, "text": result, "error": ""}
