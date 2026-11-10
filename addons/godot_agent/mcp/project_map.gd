@tool
extends RefCounted
## godot.project_map (m11-26): un mapa del proyecto rankeado hacia un foco, al estilo del repo map de
## Aider pero con las dependencias de Godot, que están en los .tscn y .tres y no en los imports.
##
## Grafo: archivos = nodos; aristas de quien usa a quien:
## - escena → scripts de sus nodos, escenas instanciadas (1) y demás ext_resource (0.5);
## - conexión de señal guardada en la escena: script del receptor → script del emisor (1);
## - script → preload/load con ruta literal, class_name y autoloads que nombra, su extends (1);
## - .tres → sus ext_resource (0.5);
## - grupo: script que lo usa → escenas con nodos en él (0.3).
## Ranking: PageRank personalizado hacia el foco, con las aristas en los dos sentidos (la vuelta pesa
## la mitad). La salida entra en un presupuesto de tokens (caracteres / 4).

const ProjectIndex := preload("../completion/project_index.gd")

const DAMPING := 0.85
## Con foco el ranking se queda más cerca de él: si no, los scripts que usa todo el proyecto (el
## jugador, el estado global) tapan a los vecinos del foco.
const FOCUS_DAMPING := 0.6
const ITERATIONS := 30
const REVERSE_WEIGHT := 0.5
const DEFAULT_TOKENS := 2000
const MIN_TOKENS := 200
const MAX_TOKENS := 8000
const CHARS_PER_TOKEN := 4
const SCENE_NODES_SHOWN := 12
const DECLS_SHOWN := 24
## Declaraciones de un archivo que no es del foco: el resto se pide con focus.
const RELATED_DECLS_SHOWN := 8
const PLACES_SHOWN := 3
const SHOWN_EXT: PackedStringArray = ["gd", "tscn", "tres", "cs"]

var index: ProjectIndex
## Raíz del índice ("res://", u otra carpeta en los tests y la medición: ver _res_view).
var root: String = "res://"
## Nombre -> ruta res://.
var autoloads: Dictionary = {}
## class_name -> ruta res://.
var class_paths: Dictionary = {}
## Ruta -> {destino: peso}.
var edges: Dictionary = {}
## "escena>script" de los scripts de sus nodos.
var attached: Dictionary = {}
var _known: Dictionary = {}


## El mapa de un índice armado con structure_only.
static func create(project_index: ProjectIndex, index_root: String, project_autoloads: Dictionary) -> RefCounted:
	var map := new()
	map.index = project_index if index_root == "res://" else _res_view(project_index, index_root)
	map.root = index_root
	map.autoloads = project_autoloads
	map._build()
	return map


## Los autoloads de project.godot en `index_root`: nombre -> ruta res://.
static func read_autoloads(index_root: String) -> Dictionary:
	var config := ConfigFile.new()
	var found := {}
	if config.load(index_root.path_join("project.godot")) != OK or not config.has_section("autoload"):
		return found
	for key: String in config.get_section_keys("autoload"):
		found[key] = str(config.get_value("autoload", key, "")).trim_prefix("*")
	return found


## Un índice de otra carpeta con las claves en res://, como las rutas de adentro de los archivos
## (los .tscn dicen res://, no la carpeta): así todo se busca igual. El índice original queda como
## estaba, porque el próximo build lo reusa.
static func _res_view(source: ProjectIndex, index_root: String) -> ProjectIndex:
	var view := ProjectIndex.new()
	view.structure_only = source.structure_only
	for key: String in source.scripts:
		view.scripts[_to_res(key, index_root)] = source.scripts[key]
	for key: String in source.scenes:
		view.scenes[_to_res(key, index_root)] = source.scenes[key]
	for key: String in source.resource_deps:
		view.resource_deps[_to_res(key, index_root)] = source.resource_deps[key]
	for path: String in source.resources:
		view.resources.append(_to_res(path, index_root))
	for script: String in source.script_nodes:
		var places: Array = []
		for place: Dictionary in source.script_nodes[script]:
			places.append({"scene": _to_res(str(place.scene), index_root), "node": place.node})
		view.script_nodes[script] = places
	view.groups = source.groups
	view.file_count = source.file_count
	return view


static func _to_res(path: String, index_root: String) -> String:
	return "res://" + path.substr(index_root.length()).trim_prefix("/") if path.begins_with(index_root) else path


