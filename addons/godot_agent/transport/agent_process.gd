@tool
extends RefCounted
## Proceso del agente: lo lanza con OS.execute_with_pipe y lee stdout (por líneas) y stderr en
## threads. Las señales se emiten siempre en el hilo principal (call_deferred).
## No parsea JSON: eso es del AcpClient.

signal line_received(line: String)
signal stderr_received(line: String)
signal exited(code: int)

const ProcessTree := preload("process_tree.gd")
const CommandResolver := preload("command_resolver.gd")

## Cada cuánto el watcher mira si el proceso sigue vivo.
const WATCH_INTERVAL_MS := 200
const EOF_GRACE_MS := 2000
## Cada cuántas vueltas del watcher se refresca la lista de descendientes.
const CHILDREN_REFRESH_TICKS := 10

var _stdio: FileAccess
var _stderr: FileAccess
var _pid: int = 0
var _stdout_thread: Thread
var _stderr_thread: Thread
var _watch_thread: Thread
var _stopping: bool = false
## stdout llegó a EOF: el exit se emite después de la última línea.
var _stdout_done: bool = false
var _exit_emitted: bool = false
var _last_error: String = ""
## Descendientes vistos por última vez: si el proceso principal muere, sus hijos quedan
## huérfanos (pgrep -P ya no los encuentra) y pueden mantener los pipes abiertos.
var _known_children: PackedInt32Array = []
var _children_mutex := Mutex.new()

## Godot 4.4.x: cerrar o liberar el FileAccess de un pipe de execute_with_pipe cierra fds
## equivocados (incluso el 0 del editor) y rompe el siguiente proceso (D11). Ahí los pipes viejos
## no se cierran: se guardan acá hasta que se cierra el editor. Corregido en 4.5.
static var _retained_pipes: Array[FileAccess] = []


## Lanza `command` con `args`. `env` se aplica al entorno del hijo (se hereda del editor: se
## setea antes de lanzar y se restaura después). Devuelve false y deja last_error() si falla.
## execute_with_pipe no recibe cwd: el agente trabaja en el `cwd` que le pasa session/new.
func start(command: String, args: PackedStringArray, env: Dictionary = {}) -> bool:
	if is_running():
		_last_error = "El proceso ya está corriendo."
		return false
	_last_error = ""
	var executable := CommandResolver.resolve(command)
	if executable.is_empty():
		_last_error = "No se encontró el comando '%s' en el PATH ni en las carpetas habituales." % command
		return false

	var child_env := env.duplicate()
	if not child_env.has("PATH"):
		child_env["PATH"] = CommandResolver.child_path_for(executable)
	var saved_env := _apply_env(child_env)
	var info: Dictionary = OS.execute_with_pipe(executable, args, true)
	_restore_env(saved_env)

	if info.is_empty():
		_last_error = "No se pudo lanzar '%s'." % executable
		return false
	_stdio = info.stdio
	_stderr = info.stderr
	_pid = info.pid
	_stopping = false
	_stdout_done = false
	_exit_emitted = false

	_stdout_thread = Thread.new()
	_stdout_thread.start(_read_stdout)
	_stderr_thread = Thread.new()
	_stderr_thread.start(_read_stderr)
	_watch_thread = Thread.new()
	_watch_thread.start(_watch_exit)
	return true


func last_error() -> String:
	return _last_error


func pid() -> int:
	return _pid


func is_running() -> bool:
	return _pid > 0 and OS.is_process_running(_pid)


## Escribe una línea en stdin del agente. Solo desde el hilo principal.
func send_line(line: String) -> bool:
	if _stdio == null or not is_running():
		return false
	var buffer := (line + "\n").to_utf8_buffer()
	_stdio.store_buffer(buffer)
	_stdio.flush()
	return _stdio.get_error() == OK


## Mata el proceso (y sus hijos) y espera a los threads. Seguro de llamar varias veces.
func stop() -> void:
	_stopping = true
	if _pid > 0 and OS.is_process_running(_pid):
		ProcessTree.kill_tree(_pid)
	_kill_known_children()
	_join_threads()
	for pipe: FileAccess in [_stdio, _stderr]:
		if pipe == null:
			continue
		if pipe_close_is_broken():
			_retained_pipes.append(pipe)
		else:
			pipe.close()
	_stdio = null
	_stderr = null
	_pid = 0


func _notification(what: int) -> void:
	# Red de seguridad: si se pierde la última referencia sin stop(), no quedan procesos ni threads.
	if what == NOTIFICATION_PREDELETE and (_pid > 0 or _stdout_thread != null):
		stop()


static func pipe_close_is_broken() -> bool:
	var version := Engine.get_version_info()
	return version.major == 4 and version.minor < 5


func _join_threads() -> void:
	for thread: Thread in [_stdout_thread, _stderr_thread, _watch_thread]:
		if thread and thread.is_started():
			thread.wait_to_finish()
	_stdout_thread = null
	_stderr_thread = null
	_watch_thread = null


# --- threads -------------------------------------------------------------------------------------

func _read_stdout() -> void:
	_read_lines(_stdio, _emit_line)
	_stdout_done = true


func _read_stderr() -> void:
	_read_lines(_stderr, _emit_stderr)


## Lee hasta EOF. get_line bloquea; termina cuando el proceso cierra el pipe (o lo matamos).
func _read_lines(file: FileAccess, emit: Callable) -> void:
	if file == null:
		return
	while not _stopping:
		var line := file.get_line()
		var error := file.get_error()
		if error != OK and line.is_empty():
			break
		if not line.is_empty():
			emit.call_deferred(line)


func _watch_exit() -> void:
	var tick := 0
	while not _stopping and OS.is_process_running(_pid):
		if tick % CHILDREN_REFRESH_TICKS == 1:
			var children := ProcessTree.descendants(_pid)
			_children_mutex.lock()
			_known_children = children
			_children_mutex.unlock()
		tick += 1
		OS.delay_msec(WATCH_INTERVAL_MS)
	# Un nieto (p. ej. node bajo npx) puede mantener stdout abierto un rato: se le da un margen.
	var waited := 0
	while not _stopping and not _stdout_done and waited < EOF_GRACE_MS:
		OS.delay_msec(WATCH_INTERVAL_MS)
		waited += WATCH_INTERVAL_MS
	if not _stdout_done:
		_kill_known_children()
	if _stopping:
		return
	var code := OS.get_process_exit_code(_pid)
	_emit_exited.call_deferred(code)


func _emit_line(line: String) -> void:
	line_received.emit(line)


func _emit_stderr(line: String) -> void:
	stderr_received.emit(line)


func _emit_exited(code: int) -> void:
	if _exit_emitted or _stopping:
		return
	_exit_emitted = true
	exited.emit(code)


func _kill_known_children() -> void:
	_children_mutex.lock()
	var children := _known_children
	_known_children = PackedInt32Array()
	_children_mutex.unlock()
	# No son hijos directos: OS.is_process_running daría error. OS.kill sobre un pid muerto no hace nada.
	for child: int in children:
		OS.kill(child)


# --- entorno -------------------------------------------------------------------------------------

static func _apply_env(env: Dictionary) -> Dictionary:
	var saved: Dictionary = {}
	for key: String in env:
		saved[key] = OS.get_environment(key) if OS.has_environment(key) else null
		OS.set_environment(key, str(env[key]))
	return saved


static func _restore_env(saved: Dictionary) -> void:
	for key: String in saved:
		if saved[key] == null:
			OS.unset_environment(key)
		else:
			OS.set_environment(key, saved[key])

