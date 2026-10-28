@tool
extends RefCounted
## Sesión en una copia aparte (m11-09): un `git worktree` del repo en una rama nueva, fuera de la
## carpeta del proyecto (si no, Godot lo importaría), para que un agente trabaje sin tocar el editor
## abierto. Al terminar, lo suyo queda commiteado en esa rama y se puede aplicar al proyecto como
## cambios sin commitear (`git apply`: el harness no hace merge), dejar la rama o descartarla.

const GitCheckpoints := preload("../oneshot/git_checkpoints.gd")
const I18n := preload("../core/i18n.gd")

const BRANCH_PREFIX := "agent/copy-"
const COMMIT_MESSAGE := "Agent session in a separate copy"

var git: GitCheckpoints
## `{dir, project, branch, base, prefix, top}`: carpeta del worktree, el proyecto dentro de ella, la
## rama, el commit de partida, la ruta del proyecto dentro del repo y la raíz del repo principal.
var info: Dictionary = {}
var last_error: String = ""


func _init(project_root: String = "") -> void:
	git = GitCheckpoints.new(project_root)


## Crea el worktree desde HEAD. `stamp` nombra la carpeta y la rama. false (con last_error) si no se
## pudo: sin git, sin commits o git worktree falló.
func create(stamp: String) -> bool:
	if not await git.check_available():
		last_error = git.last_error
		return false
	await git.call(&"_ensure_identity")
	var top: String = (await git.run(["rev-parse", "--show-toplevel"])).output
	var prefix: String = str((await git.run(["rev-parse", "--show-prefix"])).output).trim_suffix("/")
	var base: String = (await git.run(["rev-parse", "HEAD"])).output
	var base_branch: String = (await git.run(["rev-parse", "--abbrev-ref", "HEAD"])).output
	var dir := worktree_dir(top, stamp)
	var branch := BRANCH_PREFIX + stamp
	var added := await git.run(["worktree", "add", "-q", "-b", branch, dir, base])
	if added.code != 0:
		last_error = I18n.t("git worktree failed: %s") % added.output
		return false
	info = {"dir": dir, "project": dir.path_join(prefix) if not prefix.is_empty() else dir, "branch": branch, "base": base, "base_branch": base_branch, "prefix": prefix, "top": top}
	return true


## Al lado del repo y no adentro: `<repo>.godot-agent-copies/<stamp>`.
static func worktree_dir(top: String, stamp: String) -> String:
	return top.get_base_dir().path_join("%s.godot-agent-copies" % top.get_file()).path_join(stamp)


## Commitea en la rama de la copia todo lo que el agente dejó (si hay algo). Devuelve los archivos
## que cambiaron desde el commit de partida, relativos al proyecto.
func commit_changes() -> PackedStringArray:
	var copy := _in_copy()
	await copy.run(["add", "-A", "--", "."])
	var staged := await copy.run(["diff", "--cached", "--quiet"])
	if staged.code != 0:
		await copy.run(["commit", "-q", "--no-verify", "-m", COMMIT_MESSAGE])
	var names := await copy.run(["diff", "--name-only", "--relative", str(info.base), str(info.branch), "--", "."])
	return str(names.output).split("\n", false)


## Aplica al proyecto lo que cambió en la rama de la copia, como cambios sin commitear. Devuelve ""
## o el error (por ejemplo, si el usuario cambió esos mismos archivos y el parche no entra).
func apply_to_project() -> String:
	var copy := _in_copy()
	# Fuera del worktree, para que no quede como archivo sin trackear en la copia.
	var patch := str(info.dir).get_base_dir().path_join("%s.patch" % str(info.dir).get_file())
	# Desde la carpeta del proyecto en la copia: «.» limita el diff al proyecto y las rutas quedan
	# relativas a la raíz del repo, como las espera `git apply` en la raíz del repo principal.
	var diff := await copy.run(["diff", "--binary", "--output=" + patch, str(info.base), str(info.branch), "--", "."])
	if diff.code != 0:
		return I18n.t("git diff failed: %s") % diff.output
	var applied := await git.run(["-C", str(info.top), "apply", "--whitespace=nowarn", patch])
	DirAccess.remove_absolute(patch)
	return "" if applied.code == 0 else I18n.t("The changes don't apply cleanly (did you change those files too?): %s. They stay in the branch %s.") % [applied.output, info.branch]


## Saca el worktree. Con `delete_branch`, también la rama (se pierde lo que tenía).
func remove(delete_branch: bool) -> void:
	await git.run(["worktree", "remove", "--force", str(info.dir)])
	if delete_branch:
		await git.run(["branch", "-D", str(info.branch)])


func _in_copy() -> GitCheckpoints:
	var copy := GitCheckpoints.new(str(info.project))
	copy.set(&"_identity", git.get(&"_identity"))
	return copy
