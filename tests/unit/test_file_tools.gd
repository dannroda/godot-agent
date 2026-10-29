extends "test_case.gd"
## move_file (m14-05): las rutas relativas de los scripts se recalculan al mover.

const FileTools := preload("res://addons/godot_agent/mcp/tools/file_tools.gd")
const DIR := "res://tests/tmp/unit_relative"


func test_relative_path() -> void:
	assert_eq(FileTools.relative_path("res://a", "res://a/enemy.tscn"), "enemy.tscn", "misma carpeta")
	assert_eq(FileTools.relative_path("res://a/b", "res://a/ui/hud.tscn"), "../ui/hud.tscn", "subir y bajar")
	assert_eq(FileTools.relative_path("res://", "res://a/x.gd"), "a/x.gd", "desde la raíz")
	assert_eq(FileTools.relative_path("res://a/b/c", "res://x.gd"), "../../../x.gd", "hasta la raíz")


func test_relative_rewrites() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR + "/actors"))
	var spawner := DIR + "/spawner.gd"
	var hero := DIR + "/actors/hero.gd"
	_write(spawner, "extends Node\nconst Enemy := preload(\"actors/enemy.tscn\")\nconst Abs := preload(\"res://x.tscn\")\nvar hud = load('hud.tscn')\n")
	_write(hero, "extends \"../base.gd\"\nconst Bullet := preload(\"bullet.tscn\")\n")
	var files := PackedStringArray([spawner, hero])
	# Se mueve la escena que nombra spawner.gd.
	assert_eq(FileTools.relative_rewrites(files, DIR + "/actors/enemy.tscn", DIR + "/enemies/enemy.tscn", false),
		{spawner: {"actors/enemy.tscn": "enemies/enemy.tscn"}}, "lo nombrado se mueve")
	# Se mueve el script: sus rutas relativas se recalculan desde la carpeta nueva.
	assert_eq(FileTools.relative_rewrites(files, hero, DIR + "/players/hero.gd", false),
		{hero: {"bullet.tscn": "../actors/bullet.tscn"}}, "el script se mueve")
	# Se mueve la carpeta: lo de adentro entre sí sigue igual; lo de afuera cambia.
	assert_eq(FileTools.relative_rewrites(files, DIR + "/actors", DIR + "/chars/actors", true),
		{spawner: {"actors/enemy.tscn": "chars/actors/enemy.tscn"}, hero: {"../base.gd": "../../base.gd"}}, "la carpeta se mueve")
	assert_eq(FileTools._rewrite_literals(spawner, {"actors/enemy.tscn": "enemies/enemy.tscn", "hud.tscn": "ui/hud.tscn"}), OK, "reescribe")
	var text := FileAccess.get_file_as_string(spawner)
	assert_true(text.contains("preload(\"enemies/enemy.tscn\")") and text.contains("load('ui/hud.tscn')") and text.contains("res://x.tscn"), "solo los literales · " + text)
	assert_eq(FileTools._rewrite_literals(spawner, {"nada.tscn": "otra.tscn"}), ERR_ALREADY_EXISTS, "sin cambios")
	for path: String in [spawner, hero]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


static func _write(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()
