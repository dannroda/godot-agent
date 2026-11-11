extends SceneTree
## Habilita y deshabilita el plugin godot_agent 9 veces en un editor headless, intercalado con un plugin
## vacío de control, y falla si quedan huérfanos, si pierde objetos ciclo a ciclo más que el control o
## si la salida tiene errores (M0, m16-12). Después se prueba a sí mismo: el mismo check sobre
## tests/fixtures/cycle_plugins/leaky (pierde un objeto por enable) tiene que fallar por la fuga.
##
## Uso: godot --headless --path <repo> --script tests/plugin_cycle_check.gd
## El editor que se lanza es el mismo binario que corre este script.

const TestUserDir := preload("res://tests/test_user_dir.gd")
const CYCLE_ARG := "--godot-agent-cycle-test"
const TARGET_ARG := "--godot-agent-cycle-target="
const LEAKY_PLUGIN := "res://tests/fixtures/cycle_plugins/leaky/plugin.cfg"
const PROJECT_FILE := "res://project.godot"
const PASS_MARK := "[cycle-test] PASS"
const LEAK_MARK := "pierde objetos"
## Ruido conocido del motor al cerrar un editor headless; no lo produce el addon.
const KNOWN_ENGINE_NOISE: PackedStringArray = [
	"RID allocations of type 'PN13RendererDummy14TextureStorage12DummyTextureE' were leaked at exit",
]


func _init() -> void:
	TestUserDir.apply()  # user:// propio de este checkout (m13-17)
	var problems: PackedStringArray = []

	var addon := _run_editor(PackedStringArray())
	if addon.code != 0:
		problems.append("el editor salió con código %d" % addon.code)
	if not str(addon.text).contains(PASS_MARK):
		problems.append("no apareció '%s'" % PASS_MARK)
	for line: String in str(addon.text).split("\n"):
		if _is_error_line(line):
			problems.append("salida: " + line.strip_edges())
		if line.begins_with("[cycle-test]"):
			print(line)

	# Self-test: con un plugin que pierde un objeto por enable, el check tiene que fallar por eso.
	var leaky := _run_editor(PackedStringArray([TARGET_ARG + LEAKY_PLUGIN]))
	var leak_found: bool = leaky.code == 1 and str(leaky.text).contains("[cycle-test] FAIL") and str(leaky.text).contains(LEAK_MARK)
	for line: String in str(leaky.text).split("\n"):
		if line.begins_with("[cycle-test] objetos por ciclo") or line.begins_with("[cycle-test] FAIL") or line.begins_with("[cycle-test] PASS"):
			print("(self-test) " + line)
	if not leak_found:
		problems.append("self-test: el check no detectó la fuga de %s (salió con %d)" % [LEAKY_PLUGIN, leaky.code])

	if problems.is_empty():
		print("plugin_cycle_check: PASS (%s)" % Engine.get_version_info().string)
		quit(0)
	else:
		for p: String in problems:
			printerr("plugin_cycle_check: " + p)
		print("plugin_cycle_check: FAIL (%s)" % Engine.get_version_info().string)
		quit(1)


## Corre el check de ciclos en un editor headless: {code, text}. Habilitar y deshabilitar plugins
## guarda project.godot (y el editor lo reescribe al arrancar): al terminar vuelve a quedar como
## estaba (m13-19).
func _run_editor(extra: PackedStringArray) -> Dictionary:
	var args: PackedStringArray = ["--headless", "--editor", "--path", ProjectSettings.globalize_path("res://"), "--", CYCLE_ARG]
	args.append_array(extra)
	var project_before := FileAccess.get_file_as_string(PROJECT_FILE)
	var output: Array = []
	var code := OS.execute(OS.get_executable_path(), args, output, true)
	_restore_project_file(project_before)
	return {"code": code, "text": "\n".join(output)}


func _restore_project_file(before: String) -> void:
	if FileAccess.get_file_as_string(PROJECT_FILE) == before:
		return
	var file := FileAccess.open(PROJECT_FILE, FileAccess.WRITE)
	if file == null:
		printerr("plugin_cycle_check: no se pudo restaurar project.godot: %s" % error_string(FileAccess.get_open_error()))
		return
	file.store_string(before)
	file.close()
	print("plugin_cycle_check: project.godot restaurado (el editor lo había reescrito)")


func _is_error_line(line: String) -> bool:
	var is_error := line.contains("ERROR") or line.contains("SCRIPT ERROR") or line.contains("leaked")
	if not is_error:
		return false
	for noise: String in KNOWN_ENGINE_NOISE:
		if line.contains(noise):
			return false
	return true
