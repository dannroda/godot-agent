@tool
extends EditorDebuggerPlugin
## Lado editor del canal del debugger con el probe de playtest (prefijo `godot_agent:`).
## Mensajes del juego → señales; `send()` le habla a la sesión donde el probe dijo `ready`.

signal session_started
## Lo mismo con el id de la sesión que arrancó (godot.profile_run: el profiler va en esa, no en otra).
signal session_started_id(session_id: int)
signal session_stopped
## Lo mismo con el id de la sesión que terminó (DebugTools lleva las sesiones que lanzó el harness).
signal session_stopped_id(session_id: int)
signal session_breaked
## El juego salió de una pausa del debugger (continue o step del agente, del usuario o del harness).
signal session_continued
signal probe_ready
signal frame_received(png: PackedByteArray, width: int, height: int)
signal inputs_done(count: int)
signal problem_reported(text: String)
signal reply_received(id: int, result: Dictionary)
signal finding_received(finding: Dictionary)
signal finding_frame_received(signature: String, png: PackedByteArray)
signal film_frame_received(number: int, game_time: float, jpeg: PackedByteArray)
## Las instancias extra de run_scene (m11-50): `event` es started, ready, stopped, breaked o continued.
## Las señales sin número (session_started, probe_ready…) son solo de la instancia 1, la del editor.
signal instance_event(instance: int, event: String)

const PREFIX := "godot_agent"
const InstanceSessions := preload("instance_sessions.gd")

var _probe_session: int = -1
## Las instancias extra de run_scene y sus sesiones (m11-50).
var instances := InstanceSessions.new()
## A qué instancia van send(), has_probe(), is_breaked() y resume(): 1 es la del editor.
## El PID del juego que lanzó el editor (lo dice su probe), o 0. De su línea de comandos sale adónde se
## conectan las instancias extra (GameInstances.editor_debugger_uri).
var editor_game_pid := 0
var target_instance: int = 1


func _has_capture(capture: String) -> bool:
	return capture == PREFIX


func _capture(message: String, data: Array, session_id: int) -> bool:
	match message.trim_prefix(PREFIX + ":"):
		"ready":
			var number := instances.ready(session_id)
			if number > 0:
				instance_event.emit(number, "ready")
			else:
				_probe_session = session_id
				editor_game_pid = int(data[2]) if data.size() >= 3 else 0
				probe_ready.emit()
		"frame":
			if data.size() >= 3 and data[0] is PackedByteArray:
				frame_received.emit(data[0], int(data[1]), int(data[2]))
		"inputs_done":
			inputs_done.emit(int(data[0]) if not data.is_empty() else 0)
		"problem":
			problem_reported.emit(str(data[0]) if not data.is_empty() else "")
		"reply":
			if data.size() >= 2 and data[1] is Dictionary:
				reply_received.emit(int(data[0]), data[1])
		"finding":
			if not data.is_empty() and data[0] is Dictionary:
				finding_received.emit(data[0])
		"finding_frame":
			if data.size() >= 2 and data[1] is PackedByteArray:
				finding_frame_received.emit(str(data[0]), data[1])
		"film_frame":
			if data.size() >= 3 and data[2] is PackedByteArray:
				film_frame_received.emit(int(data[0]), float(data[1]), data[2])
		_:
			return false
	return true


func _setup_session(session_id: int) -> void:
	var session := get_session(session_id)
	session.started.connect(_on_started.bind(session_id))
	session.stopped.connect(_on_stopped.bind(session_id))
	session.breaked.connect(_on_breaked.bind(session_id))
	session.continued.connect(_on_continued.bind(session_id))


## La próxima sesión que arranque es la instancia `instance` (m11-50): se llama justo antes de lanzarla.
func expect_instance(instance: int) -> void:
	instances.expecting = instance


## La sesión con el probe de la instancia `instance` (por defecto, target_instance), o -1.
func probe_session(instance: int = 0) -> int:
	var number := instance if instance > 0 else target_instance
	return _probe_session if number <= 1 else instances.probe_of(number)


## La sesión de la instancia extra `instance` desde que arrancó (aunque su probe no haya dicho ready), o -1.
func instance_session(instance: int) -> int:
	return instances.session_of(instance)


## La instancia de una sesión: 1 para la del editor (o una sin instancia conocida).
func instance_of(session_id: int) -> int:
	return maxi(1, instances.number_of(session_id))


## Si hay un probe conectado y su sesión sigue activa (en target_instance, o en `instance`).
func has_probe(instance: int = 0) -> bool:
	var session_id := probe_session(instance)
	if session_id < 0:
		return false
	var session := get_session(session_id)
	return session != null and session.is_active()


