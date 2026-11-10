extends "test_case.gd"
## Llevar la GDExtension probada al juego (m19-05): el plan desde el proyecto de prueba, las rutas
## reescritas, la revisión del .gdextension, lo preparado y su entrada en el reinicio, y la tool, que
## no instala si los tests no pasan.

const NativeInstall := preload("res://addons/godot_agent/core/native_install.gd")
const DiagnosticTools := preload("res://addons/godot_agent/mcp/tools/diagnostic_tools.gd")
const SupervisorState := preload("res://addons/godot_agent/supervisor/supervisor_state.gd")
const ReadTools := preload("res://addons/godot_agent/mcp/tools/read_tools.gd")
const FileTools := preload("res://addons/godot_agent/mcp/tools/file_tools.gd")
const ProtectedPaths := preload("res://addons/godot_agent/core/protected_paths.gd")
const ExtensionSnapshot := preload("res://addons/godot_agent/supervisor/extension_snapshot.gd")

## Las features de un editor de Linux (single y double) para check().
const LINUX: PackedStringArray = ["linux", "x86_64", "64", "pc", "debug", "editor", "single", "threads"]
const LINUX_DOUBLE: PackedStringArray = ["linux", "x86_64", "64", "pc", "debug", "editor", "double", "threads"]

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
	assert_eq([planned.target, planned.new_extension, planned.replaces, planned.gdextension], ["res://addons/my_lab", false, "res://addons/my_lab/lab.gdextension", "addons/my_lab/lab.gdextension"], "donde el juego ya la tiene")
	var same := NativeInstall.plan(base.path_join("ext/project"), "res://bin/lab.gdextension", base.path_join("game"), "res://addons/my_lab/")
	assert_eq([same.error, same.target], ["", "res://addons/my_lab"], "pedir la carpeta que ya la tiene es lo mismo")
	# m19-05 #12: con target explícito, no se agrega una segunda copia en otro lado.
	var forced := NativeInstall.plan(base.path_join("ext/project"), "res://bin/lab.gdextension", base.path_join("game"), "res://native/lab/")
	assert_true(str(forced.error).contains("would register it twice") and str(forced.error).contains("res://addons/my_lab/lab.gdextension"), "target en otro lado con la extensión ya instalada · %s" % forced.error)
	_write(base.path_join("ext/project/bin/out.gdextension"), "[configuration]\nentry_symbol = \"x\"\n\n[libraries]\nlinux.debug.x86_64 = \"res://other/libx.so\"\n")
	var outside := NativeInstall.plan(base.path_join("ext/project"), "res://bin/out.gdextension", base.path_join("game"))
	assert_true(str(outside.error).contains("points outside res://bin") and str(outside.error).contains("res://other/libx.so"), "una biblioteca fuera de la carpeta no viaja · %s" % outside.error)
	_write(base.path_join("ext/project/root.gdextension"), GDEXT)
	assert_true(str(NativeInstall.plan(base.path_join("ext/project"), "res://root.gdextension", base.path_join("game")).error).contains("at the root"), "en la raíz no hay carpeta que llevar")
	assert_eq(NativeInstall.test_extensions(base.path_join("ext/project")), PackedStringArray(["res://root.gdextension", "res://bin/lab.gdextension", "res://bin/out.gdextension"]), "los .gdextension del proyecto de prueba")
	_write(base.path_join("game/native/lab.gdextension"), GDEXT)
	var twice := NativeInstall.plan(base.path_join("ext/project"), "res://bin/lab.gdextension", base.path_join("game"))
	assert_true(str(twice.error).contains("in several places"), "el juego ya la tiene dos veces: no elige una · %s" % twice.error)


