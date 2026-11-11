@tool
extends RefCounted
## Diff por nodos de dos .tscn (m11-57): qué nodos se agregaron, se borraron o se movieron (o
## renombraron), qué propiedades cambiaron (antes → después) y qué conexiones de señales. Sale del
## texto de las dos escenas, parseado acá: no carga recursos ni scripts, no usa git ni el editor.
##
## Los nodos se emparejan por `unique_id` (los .tscn de 4.6+); un nodo sin él, por su ruta, y si
## no aparece, por nombre y tipo (si hay uno solo así de cada lado: lo movieron). Los ids de
## ext_resource y sub_resource cambian de una vez a otra sin que cambie nada: un ExtResource se
## compara por su ruta y un SubResource por su contenido (sus propiedades quedan como
## `shape.size`). Las rutas de los nodos son relativas a la raíz ("." es la raíz).

const SECTIONS: PackedStringArray = ["gd_scene", "ext_resource", "sub_resource", "node", "connection", "editable"]
## Hasta qué profundidad se abren los SubResource anidados en propiedades `a.b.c`.
const SUB_DEPTH := 2
## Las propiedades de un SubResource con muchísimas (datos de un TileSet…) se comparan enteras pero
## no se abren de a una.
const SUB_MAX_PROPS := 40

static var _attr_re: RegEx
static var _ext_re: RegEx
static var _sub_re: RegEx
static var _sub_whole_re: RegEx


## true si el texto es una escena de texto (.tscn).
static func is_scene_text(text: String) -> bool:
	return text.strip_edges(true, false).begins_with("[gd_scene")


## El diff de dos escenas. Una vacía es una escena que no existía (o que se borró). Devuelve:
## {added: [{path, type, children}], removed: [{path, type, children}], moved: [{from, to, type}],
##  changed: [{path, type, props: [{name, before, after}]}], connections_added, connections_removed
##  (PackedStringArray), nodes_before, nodes_after (int), error (String, "" si se pudo)}.
## `children` es cuántos nodos de abajo vinieron o se fueron con él (no se listan aparte).
static func diff(before_text: String, after_text: String) -> Dictionary:
	var result := {
		"added": [], "removed": [], "moved": [], "changed": [],
		"connections_added": PackedStringArray(), "connections_removed": PackedStringArray(),
		"nodes_before": 0, "nodes_after": 0, "error": "",
	}
	for text: String in [before_text, after_text]:
		if not text.strip_edges().is_empty() and not is_scene_text(text):
			result.error = "not a text scene (.tscn)"
			return result
	var before := _nodes(parse(before_text))
	var after := _nodes(parse(after_text))
	result.nodes_before = before.list.size()
	result.nodes_after = after.list.size()
	var pairs := _match(before, after)
	var before_of: Dictionary = pairs.before_of  # índice en after -> índice en before
	var after_of: Dictionary = pairs.after_of
	# Lo que vino o se fue: solo los de más arriba, con cuántos traen abajo.
	result.added = _tops(after.list, before_of)
	result.removed = _tops(before.list, after_of)
	# Movidos: el nombre o el padre (emparejado) cambió. Los hijos de un nodo movido cambian de ruta
	# pero no se movieron.
	for i: int in before_of:
		var now: Dictionary = after.list[i]
		var was: Dictionary = before.list[before_of[i]]
		if now.path == was.path:
			continue
		var parent_now: String = now.parent
		var parent_was: String = was.parent
		var parent_was_now := ""
		if before.by_path.has(parent_was) and after_of.has(before.by_path[parent_was]):
			parent_was_now = after.list[after_of[before.by_path[parent_was]]].path
		if now.name != was.name or parent_was_now != parent_now:
			result.moved.append({"from": was.path, "to": now.path, "type": now.type})
	# Propiedades, en el orden en que aparecen en la escena de después.
	for i in after.list.size():
		if not before_of.has(i):
			continue
		var now: Dictionary = after.list[i]
		var was: Dictionary = before.list[before_of[i]]
		var props: Array[Dictionary] = []
		if now.path == "." and now.name != was.name:
			props.append({"name": "name", "before": was.name, "after": now.name})  # la raíz no se «mueve»
		if now.type != was.type:
			props.append({"name": "type", "before": was.type, "after": now.type})
		var keys: Array = now.props.keys()
		for key: String in was.props:
			if not now.props.has(key):
				keys.append(key)
		for key: String in keys:
			var a: Variant = was.props.get(key)
			var b: Variant = now.props.get(key)
			if a != b:
				props.append({"name": key, "before": a, "after": b})
		if not props.is_empty():
			result.changed.append({"path": now.path, "type": now.type, "props": props})
	var connections_before: Dictionary = {}
	for connection: String in before.connections:
		connections_before[connection] = true
	var connections_after: Dictionary = {}
	for connection: String in after.connections:
		connections_after[connection] = true
		if not connections_before.has(connection):
			result.connections_added.append(connection)
	for connection: String in before.connections:
		if not connections_after.has(connection):
			result.connections_removed.append(connection)
	return result


