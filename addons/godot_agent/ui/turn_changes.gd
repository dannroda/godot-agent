@tool
extends RefCounted
## Lo que cambió un turno (m11-01, m11-02, m11-06): ver el diff de un archivo, volver atrás todo el
## turno o un archivo (con confirmación y «Deshacer»), y guardar el reporte. Lo arma el plugin, que
## le pasa los diálogos y cómo encontrar la sesión de cada aviso (`data.session`).
##
## Por trozo (m11-34): cada trozo del diff del turno (del snapshot del principio al del final) se
## conserva (una marca) o se rechaza (git apply -R sobre el archivo actual, ver TurnSnapshots). Un
## trozo cuyas líneas cambiaron después queda «cambió después del turno» y no se toca. Tampoco un
## archivo con cambios sin guardar en el editor ni uno que otra sesión está editando en su turno. El
## estado de los trozos queda en `data.hunk_state` ({ruta: {"índice": "kept" o "rejected"}}).

const SessionModel := preload("../session/session_model.gd")
const SessionController := preload("../session/session_controller.gd")
const ChatEntry := preload("../session/chat_entry.gd")
const TurnSnapshots := preload("../session/turn_snapshots.gd")
const EditorWindows := preload("editor_windows.gd")
const TurnReport := preload("../session/turn_report.gd")
const DiffDialog := preload("diff_dialog.gd")
const TurnChangesDialog := preload("turn_changes_dialog.gd")
const EditorContext := preload("editor_context.gd")
const I18n := preload("../core/i18n.gd")

## Acción del aviso de un trozo rechazado: lo vuelve a aplicar.
const ACTION_HUNK_UNDO := "turn_hunk_undo"
const KEPT := "kept"
const REJECTED := "rejected"

## Los snapshots del proyecto abierto; una sesión en una copia (m11-09) tiene los suyos.
var project_snapshots: TurnSnapshots
var diff_dialog: DiffDialog
var dialog: TurnChangesDialog
## La sesión de un aviso sin `session`.
var primary_session: String = ""
## `(session: String) -> SessionController` y `(session: String) -> SessionModel`.
var controller_of: Callable
var model_of: Callable
## `(paths: PackedStringArray) -> void`: el editor relee lo que volvió atrás.
var after_restore: Callable
## `(res_path: String) -> bool`: el archivo está abierto en el editor con cambios sin guardar.
var unsaved_of: Callable = func(_res_path: String) -> bool: return false
## `(session: String, res_path: String) -> String`: el nombre de otra sesión que lo está editando, o "".
var holder_of: Callable = func(_session: String, _res_path: String) -> String: return ""


## Los trozos de un archivo del turno con lo que se puede hacer con cada uno: [{hunk, state ("",
## "kept", "rejected"), stale (sus líneas cambiaron después), blocked (por qué no se puede tocar
## ahora, o "")}]. Durante el turno (`data.live`) se ven, pero no se tocan.
func file_hunks(data: Dictionary, path: String) -> Array[Dictionary]:
	var session := str(data.get("session", primary_session))
	var snapshots := _snapshots_of(session)
	var result: Array[Dictionary] = []
	if snapshots == null or not data.has("end"):
		return result
	var blocked := _blocked_reason(data, path)
	var states: Dictionary = data.get("hunk_state", {}).get(path, {})
	for hunk: Dictionary in await snapshots.hunks(str(data.start), str(data.end), path):
		var state := str(states.get(str(hunk.index), ""))  # claves de texto: el aviso se guarda en JSON
		var possible := await snapshots.can_apply(hunk, state == REJECTED)
		result.append({"hunk": hunk, "state": state, "stale": not possible, "blocked": blocked})
	return result


## El diálogo pidió los trozos de un archivo.
func show_hunks(data: Dictionary, path: String) -> void:
	var items := await file_hunks(data, path)
	if dialog:
		dialog.set_hunks(data, path, items)


## Una acción del diálogo sobre un trozo.
func on_hunk_action(data: Dictionary, path: String, index: int, action: String) -> void:
	var error := ""
	match action:
		"keep", "unkeep":
			keep_hunk(data, path, index, action == "keep")
			if dialog:
				dialog.refresh_file(data, path)
		"reject", "undo":
			error = await reject_hunk(data, path, index, action == "undo")
			if not error.is_empty() and dialog:
				dialog.refresh_file(data, path)
	if dialog:
		dialog.set_error(data, path, error)


