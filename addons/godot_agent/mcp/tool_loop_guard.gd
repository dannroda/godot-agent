@tool
extends RefCounted
## Detector de loops de las tools godot.* (m11-49, generalizado en m11-79). Cada llamada deja una
## huella: la tool con sus argumentos y lo que devolvió (el texto sin los sobres con nonce, el reloj
## del juego, el tiempo restante ni la marca de errores, y los bytes de las imágenes). «Sin progreso»
## es que las últimas llamadas son el mismo ciclo de 1 a `max_period` llamadas repetido, con el mismo
## resultado cada vez: la misma lectura que da lo mismo, el mismo error, A → B → A → B. Que el
## resultado cambie ya cuenta como progreso: prefiere no avisar a avisar de más.
## No cuenta por rondas: del lado del server no se ve dónde empieza cada respuesta del modelo.

## Lo que cambia solo entre llamadas iguales: los sobres de texto no confiable llevan un nonce nuevo
## en cada resultado y el probe pone el reloj del juego (que avance no es progreso).
const VOLATILE_PATTERN := "</?untrusted nonce=\"[^\"]*\">|\\[game time [^\\]]*\\]"
## Líneas del resultado que cambian solas entre llamadas iguales.
const VOLATILE_PREFIXES: Array[String] = ["Playtest time left:", "The playtest's time is up", "get_errors mark:"]
const EVIDENCE_TEXT_MAX := 200

## El ciclo más largo que se busca (en llamadas).
var max_period: int = 3
## Con cuántas vueltas `observe` marca `cut` (0: nunca).
var cut_repeats: int = 0
## Cuántas vueltas del ciclo más largo se guardan.
var keep_repeats: int = 4

## Huellas de las llamadas recientes: [{call, outcome, tool, args, result}].
var _history: Array[Dictionary] = []


func reset() -> void:
	_history.clear()


## Anota una llamada y devuelve {repeats, period, cut, evidence, tools}: `repeats` es cuántas vueltas seguidas
## lleva el ciclo más corto que se repite (1 si ninguno), `cut` si llegó a `cut_repeats`.
func observe(tool_name: String, args: Dictionary, result: Dictionary) -> Dictionary:
	_history.append({"call": tool_name + " " + JSON.stringify(args, "", true), "outcome": outcome_hash(result),
		"tool": tool_name, "args": args, "result": result_text(result)})
	if _history.size() > max_period * keep_repeats:
		_history.pop_front()
	var best := {"repeats": 1, "period": 0, "cut": false, "evidence": PackedStringArray(), "tools": ""}
	for period in range(1, max_period + 1):
		var repeats := _repeats(period)
		if repeats > int(best.repeats):
			best = {"repeats": repeats, "period": period, "cut": cut_repeats > 0 and repeats >= cut_repeats,
				"evidence": _evidence(period, repeats), "tools": _cycle_tools(period)}
	return best


## Vueltas seguidas del ciclo de largo `period` al final del historial (con su resultado).
func _repeats(period: int) -> int:
	var n := _history.size()
	if n < period * 2:
		return 1
	var same := 0
	while same + period < n:
		var a: Dictionary = _history[n - 1 - same]
		var b: Dictionary = _history[n - 1 - same - period]
		if a.call != b.call or a.outcome != b.outcome:
			break
		same += 1
	return 1 + same / period


## Las tools del ciclo, en orden («game_input → capture_game_frame»).
func _cycle_tools(period: int) -> String:
	var names: PackedStringArray = []
	for entry: Dictionary in _history.slice(_history.size() - period):
		names.append(entry.tool)
	return " → ".join(names)


func _evidence(period: int, repeats: int) -> PackedStringArray:
	var lines: PackedStringArray = []
	for entry: Dictionary in _history.slice(_history.size() - period):
		var args := JSON.stringify(entry.args)
		lines.append("%s %s ×%d" % [entry.tool, args.left(EVIDENCE_TEXT_MAX) if args != "{}" else "", repeats])
		var text := str(entry.result).strip_edges()
		if not text.is_empty():
			lines.append("  → " + text.replace("\n", " ").left(EVIDENCE_TEXT_MAX))
	return lines


## El texto de un resultado MCP sin las líneas que cambian solas.
static func result_text(result: Dictionary) -> String:
	var kept: PackedStringArray = []
	for block: Variant in result.get("content", []):
		if block is Dictionary and block.get("type") == "text":
			for line: String in str(block.get("text", "")).split("\n"):
				if not VOLATILE_PREFIXES.any(func(prefix: String) -> bool: return line.begins_with(prefix)):
					kept.append(line)
	return RegEx.create_from_string(VOLATILE_PATTERN).sub("\n".join(kept), "", true).strip_edges()


static func outcome_hash(result: Dictionary) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(("error:" if result.get("isError", false) else "ok:").to_utf8_buffer())
	ctx.update(result_text(result).to_utf8_buffer())
	for block: Variant in result.get("content", []):
		if block is Dictionary and block.get("type") == "image":
			ctx.update(str(block.get("data", "")).to_utf8_buffer())
	return ctx.finish().hex_encode()