## Cuántos cambios tiene un diff (cada propiedad cuenta uno).
static func count(result: Dictionary) -> int:
	var total: int = result.added.size() + result.removed.size() + result.moved.size()
	total += result.connections_added.size() + result.connections_removed.size()
	for node: Dictionary in result.changed:
		total += node.props.size()
	return total


## Las secciones de un .tscn: {ext: {id: ruta}, sub: {id: sección}, nodes: [sección],
## connections: [sección]}; cada sección es {kind, attrs: {nombre: valor}, props: {nombre: texto}}.
## Los valores quedan como texto, tal como están en el archivo (pueden ocupar varias líneas).
static func parse(text: String) -> Dictionary:
	var scene := {"ext": {}, "sub": {}, "nodes": [], "connections": []}
	var current: Dictionary = {}
	var key := ""
	var value := ""
	var state := [0, false]  # [profundidad de corchetes, dentro de un string]
	for line: String in text.split("\n"):
		if not key.is_empty():
			value += "\n" + line
			state = _scan(line, state)
			if state[0] <= 0 and not state[1]:
				current.props[key] = value
				key = ""
			continue
		if line.begins_with("["):
			var kind := line.substr(1).get_slice(" ", 0).trim_suffix("]")
			if kind in SECTIONS:
				var attrs := _attrs(line)
				current = {"kind": kind, "attrs": attrs, "props": {}}
				match kind:
					"ext_resource":
						scene.ext[str(attrs.get("id", ""))] = str(attrs.get("path", ""))
					"sub_resource":
						scene.sub[str(attrs.get("id", ""))] = current
					"node":
						scene.nodes.append(current)
					"connection":
						scene.connections.append(current)
				continue
		var equals := line.find(" = ")
		if equals <= 0 or current.is_empty() or line.begins_with(" ") or line.begins_with("\t"):
			continue
		key = line.substr(0, equals)
		value = line.substr(equals + 3)
		state = _scan(value, [0, false])
		if state[0] <= 0 and not state[1]:
			current.props[key] = value
			key = ""
	return scene


## Sigue corchetes y strings de un valor que puede seguir en la línea siguiente.
static func _scan(text: String, state: Array) -> Array:
	var depth: int = state[0]
	var in_string: bool = state[1]
	if not text.contains("\""):  # lo común (números, vectores, arrays grandes): contar sin recorrer
		if in_string:
			return [depth, true]
		depth += text.count("(") + text.count("[") + text.count("{") - text.count(")") - text.count("]") - text.count("}")
		return [depth, false]
	var escaped := false
	for i in text.length():
		var c := text[i]
		if in_string:
			if escaped:
				escaped = false
			elif c == "\\":
				escaped = true
			elif c == "\"":
				in_string = false
		elif c == "\"":
			in_string = true
		elif c in ["(", "[", "{"]:
			depth += 1
		elif c in [")", "]", "}"]:
			depth -= 1
	return [depth, in_string]


