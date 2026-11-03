@tool
extends RefCounted
## El lado del plugin del supervisor del editor (m19-03): marca que el editor arrancó y que se cerró
## sin crash, convierte un reinicio del editor en un pedido al supervisor (si no, el editor nuevo no
## sería su hijo y quedaría sin supervisión), lanza el supervisor y lee lo que pasó mientras el
## editor estaba caído para contárselo al agente.

const State := preload("supervisor_state.gd")

const SUPERVISOR_SCRIPT := "res://addons/godot_agent/supervisor/editor_supervisor.gd"
const RESTART_GUARD := "res://addons/godot_agent/supervisor/restart_guard.gd"
const RESTART_GUARD_NAME := "GodotAgentRestartGuard"


## true después de lanzar un supervisor desde un editor sin supervisión: al cerrarse, este editor no
## se relanza solo (lo abre el supervisor).
static var handoff := false


static func is_supervised() -> bool:
	var dir := State.supervised_dir()
	return not dir.is_empty() and State.supervisor_running(dir)


static func state_dir() -> String:
	return State.state_dir(ProjectSettings.globalize_path("res://"))


## Al entrar el plugin: las extensiones de este editor cargaron bien.
static func mark_ready() -> void:
	var dir := State.supervised_dir()
	if not dir.is_empty():
		State.write_json(dir, State.READY, {"pid": OS.get_process_id(), "time": Time.get_datetime_string_from_system()})


## Al salir el plugin (cierre o reinicio del editor, o deshabilitar el plugin). En un handoff, el
## supervisor nuevo espera esta marca para abrir su editor.
static func mark_closed() -> void:
	var dir := state_dir() if handoff else State.supervised_dir()
	if not dir.is_empty():
		State.write_json(dir, State.CLOSED, {"pid": OS.get_process_id(), "time": Time.get_datetime_string_from_system()})


## Cuelga de la raíz el nodo que convierte un reinicio del editor en un pedido al supervisor
## (restart_guard.gd). Solo hace falta bajo el supervisor o en un handoff.
static func install_restart_guard(tree: SceneTree) -> void:
	if tree == null or tree.root.has_node(NodePath(RESTART_GUARD_NAME)):
		return
	var guard: Node = load(RESTART_GUARD).new()
	guard.name = RESTART_GUARD_NAME
	tree.root.add_child.call_deferred(guard)


## Deja un evento para el próximo arranque (lo usa restart_editor sin supervisor).
static func add_local_event(event: Dictionary) -> void:
	var dir := state_dir()
	event["time"] = Time.get_datetime_string_from_system()
	var pending := State.read_json(dir, State.EVENT)
	var events: Array = pending.get("events", [])
	events.append(event)
	State.write_json(dir, State.EVENT, {"events": events})


## Los eventos pendientes; el archivo queda archivado como event-<fecha>.json.
static func take_events() -> Array:
	var dir := state_dir()
	var events: Array = State.read_json(dir, State.EVENT).get("events", [])
	if FileAccess.file_exists(dir.path_join(State.EVENT)):
		var stamp := Time.get_datetime_string_from_system().replace(":", "-")
		DirAccess.rename_absolute(dir.path_join(State.EVENT), dir.path_join("event-%s.json" % stamp))
	return events


## Lanza el supervisor, que espera a que este editor se cierre y abre uno bajo su vigilancia.
## Devuelve "" o el error.
static func launch_supervisor() -> String:
	var project := ProjectSettings.globalize_path("res://")
	var dir := State.state_dir(project)
	DirAccess.make_dir_recursive_absolute(dir)
	if State.supervisor_running(dir):
		return "A supervisor is already running for this project."
	var args := PackedStringArray([
		"--headless", "--path", dir, "--script", ProjectSettings.globalize_path(SUPERVISOR_SCRIPT), "--",
		"--project", project.left(-1) if project.ends_with("/") else project, "--wait-pid", str(OS.get_process_id()),
	])
	var forwarded := editor_flags()
	if not forwarded.is_empty():
		args.append_array(["--editor-args", ",".join(forwarded)])
	var pid := OS.create_process(OS.get_executable_path(), args)
	return "" if pid > 0 else "Could not launch the supervisor."


## Los drivers que usa este editor, para que el supervisor lo relance igual: OS.get_cmdline_args no
## trae los argumentos que consume el motor (--rendering-driver, --display-driver…), así que salen
## de lo que está en uso.
static func editor_flags() -> PackedStringArray:
	var result: PackedStringArray = []
	var rendering := RenderingServer.get_current_rendering_driver_name()
	if not rendering.is_empty():
		result.append_array(["--rendering-driver", rendering])
	var display := DisplayServer.get_name().to_lower()
	if display in ["x11", "wayland", "windows", "macos"]:
		result.append_array(["--display-driver", display])
	var audio := AudioServer.get_driver_name()
	if not audio.is_empty():
		result.append_array(["--audio-driver", audio])
	return result


## El comando para abrir el editor bajo el supervisor desde una terminal.
static func command_line() -> String:
	var project := ProjectSettings.globalize_path("res://")
	project = project.left(-1) if project.ends_with("/") else project
	return "\"%s\" --headless --path \"%s\" --script \"%s\" -- --project \"%s\"" % [OS.get_executable_path(), State.state_dir(project), ProjectSettings.globalize_path(SUPERVISOR_SCRIPT), project]


## Lo que se le cuenta al agente de un evento (en inglés: lo lee el agente).
static func agent_message(event: Dictionary) -> String:
	var lines: PackedStringArray = []
	var backtrace: Array = event.get("backtrace", [])
	match str(event.get("kind", "")):
		State.EVENT_RESTART:
			lines.append("The editor restarted (%s) and loaded the libraries that are on disk now." % str(event.get("reason", "restart_editor")))
		State.EVENT_STARTUP_CRASH, State.EVENT_GAVE_UP:
			if event.kind == State.EVENT_GAVE_UP:
				lines.append("The editor crashed %d times in a few minutes, so the supervisor stopped reopening it; the user reopened it by hand." % int(event.get("crashes", 0)))
			else:
				lines.append("The editor crashed while starting, most likely in a GDExtension build, and the supervisor reopened it.")
			var restored: Array = event.get("restored", [])
			var disabled: Array = event.get("disabled", [])
			if not restored.is_empty():
				lines.append("It put back the last build the editor started with: %s. The build that crashed is next to each one as *.crashed." % ", ".join(PackedStringArray(restored)))
			if not disabled.is_empty():
				lines.append("It disabled %s (renamed to *.disabled): it had no build that ever started fine. Rename it back after fixing it." % ", ".join(PackedStringArray(disabled)))
			if restored.is_empty() and disabled.is_empty():
				lines.append("No GDExtension library had changed since the last good start, so nothing was rolled back.")
		_:
			lines.append("The editor crashed while running and the supervisor reopened it. No library was rolled back: if a GDExtension caused it, fix it and test with test_extension before restarting.")
	if not backtrace.is_empty():
		lines.append("Backtrace:")
		for line: Variant in backtrace:
			lines.append(str(line))
	return "\n".join(lines)
