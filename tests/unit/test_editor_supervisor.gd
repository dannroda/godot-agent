extends "test_case.gd"
## Supervisor del editor (m19-03): la última versión buena de las bibliotecas, el rollback, el
## backtrace del log y el supervisor de verdad con un editor falso (fixtures/supervisor).

const State := preload("res://addons/godot_agent/supervisor/supervisor_state.gd")
const Snapshot := preload("res://addons/godot_agent/supervisor/extension_snapshot.gd")
const SupervisorClient := preload("res://addons/godot_agent/supervisor/supervisor_client.gd")
const SUPERVISOR := "res://addons/godot_agent/supervisor/editor_supervisor.gd"
const FAKE_EDITOR := "res://tests/fixtures/supervisor/fake_editor.gd"

const GDEXTENSION := """[configuration]
entry_symbol = "lab_init"

[libraries]
linux.debug.x86_64 = "./linux/liblab.so"
windows.debug.x86_64 = "./windows/lab.dll"

[dependencies]
linux.debug.x86_64 = {
	"./linux/libdep.so.1": ""
}
"""


func test_extensions_lists_existing_libraries() -> void:
	var project := _project("sup_list")
	var found := Snapshot.extensions(project)
	assert_eq(found.size(), 1, "un .gdextension")
	assert_eq(found[0].files, PackedStringArray([project.path_join("bin/linux/liblab.so"), project.path_join("bin/linux/libdep.so.1")]), "bibliotecas y dependencias que existen, sin la de Windows")


func test_snapshot_changes_and_rollback() -> void:
	var project := _project("sup_rollback")
	var state := State.state_dir(project)
	assert_eq(Snapshot.snapshot(project, state), PackedStringArray(["bin/linux/liblab.so", "bin/linux/libdep.so.1"]), "copia las dos")
	assert_eq(Snapshot.snapshot(project, state), PackedStringArray(), "sin cambios no copia")
	_write(project.path_join("bin/linux/liblab.so"), "new build")
	_write(project.path_join("other/fresh.gdextension"), "[libraries]\nlinux.debug.x86_64 = \"res://other/libfresh.so\"\n")
	_write(project.path_join("other/libfresh.so"), "fresh")
	assert_eq(Snapshot.changes(project, state), {"changed": PackedStringArray(["bin/linux/liblab.so"]), "new": PackedStringArray(["other/libfresh.so"])}, "la cambiada y la nueva")
	var result := Snapshot.rollback(project, state)
	assert_eq(result, {"restored": PackedStringArray(["bin/linux/liblab.so"]), "disabled": PackedStringArray(["other/fresh.gdextension"])}, "vuelve una y desactiva la otra")
	assert_eq(FileAccess.get_file_as_string(project.path_join("bin/linux/liblab.so")), "good build", "la copia buena")
	assert_eq(FileAccess.get_file_as_string(project.path_join("bin/linux/liblab.so.crashed")), "new build", "la que crasheó queda al lado")
	assert_true(FileAccess.file_exists(project.path_join("other/fresh.gdextension.disabled")) and not FileAccess.file_exists(project.path_join("other/fresh.gdextension")), "renombrada")


func test_crash_lines_from_log() -> void:
	var project := _project("sup_log")
	var log_path := project.path_join("editor.log")
	_write(log_path, "\n".join(PackedStringArray([
		"Godot Engine v4.7.2",
		"================================================================",
		"handle_crash: Program crashed with signal 11",
		"Engine version: Godot Engine v4.7.2.stable.official",
		"Dumping the backtrace. Please include this when reporting the bug",
		"[1] 7f45 (libc.so.6+3e6f0) - /usr/lib/libc.so.6(+0x3e6f0) [0x7f45]",
		"[2] 8463c (liblab.so+8463c) - %s/bin/linux/liblab.so(+0x8463c) [0x8463c]" % project,
		"-- END OF C++ BACKTRACE --",
		"GDScript backtrace (most recent call first):",
		"    [0] _ready (res://main.gd:3)",
		"-- END OF GDSCRIPT BACKTRACE --",
		"something after",
	])))
	var lines := State.crash_lines(log_path, project)
	assert_eq(lines.size(), 8, "sin cabecera ni frames del sistema · %s" % [lines])
	assert_true(lines[0].contains("signal 11") and lines[2].contains("liblab.so") and lines[3].contains("1 frames") and lines[-1].begins_with("-- END OF GDSCRIPT"), "el orden")
	assert_eq(State.crash_lines(project.path_join("nothing.log"), project), PackedStringArray(), "sin log")