## Los atributos de un encabezado `[node name="A" type="B" unique_id=12 groups=["x"]]`.
static func _attrs(header: String) -> Dictionary:
	if _attr_re == null:
		_attr_re = RegEx.create_from_string("(\\w+)=(\"(?:[^\"\\\\]|\\\\.)*\"|\\[[^\\]]*\\]|\\w+\\(\"[^\"]*\"\\)|[^\\s\\]]+)")
	var attrs := {}
	for found: RegExMatch in _attr_re.search_all(header):
		var raw := found.get_string(2)
		if raw.begins_with("\"") and raw.ends_with("\"") and raw.length() >= 2:
			raw = raw.substr(1, raw.length() - 2).c_unescape()
		attrs[found.get_string(1)] = raw
	return attrs


## Los nodos de una escena parseada, con su ruta y sus propiedades ya comparables:
## {list: [{path, name, parent, type, uid, props}], by_path: {ruta: índice}, by_uid: {uid: índice},
##  connections: PackedStringArray}.
static func _nodes(scene: Dictionary) -> Dictionary:
	var list: Array[Dictionary] = []
	var by_path := {}
	var by_uid := {}
	for section: Dictionary in scene.nodes:
		var attrs: Dictionary = section.attrs
		var name := str(attrs.get("name", ""))
		var parent := str(attrs.get("parent", ""))
		var path := "."
		if attrs.has("parent"):
			path = name if parent == "." else parent + "/" + name
		var type := str(attrs.get("type", ""))
		if attrs.has("instance"):  # una escena instanciada: su ruta
			type = _resolve(str(attrs.instance), scene).trim_prefix("ExtResource(\"").trim_suffix("\")")
		var props := {}
		_flatten(section.props, scene, "", 0, props)
		if attrs.has("groups"):
			props["groups"] = str(attrs.groups)
		var node := {"path": path, "name": name, "parent": parent if attrs.has("parent") else "", "type": type, "uid": str(attrs.get("unique_id", "")), "props": props, "raw": section.props}
		by_path[path] = list.size()
		if not node.uid.is_empty():
			by_uid[node.uid] = list.size()
		list.append(node)
	var connections: PackedStringArray = []
	for section: Dictionary in scene.connections:
		var attrs: Dictionary = section.attrs
		var line := "%s: %s → %s.%s()" % [attrs.get("signal", ""), attrs.get("from", ""), attrs.get("to", ""), attrs.get("method", "")]
		for extra: String in ["flags", "binds", "unbinds"]:
			if attrs.has(extra):
				line += " %s=%s" % [extra, attrs[extra]]
		connections.append(line)
	return {"list": list, "by_path": by_path, "by_uid": by_uid, "connections": connections}


## Propiedades comparables: un ExtResource por su ruta, un SubResource abierto en `prop.sub`.
static func _flatten(props: Dictionary, scene: Dictionary, prefix: String, depth: int, out: Dictionary) -> void:
	if _sub_whole_re == null:
		_sub_whole_re = RegEx.create_from_string("^SubResource\\(\"([^\"]+)\"\\)$")
	for key: String in props:
		var value := str(props[key])
		var whole := _sub_whole_re.search(value)
		if whole and scene.sub.has(whole.get_string(1)):
			var sub: Dictionary = scene.sub[whole.get_string(1)]
			out[prefix + key] = str(sub.attrs.get("type", "Resource"))
			if depth < SUB_DEPTH and sub.props.size() <= SUB_MAX_PROPS:
				_flatten(sub.props, scene, prefix + key + ".", depth + 1, out)
			else:
				out[prefix + key] += " " + str(_content(sub, scene).hash())
			continue
		out[prefix + key] = _resolve(value, scene)


