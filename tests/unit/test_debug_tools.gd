extends "test_case.gd"
## m11-56: breakpoints del agente aparte de los del usuario, la pila del juego parado (DebugStack) y
## que una sesión que se cierra no deja el juego parado por sus breakpoints ni por sus pasos.

const DebugTools := preload("res://addons/godot_agent/mcp/tools/debug_tools.gd")
const DebugStack := preload("res://addons/godot_agent/playtest/runtime/debug_stack.gd")
const RunTools := preload("res://addons/godot_agent/mcp/tools/run_tools.gd")

const SCRIPT := "res://tests/unit/test_debug_tools.gd"

## Lo que ve el snapshot como miembro de este frame.
var marker: String = "hola"


## Sin editor: registra lo que se le pide al juego.
class FakeDebugger extends RefCounted:
	var probe := false
	var breaked := false
	## [path, line, enabled] o [session, path, line]
	var sent: Array = []
	var commands: PackedStringArray = []

	func has_probe() -> bool:
		return probe

	func is_breaked() -> bool:
		return breaked

	func set_breakpoint(path: String, line: int, enabled: bool) -> void:
		sent.append([path, line, enabled])

	func set_session_breakpoint(session_id: int, path: String, line: int) -> void:
		sent.append([session_id, path, line])

	func debug_command(command: String) -> bool:
		if not breaked:
			return false
		commands.append(command)
		breaked = false
		return true


func _tools(debugger: FakeDebugger, user: PackedStringArray = []) -> DebugTools:
	var tools := DebugTools.new()
	tools.run_tools = RunTools.new()
	tools.debugger = debugger
	tools.user_breakpoints = func() -> PackedStringArray: return user
	return tools


func _as(tools: DebugTools, who: String) -> void:
	tools.caller = func() -> String: return who


func _text(result: Dictionary) -> String:
	return str(result.content[0].text) if result.has("content") else str(result)


func test_breakpoints_are_per_session_and_spare_the_users() -> void:
	var debugger := FakeDebugger.new()
	var tools := _tools(debugger, PackedStringArray(["%s:20" % SCRIPT]))
	_as(tools, "")
	var result := tools._breakpoint({"action": "set", "file": SCRIPT, "line": 10})
	assert_false(result.get("isError", false), "pone uno · " + _text(result))
	assert_true(_text(result).contains("when it starts"), "sin juego: llega al arrancar · " + _text(result))
	assert_eq(debugger.sent, [[SCRIPT, 10, true]], "se manda a las sesiones activas")
	_as(tools, "s2")
	tools._breakpoint({"action": "set", "file": SCRIPT, "line": 20})
	tools._breakpoint({"action": "set", "file": SCRIPT, "line": 30})
	var listed := _text(tools._breakpoint({"action": "list"}))
	assert_true(listed.contains("Your breakpoints: %s:20, %s:30" % [SCRIPT, SCRIPT]) and listed.contains("The user's") and not listed.contains(":10"), "la lista: los suyos y los del usuario · " + listed)
	var other := tools._breakpoint({"action": "clear", "file": SCRIPT, "line": 10})
	assert_true(other.get("isError", false) and _text(other).contains("no breakpoint of yours"), "no saca el de otra sesión · " + _text(other))
	debugger.sent.clear()
	tools._breakpoint({"action": "clear", "file": SCRIPT, "line": 20})
	assert_eq(debugger.sent, [], "el usuario tiene uno en la misma línea: en el juego sigue")
	var users := tools._breakpoint({"action": "clear", "file": SCRIPT, "line": 20})
	assert_true(users.get("isError", false) and _text(users).contains("the user's"), "el del usuario no se saca · " + _text(users))
	assert_true(_text(tools._breakpoint({"action": "clear_all"})).begins_with("Cleared 1 breakpoint."), "clear_all saca solo los suyos")
	assert_eq(debugger.sent, [[SCRIPT, 30, false]], "y lo apaga en el juego")
	assert_eq(tools.breakpoints.keys(), ["%s:10" % SCRIPT], "queda el de la otra sesión")
	for bad: Dictionary in [{"file": "res://nada.gd", "line": 1}, {"file": "user://a.gd", "line": 1}, {"file": SCRIPT, "line": 0}, {"file": SCRIPT, "line": 100000}]:
		bad["action"] = "set"
		assert_true(tools._breakpoint(bad).get("isError", false), "rechaza %s" % [bad])


