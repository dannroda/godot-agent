@tool
extends RefCounted
## Checkpoints del One-shot con git (spec §10):
## - rama `agent/<timestamp>` (con un commit WIP previo en esa rama si había cambios);
## - commit `cpN: <tarea>` antes de cada tarea;
## - "Volver acá" con `reset --hard`, solo si la rama actual es la del agente.
## Nunca hace merge ni push. Los comandos van con OS.execute y argumentos en array (sin shell), en
## un Thread para no trabar el editor. Todo se limita a la carpeta del proyecto (pathspec `.`) y
## excluye `.godot/`, aunque el repo no lo ignore (D24).

const BRANCH_PREFIX := "agent/"
## Identidad para los commits si el repo no tiene una configurada.
const FALLBACK_NAME := "Godot Agent Harness"
const FALLBACK_EMAIL := "godot-agent@localhost"
const PATHSPEC: PackedStringArray = ["--", ".", ":(exclude).godot"]
## Para el resumen de cambios: spec, progreso y QA del One-shot (D41) van en los checkpoints pero no
## son cambios del juego.
const SUMMARY_PATHSPEC: PackedStringArray = ["--", ".", ":(exclude).godot", ":(exclude).godot_agent"]

var root: String = ""
var git_path: String = "git"
var base_branch: String = ""
var base_sha: String = ""
var agent_branch: String = ""
## {name: "cp1", label, sha, at (unix)}, en orden.
var checkpoints: Array[Dictionary] = []
var last_error: String = ""

var _identity: PackedStringArray = []
## Pathspec de `git add`, resuelto la primera vez (ver _add_pathspec).
var _add_spec: PackedStringArray = []


func _init(project_root: String = "") -> void:
	root = project_root


## {code, output}. Corre en un Thread y espera frames hasta que termine.
func run(args: PackedStringArray) -> Dictionary:
	var thread := Thread.new()
	thread.start(_execute.bind(args))
	var tree := Engine.get_main_loop() as SceneTree
	while thread.is_alive():
		await tree.process_frame
	return thread.wait_to_finish()


func _execute(args: PackedStringArray) -> Dictionary:
	var output: Array = []
	var full: PackedStringArray = ["-C", root]
	full.append_array(_identity)
	full.append_array(args)
	var code := OS.execute(git_path, full, output, true)
	return {"code": code, "output": "".join(output).strip_edges()}


## git instalado y el proyecto dentro de un repo con al menos un commit. Si no, last_error dice por qué.
func check_available() -> bool:
	var version := await run(["--version"])
	if version.code != 0:
		last_error = "git no está disponible: los checkpoints quedan desactivados."
		return false
	var inside := await run(["rev-parse", "--is-inside-work-tree"])
	if inside.code != 0 or inside.output != "true":
		last_error = "El proyecto no está en un repo git: los checkpoints quedan desactivados."
		return false
	var head := await run(["rev-parse", "--verify", "HEAD"])
	if head.code != 0:
		last_error = "El repo git no tiene commits todavía: hacé un primer commit para usar checkpoints."
		return false
	return true


## Sin cambios en la carpeta del proyecto (fuera de .godot/).
func is_clean() -> bool:
	var status := await run(PackedStringArray(["status", "--porcelain"]) + PATHSPEC)
	return status.code == 0 and status.output.is_empty()


func current_branch() -> String:
	var branch := await run(["rev-parse", "--abbrev-ref", "HEAD"])
	return branch.output if branch.code == 0 else ""


## Crea la rama del agente. Si había cambios, se commitean como WIP en esa rama (la del usuario no
## se toca) — quien llama ya pidió confirmación. Después crea cp1 "Estado inicial".
func start(timestamp: String = "") -> bool:
	last_error = ""
	await _ensure_identity()
	base_branch = await current_branch()
	var sha := await run(["rev-parse", "HEAD"])
	base_sha = sha.output
	if timestamp.is_empty():
		timestamp = Time.get_datetime_string_from_system().replace("-", "").replace(":", "").replace("T", "-")
	agent_branch = BRANCH_PREFIX + timestamp
	var created := await run(["checkout", "-b", agent_branch])
	if created.code != 0:
		last_error = "No se pudo crear la rama %s: %s" % [agent_branch, created.output]
		return false
	checkpoints.clear()
	var ok := true
	if not await is_clean():
		ok = not (await _commit("WIP antes del one-shot")).is_empty()
	if ok:
		ok = not (await checkpoint("Estado inicial")).is_empty()
	if not ok:
		await _abandon_branch()
	return ok


## Commit `cpN: label` con todo lo que haya (aunque no haya cambios). Devuelve el checkpoint o {}.
func checkpoint(label: String, suffix: String = "") -> Dictionary:
	if not await _on_agent_branch():
		return {}
	var name := "cp%d%s" % [checkpoints.size() + 1, suffix]
	var sha := await _commit("%s: %s" % [name, label])
	if sha.is_empty():
		return {}
	var entry := {"name": name, "label": label, "sha": sha, "at": int(Time.get_unix_time_from_system())}
	checkpoints.append(entry)
	return entry


