extends "test_case.gd"
## Probar la GDExtension en un Godot aparte (m19-02): el proyecto de prueba, qué extensiones carga,
## la salida del runner y el resumen con el crash.

const NativeTest := preload("res://addons/godot_agent/core/native_test.gd")

const CRASH_OUTPUT: PackedStringArray = [
	"PASS test_node:test_speed: speed setter",
	"================================================================",
	"handle_crash: Program crashed with signal 11",
	"Engine version: Godot Engine v4.7.2.stable.official",
	"[1] 7f455ae3e6f0 (libc.so.6+3e6f0) - /usr/lib/libc.so.6(+0x3e6f0) [0x7f455ae3e6f0]",
	"[2] 8463c (liblab.linux.template_debug.x86_64.so+8463c) - /ext/project/bin/linux/liblab.linux.template_debug.x86_64.so(+0x8463c) [0x7f0000008463c]",
	"-- END OF C++ BACKTRACE --",
	"GDScript backtrace (most recent call first):",
	"    [0] test_crash (res://tests/test_node.gd:9)",
]


func test_parse_output() -> void:
	var parsed := NativeTest.parse_output(PackedStringArray([
		"LOADED res://bin/lab.gdextension",
		"PASS test_node:test_speed: speed setter",
		"FAIL test_node:test_limit: clamps to 1000",
		"ERROR: Getter method 'MyNode::get_speed()' not found for property 'MyNode::speed'",
		"ERROR: Some unrelated engine error",
		"DONE tests=2 checks=2 failures=1",
	]))
	assert_eq([parsed.passed, parsed.failed, parsed.done, parsed.loaded], [1, PackedStringArray(["test_node:test_limit: clamps to 1000"]), "tests=2 checks=2 failures=1", "res://bin/lab.gdextension"], "tests y resumen")
	assert_eq(parsed.load_errors, PackedStringArray(["Getter method 'MyNode::get_speed()' not found for property 'MyNode::speed'"]), "solo los errores de la extensión")
	var crash := NativeTest.parse_output(CRASH_OUTPUT)
	assert_eq(crash.passed, 1, "lo de antes del crash")
	assert_true(crash.crash.size() == 7 and crash.crash[0].contains("signal 11") and crash.crash[-1].contains("test_node.gd:9"), "el backtrace C++ y el de GDScript · %s" % [crash.crash])


func test_summary_of_a_crash() -> void:
	var report := {"error": "", "code": 139, "crashed": true, "timed_out": false, "imported": false, "unregistered": PackedStringArray(), "parsed": NativeTest.parse_output(CRASH_OUTPUT), "lines": CRASH_OUTPUT}
	var text := NativeTest.summarize(report, "/ext/project", PackedStringArray(["/ext/project", "/ext"]))
	assert_true(text.begins_with("CRASHED in /ext/project") and text.contains("The editor was not affected"), "dice que crasheó sin el editor")
	assert_true(text.contains("liblab.linux.template_debug.x86_64.so(+0x8463c)") and text.contains("test_node.gd:9"), "con el backtrace")
	assert_true(text.contains("debug_symbols=yes"), "sin símbolos, cómo conseguirlos")


func test_symbolize_only_extension_frames() -> void:
	# Sin la biblioteca en disco, addr2line no resuelve nada; y libc no se mira (no está bajo dirs).
	assert_eq(NativeTest.symbolize(CRASH_OUTPUT, PackedStringArray(["/nowhere"])), {}, "frames fuera de la extensión")


func test_find_test_project_and_extensions() -> void:
	var base := _fresh_dir("native_test_layouts")
	for dir: String in ["ext/project/bin", "ext/project/.godot", "rs/godot", "rs/rust", "open"]:
		DirAccess.make_dir_recursive_absolute(base.path_join(dir))
	for file: String in ["ext/project/project.godot", "rs/godot/project.godot", "open/project.godot"]:
		_write(base.path_join(file), "")
	_write(base.path_join("ext/project/bin/lab.gdextension"), "[configuration]\nentry_symbol = \"lab_init\"\nreloadable = true\n")
	_write(base.path_join("ext/project/bin/other.gdextension"), "[configuration]\nentry_symbol = \"other_init\"\n")
	_write(base.path_join("ext/project/.godot/extension_list.cfg"), "res://bin/lab.gdextension\n")
	assert_eq(NativeTest.find_test_project({"kind": "scons", "root": base.path_join("ext")}, base.path_join("open")), base.path_join("ext/project"), "project/ al lado del SConstruct")
	assert_eq(NativeTest.find_test_project({"kind": "cargo", "root": base.path_join("rs/rust")}, base.path_join("open")), base.path_join("rs/godot"), "godot/ al lado de rust/")
	assert_eq(NativeTest.find_test_project({}, base.path_join("open/")), base.path_join("open"), "si no, el proyecto abierto")
	var project := base.path_join("ext/project")
	assert_eq(NativeTest.gdextension_files(project), PackedStringArray(["res://bin/lab.gdextension", "res://bin/other.gdextension"]), "los .gdextension")
	assert_eq(NativeTest.registered_extensions(project), PackedStringArray(["res://bin/lab.gdextension"]), "los registrados")
	assert_eq(NativeTest.reloadable_extensions(project), PackedStringArray(["res://bin/lab.gdextension"]), "los que el editor recarga")
	assert_true(NativeTest.same_dir(project + "/", project), "misma carpeta con o sin barra")


## De verdad: el runner en un Godot aparte, sobre un proyecto sin extensión, sale con 2 y lo dice.
func test_real_run_without_extension() -> void:
	var dir := _fresh_dir("native_test_empty")
	_write(dir.path_join("project.godot"), "config_version=5\n")
	var report: Dictionary = await NativeTest.run(dir, {"timeout_s": 60})
	assert_eq([report.error, report.code, report.crashed], ["", 2, false], "sale con 2 · %s" % [report.lines])
	assert_true(report.parsed.load_errors.size() == 1 and str(report.parsed.load_errors[0]).contains("no GDExtension loaded"), "dice que no cargó ninguna")
	assert_true(NativeTest.summarize(report, dir, PackedStringArray([dir])).contains("did not load"), "en el resumen")


func _fresh_dir(name: String) -> String:
	var path := ProjectSettings.globalize_path("user://unit_tests/%s" % name)
	_remove_tree(path)
	DirAccess.make_dir_recursive_absolute(path)
	return path


func _remove_tree(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		return
	for dir: String in DirAccess.get_directories_at(path):
		_remove_tree(path.path_join(dir))
	for file: String in DirAccess.get_files_at(path):
		DirAccess.remove_absolute(path.path_join(file))
	DirAccess.remove_absolute(path)


func _write(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()
