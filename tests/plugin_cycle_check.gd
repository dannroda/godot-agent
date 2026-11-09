extends SceneTree
## Habilita y deshabilita el plugin godot_agent 5 veces en un editor headless y falla si
## quedan huérfanos o si la salida tiene errores (M0).
##
## Uso: godot --headless --path <repo> --script tests/plugin_cycle_check.gd
## El editor que se lanza es el mismo binario que corre este script.

const TestUserDir := preload("res://tests/test_user_dir.gd")
const CYCLE_ARG := "--godot-agent-cycle-test"
const PROJECT_FILE := "res://project.godot"
const PASS_MARK := "[cycle-test] PASS"
## Ruido conocido del motor al cerrar un editor headless; no lo produce el addon.
const KNOWN_ENGINE_NOISE: PackedStringArray = [
	"RID allocations of type 'PN13RendererDummy14TextureStorage12DummyTextureE' were leaked at exit",
]


func _init() -> void:
	TestUserDir.apply()  # user:// propio de este checkout (m13-17)
	var project_dir := ProjectSettings.globalize_path("res://")
	var output: Array = []
	var args: PackedStringArray = ["--headless", "--editor", "--path", project_dir, "--", CYCLE_ARG]
	# Habilitar y deshabilitar el plugin guarda project.godot (y el editor lo reescribe al arrancar):
	# al terminar vuelve a quedar como estaba (m13-19).
	var project_before := FileAccess.get_file_as_string(PROJECT_FILE)
	var code := OS.execute(OS.get_executable_path(), args, output, true)
	_restore_project_file(project_before)
	var text := "\n".join(output)

	var problems: PackedStringArray = []
	if code != 0:
		problems.append("el editor salió con código %d" % code)
	if not text.contains(PASS_MARK):
		problems.append("no apareció '%s'" % PASS_MARK)
	for line: String in text.split("\n"):
		if _is_error_line(line):
			problems.append("salida: " + line.strip_edges())

	for line: String in text.split("\n"):
		if line.begins_with("[cycle-test]"):
			print(line)
	if problems.is_empty():
		print("plugin_cycle_check: PASS (%s)" % Engine.get_version_info().string)
		quit(0)
	else:
		for p: String in problems:
			printerr("plugin_cycle_check: " + p)
		print("plugin_cycle_check: FAIL (%s)" % Engine.get_version_info().string)
		quit(1)


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
