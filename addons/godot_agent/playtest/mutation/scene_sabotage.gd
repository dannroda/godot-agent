extends RefCounted
## Sabotajes de escena para medir las regresiones (m11-62, fase 2 de m11-41): una propiedad exportada a
## 0/false/null, una señal desconectada, un nodo oculto, una colisión deshabilitada. Se leen del
## SceneState del .tscn (sin instanciar nada en el editor) y se aplican en memoria sobre la escena que
## corre, después de que se asentó: el archivo no se toca, y la guarda de guardado sigue puesta.
## Una regresión puede no mirar el código que muta GDScriptMutator pero sí el estado de la escena.
## Idea de Beckett v1.16 (op=mutate: «puts one fault at a time into a restarted scene»).

const KIND := "scene"
const OP_PROPERTY := "property"
const OP_SIGNAL := "signal"
const OP_HIDE := "hide"
const OP_DISABLE := "disable"
## Lo que viaja al proceso del mutante (MutationTesting._process).
const SENT_KEYS: Array = ["kind", "path", "line", "node", "op", "property", "value", "signal", "target", "method", "change"]

## Tipos con `disabled`: deshabilitarlos saca la colisión sin sacar el nodo.
const DISABLE_TYPES: PackedStringArray = ["CollisionShape2D", "CollisionPolygon2D", "CollisionShape3D", "CollisionPolygon3D"]
## Escenas instanciadas dentro de escenas: hasta esta profundidad.
const MAX_DEPTH := 3


## Los sabotajes de `scene`. `hint`: el código de sus regresiones; si nombra nodos de la escena, solo
## se sabotean esos, la raíz y las señales que llegan a la raíz, que son lo que la regresión toca.
static func sabotages(scene: String, hint: String = "") -> Array[Dictionary]:
	var all: Array[Dictionary] = []
	_collect(scene, scene, "", 0, all)
	if hint.is_empty():
		return all
	var touched := all.filter(func(sabotage: Dictionary) -> bool:
		return sabotage.node == "." or sabotage.get("target") == "." or _mentions(hint, str(sabotage.node).get_file()))
	return touched if touched.size() > all.filter(func(sabotage: Dictionary) -> bool: return sabotage.node == ".").size() else all


static func _mentions(code: String, name: String) -> bool:
	return not name.is_empty() and RegEx.create_from_string("\\b%s\\b" % _escape(name)).search(code) != null


static func _escape(text: String) -> String:
	var escaped := ""
	for character in text:
		escaped += "\\" + character if "\\^$.|?*+()[]{}".contains(character) else character
	return escaped


static func _collect(scene: String, file: String, prefix: String, depth: int, into: Array[Dictionary]) -> void:
	var packed := load(file) as PackedScene if ResourceLoader.exists(file) else null
	if packed == null or depth > MAX_DEPTH:
		return
	var state := packed.get_state()
	for i in state.get_node_count():
		var node := _join(prefix, str(state.get_node_path(i)))
		var overrides := {}
		for j in state.get_node_property_count(i):
			overrides[state.get_node_property_name(i, j)] = state.get_node_property_value(i, j)
		var type := state.get_node_type(i)
		var instance := state.get_node_instance(i)
		if instance:
			# Lo de adentro de la escena instanciada se lee de su archivo, con este nodo como prefijo.
			_collect(scene, instance.resource_path, node, depth + 1, into)
			if type.is_empty() and instance.get_state().get_node_count() > 0:
				type = instance.get_state().get_node_type(0)
		var script: Variant = overrides.get("script")
		if script is GDScript:
			for property: Dictionary in (script as GDScript).get_script_property_list():
				if property.usage & PROPERTY_USAGE_SCRIPT_VARIABLE == 0 or property.usage & PROPERTY_USAGE_EDITOR == 0:
					continue
				var current: Variant = overrides.get(property.name, (script as GDScript).get_property_default_value(property.name))
				var broken := _broken(current, int(property.type))
				if not broken.is_empty():
					into.append(_sabotage(scene, node, OP_PROPERTY, {"property": property.name, "value": var_to_str(broken[0]),
						"change": "%s.%s = %s" % [_label(node), property.name, var_to_str(broken[0])]}))
		if (ClassDB.is_parent_class(type, "CanvasItem") or ClassDB.is_parent_class(type, "Node3D")) and not type in DISABLE_TYPES and overrides.get("visible", true) == true:
			into.append(_sabotage(scene, node, OP_HIDE, {"change": "%s hidden" % _label(node)}))
		if type in DISABLE_TYPES and overrides.get("disabled", false) == false:
			into.append(_sabotage(scene, node, OP_DISABLE, {"change": "%s disabled" % _label(node)}))
	for c in state.get_connection_count():
		var source := _join(prefix, str(state.get_connection_source(c)))
		var target := _join(prefix, str(state.get_connection_target(c)))
		var signal_name := str(state.get_connection_signal(c))
		var method := str(state.get_connection_method(c))
		into.append(_sabotage(scene, source, OP_SIGNAL, {"signal": signal_name, "target": target, "method": method,
			"change": "%s.%s → %s.%s disconnected" % [_label(source), signal_name, _label(target), method]}))


