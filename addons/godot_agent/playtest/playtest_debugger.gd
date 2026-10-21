@tool
extends EditorDebuggerPlugin
## Lado editor del canal del debugger con el probe de playtest (prefijo `godot_agent:`).
## Mensajes del juego → señales; `send()` le habla a la sesión donde el probe dijo `ready`.

signal session_started
signal session_stopped
signal session_breaked
signal probe_ready
signal frame_received(png: PackedByteArray, width: int, height: int)
signal inputs_done(count: int)
signal problem_reported(text: String)

const PREFIX := "godot_agent"

var _probe_session: int = -1


func _has_capture(capture: String) -> bool:
	return capture == PREFIX


func _capture(message: String, data: Array, session_id: int) -> bool:
	match message.trim_prefix(PREFIX + ":"):
		"ready":
			_probe_session = session_id
			probe_ready.emit()
		"frame":
			if data.size() >= 3 and data[0] is PackedByteArray:
				frame_received.emit(data[0], int(data[1]), int(data[2]))
		"inputs_done":
			inputs_done.emit(int(data[0]) if not data.is_empty() else 0)
		"problem":
			problem_reported.emit(str(data[0]) if not data.is_empty() else "")
		_:
			return false
	return true


func _setup_session(session_id: int) -> void:
	var session := get_session(session_id)
	session.started.connect(_on_started)
	session.stopped.connect(_on_stopped.bind(session_id))
	session.breaked.connect(_on_breaked)


## Si hay un probe conectado y su sesión sigue activa.
func has_probe() -> bool:
	if _probe_session < 0:
		return false
	var session := get_session(_probe_session)
	return session != null and session.is_active()


func send(message: String, data: Array = []) -> bool:
	if not has_probe():
		return false
	get_session(_probe_session).send_message(PREFIX + ":" + message, data)
	return true


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


func _on_started() -> void:
	session_started.emit()


func _on_stopped(session_id: int) -> void:
	if session_id == _probe_session:
		_probe_session = -1
	session_stopped.emit()


func _on_breaked(_can_debug: bool) -> void:
	session_breaked.emit()