## m19-05 #1: el target pasa por la misma lista de file_tools (ProtectedPaths), normalizado: res:///,
## barras dobles, barra inicial, contrabarras, `..`, carpetas ocultas y unidades de Windows.
func test_target_guard_variants() -> void:
	var base := _layout("native_install_guard")
	var test_project := base.path_join("ext/project")
	var game := base.path_join("game")
	for target: String in ["res://addons/godot_agent", "res:///addons/godot_agent", "addons//godot_agent", "/addons/godot_agent/", "addons\\godot_agent", "res://addons/x/../godot_agent", "res://addons/godot_agent/lab", "/.godot", "res://.godot/x", "project.godot", "res://project.godot", ".git/lab", "res://bin/.hidden"]:
		var planned := NativeInstall.plan(test_project, "res://bin/lab.gdextension", game, target)
		assert_true(str(planned.error).begins_with("Can't install into"), "%s se rechaza · %s" % [target, planned.error])
		assert_eq(planned.files, [], "%s no arma archivos" % target)
	for target: String in ["../outside", "res://../outside", "res://a/../../outside", "C:/lab", "c:\\lab"]:
		var planned := NativeInstall.plan(test_project, "res://bin/lab.gdextension", game, target)
		assert_true(str(planned.error).contains("is outside the project"), "%s está fuera del juego · %s" % [target, planned.error])
	for target: String in ["res://", "/", "res://.", "addons/.."]:
		assert_true(str(NativeInstall.plan(test_project, "res://bin/lab.gdextension", game, target).error).contains("root of the game"), "%s es la raíz" % target)
	var normal := NativeInstall.plan(test_project, "res://bin/lab.gdextension", game, "res:///native//lab/")
	assert_eq([normal.error, normal.target], ["", "res://native/lab"], "una ruta válida con barras de más se normaliza")
	assert_true(Array(normal.files).all(func(file: Dictionary) -> bool: return str(file.to).begins_with("native/lab/")), "y los destinos también")
	# Windows y macOS no distinguen mayúsculas: Addons/Godot_Agent es el harness.
	assert_true(ProtectedPaths.is_protected("res://Addons/Godot_Agent/x", true) and ProtectedPaths.is_protected("res://PROJECT.godot", true), "sin distinguir mayúsculas")
	assert_false(ProtectedPaths.is_protected("res://Addons/Godot_Agent/x", false), "en Linux es otra carpeta")
	assert_eq(FileTools.PROTECTED, ProtectedPaths.PROTECTED, "la misma lista que file_tools")


## m19-05 #1: un enlace simbólico dentro del juego que lleva al harness, a .godot o fuera del juego.
func test_target_guard_symlinks() -> void:
	var base := _layout("native_install_links")
	var game := base.path_join("game")
	DirAccess.make_dir_recursive_absolute(game.path_join("addons/godot_agent"))
	DirAccess.make_dir_recursive_absolute(base.path_join("outside"))
	var dir := DirAccess.open(game)
	assert_eq(dir.create_link(game.path_join("addons/godot_agent"), game.path_join("harness")), OK, "enlace al harness")
	assert_eq(dir.create_link(base.path_join("outside"), game.path_join("away")), OK, "enlace afuera")
	assert_eq(dir.create_link("addons", game.path_join("plugins")), OK, "enlace relativo a una carpeta normal")
	for target: String in ["res://harness", "res://harness/lab"]:
		assert_true(str(NativeInstall.plan(base.path_join("ext/project"), "res://bin/lab.gdextension", game, target).error).contains("leads to res://addons/godot_agent"), "%s lleva al harness" % target)
	assert_true(str(NativeInstall.plan(base.path_join("ext/project"), "res://bin/lab.gdextension", game, "res://away/lab").error).contains("leads outside the project"), "fuera del juego por un enlace")
	assert_eq(NativeInstall.plan(base.path_join("ext/project"), "res://bin/lab.gdextension", game, "res://plugins/lab").error, "", "un enlace a una carpeta del juego sirve")


