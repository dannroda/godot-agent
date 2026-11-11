@tool
extends RefCounted
## Un run manual del juego (F5/F6, no run_scene) que para en el debugger por un error o termina con
## errores (m11-55): junta el motivo, los errores del juego desde que arrancó y la pila, y avisa una
## vez por run para que el dock ofrezca «Arreglar con el agente». Nada se manda solo: el prompt sale
## cuando el usuario aprieta el botón. Los runs del agente no avisan: el agente ya recibe sus errores
## en cada resultado de tool. Apagable en Ajustes (HarnessSettings.KEY_RUN_ERROR_FIX).

## `{breaked, reason, count, lines}`: si paró en el debugger, el motivo de la pausa, cuántos errores
## del juego hubo y las últimas líneas formateadas.
signal error_found(info: Dictionary)

const ErrorCollector := preload("error_collector.gd")
const I18n := preload("../core/i18n.gd")
const UntrustedText := preload("../mcp/untrusted_text.gd")
## Líneas de error que van al aviso y al prompt; el Agent Log tiene todas.
const MAX_LINES := 12
const ERROR_KINDS: PackedStringArray = ["error", "script", "shader"]

var errors: ErrorCollector
## Si el run en curso lo lanzó el harness (lo pone el plugin: RunTools.harness_run).
var launched_by_harness: Callable = func() -> bool: return false
## El motivo de la pausa del debugger (PlaytestDebugger.break_reason), leído un momento después.
var break_reason: Callable = func() -> String: return ""
## Si el juego sigue parado en el debugger cuando se lee el motivo (PlaytestDebugger.any_breaked).
var still_breaked: Callable = func() -> bool: return true
## El ajuste: avisar o no.
var enabled: Callable = func() -> bool: return true

var _mark: int = 0
var _running: bool = false
var _notified: bool = false
var _harness_run: bool = false


## La sesión de debug del juego arrancó: desde acá cuentan los errores.
func on_game_started() -> void:
	if errors:
		errors.collect()
		_mark = errors.mark()
	_running = true
	_notified = false
	_harness_run = bool(launched_by_harness.call())


## Motivo con el que el debugger para en un breakpoint o en la palabra `breakpoint`.
const BREAKPOINT_REASON := "Breakpoint"


## El debugger pausó el juego (por un error, normalmente). Se llama un momento después de la pausa:
## si el usuario ya la continuó o hizo un paso, el panel no dice el motivo y podía ser un breakpoint;
## los errores del run se avisan al terminar el juego (revisión de next2 #22).
func on_game_breaked() -> void:
	if not bool(still_breaked.call()):
		return
	_report(true)


## El juego terminó: si dejó errores y no se avisó todavía, se avisa ahora.
func on_game_stopped() -> void:
	_report(false)
	_running = false


func _report(breaked: bool) -> void:
	if not _running or _notified or _harness_run or not bool(enabled.call()):
		return
	var reason := str(break_reason.call()) if breaked else ""
	# Una pausa en un breakpoint (del usuario o del agente, m11-56) no es un error: si hubo errores,
	# se avisa al terminar el juego.
	if reason.begins_with(BREAKPOINT_REASON):
		return
	var found: Array[Dictionary] = []
	if errors:
		for entry: Dictionary in errors.entries_since(_mark):
			if str(entry.source) == "game" and str(entry.kind) in ERROR_KINDS and not ErrorCollector.is_engine_noise(entry):
				found.append(entry)
	if found.is_empty() and reason.is_empty():
		return
	_notified = true
	error_found.emit(summary(breaked, reason, found))


## `{breaked, reason, count, lines}` a partir de lo juntado.
static func summary(breaked: bool, reason: String, entries: Array[Dictionary]) -> Dictionary:
	var lines: PackedStringArray = []
	for entry: Dictionary in entries.slice(maxi(entries.size() - MAX_LINES, 0)):
		lines.append(ErrorCollector.format_entry(entry))
	return {"breaked": breaked, "reason": reason, "count": entries.size(), "lines": lines}


## El título del aviso, traducido.
static func notice_title(info: Dictionary) -> String:
	return I18n.t("The game stopped in the debugger with an error") if info.breaked else I18n.t("The game ended with errors")


## El cuerpo del aviso: el motivo de la pausa o el primer error; si hubo más, cuántos.
static func notice_text(info: Dictionary) -> String:
	var lines: PackedStringArray = info.lines
	var first := str(info.reason) if not str(info.reason).is_empty() else (_human_line(lines[0]) if not lines.is_empty() else "")
	if int(info.count) > 1:
		first += "\n" + I18n.t("%d errors in total; they are in the details.") % int(info.count)
	return first


## Los errores y la pila para el pliegue de detalles (monoespaciado, con «Copiar»).
static func notice_details(info: Dictionary) -> String:
	var parts: PackedStringArray = []
	if not str(info.reason).is_empty():
		parts.append(str(info.reason))
	parts.append_array(info.lines)
	return "\n".join(parts)


## El prompt para el agente (en inglés): qué pasó y qué hacer, con el motivo y los errores. Los
## mensajes los escribió el juego: van en sobres con nonce, como en los resultados de tools (m11-45).
static func prompt(info: Dictionary) -> String:
	var what := "stopped in the debugger with an error" if info.breaked else "ended with errors"
	var parts: PackedStringArray = ["The user ran the game from the editor by hand (not with godot.run_scene) and it %s. Find the cause and fix it; then run the scene with godot.run_scene to check that it works." % what]
	if not str(info.reason).is_empty():
		parts.append("Debugger: " + UntrustedText.wrap(str(info.reason)))
	var lines: PackedStringArray = info.lines
	if not lines.is_empty():
		parts.append("Errors since the game started (%d%s):" % [int(info.count), ", the last %d" % lines.size() if int(info.count) > lines.size() else ""])
		parts.append(UntrustedText.wrap("\n".join(lines)))
	return UntrustedText.seal("\n".join(parts), UntrustedText.new_nonce())


## «#3 [game/error] res://a.gd:12 — mensaje» → «mensaje (res://a.gd:12)».
static func _human_line(line: String) -> String:
	var dash := line.find(" — ")
	if dash < 0:
		return line
	var head := line.left(dash)
	var message := line.substr(dash + 3)
	var location := head.substr(head.find("]") + 1).strip_edges()
	return message if location.is_empty() else "%s (%s)" % [message, location]
