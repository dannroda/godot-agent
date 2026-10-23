extends "test_case.gd"
## Foto de archivos de Remote Control (m7-22).

const RemoteWatch := preload("res://addons/godot_agent/session/remote_watch.gd")


func _project(name: String) -> String:
	var dir := ProjectSettings.globalize_path(temp_dir(name))
	OS.execute("rm", ["-rf", dir])
	DirAccess.make_dir_recursive_absolute(dir + "/scripts")
	DirAccess.make_dir_recursive_absolute(dir + "/.godot")
	_write(dir + "/scripts/player.gd", "extends Node\n")
	_write(dir + "/main.tscn", "[gd_scene format=3]\n")
	_write(dir + "/icon.png", "PNG")
	return dir


func _write(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()


func _summary(changes: Array) -> Array:
	return changes.map(func(change: Dictionary) -> String: return "%s %s" % [RemoteWatch.FileChange.keys()[change.change], change.path])


func test_poll_reports_changes() -> void:
	var dir := _project("remote_watch_poll")
	var watch := RemoteWatch.new()
	watch.ignored = ["harness.tres"]
	watch.start(dir)
	assert_eq(watch.poll().size(), 0, "sin cambios")
	_write(dir + "/harness.tres", "config")
	_write(dir + "/scripts/player.gd", "extends Node2D\n")
	_write(dir + "/scripts/enemy.gd", "extends Node\n")
	DirAccess.remove_absolute(dir + "/main.tscn")
	_write(dir + "/.godot/cache.bin", "x")
	_write(dir + "/scripts/enemy.gd.uid", "uid://x")
	var changes := watch.poll()
	assert_eq(_summary(changes), ["DELETED res://main.tscn", "CREATED res://scripts/enemy.gd", "MODIFIED res://scripts/player.gd"].map(func(s: String) -> String: return s), "cambios (sin .godot, .uid ni los ignorados)")
	var by_path := {}
	for change: Dictionary in changes:
		by_path[change.path] = change
	assert_eq(by_path["res://scripts/player.gd"].before, "extends Node\n", "texto de antes del modificado")
	assert_eq(by_path["res://main.tscn"].before, "[gd_scene format=3]\n", "texto de antes del borrado")
	assert_eq(watch.poll().size(), 0, "la foto quedó al día")


func test_restore() -> void:
	var dir := _project("remote_watch_restore")
	var watch := RemoteWatch.new()
	watch.start(dir)
	_write(dir + "/scripts/player.gd", "roto\n")
	_write(dir + "/nuevo.gd", "x\n")
	DirAccess.remove_absolute(dir + "/main.tscn")
	var changes := watch.poll()
	assert_true(RemoteWatch.can_restore(changes), "se puede deshacer")
	assert_eq(watch.restore(changes).size(), 0, "sin fallas")
	assert_eq(FileAccess.get_file_as_string(dir + "/scripts/player.gd"), "extends Node\n", "modificado vuelve")
	assert_eq(FileAccess.get_file_as_string(dir + "/main.tscn"), "[gd_scene format=3]\n", "borrado vuelve")
	assert_false(FileAccess.file_exists(dir + "/nuevo.gd"), "creado se borra")
	assert_eq(watch.poll().size(), 0, "deshacer no se reporta como cambio")
	# Un binario modificado no tiene texto de antes: no se puede deshacer.
	_write(dir + "/icon.png", "PNG2")
	assert_false(RemoteWatch.can_restore(watch.poll()), "binario sin texto de antes")


func test_rebase_and_saved() -> void:
	var dir := _project("remote_watch_rebase")
	var watch := RemoteWatch.new()
	watch.start(dir)
	_write(dir + "/scripts/player.gd", "turno del dock\n")
	watch.rebase()
	assert_eq(watch.poll().size(), 0, "rebase absorbe lo del turno del dock")
	watch.root = dir
	_write(dir + "/main.tscn", "guardado en el editor\n")
	# note_saved recibe rutas res://: acá se simula con la ruta relativa a la carpeta del test.
	watch.note_saved("res://main.tscn")
	assert_eq(watch.poll().size(), 0, "lo guardado en el editor no cuenta")
	watch.stop()
	assert_false(watch.is_active(), "apagado")
	assert_eq(watch.poll().size(), 0, "apagado no reporta")


func test_merge() -> void:
	var first: Array[Dictionary] = [
		{"path": "res://a.gd", "change": RemoteWatch.FileChange.MODIFIED, "before": "uno"},
		{"path": "res://b.gd", "change": RemoteWatch.FileChange.CREATED, "before": null},
	]
	var second: Array[Dictionary] = [
		{"path": "res://a.gd", "change": RemoteWatch.FileChange.MODIFIED, "before": "dos"},
		{"path": "res://b.gd", "change": RemoteWatch.FileChange.DELETED, "before": "x"},
		{"path": "res://c.gd", "change": RemoteWatch.FileChange.DELETED, "before": "c"},
	]
	var merged := RemoteWatch.merge(first, second)
	assert_eq(_summary(merged), ["MODIFIED res://a.gd", "DELETED res://c.gd"], "creado y borrado se cancelan")
	assert_eq(merged[0].before, "uno", "queda el texto de antes de la primera tanda")


func test_describe() -> void:
	var RemoteActivity := load("res://addons/godot_agent/session/remote_activity.gd")
	var changes: Array[Dictionary] = []
	for i in 8:
		changes.append({"path": "res://s%d.gd" % i, "change": RemoteWatch.FileChange.MODIFIED, "before": ""})
	changes.append({"path": "res://n.gd", "change": RemoteWatch.FileChange.CREATED, "before": null})
	var text: String = RemoteActivity.describe(changes)
	assert_eq(text, "From Remote Control: modified s0.gd, s1.gd, s2.gd, s3.gd, s4.gd, s5.gd and 2 more · created n.gd", "texto")