## "Volver acá": deja la carpeta del proyecto como en el checkpoint. Devuelve las rutas (relativas al
## proyecto) que cambiaron, para recargarlas en el editor, o null si no se pudo.
func restore(checkpoint_entry: Dictionary) -> Variant:
	last_error = ""
	if not await _on_agent_branch():
		return null
	var sha := str(checkpoint_entry.get("sha", ""))
	var changed: PackedStringArray = []
	var diff := await run(PackedStringArray(["diff", "--name-only", "--relative", sha]) + PATHSPEC)
	var untracked := await run(PackedStringArray(["ls-files", "--others", "--exclude-standard"]) + PATHSPEC)
	for output: String in [diff.output, untracked.output]:
		for line: String in output.split("\n", false):
			if not line in changed:
				changed.append(line)
	# Equivale a `reset --hard` limitado a la carpeta del proyecto: si el proyecto vive dentro de un
	# repo más grande, lo de afuera no se toca.
	var reset := await run(["reset", "-q", "--mixed", sha])
	if reset.code != 0:
		last_error = "git reset falló: " + reset.output
		return null
	var checkout := await run(PackedStringArray(["checkout"]) + PATHSPEC)
	if checkout.code != 0:
		last_error = "git checkout falló: " + checkout.output
		return null
	await run(PackedStringArray(["clean", "-fdq"]) + PATHSPEC)
	var index := checkpoints.find(checkpoint_entry)
	if index >= 0:
		checkpoints.resize(index + 1)
	return changed


## Archivos cambiados desde antes del One-shot: {files: [{path, added, removed}], added, removed}.
func changes_summary() -> Dictionary:
	if not await _on_agent_branch():
		return {}
	await run(PackedStringArray(["add", "-A"]) + await _add_pathspec())
	var numstat := await run(PackedStringArray(["diff", "--cached", "--numstat", "--relative", base_sha]) + SUMMARY_PATHSPEC)
	var files: Array[Dictionary] = []
	var added := 0
	var removed := 0
	for line: String in numstat.output.split("\n", false):
		var parts := line.split("\t")
		if parts.size() < 3:
			continue
		var file := {"path": parts[2], "added": int(parts[0]) if parts[0].is_valid_int() else 0, "removed": int(parts[1]) if parts[1].is_valid_int() else 0}
		added += int(file.added)
		removed += int(file.removed)
		files.append(file)
	return {"files": files, "added": added, "removed": removed}


## Contenido de un archivo (relativo al proyecto) antes del One-shot; "" si no existía.
func base_text(path: String) -> String:
	var shown := await run(["show", "%s:./%s" % [base_sha, path]])
	return shown.output if shown.code == 0 else ""


## "Aceptar todo": commit final en la rama del agente, lista para que el usuario haga merge.
func accept(goal: String) -> bool:
	if not await _on_agent_branch():
		return false
	if not await is_clean():
		return not (await _commit("One-shot: %s" % goal.get_slice("\n", 0).left(72))).is_empty()
	return true


## start() falló después de crear la rama: se vuelve a la del usuario (los cambios sin commitear
## siguen en el árbol de trabajo) y se borra la rama vacía.
func _abandon_branch() -> void:
	var error := last_error
	await run(["reset", "-q", "--soft", base_sha])
	await run(["checkout", "-q", base_branch])
	await run(["branch", "-q", "-D", agent_branch])
	agent_branch = ""
	checkpoints.clear()
	last_error = error


func _commit(message: String) -> String:
	var staged := await run(PackedStringArray(["add", "-A"]) + await _add_pathspec())
	if staged.code != 0:
		last_error = "git add falló: " + staged.output
		return ""
	var commit := await run(["commit", "--allow-empty", "--no-verify", "-q", "-m", message])
	if commit.code != 0:
		last_error = "git commit falló: " + commit.output
		return ""
	var sha := await run(["rev-parse", "HEAD"])
	return sha.output


## `git add` sale con error si el pathspec nombra una ruta ignorada, aunque sea para excluirla: si
## el repo ya ignora `.godot/`, alcanza con `.`.
func _add_pathspec() -> PackedStringArray:
	if _add_spec.is_empty():
		var ignored := await run(["check-ignore", "-q", ".godot/"])
		_add_spec = PackedStringArray(["--", "."]) if ignored.code == 0 else PATHSPEC
	return _add_spec


func _on_agent_branch() -> bool:
	var branch := await current_branch()
	if agent_branch.is_empty() or branch != agent_branch:
		last_error = "La rama actual (%s) no es la del agente (%s): no se toca." % [branch, agent_branch]
		return false
	return true


func _ensure_identity() -> void:
	var email := await run(["config", "user.email"])
	_identity = [] if email.code == 0 and not email.output.is_empty() else PackedStringArray(["-c", "user.name=" + FALLBACK_NAME, "-c", "user.email=" + FALLBACK_EMAIL])
