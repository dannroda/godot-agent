extends "test_case.gd"
## Sesión en una copia aparte (m11-09): crear el worktree, commitear lo del agente, aplicarlo al
## proyecto sin merge y descartar la copia.

const WorktreeSession := preload("res://addons/godot_agent/session/worktree_session.gd")
const AddonUpdater := preload("res://addons/godot_agent/core/addon_updater.gd")


func test_copy_lifecycle() -> void:
	if OS.execute("git", ["--version"]) != 0:
		return
	var base := ProjectSettings.globalize_path("user://unit_tests/worktree")
	AddonUpdater._remove_tree(base)
	var repo := base.path_join("repo")
	var project := repo.path_join("game")
	DirAccess.make_dir_recursive_absolute(project)
	_write(project.path_join("a.gd"), "a1\n")
	_write(repo.path_join("README.md"), "outside the project\n")
	for args: Array in [["init", "-q"], ["-c", "user.name=t", "-c", "user.email=t@t", "add", "-A"], ["-c", "user.name=t", "-c", "user.email=t@t", "commit", "-qm", "base"]]:
		OS.execute("git", PackedStringArray(["-C", repo]) + PackedStringArray(args))
	var session := WorktreeSession.new(project)
	assert_true(await session.create("t1"), "crea la copia: %s" % session.last_error)
	assert_eq(session.info.dir, base.path_join("repo.godot-agent-copies/t1"), "al lado del repo")
	assert_eq(session.info.project, base.path_join("repo.godot-agent-copies/t1/game"), "el proyecto dentro de la copia")
	assert_true(FileAccess.file_exists(session.info.project.path_join("a.gd")), "con los archivos de HEAD")

	# El agente trabaja en la copia.
	_write(session.info.project.path_join("a.gd"), "a2\n")
	_write(session.info.project.path_join("b.gd"), "new\n")
	assert_eq(FileAccess.get_file_as_string(project.path_join("a.gd")), "a1\n", "el proyecto no cambia")
	var changed := Array(await session.commit_changes())
	changed.sort()
	assert_eq(changed, ["a.gd", "b.gd"], "lo que cambió, relativo al proyecto")
	assert_eq(await session.apply_to_project(), "", "se aplica")
	assert_eq(FileAccess.get_file_as_string(project.path_join("a.gd")), "a2\n", "cambio aplicado")
	assert_true(FileAccess.file_exists(project.path_join("b.gd")), "archivo nuevo aplicado")
	assert_eq(_git(repo, ["rev-parse", "--abbrev-ref", "HEAD"]) in ["master", "main"], true, "sigue en su rama")
	assert_true(_git(repo, ["status", "--porcelain"]).contains("a.gd"), "como cambios sin commitear")
	await session.remove(true)
	assert_false(DirAccess.dir_exists_absolute(session.info.dir), "la copia se borra")
	assert_eq(_git(repo, ["branch", "--list", session.info.branch]), "", "y su rama")


func _git(root: String, args: Array) -> String:
	var output := []
	OS.execute("git", PackedStringArray(["-C", root]) + PackedStringArray(args), output, true)
	return "".join(output).strip_edges()


func _write(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()