## m19-05 #2: un addon con el .gdextension en una subcarpeta (addons/foo/bin/foo.gdextension) se
## instala en addons/foo/, no en addons/foo/bin/bin/; si el juego ya lo tiene, se reemplaza ese.
func test_plan_addon_with_gdextension_in_a_subfolder() -> void:
	var base := _fresh_dir("native_install_subfolder")
	var project := base.path_join("ext/demo")
	var game := base.path_join("game")
	_write(project.path_join("project.godot"), "")
	_write(game.path_join("project.godot"), "")
	_write(project.path_join("addons/foo/bin/foo.gdextension"), "[configuration]\nentry_symbol = \"lab_library_init\"\ncompatibility_minimum = \"4.5\"\n\n[libraries]\nlinux.debug.x86_64 = \"res://addons/foo/bin/libfoo.so\"\n")
	_write(project.path_join("addons/foo/bin/libfoo.so"), "ELF " + SYMBOL)
	_write(project.path_join("addons/foo/plugin.cfg"), "")
	var fresh := NativeInstall.plan(project, "res://addons/foo/bin/foo.gdextension", game)
	assert_eq([fresh.error, fresh.target, fresh.gdextension, fresh.new_extension], ["", "res://addons/foo", "addons/foo/bin/foo.gdextension", true], "nueva: addons/foo/ igual · %s" % fresh.error)
	_write(game.path_join("addons/foo/bin/foo.gdextension"), "old")
	var existing := NativeInstall.plan(project, "res://addons/foo/bin/foo.gdextension", game)
	assert_eq([existing.error, existing.target, existing.replaces, existing.new_extension], ["", "res://addons/foo", "res://addons/foo/bin/foo.gdextension", false], "ya está: la misma carpeta del addon, no la del .gdextension")
	assert_eq(Array(existing.files).map(func(file: Dictionary) -> String: return file.to), ["addons/foo/bin/foo.gdextension", "addons/foo/bin/libfoo.so", "addons/foo/plugin.cfg"], "sin bin/bin/")
	var into_bin := NativeInstall.plan(project, "res://addons/foo/bin/foo.gdextension", game, "res://addons/foo/bin")
	assert_true(str(into_bin.error).contains("would register it twice"), "target = la carpeta del .gdextension: quedarían dos · %s" % into_bin.error)
	_remove_tree(game.path_join("addons/foo"))
	_write(game.path_join("native/foo.gdextension"), "old")
	var moved := NativeInstall.plan(project, "res://addons/foo/bin/foo.gdextension", game)
	assert_true(str(moved.error).contains("would leave two copies") and str(moved.error).contains("res://native/foo.gdextension"), "el juego la tiene con otra estructura: no duplica · %s" % moved.error)


## m19-05 #3: un proyecto anidado dentro del juego (el de prueba, con su project.godot) no cuenta:
## Godot no lo escanea, así que su .gdextension no es «la que el juego ya tiene».
func test_nested_project_in_the_game_is_skipped() -> void:
	var base := _layout("native_install_nested")
	var game := base.path_join("game")
	_write(game.path_join("ext/project/project.godot"), "")
	_write(game.path_join("ext/project/bin/lab.gdextension"), GDEXT)
	assert_eq(NativeInstall.game_copies(game, "lab.gdextension"), PackedStringArray(), "no la ve")
	var planned := NativeInstall.plan(base.path_join("ext/project"), "res://bin/lab.gdextension", game)
	assert_eq([planned.error, planned.target, planned.new_extension], ["", "res://addons/lab", true], "va a addons/lab, no adentro del proyecto anidado")


