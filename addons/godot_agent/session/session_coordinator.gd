@tool
extends RefCounted
## Coordina las sesiones del agente abiertas a la vez en el editor (m7-44) para que no se pisen:
## qué archivos está editando cada una en su turno y cuál tiene el juego.
##
## - Un archivo que una sesión escribe en su turno queda suyo hasta que el turno termina; si otra
##   quiere escribirlo mientras tanto, se le rechaza con el nombre de la que lo tiene.
## - El juego es de la sesión que lo lanzó hasta que se detiene; otra que quiera correrlo espera
##   en cola (hasta un tope) y no puede tocar el juego ajeno con las tools game_*.

signal changed

## Espera máxima en la cola del juego antes de rechazar.
const GAME_WAIT_S := 90.0
const POLL_S := 0.25

## id de sesión (no vacío) -> nombre visible ("Sesión 2"…), en el orden en que se abrieron.
var _labels: Dictionary = {}
## ruta normalizada -> id de la sesión que la está editando.
var _claims: Dictionary = {}
var _game_owner: String = ""
## Si el juego sigue corriendo; lo reemplazan las pruebas.
var is_game_running: Callable = func() -> bool: return EditorInterface.is_playing_scene()


func register(session: String, label: String) -> void:
	_labels[session] = label
	changed.emit()


func unregister(session: String) -> void:
	_labels.erase(session)
	release_files(session)
	if _game_owner == session:
		_game_owner = ""
	changed.emit()


func sessions() -> PackedStringArray:
	return PackedStringArray(_labels.keys())


func label(session: String) -> String:
	return str(_labels.get(session, session))


## true con más de una sesión abierta: con una sola no hay nada que coordinar.
func is_shared() -> bool:
	return _labels.size() > 1


## Rutas de `paths` que otra sesión está editando: ruta -> id de esa sesión. Las demás quedan de
## `session` hasta que termine su turno; si alguna es ajena, no se toma ninguna.
func claim_files(session: String, paths: PackedStringArray) -> Dictionary:
	var taken: Dictionary = {}
	for path: String in paths:
		var key := normalize(path)
		var owner := str(_claims.get(key, ""))
		if not owner.is_empty() and owner != session and _labels.has(owner):
			taken[path] = owner
	if not taken.is_empty() or not _labels.has(session):
		return taken
	var added := false
	for path: String in paths:
		var key := normalize(path)
		if not key.is_empty() and _claims.get(key) != session:
			_claims[key] = session
			added = true
	if added:
		changed.emit()
	return taken


## Archivos que tiene `session`, como rutas normalizadas.
func files_of(session: String) -> PackedStringArray:
	var result: PackedStringArray = []
	for key: String in _claims:
		if _claims[key] == session:
			result.append(key)
	result.sort()
	return result


func release_files(session: String) -> void:
	var released := false
	for key: String in _claims.keys():
		if _claims[key] == session:
			_claims.erase(key)
			released = true
	if released:
		changed.emit()


## Id de la sesión que tiene el juego corriendo, o "".
func game_owner() -> String:
	if not _game_owner.is_empty() and not is_game_running.call():
		_game_owner = ""
		changed.emit()
	return _game_owner


## Espera a que el juego quede libre (o sea de `session`) y lo toma. Devuelve "" si lo tomó o el
## id de la sesión que lo sigue teniendo al vencer `timeout_s`.
func acquire_game(session: String, timeout_s: float = GAME_WAIT_S) -> String:
	var deadline := Time.get_ticks_msec() + int(timeout_s * 1000.0)
	while true:
		var owner := game_owner()
		if owner.is_empty() or owner == session or not _labels.has(owner):
			_game_owner = session
			changed.emit()
			return ""
		if Time.get_ticks_msec() >= deadline:
			return owner
		await Engine.get_main_loop().create_timer(POLL_S).timeout
	return ""


func release_game(session: String) -> void:
	if _game_owner == session:
		_game_owner = ""
		changed.emit()


## Rutas res:// en los argumentos de una tool (los de primer nivel y los de listas, como `paths`).
static func paths_in_args(args: Dictionary) -> PackedStringArray:
	var result: PackedStringArray = []
	for key: Variant in args:
		var values: Array = args[key] if args[key] is Array else [args[key]]
		for value: Variant in values:
			if value is String and str(value).begins_with("res://") and not str(value) in result:
				result.append(str(value))
	return result


## Clave de una ruta: res:// y absolutas del proyecto valen lo mismo.
static func normalize(path: String) -> String:
	if path.is_empty():
		return ""
	if path.begins_with("res://"):
		return ProjectSettings.globalize_path(path).simplify_path()
	return path.simplify_path()
