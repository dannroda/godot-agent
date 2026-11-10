extends RefCounted
## game_monitors (m11-43): los monitores de Performance del juego en marcha, muestreados cada frame
## durante una ventana, y los nodos huérfanos (creados y nunca agregados al árbol, o sacados sin
## liberar). profile_run solo ve GDScript: un juego lento por draw calls o física, o que pierde nodos,
## aparece acá. Corre dentro del juego (lo usa la probe): sin código de editor.
## Ideas de performance_audit (flopperam/unreal-engine-mcp), el toolset Perf del MCP de Unreal y
## manage_profiler de MCP for Unity.

## Huérfanos que se listan (el resto se cuenta).
const ORPHAN_LIST := 20
const MB := 1024.0 * 1024.0

## Monitores que se resumen con promedio y máximo: [nombre, monitor].
const LOAD: Array = [
	["draw calls", Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME],
	["objects drawn", Performance.RENDER_TOTAL_OBJECTS_IN_FRAME],
	["primitives", Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME],
	["2D physics bodies awake", Performance.PHYSICS_2D_ACTIVE_OBJECTS],
	["2D collision pairs", Performance.PHYSICS_2D_COLLISION_PAIRS],
	["3D physics bodies awake", Performance.PHYSICS_3D_ACTIVE_OBJECTS],
	["3D collision pairs", Performance.PHYSICS_3D_COLLISION_PAIRS],
]
## Monitores que se resumen con el primero, el último y la diferencia (una fuga crece): [nombre, monitor, en MB].
const COUNTS: Array = [
	["nodes", Performance.OBJECT_NODE_COUNT, false],
	["orphan nodes", Performance.OBJECT_ORPHAN_NODE_COUNT, false],
	["objects", Performance.OBJECT_COUNT, false],
	["resources", Performance.OBJECT_RESOURCE_COUNT, false],
	["static memory", Performance.MEMORY_STATIC, true],
	["video memory", Performance.RENDER_VIDEO_MEM_USED, true],
]

var _started_usec := 0
var _last_usec := 0
## Duración de cada frame (ms), medida entre frames: el FPS de Performance es un promedio por segundo.
var _frame_ms: PackedFloat64Array = []
## TIME_PROCESS y TIME_PHYSICS_PROCESS (ms): Godot los actualiza una vez por segundo con el máximo de ese segundo.
var _process_ms: PackedFloat64Array = []
var _physics_ms: PackedFloat64Array = []
## nombre → PackedFloat64Array con un valor por frame.
var _load: Dictionary = {}
var _first: Dictionary = {}
var _last: Dictionary = {}


func start() -> void:
	_started_usec = Time.get_ticks_usec()
	_last_usec = _started_usec
	_frame_ms.clear()
	_process_ms.clear()
	_physics_ms.clear()
	_load.clear()
	for row: Array in LOAD:
		_load[row[0]] = PackedFloat64Array()
	for row: Array in COUNTS:
		_first[row[0]] = Performance.get_monitor(row[1])
	_last = _first.duplicate()


func is_running() -> bool:
	return _started_usec > 0