func _build() -> void:
	for path: String in index.resources:
		_known[path] = true
	for path: String in index.scripts:
		var name: String = index.scripts[path].class_name
		if not name.is_empty():
			class_paths[name] = path
	var group_users := {}
	var group_members := {}
	for path: String in index.scripts:
		var info: Dictionary = index.scripts[path]
		var from := path
		var base := str(info.extends)
		if base.begins_with("res://") or base.ends_with(".gd"):
			_edge(from, _resolve(base, from), 1.0)
		elif class_paths.has(base):
			_edge(from, class_paths[base], 1.0)
		for target: String in info.get("refs", PackedStringArray()):
			_edge(from, _resolve(target, from), 1.0)
		for ident: String in info.get("idents", PackedStringArray()):
			if class_paths.has(ident):
				_edge(from, class_paths[ident], 1.0)
			if autoloads.has(ident):
				_edge(from, str(autoloads[ident]), 1.0)
		for group: String in info.get("groups", PackedStringArray()):
			(group_users.get_or_add(group, {}) as Dictionary)[from] = true
	for path: String in index.scenes:
		var scene: Dictionary = index.scenes[path]
		var from := path
		var direct := {}
		var node_scripts := {}
		for node: Dictionary in scene.nodes:
			var script := str(node.script)
			if script.is_empty() and not str(node.instance).is_empty():
				script = index._root_script(str(node.instance), 0)
			if not str(node.script).is_empty():
				_edge(from, str(node.script), 1.0)
				direct[str(node.script)] = true
				attached[from + ">" + str(node.script)] = true
			if not str(node.instance).is_empty():
				_edge(from, str(node.instance), 1.0)
				direct[str(node.instance)] = true
			node_scripts[str(node.path)] = script
			for group: String in node.groups:
				(group_members.get_or_add(group, {}) as Dictionary)[from] = true
		for dep: String in scene.get("deps", PackedStringArray()):
			if not direct.has(dep):
				_edge(from, dep, 0.5)
		for connection: Dictionary in scene.connections:
			var emitter := str(node_scripts.get(str(connection.from), ""))
			var receiver := str(node_scripts.get(str(connection.to), ""))
			if not emitter.is_empty() and not receiver.is_empty():
				_edge(receiver, emitter, 1.0)
	for path: String in index.resource_deps:
		for dep: String in index.resource_deps[path].deps:
			_edge(path, dep, 0.5)
	for group: String in group_users:
		for user: String in group_users[group]:
			for member: String in group_members.get(group, {}):
				_edge(user, member, 0.3)


func _edge(from: String, to: String, weight: float) -> void:
	if from == to or to.is_empty() or not _known.has(to):
		return
	var out: Dictionary = edges.get_or_add(from, {})
	out[to] = maxf(float(out.get(to, 0.0)), weight)


## Una ruta de preload/load o extends: absoluta (res://) o relativa a la carpeta del script.
func _resolve(target: String, from: String) -> String:
	if target.begins_with("res://"):
		return target
	if target.begins_with("uid://"):
		return ""
	return from.get_base_dir().path_join(target).simplify_path()


## Los archivos del foco: rutas res://, class_name, autoloads o nombres de archivo (con o sin
## extensión). Devuelve {paths, unknown}.
func resolve_focus(items: PackedStringArray) -> Dictionary:
	var paths := PackedStringArray()
	var unknown := PackedStringArray()
	for raw: String in items:
		var item := raw.strip_edges()
		if item.is_empty():
			continue
		var found := PackedStringArray()
		if _known.has(item):
			found.append(item)
		elif class_paths.has(item):
			found.append(class_paths[item])
		elif autoloads.has(item):
			found.append(str(autoloads[item]))
		else:
			var lower := item.to_lower()
			for path: String in _known:
				var file := path.get_file().to_lower()
				if file == lower or file.get_basename() == lower:
					found.append(path)
		if found.is_empty():
			unknown.append(item)
		for path: String in found:
			if not path in paths:
				paths.append(path)
	return {"paths": paths, "unknown": unknown}


