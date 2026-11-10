extends "test_case.gd"
## Llevar la GDExtension probada al juego (m19-05): el plan desde el proyecto de prueba, las rutas
## reescritas, la revisión del .gdextension, lo preparado y su entrada en el reinicio, y la tool, que
## no instala si los tests no pasan.

const NativeInstall := preload("res://addons/godot_agent/core/native_install.gd")
const DiagnosticTools := preload("res://addons/godot_agent/mcp/tools/diagnostic_tools.gd")
const SupervisorState := preload("res://addons/godot_agent/supervisor/supervisor_state.gd")
const ReadTools := preload("res://addons/godot_agent/mcp/tools/read_tools.gd")

const SYMBOL := "lab_library_init"
const GDEXT := """[configuration]
entry_symbol = "lab_library_init"
compatibility_minimum = "4.5"

[libraries]
linux.debug.x86_64 = "res://bin/linux/liblab.linux.template_debug.x86_64.so"
linux.release.x86_64 = "res://bin/linux/liblab.linux.template_release.x86_64.so"
windows.debug.x86_64 = "res://bin/windows/lab.windows.template_debug.x86_64.dll"
windows.release.x86_64 = "res://bin/windows/lab.windows.template_release.x86_64.dll"

[icons]
Lab = "res://bin/lab.svg"
"""


func test_plan_from_template_layout() -> void:
	var base := _layout("native_install_plan")
	var planned := NativeInstall.plan(base.path_join("ext/project"), "res://bin/lab.gdextension", base.path_join("game"))
	assert_eq(planned.error, "", "sin error")
	assert_eq([planned.source, planned.target, planned.new_extension], ["res://bin", "res://addons/lab", true], "de bin/ a addons/lab/, nueva")
	var targets := Array(planned.files).map(func(file: Dictionary) -> String: return file.to)
	assert_eq(targets, ["addons/lab/lab.gdextension", "addons/lab/lab.svg", "addons/lab/linux/liblab.linux.template_debug.x86_64.so", "addons/lab/linux/liblab.linux.template_release.x86_64.so"], "el .gdextension, el ícono y las bibliotecas que existen; no lo que no se compiló ni la basura de bin/")
	assert_true(planned.gdextension_text.contains("\"res://addons/lab/linux/liblab.linux.template_debug.x86_64.so\"") and not planned.gdextension_text.contains("\"res://bin/"), "rutas reescritas")
	assert_true(planned.gdextension_text.contains("entry_symbol = \"lab_library_init\""), "el resto igual")


func test_plan_into_existing_folder_and_errors() -> void:
	var base := _layout("native_install_existing")
	_write(base.path_join("game/addons/my_lab/lab.gdextension"), GDEXT)
	var planned := NativeInstall.plan(base.path_join("ext/project"), "res://bin/lab.gdextension", base.path_join("game"))
	assert_eq([planned.target, planned.new_extension], ["res://addons/my_lab", false], "donde el juego ya la tiene")
	var forced := NativeInstall.plan(base.path_join("ext/project"), "res://bin/lab.gdextension", base.path_join("game"), "res://native/lab/")
	assert_eq([forced.target, forced.new_extension], ["res://native/lab", true], "target pedido")
	assert_true(str(NativeInstall.plan(base.path_join("ext/project"), "res://bin/lab.gdextension", base.path_join("game"), "res://addons/godot_agent").error).contains("Can't install"), "nunca sobre el harness")
	_write(base.path_join("ext/project/bin/out.gdextension"), "[configuration]\nentry_symbol = \"x\"\n\n[libraries]\nlinux.debug.x86_64 = \"res://other/libx.so\"\n")
	var outside := NativeInstall.plan(base.path_join("ext/project"), "res://bin/out.gdextension", base.path_join("game"))
	assert_true(str(outside.error).contains("points outside res://bin") and str(outside.error).contains("res://other/libx.so"), "una biblioteca fuera de la carpeta no viaja · %s" % outside.error)
	_write(base.path_join("ext/project/root.gdextension"), GDEXT)
	assert_true(str(NativeInstall.plan(base.path_join("ext/project"), "res://root.gdextension", base.path_join("game")).error).contains("at the root"), "en la raíz no hay carpeta que llevar")
	assert_eq(NativeInstall.test_extensions(base.path_join("ext/project")), PackedStringArray(["res://root.gdextension", "res://bin/lab.gdextension", "res://bin/out.gdextension"]), "los .gdextension del proyecto de prueba")