## Una muestra; se llama una vez por frame.
func tick() -> void:
	var now := Time.get_ticks_usec()
	_frame_ms.append((now - _last_usec) / 1000.0)
	_last_usec = now
	_process_ms.append(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
	_physics_ms.append(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0)
	for row: Array in LOAD:
		(_load[row[0]] as PackedFloat64Array).append(Performance.get_monitor(row[1]))
	for row: Array in COUNTS:
		_last[row[0]] = Performance.get_monitor(row[1])


func frames() -> int:
	return _frame_ms.size()


## El resumen para el agente, en inglés. `orphans`: listar los nodos huérfanos de ahora.
func report(orphans: bool = true) -> String:
	if _frame_ms.is_empty():
		return "No frames were sampled (the game was paused or ended)."
	var seconds := (_last_usec - _started_usec) / 1000000.0
	var lines: PackedStringArray = []
	var frame := stats(_frame_ms)
	lines.append("Sampled %d frames over %.2f s." % [_frame_ms.size(), seconds])
	lines.append("Frame time: avg %.1f ms, p95 %.1f ms, max %.1f ms (%.0f fps on average)." % [frame.avg, frame.p95, frame.max, _frame_ms.size() / seconds if seconds > 0.0 else 0.0])
	# Godot actualiza estos dos una vez por segundo con el frame más lento de ese segundo: el promedio no
	# dice nada, el máximo sí.
	lines.append("Slowest frame of each second, as the engine measures it: process up to %.2f ms, physics up to %.2f ms." % [stats(_process_ms).max, stats(_physics_ms).max])
	var load: PackedStringArray = []
	for row: Array in LOAD:
		var values: PackedFloat64Array = _load[row[0]]
		var row_stats := stats(values)
		if row_stats.max > 0.0:
			load.append("%s avg %s, max %s" % [row[0], _number(row_stats.avg), _number(row_stats.max)])
	if not load.is_empty():
		lines.append("Per frame: " + " · ".join(load) + ".")
	var counts: PackedStringArray = []
	for row: Array in COUNTS:
		var first := float(_first.get(row[0], 0.0))
		var last := float(_last.get(row[0], 0.0))
		if row[2] and last == 0.0:
			continue  # sin render (headless) no hay memoria de video
		counts.append(_change(row[0], first, last, row[2]))
	lines.append("Start → end: " + " · ".join(counts) + ".")
	if orphans:
		lines.append(orphan_text())
	return "\n".join(lines)


## Los nodos huérfanos de ahora: clase, nombre y script, los primeros ORPHAN_LIST. Godot solo los
## lleva en builds de debug (como los del editor).
static func orphan_text() -> String:
	var ids: Array = Node.get_orphan_node_ids()
	if ids.is_empty():
		return "Orphan nodes now: none."
	var lines: PackedStringArray = ["Orphan nodes now (%d; created and never added to the tree, or removed without free()):" % ids.size()]
	var by_kind := {}
	for id: int in ids:
		var node := instance_from_id(id) as Node
		if node == null:
			continue
		var script := node.get_script() as Script
		var kind := "%s (%s%s)" % [node.name, node.get_class(), ", " + script.resource_path if script and not script.resource_path.is_empty() else ""]
		by_kind[kind] = int(by_kind.get(kind, 0)) + 1
	var kinds := by_kind.keys()
	kinds.sort_custom(func(a: String, b: String) -> bool: return by_kind[a] > by_kind[b])
	for i in mini(kinds.size(), ORPHAN_LIST):
		lines.append("- %s%s" % [kinds[i], " ×%d" % by_kind[kinds[i]] if by_kind[kinds[i]] > 1 else ""])
	if kinds.size() > ORPHAN_LIST:
		lines.append("- … and %d more kinds" % (kinds.size() - ORPHAN_LIST))
	return "\n".join(lines)


## {avg, p95, max, min} de una lista de valores.
static func stats(values: PackedFloat64Array) -> Dictionary:
	if values.is_empty():
		return {"avg": 0.0, "p95": 0.0, "max": 0.0, "min": 0.0}
	var sorted := values.duplicate()
	sorted.sort()
	var total := 0.0
	for value: float in values:
		total += value
	var p95_index := clampi(ceili(sorted.size() * 0.95) - 1, 0, sorted.size() - 1)
	return {"avg": total / values.size(), "p95": sorted[p95_index], "max": sorted[-1], "min": sorted[0]}


static func _change(label: String, first: float, last: float, megabytes: bool) -> String:
	if megabytes:
		var delta_mb := (last - first) / MB
		return "%s %.1f → %.1f MB%s" % [label, first / MB, last / MB, " (%+.1f)" % delta_mb if absf(delta_mb) >= 0.05 else ""]
	var delta := roundi(last - first)
	return "%s %d → %d%s" % [label, roundi(first), roundi(last), " (%+d)" % delta if delta != 0 else ""]


static func _number(value: float) -> String:
	return str(roundi(value)) if value >= 10.0 or is_equal_approx(value, roundf(value)) else "%.1f" % value