func test_new_game_gets_the_agent_breakpoints() -> void:
	var debugger := FakeDebugger.new()
	var tools := _tools(debugger)
	tools.breakpoints = {"%s:10" % SCRIPT: "", "%s:12" % SCRIPT: "s2"}
	tools._on_session_started(3)
	assert_eq(debugger.sent, [[3, SCRIPT, 10], [3, SCRIPT, 12]], "los manda a la sesión que arrancó")


func test_not_stopped() -> void:
	var debugger := FakeDebugger.new()
	var tools := _tools(debugger)
	var result: Dictionary = await tools._stack({})
	assert_true(result.get("isError", false) and _text(result) == RunTools.NO_PROBE, "sin probe · " + _text(result))
	debugger.probe = true
	result = await tools._debug({"action": "continue"})
	assert_true(result.get("isError", false) and _text(result).begins_with("The game is not stopped in the debugger (state: game: "), "corriendo · " + _text(result))
	assert_eq(debugger.commands, PackedStringArray(), "no manda nada")


func test_closed_session_releases_the_game() -> void:
	var debugger := FakeDebugger.new()
	var tools := _tools(debugger)
	tools.breakpoints = {"%s:10" % SCRIPT: "s2", "%s:12" % SCRIPT: ""}
	debugger.breaked = true
	debugger.probe = true
	tools.break_reason = func() -> String: return "Breakpoint (0 - %s:12 - at function: f)" % SCRIPT
	assert_eq(await tools.release_session("s2"), PackedStringArray(["%s:10" % SCRIPT]), "saca los de la sesión que se cerró")
	assert_eq(debugger.commands, PackedStringArray(), "el juego está parado en uno de otra sesión: sigue parado")
	assert_eq(await tools.release_session(""), PackedStringArray(["%s:12" % SCRIPT]), "la principal")
	assert_eq(debugger.commands, PackedStringArray(["continue"]), "parado en uno suyo: sigue")
	debugger.breaked = true
	tools._stepped_by = "s3"
	tools._has_stepper = true
	tools.break_reason = func() -> String: return "Breakpoint (0 - res://otro.gd:5 - at function: g)"
	assert_eq(await tools.release_session("s3"), PackedStringArray(), "sin breakpoints")
	assert_eq(debugger.commands, PackedStringArray(["continue", "continue"]), "parado por un paso suyo: sigue")
	debugger.breaked = true
	await tools.release_session("s3")
	assert_eq(debugger.commands.size(), 2, "una pausa del usuario o de un error no se toca")


func test_stopped_at_any() -> void:
	var keys := PackedStringArray(["res://player.gd:12"])
	assert_true(DebugTools.stopped_at_any("Breakpoint (0 - res://player.gd:12 - at function: _process)", keys), "formato del panel de pila")
	assert_true(DebugTools.stopped_at_any("Breakpoint (res://player.gd:12 in _process)", keys), "otro formato")
	assert_false(DebugTools.stopped_at_any("Breakpoint (0 - res://player.gd:120 - at function: _process)", keys), "otra línea")
	assert_false(DebugTools.stopped_at_any("", keys), "sin motivo")