## m19-05 #6: entre varios .gdextension se elige el que se llama como su carpeta de addon; si no hay
## uno solo así, error. Todos los del addon van reescritos, y se revisa el elegido.
func test_pick_gdextension_by_folder_name() -> void:
	var base := _fresh_dir("native_install_pick")
	var project := base.path_join("ext/demo")
	var game := base.path_join("game")
	_write(project.path_join("project.godot"), "")
	_write(game.path_join("project.godot"), "")
	var lab := "[configuration]\nentry_symbol = \"lab_library_init\"\ncompatibility_minimum = \"4.5\"\n\n[libraries]\nlinux.debug.x86_64 = \"res://addons/lab/bin/liblab.so\"\n"
	_write(project.path_join("addons/lab/a_tools.gdextension"), lab.replace("liblab.so", "libtools.so"))
	_write(project.path_join("addons/lab/lab.gdextension"), lab)
	_write(project.path_join("addons/lab/bin/liblab.so"), "ELF " + SYMBOL)
	_write(project.path_join("addons/lab/bin/libtools.so"), "ELF other")
	assert_eq(NativeInstall.pick_gdextension(project), {"path": "res://addons/lab/lab.gdextension", "error": ""}, "el que se llama como la carpeta, no el primero")
	var planned := NativeInstall.plan(project, "res://addons/lab/lab.gdextension", game, "res://addons/lab2")
	assert_eq(planned.gdextension, "addons/lab2/lab.gdextension", "el elegido")
	var texts := Array(planned.files).filter(func(file: Dictionary) -> bool: return file.has("text")).map(func(file: Dictionary) -> String: return file.text)
	assert_true(texts.size() == 2 and texts.all(func(text: String) -> bool: return text.contains("res://addons/lab2/bin/")), "los dos .gdextension reescritos")
	var state := SupervisorState.state_dir(game)
	assert_eq(NativeInstall.stage(planned, state), "", "preparado")
	assert_eq(NativeInstall.check_staged(planned, state, _features(LINUX)).problems, PackedStringArray(), "se revisa el elegido (el otro no tiene el entry_symbol)")
	NativeInstall.discard_pending(state)
	_write(project.path_join("addons/other/other.gdextension"), lab)
	assert_true(str(NativeInstall.pick_gdextension(project).error).contains("more than one is named like its folder"), "dos addons: ambiguo")


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
	var ok: Dictionary = NativeInstall.check(GDEXT, bin, project, _features(LINUX))
	assert_eq([ok.problems, ok.warnings], [PackedStringArray(), PackedStringArray()], "la build sana pasa · %s" % [ok])
	assert_eq(ok.not_built, PackedStringArray(["windows.x86_64"]), "windows sin compilar: se lista, no es problema")
	var on_windows: Dictionary = NativeInstall.check(GDEXT, bin, project, _features(["windows", "x86_64", "64", "pc", "debug", "editor"]))
	assert_true(Array(on_windows.problems).has("windows.debug.x86_64: file not found: res://bin/windows/lab.windows.template_debug.x86_64.dll (it's the key this editor loads)"), "en la plataforma de este editor, faltar la que carga es un problema · %s" % [on_windows])
	assert_true(Array(on_windows.warnings).has("windows.release.x86_64: file not found: res://bin/windows/lab.windows.template_release.x86_64.dll"), "la release que falta, un aviso")
	var no_release := GDEXT.replace("linux.release.x86_64 = \"res://bin/linux/liblab.linux.template_release.x86_64.so\"\n", "")
	var without_release: Dictionary = NativeInstall.check(no_release, bin, project, _features(LINUX))
	assert_true(without_release.problems.is_empty() and Array(without_release.warnings).has("linux.x86_64 has a debug library but no release key: release exports won't load it"), "sin release: aviso, se instala igual")
	var swapped := GDEXT.replace("linux.debug.x86_64 = \"res://bin/linux/liblab.linux.template_debug", "linux.debug.x86_64 = \"res://bin/linux/liblab.linux.template_release")
	assert_true(Array(NativeInstall.check(swapped, bin, project, _features(LINUX)).warnings).any(func(p: String) -> bool: return p.begins_with("linux.debug.x86_64 is a debug key but points to a release library")), "debug que apunta a release")
	var wrong_symbol := GDEXT.replace("entry_symbol = \"lab_library_init\"", "entry_symbol = \"other_init\"")
	var symbol_check: Dictionary = NativeInstall.check(wrong_symbol, bin, project, _features(LINUX))
	assert_true(Array(symbol_check.problems).has("linux.debug.x86_64: entry_symbol other_init not found in res://bin/linux/liblab.linux.template_debug.x86_64.so"), "entry_symbol que no está en la biblioteca que carga el editor: problema · %s" % [symbol_check])
	assert_true(Array(symbol_check.warnings).any(func(p: String) -> bool: return p.begins_with("linux.release.x86_64: entry_symbol other_init")), "en la release, aviso")
	var precision := GDEXT.replace("linux.debug.x86_64 =", "linux.debug.x86_64.double = \"res://bin/linux/liblab.linux.template_debug.x86_64.double.so\"\nlinux.debug.x86_64.single =")
	var single: Dictionary = NativeInstall.check(precision.replace("[icons]", "[other]"), bin, project, _features(LINUX))
	assert_true(single.problems.is_empty(), "la double que no se compiló no frena a un editor single · %s" % [single])
	var double_problems: PackedStringArray = NativeInstall.check(precision.replace("[icons]", "[other]"), bin, project, _features(LINUX_DOUBLE)).problems
	assert_true(Array(double_problems).any(func(p: String) -> bool: return p.begins_with("linux.debug.x86_64.double: file not found")), "un editor double carga la double, que falta · %s" % [double_problems])
	var too_new := GDEXT.replace("compatibility_minimum = \"4.5\"", "compatibility_minimum = \"%d.0\"" % (Engine.get_version_info().major + 1))
	assert_true(Array(NativeInstall.check(too_new, bin, project, _features(LINUX)).problems).any(func(p: String) -> bool: return p.contains("is newer than this Godot")), "pide un Godot más nuevo")
	var bare := "[configuration]\n\n[libraries]\nlinux.debug.x86_64 = \"res://bin/linux/liblab.linux.template_debug.x86_64.so\"\n"
	var bare_problems: PackedStringArray = NativeInstall.check(bare, bin, project, _features(LINUX)).problems
	assert_true(bare_problems.has("[configuration] has no entry_symbol") and bare_problems.has("[configuration] has no compatibility_minimum"), "configuración incompleta")
	assert_true(Array(NativeInstall.check(GDEXT, bin, project, _features(["macos", "arm64", "64", "debug", "editor"])).problems).any(func(p: String) -> bool: return p.begins_with("no library this editor can load on macos.arm64")), "nada que cargar en esta plataforma")


