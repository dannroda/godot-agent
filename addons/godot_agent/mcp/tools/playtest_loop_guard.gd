@tool
extends RefCounted
## m11-49: corta un playtest cuando el agente entra en loop. Cada llamada a una tool del juego deja
## una huella: la tool con sus argumentos y lo que devolvió (el texto del probe sin el tiempo restante
## ni la marca de errores, y los bytes de la captura). «Sin progreso» es que las últimas llamadas son
## el mismo ciclo de 1 a MAX_PERIOD llamadas repetido, con el mismo resultado cada vez: mismas teclas
## que dejan el mismo estado, la misma captura, el mismo error. Con WARN_REPEATS vueltas el resultado
## de la tool se lo dice al agente; con CUT_REPEATS el harness corta el playtest como «could not test».
## Que el resultado cambie (el juego avanzó, una animación) ya cuenta como progreso: prefiere no cortar
## a cortar de más.

const MAX_PERIOD := 3
const WARN_REPEATS := 3
const CUT_REPEATS := 4
## Lo que cambia solo entre llamadas iguales: los sobres de texto no confiable llevan un nonce nuevo
## en cada resultado y el probe pone el reloj del juego (que avance no es progreso).
const VOLATILE_PATTERN := "</?untrusted nonce=\"[^\"]*\">|\\[game time [^\\]]*\\]"
## Líneas del resultado que cambian solas entre llamadas iguales.
const VOLATILE_PREFIXES: Array[String] = ["Playtest time left:", "The playtest's time is up", "get_errors mark:"]
const EVIDENCE_TEXT_MAX := 200

## Huellas de las llamadas del playtest en curso: [{call, outcome, tool, args, result}].
var _history: Array[Dictionary] = []


func reset() -> void:
	_history.clear()


## Anota una llamada y devuelve {repeats, period, cut, evidence, tools}: `repeats` es cuántas vueltas seguidas
## lleva el ciclo más corto que se repite (1 si ninguno), `cut` si llegó a CUT_REPEATS.
func observe(tool_name: String, args: Dictionary, result: Dictionary) -> Dictionary:
	_history.append({"call": tool_name + " " + JSON.stringify(args, "", true), "outcome": outcome_hash(result),
		"tool": tool_name, "args": args, "result": result_text(result)})
	if _history.size() > MAX_PERIOD * CUT_REPEATS:
		_history.pop_front()
	var best := {"repeats": 1, "period": 0, "cut": false, "evidence": PackedStringArray(), "tools": ""}
	for period in range(1, MAX_PERIOD + 1):
		var repeats := _repeats(period)
		if repeats > int(best.repeats):
			best = {"repeats": repeats, "period": period, "cut": repeats >= CUT_REPEATS, "evidence": _evidence(period, repeats), "tools": _cycle_tools(period)}
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
