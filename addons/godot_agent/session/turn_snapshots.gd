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
## La carpeta del proyecto dentro del repo ("" si es la raíz, si no "sub/carpeta/"): un parche armado
## con --relative se aplica con --directory.
var _prefix: String = ""
## Lo que usa git con el index propio o escribe en el proyecto va de a uno (m11-34): un peek() del
## contador no puede correr a la vez que un take() o un rechazo.
var _busy: bool = false
## sesión -> {sha, msec} del último take() (el contador vivo busca ahí el principio del turno).
var _latest: Dictionary = {}


func _init(project_root: String = "") -> void:
	git = GitCheckpoints.new(project_root)


## Mira si se puede usar git en el proyecto. Se espera con await.
func setup() -> bool:
	available = await git.check_available()
	if not available:
		return false
	await git.ensure_identity()
	_git_dir = _absolute((await git.run(["rev-parse", "--git-dir"])).output)
	_prefix = (await git.run(["rev-parse", "--show-prefix"])).output
	return true


## Espera su turno para usar git (ver _busy). Siempre con _unlock() después.
func _lock() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	while _busy:
		await tree.process_frame
	_busy = true


func _unlock() -> void:
	_busy = false


## Commit con el estado actual de la carpeta del proyecto; "" si no se pudo.
func take(session: String) -> String:
	if not available:
		return ""
	await _lock()
	var sha := await _take(session)
	_unlock()
	if not sha.is_empty():
		_latest[session] = {"sha": sha, "msec": Time.get_ticks_msec()}
	return sha


## El último snapshot de `session` si se tomó en `since_msec` o después; si no, "".
func latest_take(session: String, since_msec: int) -> String:
	var taken: Dictionary = _latest.get(session, {})
	return str(taken.sha) if not taken.is_empty() and int(taken.msec) >= since_msec else ""


func _take(session: String) -> String:
	var index := _git_dir.path_join("godot-agent-index-%s" % session.validate_filename())
	# El index propio se arma una vez desde HEAD y después se reusa: lo escribe siempre git, así su
	# fecha sirve para detectar archivos cambiados en el mismo segundo («racy git»). Copiar el index
	# del usuario cada vez le pondría una fecha nueva y git podría no ver un cambio de igual tamaño.
	if not FileAccess.file_exists(index) and (await _run_with_index(index, PackedStringArray(["read-tree", "HEAD"]))).code != 0:
		return ""
	var added := await _run_with_index(index, PackedStringArray(["add", "-A"]) + await git.add_pathspec())
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


## El diff unificado entre dos snapshots (o un árbol de peek), en la carpeta del proyecto (m11-28).
func patch(from: String, to: String) -> String:
	var shown := await git.run(PackedStringArray(["diff", "--no-renames", "--no-color", "-U3", "--relative", from, to]) + PATHSPEC, false)
	return shown.output if shown.code == 0 else ""


## El contenido de un archivo (relativo al proyecto) en un snapshot; "" si no estaba.
func text_at(sha: String, path: String) -> String:
	var shown := await git.run(["show", "%s:./%s" % [sha, path]])
	return shown.output if shown.code == 0 else ""


## Deja los archivos de la carpeta del proyecto (todos, o solo `paths`) como en el snapshot `sha`:
## restaura los que cambiaron o se borraron y borra los que se crearon después. Devuelve
## `{changed, before}`: las rutas (relativas al proyecto) que tocó, para recargarlas en el editor, y
## el snapshot de cómo estaba todo antes de restaurar (para deshacerlo); {} si no se pudo.
func restore(session: String, sha: String, paths: PackedStringArray = []) -> Dictionary:
	if not available:
		return {}
	await _lock()
	var result := await _restore(session, sha, paths)
	_unlock()
	return result


func _restore(session: String, sha: String, paths: PackedStringArray) -> Dictionary:
	var now := await _take(session)
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


## Lo que cambió desde `from` hasta ahora, sin guardar un snapshot (el contador vivo, m11-34): arma
## el árbol con otro index propio (el de take() no se toca) y no deja commit ni ref. Mismo formato que
## diff(), más `tree` (el árbol de ahora); {} si no se pudo.
func peek(session: String, from: String) -> Dictionary:
	if not available or from.is_empty():
		return {}
	await _lock()
	var index := _git_dir.path_join("godot-agent-peek-%s" % session.validate_filename())
	var tree := ""
	if FileAccess.file_exists(index) or (await _run_with_index(index, PackedStringArray(["read-tree", "HEAD"]))).code == 0:
		if (await _run_with_index(index, PackedStringArray(["add", "-A"]) + await git.add_pathspec())).code == 0:
			var written := await _run_with_index(index, PackedStringArray(["write-tree"]))
			tree = written.output if written.code == 0 else ""
	var result := {}
	if not tree.is_empty():
		result = await diff(from, tree)
		result["tree"] = tree  # para ver los trozos hasta ahora (git diff acepta un árbol)
	_unlock()
	return result