## Si el juego del probe está parado en el debugger (por un error o un breakpoint).
func is_breaked(instance: int = 0) -> bool:
	return has_probe(instance) and get_session(probe_session(instance)).is_breaked()


## `instance`: a cuál (por defecto, target_instance).
func send(message: String, data: Array = [], instance: int = 0) -> bool:
	if not has_probe(instance):
		return false
	get_session(probe_session(instance)).send_message(PREFIX + ":" + message, data)
	return true


## Un breakpoint en todas las sesiones activas (m11-56). `line` empieza en 1, como en el editor.
func set_breakpoint(path: String, line: int, enabled: bool) -> void:
	for session_id in get_sessions().size():
		var session := get_session(session_id)
		if session and session.is_active():
			session.set_breakpoint(path, line, enabled)


## Un breakpoint en una sesión (DebugTools: solo en las que lanzó el harness).
func set_session_breakpoint(session_id: int, path: String, line: int, enabled: bool = true) -> void:
	var session := get_session(session_id)
	if session and session.is_active():
		session.set_breakpoint(path, line, enabled)


## Hay algún juego corriendo (con el probe o sin él).
func has_game() -> bool:
	for session_id in get_sessions().size():
		var session := get_session(session_id)
		if session and session.is_active():
			return true
	return false


## La sesión parada en el debugger: la del probe si es ella; si no, la primera que lo esté (un juego
## sin probe, o parado antes de que el probe cargue, que es el último autoload). -1 = ninguna.
func breaked_session() -> int:
	if is_breaked():
		return _probe_session
	for session_id in get_sessions().size():
		var session := get_session(session_id)
		if session and session.is_active() and session.is_breaked():
			return session_id
	return -1


## Algún juego está parado en el debugger, tenga o no el probe (game_debug no lo necesita).
func any_breaked() -> bool:
	return breaked_session() >= 0


## continue, step, next u out al juego parado en el debugger (m11-56). Va al hilo principal: uno
## parado en otro hilo (Thread, WorkerThreadPool) solo se maneja desde el panel del Debugger.
func debug_command(command: String) -> bool:
	var session_id := breaked_session()
	if session_id < 0:
		return false
	get_session(session_id).send_message(command, [])
	return true


## Saca al juego de una pausa del debugger (m15-05).
func resume() -> void:
	if is_breaked():
		get_session(probe_session()).send_message("continue", [])


## Motivo y ubicación de la pausa del debugger ("Invalid call…", "res://a.gd:12 in _ready").
## El EditorDebuggerSession no los expone: se leen del panel Stack Trace del debugger.
static func break_reason() -> String:
	for node: Node in EditorInterface.get_base_control().find_children("*", "ScriptEditorDebugger", true, false):
		var tabs := node.find_children("*", "TabContainer", true, false)
		if tabs.is_empty() or (tabs[0] as TabContainer).get_tab_count() == 0:
			continue
		var stack_tab := (tabs[0] as TabContainer).get_tab_control(0)
		var stack := ""
		for tree_node: Node in stack_tab.find_children("*", "Tree", true, false):
			var root := (tree_node as Tree).get_root()
			if root and root.get_first_child():
				stack = root.get_first_child().get_text(0)
				break
		if stack.is_empty():
			continue
		var reason := ""
		for label_node: Node in stack_tab.find_children("*", "", true, false):
			if label_node is RichTextLabel:
				reason = (label_node as RichTextLabel).get_parsed_text()
			elif label_node is Label:
				reason = (label_node as Label).text
			if not reason.strip_edges().is_empty():
				break
		return "%s (%s)" % [reason.strip_edges(), stack.strip_edges()]
	return ""


func _on_started(session_id: int) -> void:
	var number := instances.started(session_id)
	if number > 0:
		instance_event.emit(number, "started")
		session_started_id.emit(session_id)
		return
	session_started.emit()
	session_started_id.emit(session_id)


func _on_stopped(session_id: int) -> void:
	var number := instances.stopped(session_id)
	if number > 0:
		instance_event.emit(number, "stopped")
		session_stopped_id.emit(session_id)
		return
	if session_id == _probe_session:
		_probe_session = -1
	session_stopped.emit()
	session_stopped_id.emit(session_id)


func _on_breaked(_can_debug: bool, session_id: int = -1) -> void:
	if instances.number_of(session_id) > 0:
		instance_event.emit(instances.number_of(session_id), "breaked")
		return
	session_breaked.emit()


func _on_continued(session_id: int = -1) -> void:
	if instances.number_of(session_id) > 0:
		instance_event.emit(instances.number_of(session_id), "continued")
		return
	session_continued.emit()
