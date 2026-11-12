@tool
extends RefCounted
## Qué sesión del debugger es cada instancia extra de run_scene (m11-50). PlaytestDebugger lo usa; está
## aparte porque un EditorDebuggerPlugin solo existe dentro del editor (los tests no lo pueden crear).

## sesión → número (2..N), desde que la sesión arranca.
var by_session: Dictionary = {}
## número → sesión, desde que su probe dijo ready.
var probes: Dictionary = {}
## La próxima sesión que arranque es esta instancia (el harness las lanza de a una). 0 = ninguna.
var expecting: int = 0


## Una sesión arrancó: su número si era la instancia esperada, o 0 si es el juego del editor.
func started(session_id: int) -> int:
	if expecting > 0:
		by_session[session_id] = expecting
		expecting = 0
		return int(by_session[session_id])
	by_session.erase(session_id)  # una sesión reusada por el juego del editor
	return 0


## El probe de una sesión dijo ready: su número, o 0 si es el juego del editor.
func ready(session_id: int) -> int:
	if not by_session.has(session_id):
		return 0
	probes[int(by_session[session_id])] = session_id
	return int(by_session[session_id])


## Una sesión terminó: su número (y sale del mapa), o 0 si es el juego del editor.
func stopped(session_id: int) -> int:
	if not by_session.has(session_id):
		return 0
	var number := int(by_session[session_id])
	by_session.erase(session_id)
	probes.erase(number)
	return number


func number_of(session_id: int) -> int:
	return int(by_session.get(session_id, 0))


func session_of(number: int) -> int:
	for session_id: int in by_session:
		if int(by_session[session_id]) == number:
			return session_id
	return -1


func probe_of(number: int) -> int:
	return int(probes.get(number, -1))
