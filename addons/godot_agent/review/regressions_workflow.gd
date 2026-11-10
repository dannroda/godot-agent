@tool
extends RefCounted
## El workflow de GitHub Actions que corre las regresiones de playtest grabadas en el CI del juego
## (m16-10): baja el Godot de la versión del editor, importa el proyecto, corre regression_cli.gd
## (headless, o bajo Xvfb si las regresiones necesitan render) y, si falla, sube el informe y las
## capturas como artifacts. Lo escribe el botón «CI workflow…» del panel de hallazgos y la tool
## godot.write_regressions_workflow; nunca pisa uno que exista sin `overwrite`.

const PATH := "res://.github/workflows/godot-agent-regressions.yml"
const CLI := "res://addons/godot_agent/playtest/regression_cli.gd"
const REGRESSIONS_DIR := ".godot_agent/playtests/regressions"
const REPORT := "regressions-report.txt"
## Avisos de write(): sin repo git (el yml queda en el proyecto y hay que llevarlo a la raíz del
## repo), o una carpeta que el CI necesita está en .gitignore.
const WARN_NO_GIT := "no_git"
const WARN_IGNORED_REGRESSIONS := "ignored_regressions"
const WARN_IGNORED_ADDON := "ignored_addon"
## El editor no es un release oficial (custom_build, dev): la URL de descarga del yml es una suposición.
const WARN_CUSTOM_BUILD := "custom_build"
const WARNING_TEXTS: Dictionary = {
	WARN_CUSTOM_BUILD: "This editor is not an official Godot release, so the download URL in the workflow probably does not exist: point the Install Godot step to a build you host, or to the official release closest to this version.",
	WARN_NO_GIT: "The project is not in a git repository: the workflow was written in the project folder. GitHub only reads .github/workflows/ at the root of the repository, so move it there and adjust --path if the project is in a subfolder.",
	WARN_IGNORED_REGRESSIONS: ".godot_agent/ is ignored by git: the saved regressions won't be in the repository, so the CI will find none. Un-ignore .godot_agent/playtests/regressions/ (or commit it with git add -f).",
	WARN_IGNORED_ADDON: "addons/godot_agent/ is ignored by git: the CI needs the addon to run the regressions. Commit it or install it in the workflow.",
}


## La versión del editor como la nombran los releases de Godot: «4.7.2-stable», «4.8-beta2».
## Las opciones de regression_cli.gd para `repeat` y `fail_on_flaky` (vacío con los valores por defecto).
static func cli_options(repeat: int, fail_on_flaky: bool) -> PackedStringArray:
	var options: PackedStringArray = []
	if repeat > 1:
		options.append("--repeat=%d" % repeat)
	if fail_on_flaky:
		options.append("--fail-on-flaky")
	return options


static func editor_version() -> String:
	var info: Dictionary = Engine.get_version_info()
	var patch := ".%d" % int(info.patch) if int(info.patch) > 0 else ""
	return "%d.%d%s-%s" % [int(info.major), int(info.minor), patch, str(info.status)]


## true si este editor es la versión .NET (los scripts C# del juego necesitan el build mono y dotnet).
static func is_dotnet_editor() -> bool:
	return ClassDB.class_exists("CSharpScript")


## true si el editor es un release oficial de Godot (build "official"); un custom_build no está en
## los releases y la URL de descarga sería una suposición.
static func is_official_build() -> bool:
	return str(Engine.get_version_info().get("build", "")) == "official"


## Las estables salen de godotengine/godot; betas, rc y dev de godotengine/godot-builds. Con
## `dotnet`, el zip mono (trae el binario y GodotSharp/ en una carpeta).
static func download_url(version: String, dotnet: bool = false) -> String:
	var repo := "godotengine/godot" if version.ends_with("-stable") else "godotengine/godot-builds"
	return "https://github.com/%s/releases/download/%s/%s.zip" % [repo, version, zip_name(version, dotnet)]


static func zip_name(version: String, dotnet: bool) -> String:
	return "Godot_v%s_mono_linux_x86_64" % version if dotnet else "Godot_v%s_linux.x86_64" % version


