extends "test_case.gd"
## El agente corre Godot con el binario del editor (D43): entorno, shim al frente del PATH y que
## el shim lance de verdad este binario.

const EditorBinary := preload("res://addons/godot_agent/transport/editor_binary.gd")


func test_child_env() -> void:
	var env := EditorBinary.child_env({"DEBUG": "1"}, "/usr/bin:/bin")
	assert_eq(env.GODOT, OS.get_executable_path(), "GODOT es el binario del editor")
	assert_eq(env.GODOT_BIN, OS.get_executable_path(), "GODOT_BIN también")
	assert_eq(env.DEBUG, "1", "conserva el entorno del perfil")
	var dir := EditorBinary.shim_dir()
	assert_false(dir.is_empty(), "crea el shim")
	assert_eq(env.PATH, dir + ":/usr/bin:/bin", "el shim va al frente del PATH")
	env = EditorBinary.child_env({"GODOT": "/otro/godot", "PATH": "/perfil"}, "/usr/bin")
	assert_eq(env.GODOT, "/otro/godot", "el perfil puede pisar GODOT")
	assert_eq(env.PATH, dir + ":/perfil", "respeta el PATH del perfil")


func test_shim_content() -> void:
	assert_eq(EditorBinary.shim_content("/opt/it's/godot", false), "#!/bin/sh\nexec '/opt/it'\\''s/godot' \"$@\"\n", "sh con comillas escapadas")
	assert_eq(EditorBinary.shim_content("C:\\Godot\\godot.exe", true), "@\"C:\\Godot\\godot.exe\" %*\r\n", "cmd pasa los argumentos")
	assert_eq(EditorBinary.shim_dir("/a/godot"), EditorBinary.shim_dir("/a/godot"), "estable por binario")
	assert_false(EditorBinary.shim_dir("/a/godot") == EditorBinary.shim_dir("/b/godot"), "uno por binario")


func test_shim_runs_editor_binary() -> void:
	if OS.get_name() == "Windows":
		return
	var output: Array = []
	var code := OS.execute(EditorBinary.shim_dir().path_join("godot"), ["--version"], output)
	assert_eq(code, 0, "el shim corre")
	var version := Engine.get_version_info()
	assert_true(str(output[0]).begins_with("%d.%d" % [version.major, version.minor]), "es la versión del editor (%s)" % str(output[0]).strip_edges())
