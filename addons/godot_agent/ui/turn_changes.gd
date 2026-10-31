@tool
extends RefCounted
## Lo que cambió un turno (m11-01, m11-02, m11-06): ver el diff de un archivo, volver atrás todo el
## turno o un archivo (con confirmación y «Deshacer»), y guardar el reporte. Lo arma el plugin, que
## le pasa los diálogos y cómo encontrar la sesión de cada aviso (`data.session`).

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
