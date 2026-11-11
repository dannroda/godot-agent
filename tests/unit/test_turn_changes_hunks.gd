extends "test_case.gd"
## Cambios del turno por trozo en el diálogo (m11-34): conservar, rechazar y deshacer, y los casos
## borde: un trozo cuyas líneas cambiaron después, un archivo con cambios sin guardar en el editor,
## uno que otra sesión está editando, el turno todavía corriendo y una sesión en una copia aparte.

const TurnSnapshots := preload("res://addons/godot_agent/session/turn_snapshots.gd")
const TurnChanges := preload("res://addons/godot_agent/ui/turn_changes.gd")
const TurnChangesDialog := preload("res://addons/godot_agent/ui/turn_changes_dialog.gd")
const SessionController := preload("res://addons/godot_agent/session/session_controller.gd")
const SessionModel := preload("res://addons/godot_agent/session/session_model.gd")
const AgentLog := preload("res://addons/godot_agent/core/agent_log.gd")
const AddonUpdater := preload("res://addons/godot_agent/core/addon_updater.gd")

const BEFORE := "func a():\n\treturn 1\n\n\nfunc b():\n\treturn 2\n\n\n\n\nfunc c():\n\treturn 3\n"
const AFTER := "func a():\n\treturn 10\n\n\nfunc b():\n\treturn 2\n\n\n\n\nfunc c():\n\treturn 30\n"

var _root := ""
var _model: SessionModel
var _controller: SessionController
var _unsaved: Dictionary = {}
var _holders: Dictionary = {}


func test_keep_reject_undo_and_guards() -> void:
	if OS.execute("git", ["--version"]) != 0:
		return
	var setup := await _turn("turn_changes_hunks")
	var changes: TurnChanges = setup.changes
	var data: Dictionary = setup.data
	var dialog := TurnChangesDialog.new()
	changes.dialog = dialog
	dialog.show_turn(data)
	dialog.hide()

	var items := await changes.file_hunks(data, "p.gd")
	assert_eq(items.size(), 2, "dos trozos")
	assert_eq([items[0].state, items[0].stale, items[0].blocked], ["", false, ""], "sin tocar, se puede rechazar")

	# Conservar: una marca, el archivo no cambia.
	changes.keep_hunk(data, "p.gd", 0)
	assert_eq(data.hunk_state, {"p.gd": {"0": "kept"}})
	assert_eq(_read("p.gd"), AFTER, "conservar no escribe")

	# Rechazar con una edición posterior del usuario en otra parte del archivo.
	_write("p.gd", "# note\n" + AFTER)
	assert_eq(await changes.reject_hunk(data, "p.gd", 1), "", "rechazado")
	assert_eq(_read("p.gd"), "# note\n" + AFTER.replace("return 30", "return 3"), "solo ese trozo; la nota queda")
	assert_eq(data.hunk_state["p.gd"]["1"], "rejected")
	var notice: Variant = _model.entries()[-1]
	assert_true(str(notice.text).contains("p.gd:12"), "el aviso dice dónde: %s" % notice.text)
	assert_eq(notice.actions[0].id, TurnChanges.ACTION_HUNK_UNDO, "con Deshacer")
	assert_true(str(_controller.get(&"_note_for_agent")).contains("rejected one of your changes in p.gd"), "nota para el agente")

	# Deshacer desde el aviso del chat.
	await changes.undo_hunk(notice.actions[0].data)
	assert_eq(_read("p.gd"), "# note\n" + AFTER, "deshacer lo vuelve a aplicar")
	assert_false(data.hunk_state["p.gd"].has("1"), "y le saca la marca")

	# Stale: el usuario cambió esas mismas líneas.
	_write("p.gd", "# note\n" + AFTER.replace("return 10", "return 99"))
	items = await changes.file_hunks(data, "p.gd")
	assert_true(items[0].stale, "esas líneas cambiaron después")
	assert_false(items[1].stale)
	var refused := await changes.reject_hunk(data, "p.gd", 0)
	assert_true(refused.contains("changed after the turn"), refused)
	assert_true(_read("p.gd").contains("return 99"), "no pisó nada")
	dialog.set_hunks(data, "p.gd", items)  # no está abierto: no hace nada
	(dialog.get(&"_expanded") as Dictionary)["p.gd"] = []
	dialog.set_hunks(data, "p.gd", items)
	var card0 := dialog.find_child("Hunk0", true, false)
	var card1 := dialog.find_child("Hunk1", true, false)
	assert_true((card0.find_child("Reject", true, false) as Button).disabled, "el botón del trozo stale está deshabilitado")
	assert_eq((card0.find_child("State", true, false) as Label).text, "Kept · changed afterwards")
	assert_false((card1.find_child("Reject", true, false) as Button).disabled)

	# Un archivo con cambios sin guardar en el editor no se toca.
	_unsaved["res://p.gd"] = true
	items = await changes.file_hunks(data, "p.gd")
	assert_true(str(items[1].blocked).contains("unsaved changes"), str(items[1].blocked))
	assert_true((await changes.reject_hunk(data, "p.gd", 1)).contains("unsaved changes"))
	assert_true(_read("p.gd").contains("return 30"), "no escribió")
	dialog.set_hunks(data, "p.gd", items)
	assert_true((dialog.find_child("Hunk1", true, false).find_child("Reject", true, false) as Button).disabled, "Rechazar deshabilitado")
	assert_true((dialog.find_child("RejectAll", true, false) as Button).disabled)
	_unsaved.clear()

	# Uno que otra sesión está editando en su turno, tampoco.
	_holders["res://p.gd"] = "Session 2"
	assert_eq(await changes.reject_hunk(data, "p.gd", 1), "«Session 2» is editing it in its turn.")
	assert_true(_read("p.gd").contains("return 30"), "no escribió")
	_holders.clear()

	# Rechazar todo: los que se puede (el stale queda).
	var counts := await changes.reject_file(data, "p.gd")
	assert_eq(counts, {"rejected": 1, "skipped": 1})
	assert_true(_read("p.gd").contains("return 3\n") and _read("p.gd").contains("return 99"))

	# Durante el turno se ve, pero no se toca.
	var live := data.duplicate()
	live["live"] = true
	assert_eq(await changes.reject_hunk(live, "p.gd", 0), "The turn is still running.")
	dialog.free()


