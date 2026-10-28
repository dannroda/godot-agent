@tool
extends RefCounted
## Snapshots por turno (m11-01, m11-02): el estado de la carpeta del proyecto al empezar y al
## terminar cada turno de Construir o Auto, como commits sueltos colgados de
## `refs/godot-agent/turns/<sesión>/<ms>`. No toca la rama, el index ni el stash del usuario: arma
## cada snapshot con un index propio por sesión (en .git/, por `GIT_INDEX_FILE`), que git reusa para
## releer solo lo que cambió. Con eso se ve qué cambió un turno y se vuelve atrás un archivo o todo.
## Lo que .gitignore ignora queda afuera, y también .godot/ y .godot_agent/ (datos del harness).

const GitCheckpoints := preload("../oneshot/git_checkpoints.gd")

const REF_PREFIX := "refs/godot-agent/turns/"
## Snapshots que se guardan por sesión (dos por turno): los más viejos se sueltan.
const KEEP_PER_SESSION := 60
const MESSAGE := "Godot Agent Harness: turn snapshot"
const PATHSPEC := GitCheckpoints.SUMMARY_PATHSPEC

var git: GitCheckpoints
## false si no hay git, el proyecto no está en un repo o el repo no tiene commits (ver setup()).
var available: bool = false
var _git_dir: String = ""


func _init(project_root: String = "") -> void:
	git = GitCheckpoints.new(project_root)


## Mira si se puede usar git en el proyecto. Se espera con await.
func setup() -> bool:
	available = await git.check_available()
	if not available:
		return false
	await git.call(&"_ensure_identity")
	_git_dir = _absolute((await git.run(["rev-parse", "--git-dir"])).output)
	return true


## Commit con el estado actual de la carpeta del proyecto; "" si no se pudo.
func take(session: String) -> String:
	if not available:
		return ""
	var index := _git_dir.path_join("godot-agent-index-%s" % session.validate_filename())
	# El index propio se arma una vez desde HEAD y después se reusa: lo escribe siempre git, así su
	# fecha sirve para detectar archivos cambiados en el mismo segundo («racy git»). Copiar el index
	# del usuario cada vez le pondría una fecha nueva y git podría no ver un cambio de igual tamaño.
	if not FileAccess.file_exists(index) and (await _run_with_index(index, PackedStringArray(["read-tree", "HEAD"]))).code != 0:
		return ""
	var added := await _run_with_index(index, PackedStringArray(["add", "-A"]) + await git.call(&"_add_pathspec"))
	if added.code != 0:
		return ""
	var tree := await _run_with_index(index, PackedStringArray(["write-tree"]))
	if tree.code != 0:
		return ""
	var commit := await git.run(["commit-tree", tree.output, "-p", "HEAD", "-m", MESSAGE])
	if commit.code != 0:
		return ""
	await git.run(["update-ref", "%s%s/%d" % [REF_PREFIX, session.validate_filename(), int(Time.get_unix_time_from_system() * 1000.0)], commit.output])
	await _prune(session)
	return commit.output


## Lo que cambió entre dos snapshots en la carpeta del proyecto:
## `{files: [{path, status (A, M o D), added, removed}], added, removed}`; rutas relativas al proyecto.
func diff(from: String, to: String) -> Dictionary:
	var numstat := await git.run(PackedStringArray(["diff", "--no-renames", "--numstat", "--relative", from, to]) + PATHSPEC)
	var statuses := await git.run(PackedStringArray(["diff", "--no-renames", "--name-status", "--relative", from, to]) + PATHSPEC)
	return parse_diff(numstat.output, statuses.output)


## El contenido de un archivo (relativo al proyecto) en un snapshot; "" si no estaba.
func text_at(sha: String, path: String) -> String:
	var shown := await git.run(["show", "%s:./%s" % [sha, path]])
	return shown.output if shown.code == 0 else ""


