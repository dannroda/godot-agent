extends SceneTree
## Supervisor del editor (m19-03): un Godot headless que lanza el editor y lo vigila, para que una
## GDExtension que crashea al cargar no lo deje en un loop. Godot carga las extensiones antes que
## cualquier plugin, así que desde adentro del editor no se puede salir de ese loop.
##
##   godot --headless --path <proyecto>/.godot/agent_supervisor --script <este archivo> -- --project <proyecto>
##
## `--path` apunta a la carpeta de estado, que no tiene project.godot: el supervisor no carga ninguna
## extensión. El editor se lanza sin pipes (si el supervisor muriera, un pipe cerrado tiraría al
## editor al escribir) y con `--log-file`, de donde sale el backtrace.
##
## - Arranque bueno: el plugin escribe ready.json; a los STABLE_S segundos se copian las bibliotecas
##   a good/ (la última versión buena).
## - Crash antes de eso: vuelve a la versión buena (o desactiva una extensión nueva), deja el evento
##   para el agente y relanza. Crash después: deja el evento y relanza.
## - Cierre normal: termina, salvo que el plugin haya pedido reiniciar (restart.json).
## - Antes de cada lanzamiento mueve al proyecto lo que dejó preparado install_extension (pending/).
## - MAX_CRASHES crashes en LOOP_WINDOW_S: deja de relanzar.
##
## Opciones: `--wait-pid N` espera a que se cierre ese editor (el que lo lanzó, que marca closed.json)
## antes de abrir uno; `--editor-args a,b` agrega flags al editor (los del que lo lanzó: drivers de video, pantalla,
## audio); `--launch a,b,c` reemplaza los argumentos del editor (tests).

const State := preload("supervisor_state.gd")
const Snapshot := preload("extension_snapshot.gd")
const NativeInstall := preload("../core/native_install.gd")

const STABLE_S := 30
const LOOP_WINDOW_S := 300
const MAX_CRASHES := 3
const POLL_MS := 250
const WAIT_PID_TIMEOUT_S := 120
const WAIT_PID_GRACE_MS := 2000

var project := ""
var state_dir := ""
var _godot := OS.get_executable_path()
var _launch_override: PackedStringArray = []
## Flags del editor original (SupervisorClient.editor_flags): se repiten en cada lanzamiento.
var _editor_args: PackedStringArray = []
var _wait_pid := 0
var _pid := 0
var _ready_ms := -1
var _stable := false
var _crashes: Array[int] = []
var _started := ""
var _last_beat_ms := 0
var _wait_deadline_ms := 0


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	for i: int in args.size():
		match args[i]:
			"--project":
				project = args[i + 1].simplify_path() if i + 1 < args.size() else ""
			"--wait-pid":
				_wait_pid = int(args[i + 1]) if i + 1 < args.size() else 0
			"--editor-args":
				_editor_args = args[i + 1].split(",", false) if i + 1 < args.size() else PackedStringArray()
			"--launch":
				_launch_override = args[i + 1].split(",", false) if i + 1 < args.size() else PackedStringArray()
	if project.ends_with("/"):
		project = project.left(-1)
	if project.is_empty() or not FileAccess.file_exists(project.path_join("project.godot")):
		printerr("editor_supervisor: --project must be a folder with a project.godot")
		quit(2)
		return
	state_dir = State.state_dir(project)
	DirAccess.make_dir_recursive_absolute(state_dir)
	if State.supervisor_running(state_dir):
		printerr("editor_supervisor: another supervisor is running for %s" % project)
		quit(3)
		return
	_started = Time.get_datetime_string_from_system()
	_beat()
	_wait_deadline_ms = Time.get_ticks_msec() + WAIT_PID_TIMEOUT_S * 1000
	_log("started for %s" % project)


func _process(_delta: float) -> bool:
	if Time.get_ticks_msec() - _last_beat_ms >= 1000:
		_beat()
	if _wait_pid > 0:
		# No es hijo nuestro (OS.is_process_running no sirve): su plugin marca closed al salir.
		if not State.marked_by(state_dir, State.CLOSED, _wait_pid) and Time.get_ticks_msec() < _wait_deadline_ms:
			OS.delay_msec(POLL_MS)
			return false
		_wait_pid = 0
		# Que termine de cerrarse antes de abrir otro editor sobre el mismo proyecto.
		OS.delay_msec(WAIT_PID_GRACE_MS)
	if _pid == 0:
		if not _launch():
			return _finish("could not launch the editor")
	elif OS.is_process_running(_pid):
		_watch()
	elif _on_exit():
		return true
	OS.delay_msec(POLL_MS)
	return false