## m19-05 #4: el editor carga la clave con más etiquetas que cumple (la primera en un empate); si a
## esa le falta el archivo, no carga nada aunque otra clave más general tenga la suya.
func test_check_uses_the_key_this_editor_loads() -> void:
	var base := _layout("native_install_loaded_key")
	var bin := base.path_join("ext/project/bin")
	var project := base.path_join("ext/project")
	var config := ConfigFile.new()
	var general := "[configuration]\nentry_symbol = \"lab_library_init\"\ncompatibility_minimum = \"4.5\"\n\n[libraries]\nlinux.x86_64 = \"res://bin/linux/liblab.linux.template_debug.x86_64.so\"\nlinux.debug.x86_64 = \"res://bin/linux/missing.so\"\n"
	config.parse(general)
	assert_eq(NativeInstall.loaded_key(config, "libraries", _features(LINUX)), "linux.debug.x86_64", "la de más etiquetas")
	var problems: PackedStringArray = NativeInstall.check(general, bin, project, _features(LINUX)).problems
	assert_true(problems.has("linux.debug.x86_64: file not found: res://bin/linux/missing.so (it's the key this editor loads)"), "la que carga no tiene archivo: problema, aunque linux.x86_64 exista · %s" % [problems])
	var tie := "[configuration]\nentry_symbol = \"lab_library_init\"\ncompatibility_minimum = \"4.5\"\n\n[libraries]\nlinux.debug.x86_64 = \"res://bin/linux/missing.so\"\nlinux.x86_64.debug = \"res://bin/linux/liblab.linux.template_debug.x86_64.so\"\n"
	config.parse(tie)
	assert_eq(NativeInstall.loaded_key(config, "libraries", _features(LINUX)), "linux.debug.x86_64", "en un empate, la primera")
	assert_false(NativeInstall.check(tie, bin, project, _features(LINUX)).problems.is_empty(), "y falta")
	var release_only := "[configuration]\nentry_symbol = \"lab_library_init\"\ncompatibility_minimum = \"4.5\"\n\n[libraries]\nlinux.release.x86_64 = \"res://bin/linux/liblab.linux.template_release.x86_64.so\"\n"
	assert_true(Array(NativeInstall.check(release_only, bin, project, _features(LINUX)).problems).any(func(p: String) -> bool: return p.begins_with("no library this editor can load on linux.x86_64")), "solo release: el editor no carga ninguna")


