extends "test_case.gd"
## GDExtension del proyecto (m19-01): detectar SCons, CMake o Cargo, armar los comandos y leer los
## errores del compilador por archivo y línea.

const NativeBuild := preload("res://addons/godot_agent/core/native_build.gd")


func test_parse_gcc_clang_rustc_msvc() -> void:
	var project := ProjectSettings.globalize_path("res://")
	var root := "/ext/my_ext"
	var lines := PackedStringArray([
		"src/my_node.cpp: In member function 'void godot::MyNode::_process(double)':",
		"src/my_node.cpp:12:5: error: 'undefined_thing' was not declared in this scope",
		"src/my_node.cpp:12:5: error: 'undefined_thing' was not declared in this scope",
		"src/my_node.cpp:3:1: warning: unused variable 'x' [-Wunused-variable]",
		"src/register_types.cpp:4:10: fatal error: missing.h: No such file or directory",
		"%sbin/gen.cpp:7:2: error: expected ';' after expression" % project,
		"src/lib.rs:9:13: error[E0425]: cannot find value `speed` in this scope",
		"C:\\ext\\src\\my_node.cpp(21,8): error C2065: 'foo': undeclared identifier",
		"scons: *** [src/my_node.os] Error 1",
		"error: could not compile `my_ext` (lib) due to 1 previous error",
	])
	var results := NativeBuild.parse_output(lines, root)
	assert_eq(results.keys(), [
		"/ext/my_ext/src/my_node.cpp", "/ext/my_ext/src/register_types.cpp", "res://bin/gen.cpp",
		"/ext/my_ext/src/lib.rs", "C:/ext/src/my_node.cpp",
	], "rutas relativas a la raíz, las del proyecto como res://, sin warnings ni líneas sin archivo")
	assert_eq(results["/ext/my_ext/src/my_node.cpp"].errors, ["line 12: 'undefined_thing' was not declared in this scope"], "sin repetir")
	assert_eq(results["/ext/my_ext/src/register_types.cpp"].errors, ["line 4: missing.h: No such file or directory"], "fatal error")
	assert_eq(results["/ext/my_ext/src/lib.rs"].errors, ["line 9: E0425 cannot find value `speed` in this scope"], "código de rustc")
	assert_eq(results["C:/ext/src/my_node.cpp"].errors, ["line 21: C2065 'foo': undeclared identifier"], "MSVC")


func test_find_project_layouts() -> void:
	var base := _fresh_dir("native_layouts")
	# godot-cpp-template: el editor abre project/ y el SConstruct está arriba.
	DirAccess.make_dir_recursive_absolute(base.path_join("cpp/project"))
	_touch(base.path_join("cpp/SConstruct"))
	var cpp := NativeBuild.find_project(base.path_join("cpp/project"))
	assert_eq([cpp.get("kind"), cpp.get("root")], ["scons", base.path_join("cpp")], "SConstruct en la carpeta de arriba")
	# El libro de gdext: godot/ y rust/ hermanos.
	DirAccess.make_dir_recursive_absolute(base.path_join("rs/godot"))
	DirAccess.make_dir_recursive_absolute(base.path_join("rs/rust"))
	_touch(base.path_join("rs/rust/Cargo.toml"))
	var rust := NativeBuild.find_project(base.path_join("rs/godot/"))
	assert_eq([rust.get("kind"), rust.get("file")], ["cargo", base.path_join("rs/rust/Cargo.toml")], "rust/ al lado del proyecto")
	# En la misma carpeta gana SCons sobre CMake.
	DirAccess.make_dir_recursive_absolute(base.path_join("both/project"))
	_touch(base.path_join("both/project/CMakeLists.txt"))
	_touch(base.path_join("both/project/SConstruct"))
	assert_eq(NativeBuild.find_project(base.path_join("both/project")).get("kind"), "scons", "SCons antes que CMake")
	DirAccess.make_dir_recursive_absolute(base.path_join("none/project"))
	assert_true(NativeBuild.find_project(base.path_join("none/project")).is_empty(), "sin sistema de build")


func test_commands() -> void:
	var scons := NativeBuild.commands({"kind": "scons", "root": "/ext", "file": "/ext/SConstruct"}, "template_release", ["platform=windows"])
	assert_eq(scons, [PackedStringArray(["scons", "-C", "/ext", "target=template_release", "platform=windows"])], "scons -C con target y args")
	var cargo := NativeBuild.commands({"kind": "cargo", "root": "/ext", "file": "/ext/Cargo.toml"}, "template_release", [])
	assert_eq(cargo, [PackedStringArray(["cargo", "build", "--manifest-path", "/ext/Cargo.toml", "--message-format=short", "--release"])], "cargo --release")
	var cmake := NativeBuild.commands({"kind": "cmake", "root": "/ext", "file": "/ext/CMakeLists.txt"}, "template_debug", [])
	assert_eq(cmake.size(), 2, "cmake configura y compila")
	assert_true("-DGODOTCPP_TARGET=template_debug" in cmake[0] and cmake[1][1] == "--build", "el target va en la configuración · %s" % [cmake])


## Con SCons y un compilador de C, compila de verdad un programa con un error y después arreglado.
func test_real_scons_build() -> void:
	if NativeBuild.CommandResolver.resolve("scons").is_empty() or NativeBuild.CommandResolver.resolve("gcc").is_empty():
		print("  (sin scons o gcc: se saltea la compilación real)")
		return
	var root := _fresh_dir("native_scons")
	_write(root.path_join("SConstruct"), "Program('hello', ['hello.c'])\n")
	_write(root.path_join("hello.c"), "int main(void) {\n\treturn undefined_thing;\n}\n")
	var project := NativeBuild.find_project(root)
	var report: Dictionary = await NativeBuild.build(project)
	assert_eq(report.error, "", "scons corrió")
	var source := root.path_join("hello.c")
	assert_true(report.results.has(source) and str(report.results[source].errors).contains("line 2:"), "el error con su línea · %s" % [report.results])
	_write(source, "int main(void) {\n\treturn 0;\n}\n")
	report = await NativeBuild.build(project)
	assert_eq([report.error, report.results], ["", {}], "arreglado, compila")


## Con Cargo, un crate sin dependencias (no baja nada) con un error de rustc.
func test_real_cargo_build() -> void:
	if NativeBuild.CommandResolver.resolve("cargo").is_empty():
		print("  (sin cargo: se saltea la compilación real)")
		return
	var root := _fresh_dir("native_cargo")
	DirAccess.make_dir_recursive_absolute(root.path_join("src"))
	_write(root.path_join("Cargo.toml"), "[package]\nname = \"native_fixture\"\nversion = \"0.1.0\"\nedition = \"2021\"\n\n[lib]\npath = \"src/lib.rs\"\n")
	_write(root.path_join("src/lib.rs"), "pub fn speed() -> f64 {\n\tundefined_speed\n}\n")
	var report: Dictionary = await NativeBuild.build(NativeBuild.find_project(root))
	assert_eq(report.error, "", "cargo corrió")
	var source := root.path_join("src/lib.rs")
	assert_true(report.results.has(source) and str(report.results[source].errors).contains("line 2: E0425"), "el error de rustc · %s" % [report.results])


func test_missing_tool_message() -> void:
	assert_true(NativeBuild.missing_tool_message("scons").contains("pip install scons"), "cómo instalar SCons")
	assert_true(NativeBuild.missing_tool_message("cargo").contains("rustup"), "cómo instalar Rust")


## Una carpeta vacía en user://unit_tests (con subcarpetas, que temp_dir no borra).
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


func _touch(path: String) -> void:
	_write(path, "")


func _write(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()
