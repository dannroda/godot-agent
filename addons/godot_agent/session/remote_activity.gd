@tool
extends Node
## Lo que se hace desde el celular con Remote Control, en el chat del dock (m7-22). Mientras está
## prendido y no hay un turno del dock en curso, RemoteWatch mira los archivos del proyecto cada
## POLL_INTERVAL_S; una tanda de cambios termina cuando pasa una vuelta sin cambios y queda como un
## aviso «Desde Remote Control: …» con «Ver diff» y «Deshacer».

const RemoteWatch := preload("remote_watch.gd")
const SessionModel := preload("session_model.gd")
const ChatEntry := preload("chat_entry.gd")
const AgentLog := preload("../core/agent_log.gd")
const I18n := preload("../core/i18n.gd")
const ProjectConfig := preload("../config/project_config.gd")

const ACTION_DIFF := "remote_diff"
const ACTION_UNDO := "remote_undo"
const POLL_INTERVAL_S := 2.0
## Nombres de archivo que se listan por tipo de cambio; el resto va como «y N más».
const MAX_NAMES := 6

## Tras restaurar archivos: el editor los vuelve a leer (EditorSync.after_agent_write, ruta absoluta).
var after_restore: Callable
var watch := RemoteWatch.new()
var _model: SessionModel
var _log: AgentLog
var _root: String = ""
var _timer: Timer
var _pending: Array[Dictionary] = []
## id de la tanda -> {changes, entry}
var _batches: Dictionary = {}
var _next_batch: int = 1


func setup(model: SessionModel, log: AgentLog, project_root: String) -> void:
	_model = model
	_log = log
	_root = project_root
	# La config la guarda el harness (Settings, «Permitir siempre»), no el celular.
	watch.ignored = [ProjectConfig.PATH.trim_prefix("res://")]
	_model.remote_control_changed.connect(_on_remote_control_changed)
	_model.state_changed.connect(_on_state_changed)
	_model.turn_finished.connect(func(_reason: String) -> void: watch.rebase())


func _ready() -> void:
	_timer = Timer.new()
	_timer.wait_time = POLL_INTERVAL_S
	_timer.timeout.connect(poll_now)
	add_child(_timer)
	if watch.is_active():
		_timer.start()


## Un archivo guardado desde el editor no viene del celular.
func note_saved(res_path: String) -> void:
	watch.note_saved(res_path)


## Una vuelta del watcher (la llama el timer; los tests, directo).
func poll_now() -> void:
	if not watch.is_active() or _model.is_busy():
		return
	var changes := watch.poll()
	if changes.is_empty():
		flush()
	else:
		_pending = RemoteWatch.merge(_pending, changes)


## Cierra la tanda en curso como un aviso en el chat.
func flush() -> void:
	if _pending.is_empty():
		return
	var changes := _pending
	_pending = []
	var id := _next_batch
	_next_batch += 1
	var actions: Array[Dictionary] = []
	actions.append({"id": ACTION_DIFF, "label": I18n.t("View diff"), "data": id})
	if RemoteWatch.can_restore(changes):
		actions.append({"id": ACTION_UNDO, "label": I18n.t("Undo"), "data": id})
	var entry := _model.add_notice(describe(changes), ChatEntry.NoticeLevel.INFO, actions)
	_batches[id] = {"changes": changes, "entry": entry}
	if _log:
		_log.add(AgentLog.CH_FS, "Remote Control: %s" % ", ".join(changes.map(func(change: Dictionary) -> String: return "%s %s" % [RemoteWatch.FileChange.keys()[change.change].to_lower(), change.path])))


## Texto de una tanda: «Desde Remote Control: modificó a.gd y main.tscn · creó b.gd».
static func describe(changes: Array) -> String:
	var parts: PackedStringArray = []
	for kind: RemoteWatch.FileChange in [RemoteWatch.FileChange.MODIFIED, RemoteWatch.FileChange.CREATED, RemoteWatch.FileChange.DELETED]:
		var names: PackedStringArray = []
		for change: Dictionary in changes:
			if change.change == kind:
				names.append(str(change.path).trim_prefix("res://"))
		if names.is_empty():
			continue
		var shown := ", ".join(names.slice(0, MAX_NAMES))
		if names.size() > MAX_NAMES:
			shown += " " + I18n.t("and %d more") % (names.size() - MAX_NAMES)
		match kind:
			RemoteWatch.FileChange.MODIFIED:
				parts.append(I18n.t("modified %s") % shown)
			RemoteWatch.FileChange.CREATED:
				parts.append(I18n.t("created %s") % shown)
			RemoteWatch.FileChange.DELETED:
				parts.append(I18n.t("deleted %s") % shown)
	return I18n.t("From Remote Control: %s") % " · ".join(parts)


## Diff de una tanda: antes y ahora de cada archivo, uno debajo del otro.
func diff_texts(id: int) -> PackedStringArray:
	var batch: Variant = _batches.get(id)
	if batch == null:
		return PackedStringArray(["", ""])
	var before := ""
	var after := ""
	for change: Dictionary in batch.changes:
		var header := "=== %s ===\n" % change.path
		var path := ProjectSettings.globalize_path(change.path) if _root.is_empty() else _root + "/" + str(change.path).trim_prefix("res://")
		before += header + (str(change.before) if change.before != null else "") + "\n"
		after += header + (FileAccess.get_file_as_string(path) if FileAccess.file_exists(path) else "") + "\n"
	return PackedStringArray([before, after])


## Deshace una tanda. Devuelve las rutas que no se pudieron restaurar.
func undo(id: int) -> PackedStringArray:
	var batch: Variant = _batches.get(id)
	if batch == null:
		return PackedStringArray()
	var failed := watch.restore(batch.changes) if watch.is_active() else _restore_inactive(batch.changes)
	if after_restore.is_valid():
		for change: Dictionary in batch.changes:
			after_restore.call(_root + "/" + str(change.path).trim_prefix("res://"))
	var entry: ChatEntry = batch.entry
	entry.actions = []
	entry.text += "\n" + (I18n.t("Undone.") if failed.is_empty() else I18n.t("Could not restore: %s") % ", ".join(failed))
	_model.notify_entry_changed(entry)
	_batches.erase(id)
	return failed


func _restore_inactive(changes: Array) -> PackedStringArray:
	var helper := RemoteWatch.new()
	helper.root = _root
	return helper.restore(changes)


func _on_remote_control_changed(url: String) -> void:
	if url.is_empty():
		poll_now()
		flush()
		watch.stop()
		if _timer:
			_timer.stop()
	elif not watch.is_active():
		watch.start(_root)
		if watch.truncated and _model:
			_model.add_notice(I18n.t("The project has more than %d files: changes from Remote Control are only watched in the first ones.") % RemoteWatch.MAX_FILES, ChatEntry.NoticeLevel.WARNING)
		if _timer:
			_timer.start()


## Antes de un turno del dock se cierra lo que vino del celular; lo que cambie en el turno es del dock.
func _on_state_changed(state: SessionModel.SessionState) -> void:
	if state == SessionModel.SessionState.PROMPTING and watch.is_active():
		_pending = RemoteWatch.merge(_pending, watch.poll())
		flush()
