extends RefCounted
## Detectores dentro del juego (m15-07): lo que el agente no está mirando cuando pasa. NaN en
## transforms, cuerpos fuera del mundo, caídas sin fin, frames largos y un HUD con más que su máximo.
## Basado en lib/detectors.gd de Autopilot (ramenvr/autopilot, Apache 2.0). Sin su Logger: los errores
## los junta el ErrorCollector del editor.

const GameWorld := preload("game_world.gd")
const GameUi := preload("game_ui.gd")

const LONG_FALL_S := 8.0
const HITCH_S := 0.75
const SCAN_EVERY_S := 0.5
const HUD_EVERY_S := 0.25
const OUT_OF_WORLD_MARGIN := 50.0
## Al cargar una escena hay frames largos que no dicen nada.
const LOADING_S := 3.0
const SCAN_MAX_NODES := 5000

## firma → veces vista. Se avisa en la 1, 10, 100 y 1000: un bug por frame no tapa todo lo demás.
var counts: Dictionary = {}

var _fraction := RegEx.create_from_string("(?<![\\d/])(\\d+)\\s*/\\s*(\\d+)(?![\\d/])")
var _digits := RegEx.create_from_string("[0-9]+")
var _falling := 0.0
var _hud_at := 0.0
var _scan_at := 0.0
var _kill_y: Variant = null
var _scene: Node = null
var _scene_at := 0
var _flagged: Dictionary = {}


## Mira este frame. `emit`: Callable(finding). `real_dt`: lo que tardó el frame en tiempo real.
func tick(host: Node, emit: Callable, real_dt: float) -> void:
	var tree := host.get_tree()
	var scene := tree.current_scene
	if scene != _scene:
		_scene = scene
		_scene_at = Time.get_ticks_msec()
		_kill_y = null
		_flagged.clear()
		_falling = 0.0
	var loading := Time.get_ticks_msec() - _scene_at < int(LOADING_S * 1000.0)
	# Movie Maker escribe cada frame a disco: ahí un frame largo no es del juego.
	if not tree.paused and not loading and real_dt > HITCH_S and not OS.has_feature("movie"):
		_report(emit, {"detector": "hitch", "severity": "warning", "summary": "A frame took %.2f s." % real_dt, "signature": "hitch"})
	_check_fall(tree, emit, real_dt)
	var now := Time.get_ticks_msec() / 1000.0
	if now - _hud_at >= HUD_EVERY_S:
		_hud_at = now
		_check_hud(host, emit)
	if now - _scan_at >= SCAN_EVERY_S and scene != null and not loading:
		_scan_at = now
		_scan(scene, emit)


func _check_fall(tree: SceneTree, emit: Callable, real_dt: float) -> void:
	if tree.paused:
		return
	var body := GameWorld.player(tree)
	if not (body is CharacterBody3D or body is CharacterBody2D):
		return
	var falling: bool = not body.is_on_floor() and (body.velocity.y < 0.0 if body is CharacterBody3D else body.velocity.y > 0.0)
	_falling = _falling + real_dt * Engine.time_scale if falling else 0.0
	if _falling > LONG_FALL_S:
		_falling = -1e9  # una vez por caída
		_report(emit, {"detector": "long_fall", "severity": "error", "summary": "%s kept falling for %d s." % [body.name, int(LONG_FALL_S)],
			"signature": "long_fall:%s" % body.name, "node": str(body.name), "where": _where(body)})


func _check_hud(host: Node, emit: Callable) -> void:
	var texts := GameUi.new(host).texts()
	for key: String in texts:
		for found: RegExMatch in _fraction.search_all(texts[key]):
			var value := int(found.get_string(1))
			var limit := int(found.get_string(2))
			if limit > 0 and value > limit:
				_report(emit, {"detector": "hud_fraction", "severity": "error", "summary": "The text %s shows %d/%d: more than its maximum." % [key, value, limit],
					"signature": "hud_fraction:%s" % key, "node": key.get_slice(".", 1)})


## Transforms con NaN y cuerpos debajo del nivel (el punto dibujado más bajo al empezar, menos un margen).
func _scan(scene: Node, emit: Callable) -> void:
	if _kill_y == null and scene is Node3D:
		var lowest := INF
		for visual: Node in scene.find_children("*", "GeometryInstance3D", true, false):
			var instance := visual as GeometryInstance3D
			lowest = minf(lowest, (instance.global_transform * instance.get_aabb()).position.y)
		_kill_y = (lowest if lowest != INF else 0.0) - OUT_OF_WORLD_MARGIN
	var checked := 0
	var stack: Array[Node] = [scene]
	while not stack.is_empty() and checked < SCAN_MAX_NODES:
		var node: Node = stack.pop_back()
		stack.append_array(node.get_children())
		if node is Node3D:
			checked += 1
			var position_3d: Vector3 = node.global_position
			if not (position_3d.is_finite() and (node as Node3D).global_basis.is_finite()):
				_flag_nan(node, emit)
			elif _kill_y != null and node is PhysicsBody3D and position_3d.y < _kill_y and not _flagged.has(node):
				_flagged[node] = true
				_report(emit, {"detector": "out_of_world", "severity": "error", "summary": "%s fell out of the world (below %.0f)." % [node.name, _kill_y],
					"signature": "out_of_world:%s" % node.name, "node": str(node.name), "where": _where(node)})
		elif node is Node2D:
			checked += 1
			if not (node as Node2D).global_position.is_finite():
				_flag_nan(node, emit)


func _flag_nan(node: Node, emit: Callable) -> void:
	if not _flagged.has(node):
		_flagged[node] = true
		_report(emit, {"detector": "nan", "severity": "error", "summary": "%s has a NaN or infinite transform." % node.name, "signature": "nan:%s" % node.name, "node": str(node.name)})


func _report(emit: Callable, finding: Dictionary) -> void:
	var signature := _digits.sub(str(finding.signature), "#", true).left(160)
	var count: int = counts.get(signature, 0) + 1
	counts[signature] = count
	if count in [1, 10, 100, 1000]:
		finding.signature = signature
		finding.count = count
		var scene_file := _scene.scene_file_path if _scene else ""
		finding.scene = scene_file
		emit.call(finding)


static func _where(node: Node) -> Array:
	if node is Node3D:
		var at: Vector3 = node.global_position
		return [at.x, at.y, at.z]
	if node is Node2D:
		var at: Vector2 = node.global_position
		return [at.x, at.y]
	return []