## [valor roto], o [] si no hay uno que cambie algo (ya está en 0, un tipo que no se rompe así).
static func _broken(current: Variant, type: int) -> Array:
	match type:
		TYPE_INT:
			return [0] if current != null and int(current) != 0 else []
		TYPE_FLOAT:
			return [0.0] if current != null and not is_zero_approx(float(current)) else []
		TYPE_BOOL:
			return [not bool(current)] if current != null else [true]
		TYPE_VECTOR2, TYPE_VECTOR3, TYPE_VECTOR2I, TYPE_VECTOR3I:
			return [type_convert(Vector3.ZERO, type)] if current != null and current != type_convert(Vector3.ZERO, type) else []
		TYPE_OBJECT:
			return [null] if current != null else []
	return []


static func _sabotage(scene: String, node: String, op: String, extra: Dictionary) -> Dictionary:
	var sabotage := {"kind": KIND, "path": scene, "line": 0, "node": node, "op": op}
	sabotage.merge(extra)
	return sabotage


static func _join(prefix: String, path: String) -> String:
	path = path.trim_prefix("./")
	if prefix.is_empty():
		return path
	return prefix if path == "." else prefix.path_join(path)


static func _label(node: String) -> String:
	return "root" if node == "." else node


## Aplica el sabotaje a la escena que corre. "" si quedó puesto, o por qué no (el nodo ya no está, la
## señal no está conectada…): entonces el mutante no vale.
static func apply(root: Node, sabotage: Dictionary) -> String:
	var path := str(sabotage.get("node", "."))
	var node := root if path == "." else root.get_node_or_null(NodePath(path))
	if node == null:
		return "the node %s is not in the scene" % path
	match str(sabotage.get("op", "")):
		OP_PROPERTY:
			var property := str(sabotage.get("property", ""))
			if not property in node:
				return "%s has no property %s" % [path, property]
			node.set(property, str_to_var(str(sabotage.get("value", "null"))))
		OP_HIDE:
			if not "visible" in node:
				return "%s can't be hidden" % path
			node.set("visible", false)
		OP_DISABLE:
			if not "disabled" in node:
				return "%s can't be disabled" % path
			node.set_deferred("disabled", true)
		OP_SIGNAL:
			var target_path := str(sabotage.get("target", "."))
			var target := root if target_path == "." else root.get_node_or_null(NodePath(target_path))
			var cut := 0
			for connection: Dictionary in node.get_signal_connection_list(str(sabotage.get("signal", ""))):
				var callable: Callable = connection.callable
				if callable.get_object() == target and callable.get_method() == StringName(sabotage.get("method", "")):
					node.disconnect(connection.signal.get_name(), callable)
					cut += 1
			if cut == 0:
				return "%s.%s is not connected to %s" % [path, sabotage.get("signal", ""), sabotage.get("method", "")]
		_:
			return "unknown sabotage %s" % sabotage.get("op", "")
	return ""
