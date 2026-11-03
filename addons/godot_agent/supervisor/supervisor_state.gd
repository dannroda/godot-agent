@tool
extends RefCounted
## Lo que comparten el supervisor del editor (m19-03) y el plugin: archivos en
## `<proyecto>/.godot/agent_supervisor/`. El supervisor corre fuera del editor con `--path` en esa
## carpeta (no tiene project.godot, así que no carga ninguna GDExtension) y por eso este archivo no
## usa rutas res://.
##
## - `ready.json`: el plugin arrancó en el editor `pid` (las bibliotecas cargaron bien).
## - `closed.json`: el plugin salió del editor `pid` sin crash (al cerrar o reiniciar).
## - `restart.json`: el plugin pide relanzar el editor cuando se cierre (reiniciar sin perder la
##   supervisión: el reinicio del propio Godot lanzaría un editor que no es hijo del supervisor).
## - `event.json`: lo que pasó y el plugin tiene que contarle al agente al volver (crash, rollback,
##   reinicio). El plugin lo renombra al leerlo.
## - `supervisor.json`: el pid del supervisor y su latido (`beat`, cada segundo), para saber si sigue vivo.
## - `editor.log`: la salida del editor (`--log-file`), de donde sale el backtrace.
## - `good/`: copia de las bibliotecas con las que el editor arrancó bien por última vez.

## Variable de entorno que el supervisor le pasa al editor: la carpeta de estado.
const ENV_VAR := "GODOT_AGENT_SUPERVISOR"
const DIR_NAME := ".godot/agent_supervisor"
const READY := "ready.json"
const CLOSED := "closed.json"
const RESTART := "restart.json"
const EVENT := "event.json"
const SUPERVISOR := "supervisor.json"
const LOG := "editor.log"
const GOOD_DIR := "good"

## Sin latido del supervisor por más de esto, está muerto.
const HEARTBEAT_TIMEOUT_S := 10

const EVENT_CRASH := "crash"
const EVENT_STARTUP_CRASH := "startup_crash"
const EVENT_RESTART := "restart"
const EVENT_GAVE_UP := "gave_up"


static func state_dir(project_dir: String) -> String:
	return _strip_slash(project_dir).path_join(DIR_NAME)


## La carpeta de estado si este editor corre bajo el supervisor, o "".
static func supervised_dir() -> String:
	return OS.get_environment(ENV_VAR)


static func write_json(dir: String, file: String, data: Dictionary) -> bool:
	DirAccess.make_dir_recursive_absolute(dir)
	var tmp := dir.path_join(file + ".tmp")
	var handle := FileAccess.open(tmp, FileAccess.WRITE)
	if handle == null:
		return false
	handle.store_string(JSON.stringify(data, "\t"))
	handle.close()
	return DirAccess.rename_absolute(tmp, dir.path_join(file)) == OK


static func read_json(dir: String, file: String) -> Dictionary:
	var path := dir.path_join(file)
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}


static func remove(dir: String, file: String) -> void:
	var path := dir.path_join(file)
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)


## Si `pid` escribió `file` (ready o closed).
static func marked_by(dir: String, file: String, pid: int) -> bool:
	return int(read_json(dir, file).get("pid", 0)) == pid and pid > 0


## Si el supervisor de esta carpeta sigue vivo: reescribe supervisor.json cada segundo. No se mira
## el pid, porque OS.is_process_running solo sirve para los procesos hijos (y el supervisor es el
## padre del editor).
static func supervisor_running(dir: String) -> bool:
	var beat := int(read_json(dir, SUPERVISOR).get("beat", 0))
	return beat > 0 and int(Time.get_unix_time_from_system()) - beat <= HEARTBEAT_TIMEOUT_S


## Las líneas del crash en el log del editor: desde `handle_crash:` hasta el final del backtrace de
## GDScript, sin los frames del motor ni de las bibliotecas del sistema (solo los de `project_dir`).
static func crash_lines(log_path: String, project_dir: String) -> PackedStringArray:
	if not FileAccess.file_exists(log_path):
		return PackedStringArray()
	var lines := FileAccess.get_file_as_string(log_path).split("\n")
	var start := -1
	for i: int in range(lines.size() - 1, -1, -1):
		if lines[i].contains("handle_crash:"):
			start = i
			break
	if start < 0:
		return PackedStringArray()
	var frame := RegEx.create_from_string("^\\[\\d+\\] .* - ")
	var root := _strip_slash(project_dir) + "/"
	var result: PackedStringArray = []
	var hidden := 0
	for i: int in range(start, lines.size()):
		var line := lines[i].strip_edges()
		if line.is_empty() or line.begins_with("=====") or line.begins_with("Dumping the backtrace") or line.begins_with("Load address"):
			continue
		if frame.search(line) != null and not line.contains(root):
			hidden += 1
			continue
		if line.begins_with("-- END OF C++") and hidden > 0:
			result.append("(%d frames in Godot or system libraries not shown)" % hidden)
			hidden = 0
		result.append(line)
		if line.begins_with("-- END OF GDSCRIPT"):
			break
	return result


static func _strip_slash(path: String) -> String:
	return path.left(-1) if path.ends_with("/") and path.length() > 1 else path