func test_copy_session_uses_its_own_snapshots() -> void:
	if OS.execute("git", ["--version"]) != 0:
		return
	var main := await _turn("turn_changes_main")
	var main_root := _root
	var copy := await _turn("turn_changes_copy")
	var changes: TurnChanges = main.changes
	# La sesión "copy" trabaja en su carpeta: sus trozos y rechazos van ahí, sin las guardas del
	# editor (en la copia no hay nada abierto ni reclamado acá).
	var copy_controller: SessionController = copy.controller
	changes.controller_of = func(session: String) -> SessionController: return copy_controller if session == "copy" else null
	var data: Dictionary = copy.data.duplicate(true)
	data.session = "copy"
	_unsaved["res://p.gd"] = true
	_holders["res://p.gd"] = "Session 2"
	assert_eq(await changes.reject_hunk(data, "p.gd", 0), "", "en la copia las guardas del editor no aplican")
	assert_true(FileAccess.get_file_as_string(_root.path_join("p.gd")).contains("return 1\n"), "rechazado en la copia")
	assert_true(FileAccess.get_file_as_string(main_root.path_join("p.gd")).contains("return 10"), "el proyecto no se tocó")
	_unsaved.clear()
	_holders.clear()


func test_scene_by_node() -> void:
	if OS.execute("git", ["--version"]) != 0:
		return
	var setup := await _turn("turn_changes_scene")
	var changes: TurnChanges = setup.changes
	var data: Dictionary = setup.data
	var scene_before := "[gd_scene format=3]\n\n[node name=\"Main\" type=\"Node2D\" unique_id=1]\n\n[node name=\"Player\" type=\"Node2D\" parent=\".\" unique_id=2]\nposition = Vector2(1, 2)\n"
	var scene_after := "[gd_scene format=3]\n\n[node name=\"Main\" type=\"Node2D\" unique_id=1]\n\n[node name=\"Player\" type=\"Node2D\" parent=\".\" unique_id=2]\nposition = Vector2(5, 2)\n\n[node name=\"Coin\" type=\"Area2D\" parent=\".\" unique_id=3]\n"
	# Otro turno, ahora con la escena.
	_write("main.tscn", scene_before)
	var snapshots: TurnSnapshots = changes.project_snapshots
	data.start = await snapshots.take("s1")
	_write("main.tscn", scene_after)
	data.end = await snapshots.take("s1")
	var items := await changes.file_hunks(data, "main.tscn")
	assert_eq(items.map(func(item: Dictionary) -> String: return str(item.scene.label)), ["+ Coin", "~ Player · position"], "por nodo")
	assert_eq(await changes.reject_hunk(data, "main.tscn", 1), "", "rechazar la posición")
	assert_true(_read("main.tscn").contains("Vector2(1, 2)") and _read("main.tscn").contains("Coin"), "solo la posición")
	assert_true(str(_model.entries()[-1].text).contains("main.tscn (Player · position)"), str(_model.entries()[-1].text))
	assert_eq(await changes.reject_hunk(data, "main.tscn", 0), "", "rechazar el nodo agregado")
	assert_false(_read("main.tscn").contains("Coin"), "Coin se fue")
	await changes.undo_hunk(_model.entries()[-1].actions[0].data)
	assert_true(_read("main.tscn").contains("Coin"), "deshacer lo devuelve")
	# Stale y sin guardar.
	_write("main.tscn", _read("main.tscn").replace("Vector2(1, 2)", "Vector2(9, 9)"))
	items = await changes.file_hunks(data, "main.tscn")
	assert_true(items[1].stale and items[1].state == "rejected", "deshacer la posición ya no se puede: cambió después")
	assert_true((await changes.reject_hunk(data, "main.tscn", 1, true)).contains("changed in the scene after the turn"))
	_unsaved["res://main.tscn"] = true
	assert_true((await changes.reject_hunk(data, "main.tscn", 0)).contains("unsaved changes"), "una escena abierta sin guardar no se toca")
	_unsaved.clear()