## Dónde está el proyecto respecto del repo git: {toplevel: raíz absoluta ("" sin git),
## project_dir: ruta del proyecto relativa a la raíz ("" si es la raíz), ignored: carpetas que el
## CI necesita y están en .gitignore}. git con OS.execute y argumentos en array, como los checkpoints.
static func repo_info(project_root: String) -> Dictionary:
	var info := {"toplevel": "", "project_dir": "", "ignored": PackedStringArray()}
	var output: Array = []
	if OS.execute("git", ["-C", project_root, "rev-parse", "--show-toplevel"], output, true) != 0 or output.is_empty():
		return info
	info.toplevel = str(output[0]).strip_edges()
	output = []
	if OS.execute("git", ["-C", project_root, "rev-parse", "--show-prefix"], output, true) == 0 and not output.is_empty():
		info.project_dir = str(output[0]).strip_edges().trim_suffix("/")
	for folder: String in [".godot_agent", "addons/godot_agent"]:
		# check-ignore sale con 0 si la ruta está ignorada, 1 si no (exista o no).
		if OS.execute("git", ["-C", project_root, "check-ignore", "-q", folder + "/"], [], true) == 0:  # con la barra: cuenta como carpeta aunque no exista
			info.ignored.append(folder)
	return info


## El texto del workflow. `render`: las regresiones corren bajo Xvfb con OpenGL por software, para
## las que necesitan dibujar (capturas, shaders); si no, headless. `project_dir`: el proyecto
## relativo a la raíz del repo ("" si es la raíz): --path y las capturas salen de ahí. `dotnet`: el
## build mono de Godot más el SDK de .NET y un `dotnet build` del proyecto antes de correr.
## `repeat`: corridas de cada regresión (m11-42); `fail_on_flaky`: una inestable también hace fallar el CI.
static func workflow_text(version: String, render: bool, project_dir: String = "", dotnet: bool = false, repeat: int = 1, fail_on_flaky: bool = false) -> String:
	var godot := "\"$RUNNER_TEMP/godot/godot\""
	var project := "\"%s\"" % project_dir if not project_dir.is_empty() else "."
	var captures := project_dir.path_join(".godot_agent/playtests") if not project_dir.is_empty() else ".godot_agent/playtests"
	var run_line := "%s --headless --path %s --script %s" % [godot, project, CLI]
	if render:
		run_line = "xvfb-run -a -s \"-screen 0 1280x720x24\" %s --display-driver x11 --rendering-driver opengl3 --audio-driver Dummy --path %s --script %s" % [godot, project, CLI]
	var cli_args := cli_options(repeat, fail_on_flaky)
	if not cli_args.is_empty():
		run_line += " -- " + " ".join(cli_args)
	var lines: PackedStringArray = [
		"# Written by Godot Agent Harness: runs the playtest regressions saved in %s/ on every push." % REGRESSIONS_DIR,
		"# Edit it freely; the harness won't overwrite it unless you ask.",
		"name: Playtest regressions",
		"",
		"on:",
		"  push:",
		"  pull_request:",
		"  workflow_dispatch:",
		"",
		"jobs:",
		"  regressions:",
		"    name: Playtest regressions (Godot %s)" % version,
		"    runs-on: ubuntu-latest",
		"    steps:",
		"      - uses: actions/checkout@v4",
		"",
		"      - name: Install Godot %s%s" % [version, " (.NET)" if dotnet else ""],
		"        run: |",
		"          curl -fsSL -o \"$RUNNER_TEMP/godot.zip\" \"%s\"" % download_url(version, dotnet),
		"          mkdir -p \"$RUNNER_TEMP/godot\"",
		"          unzip -oq \"$RUNNER_TEMP/godot.zip\" -d \"$RUNNER_TEMP/godot\"",
	]
	if dotnet:
		# El zip mono trae una carpeta con el binario y GodotSharp/: van juntos.
		lines.append_array([
			"          mv \"$RUNNER_TEMP/godot/%s\"/* \"$RUNNER_TEMP/godot/\"" % zip_name(version, true),
			"          ln -sf \"Godot_v%s_mono_linux.x86_64\" \"$RUNNER_TEMP/godot/godot\"" % version,
		])
	else:
		lines.append("          mv \"$RUNNER_TEMP/godot/%s\" \"$RUNNER_TEMP/godot/godot\"" % zip_name(version, false))
	lines.append("          %s --version" % godot)
	if dotnet:
		lines.append_array([
			"",
			"      - uses: actions/setup-dotnet@v4",
			"        with:",
			"          dotnet-version: 8.0.x",
		])
	if render:
		lines.append_array([
			"",
			"      - name: Install Xvfb",
			"        run: |",
			"          sudo apt-get update -qq",
			"          sudo apt-get install -y -qq xvfb libgl1-mesa-dri",
		])
	lines.append_array([
		"",
		"      - name: Import the project",
		"        run: |",  # el comando empieza con comillas: en una sola línea sería un escalar YAML inválido
		"          %s --headless --path %s --import" % [godot, project],
	])
	if dotnet:
		lines.append_array([
			"",
			"      - name: Build the C# project",
			"        run: dotnet build %s" % project,
		])
	lines.append_array([
		"",
		"      - name: Run the regressions",
		"        run: |",
		"          set -o pipefail",
		"          %s 2>&1 | tee %s" % [run_line, REPORT],
		"",
		"      - name: Upload the report and the captures",
		"        if: failure()",
		"        uses: actions/upload-artifact@v4",
		"        with:",
		"          name: playtest-regressions",
		"          path: |",
		"            %s" % REPORT,
		"            %s/**/*.png" % captures,
		"            %s/**/*.jpg" % captures,
		"          if-no-files-found: ignore",
		"",
	])
	return "\n".join(lines)