func test_agent_messages() -> void:
	var startup := SupervisorClient.agent_message({"kind": State.EVENT_STARTUP_CRASH, "restored": ["bin/linux/liblab.so"], "disabled": [], "backtrace": ["handle_crash: Program crashed with signal 11"]})
	assert_true(startup.contains("while starting") and startup.contains("bin/linux/liblab.so") and startup.contains("*.crashed") and startup.contains("signal 11"), startup)
	var restart := SupervisorClient.agent_message({"kind": State.EVENT_RESTART, "reason": "restart_editor"})
	assert_true(restart.contains("restarted (restart_editor)"), restart)
	var gave_up := SupervisorClient.agent_message({"kind": State.EVENT_GAVE_UP, "crashes": 3})
	assert_true(gave_up.contains("3 times") and gave_up.contains("No GDExtension library had changed"), gave_up)


func test_editor_flags_from_drivers_in_use() -> void:
	var flags := SupervisorClient.editor_flags()
	assert_true("--rendering-driver" in flags and "--audio-driver" in flags, "los drivers en uso · %s" % [flags])
	assert_false("--display-driver" in flags, "headless no se repite (el supervisor abre un editor con ventana)")


## De verdad: el editor falso crashea al arrancar con una build nueva; el supervisor vuelve a la
## buena, lo relanza, y en el segundo arranque se cierra bien y el supervisor termina.
func test_real_startup_crash_rolls_back() -> void:
	var project := _project("sup_real_rollback")
	var state := State.state_dir(project)
	Snapshot.snapshot(project, state)
	_write(project.path_join("bin/linux/liblab.so"), "crashing build")
	_write(project.path_join("plan.json"), JSON.stringify(["crash_start", "close"]))
	assert_true(await _supervise(project), "el supervisor terminó")
	assert_eq(FileAccess.get_file_as_string(state.path_join("launches.txt")), "2", "lo relanzó una vez")
	assert_eq(FileAccess.get_file_as_string(project.path_join("bin/linux/liblab.so")), "good build", "volvió a la build buena")
	var events: Array = State.read_json(state, State.EVENT).get("events", [])
	assert_eq(events.size(), 1, "un evento · %s" % [events])
	if events.size() == 1:
		assert_eq([events[0].kind, events[0].restored], [State.EVENT_STARTUP_CRASH, ["bin/linux/liblab.so"]], "crash al arrancar, con rollback")
		assert_true(str(events[0].backtrace).contains("handle_crash"), "con el backtrace del log")
	assert_false(State.supervisor_running(state), "borró su pid")


## Un reinicio pedido por el plugin se relanza; un crash después de arrancar también, sin rollback.
func test_real_restart_and_running_crash() -> void:
	var project := _project("sup_real_restart")
	_write(project.path_join("plan.json"), JSON.stringify(["restart", "close"]))
	assert_true(await _supervise(project), "terminó")
	var events: Array = State.read_json(State.state_dir(project), State.EVENT).get("events", [])
	assert_eq(events.map(func(event: Dictionary) -> String: return event.kind), [State.EVENT_RESTART], "el reinicio")


