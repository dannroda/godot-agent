@tool
extends RefCounted
## Archivos de traspaso del One-shot (D41), en el proyecto: `.godot_agent/oneshot/<id>/` con
## spec.md (lo escribe el agente al empezar), progress.md (lo actualiza al cerrar cada tarea) y
## qa-<n>.md (los informes del evaluador). Una sesión nueva retoma leyéndolos. El estado del
## harness va aparte, en user:// (D37).
## `.godot_agent/.gdignore` deja la carpeta fuera del FileSystem del editor y del export; git la
## incluye en los checkpoints, así spec y progreso quedan sincronizados con el código.

const ROOT_DIR := ".godot_agent"
const SPEC := "spec.md"
const PROGRESS := "progress.md"

var project_root: String = ""
var run_id: String = ""


func dir() -> String:
	return project_root.path_join(ROOT_DIR).path_join("oneshot").path_join(run_id)


## Ruta relativa al proyecto, para los prompts y la UI.
func relative_dir() -> String:
	return "%s/oneshot/%s" % [ROOT_DIR, run_id]


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


func has_spec() -> bool:
	return not run_id.is_empty() and FileAccess.file_exists(spec_path())


func read(path: String) -> String:
	return FileAccess.get_file_as_string(path) if FileAccess.file_exists(path) else ""


func write(path: String, text: String) -> bool:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(text)
	file.close()
	return true