## Un repo temporal con un turno que cambió p.gd, y un TurnChanges para él.
func _turn(name: String) -> Dictionary:
	_root = ProjectSettings.globalize_path("user://unit_tests/" + name)
	AddonUpdater._remove_tree(_root)
	DirAccess.make_dir_recursive_absolute(_root)
	_write("p.gd", BEFORE)
	for args: Array in [["init", "-q"], ["-c", "user.name=t", "-c", "user.email=t@t", "add", "-A"], ["-c", "user.name=t", "-c", "user.email=t@t", "commit", "-qm", "base"]]:
		OS.execute("git", PackedStringArray(["-C", _root]) + PackedStringArray(args))
	var snapshots := TurnSnapshots.new(_root)
	await snapshots.setup()
	var start := await snapshots.take("s1")
	_write("p.gd", AFTER)
	var end := await snapshots.take("s1")
	_model = SessionModel.new()
	_controller = SessionController.new()
	_controller.setup(_model, AgentLog.new(), _root)
	_controller.snapshots = snapshots
	var changes := TurnChanges.new()
	changes.project_snapshots = snapshots
	changes.primary_session = "s1"
	var model := _model
	var controller := _controller
	changes.model_of = func(_session: String) -> SessionModel: return model
	changes.controller_of = func(_session: String) -> SessionController: return controller
	changes.after_restore = func(_paths: PackedStringArray) -> void: pass
	changes.unsaved_of = func(res_path: String) -> bool: return _unsaved.has(res_path)
	changes.holder_of = func(_session: String, res_path: String) -> String: return str(_holders.get(res_path, ""))
	var data := {"session": "s1", "start": start, "end": end, "files": [{"path": "p.gd", "status": "M", "added": 2, "removed": 2}]}
	return {"changes": changes, "data": data, "controller": controller}


func _read(path: String) -> String:
	return FileAccess.get_file_as_string(_root.path_join(path))


func _write(path: String, text: String) -> void:
	var file := FileAccess.open(_root.path_join(path), FileAccess.WRITE)
	file.store_string(text)
	file.close()
