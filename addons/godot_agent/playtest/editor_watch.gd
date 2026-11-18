extends RefCounted
## Lado del editor del watchdog del juego (m2-07 de pruebas-windows; ver runtime/editor_watchdog.gd):
## escucha en un puerto de 127.0.0.1 y lo deja en el entorno, que heredan el juego del editor y las
## instancias extra. Acepta las conexiones y las tiene abiertas mientras viva; al morir el editor el
## sistema las cierra y cada juego se termina. Arranca con el primer juego que lanza el harness, no
## antes. Al deshabilitar el plugin se para y los juegos del harness que sigan abiertos terminan.

const EditorWatchdog := preload("runtime/editor_watchdog.gd")
const POLL_MS := 500

var _server: TCPServer
var _peers: Array[StreamPeerTCP] = []
var _next_poll_ms: int = 0


## Idempotente. false si no pudo escuchar: el juego corre igual, sin watchdog.
func start() -> bool:
	if _server:
		return true
	var server := TCPServer.new()
	if server.listen(0, "127.0.0.1") != OK:
		return false
	_server = server
	OS.set_environment(EditorWatchdog.ENV, str(server.get_local_port()))
	(Engine.get_main_loop() as SceneTree).process_frame.connect(_poll)
	return true


func stop() -> void:
	if _server == null:
		return
	var tree := Engine.get_main_loop() as SceneTree
	if tree.process_frame.is_connected(_poll):
		tree.process_frame.disconnect(_poll)
	if OS.get_environment(EditorWatchdog.ENV) == str(_server.get_local_port()):
		OS.unset_environment(EditorWatchdog.ENV)
	for peer: StreamPeerTCP in _peers:
		peer.disconnect_from_host()
	_peers.clear()
	_server.stop()
	_server = null


func port() -> int:
	return _server.get_local_port() if _server else 0


## Toma las conexiones nuevas y suelta las de los juegos que terminaron.
func _poll() -> void:
	var now := Time.get_ticks_msec()
	if now < _next_poll_ms:
		return
	_next_poll_ms = now + POLL_MS
	while _server.is_connection_available():
		_peers.append(_server.take_connection())
	_peers.assign(_peers.filter(func(peer: StreamPeerTCP) -> bool:
		peer.poll()
		return peer.get_status() == StreamPeerTCP.STATUS_CONNECTED))
