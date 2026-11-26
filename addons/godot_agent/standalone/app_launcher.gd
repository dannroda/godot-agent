@tool
extends RefCounted
## Abre la app aparte con un proyecto propio (m20-13): `godot --path <proyecto del juego>` corre los
## autoloads del juego en la ventana del harness, y Godot no deja saltearlos. Así que la app tiene su
## project.godot, sin autoloads, junto a los datos del editor, con una copia del addon al día, y la
## carpeta del juego le llega por --project (ProjectDirs.root lee de ahí lo del usuario).

const AcpRegistry := preload("../core/acp_registry.gd")

const DIR := "godot_agent/app"
const ADDON := "res://addons/godot_agent"
## El config del proyecto del usuario no va en la copia: la app lo lee de la carpeta del juego.
const SKIP := ["config/project_config.tres"]
const PROJECT := """config_version=5

[application]

config/name="Godot Agent"
run/main_scene="res://addons/godot_agent/standalone/main.tscn"
config/features=PackedStringArray("%s")
"""


static func app_dir() -> String:
	return AcpRegistry.editor_data_dir().path_join(DIR)


## El proyecto de la app al día con el addon de `addon_dir`. `{error, changed}`: si cambió algo, hace
## falta importar (las imágenes del addon) antes de abrirla.
static func prepare(target: String = app_dir(), addon_dir: String = ProjectSettings.globalize_path(ADDON)) -> Dictionary:
	DirAccess.make_dir_recursive_absolute(target)
	var project := PROJECT % ("%d.%d" % [Engine.get_version_info().major, Engine.get_version_info().minor])
	var changed := false
	if FileAccess.get_file_as_string(target.path_join("project.godot")) != project:
		var file := FileAccess.open(target.path_join("project.godot"), FileAccess.WRITE)
		if file == null:
			return {"error": FileAccess.get_open_error(), "changed": false}
		file.store_string(project)
		file.close()
		changed = true
	var copied := sync_dir(addon_dir, target.path_join("addons/godot_agent"), "")
	if copied < 0:
		return {"error": ERR_CANT_CREATE, "changed": changed}
	return {"error": OK, "changed": changed or copied > 0}


## Copia lo que falta o cambió de `from` a `to` y borra de `to` lo que ya no está (un script viejo con
## class_name rompería la app). Cuántos archivos cambió, o -1 si alguno no se pudo copiar.
static func sync_dir(from: String, to: String, relative: String) -> int:
	DirAccess.make_dir_recursive_absolute(to)
	var count := 0
	var present := {}
	for name: String in DirAccess.get_files_at(from):
		var rel := relative.path_join(name) if not relative.is_empty() else name
		present[name] = true
		if rel in SKIP:
			continue
		var source := from.path_join(name)
		var destination := to.path_join(name)
		if FileAccess.file_exists(destination) and FileAccess.get_modified_time(destination) >= FileAccess.get_modified_time(source) \
				and FileAccess.get_size(destination) == FileAccess.get_size(source):
			continue
		if DirAccess.copy_absolute(source, destination) != OK:
			return -1
		count += 1
	for name: String in DirAccess.get_directories_at(from):
		present[name] = true
		var inner := sync_dir(from.path_join(name), to.path_join(name), relative.path_join(name) if not relative.is_empty() else name)
		if inner < 0:
			return -1
		count += inner
	for name: String in DirAccess.get_files_at(to):
		if not present.has(name):
			DirAccess.remove_absolute(to.path_join(name))
			count += 1
	for name: String in DirAccess.get_directories_at(to):
		if not present.has(name):
			remove_tree(to.path_join(name))
			count += 1
	return count


## Borra la carpeta `path` con todo lo que tiene (solo dentro del proyecto de la app).
static func remove_tree(path: String) -> void:
	for name: String in DirAccess.get_files_at(path):
		DirAccess.remove_absolute(path.path_join(name))
	for name: String in DirAccess.get_directories_at(path):
		remove_tree(path.path_join(name))
	DirAccess.remove_absolute(path)


## Prepara el proyecto de la app y la abre sobre `project` (la carpeta del juego). Bloquea mientras
## copia e importa (la primera vez, unos segundos): llamarlo desde un hilo. OK o el error.
static func launch(project: String, godot: String = OS.get_executable_path()) -> Error:
	var target := app_dir()
	var prepared := prepare(target)
	if prepared.error != OK:
		return prepared.error
	if prepared.changed:
		OS.execute(godot, PackedStringArray(["--headless", "--path", target, "--import"]))
	var pid := OS.create_process(godot, PackedStringArray(["--path", target, "--", "--project=" + project]))
	return OK if pid > 0 else ERR_CANT_FORK