## «Rechazar todo» de un archivo en el diálogo.
func on_reject_file(data: Dictionary, path: String) -> void:
	var counts := await reject_file(data, path)
	if dialog:
		dialog.refresh_file(data, path)
		var skipped: int = counts.skipped
		var message := ""
		if skipped == 1:
			message = I18n.t("1 change could not be rejected: its lines changed after the turn, or the file can't be touched now.")
		elif skipped > 1:
			message = I18n.t("%d changes could not be rejected: their lines changed after the turn, or the file can't be touched now.") % skipped
		dialog.set_error(data, path, message)


## Por qué no se puede tocar ahora un archivo del turno, o "".
func _blocked_reason(data: Dictionary, path: String) -> String:
	if data.get("live", false):
		return I18n.t("The turn is still running.")
	var session := str(data.get("session", primary_session))
	if _snapshots_of(session) != project_snapshots:
		return ""  # una copia aparte: nada abierto en el editor ni reclamado acá
	var res_path := "res://" + path
	if unsaved_of.call(res_path):
		return I18n.t("It has unsaved changes in the editor: save or discard them first.")
	var holder: String = holder_of.call(session, res_path)
	if not holder.is_empty():
		return I18n.t("«%s» is editing it in its turn.") % holder
	return ""


## Marca un trozo como revisado sin cambiar el archivo (o le saca la marca).
func keep_hunk(data: Dictionary, path: String, index: int, kept: bool = true) -> void:
	_set_state(data, path, index, KEPT if kept else "")


## Rechaza un trozo (o, con `undo`, vuelve a aplicar uno rechazado). Devuelve "" o el motivo por el
## que no se pudo; en ese caso no escribió nada.
func reject_hunk(data: Dictionary, path: String, index: int, undo: bool = false) -> String:
	var blocked := _blocked_reason(data, path)
	if not blocked.is_empty():
		return blocked
	var session := str(data.get("session", primary_session))
	var snapshots := _snapshots_of(session)
	var hunks := await snapshots.hunks(str(data.start), str(data.end), path)
	if index < 0 or index >= hunks.size():
		return I18n.t("That change is no longer there.")
	var applied: Dictionary = await snapshots.apply_hunk(hunks[index], undo)
	if not applied.ok:
		return I18n.t("Those lines changed after the turn: use «Go back» for the whole file.")
	_set_state(data, path, index, "" if undo else REJECTED)
	if snapshots == project_snapshots:
		after_restore.call(PackedStringArray([path]))
	var model: SessionModel = model_of.call(session)
	var hunk: Dictionary = hunks[index]
	var line: int = TurnSnapshots.changed_lines(hunk).old_line
	var where := "%s:%d" % [path, line]
	if model and not undo:
		var payload := {"data": data, "path": path, "index": index}
		model.add_notice(I18n.t("Rejected a change in %s.") % where, ChatEntry.NoticeLevel.INFO, [{"id": ACTION_HUNK_UNDO, "label": I18n.t("Undo"), "data": payload}])
	var controller: SessionController = controller_of.call(session)
	if controller:
		if undo:
			controller.note_for_agent("[The user re-applied one of your changes in %s that they had rejected. Re-read the file before editing it again.]" % path)
		else:
			controller.note_for_agent("[The user rejected one of your changes in %s (around line %d of the file before your turn). Re-read the file before editing it again.]" % [path, line])
	if dialog:
		dialog.refresh_file(data, path)
	return ""


## «Deshacer» del aviso de un trozo rechazado.
func undo_hunk(payload: Dictionary) -> void:
	var data: Dictionary = payload.data
	var error := await reject_hunk(data, str(payload.path), int(payload.index), true)
	if not error.is_empty():
		var model: SessionModel = model_of.call(str(data.get("session", primary_session)))
		if model:
			model.add_notice(I18n.t("Could not undo: %s") % error, ChatEntry.NoticeLevel.WARNING)


## Rechaza todos los trozos de un archivo que se pueden rechazar. Devuelve {rejected, skipped}.
func reject_file(data: Dictionary, path: String) -> Dictionary:
	var counts := {"rejected": 0, "skipped": 0}
	var items := await file_hunks(data, path)
	items.reverse()  # de abajo hacia arriba
	for item: Dictionary in items:
		if item.state == REJECTED:
			continue
		if item.stale or not str(item.blocked).is_empty():
			counts.skipped += 1
			continue
		if (await reject_hunk(data, path, int(item.hunk.index))).is_empty():
			counts.rejected += 1
		else:
			counts.skipped += 1
	return counts


