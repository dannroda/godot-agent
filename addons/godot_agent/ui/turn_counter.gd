@tool
extends Node
## El contador vivo de los cambios del turno (m11-34): mientras el agente trabaja, arriba del
## composer «3 files · +42 −7»; un clic abre los cambios hasta ahora (solo para ver: el agente sigue
## escribiendo). Se recalcula con TurnSnapshots.peek() después de cada tool call terminada, a lo sumo
## cada THROTTLE_S, y se borra cuando termina el turno (el aviso de fin de turno toma su lugar).
##
## No toca SessionController: el principio del turno es el último snapshot de la sesión tomado
## después de que pasó a PROMPTING (lo toma el controller al arrancar un turno de Construir o Auto).

const SessionModel := preload("../session/session_model.gd")
const TurnSnapshots := preload("../session/turn_snapshots.gd")

const THROTTLE_S := 2.0

## `(session) -> TurnSnapshots`, `(session) -> SessionModel`, `(session) -> AgentDock` (con
## set_turn_changes()), y `(data: Dictionary) -> void` para abrir el diálogo.
var snapshots_of: Callable
var model_of: Callable
var dock_of: Callable
var open_dialog: Callable
## El reloj del intervalo entre cálculos (para las pruebas).
var now_ms: Callable = func() -> int: return Time.get_ticks_msec()

## sesión -> cuándo pasó a PROMPTING (ms de Time, el mismo reloj de TurnSnapshots.latest_take()).
var _turn_since: Dictionary = {}
## sesión -> cuándo se calculó por última vez (ms).
var _last_run: Dictionary = {}
## sesión -> hay que recalcular.
var _pending: Dictionary = {}
var _running: Dictionary = {}
## sesión -> {start, tree, files, added, removed} de lo último que se calculó.
var _latest: Dictionary = {}


func _ready() -> void:
	set_process(false)


## Una sesión cambió de estado (state_changed de su modelo).
func on_state(session: String, state: int) -> void:
	if state == SessionModel.SessionState.PROMPTING:
		if not _turn_since.has(session):
			_turn_since[session] = Time.get_ticks_msec()
	else:
		clear(session)


## Algo pasó en el turno (una tool call terminó): hay que recalcular, a su debido tiempo.
func note_activity(session: String) -> void:
	if not _turn_since.has(session):
		return
	_pending[session] = true
	set_process(true)


func clear(session: String) -> void:
	_turn_since.erase(session)
	_pending.erase(session)
	_latest.erase(session)
	var dock: Object = dock_of.call(session) if dock_of.is_valid() else null
	if dock:
		dock.set_turn_changes({})


func _process(_delta: float) -> void:
	if _pending.is_empty():
		set_process(false)
		return
	for session: String in _pending.keys():
		if _running.has(session):
			continue
		if now_ms.call() - int(_last_run.get(session, -100000)) < int(THROTTLE_S * 1000.0):
			continue
		_pending.erase(session)
		refresh(session)


## Recalcula ya lo que cambió la sesión en este turno.
func refresh(session: String) -> void:
	if not _turn_since.has(session):
		return
	var snapshots: TurnSnapshots = snapshots_of.call(session)
	if snapshots == null or not snapshots.available:
		return
	var start := snapshots.latest_take(session, int(_turn_since[session]))
	if start.is_empty():
		return  # Preguntar o Revisar: sin snapshot del turno
	_running[session] = true
	_last_run[session] = now_ms.call()
	var peeked: Dictionary = await snapshots.peek(session, start)
	_running.erase(session)
	if peeked.is_empty() or not _turn_since.has(session):
		return
	var summary := {"start": start, "tree": str(peeked.get("tree", "")), "files": peeked.files, "added": peeked.added, "removed": peeked.removed}
	_latest[session] = summary
	var dock: Object = dock_of.call(session) if dock_of.is_valid() else null
	if dock:
		dock.set_turn_changes(summary)


## Lo último que se calculó para la sesión ({} si nada).
func latest(session: String) -> Dictionary:
	return _latest.get(session, {})


## El clic en el contador: los cambios hasta ahora, para ver.
func open(session: String) -> void:
	var summary: Dictionary = _latest.get(session, {})
	if summary.is_empty() or not open_dialog.is_valid():
		return
	open_dialog.call({"session": session, "start": summary.start, "end": summary.tree, "files": summary.files, "live": true})