## PageRank personalizado: ruta -> puntaje, hacia `focus` (vacío: todo el proyecto por igual).
func rank(focus: PackedStringArray) -> Dictionary:
	var nodes := {}
	for path: String in _known:
		if path.get_extension() in SHOWN_EXT:
			nodes[path] = true
	for from: String in edges:
		nodes[from] = true
		for to: String in edges[from]:
			nodes[to] = true
	# Lo que usa medio proyecto (el estado global, el jugador) recibe menos por cada uso: si no, tapa
	# a los vecinos del foco. Una escena y los scripts de sus nodos van juntos en los dos sentidos.
	var users := {}
	for from: String in edges:
		for to: String in edges[from]:
			users[to] = int(users.get(to, 0)) + 1
	var out := {}
	for from: String in edges:
		for to: String in edges[from]:
			var weight: float = float(edges[from][to]) / sqrt(float(users[to]))
			var back := weight if attached.has(from + ">" + to) else weight * REVERSE_WEIGHT
			(out.get_or_add(from, {}) as Dictionary)[to] = float((out.get(from, {}) as Dictionary).get(to, 0.0)) + weight
			(out.get_or_add(to, {}) as Dictionary)[from] = float((out.get(to, {}) as Dictionary).get(from, 0.0)) + back
	var personal := {}
	for path: String in focus:
		if nodes.has(path):
			personal[path] = 1.0 / focus.size()
	if personal.is_empty():
		for path: String in nodes:
			personal[path] = 1.0 / maxf(nodes.size(), 1.0)
	var totals := {}
	for from: String in out:
		var total := 0.0
		for to: String in out[from]:
			total += float(out[from][to])
		totals[from] = total
	var damping := DAMPING if personal.size() == nodes.size() else FOCUS_DAMPING
	var scores := personal.duplicate()
	for path: String in nodes:
		if not scores.has(path):
			scores[path] = 0.0
	for _i in ITERATIONS:
		var next := {}
		var dangling := 0.0
		for path: String in nodes:
			next[path] = 0.0
		for from: String in nodes:
			var score: float = scores[from]
			if not out.has(from):
				dangling += score
				continue
			for to: String in out[from]:
				next[to] += damping * score * float(out[from][to]) / float(totals[from])
		for path: String in nodes:
			next[path] += (1.0 - damping + damping * dangling) * float(personal.get(path, 0.0))
		scores = next
	return scores


## El mapa en texto, dentro de `max_tokens`. `focus`: lo que pidió el agente (o lo abierto);
## `focus_label` explica de dónde salió.
func render(focus: PackedStringArray, max_tokens: int, focus_label: String) -> String:
	var budget := clampi(max_tokens, MIN_TOKENS, MAX_TOKENS) * CHARS_PER_TOKEN
	var scores := rank(focus)
	var ranked: Array = scores.keys().filter(func(path: String) -> bool: return path.get_extension() in SHOWN_EXT)
	# A igual puntaje, el foco primero y después por ruta: así el resultado es estable.
	ranked.sort_custom(func(a: String, b: String) -> bool:
		if not is_equal_approx(float(scores[a]), float(scores[b])):
			return float(scores[a]) > float(scores[b])
		return a < b)
	for i in range(focus.size() - 1, -1, -1):
		if focus[i] in ranked:
			ranked.erase(focus[i])
			ranked.push_front(focus[i])
	var lines: PackedStringArray = ["Project map: %d scripts, %d scenes, %d resources. Ranked toward %s." % [index.scripts.size(), index.scenes.size(), index.resource_deps.size(), focus_label]]
	if not autoloads.is_empty():
		var names: PackedStringArray = []
		for name: String in autoloads:
			names.append("%s (%s)" % [name, autoloads[name]])
		lines.append("Autoloads: " + ", ".join(names))
	lines.append("")
	var used := "\n".join(lines).length()
	var shown := 0
	for path: String in ranked:
		var block := _file_block(path, DECLS_SHOWN if focus.is_empty() or path in focus else RELATED_DECLS_SHOWN)
		if used + block.length() + 1 > budget:
			block = _file_header(path)
			if used + block.length() + 1 > budget:
				break
		lines.append(block)
		used += block.length() + 1
		shown += 1
	if shown < ranked.size():
		lines.append("… %d more files. Raise max_tokens or narrow focus to see them." % (ranked.size() - shown))
	return "\n".join(lines)