## Escribe el workflow en la raíz del repo git que contiene `project_root` (la carpeta del proyecto,
## absoluta); sin git, en el proyecto, con el aviso WARN_NO_GIT. Sin `overwrite` no pisa uno que
## exista. `dotnet` y `official`: null = los de este editor (los tests los fijan). Devuelve
## {ok, path, existed, error, root, project_dir, warnings}: `path` relativo a `root`.
static func write(project_root: String, render: bool, overwrite: bool, version: String = "", dotnet: Variant = null, official: Variant = null, repeat: int = 1, fail_on_flaky: bool = false) -> Dictionary:
	var use_dotnet: bool = dotnet if dotnet is bool else is_dotnet_editor()
	var is_official: bool = official if official is bool else is_official_build()
	var repo := repo_info(project_root)
	var root: String = repo.toplevel if not str(repo.toplevel).is_empty() else project_root
	var relative := PATH.trim_prefix("res://")
	var absolute := root.path_join(relative)
	var warnings: PackedStringArray = []
	if str(repo.toplevel).is_empty():
		warnings.append(WARN_NO_GIT)
	if ".godot_agent" in repo.ignored:
		warnings.append(WARN_IGNORED_REGRESSIONS)
	if "addons/godot_agent" in repo.ignored:
		warnings.append(WARN_IGNORED_ADDON)
	if not is_official:
		warnings.append(WARN_CUSTOM_BUILD)
	var result := {"ok": false, "path": relative, "existed": FileAccess.file_exists(absolute), "error": "", "root": root, "project_dir": repo.project_dir, "warnings": warnings}
	if result.existed and not overwrite:
		result.error = "%s already exists" % relative
		return result
	if DirAccess.make_dir_recursive_absolute(absolute.get_base_dir()) != OK:
		result.error = "could not create %s" % relative.get_base_dir()
		return result
	var file := FileAccess.open(absolute, FileAccess.WRITE)
	if file == null:
		result.error = "could not write %s: %s" % [relative, error_string(FileAccess.get_open_error())]
		return result
	file.store_string(workflow_text(version if not version.is_empty() else editor_version(), render, repo.project_dir, use_dotnet, repeat, fail_on_flaky))
	file.close()
	result.ok = true
	return result


## Dónde se escribiría el workflow para `project_root` (la raíz del repo, o el proyecto sin git).
static func target_path(project_root: String) -> String:
	var repo := repo_info(project_root)
	var root: String = repo.toplevel if not str(repo.toplevel).is_empty() else project_root
	return root.path_join(PATH.trim_prefix("res://"))


static func exists(project_root: String) -> bool:
	return FileAccess.file_exists(target_path(project_root))