func test_plan_from_addon_layout_takes_the_whole_folder() -> void:
	var base := _fresh_dir("native_install_addon")
	var project := base.path_join("ext/demo")
	_write(project.path_join("project.godot"), "")
	_write(base.path_join("game/project.godot"), "")
	_write(project.path_join("addons/lab/lab.gdextension"), "[configuration]\nentry_symbol = \"lab_library_init\"\ncompatibility_minimum = \"4.5\"\n\n[libraries]\nlinux.debug.x86_64 = \"bin/liblab.so\"\n")
	_write(project.path_join("addons/lab/bin/liblab.so"), "ELF " + SYMBOL)
	_write(project.path_join("addons/lab/plugin.cfg"), "[plugin]\nname=\"Lab\"\n")
	_write(project.path_join("addons/lab/lab_plugin.gd"), "@tool\nextends EditorPlugin\n")
	_write(project.path_join("addons/lab/icon.svg.import"), "")
	var planned := NativeInstall.plan(project, "res://addons/lab/lab.gdextension", base.path_join("game"))
	assert_eq([planned.error, planned.source, planned.target], ["", "res://addons/lab", "res://addons/lab"], "addons/lab/ va igual")
	var targets := Array(planned.files).map(func(file: Dictionary) -> String: return file.to)
	assert_eq(targets, ["addons/lab/bin/liblab.so", "addons/lab/lab.gdextension", "addons/lab/lab_plugin.gd", "addons/lab/plugin.cfg"], "la carpeta entera, sin los .import")
	assert_eq(planned.gdextension_text, FileAccess.get_file_as_string(project.path_join("addons/lab/lab.gdextension")), "rutas relativas: no cambia")


func test_check_like_the_skill_script() -> void:
	var base := _layout("native_install_check")
	var bin := base.path_join("ext/project/bin")
	var project := base.path_join("ext/project")
	var ok: Dictionary = NativeInstall.check(GDEXT, bin, project, "linux", "x86_64")
	assert_eq([ok.problems, ok.warnings], [PackedStringArray(), PackedStringArray()], "la build sana pasa · %s" % [ok])
	assert_eq(ok.not_built, PackedStringArray(["windows.x86_64"]), "windows sin compilar: se lista, no es problema")
	var on_windows: Dictionary = NativeInstall.check(GDEXT, bin, project, "windows", "x86_64")
	assert_true(Array(on_windows.problems).any(func(p: String) -> bool: return p.begins_with("no library this editor can load on windows.x86_64")), "en la plataforma de este editor, faltar la debug es un problema · %s" % [on_windows])
	assert_true(Array(on_windows.warnings).has("windows.release.x86_64: file not found: res://bin/windows/lab.windows.template_release.x86_64.dll"), "la release que falta, un aviso")
	var no_release := GDEXT.replace("linux.release.x86_64 = \"res://bin/linux/liblab.linux.template_release.x86_64.so\"\n", "")
	var without_release: Dictionary = NativeInstall.check(no_release, bin, project, "linux", "x86_64")
	assert_true(without_release.problems.is_empty() and Array(without_release.warnings).has("linux.x86_64 has a debug library but no release key: release exports won't load it"), "sin release: aviso, se instala igual")
	var swapped := GDEXT.replace("linux.debug.x86_64 = \"res://bin/linux/liblab.linux.template_debug", "linux.debug.x86_64 = \"res://bin/linux/liblab.linux.template_release")
	assert_true(Array(NativeInstall.check(swapped, bin, project, "linux", "x86_64").warnings).any(func(p: String) -> bool: return p.begins_with("linux.debug.x86_64 is a debug key but points to a release library")), "debug que apunta a release")
	var wrong_symbol := GDEXT.replace("entry_symbol = \"lab_library_init\"", "entry_symbol = \"other_init\"")
	var symbol_check: Dictionary = NativeInstall.check(wrong_symbol, bin, project, "linux", "x86_64")
	assert_true(Array(symbol_check.problems).has("linux.debug.x86_64: entry_symbol other_init not found in res://bin/linux/liblab.linux.template_debug.x86_64.so"), "entry_symbol que no está en la biblioteca que carga el editor: problema · %s" % [symbol_check])
	assert_true(Array(symbol_check.warnings).any(func(p: String) -> bool: return p.begins_with("linux.release.x86_64: entry_symbol other_init")), "en la release, aviso")
	var precision := GDEXT.replace("linux.debug.x86_64 =", "linux.debug.x86_64.single =") + "linux.debug.x86_64.double = \"res://bin/linux/liblab.linux.template_debug.x86_64.double.so\"\n"
	var single: Dictionary = NativeInstall.check(precision.replace("[icons]", "[other]"), bin, project, "linux", "x86_64")
	assert_true(single.problems.is_empty(), "la double que no se compiló no frena a un editor single · %s" % [single])
	assert_true(Array(NativeInstall.check(precision.replace("[icons]", "[other]"), bin, project, "linux", "x86_64", true).problems).any(func(p: String) -> bool: return p.begins_with("no library this editor can load")), "un editor double necesita la double")
	var too_new := GDEXT.replace("compatibility_minimum = \"4.5\"", "compatibility_minimum = \"%d.0\"" % (Engine.get_version_info().major + 1))
	assert_true(Array(NativeInstall.check(too_new, bin, project, "linux", "x86_64").problems).any(func(p: String) -> bool: return p.contains("is newer than this Godot")), "pide un Godot más nuevo")
	var bare := "[configuration]\n\n[libraries]\nlinux.debug.x86_64 = \"res://bin/linux/liblab.linux.template_debug.x86_64.so\"\n"
	var bare_problems: PackedStringArray = NativeInstall.check(bare, bin, project, "linux", "x86_64").problems
	assert_true(bare_problems.has("[configuration] has no entry_symbol") and bare_problems.has("[configuration] has no compatibility_minimum"), "configuración incompleta")
	assert_true(Array(NativeInstall.check(GDEXT, bin, project, "macos", "arm64").problems).any(func(p: String) -> bool: return p.begins_with("no library this editor can load on macos.arm64")), "nada que cargar en esta plataforma")


