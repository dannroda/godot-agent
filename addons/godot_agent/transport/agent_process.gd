@tool
extends RefCounted
## Proceso del agente: lo lanza con OS.execute_with_pipe y lee stdout (por líneas) y stderr desde el
## hilo principal, una vez por frame y solo los bytes que ya están en el pipe (get_length), así que
## nunca bloquea. Sin threads a propósito (D35): si el editor recarga un script del addon modificado
## en disco (un git pull, un proyecto con el addon por symlink), un thread que estaba ejecutando ese
## script sigue con el bytecode liberado y el editor se cae. Las líneas de stdout se entregan con un
## presupuesto de tiempo por frame: una ráfaga de updates no congela el editor. No parsea JSON: eso
## es del AcpClient.

signal line_received(line: String)
signal stderr_received(line: String)
signal exited(code: int)

const ProcessTree := preload("process_tree.gd")
const CommandResolver := preload("command_resolver.gd")

## Cada cuánto se mira si el proceso sigue vivo.
const WATCH_INTERVAL_MS := 200
## Muerto el proceso, un nieto (p. ej. node bajo npx) puede seguir escribiendo un rato.
const EOF_GRACE_MS := 2000
## Cada cuánto se refresca la lista de descendientes (con pgrep, que lanza procesos, menos seguido).
const CHILDREN_REFRESH_MS := 2000
const CHILDREN_REFRESH_PGREP_MS := 10000
## Tiempo de un frame que se puede usar para entregar líneas de stdout (el resto, al siguiente).
const LINE_BUDGET_USEC := 6000
## Bytes que se leen de un pipe por frame como máximo.
const READ_CHUNK := 1 << 20

var _stdio: FileAccess
var _stderr: FileAccess
var _pid: int = 0
var _last_error: String = ""
## Cambia en cada start() y stop(): un handler que para (o relanza) el proceso corta la entrega.
var _generation: int = 0
var _polling: bool = false
## Bytes leídos que todavía no forman una línea completa.
var _stdout_rest: PackedByteArray = []
var _stderr_rest: PackedByteArray = []
## Líneas de stdout que esperan su turno de entrega.
var _lines: PackedStringArray = []
var _next_watch_ms: int = 0
var _next_children_ms: int = 0
## Momento en que se vio muerto el proceso (-1: vivo).
var _dead_since_ms: int = -1
## Descendientes vistos por última vez: si el proceso principal muere, sus hijos quedan
## huérfanos (ya no cuelgan de él) y pueden seguir vivos con los pipes abiertos.
var _known_children: PackedInt32Array = []


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
	_generation += 1
	_stdio = info.stdio
	_stderr = info.stderr
	_pid = info.pid
	_stdout_rest.clear()
	_stderr_rest.clear()
	_lines.clear()
	_known_children.clear()
	_dead_since_ms = -1
	_next_watch_ms = 0
	_next_children_ms = Time.get_ticks_msec() + WATCH_INTERVAL_MS
	_set_polling(true)
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


## Mata el proceso (y sus hijos) y cierra los pipes. Seguro de llamar varias veces.
func stop() -> void:
	_generation += 1
	_set_polling(false)
	if _pid > 0 and OS.is_process_running(_pid):
		ProcessTree.kill_tree(_pid)
	_kill_known_children()
	for pipe: FileAccess in [_stdio, _stderr]:
		if pipe:
			pipe.close()
	_stdio = null
	_stderr = null
	_pid = 0
	_lines.clear()


func _notification(what: int) -> void:
	# Red de seguridad: si se pierde la última referencia sin stop(), no quedan procesos.
	if what == NOTIFICATION_PREDELETE and (_pid > 0 or _stdio != null):
		stop()


func _set_polling(enabled: bool) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or enabled == _polling:
		return
	_polling = enabled
	if enabled:
		tree.process_frame.connect(_poll)
	else:
		tree.process_frame.disconnect(_poll)


# --- lectura -------------------------------------------------------------------------------------

