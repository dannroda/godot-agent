@tool
extends RefCounted
## Archivos de traspaso del One-shot (D41), en el proyecto: `.godot_agent/oneshot/<id>/` con
## spec.md (lo escribe el agente al empezar), progress.md (lo actualiza al cerrar cada tarea) y
## qa-<n>.md (los informes del evaluador). Una sesión nueva retoma leyéndolos. El estado del
## harness va aparte, en user:// (D37).
## `.godot_agent/.gdignore` deja la carpeta fuera del FileSystem del editor y del export; git la
## incluye en los checkpoints, así spec y progreso quedan sincronizados con el código.

const AtomicFile := preload("../core/atomic_file.gd")

const ROOT_DIR := ".godot_agent"
const SPEC := "spec.md"
const PROGRESS := "progress.md"
## Archivos de referencia que dio el usuario (un GDD, arte de referencia…) y venían de afuera del
## proyecto: se copian acá, adentro, donde el agente trabaja.
const REFS_DIR := "refs"
## Tope por archivo de referencia: la copia viaja en la rama del agente con los checkpoints.
const MAX_REFERENCE_BYTES := 50 * 1024 * 1024

var project_root: String = ""
var run_id: String = ""


func dir() -> String:
	return project_root.path_join(ROOT_DIR).path_join("oneshot").path_join(run_id)


## Ruta relativa al proyecto, para los prompts y la UI.
func relative_dir() -> String:
	return "%s/oneshot/%s" % [ROOT_DIR, run_id]


func refs_dir() -> String:
	return dir().path_join(REFS_DIR)


## Deja los archivos de referencia donde el agente los lee: los del proyecto, en su lugar; los de
## afuera, copiados a refs/. {paths: rutas absolutas para el prompt, skipped: nombres que no se
## pudieron usar (no existen, son muy grandes o no se copiaron)}.
func add_references(paths: PackedStringArray) -> Dictionary:
	var result: PackedStringArray = []
	var skipped: PackedStringArray = []
	var root := project_root.simplify_path().trim_suffix("/") + "/"
	for path: String in paths:
		var absolute := ProjectSettings.globalize_path(path) if path.begins_with("res://") else path.simplify_path()
		if not FileAccess.file_exists(absolute):
			skipped.append(path.get_file())
			continue
		if absolute.begins_with(root):
			if not result.has(absolute):
				result.append(absolute)
			continue
		var file := FileAccess.open(absolute, FileAccess.READ)
		var too_big := file == null or file.get_length() > MAX_REFERENCE_BYTES
		if file:
			file.close()
		if too_big or DirAccess.make_dir_recursive_absolute(refs_dir()) != OK:
			skipped.append(path.get_file())
			continue
		var target := _free_path(refs_dir(), absolute.get_file())
		if DirAccess.copy_absolute(absolute, target) != OK:
			skipped.append(path.get_file())
			continue
		result.append(target)
	return {"paths": result, "skipped": skipped}


## `name` en `folder`, o `name-2`, `name-3`… si ya hay uno: dos referencias con el mismo nombre no
## se pisan.
static func _free_path(folder: String, name: String) -> String:
	var target := folder.path_join(name)
	var n := 2
	while FileAccess.file_exists(target):
		var extension := name.get_extension()
		target = folder.path_join("%s-%d%s" % [name.get_basename(), n, "." + extension if not extension.is_empty() else ""])
		n += 1
	return target


func spec_path() -> String:
	return dir().path_join(SPEC)


func progress_path() -> String:
	return dir().path_join(PROGRESS)


func qa_path(round_number: int) -> String:
	return dir().path_join("qa-%d.md" % round_number)


func prepare() -> bool:
	if project_root.is_empty() or run_id.is_empty():
		return false
	if DirAccess.make_dir_recursive_absolute(dir()) != OK:
		return false
	var gdignore := project_root.path_join(ROOT_DIR).path_join(".gdignore")
	if not FileAccess.file_exists(gdignore):
		var file := FileAccess.open(gdignore, FileAccess.WRITE)
		if file == null:
			return false
		file.close()
	return true


## qa-<n>.md del run, en orden de vuelta.
func qa_files() -> PackedStringArray:
	var result: PackedStringArray = []
	if run_id.is_empty() or not DirAccess.dir_exists_absolute(dir()):
		return result
	var rounds: Array[int] = []
	for file: String in DirAccess.get_files_at(dir()):
		if file.begins_with("qa-") and file.ends_with(".md") and file.trim_prefix("qa-").trim_suffix(".md").is_valid_int():
			rounds.append(int(file.trim_prefix("qa-").trim_suffix(".md")))
	rounds.sort()
	for round_number: int in rounds:
		result.append(qa_path(round_number))
	return result


func has_spec() -> bool:
	return not run_id.is_empty() and FileAccess.file_exists(spec_path())


func read(path: String) -> String:
	return FileAccess.get_file_as_string(path) if FileAccess.file_exists(path) else ""


func write(path: String, text: String) -> bool:
	return AtomicFile.write_text(path, text) == OK
