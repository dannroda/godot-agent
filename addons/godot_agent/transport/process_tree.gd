@tool
extends RefCounted
## Termina un proceso y sus descendientes. OS.kill solo mata el PID dado, y lanzadores como
## npx dejan un hijo (node) con los pipes abiertos.
## Sin shell: comandos con argumentos en array. En Linux, los hijos salen de /proc sin lanzar nada.


static func kill_tree(pid: int) -> void:
	if pid <= 0:
		return
	if OS.get_name() == "Windows":
		OS.execute("taskkill", ["/T", "/F", "/PID", str(pid)])
		return
	for child: int in descendants(pid):
		OS.kill(child)
	OS.kill(pid)


## Si descendants() puede listar algo en esta plataforma (en Windows, taskkill /T se encarga).
static func can_list_descendants() -> bool:
	return OS.get_name() != "Windows"


## Linux con /proc/<pid>/task/<tid>/children: listar hijos no lanza procesos.
static func has_proc_children() -> bool:
	return OS.get_name() == "Linux" and FileAccess.file_exists("/proc/self/task/%d/children" % OS.get_process_id())


## Descendientes en orden de profundidad (hojas primero).
static func descendants(pid: int) -> PackedInt32Array:
	var result: PackedInt32Array = []
	for child: int in children(pid):
		result.append_array(descendants(child))
		result.append(child)
	return result


## Hijos directos: de /proc en Linux, si no con `pgrep -P`.
static func children(pid: int) -> PackedInt32Array:
	var result: PackedInt32Array = []
	if has_proc_children():
		for task: String in DirAccess.get_directories_at("/proc/%d/task" % pid):
			var file := FileAccess.open("/proc/%d/task/%s/children" % [pid, task], FileAccess.READ)
			if file:
				# Los archivos de /proc reportan largo 0: se leen por línea, no con get_as_text.
				for item: String in file.get_line().split(" ", false):
					result.append(item.to_int())
		return result
	var output: Array = []
	if OS.execute("pgrep", ["-P", str(pid)], output) != 0:
		return result
	for line: String in "\n".join(output).split("\n", false):
		var child := line.strip_edges().to_int()
		if child > 0:
			result.append(child)
	return result


## Si `pid` sigue vivo, para procesos que no son hijos directos (OS.is_process_running da error con
## esos). Sin /proc no se puede saber sin lanzar procesos: se asume vivo.
static func is_alive(pid: int) -> bool:
	if OS.get_name() == "Linux":
		return DirAccess.dir_exists_absolute("/proc/%d" % pid)
	return true