func _file_header(path: String) -> String:
	match path.get_extension():
		"gd":
			var info: Dictionary = _script_info(path)
			var parts: PackedStringArray = [path, "script"]
			if not str(info.get("class_name", "")).is_empty():
				parts.append("class_name " + str(info.class_name))
			if not str(info.get("extends", "")).is_empty():
				parts.append("extends " + str(info.extends))
			return " · ".join(parts)
		"tscn":
			var root_node := _scene_root(path)
			return "%s · scene · root %s" % [path, _node_label(path, root_node)] if not root_node.is_empty() else "%s · scene" % path
		"tres":
			return "%s · resource" % path
	return path


func _file_block(path: String, decls_shown: int) -> String:
	var lines: PackedStringArray = [_file_header(path)]
	match path.get_extension():
		"gd":
			var info: Dictionary = _script_info(path)
			var decls: Array = info.get("decls", [])
			decls = decls.filter(func(decl: Array) -> bool: return not str(decl[1]).begins_with("class_name"))
			for decl: Array in decls.slice(0, decls_shown):
				lines.append("  %d: %s" % [decl[0], decl[1]])
			if decls.size() > decls_shown:
				lines.append("  … %d more declarations" % (decls.size() - decls_shown))
			var places: Array = index.script_nodes.get(path, [])
			if not places.is_empty():
				var shown: PackedStringArray = []
				for place: Dictionary in places.slice(0, PLACES_SHOWN):
					shown.append("%s (%s)" % [str(place.scene), place.node])
				lines.append("  on: " + ", ".join(shown) + (" +%d" % (places.size() - PLACES_SHOWN) if places.size() > PLACES_SHOWN else ""))
		"tscn":
			var scene: Dictionary = index.scenes.get(path, {})
			var nodes: Array = scene.get("nodes", [])
			# Sin tipo, instancia ni script es un cambio a un nodo de la escena base (escena heredada o
			# hijo editable): su árbol está en esa escena.
			var own: Array = nodes.slice(1).filter(func(node: Dictionary) -> bool:
				return not (str(node.type).is_empty() and str(node.instance).is_empty() and str(node.script).is_empty()))
			for node: Dictionary in own.slice(0, SCENE_NODES_SHOWN - 1):
				var depth := str(node.path).count("/") + 1
				lines.append("  " + "  ".repeat(depth - 1) + _node_label(path, node))
			if own.size() > SCENE_NODES_SHOWN - 1:
				lines.append("  … %d more nodes" % (own.size() - SCENE_NODES_SHOWN + 1))
			var connections: Array = scene.get("connections", [])
			var root_name := str(nodes[0].name) if not nodes.is_empty() else "."
			for connection: Dictionary in connections.slice(0, 6):
				var from_node := root_name if connection.from == ProjectIndex.ROOT else str(connection.from)
				var to_node := root_name if connection.to == ProjectIndex.ROOT else str(connection.to)
				lines.append("  signal %s.%s → %s.%s" % [from_node, connection.signal, to_node, connection.method])
			if connections.size() > 6:
				lines.append("  … %d more connections" % (connections.size() - 6))
		"tres":
			var deps: PackedStringArray = index.resource_deps.get(path, {}).get("deps", PackedStringArray())
			if not deps.is_empty():
				lines.append("  uses: " + ", ".join(deps.slice(0, 4)) + (" +%d" % (deps.size() - 4) if deps.size() > 4 else ""))
	return "\n".join(lines)


func _node_label(scene_path: String, node: Dictionary) -> String:
	var type := index.node_type(scene_path, node)
	var label := "%s: %s" % [node.name, type if not type.is_empty() else "?"]
	if node.get("unique", false):
		label = "%" + label
	if not str(node.script).is_empty():
		label += " script " + _short(scene_path, str(node.script))
	if not str(node.instance).is_empty():
		label += " instance " + _short(scene_path, str(node.instance))
	var groups: PackedStringArray = node.get("groups", PackedStringArray())
	if not groups.is_empty():
		label += " groups " + ",".join(groups)
	return label


## Una ruta de la misma carpeta, por nombre; si no, completa.
static func _short(from: String, path: String) -> String:
	return path.get_file() if path.get_base_dir() == from.get_base_dir() else path


func _scene_root(path: String) -> Dictionary:
	var nodes: Array = index.scenes.get(path, {}).get("nodes", [])
	return nodes[0] if not nodes.is_empty() else {}


func _script_info(path: String) -> Dictionary:
	return index.scripts.get(path, {})

