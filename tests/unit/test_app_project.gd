extends "test_case.gd"
## m20-13: la app aparte con un proyecto propio. Lo del usuario se lee de la carpeta elegida
## (ProjectDirs.root), su user:// se calcula como Godot, y AppLauncher arma la copia del addon.

const ProjectDirs := preload("res://addons/godot_agent/core/project_dirs.gd")
const ProjectConfig := preload("res://addons/godot_agent/config/project_config.gd")
const AppLauncher := preload("res://addons/godot_agent/standalone/app_launcher.gd")

const TMP := "user://test_app_project"


func test_paths_of_the_chosen_project() -> void:
	assert_eq(ProjectDirs.to_fs("res://agent_modes"), "res://agent_modes", "en el editor, res:// queda igual")
	ProjectDirs.root = "/juegos/uno"
	assert_eq(ProjectDirs.to_fs("res://agent_modes"), "/juegos/uno/agent_modes", "fuera, la carpeta del proyecto")
	assert_eq(ProjectDirs.to_fs("user://x"), "user://x", "lo que no es res:// no cambia")
	assert_eq(ProjectDirs.globalize("res://"), "/juegos/uno/", "globalize también")
	ProjectDirs.root = ""


func test_user_dir_like_godot() -> void:
	var here := ProjectSettings.globalize_path("res://").trim_suffix("/")
	# Los tests redirigen user:// a una subcarpeta por checkout (test_user_dir.gd): se compara sin ella.
	assert_eq(ProjectDirs.user_dir_of(here), OS.get_user_data_dir().get_slice("/checkouts/", 0), "el user:// de este proyecto, como lo calcula Godot")
	var dir := ProjectSettings.globalize_path(TMP).path_join("custom")
	DirAccess.make_dir_recursive_absolute(dir)
	FileAccess.open(dir.path_join("project.godot"), FileAccess.WRITE).store_string("config_version=5\n[application]\nconfig/name=\"Mi juego\"\nconfig/use_custom_user_dir=true\nconfig/custom_user_dir_name=\"mi_juego\"\n")
	assert_eq(ProjectDirs.user_dir_of(dir, "/datos"), "/datos/mi_juego", "con carpeta propia")
	assert_eq(ProjectDirs.user_dir_of(dir.path_join("nada")), "", "sin project.godot")
	_clean()


func test_config_from_the_chosen_project() -> void:
	var dir := ProjectSettings.globalize_path(TMP).path_join("game")
	DirAccess.make_dir_recursive_absolute(dir.path_join("addons/godot_agent/config"))
	ProjectDirs.root = dir
	var config: Resource = ProjectConfig.new()
	config.set(&"turn_snapshots", false)
	assert_eq(config.call(&"save_to_project"), OK, "se guarda en la carpeta elegida")
	assert_true(FileAccess.file_exists(dir.path_join("addons/godot_agent/config/project_config.tres")), "ahí, no en res://")
	assert_false(ProjectConfig.load_or_default().get(&"turn_snapshots"), "y se lee de ahí")
	ProjectDirs.root = ""
	_clean()


func test_launcher_keeps_its_copy_in_sync() -> void:
	var target := ProjectSettings.globalize_path(TMP).path_join("app")
	var first := AppLauncher.prepare(target)
	assert_eq([first.error, first.changed], [OK, true], "la primera vez copia")
	assert_true(FileAccess.file_exists(target.path_join("addons/godot_agent/standalone/main.gd")), "el addon")
	assert_true(FileAccess.get_file_as_string(target.path_join("project.godot")).contains("standalone/main.tscn"), "con la app como escena principal")
	assert_false(FileAccess.get_file_as_string(target.path_join("project.godot")).contains("autoload"), "y sin autoloads")
	assert_true(FileAccess.get_file_as_string(target.path_join("project.godot")).contains("res://icon.svg") and FileAccess.get_file_as_string(target.path_join("icon.svg")).contains("#f0a85a"), "con el logo del proyecto como ícono (m21-15)")
	assert_false(FileAccess.file_exists(target.path_join("addons/godot_agent/config/project_config.tres")), "sin el config del usuario")
	assert_false(AppLauncher.prepare(target).changed, "la segunda, nada que copiar")
	FileAccess.open(target.path_join("addons/godot_agent/stale.gd"), FileAccess.WRITE).store_string("class_name Old\n")
	DirAccess.make_dir_recursive_absolute(target.path_join("addons/godot_agent/old_dir"))
	assert_true(AppLauncher.prepare(target).changed, "lo que ya no está en el addon")
	assert_false(FileAccess.file_exists(target.path_join("addons/godot_agent/stale.gd")) or DirAccess.dir_exists_absolute(target.path_join("addons/godot_agent/old_dir")), "se borra")
	_clean()


func _clean() -> void:
	AppLauncher.remove_tree(ProjectSettings.globalize_path(TMP))


## m21-21: otra carpeta se abre en otra ventana de la app, con --project.
func test_other_project_window_args() -> void:
	var Main := load("res://addons/godot_agent/standalone/main.gd")
	assert_eq(Main.project_window_args("/juegos/dos/"), PackedStringArray(["--", "--project=/juegos/dos"]), "la carpeta, sin barra final")