func test_stage_check_and_apply() -> void:
	var base := _layout("native_install_stage")
	var game := base.path_join("game")
	_write(game.path_join("addons/lab/linux/liblab.linux.template_debug.x86_64.so"), "old build")
	_write(game.path_join("addons/lab/lab.gdextension"), GDEXT.replace("res://bin/", "res://addons/lab/"))
	var state := SupervisorState.state_dir(game)
	var planned := NativeInstall.plan(base.path_join("ext/project"), "res://bin/lab.gdextension", game)
	assert_eq(NativeInstall.stage(planned, state), "", "preparado")
	assert_eq(FileAccess.get_file_as_string(game.path_join("addons/lab/linux/liblab.linux.template_debug.x86_64.so")), "old build", "el juego no cambia hasta el reinicio")
	assert_eq(NativeInstall.pending(state).files.size(), 4, "pending.json con los 4 archivos")
	var checked := NativeInstall.check_staged(planned, state)
	assert_eq(checked.problems, PackedStringArray(), "lo preparado se revisa con las rutas nuevas · %s" % [checked.problems])
	var applied := NativeInstall.apply_pending(game, state)
	assert_eq([applied.applied.size(), applied.failed], [4, PackedStringArray()], "entra todo")
	assert_true(FileAccess.get_file_as_string(game.path_join("addons/lab/linux/liblab.linux.template_debug.x86_64.so")).contains(SYMBOL), "la build nueva en su lugar")
	assert_true(FileAccess.get_file_as_string(game.path_join("addons/lab/lab.gdextension")).contains("res://addons/lab/linux/"), "el .gdextension reescrito")
	assert_true(NativeInstall.pending(state).is_empty() and not DirAccess.dir_exists_absolute(state.path_join("pending")), "no queda nada preparado")
	assert_eq(NativeInstall.apply_pending(game, state).applied, PackedStringArray(), "sin nada preparado no hace nada")
	assert_false(FileAccess.file_exists(game.path_join("addons/lab/linux/liblab.linux.template_debug.x86_64.so.installing")), "sin temporales")


