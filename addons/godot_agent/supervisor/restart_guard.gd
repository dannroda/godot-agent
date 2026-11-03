@tool
extends Node
## Convierte un reinicio del editor en un pedido al supervisor (m19-03). Godot descarga los plugins
## (_exit_editor) antes de marcar el reinicio (set_restart_on_exit), así que el plugin no lo ve al
## salir. Este nodo cuelga de la raíz del árbol y sale recién cuando el árbol se finaliza, después de
## la marca y antes de que Godot relance: ahí la cancela y le pide al supervisor que abra el editor,
## para que el nuevo sea su hijo y siga supervisado.

const State := preload("supervisor_state.gd")
const SupervisorClient := preload("supervisor_client.gd")
const NODE_NAME := "GodotAgentRestartGuard"


func _exit_tree() -> void:
	if not OS.is_restart_on_exit_set():
		return
	if SupervisorClient.handoff:
		# Lo abre el supervisor que se acaba de lanzar.
		OS.set_restart_on_exit(false)
		return
	var dir := State.supervised_dir()
	if dir.is_empty() or not State.supervisor_running(dir):
		return
	OS.set_restart_on_exit(false)
	State.write_json(dir, State.RESTART, {"pid": OS.get_process_id(), "reason": "editor restart"})