func _launch() -> bool:
	# Lo que preparó install_extension (m19-05) entra con el editor cerrado; si crashea al arrancar,
	# el rollback vuelve a la build buena (o desactiva una extensión nueva).
	var installed := NativeInstall.apply_pending(project, state_dir)
	if not (installed.applied as PackedStringArray).is_empty() or not (installed.failed as PackedStringArray).is_empty():
		_log("installed staged files: %s%s" % [", ".join(installed.applied), "; failed: " + ", ".join(installed.failed) if not installed.failed.is_empty() else ""])
	State.remove(state_dir, State.READY)
	State.remove(state_dir, State.CLOSED)
	var log_path := state_dir.path_join(State.LOG)
	if FileAccess.file_exists(log_path):
		DirAccess.remove_absolute(log_path + ".prev")
		DirAccess.rename_absolute(log_path, log_path + ".prev")
	var args := _launch_override if not _launch_override.is_empty() else _editor_args + PackedStringArray(["--editor", "--path", project])
	args = args + PackedStringArray(["--log-file", log_path])
	OS.set_environment(State.ENV_VAR, state_dir)
	_pid = OS.create_process(_godot, args)
	_ready_ms = -1
	_stable = false
	_log("launched editor pid %d" % _pid)
	return _pid > 0


func _watch() -> void:
	if _ready_ms < 0 and State.marked_by(state_dir, State.READY, _pid):
		_ready_ms = Time.get_ticks_msec()
	if _ready_ms >= 0 and not _stable and Time.get_ticks_msec() - _ready_ms >= STABLE_S * 1000:
		_stable = true
		var copied := Snapshot.snapshot(project, state_dir)
		_log("editor stable; good builds saved: %s" % (", ".join(copied) if not copied.is_empty() else "unchanged"))


## El editor terminó. Devuelve true si el supervisor también termina.
func _on_exit() -> bool:
	var dead := _pid
	_pid = 0
	var backtrace := State.crash_lines(state_dir.path_join(State.LOG), project)
	var ready := _ready_ms >= 0
	var closed := State.marked_by(state_dir, State.CLOSED, dead)
	var crashed := not backtrace.is_empty() or (ready and not closed)
	var restart := State.read_json(state_dir, State.RESTART)
	State.remove(state_dir, State.RESTART)
	if not crashed:
		if int(restart.get("pid", 0)) == dead:
			_log("restart requested by editor pid %d" % dead)
			_add_event({"kind": State.EVENT_RESTART, "reason": str(restart.get("reason", ""))})
			return false
		return _finish("editor closed")
	var now := Time.get_ticks_msec()
	_crashes.append(now)
	_crashes = _crashes.filter(func(at: int) -> bool: return now - at <= LOOP_WINDOW_S * 1000)
	var event := {"kind": State.EVENT_CRASH if _stable else State.EVENT_STARTUP_CRASH, "backtrace": backtrace, "log": state_dir.path_join(State.LOG + ".prev")}
	if not _stable:
		event.merge(Snapshot.changes(project, state_dir))
		event.merge(Snapshot.rollback(project, state_dir))
	_log("editor pid %d crashed (%s): restored %s, disabled %s" % [dead, event.kind, event.get("restored", []), event.get("disabled", [])])
	if _crashes.size() >= MAX_CRASHES:
		event.kind = State.EVENT_GAVE_UP
		event["crashes"] = _crashes.size()
		_add_event(event)
		return _finish("%d crashes in %d s: not relaunching" % [_crashes.size(), LOOP_WINDOW_S])
	_add_event(event)
	return false


func _beat() -> void:
	_last_beat_ms = Time.get_ticks_msec()
	State.write_json(state_dir, State.SUPERVISOR, {"pid": OS.get_process_id(), "project": project, "started": _started, "beat": int(Time.get_unix_time_from_system())})


func _add_event(event: Dictionary) -> void:
	event["time"] = Time.get_datetime_string_from_system()
	var pending := State.read_json(state_dir, State.EVENT)
	var events: Array = pending.get("events", [])
	events.append(event)
	State.write_json(state_dir, State.EVENT, {"events": events})


func _finish(reason: String) -> bool:
	_log(reason)
	State.remove(state_dir, State.SUPERVISOR)
	quit(0)
	return true


func _log(message: String) -> void:
	var line := "[%s] %s" % [Time.get_datetime_string_from_system(), message]
	print(line)
	var file := FileAccess.open(state_dir.path_join("supervisor.log"), FileAccess.READ_WRITE if FileAccess.file_exists(state_dir.path_join("supervisor.log")) else FileAccess.WRITE)
	if file:
		file.seek_end()
		file.store_line(line)
		file.close()