func _set_state(data: Dictionary, path: String, index: int, state: String) -> void:
	if not data.has("hunk_state"):
		data["hunk_state"] = {}
	var states: Dictionary = data.hunk_state.get(path, {})
	if state.is_empty():
		states.erase(str(index))
	else:
		states[str(index)] = state
	data.hunk_state[path] = states


func show_diff(data: Dictionary, path: String) -> void:
	var snapshots := _snapshots_of(str(data.get("session", primary_session)))
	var before := await snapshots.text_at(str(data.start), path)
	var full := snapshots.git.root.path_join(path)
	var now := FileAccess.get_file_as_string(full) if FileAccess.file_exists(full) else ""
	diff_dialog.show_diff(path, I18n.t("before the turn"), before, I18n.t("now"), now)


## Los snapshots de una sesión: los del proyecto, o los de su copia (m11-09).
func _snapshots_of(session: String) -> TurnSnapshots:
	var controller: SessionController = controller_of.call(session)
	return controller.snapshots if controller and controller.snapshots else project_snapshots


## Reporte del turno (m11-06) en res://.godot_agent/reports/<fecha>/, y se abre su carpeta.
func save_report(data: Dictionary) -> void:
	var model: SessionModel = model_of.call(str(data.get("session", primary_session)))
	if model == null:
		return
	var collected := TurnReport.collect(model, int(data.get("first_entry", 0)))
	var now := Time.get_datetime_string_from_system()
	var project := str(ProjectSettings.get_setting("application/config/name", EditorContext.project_path().get_file()))
	var path := TurnReport.write(TurnReport.DIR, now.replace(":", "-").replace("T", "_"), "Turn report · %s · %s" % [project, now.replace("T", " ")], collected, data.get("files", []))
	if path.is_empty():
		model.add_notice(I18n.t("Could not save the report in %s.") % TurnReport.DIR, ChatEntry.NoticeLevel.ERROR)
		return
	model.add_notice(I18n.t("Report saved in %s.") % path.get_base_dir())
	OS.shell_show_in_file_manager(ProjectSettings.globalize_path(path))


## Volver atrás todo un turno pisa también lo que vino después en esos archivos: se confirma. Deshacer
## una vuelta atrás (`undo` en data) no pregunta.
func confirm_restore(data: Dictionary) -> void:
	if data.get("undo", false):
		restore(data)
		return
	var confirm := ConfirmationDialog.new()
	confirm.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	confirm.title = I18n.t("Go back to before this turn")
	confirm.dialog_text = I18n.t("The project's files go back to how they were before this turn, including what changed after it (by the agent or by you). Files .gitignore leaves out are not touched. You can undo it from the chat.")
	confirm.ok_button_text = I18n.t("Go back")
	confirm.cancel_button_text = I18n.t("Cancel")
	confirm.confirmed.connect(restore.bind(data))
	confirm.visibility_changed.connect(func() -> void:
		if not confirm.visible:
			EditorWindows.free_later.call_deferred(confirm))
	EditorInterface.get_base_control().add_child(confirm)
	confirm.popup_centered()


## Deja los archivos (todos o `paths`) como en el snapshot `data.start`, recarga lo abierto, avisa en
## el chat de esa sesión (con «Deshacer») y le deja una nota al agente para su próximo turno.
func restore(data: Dictionary, paths: PackedStringArray = []) -> void:
	var session := str(data.get("session", primary_session))
	var model: SessionModel = model_of.call(session)
	var snapshots := _snapshots_of(session)
	var result: Dictionary = await snapshots.restore(session, str(data.start), paths)
	if result.is_empty():
		if model:
			model.add_notice(I18n.t("Could not go back: git failed."), ChatEntry.NoticeLevel.ERROR)
		return
	var changed: PackedStringArray = result.changed
	if snapshots == project_snapshots:  # en una copia no hay nada abierto en el editor
		after_restore.call(changed)
	if paths.size() == 1:
		dialog.mark_reverted(paths[0])
	if changed.is_empty() or model == null:
		return
	var names := ", ".join(changed)
	var undo := {"session": session, "start": result.before, "undo": true}
	model.add_notice(I18n.t("Went back: %s") % names, ChatEntry.NoticeLevel.INFO, [{"id": SessionController.ACTION_TURN_RESTORE, "label": I18n.t("Undo"), "data": undo}])
	var controller: SessionController = controller_of.call(session)
	if controller and not data.get("undo", false):
		controller.note_for_agent("[The user reverted these project files to how they were before one of your earlier turns: %s. Re-read them before editing them again.]" % names)