func test_stage_check_and_apply() -> void:
	var base := _layout("native_install_stage")
	var game := base.path_join("game")
	_write(game.path_join("addons/lab/linux/liblab.linux.template_debug.x86_64.so"), "old build")
	_write(game.path_join("addons/lab/lab.gdextension"), GDEXT.replace("res://bin/", "res://addons/lab/"))
	# m19-05 #11: lo que dejó una instalación anterior se limpia.
	_write(game.path_join("addons/lab/lab.gdextension.old"), "stale")
	var state := SupervisorState.state_dir(game)
	var planned := NativeInstall.plan(base.path_join("ext/project"), "res://bin/lab.gdextension", game)
	assert_eq(NativeInstall.stage(planned, state), "", "preparado")
	assert_eq(FileAccess.get_file_as_string(game.path_join("addons/lab/linux/liblab.linux.template_debug.x86_64.so")), "old build", "el juego no cambia hasta el reinicio")
	assert_eq(NativeInstall.pending(state).files.size(), 4, "pending.json con los 4 archivos")
	var checked := NativeInstall.check_staged(planned, state)
	assert_eq(checked.problems, PackedStringArray(), "lo preparado se revisa con las rutas nuevas · %s" % [checked.problems])
	var applied := NativeInstall.apply_pending(game, state)
	assert_eq([applied.applied.size(), applied.failed, applied.error], [4, PackedStringArray(), ""], "entra todo")
	assert_true(FileAccess.get_file_as_string(game.path_join("addons/lab/linux/liblab.linux.template_debug.x86_64.so")).contains(SYMBOL), "la build nueva en su lugar")
	assert_true(FileAccess.get_file_as_string(game.path_join("addons/lab/lab.gdextension")).contains("res://addons/lab/linux/"), "el .gdextension reescrito")
	assert_true(NativeInstall.pending(state).is_empty() and not DirAccess.dir_exists_absolute(state.path_join("pending")), "no queda nada preparado")
	assert_eq(NativeInstall.apply_pending(game, state).applied, PackedStringArray(), "sin nada preparado no hace nada")
	assert_eq(_leftovers(game.path_join("addons/lab")), PackedStringArray(), "sin .installing ni .old, tampoco el viejo")
	assert_true(NativeInstall.last_install(state).ok and NativeInstall.pending_line(state).is_empty(), "salió bien: nada que avisar")


## m19-05 #9: preparar de nuevo y fallar deja lo preparado antes como estaba (manifest y archivos).
func test_failed_restage_keeps_the_previous_one() -> void:
	var base := _layout("native_install_restage")
	var game := base.path_join("game")
	var state := SupervisorState.state_dir(game)
	var planned := NativeInstall.plan(base.path_join("ext/project"), "res://bin/lab.gdextension", game)
	assert_eq(NativeInstall.stage(planned, state), "", "primera preparación")
	var before := FileAccess.get_file_as_string(state.path_join("pending.json"))
	var broken := planned.duplicate(true)
	broken.files[1].from = base.path_join("does/not/exist.svg")
	assert_true(NativeInstall.stage(broken, state).begins_with("Could not stage"), "la segunda falla")
	assert_eq(FileAccess.get_file_as_string(state.path_join("pending.json")), before, "el manifest anterior intacto")
	assert_eq(NativeInstall.apply_pending(game, state).applied.size(), 4, "y sus archivos, completos")
	assert_false(DirAccess.dir_exists_absolute(state.path_join("pending.new")) or FileAccess.file_exists(state.path_join("pending.json.new")), "sin restos de la que falló")


