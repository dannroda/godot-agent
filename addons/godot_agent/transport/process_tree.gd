@tool
extends RefCounted
## Termina un proceso y sus descendientes. OS.kill solo mata el PID dado, y lanzadores como
## npx dejan un hijo (node) con los pipes abiertos: los threads lectores no terminarían nunca.
## Sin shell: comandos con argumentos en array.


static func kill_tree(pid: int) -> void:
	if pid <= 0:
		return
	if OS.get_name() == "Windows":
		OS.execute("taskkill", ["/T", "/F", "/PID", str(pid)])
		return
	for child: int in descendants(pid):
		OS.kill(child)
	OS.kill(pid)


## Descendientes en orden de profundidad (hojas primero) vía `pgrep -P`.
static func descendants(pid: int) -> PackedInt32Array:
	var result: PackedInt32Array = []
	var output: Array = []
	if OS.execute("pgrep", ["-P", str(pid)], output) != 0:
		return result
	for line: String in "\n".join(output).split("\n", false):
		var child := line.strip_edges().to_int()
		if child > 0:
			result.append_array(descendants(child))
			result.append(child)
	return result
