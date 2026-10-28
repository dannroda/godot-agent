@tool
extends RefCounted
## GitHub con el CLI `gh` (m11-10), opcional: traer los comentarios de revisión de un PR como
## hallazgos de Revisar (solo lee) y abrir un PR con la rama de una sesión en una copia aparte (eso
## pushea: solo si el proyecto lo permite, ver ProjectConfig.github_pull_requests).

const I18n := preload("i18n.gd")

var project_root: String = ""
var gh_path: String = "gh"
var git_path: String = "git"


func _init(root: String = "") -> void:
	project_root = root


## Los comentarios de revisión del PR `pr` (número, o "" para el de la rama actual) como hallazgos:
## `{findings, url, error}`. Los que no son de archivos del proyecto o no tienen línea quedan afuera.
func fetch_review(pr: String) -> Dictionary:
	var repo := await _repo()
	if repo.is_empty():
		return {"findings": [], "url": "", "error": I18n.t("The project's git remote «origin» is not a GitHub repository.")}
	var target := pr.strip_edges().trim_prefix("#")
	if target.is_empty():
		target = (await _run(git_path, ["-C", project_root, "rev-parse", "--abbrev-ref", "HEAD"])).output
	var view := await _run(gh_path, ["pr", "view", target, "--repo", repo, "--json", "number,url"])
	var info: Variant = JSON.parse_string(view.output) if view.code == 0 else null
	if not info is Dictionary:
		return {"findings": [], "url": "", "error": I18n.t("gh could not find the pull request: %s") % view.output.left(300)}
	var comments := await _run(gh_path, ["api", "--paginate", "repos/%s/pulls/%d/comments" % [repo, int(info.number)]])
	var list: Variant = JSON.parse_string(comments.output) if comments.code == 0 else null
	if not list is Array:
		return {"findings": [], "url": str(info.url), "error": I18n.t("gh could not read the review comments: %s") % comments.output.left(300)}
	var prefix: String = str((await _run(git_path, ["-C", project_root, "rev-parse", "--show-prefix"])).output).trim_suffix("/")
	return {"findings": comments_to_findings(list, prefix), "url": str(info.url), "error": ""}


## Pushea `branch` desde `copy_dir` y abre un PR contra `base`. `{url, error}`.
func open_pull_request(copy_dir: String, branch: String, base: String, title: String, body: String) -> Dictionary:
	var repo := await _repo()
	if repo.is_empty():
		return {"url": "", "error": I18n.t("The project's git remote «origin» is not a GitHub repository.")}
	var pushed := await _run(git_path, ["-C", copy_dir, "push", "-u", "origin", branch])
	if pushed.code != 0:
		return {"url": "", "error": I18n.t("git push failed: %s") % pushed.output.left(300)}
	var created := await _run(gh_path, ["pr", "create", "--repo", repo, "--head", branch, "--base", base, "--title", title, "--body", body])
	if created.code != 0:
		return {"url": "", "error": I18n.t("gh could not open the pull request: %s") % created.output.left(300)}
	return {"url": created.output.strip_edges().get_slice("\n", created.output.strip_edges().get_slice_count("\n") - 1), "error": ""}


## `owner/repo` de una URL de remote de GitHub (ssh o https), o "".
static func repo_from_remote(url: String) -> String:
	var found := RegEx.create_from_string("github\\.com[:/]([^/\\s]+)/([^/\\s]+?)(?:\\.git)?/?$").search(url.strip_edges())
	return "%s/%s" % [found.get_string(1), found.get_string(2)] if found else ""


## Comentarios de la API de GitHub (pulls/N/comments) → hallazgos de Revisar. `prefix` es la carpeta
## del proyecto dentro del repo ("" si es la raíz). Las respuestas de un hilo no se repiten.
static func comments_to_findings(comments: Array, prefix: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for comment: Variant in comments:
		if not comment is Dictionary or comment.get("in_reply_to_id") != null or not comment.get("path") is String:
			continue
		var path := str(comment.path)
		if not prefix.is_empty():
			if not path.begins_with(prefix + "/"):
				continue
			path = path.trim_prefix(prefix + "/")
		var line: Variant = comment.get("line") if comment.get("line") != null else comment.get("original_line")
		var body := str(comment.get("body", "")).strip_edges()
		if line == null or body.is_empty():
			continue
		var author := str(comment.user.get("login", "")) if comment.get("user") is Dictionary else ""
		result.append({
			"path": "res://" + path,
			"line": int(line),
			"severity": "style",
			"title": body.get_slice("\n", 0).left(120),
			"body": body + ("\n\n— @%s on GitHub" % author if not author.is_empty() else ""),
			"suggestion": "",
		})
	return result


func _repo() -> String:
	var remote := await _run(git_path, ["-C", project_root, "remote", "get-url", "origin"])
	return repo_from_remote(remote.output) if remote.code == 0 else ""


## `{code, output}` en un Thread, esperando frames (como GitCheckpoints.run).
func _run(program: String, args: PackedStringArray) -> Dictionary:
	var thread := Thread.new()
	thread.start(func() -> Dictionary:
		var output: Array = []
		var code := OS.execute(program, args, output, true)
		return {"code": code, "output": "".join(output).strip_edges()})
	var tree := Engine.get_main_loop() as SceneTree
	while thread.is_alive():
		await tree.process_frame
	return thread.wait_to_finish()