## m19-05 #10 y #11: si un archivo no puede entrar, no entra ninguno: vuelve lo que había, lo
## preparado sigue, y la falla se avisa una vez en el dock y en project_info hasta prepararlo de nuevo.
func test_apply_is_all_or_nothing() -> void:
	var base := _layout("native_install_atomic")
	var game := base.path_join("game")
	var state := SupervisorState.state_dir(game)
	var old_text := GDEXT.replace("res://bin/", "res://addons/lab/")
	_write(game.path_join("addons/lab/lab.gdextension"), old_text)
	# lab.svg (el segundo en orden) es una carpeta con algo adentro: el rename falla.
	_write(game.path_join("addons/lab/lab.svg/keep"), "")
	var planned := NativeInstall.plan(base.path_join("ext/project"), "res://bin/lab.gdextension", game)
	assert_eq(NativeInstall.stage(planned, state), "", "preparado")
	var failed := NativeInstall.apply_pending(game, state)
	assert_true(str(failed.error).contains("res://addons/lab/lab.svg") and failed.applied.is_empty() and failed.failed.size() == 4, "falla y no aplica nada · %s" % [failed])
	assert_eq(FileAccess.get_file_as_string(game.path_join("addons/lab/lab.gdextension")), old_text, "el .gdextension que ya había entrado vuelve al viejo")
	assert_false(FileAccess.file_exists(game.path_join("addons/lab/linux/liblab.linux.template_debug.x86_64.so")), "las bibliotecas no quedaron")
	assert_eq(_leftovers(game.path_join("addons/lab")), PackedStringArray(), "sin .installing ni .old")
	assert_eq(NativeInstall.pending(state).files.size(), 4, "lo preparado sigue")
	var line := NativeInstall.pending_line(state)
	assert_true(line.contains("failed and the game kept the build it had") and line.contains("lab.svg") and line.contains("Staged GDExtension install"), "project_info lo dice · %s" % line)
	var failure := NativeInstall.take_install_failure(state)
	assert_eq(failure.get("extensions"), ["lab"], "el aviso del dock, con la extensión")
	assert_eq(NativeInstall.take_install_failure(state), {}, "una sola vez")
	assert_true(NativeInstall.pending_line(state).contains("failed"), "project_info sigue diciéndolo")
	_remove_tree(game.path_join("addons/lab/lab.svg"))
	assert_eq(NativeInstall.apply_pending(game, state).error, "", "arreglado, entra")
	assert_false(NativeInstall.pending_line(state).contains("failed"), "y ya no hay falla que avisar")


