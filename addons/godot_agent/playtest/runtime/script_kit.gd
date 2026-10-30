extends RefCounted
## El `game` que recibe un game_script (m15-12): las manos del jugador y lecturas, dentro del juego.
## Como corre en el proceso del juego, reacciona en el mismo frame: no hace falta compensar latencia
## como kit/control.py de Autopilot, del que sale la idea de devolver {ok, why, data} con diagnóstico,
## porque eso separa «el juego falla» de «no supe hacerlo».

const GameWorld := preload("game_world.gd")

const TAP_FRAMES := 6
const TURN_GAIN := 0.8
## Grados que se prueba girar para medir cuánto mueve la vista el mouse.
const PROBE_COUNTS := 40.0
const NOT_TURNING := "the mouse doesn't turn the view: a menu or a cutscene holding it, or a game that only turns with the mouse captured (mouse_mode is %s)?"


## Se queda con los errores de script mientras corre: los de compilación no llegan de otra forma.
class ScriptErrors:
	extends Logger
	var lock := Mutex.new()
	var lines: PackedStringArray = []
	var fatal := false

	func _log_error(function: String, file: String, line: int, code: String, rationale: String, _editor_notify: bool, error_type: int, _script_backtraces: Array) -> void:
		if error_type != ERROR_TYPE_SCRIPT:
			return
		# El game_script no tiene archivo: sus errores cortan la corrida; los del juego solo se cuentan.
		var own := not file.ends_with(".gd")
		lock.lock()
		lines.append("Script error%s: %s" % [" at line %d" % line if own else " (%s:%d in %s)" % [file, line, function], rationale if not rationale.is_empty() else code])
		fatal = fatal or own
		lock.unlock()

	func _log_message(_message: String, _error: bool) -> void:
		pass


## Nunca se emite: un await acá deja colgado para siempre a un script vencido.
signal _never

var aborted := false
var lines: PackedStringArray = []

var _host: Node
var _held: Dictionary = {}
var _degrees_per_count := Vector2.ZERO


func _init(host: Node) -> void:
	_host = host


# --- resultados -------------------------------------------------------------------------------------

func ok(why: String = "", data: Dictionary = {}) -> Dictionary:
	return {"ok": true, "why": why, "data": data}


func fail(why: String, data: Dictionary = {}) -> Dictionary:
	return {"ok": false, "why": why, "data": data}


## Lo que vuelve al agente, además del valor que devuelve run().
func say(...values: Array) -> void:
	var parts: PackedStringArray = []
	for value: Variant in values:
		parts.append(str(value))
	lines.append("t=%.2f %s" % [Time.get_ticks_msec() / 1000.0, " ".join(parts)])


# --- leer -------------------------------------------------------------------------------------------

func tree() -> SceneTree:
	return _host.get_tree()


## Nodo por ruta (como en game_get) o null.
func node(path: String = "") -> Node:
	var found: Variant = _host.call(&"_node", path)
	return found if found is Node else null


func player() -> Node:
	return GameWorld.player(tree())


## Velocidad, salto, gravedad y altura de un salto del jugador, leídos del juego.
func movement() -> Dictionary:
	return GameWorld.movement(tree())


# --- las manos del jugador ----------------------------------------------------------------------------

## Aprieta y suelta una acción del InputMap o una tecla. Con await.
func press(name: String, frames: int = TAP_FRAMES) -> Dictionary:
	var result := hold(name)
	if not result.ok:
		return result
	await wait_frames(frames)
	release(name)
	await wait_frames(1)
	return ok("pressed %s" % name)


## Deja apretado hasta release() o hasta que termine el script.
func hold(name: String, strength: float = 1.0) -> Dictionary:
	var event := _event(name, true, strength)
	if event == null:
		return fail("'%s' is neither an InputMap action nor a key." % name)
	Input.parse_input_event(event)
	_held[name] = true
	return ok("holding %s" % name)


func release(name: String) -> void:
	var event := _event(name, false, 0.0)
	if event:
		Input.parse_input_event(event)
	_held.erase(name)


func release_all() -> void:
	for name: String in _held.keys():
		release(name)


## Movimiento relativo del mouse, como la mira de un juego en primera persona.
func mouse(dx: float, dy: float) -> void:
	var motion := InputEventMouseMotion.new()
	motion.relative = Vector2(dx, dy)
	motion.screen_relative = motion.relative
	motion.position = _host.get_viewport().get_mouse_position()
	motion.global_position = motion.position
	Input.parse_input_event(motion)


