extends "test_case.gd"
## Snapshots por turno (m11-01, m11-02) sobre un repo de git temporal: qué cambió un turno y volver
## atrás un archivo o todo, sin tocar la rama, el index ni HEAD del usuario.

const TurnSnapshots := preload("res://addons/godot_agent/session/turn_snapshots.gd")
const AddonUpdater := preload("res://addons/godot_agent/core/addon_updater.gd")
const SessionController := preload("res://addons/godot_agent/session/session_controller.gd")
const SessionModel := preload("res://addons/godot_agent/session/session_model.gd")
const AgentLog := preload("res://addons/godot_agent/core/agent_log.gd")


func test_parse_diff() -> void:
	var parsed := TurnSnapshots.parse_diff("3\t1\tplayer.gd\n-\t-\ticon.png\n0\t5\told.gd", "M\tplayer.gd\nA\ticon.png\nD\told.gd")
	assert_eq(parsed.files.map(func(f: Dictionary) -> String: return "%s %s +%d -%d" % [f.status, f.path, f.added, f.removed]),
		["M player.gd +3 -1", "A icon.png +0 -0", "D old.gd +0 -5"], "estado y líneas; binarios sin líneas")
	assert_eq([parsed.added, parsed.removed], [3, 6], "totales")


func test_snapshots_in_a_repo() -> void:
	if OS.execute("git", ["--version"]) != 0:
		return
	var root := ProjectSettings.globalize_path("user://unit_tests/turn_snapshots")
	AddonUpdater._remove_tree(root)
	DirAccess.make_dir_recursive_absolute(root)
	_write(root.path_join("a.gd"), "a1\n")
	_write(root.path_join("keep.gd"), "keep\n")
	_write(root.path_join(".gitignore"), "ignored.txt\n")
	for args: Array in [["init", "-q"], ["-c", "user.name=t", "-c", "user.email=t@t", "add", "-A"], ["-c", "user.name=t", "-c", "user.email=t@t", "commit", "-qm", "base"]]:
		OS.execute("git", PackedStringArray(["-C", root]) + PackedStringArray(args))
	var head_before := _git(root, ["rev-parse", "HEAD"])
	_write(root.path_join("staged.gd"), "user staged this\n")
	_git(root, ["add", "staged.gd"])
	var snapshots := TurnSnapshots.new(root)
	assert_true(await snapshots.setup(), "git disponible")
	var start := await snapshots.take("s1")
	assert_false(start.is_empty(), "snapshot al empezar")

	# El turno: cambia a.gd, crea b.gd, borra keep.gd y algo ignorado.
	_write(root.path_join("a.gd"), "a2\n")
	_write(root.path_join("b.gd"), "new\n")
	_write(root.path_join("ignored.txt"), "x")
	DirAccess.remove_absolute(root.path_join("keep.gd"))
	var end := await snapshots.take("s1")
	var changes: Dictionary = await snapshots.diff(start, end)
	var summary: Array = changes.files.map(func(f: Dictionary) -> String: return "%s %s" % [f.status, f.path])
	summary.sort()
	assert_eq(summary, ["A b.gd", "D keep.gd", "M a.gd"], "lo que cambió el turno, sin lo ignorado")
	assert_eq(await snapshots.text_at(start, "a.gd"), "a1", "el texto de antes")

	var one: Dictionary = await snapshots.restore("s1", start, PackedStringArray(["a.gd"]))
	assert_eq(Array(one.changed), ["a.gd"], "volver un archivo")
	assert_eq(FileAccess.get_file_as_string(root.path_join("a.gd")), "a1\n", "a.gd como antes")
	assert_true(FileAccess.file_exists(root.path_join("b.gd")), "lo demás queda")

	var all: Dictionary = await snapshots.restore("s1", start)
	var restored := Array(all.changed)
	restored.sort()
	assert_eq(restored, ["b.gd", "keep.gd"], "volver todo lo que quedaba")
	assert_false(FileAccess.file_exists(root.path_join("b.gd")), "lo creado se borra")
	assert_eq(FileAccess.get_file_as_string(root.path_join("keep.gd")), "keep\n", "lo borrado vuelve")
	assert_true(FileAccess.file_exists(root.path_join("ignored.txt")), "lo ignorado no se toca")
	await snapshots.restore("s1", all.before)
	assert_eq(FileAccess.get_file_as_string(root.path_join("b.gd")), "new\n", "volver atrás se deshace con el snapshot de antes")
	assert_eq(_git(root, ["rev-parse", "HEAD"]), head_before, "HEAD no se movió")
	assert_eq(_git(root, ["diff", "--cached", "--name-only"]), "staged.gd", "el index del usuario sigue igual")
	assert_true(_git(root, ["for-each-ref", "refs/godot-agent/turns/s1/"]).split("\n", false).size() >= 3, "snapshots en sus refs")

	# El aviso de fin de turno (m11-02): los archivos y las acciones con sus snapshots.
	var controller := SessionController.new()
	controller.setup(SessionModel.new(), AgentLog.new(), root)
	controller.snapshots = snapshots
	controller.session_key = "s2"
	var turn_start := await snapshots.take("s2")
	_write(root.path_join("c.gd"), "c\n")
	await controller.call(&"_report_turn_changes", turn_start)
	var notice: Variant = controller.model.entries()[-1]
	assert_true(str(notice.text).contains("c.gd"), "aviso con el archivo: %s" % notice.text)
	assert_eq(notice.actions.map(func(action: Dictionary) -> String: return action.id), [SessionController.ACTION_TURN_CHANGES, SessionController.ACTION_TURN_RESTORE], "ver cambios y volver atrás")
	assert_eq([notice.actions[0].data.session, notice.actions[0].data.start], ["s2", turn_start], "con la sesión y el snapshot del inicio")
	var count := controller.model.entries().size()
	await controller.call(&"_report_turn_changes", await snapshots.take("s2"))
	assert_eq(controller.model.entries().size(), count, "un turno sin cambios no avisa")


func _git(root: String, args: Array) -> String:
	var output := []
	OS.execute("git", PackedStringArray(["-C", root]) + PackedStringArray(args), output, true)
	return "".join(output).strip_edges()


func _write(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()