## m19-05 #13: apply_pending no confía en las rutas del manifest.
func test_apply_validates_manifest_paths() -> void:
	var base := _layout("native_install_manifest")
	var game := base.path_join("game")
	var state := SupervisorState.state_dir(game)
	for bad: String in ["../evil.txt", "/tmp/evil.txt", "addons/godot_agent/plugin.gd", ".godot/x.txt", "project.godot", "addons//lab/x.txt", "res://x.txt", "addons\\lab\\x.txt"]:
		_write(state.path_join("pending").path_join(bad.trim_prefix("/").replace("../", "up/").replace("res://", "")), "evil")
		_write(state.path_join("pending.json"), JSON.stringify({"files": [bad]}))
		var result := NativeInstall.apply_pending(game, state)
		assert_false(str(result.error).is_empty(), "%s se rechaza · %s" % [bad, result])
		assert_eq(result.applied, PackedStringArray(), "%s no entra" % bad)
	assert_false(FileAccess.file_exists(base.path_join("evil.txt")) or FileAccess.file_exists(game.path_join("addons/godot_agent/plugin.gd")) or FileAccess.get_file_as_string(game.path_join("project.godot")) == "evil", "nada escrito")
	_write(state.path_join("pending.json"), JSON.stringify({"files": ["addons/lab/missing.txt"]}))
	assert_true(str(NativeInstall.apply_pending(game, state).error).contains("is not in"), "un archivo que no está en pending/")
	NativeInstall.discard_pending(state)
	assert_true(NativeInstall.last_install(state).is_empty(), "descartar borra la falla")


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
	assert_false(text.contains("rolled back"), "una nueva no se «vuelve atrás»")
	var again: Dictionary = await tools._install_extension(args)
	assert_true(again.content[0].text.contains("This replaces the install staged before, of lab"), "preparar de nuevo lo dice")
	assert_eq(NativeInstall.pending(state).files.size(), 4, "preparado")
	assert_false(FileAccess.file_exists(game.path_join("addons/lab/lab.gdextension")), "el juego sigue igual")
	var same: Dictionary = await tools._install_extension({"project": game})
	assert_true(same.isError and same.content[0].text.contains("nothing to install"), "el proyecto de prueba no puede ser el juego")
	NativeInstall.discard_pending(state)


## m19-05 #5: el resultado no promete volver atrás si el supervisor no tiene a qué: una nueva se
## desactiva; una que el juego tiene, vuelve al .gdextension y bibliotecas buenas si están en good/.
func test_tool_says_what_a_crash_would_do() -> void:
	var base := _layout("native_install_crash_note")
	var game := base.path_join("game")
	var state := SupervisorState.state_dir(game)
	var tools := DiagnosticTools.new()
	tools.setup(null, game)
	var fresh := NativeInstall.plan(base.path_join("ext/project"), "res://bin/lab.gdextension", game)
	assert_true(tools._crash_note(fresh, state).contains("disables it") and not tools._crash_note(fresh, state).contains("goes back"), "nueva: se desactiva")
	_write(game.path_join("addons/lab/lab.gdextension"), GDEXT.replace("res://bin/", "res://addons/lab/"))
	_write(game.path_join("addons/lab/linux/liblab.linux.template_debug.x86_64.so"), "good build")
	var existing := NativeInstall.plan(base.path_join("ext/project"), "res://bin/lab.gdextension", game)
	assert_true(tools._crash_note(existing, state).contains("has no copy of the build the game has now"), "sin copia buena no promete rollback · %s" % tools._crash_note(existing, state))
	ExtensionSnapshot.snapshot(game, state)
	assert_true(tools._crash_note(existing, state).contains("goes back to the .gdextension and libraries that last started fine"), "con copia buena, vuelve")


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


func _features(features: PackedStringArray) -> Callable:
	return func(tag: String) -> bool: return tag in features


## Los .installing y .old que quedaron en `dir` (recursivo).
func _leftovers(dir: String) -> PackedStringArray:
	var result: PackedStringArray = []
	for file: String in DirAccess.get_files_at(dir):
		if file.ends_with(NativeInstall.OLD_SUFFIX) or file.ends_with(NativeInstall.TMP_SUFFIX):
			result.append(file)
	for sub: String in DirAccess.get_directories_at(dir):
		result.append_array(_leftovers(dir.path_join(sub)))
	return result


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


## Con las carpetas ocultas y sin seguir los enlaces simbólicos (test_target_guard_symlinks): se
## borra el enlace, no lo de adentro.
func _remove_tree(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		return
	var dir := DirAccess.open(path)
	dir.include_hidden = true  # el estado del supervisor está en .godot/
	for file: String in dir.get_files():
		DirAccess.remove_absolute(path.path_join(file))
	for sub: String in dir.get_directories():
		if dir.is_link(sub):
			OS.execute("rm", [path.path_join(sub)])
		else:
			_remove_tree(path.path_join(sub))
	DirAccess.remove_absolute(path)


func _write(path: String, text: String) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()