func _event(name: String, pressed: bool, strength: float) -> InputEvent:
	if InputMap.has_action(name):
		var action := InputEventAction.new()
		action.action = name
		action.pressed = pressed
		action.strength = strength
		return action
	var keycode := OS.find_keycode_from_string(name)
	if keycode == KEY_NONE:
		return null
	var key := InputEventKey.new()
	key.keycode = keycode
	key.physical_keycode = keycode
	key.pressed = pressed
	return key


# --- esperar ------------------------------------------------------------------------------------------

## Frames de física (emiten también en pausa, pero el juego no avanza).
func wait_frames(count: int) -> void:
	for _frame in maxi(count, 0):
		await tree().physics_frame
		await _check()


## Segundos reales, también con el juego en pausa.
func wait(seconds: float) -> void:
	await tree().create_timer(seconds, true, false, true).timeout
	await _check()


## Espera a que `condition` (un Callable) dé true.
func until(condition: Callable, timeout: float = 5.0) -> Dictionary:
	var deadline := Time.get_ticks_msec() + int(timeout * 1000.0)
	while Time.get_ticks_msec() < deadline:
		if condition.call():
			return ok("condition met")
		await tree().process_frame
		await _check()
	return fail("timed out after %.1f s" % timeout)


## Un script al que se le venció el tiempo se queda acá para siempre: no sigue tocando el juego.
func _check() -> void:
	if aborted:
		await _never


# --- apuntar ------------------------------------------------------------------------------------------

## Gira la vista con el mouse hasta apuntar a un Node3D o Vector3 (3D). Mide cuánto gira cada
## movimiento: no asume la sensibilidad del juego.
func look_at(target: Variant, tolerance: float = 2.5, timeout: float = 1.5) -> Dictionary:
	var camera := _host.get_viewport().get_camera_3d()
	if camera == null:
		return fail("there is no Camera3D: look_at is for 3D games")
	if _degrees_per_count == Vector2.ZERO:
		var measured: Dictionary = await _measure_look(camera)
		if not measured.ok:
			return measured
	var deadline := Time.get_ticks_msec() + int(timeout * 1000.0)
	while true:
		var error := _aim_error(camera, target)
		if absf(error.x) <= tolerance and absf(error.y) <= tolerance:
			return ok("on target", {"error": error})
		if Time.get_ticks_msec() > deadline:
			return fail("didn't get there: the view stayed %.1f° right and %.1f° up off the target (a pitch limit, or too close?)" % [error.x, error.y], {"error": error})
		mouse(error.x * TURN_GAIN / _degrees_per_count.x, -error.y * TURN_GAIN / _degrees_per_count.y)
		await wait_frames(1)
	return fail("unreachable")


func _measure_look(camera: Camera3D) -> Dictionary:
	var before := _view(camera)
	mouse(PROBE_COUNTS, PROBE_COUNTS)
	await wait_frames(3)
	var turned := _view(camera) - before
	if absf(turned.x) < 0.05:
		return fail(NOT_TURNING % Input.mouse_mode)
	_degrees_per_count = Vector2(turned.x / PROBE_COUNTS, -turned.y / PROBE_COUNTS)
	if absf(_degrees_per_count.y) < 0.0001:
		_degrees_per_count.y = _degrees_per_count.x  # la cabeza contra su límite: como en el otro eje
	mouse(-PROBE_COUNTS, -PROBE_COUNTS)
	await wait_frames(3)
	return ok()


## (derecha, arriba) en grados, como los ve el jugador.
static func _view(camera: Camera3D) -> Vector2:
	var forward := -camera.global_basis.z
	return Vector2(rad_to_deg(atan2(forward.x, -forward.z)), rad_to_deg(asin(clampf(forward.y, -1.0, 1.0))))


static func _aim_error(camera: Camera3D, target: Variant) -> Vector2:
	var point: Vector3 = (target as Node3D).global_position if target is Node3D else target
	var local := camera.global_basis.inverse() * (point - camera.global_position)
	return Vector2(rad_to_deg(atan2(local.x, -local.z)), rad_to_deg(atan2(local.y, Vector2(local.x, local.z).length())))
