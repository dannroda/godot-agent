extends "test_case.gd"
## El punto de entrada del plugin (m16-15). Al habilitarlo, el editor compila plugin.gd sin caché y eso
## cuesta ~1,8 ms por cada script que nombra: con todo el plugin ahí eran ~180 ms de los ~430 del enable.

const ENTRY := "res://addons/godot_agent/plugin.gd"
const AGENT := "res://addons/godot_agent/agent_plugin.gd"
## Lo que plugin.gd llama sin tipo en agent_plugin.gd: un nombre cambiado no da error de parseo.
const CALLED_BY_ENTRY: PackedStringArray = ["build", "make_visible", "has_main_screen", "plugin_name", "plugin_icon"]


func test_entry_names_no_script() -> void:
	var source := FileAccess.get_file_as_string(ENTRY)
	assert_true(source.contains("\nextends EditorPlugin\n"), "hereda de EditorPlugin directo (heredar de un script lo compila entero)")
	assert_false(source.contains("preload("), "no precarga nada")
	assert_true(source.contains("const AGENT_PLUGIN_PATH := \"%s\"" % AGENT), "carga agent_plugin.gd por ruta")


## Como lo hace el editor al habilitarlo: cargado una vez y vuelto a compilar sin caché. Con el plugin
## entero adentro tardaba ~170 ms; ahora menos de 1 ms (el margen es para runners lentos).
func test_entry_recompiles_fast() -> void:
	load(AGENT)
	load(ENTRY)
	var start := Time.get_ticks_usec()
	for i in 3:
		ResourceLoader.load(ENTRY, "", ResourceLoader.CACHE_MODE_IGNORE)
	var ms := (Time.get_ticks_usec() - start) / 3000.0
	assert_true(ms < 25.0, "plugin.gd se recompila en %.1f ms" % ms)


func test_agent_has_what_the_entry_calls() -> void:
	var script: GDScript = load(AGENT)
	var methods := {}
	for method: Dictionary in script.get_script_method_list():
		methods[method.name] = method
	for name: String in CALLED_BY_ENTRY:
		assert_true(methods.has(name), "agent_plugin.gd tiene %s()" % name)
	assert_eq((methods.get("_init", {}).get("args", []) as Array).size(), 1, "_init recibe el EditorPlugin")
	assert_eq(script.get_instance_base_type(), &"Node", "es un Node (hijo del EditorPlugin)")
