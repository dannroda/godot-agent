extends RefCounted
## El juego del playtest termina si muere el editor que lo lanzó (m2-07 de pruebas-windows).
## El canal del debugger no se lo dice al juego: en Windows el juego quedaba huérfano, corriendo, y en
## Linux solo moría cuando se caía el X (xvfb-run). El PID del editor no alcanza: en Windows
## OS.is_process_running solo ve los procesos que lanzó el mismo proceso. Por eso el editor escucha
## en un puerto de 127.0.0.1 (playtest/editor_watch.gd) y lo pasa por el entorno; el juego se conecta
## y mira la conexión cada segundo. Si el editor muere, el sistema cierra el socket aunque el editor
## estuviera trabado, y el juego se mata con OS.kill, como el Stop del editor: así no pasa por el
## exit() de Xlib, que con un Logger registrado se colgaba en un futex (m16-24, m16-25).
## Solo vigila si la conexión llegó a abrirse: sin editor que escuche no hace nada.

const ENV := "GODOT_AGENT_EDITOR_WATCH"
const PERIOD_S := 1.0
## Con el editor vivo, en 127.0.0.1 conecta enseguida. En Windows un connect rechazado no pasa a
## STATUS_ERROR y se queda en STATUS_CONNECTING: pasado esto, deja de vigilar.
const CONNECT_TIMEOUT_MS := 5000

## Lo que pasa cuando se cae la conexión; los tests ponen otra cosa.
var on_editor_gone: Callable = func() -> void: OS.kill(OS.get_process_id())
var _peer: StreamPeerTCP
var _connected: bool = false
var _started_ms: int = 0
var _timer: Timer


## Se conecta al puerto del entorno y revisa cada PERIOD_S con un Timer interno de `host`. false si
## no hay puerto o no se pudo empezar la conexión.
func start(host: Node, port: int = int(OS.get_environment(ENV))) -> bool:
	if port <= 0 or port > 65535:
		return false
	_peer = StreamPeerTCP.new()
	if _peer.connect_to_host("127.0.0.1", port) != OK:
		_peer = null
		return false
	_started_ms = Time.get_ticks_msec()
	_timer = Timer.new()
	_timer.wait_time = PERIOD_S
	_timer.process_mode = Node.PROCESS_MODE_ALWAYS  # también con el juego en pausa
	_timer.ignore_time_scale = true
	_timer.autostart = true  # arranca al entrar al árbol, aunque `host` todavía no esté
	_timer.timeout.connect(check)
	# Interno: no aparece en el árbol que ven el agente ni el juego.
	host.add_child(_timer, false, Node.INTERNAL_MODE_BACK)
	return true


## Una revisión. Devuelve false si dejó de vigilar.
func check() -> bool:
	if _peer == null:
		return false
	_peer.poll()
	match _peer.get_status():
		StreamPeerTCP.STATUS_CONNECTED:
			_connected = true
			return true
		StreamPeerTCP.STATUS_CONNECTING:
			if Time.get_ticks_msec() - _started_ms < CONNECT_TIMEOUT_MS:
				return true
	var was_connected := _connected
	stop()
	if was_connected:
		on_editor_gone.call()
	return false


func stop() -> void:
	if _timer:
		_timer.queue_free()
		_timer = null
	if _peer:
		_peer.disconnect_from_host()
		_peer = null
	_connected = false
