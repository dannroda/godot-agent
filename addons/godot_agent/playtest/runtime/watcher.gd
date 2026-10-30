extends RefCounted
## game_watch (m15-20): qué cambió en unos nodos durante una ventana de tiempo, con marca de tiempo.
## Un flash de 0,3 s pasa entre dos tool calls; esto lo ve porque mira cada frame.
## Idea de watch_* de lib/sight.gd de Autopilot (ramenvr/autopilot, Apache 2.0).

const MAX_EVENTS := 200
const MOVED_3D := 0.01
const MOVED_2D := 1.0
const TURNED_DEG := 1.0
const RESIZED := 0.05

## {node, properties, from, visible, animation, moved, turned, resized, values}
var _entries: Array[Dictionary] = []
var _events: Array[String] = []
var _dropped := 0
var _started := 0


## `nodes`: los nodos a mirar. `properties`: nombres de propiedad que también se miran en cada uno.
func start(nodes: Array[Node], properties: PackedStringArray) -> void:
	_started = Time.get_ticks_msec()
	for node: Node in nodes:
		var entry := {"node": node, "visible": _visible(node), "animation": _animations(node), "from": _transform(node), "values": {}}
		for property: String in properties:
			if property.get_slice(":", 0) in node:
				entry.values[property] = node.get_indexed(NodePath(property))
		_entries.append(entry)


func tick() -> void:
	for entry: Dictionary in _entries:
		var node: Node = entry.node
		if not is_instance_valid(node):
			if not entry.has("gone"):
				entry.gone = true
				_event(entry, "was freed")
			continue
		_check_transform(entry, node)
		var shown := _visible(node)
		if shown != entry.visible:
			entry.visible = shown
			_event(entry, "was shown" if shown else "was hidden")
		var playing := _animations(node)
		for name: String in playing:
			if not name in entry.animation:
				_event(entry, "started animation %s" % name)
		for name: String in entry.animation:
			if not name in playing:
				_event(entry, "ended animation %s" % name)
		entry.animation = playing
		for property: String in entry.values:
			var value: Variant = node.get_indexed(NodePath(property))
			if value != entry.values[property]:
				_event(entry, "%s: %s → %s" % [property, entry.values[property], value])
				entry.values[property] = value


func report() -> String:
	var lines: PackedStringArray = []
	for entry: Dictionary in _entries:
		if is_instance_valid(entry.node) and entry.has("moved"):
			lines.append("%s moved from %s to %s" % [entry.path, entry.from[0], _transform(entry.node)[0]])
	if _events.is_empty():
		return "Nothing changed in %d s of watching %d nodes." % [roundi((Time.get_ticks_msec() - _started) / 1000.0), _entries.size()]
	var text := PackedStringArray(_events)
	if _dropped > 0:
		text.append("(… %d more changes)" % _dropped)
	text.append_array(lines)
	return "\n".join(text)


func _check_transform(entry: Dictionary, node: Node) -> void:
	var now := _transform(node)
	var from: Array = entry.from
	if now.is_empty() or from.is_empty():
		return
	var threshold := MOVED_3D if node is Node3D else MOVED_2D
	if not entry.has("moved") and (now[0] - from[0]).length() > threshold:
		entry.moved = true
		entry.path = str(node.get_path())
		_event(entry, "started moving")
	if not entry.has("turned") and rad_to_deg(absf(now[1] - from[1])) > TURNED_DEG:
		entry.turned = true
		_event(entry, "turned")
	if not entry.has("resized") and (now[2] - from[2]).abs().length() > RESIZED * maxf(from[2].length(), 0.001):
		entry.resized = true
		_event(entry, "changed size")


func _event(entry: Dictionary, what: String) -> void:
	if _events.size() >= MAX_EVENTS:
		_dropped += 1
		return
	if not entry.has("path"):
		entry.path = str(entry.node.get_path()) if is_instance_valid(entry.node) else "(freed)"
	_events.append("t=%.2f %s %s" % [(Time.get_ticks_msec() - _started) / 1000.0, entry.path, what])


## [posición, ángulo, escala], o [] si el nodo no tiene transform.
static func _transform(node: Node) -> Array:
	if node is Node3D:
		var node_3d := node as Node3D
		return [node_3d.global_position, node_3d.global_rotation.y, node_3d.scale]
	if node is Node2D:
		var node_2d := node as Node2D
		return [node_2d.global_position, node_2d.global_rotation, node_2d.scale]
	if node is Control:
		var control := node as Control
		return [control.global_position, control.rotation, control.scale]
	return []


static func _visible(node: Node) -> bool:
	return (node as CanvasItem).is_visible_in_tree() if node is CanvasItem else (node as Node3D).is_visible_in_tree() if node is Node3D else true


## Animaciones que están corriendo en el nodo o en sus AnimationPlayer y sprites hijos.
static func _animations(node: Node) -> PackedStringArray:
	var names: PackedStringArray = []
	var candidates: Array[Node] = [node]
	candidates.append_array(node.find_children("*", "AnimationPlayer", true, false))
	candidates.append_array(node.find_children("*", "AnimatedSprite2D", true, false))
	candidates.append_array(node.find_children("*", "AnimatedSprite3D", true, false))
	for candidate: Node in candidates:
		if candidate is AnimationPlayer and (candidate as AnimationPlayer).is_playing():
			names.append(str((candidate as AnimationPlayer).current_animation))
		elif candidate is AnimatedSprite2D and (candidate as AnimatedSprite2D).is_playing():
			names.append(str((candidate as AnimatedSprite2D).animation))
		elif candidate is AnimatedSprite3D and (candidate as AnimatedSprite3D).is_playing():
			names.append(str((candidate as AnimatedSprite3D).animation))
	return names
