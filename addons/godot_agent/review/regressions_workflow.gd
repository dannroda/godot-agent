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


## La versión del editor como la nombran los releases de Godot: «4.7.2-stable», «4.8-beta2».
static func editor_version() -> String:
	var info: Dictionary = Engine.get_version_info()
	var patch := ".%d" % int(info.patch) if int(info.patch) > 0 else ""
	return "%d.%d%s-%s" % [int(info.major), int(info.minor), patch, str(info.status)]


## Las estables salen de godotengine/godot; betas, rc y dev de godotengine/godot-builds.
static func download_url(version: String) -> String:
	var repo := "godotengine/godot" if version.ends_with("-stable") else "godotengine/godot-builds"
	return "https://github.com/%s/releases/download/%s/Godot_v%s_linux.x86_64.zip" % [repo, version, version]


## El texto del workflow. `render`: las regresiones corren bajo Xvfb con OpenGL por software, para
## las que necesitan dibujar (capturas, shaders); si no, headless.
static func workflow_text(version: String, render: bool) -> String:
	var godot := "\"$RUNNER_TEMP/godot/godot\""
	var run_line := "%s --headless --path . --script %s" % [godot, CLI]
	if render:
		run_line = "xvfb-run -a -s \"-screen 0 1280x720x24\" %s --display-driver x11 --rendering-driver opengl3 --audio-driver Dummy --path . --script %s" % [godot, CLI]
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
		"      - name: Install Godot %s" % version,
		"        run: |",
		"          curl -fsSL -o \"$RUNNER_TEMP/godot.zip\" \"%s\"" % download_url(version),
		"          mkdir -p \"$RUNNER_TEMP/godot\"",
		"          unzip -oq \"$RUNNER_TEMP/godot.zip\" -d \"$RUNNER_TEMP/godot\"",
		"          mv \"$RUNNER_TEMP/godot/Godot_v%s_linux.x86_64\" \"$RUNNER_TEMP/godot/godot\"" % version,
		"          %s --version" % godot,
	]
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
		"          %s --headless --path . --import" % godot,
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
		"            .godot_agent/playtests/**/*.png",
		"            .godot_agent/playtests/**/*.jpg",
		"          if-no-files-found: ignore",
		"",
	])
	return "\n".join(lines)


## Escribe el workflow en `project_root` (la carpeta del proyecto, absoluta). Sin `overwrite` no pisa
## uno que exista. Devuelve {ok, path, existed, error}: `path` relativo al proyecto.
static func write(project_root: String, render: bool, overwrite: bool, version: String = "") -> Dictionary:
	var relative := PATH.trim_prefix("res://")
	var absolute := project_root.path_join(relative)
	var result := {"ok": false, "path": relative, "existed": FileAccess.file_exists(absolute), "error": ""}
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
	file.store_string(workflow_text(version if not version.is_empty() else editor_version(), render))
	file.close()
	result.ok = true
	return result


static func exists(project_root: String) -> bool:
	return FileAccess.file_exists(project_root.path_join(PATH.trim_prefix("res://")))
