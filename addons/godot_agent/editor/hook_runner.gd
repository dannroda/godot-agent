@tool
extends Node
## Corre los hooks del proyecto (m11-24, ver core/project_hooks.gd) cuando el plugin le pasa un evento.
## - Un hook sin aprobar en esta máquina no corre: `held` avisa una vez por clave.
## - Eventos seguidos del mismo hook se juntan (DEBOUNCE_S) y un hook corre de a uno: si llega otro
##   evento mientras corre, corre una vez más al terminar, con el último.
## - Nunca bloquea: el comando corre en otro proceso y el editor sigue.
## - Cada corrida va al log (`log_line`); una falla avisa con `failed` una vez hasta que vuelve a pasar.

signal finished(hook: Dictionary, result: Dictionary)

const ProjectHooks := preload("../core/project_hooks.gd")
const TurnChecks := preload("../core/turn_checks.gd")

const DEBOUNCE_S := 1.0

## Callable() -> {hooks: Array, godot: String, project: String}.
var provider: Callable
## Callable(key: String) -> bool.
var is_approved: Callable
## Callable(hook: Dictionary, key: String): un hook frenado por no estar aprobado (una vez por clave).
var held: Callable
## Callable(text: String): una línea para el log del harness.
var log_line: Callable
## Callable(hook: Dictionary, result: Dictionary): una falla (una vez hasta que el hook vuelve a pasar).
var failed: Callable
## Callable(hook: Dictionary, event: Dictionary) -> Dictionary: corre una acción que no es un comando
## (tool, prompt) y devuelve `{ok, output}`. Sin asignar, esas acciones no corren.
var run_action: Callable
var debounce_s: float = DEBOUNCE_S

## clave -> último resultado `{ok, code, output, timed_out, event, at}` (la pestaña Hooks lo muestra).
var last_results: Dictionary = {}
var _held_noticed: Dictionary = {}
var _failing: Dictionary = {}
var _pending: Dictionary = {}  # clave -> {hook, event}
var _running: Dictionary = {}  # clave -> true
var _again: Dictionary = {}  # clave -> {hook, event}
## Los procesos de los comandos en curso: se paran al salir del árbol (deshabilitar el plugin, cerrar el
## editor), porque la corrida no vuelve a tener un frame para terminar.
var _processes: Dictionary = {}  # clave -> AgentProcess


func _exit_tree() -> void:
	for process: Object in _processes.values():
		if is_instance_valid(process):
			process.call(&"stop")
	_processes.clear()


## Un evento del editor: `{event, path, by, errors, lines}`.
func fire(event: Dictionary) -> void:
	if not provider.is_valid() or not is_inside_tree():
		return
	var info: Dictionary = provider.call()
	for hook: Dictionary in ProjectHooks.normalize_list(info.get("hooks", [])):
		if not ProjectHooks.matches(hook, event):
			continue
		var key := ProjectHooks.approval_key(str(info.get("project", "")), hook)
		if not (is_approved.is_valid() and bool(is_approved.call(key))):
			if not _held_noticed.has(key):
				_held_noticed[key] = true
				_log("⊘ hook «%s» (%s %s): not approved on this machine, didn't run" % [hook.name, event.get("event", ""), event.get("path", "")])
				if held.is_valid():
					held.call(hook, key)
			continue
		if _running.has(key):
			_again[key] = {"hook": hook, "event": event}
		elif _pending.has(key):
			_pending[key].event = event
		else:
			_pending[key] = {"hook": hook, "event": event}
			_start_after_debounce(key, info)


## Se olvida de los avisos de hooks frenados (por ejemplo, después de aprobar uno).
func forget_held(key: String = "") -> void:
	if key.is_empty():
		_held_noticed.clear()
	else:
		_held_noticed.erase(key)


func is_running(key: String) -> bool:
	return _running.has(key) or _pending.has(key)


func _start_after_debounce(key: String, info: Dictionary) -> void:
	if debounce_s > 0.0:
		await get_tree().create_timer(debounce_s).timeout
	if not is_inside_tree() or not _pending.has(key):
		return
	var job: Dictionary = _pending[key]
	_pending.erase(key)
	_running[key] = true
	await _run(key, job.hook, job.event, info)
	_running.erase(key)
	if _again.has(key) and is_inside_tree():
		_pending[key] = _again[key]
		_again.erase(key)
		_start_after_debounce(key, info)


func _run(key: String, hook: Dictionary, event: Dictionary, info: Dictionary) -> void:
	var started := Time.get_ticks_msec()
	var result := {"ok": false, "code": -1, "output": "", "timed_out": false, "event": event, "at": Time.get_unix_time_from_system()}
	if str(hook.action) == ProjectHooks.ACTION_COMMAND:
		var how := ProjectHooks.invocation(hook, event, str(info.get("godot", OS.get_executable_path())), str(info.get("project", "")))
		if not str(how.error).is_empty():
			result.output = str(how.error)
		else:
			var ran: Dictionary = await TurnChecks.run_process(how, int(hook.timeout_s), ProjectHooks.environment(hook, event),
				func(process: Object) -> void: _processes[key] = process)
			_processes.erase(key)
			result.code = int(ran.code)
			result.output = str(ran.output)
			result.timed_out = bool(ran.timed_out)
			result.ok = bool(ran.launched) and not result.timed_out and result.code == 0
	elif run_action.is_valid():
		var done: Dictionary = await run_action.call(hook, event)
		result.ok = bool(done.get("ok", false))
		result.output = str(done.get("output", ""))
	else:
		result.output = "This action isn't available here."
	if not is_inside_tree():
		return
	last_results[key] = result
	var seconds := (Time.get_ticks_msec() - started) / 1000.0
	var why := "" if result.ok else (" (stopped after %d s)" % int(hook.timeout_s) if result.timed_out else (" (exit code %d)" % result.code if result.code >= 0 else ""))
	_log("%s hook «%s» on %s %s · %.1f s%s%s" % ["✓" if result.ok else "✗", hook.name, event.get("event", ""), event.get("path", ""), seconds, why,
		("\n" + str(result.output)) if not str(result.output).is_empty() else ""])
	if result.ok:
		_failing.erase(key)
	elif not _failing.has(key):
		_failing[key] = true
		if failed.is_valid():
			failed.call(hook, result)
	finished.emit(hook, result)


func _log(text: String) -> void:
	if log_line.is_valid():
		log_line.call(text)