func test_tool_installs_only_after_the_tests_pass() -> void:
	var base := _layout("native_install_tool")
	var game := base.path_join("game")
	var state := SupervisorState.state_dir(game)
	var tools := DiagnosticTools.new()
	tools.setup(null, game)
	var calls: Array = []
	var report := {"error": "", "code": 1, "crashed": false, "timed_out": false, "imported": false, "unregistered": PackedStringArray(), "lines": PackedStringArray(),
		"parsed": {"passed": 0, "failed": PackedStringArray(["test_lab:test_speed: speed setter"]), "load_errors": PackedStringArray(), "crash": PackedStringArray(), "done": "tests=1 checks=1 failures=1", "loaded": "res://bin/lab.gdextension"}}
	tools.extension_tester = func(dir: String, options: Dictionary) -> Dictionary:
		calls.append([dir, options.tests])
		return report
	var args := {"project": base.path_join("ext/project"), "tests": "res://tests"}
	var failed: Dictionary = await tools._install_extension(args)
	assert_true(failed.isError and failed.content[0].text.begins_with("Not installed: the tests didn't pass.") and failed.content[0].text.contains("speed setter"), "no instala si falla un test · %s" % failed.content[0].text)
	assert_true(NativeInstall.pending(state).is_empty(), "y no prepara nada")
	assert_eq(calls, [[base.path_join("ext/project"), "res://tests"]], "corre los tests del proyecto de prueba")
	report.code = 0
	report.parsed.failed = PackedStringArray()
	report.parsed.done = "tests=1 checks=1 failures=0"
	var passed: Dictionary = await tools._install_extension(args)
	var text: String = passed.content[0].text
	assert_false(passed.isError, "instala si pasan · %s" % text)
	assert_true(text.contains("Staged 4 files from res://bin (test project) for res://addons/lab") and text.contains("res://addons/lab/lab.gdextension") and text.contains("call restart_editor"), "dice qué preparó y qué sigue")
	assert_true(text.contains("windows.x86_64") and text.contains("registers and loads it"), "lo no compilado y que es nueva")
	assert_eq(NativeInstall.pending(state).files.size(), 4, "preparado")
	assert_false(FileAccess.file_exists(game.path_join("addons/lab/lab.gdextension")), "el juego sigue igual")
	var same: Dictionary = await tools._install_extension({"project": game})
	assert_true(same.isError and same.content[0].text.contains("nothing to install"), "el proyecto de prueba no puede ser el juego")
	NativeInstall.discard_pending(state)


## Lo preparado que no entró (el editor se cerró sin restart_editor): se describe para el aviso del
## dock y godot.project_info lo nombra; descartarlo no deja nada.
func test_pending_is_reported_until_discarded() -> void:
	var base := _layout("native_install_pending")
	var game := base.path_join("game")
	var state := SupervisorState.state_dir(game)
	var reader := ReadTools.new()
	reader.supervisor_state_dir = state
	assert_true(NativeInstall.pending_info(state).is_empty() and NativeInstall.pending_line(state).is_empty(), "sin nada preparado no hay aviso")
	assert_false(reader._project_info({}).contains("Staged GDExtension"), "ni en project_info")
	var planned := NativeInstall.plan(base.path_join("ext/project"), "res://bin/lab.gdextension", game)
	assert_eq(NativeInstall.stage(planned, state), "", "preparado")
	var info := NativeInstall.pending_info(state)
	assert_eq([info.extensions, info.target, info.files], [PackedStringArray(["res://addons/lab/lab.gdextension"]), "res://addons/lab", 4], "qué está preparado")
	assert_eq(NativeInstall.pending_names(info), "lab", "el nombre para el aviso")
	var line := NativeInstall.pending_line(state)
	assert_true(line.contains("4 files for res://addons/lab/lab.gdextension") and line.contains("godot.restart_editor"), "la línea para el agente · %s" % line)
	assert_true(reader._project_info({}).contains(line), "project_info la incluye")
	NativeInstall.discard_pending(state)
	assert_true(NativeInstall.pending_info(state).is_empty() and not DirAccess.dir_exists_absolute(state.path_join("pending")), "descartado no queda nada")
	assert_false(reader._project_info({}).contains("Staged GDExtension"), "y project_info ya no lo nombra")
	assert_false(FileAccess.file_exists(game.path_join("addons/lab/lab.gdextension")), "el juego no cambió")


## ext/project (godot-cpp-template) con bin/lab.gdextension y la build de linux; game/ vacío.
func _layout(name: String) -> String:
	var base := _fresh_dir(name)
	var project := base.path_join("ext/project")
	_write(project.path_join("project.godot"), "")
	_write(base.path_join("game/project.godot"), "")
	_write(project.path_join("bin/lab.gdextension"), GDEXT)
	_write(project.path_join("bin/lab.svg"), "<svg/>")
	_write(project.path_join("bin/linux/liblab.linux.template_debug.x86_64.so"), "\u007fELF debug " + SYMBOL + " end")
	_write(project.path_join("bin/linux/liblab.linux.template_release.x86_64.so"), "\u007fELF release " + SYMBOL + " end")
	_write(project.path_join("bin/linux/liblab.linux.template_debug.x86_64.so.crashed"), "")
	return base


func _fresh_dir(name: String) -> String:
	var path := ProjectSettings.globalize_path("user://unit_tests/%s" % name)
	_remove_tree(path)
	DirAccess.make_dir_recursive_absolute(path)
	return path


func _remove_tree(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		return
	for file: String in DirAccess.get_files_at(path):
		DirAccess.remove_absolute(path.path_join(file))
	for sub: String in DirAccess.get_directories_at(path):
		_remove_tree(path.path_join(sub))
	DirAccess.remove_absolute(path)


func _write(path: String, text: String) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()
