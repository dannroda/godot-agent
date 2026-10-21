extends "test_case.gd"
## Checkpoints git del One-shot (spec §10) sobre un repo temporal en user://.

const GitCheckpoints := preload("res://addons/godot_agent/oneshot/git_checkpoints.gd")


func _repo(name: String) -> String:
	var dir := ProjectSettings.globalize_path(temp_dir(name))
	OS.execute("rm", ["-rf", dir])
	DirAccess.make_dir_recursive_absolute(dir + "/project/.godot")
	OS.execute("git", ["-c", "init.defaultBranch=main", "init", "-q", dir])
	_write(dir + "/outside.txt", "fuera del proyecto\n")
	_write(dir + "/project/project.godot", "config_version=5\n")
	_write(dir + "/project/player.gd", "extends Node\n")
	OS.execute("git", ["-C", dir, "add", "-A"])
	OS.execute("git", ["-C", dir, "-c", "user.name=t", "-c", "user.email=t@t", "commit", "-q", "-m", "inicio"])
	return dir


func _write(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()


func _read(path: String) -> String:
	return FileAccess.get_file_as_string(path) if FileAccess.file_exists(path) else "<no existe>"


func test_unavailable() -> void:
	var dir := ProjectSettings.globalize_path(temp_dir("git_none"))
	OS.execute("rm", ["-rf", dir + "/.git"])
	var git := GitCheckpoints.new(dir)
	assert_false(await git.check_available(), "sin repo")
	assert_true(git.last_error.contains("no está en un repo git"), "motivo: " + git.last_error)
	git.git_path = "git-que-no-existe"
	assert_false(await git.check_available(), "sin git")
	assert_true(git.last_error.contains("git no está disponible"), "motivo: " + git.last_error)


func test_branch_checkpoints_restore() -> void:
	var dir := _repo("git_cp")
	var project := dir + "/project"
	var git := GitCheckpoints.new(project)
	assert_true(await git.check_available(), "repo disponible")
	assert_true(await git.is_clean(), "limpio")
	# Cambios del usuario antes de empezar: van como WIP a la rama del agente, no a main.
	_write(project + "/player.gd", "extends Node\n# wip del usuario\n")
	_write(dir + "/outside.txt", "cambio afuera sin commitear\n")
	assert_false(await git.is_clean(), "sucio")
	assert_true(await git.start("20261021-0712"), "start: " + git.last_error)
	assert_eq(git.agent_branch, "agent/20261021-0712", "rama del agente")
	assert_eq(await git.current_branch(), "agent/20261021-0712", "quedó en la rama del agente")
	assert_eq(git.base_branch, "main", "rama base")
	assert_eq(git.checkpoints.size(), 1, "cp1 estado inicial")
	assert_eq(git.checkpoints[0].name, "cp1", "nombre")
	var main_log := await git.run(["log", "--format=%s", "main"])
	assert_eq(main_log.output, "inicio", "main no se tocó")
	var agent_log := await git.run(["log", "--format=%s", "-3"])
	assert_eq(agent_log.output, "cp1: Estado inicial\nWIP antes del one-shot\ninicio", "WIP y cp1 en la rama del agente")

	# Tarea 1 del agente.
	var cp2 := await git.checkpoint("Player con inercia")
	_write(project + "/player.gd", "extends CharacterBody2D\n")
	_write(project + "/bullet.gd", "extends Area2D\n")
	DirAccess.make_dir_recursive_absolute(project + "/scenes")
	_write(project + "/scenes/main.tscn", "[gd_scene format=3]\n")
	_write(project + "/.godot/cache.bin", "cache")
	var cp3 := await git.checkpoint("Disparo")
	assert_eq(cp3.name, "cp3", "cp3")
	_write(project + "/player.gd", "extends CharacterBody2D\n# roto\n")
	_write(project + "/extra.gd", "extends Node\n")
	var summary := await git.changes_summary()
	var paths: Array = summary.files.map(func(file: Dictionary) -> String: return file.path)
	paths.sort()
	assert_eq(paths, ["bullet.gd", "extra.gd", "player.gd", "scenes/main.tscn"], "archivos cambiados desde la base (sin .godot)")
	assert_true(int(summary.added) >= 5, "líneas agregadas: %d" % summary.added)
	assert_eq(await git.base_text("player.gd"), "extends Node", "texto base")

	# Volver a cp2: player.gd como lo dejó el WIP, sin bullet/extra/scenes.
	var changed: Variant = await git.restore(cp2)
	assert_true(changed is PackedStringArray, "restore: " + git.last_error)
	assert_eq(_read(project + "/player.gd"), "extends Node\n# wip del usuario\n", "player.gd en cp2")
	assert_false(FileAccess.file_exists(project + "/bullet.gd"), "bullet.gd no existía en cp2")
	assert_false(FileAccess.file_exists(project + "/extra.gd"), "extra.gd (sin commitear) se borró")
	assert_false(FileAccess.file_exists(project + "/scenes/main.tscn"), "escena nueva borrada")
	assert_true(FileAccess.file_exists(project + "/.godot/cache.bin"), ".godot/ no se toca")
	assert_eq(_read(dir + "/outside.txt"), "cambio afuera sin commitear\n", "lo de fuera del proyecto no se toca")
	assert_true("bullet.gd" in changed and "extra.gd" in changed and "player.gd" in changed, "rutas para recargar: %s" % changed)
	assert_eq(git.checkpoints.size(), 2, "los checkpoints posteriores se descartan")

	# En otra rama no toca nada.
	await git.run(["checkout", "-q", "main"])
	assert_true((await git.checkpoint("x")).is_empty(), "fuera de la rama del agente no commitea")
	assert_true(git.last_error.contains("no es la del agente"), "motivo: " + git.last_error)
	assert_eq(await git.restore(cp2), null, "ni restaura")
	await git.run(["checkout", "-q", git.agent_branch])
	assert_true(await git.accept("Asteroids"), "aceptar")
	var refs := await git.run(["branch", "--format=%(refname:short)"])
	assert_eq(refs.output, "agent/20261021-0712\nmain", "sin merges: las dos ramas siguen")


## Con `.godot/` en el .gitignore (lo normal), `git add` no puede nombrarla ni para excluirla.
func test_gitignored_godot_dir() -> void:
	var dir := _repo("git_ignored")
	var project := dir + "/project"
	_write(project + "/.gitignore", ".godot/\n")
	OS.execute("git", ["-C", dir, "add", "-A"])
	OS.execute("git", ["-C", dir, "-c", "user.name=t", "-c", "user.email=t@t", "commit", "-q", "-m", "gitignore"])
	_write(project + "/.godot/cache.bin", "cache")
	_write(project + "/player.gd", "extends Node2D\n")
	var git := GitCheckpoints.new(project)
	assert_true(await git.start("20261021-0800"), "start con WIP: " + git.last_error)
	var cp2 := await git.checkpoint("Pelota")
	assert_eq(cp2.get("name", ""), "cp2", "cp2: " + git.last_error)
	_write(project + "/ball.gd", "extends Area2D\n")
	var summary := await git.changes_summary()
	assert_eq(summary.files.map(func(file: Dictionary) -> String: return file.path), ["ball.gd", "player.gd"], "resumen")
	assert_true(await git.restore(cp2) is PackedStringArray, "restore: " + git.last_error)
	assert_false(FileAccess.file_exists(project + "/ball.gd"), "ball.gd borrado")
	assert_true(FileAccess.file_exists(project + "/.godot/cache.bin"), ".godot/ intacta")


## Si start() falla después de crear la rama, el usuario vuelve a la suya con sus cambios.
func test_start_failure_restores_branch() -> void:
	var dir := _repo("git_fail")
	var project := dir + "/project"
	_write(project + "/player.gd", "extends Node\n# cambio\n")
	var git := GitCheckpoints.new(project)
	_write(dir + "/.git/hooks/pre-commit", "#!/bin/sh\nexit 1\n")  # --no-verify lo saltea: se fuerza otro error
	OS.execute("chmod", ["-w", dir + "/.git/objects"])
	var ok := await git.start("20261021-0900")
	OS.execute("chmod", ["+w", dir + "/.git/objects"])
	assert_false(ok, "start falla sin poder escribir objetos")
	assert_true(git.last_error.contains("git"), "motivo: " + git.last_error)
	assert_eq(await git.current_branch(), "main", "volvió a main")
	var branches := await git.run(["branch", "--format=%(refname:short)"])
	assert_eq(branches.output, "main", "sin rama del agente")
	assert_eq(_read(project + "/player.gd"), "extends Node\n# cambio\n", "los cambios siguen")
