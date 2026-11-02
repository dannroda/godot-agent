extends SceneTree
## Runner de test_extension (m19-02): corre en un Godot headless aparte, sobre el proyecto de prueba
## de la GDExtension, para que un crash de la extensión mate a ese proceso y no al editor. El mismo
## formato que el runner de la skill gdextension-cpp (godot-agent-plugins), así que los tests sirven
## para los dos.
##
##   godot --headless --path <proyecto> --script <este archivo> -- --dir=res://tests --class=MyNode
##
## Cada archivo tests/test_*.gd extiende RefCounted y tiene métodos test_*(t) que llaman a
## t.check(condición, "qué"). Un test puede hacer await (`await t.tree.process_frame`).
## Sin carpeta de tests solo comprueba que la extensión cargó y que las clases existen.
##
## Sale con 0 si todo pasó, 1 si falló un check y 2 si la extensión o una clase no cargó.

var tree: SceneTree
var _failures := 0
var _checks := 0
var _current := ""


func check(condition: bool, what: String) -> void:
	_checks += 1
	if condition:
		print("PASS %s: %s" % [_current, what])
	else:
		_failures += 1
		printerr("FAIL %s: %s" % [_current, what])


func _initialize() -> void:
	tree = self
	_run.call_deferred()


func _run() -> void:
	# En _initialize el árbol todavía no corre y los chequeos de hilo no avisan: un frame primero.
	await process_frame

	var dir := "res://tests"
	var classes: PackedStringArray = []
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--dir="):
			dir = arg.trim_prefix("--dir=")
		elif arg.begins_with("--class="):
			classes = arg.trim_prefix("--class=").split(",", false)

	var loaded := GDExtensionManager.get_loaded_extensions()
	if loaded.is_empty():
		printerr("ERROR no GDExtension loaded. Read the load errors above.")
		quit(2)
		return
	print("LOADED %s" % ", ".join(loaded))
	for name: String in classes:
		if not ClassDB.class_exists(name):
			printerr("ERROR class %s isn't registered" % name)
			quit(2)
			return

	var ran := 0
	if DirAccess.dir_exists_absolute(dir):
		for file: String in DirAccess.get_files_at(dir):
			if not (file.begins_with("test_") and file.ends_with(".gd")):
				continue
			var script := load(dir.path_join(file)) as GDScript
			if script == null or not script.can_instantiate():
				_failures += 1
				printerr("FAIL %s: script doesn't load" % file)
				continue
			var suite: Object = script.new()
			for method: Dictionary in suite.get_method_list():
				var method_name: String = method.name
				if not method_name.begins_with("test_"):
					continue
				_current = "%s:%s" % [file.get_basename(), method_name]
				ran += 1
				await suite.call(method_name, self)
			if suite is Node:
				suite.free()

	print("DONE tests=%d checks=%d failures=%d" % [ran, _checks, _failures])
	quit(1 if _failures else 0)