## Una vez por frame: lee lo que haya en los pipes, entrega líneas y mira si el proceso sigue vivo.
func _poll() -> void:
	var generation := _generation
	_read_stderr()
	if generation != _generation:
		return
	_read_stdout()
	_deliver_lines(generation)
	if generation != _generation:
		return
	var now := Time.get_ticks_msec()
	if now < _next_watch_ms:
		return
	_next_watch_ms = now + WATCH_INTERVAL_MS
	if _dead_since_ms < 0:
		if OS.is_process_running(_pid):
			if now >= _next_children_ms:
				_refresh_children()
			return
		_dead_since_ms = now
	# Muerto: el exit sale después de la última línea y cuando los huérfanos dejaron de escribir.
	if not _lines.is_empty() or _available(_stdio) > 0 or _available(_stderr) > 0:
		return
	if now - _dead_since_ms < EOF_GRACE_MS and _children_alive():
		return
	_finish()


func _finish() -> void:
	_set_polling(false)
	_kill_known_children()
	var generation := _generation
	var rest := _stderr_rest.get_string_from_utf8().strip_edges(false, true)
	_stderr_rest.clear()
	if not rest.is_empty():
		stderr_received.emit(rest)
	rest = _stdout_rest.get_string_from_utf8().strip_edges(false, true)
	_stdout_rest.clear()
	if not rest.is_empty() and generation == _generation:
		line_received.emit(rest)
	if generation == _generation:
		exited.emit(OS.get_process_exit_code(_pid))


func _read_stdout() -> void:
	var data := _read_available(_stdio)
	if data.is_empty():
		return
	_stdout_rest.append_array(data)
	var split := _split_lines(_stdout_rest)
	_stdout_rest = split.rest
	_lines.append_array(split.lines)


func _read_stderr() -> void:
	var data := _read_available(_stderr)
	if data.is_empty():
		return
	_stderr_rest.append_array(data)
	var split := _split_lines(_stderr_rest)
	_stderr_rest = split.rest
	var generation := _generation
	for line: String in split.lines:
		stderr_received.emit(line)
		if generation != _generation:
			return


## Entrega líneas hasta agotar el presupuesto del frame; las que quedan salen en el próximo.
func _deliver_lines(generation: int) -> void:
	if _lines.is_empty():
		return
	var started := Time.get_ticks_usec()
	var batch := _lines
	_lines = PackedStringArray()
	for i in batch.size():
		line_received.emit(batch[i])
		if generation != _generation:
			return
		if Time.get_ticks_usec() - started > LINE_BUDGET_USEC and i + 1 < batch.size():
			_lines = batch.slice(i + 1) + _lines
			return


## Bytes que ya están en el pipe. Leer exactamente eso no bloquea aunque el pipe sea bloqueante.
static func _available(pipe: FileAccess) -> int:
	return pipe.get_length() if pipe else 0


static func _read_available(pipe: FileAccess) -> PackedByteArray:
	var count := mini(_available(pipe), READ_CHUNK)
	return pipe.get_buffer(count) if count > 0 else PackedByteArray()


## `{lines, rest}`: las líneas completas de `data` (sin vacías ni el \r final) y lo que sobra.
static func _split_lines(data: PackedByteArray) -> Dictionary:
	var lines: PackedStringArray = []
	var start := 0
	var newline := data.find(10)
	while newline >= 0:
		var line := data.slice(start, newline).get_string_from_utf8().strip_edges(false, true)
		if not line.is_empty():
			lines.append(line)
		start = newline + 1
		newline = data.find(10, start)
	return {"lines": lines, "rest": data.slice(start)}


# --- descendientes -------------------------------------------------------------------------------

func _refresh_children() -> void:
	if not ProcessTree.can_list_descendants():
		_next_children_ms = Time.get_ticks_msec() + 3600000
		return
	_known_children = ProcessTree.descendants(_pid)
	var interval := CHILDREN_REFRESH_MS if ProcessTree.has_proc_children() else CHILDREN_REFRESH_PGREP_MS
	_next_children_ms = Time.get_ticks_msec() + interval


func _children_alive() -> bool:
	for child: int in _known_children:
		if ProcessTree.is_alive(child):
			return true
	return false


func _kill_known_children() -> void:
	var children := _known_children
	_known_children = PackedInt32Array()
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
