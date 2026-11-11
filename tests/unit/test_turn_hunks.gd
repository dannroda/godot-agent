extends "test_case.gd"
## Rechazar los cambios de un turno por trozo (m11-34) sobre un repo de git temporal: el trozo se
## deshace aunque el archivo haya cambiado en otra parte, no pisa lo que cambió en esas líneas, se
## puede volver a aplicar, y peek() cuenta sin dejar snapshots. También con el proyecto en una
## subcarpeta del repo (como una copia aparte o un monorepo).

const TurnSnapshots := preload("res://addons/godot_agent/session/turn_snapshots.gd")
const AddonUpdater := preload("res://addons/godot_agent/core/addon_updater.gd")

const BEFORE := "func a():\n\treturn 1\n\n\nfunc b():\n\treturn 2\n\n\n\n\nfunc c():\n\treturn 3\n"
const AFTER := "func a():\n\treturn 10\n\n\nfunc b():\n\treturn 2\n\n\n\n\nfunc c():\n\treturn 30\n"


func test_parse_hunks() -> void:
	var diff := "diff --git a/p.gd b/p.gd\nindex 1..2 100644\n--- a/p.gd\n+++ b/p.gd\n@@ -1,3 +1,3 @@\n x\n-a\n+b\n \n@@ -10 +10,2 @@ func c():\n-c\n+d\n+e\n"
	var hunks := TurnSnapshots.parse_hunks(diff, "p.gd")
	assert_eq(hunks.size(), 2)
	assert_eq([hunks[0].old_start, hunks[0].old_count, hunks[0].new_start, hunks[0].new_count], [1, 3, 1, 3])
	assert_eq([hunks[1].old_start, hunks[1].old_count, hunks[1].new_count], [10, 1, 2], "un rango sin coma cuenta 1")
	assert_eq(hunks[0].patch, "diff --git a/p.gd b/p.gd\nindex 1..2 100644\n--- a/p.gd\n+++ b/p.gd\n@@ -1,3 +1,3 @@\n x\n-a\n+b\n \n",
		"el parche de un trozo: el encabezado y ese trozo, con la línea de contexto vacía del final")
	assert_true(str(hunks[1].patch).begins_with("diff --git") and not str(hunks[1].patch).contains("-a\n"), "el segundo no lleva el primero")


func test_reject_hunks_in_repo_root() -> void:
	await _reject_hunks("")


func test_reject_hunks_in_subfolder() -> void:
	await _reject_hunks("game/")


func _reject_hunks(sub: String) -> void:
	if OS.execute("git", ["--version"]) != 0:
		return
	var repo := ProjectSettings.globalize_path("user://unit_tests/turn_hunks")
	AddonUpdater._remove_tree(repo)
	var root := repo.path_join(sub)
	DirAccess.make_dir_recursive_absolute(root)
	_write(root.path_join("p.gd"), BEFORE)
	_write(root.path_join("other.gd"), "x\n")
	for args: Array in [["init", "-q"], ["-c", "user.name=t", "-c", "user.email=t@t", "add", "-A"], ["-c", "user.name=t", "-c", "user.email=t@t", "commit", "-qm", "base"]]:
		OS.execute("git", PackedStringArray(["-C", repo]) + PackedStringArray(args))
	var snapshots := TurnSnapshots.new(root)
	assert_true(await snapshots.setup(), "git disponible")
	var start := await snapshots.take("s1")
	_write(root.path_join("p.gd"), AFTER)
	_write(root.path_join("new.gd"), "created\n")
	var end := await snapshots.take("s1")
	var refs_before := _git(repo, ["for-each-ref", "refs/godot-agent/"]).split("\n", false).size()

	var hunks := await snapshots.hunks(start, end, "p.gd")
	assert_eq(hunks.size(), 2, "dos trozos: return 10 y return 30 (%s)" % sub)
	# Después del turno el usuario edita otra parte del archivo: el trozo 1 se rechaza igual.
	_write(root.path_join("p.gd"), "# user note\n" + AFTER)
	assert_true(await snapshots.can_apply(hunks[1]), "se puede rechazar con una edición en otra parte")
	var rejected: Dictionary = await snapshots.apply_hunk(hunks[1])
	assert_true(rejected.ok, "rechazado: %s" % rejected.error)
	assert_eq(FileAccess.get_file_as_string(root.path_join("p.gd")), "# user note\n" + AFTER.replace("return 30", "return 3"),
		"solo ese trozo vuelve; la nota del usuario y el otro trozo quedan")
	# Deshacer el rechazo: vuelve a aplicarlo.
	assert_false(await snapshots.can_apply(hunks[1]), "ya rechazado no se rechaza de nuevo")
	var undone: Dictionary = await snapshots.apply_hunk(hunks[1], true)
	assert_true(undone.ok, "deshacer el rechazo: %s" % undone.error)
	assert_eq(FileAccess.get_file_as_string(root.path_join("p.gd")), "# user note\n" + AFTER)
	# Stale: el usuario cambió esas mismas líneas; no se pisa nada.
	var stale_text := "# user note\n" + AFTER.replace("return 10", "return 99")
	_write(root.path_join("p.gd"), stale_text)
	assert_false(await snapshots.can_apply(hunks[0]), "esas líneas cambiaron después: no se puede")
	var refused: Dictionary = await snapshots.apply_hunk(hunks[0])
	assert_false(refused.ok, "rechazar un trozo stale falla")
	assert_eq(FileAccess.get_file_as_string(root.path_join("p.gd")), stale_text, "y no escribió nada")
	# Un archivo creado en el turno: su único trozo lo borra, y deshacerlo lo vuelve a crear.
	var created := await snapshots.hunks(start, end, "new.gd")
	assert_eq(created.size(), 1)
	assert_true((await snapshots.apply_hunk(created[0])).ok, "rechazar un archivo nuevo")
	assert_false(FileAccess.file_exists(root.path_join("new.gd")), "lo borra")
	assert_true((await snapshots.apply_hunk(created[0], true)).ok)
	assert_eq(FileAccess.get_file_as_string(root.path_join("new.gd")), "created\n", "y deshacerlo lo devuelve")

	# peek: lo que cambió desde el principio del turno, sin commits ni refs nuevos.
	_write(root.path_join("other.gd"), "x\ny\n")
	var peeked: Dictionary = await snapshots.peek("s1", start)
	var summary: Array = peeked.files.map(func(f: Dictionary) -> String: return "%s %s" % [f.status, f.path])
	summary.sort()
	assert_eq(summary, ["A new.gd", "M other.gd", "M p.gd"], "peek ve lo que hay ahora")
	assert_eq(_git(repo, ["for-each-ref", "refs/godot-agent/"]).split("\n", false).size(), refs_before, "peek no deja refs")
	var next := await snapshots.take("s1")
	var since_end: Dictionary = await snapshots.diff(end, next)
	assert_eq(since_end.files.size(), 2, "el index de take() no lo tocó peek: ve p.gd y other.gd desde el fin del turno")