## Deja los archivos de la carpeta del proyecto (todos, o solo `paths`) como en el snapshot `sha`:
## restaura los que cambiaron o se borraron y borra los que se crearon después. Devuelve
## `{changed, before}`: las rutas (relativas al proyecto) que tocó, para recargarlas en el editor, y
## el snapshot de cómo estaba todo antes de restaurar (para deshacerlo); {} si no se pudo.
func restore(session: String, sha: String, paths: PackedStringArray = []) -> Dictionary:
	var now := await take(session)
	if now.is_empty():
		return {}
	var changed: PackedStringArray = []
	var to_restore: PackedStringArray = []
	for file: Dictionary in (await diff(sha, now)).files:
		if not paths.is_empty() and not file.path in paths:
			continue
		changed.append(file.path)
		if file.status == "A":
			DirAccess.remove_absolute(git.root.path_join(file.path))
		else:
			to_restore.append(file.path)
	if not to_restore.is_empty():
		var restored := await git.run(PackedStringArray(["restore", "--source=" + sha, "--worktree", "--"]) + to_restore)
		if restored.code != 0:
			return {}
	return {"changed": changed, "before": now}


## `--numstat` y `--name-status` de git diff juntos (ver diff()).
static func parse_diff(numstat: String, statuses: String) -> Dictionary:
	var status_of := {}
	for line: String in statuses.split("\n", false):
		var parts := line.split("\t")
		if parts.size() >= 2:
			status_of[parts[1]] = parts[0].left(1)
	var files: Array[Dictionary] = []
	var added := 0
	var removed := 0
	for line: String in numstat.split("\n", false):
		var parts := line.split("\t")
		if parts.size() < 3:
			continue
		var file := {"path": parts[2], "status": str(status_of.get(parts[2], "M")),
			"added": int(parts[0]) if parts[0].is_valid_int() else 0, "removed": int(parts[1]) if parts[1].is_valid_int() else 0}
		added += int(file.added)
		removed += int(file.removed)
		files.append(file)
	return {"files": files, "added": added, "removed": removed}


func _prune(session: String) -> void:
	var refs := await git.run(["for-each-ref", "--format=%(refname)", REF_PREFIX + session.validate_filename() + "/"])
	var names := Array(refs.output.split("\n", false))
	names.sort_custom(func(a: String, b: String) -> bool: return int(a.get_file()) < int(b.get_file()))
	for i in maxi(names.size() - KEEP_PER_SESSION, 0):
		await git.run(["update-ref", "-d", names[i]])


## Un comando de git con el index propio. OS.execute no recibe variables de entorno, así que pasa
## por `env` (o `cmd /c set` en Windows) en un Thread, como GitCheckpoints.run.
func _run_with_index(index: String, args: PackedStringArray) -> Dictionary:
	var full := PackedStringArray(["-C", git.root])
	full.append_array(git.get(&"_identity"))
	full.append_array(args)
	var program := "env"
	var program_args := PackedStringArray(["GIT_INDEX_FILE=" + index, git.git_path]) + full
	if OS.get_name() == "Windows":
		program = "cmd.exe"
		var quoted := Array(full).map(func(arg: String) -> String: return "\"%s\"" % arg.replace("\"", "\\\""))
		program_args = PackedStringArray(["/d", "/c", "set \"GIT_INDEX_FILE=%s\" && \"%s\" %s" % [index, git.git_path, " ".join(quoted)]])
	var thread := Thread.new()
	thread.start(func() -> Dictionary:
		var output: Array = []
		var code := OS.execute(program, program_args, output, true)
		return {"code": code, "output": "".join(output).strip_edges()})
	var tree := Engine.get_main_loop() as SceneTree
	while thread.is_alive():
		await tree.process_frame
	return thread.wait_to_finish()


func _absolute(path: String) -> String:
	return path if path.is_absolute_path() else git.root.path_join(path).simplify_path()