func test_stack_snapshot() -> void:
	var text: String = _outer(7)
	var lines := text.split("\n")
	assert_true(lines[0].begins_with("Stack (") and lines[0].ends_with("#0 is where it stopped):"), "cabecera · " + lines[0])
	assert_true(lines[1].begins_with("#0 %s:" % SCRIPT) and lines[1].ends_with(" in _inner()"), "#0 es la que pidió, sin frames del addon · " + lines[1])
	assert_true(lines[2].begins_with("#1 %s:" % SCRIPT) and lines[2].ends_with(" in _outer()"), "#1 la que la llamó · " + lines[2])
	assert_true(text.contains("Frame #1, _outer() at %s:" % SCRIPT), "las variables del frame pedido · " + text)
	assert_true(text.contains("  marker = \"hola\""), "los miembros · " + text)
	var bare: Dictionary = DebugStack.snapshot({"variables": false})
	assert_false(str(bare.get("text", "")).contains("Members"), "solo la pila")
	var missing: Dictionary = DebugStack.snapshot({"frame": 999})
	assert_true(str(missing.get("text", "")).contains("There is no frame #999"), "frame fuera de rango")
	var all: Dictionary = DebugStack.snapshot({}, "res://")
	assert_eq(str(all.get("error", "")), "No game frames on the stack.", "todo filtrado")


func _outer(depth: int) -> String:
	return _inner(depth + 1)


func _inner(_depth: int) -> String:
	return str(DebugStack.snapshot({"frame": 1}).get("text", ""))


func test_describe() -> void:
	assert_eq(DebugStack.describe("a\"b\n"), "\"a\\\"b\\n\"", "texto escapado")
	assert_eq(DebugStack.describe(3), "3", "número")
	assert_eq(DebugStack.describe([1, 2]), "Array(2) [1, 2]", "array")
	assert_eq(DebugStack.describe(range(20)), "Array(20) [0, 1, 2, 3, 4, 5, 6, 7, …]", "array largo")
	assert_eq(DebugStack.describe({"a": 1}), "Dictionary(1) {\"a\": 1}", "diccionario")
	assert_eq(DebugStack.describe(PackedInt32Array([4, 5])), "PackedInt32Array(2) [4, 5]", "packed")
	assert_eq(DebugStack.describe("x".repeat(500)).length(), DebugStack.MAX_VALUE + 1, "acotado")
	var node := Node.new()
	assert_true(DebugStack.describe(node).begins_with("Node#"), "nodo fuera del árbol")
	node.free()
	assert_eq(DebugStack.describe(node), "<Freed Object>", "liberado")
	assert_eq(DebugStack.describe(null), "<null>", "null")
	assert_eq(DebugStack.describe(load(SCRIPT)), "GDScript " + SCRIPT, "recurso con su ruta")


## Revisión de next2 #4: un array que se contiene a sí mismo desbordaba la pila dentro del bucle del
## debugger, y datos anidados que reusan arrays tardaban segundos (7 niveles × 8 items: 5,9 s).
func test_describe_cycles_and_nesting_are_bounded() -> void:
	var loop: Array = [1]
	loop.append(loop)
	assert_eq(DebugStack.describe(loop), "Array(2) [1, Array(2) [1, Array(2)]]", "un ciclo se corta a MAX_DEPTH niveles")
	var own := {}
	own["self"] = own
	assert_eq(DebugStack.describe(own), "Dictionary(1) {\"self\": Dictionary(1) {\"self\": Dictionary(1)}}", "un diccionario que se contiene")
	var nested: Array = [0, 1, 2, 3, 4, 5, 6, 7]
	for level in 7:
		var wider: Array = []
		for i in 8:
			wider.append(nested)
		nested = wider
	var started := Time.get_ticks_msec()
	var text := DebugStack.describe(nested)
	assert_true(Time.get_ticks_msec() - started < 100, "7 niveles × 8 items en menos de 0,1 s (%d ms)" % (Time.get_ticks_msec() - started))
	assert_true(text.length() <= DebugStack.MAX_VALUE + 1, "acotado")
	loop.clear()  # corta el ciclo para que se libere
	own.clear()
