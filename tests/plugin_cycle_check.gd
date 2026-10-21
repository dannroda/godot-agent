extends SceneTree
## Habilita y deshabilita el plugin godot_agent 5 veces en un editor headless y falla si
## quedan huérfanos o si la salida tiene errores (M0).
##
## Uso: godot --headless --path <repo> --script tests/plugin_cycle_check.gd
## El editor que se lanza es el mismo binario que corre este script.

const CYCLE_ARG := "--godot-agent-cycle-test"
const PASS_MARK := "[cycle-test] PASS"
## Ruido conocido del motor al cerrar un editor headless; no lo produce el addon.
const KNOWN_ENGINE_NOISE: PackedStringArray = [
	"RID allocations of type 'PN13RendererDummy14TextureStorage12DummyTextureE' were leaked at exit",
]


func _init() -> void:
	var project_dir := ProjectSettings.globalize_path("res://")
	var output: Array = []
	var args: PackedStringArray = ["--headless", "--editor", "--path", project_dir, "--", CYCLE_ARG]
	var code := OS.execute(OS.get_executable_path(), args, output, true)
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


func _is_error_line(line: String) -> bool:
	var is_error := line.contains("ERROR") or line.contains("SCRIPT ERROR") or line.contains("leaked")
	if not is_error:
		return false
	for noise: String in KNOWN_ENGINE_NOISE:
		if line.contains(noise):
			return false
	return true