func test_peek_and_take_are_serialized() -> void:
	if OS.execute("git", ["--version"]) != 0:
		return
	var repo := ProjectSettings.globalize_path("user://unit_tests/turn_hunks_lock")
	AddonUpdater._remove_tree(repo)
	DirAccess.make_dir_recursive_absolute(repo)
	_write(repo.path_join("a.gd"), "1\n")
	for args: Array in [["init", "-q"], ["-c", "user.name=t", "-c", "user.email=t@t", "add", "-A"], ["-c", "user.name=t", "-c", "user.email=t@t", "commit", "-qm", "base"]]:
		OS.execute("git", PackedStringArray(["-C", repo]) + PackedStringArray(args))
	var snapshots := TurnSnapshots.new(repo)
	await snapshots.setup()
	var start := await snapshots.take("s1")
	_write(repo.path_join("a.gd"), "2\n")
	var order: Array[String] = []
	var peeking := func() -> void:
		var result: Dictionary = await snapshots.peek("s1", start)
		order.append("peek %d" % result.files.size())
	var taking := func() -> void:
		var sha := await snapshots.take("s1")
		order.append("take %s" % (not sha.is_empty()))
	peeking.call()  # sin await: arranca y queda esperando a git
	assert_true(snapshots.get(&"_busy"), "peek tiene el lock")
	await taking.call()
	assert_eq(order, ["peek 1", "take true"], "take espera a que peek termine")
	assert_false(snapshots.get(&"_busy"))


func _git(root: String, args: Array) -> String:
	var output := []
	OS.execute("git", PackedStringArray(["-C", root]) + PackedStringArray(args), output, true)
	return "".join(output).strip_edges()


func _write(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()


func test_changed_lines() -> void:
	var hunk := TurnSnapshots.parse_hunks("@@ -9,4 +9,4 @@\n \n \n func c():\n-\treturn 3\n+\treturn 30\n")[0]
	assert_eq(TurnSnapshots.changed_lines(hunk), {"old_line": 12, "new_first": 12, "new_last": 12}, "sin las líneas de contexto")
	var removed := TurnSnapshots.parse_hunks("@@ -4,3 +4,2 @@\n a\n-b\n c\n")[0]
	assert_eq(TurnSnapshots.changed_lines(removed), {"old_line": 5, "new_first": 5, "new_last": 4}, "solo borra")
	var created := TurnSnapshots.parse_hunks("@@ -0,0 +1,2 @@\n+x\n+y\n")[0]
	assert_eq(TurnSnapshots.changed_lines(created), {"old_line": 1, "new_first": 1, "new_last": 2}, "archivo nuevo")