## Un valor con los ids de recursos cambiados por lo que nombran: un SubResource, por un hash de su
## contenido (con los anidados resueltos igual, hasta una profundidad).
static func _resolve(value: String, scene: Dictionary, depth: int = 0) -> String:
	if not value.contains("Resource("):
		return value
	if _ext_re == null:
		_ext_re = RegEx.create_from_string("ExtResource\\(\"([^\"]+)\"\\)")
		_sub_re = RegEx.create_from_string("SubResource\\(\"([^\"]+)\"\\)")
	var out := value
	for found: RegExMatch in _ext_re.search_all(value):
		out = out.replace(found.get_string(0), "ExtResource(\"%s\")" % scene.ext.get(found.get_string(1), found.get_string(1)))
	for found: RegExMatch in _sub_re.search_all(value):
		var sub: Dictionary = scene.sub.get(found.get_string(1), {})
		if not sub.is_empty():
			var content := _content(sub, scene, depth + 1) if depth < 4 else ""
			out = out.replace(found.get_string(0), "SubResource(%s %d)" % [sub.attrs.get("type", "Resource"), content.hash()])
	return out


## El contenido de un sub_resource sin su id, para compararlo.
static func _content(sub: Dictionary, scene: Dictionary, depth: int = 0) -> String:
	var parts: PackedStringArray = [str(sub.attrs.get("type", ""))]
	for key: String in sub.props:
		parts.append("%s=%s" % [key, _resolve(str(sub.props[key]), scene, depth)])
	return "\n".join(parts)


## Empareja los nodos: por unique_id; si falta, por ruta (salvo que los dos tengan ids distintos:
## es otro nodo con el mismo nombre); y lo que queda, por nombre y tipo si es único de cada lado.
static func _match(before: Dictionary, after: Dictionary) -> Dictionary:
	var before_of := {}
	var after_of := {}
	for i in after.list.size():
		var node: Dictionary = after.list[i]
		var j := -1
		if not node.uid.is_empty() and before.by_uid.has(node.uid):
			j = before.by_uid[node.uid]
		elif before.by_path.has(node.path):
			var other: Dictionary = before.list[before.by_path[node.path]]
			if node.uid.is_empty() or other.uid.is_empty():
				j = before.by_path[node.path]
		if j >= 0 and not after_of.has(j):
			before_of[i] = j
			after_of[j] = i
	var left := {}
	for j in before.list.size():
		var node: Dictionary = before.list[j]
		if not after_of.has(j):
			var key := "%s|%s" % [node.name, node.type]
			left[key] = -2 if left.has(key) else j
	var right := {}
	for i in after.list.size():
		var node: Dictionary = after.list[i]
		if not before_of.has(i):
			var key := "%s|%s" % [node.name, node.type]
			right[key] = -2 if right.has(key) else i
	for key: String in right:
		var i: int = right[key]
		var j: int = left.get(key, -1)
		if i < 0 or j < 0:
			continue
		if not after.list[i].uid.is_empty() and not before.list[j].uid.is_empty():
			continue  # los dos con id y distinto: son nodos distintos
		before_of[i] = j
		after_of[j] = i
	return {"before_of": before_of, "after_of": after_of}


## Los nodos sin pareja que no están debajo de otro sin pareja, con cuántos tienen abajo.
static func _tops(list: Array, matched: Dictionary) -> Array[Dictionary]:
	var lonely := {}
	for i in list.size():
		if not matched.has(i):
			lonely[list[i].path] = i
	var tops: Array[Dictionary] = []
	var top_of := {}
	for i in list.size():
		if matched.has(i):
			continue
		var node: Dictionary = list[i]
		var ancestor := _lonely_ancestor(node.path, lonely)
		if ancestor.is_empty():
			top_of[node.path] = tops.size()
			tops.append({"path": node.path, "type": node.type, "children": 0})
		elif top_of.has(ancestor):
			tops[top_of[ancestor]].children += 1
	return tops


## El ancestro más alto de `path` que también está en `lonely`, o "".
static func _lonely_ancestor(path: String, lonely: Dictionary) -> String:
	if path == ".":
		return ""
	if lonely.has("."):
		return "."
	var parts := path.split("/")
	var prefix := ""
	for k in parts.size() - 1:
		prefix = parts[k] if prefix.is_empty() else prefix + "/" + parts[k]
		if lonely.has(prefix):
			return prefix
	return ""