## Crashea siempre: a los MAX_CRASHES deja de relanzar.
func test_real_gives_up() -> void:
	var project := _project("sup_real_gave_up")
	_write(project.path_join("plan.json"), JSON.stringify(["crash_start"]))
	assert_true(await _supervise(project), "terminó")
	var state := State.state_dir(project)
	assert_eq(FileAccess.get_file_as_string(state.path_join("launches.txt")), str(3), "tres arranques")
	var events: Array = State.read_json(state, State.EVENT).get("events", [])
	assert_eq(events.map(func(event: Dictionary) -> String: return event.kind), [State.EVENT_STARTUP_CRASH, State.EVENT_STARTUP_CRASH, State.EVENT_GAVE_UP], "dos crashes y el último")


## Lo que preparó install_extension (m19-05) entra antes de abrir el editor; si esa build crashea al
## arrancar, el rollback vuelve a la buena igual que con una build copiada a mano.
func test_real_installs_pending_before_launch() -> void:
	var project := _project("sup_real_pending")
	var state := State.state_dir(project)
	Snapshot.snapshot(project, state)
	DirAccess.make_dir_recursive_absolute(state.path_join("pending/bin/linux"))
	_write(state.path_join("pending/bin/linux/liblab.so"), "crashing build")
	_write(state.path_join("pending/bin/readme.txt"), "new file")
	_write(state.path_join("pending.json"), JSON.stringify({"files": ["bin/linux/liblab.so", "bin/readme.txt"]}))
	_write(project.path_join("plan.json"), JSON.stringify(["crash_start", "close"]))
	assert_true(await _supervise(project), "terminó")
	assert_eq(FileAccess.get_file_as_string(project.path_join("bin/readme.txt")), "new file", "lo preparado entró")
	assert_eq(FileAccess.get_file_as_string(project.path_join("bin/linux/liblab.so.crashed")), "crashing build", "la build instalada crasheó y quedó como .crashed")
	assert_eq(FileAccess.get_file_as_string(project.path_join("bin/linux/liblab.so")), "good build", "volvió la buena")
	assert_false(FileAccess.file_exists(state.path_join("pending.json")), "no queda nada preparado (no se reinstala en el relanzamiento)")


## Corre el supervisor con el editor falso y espera a que termine (60 s como mucho).
func _supervise(project: String) -> bool:
	var state := State.state_dir(project)
	DirAccess.make_dir_recursive_absolute(state)
	var launch := ",".join(PackedStringArray(["--headless", "--path", project, "--script", ProjectSettings.globalize_path(FAKE_EDITOR)]))
	var pid := OS.create_process(OS.get_executable_path(), PackedStringArray([
		"--headless", "--path", state, "--script", ProjectSettings.globalize_path(SUPERVISOR), "--", "--project", project, "--launch", launch,
	]))
	var tree := Engine.get_main_loop() as SceneTree
	var deadline := Time.get_ticks_msec() + 60000
	while OS.is_process_running(pid) and Time.get_ticks_msec() < deadline:
		await tree.create_timer(0.2).timeout
	if OS.is_process_running(pid):
		OS.kill(pid)
		return false
	return true


## Un proyecto de prueba con una extensión, su biblioteca y una dependencia.
func _project(name: String) -> String:
	var path := ProjectSettings.globalize_path("user://unit_tests/%s" % name)
	_remove_tree(path)
	DirAccess.make_dir_recursive_absolute(path.path_join("bin/linux"))
	DirAccess.make_dir_recursive_absolute(path.path_join("other"))
	_write(path.path_join("project.godot"), "config_version=5\n")
	_write(path.path_join("bin/lab.gdextension"), GDEXTENSION)
	_write(path.path_join("bin/linux/liblab.so"), "good build")
	_write(path.path_join("bin/linux/libdep.so.1"), "dependency")
	return path


## Con las carpetas ocultas: el estado del supervisor está en .godot/.
func _remove_tree(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	dir.include_hidden = true
	for sub: String in dir.get_directories():
		_remove_tree(path.path_join(sub))
	for file: String in dir.get_files():
		DirAccess.remove_absolute(path.path_join(file))
	DirAccess.remove_absolute(path)


func _write(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()