## Los trozos de lo que cambió `path` (relativo al proyecto) entre dos snapshots: cada uno
## {index, path, patch (el parche de ese trozo solo, con su encabezado), old_start, old_count,
## new_start, new_count, lines}. Vacío si no cambió, o si es binario (no tiene trozos).
func hunks(from: String, to: String, path: String) -> Array[Dictionary]:
	var shown := await git.run(PackedStringArray(["diff", "--no-renames", "--no-color", "-U3", "--relative", from, to, "--", path]), false)
	return parse_hunks(shown.output if shown.code == 0 else "", path)


## Los trozos de la salida de `git diff` de un archivo (ver hunks()).
static func parse_hunks(diff_text: String, path: String = "") -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var header: PackedStringArray = []
	var current: Dictionary = {}
	var lines := diff_text.split("\n")
	if not lines.is_empty() and lines[lines.size() - 1].is_empty():
		lines.resize(lines.size() - 1)
	for line: String in lines:
		if line.begins_with("@@ "):
			current = _hunk_from_header(line, result.size(), path)
			current.header = header
			result.append(current)
		elif current.is_empty():
			header.append(line)
		else:
			current.lines.append(line)
	for hunk: Dictionary in result:
		hunk.patch = "\n".join(hunk.header) + "\n" + hunk.at + "\n" + "\n".join(hunk.lines) + "\n"
		hunk.erase("header")
	return result


static func _hunk_from_header(line: String, index: int, path: String) -> Dictionary:
	var ranges := line.get_slice("@@", 1).strip_edges().split(" ")
	var old := ranges[0].trim_prefix("-").split(",")
	var new := ranges[1].trim_prefix("+").split(",") if ranges.size() > 1 else PackedStringArray(["0"])
	return {
		"index": index, "path": path, "at": line, "lines": PackedStringArray(),
		"old_start": int(old[0]), "old_count": int(old[1]) if old.size() > 1 else 1,
		"new_start": int(new[0]), "new_count": int(new[1]) if new.size() > 1 else 1,
	}


## Las líneas que cambia un trozo, sin el contexto: {old_line (la primera que cambia en el archivo de
## antes), new_first y new_last (las que quedaron en el de después; new_last < new_first si solo
## borra)}.
static func changed_lines(hunk: Dictionary) -> Dictionary:
	var lead := 0
	for line: String in hunk.lines:
		if not line.begins_with(" "):
			break
		lead += 1
	var added := 0
	for line: String in hunk.lines:
		if line.begins_with("+"):
			added += 1
	var old_line := int(hunk.old_start) + lead if int(hunk.old_count) > 0 else int(hunk.old_start) + 1
	var new_first := int(hunk.new_start) + lead if int(hunk.new_count) > 0 else int(hunk.new_start) + 1
	return {"old_line": maxi(old_line, 1), "new_first": maxi(new_first, 1), "new_last": maxi(new_first, 1) + added - 1}


## true si el trozo se puede rechazar ahora (deshacerlo sobre el archivo actual) sin pisar nada: con
## `undo`, si se puede volver a aplicar.
func can_apply(hunk: Dictionary, undo: bool = false) -> bool:
	await _lock()
	var ok: bool = (await _apply(hunk, not undo, true)).code == 0
	_unlock()
	return ok


## Rechaza un trozo (lo deshace en el archivo actual) o, con `undo`, lo vuelve a aplicar. Si esas
## líneas cambiaron después, no escribe nada. Devuelve {ok, error}.
func apply_hunk(hunk: Dictionary, undo: bool = false) -> Dictionary:
	await _lock()
	var checked := await _apply(hunk, not undo, true)
	var result := {"ok": false, "error": checked.output}
	if checked.code == 0:
		var applied := await _apply(hunk, not undo, false)
		result = {"ok": applied.code == 0, "error": applied.output if applied.code != 0 else ""}
	_unlock()
	return result


func _apply(hunk: Dictionary, reverse: bool, check_only: bool) -> Dictionary:
	var patch_path := _git_dir.path_join("godot-agent-hunk.patch")
	var file := FileAccess.open(patch_path, FileAccess.WRITE)
	if file == null:
		return {"code": 1, "output": "could not write the patch"}
	file.store_string(str(hunk.patch))
	file.close()
	var args := PackedStringArray(["apply", "--whitespace=nowarn"])
	if reverse:
		args.append("-R")
	if check_only:
		args.append("--check")
	if not _prefix.is_empty():
		args.append("--directory=" + _prefix.trim_suffix("/"))
	args.append(patch_path)
	return await git.run(args)


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
## por `env` (o `cmd /c set` en Windows), con GitCheckpoints.execute.
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
	return await GitCheckpoints.execute(program, program_args)


func _absolute(path: String) -> String:
	return path if path.is_absolute_path() else git.root.path_join(path).simplify_path()
