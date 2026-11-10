extends "test_case.gd"
## El workflow de CI de las regresiones (m16-10): versión del editor, texto del yml (headless y con
## render), escritura sin pisar uno que exista, y una comprobación estructural del YAML.

const RegressionsWorkflow := preload("res://addons/godot_agent/review/regressions_workflow.gd")
const RunTools := preload("res://addons/godot_agent/mcp/tools/run_tools.gd")


func test_editor_version_names_the_release() -> void:
	var version := RegressionsWorkflow.editor_version()
	var info: Dictionary = Engine.get_version_info()
	assert_true(version.begins_with("%d.%d" % [int(info.major), int(info.minor)]), "empieza con major.minor (%s)" % version)
	assert_true(version.ends_with("-" + str(info.status)), "termina con el status (%s)" % version)
	assert_eq(RegressionsWorkflow.download_url("4.7.2-stable"), "https://github.com/godotengine/godot/releases/download/4.7.2-stable/Godot_v4.7.2-stable_linux.x86_64.zip", "las estables salen de godotengine/godot")
	assert_eq(RegressionsWorkflow.download_url("4.8-beta2"), "https://github.com/godotengine/godot-builds/releases/download/4.8-beta2/Godot_v4.8-beta2_linux.x86_64.zip", "las betas de godot-builds")
	assert_eq(RegressionsWorkflow.download_url("4.7.2-stable", true), "https://github.com/godotengine/godot/releases/download/4.7.2-stable/Godot_v4.7.2-stable_mono_linux_x86_64.zip", "el zip mono para .NET")
	assert_eq(RegressionsWorkflow.is_dotnet_editor(), ClassDB.class_exists("CSharpScript"), "detecta el editor .NET")
	assert_eq(RegressionsWorkflow.is_official_build(), str(Engine.get_version_info().build) == "official", "detecta el build oficial")


func test_workflow_text_headless_and_render() -> void:
	var text := RegressionsWorkflow.workflow_text("4.7.2-stable", false)
	assert_true(text.contains("name: Playtest regressions"), "nombre")
	assert_true(text.contains("Install Godot 4.7.2-stable") and text.contains("Godot_v4.7.2-stable_linux.x86_64.zip"), "instala la versión del editor")
	assert_true(text.contains("--headless --path . --import"), "importa el proyecto")
	assert_true(text.contains("--headless --path . --script res://addons/godot_agent/playtest/regression_cli.gd 2>&1 | tee regressions-report.txt"), "corre el CLI headless y guarda el informe")
	assert_true(text.contains("if: failure()") and text.contains("actions/upload-artifact@v4") and text.contains(".godot_agent/playtests/**/*.png"), "sube informe y capturas al fallar")
	assert_false(text.contains("xvfb"), "sin render no hay Xvfb")
	var render := RegressionsWorkflow.workflow_text("4.8-beta2", true)
	assert_true(render.contains("Install Xvfb") and render.contains("xvfb-run -a") and render.contains("--rendering-driver opengl3"), "con render corre bajo Xvfb")
	assert_false(render.contains("--headless --path . --script"), "y no headless")
	assert_true(render.contains("godot-builds/releases/download/4.8-beta2/"), "una beta baja de godot-builds")
	_assert_yaml_shape(text, "headless")
	_assert_yaml_shape(render, "render")
	var dotnet := RegressionsWorkflow.workflow_text("4.7.2-stable", false, "", true)
	assert_true(dotnet.contains("Godot_v4.7.2-stable_mono_linux_x86_64.zip") and dotnet.contains("ln -sf \"Godot_v4.7.2-stable_mono_linux.x86_64\""), ".NET: baja el build mono y enlaza el binario")
	assert_true(dotnet.contains("actions/setup-dotnet@v4") and dotnet.contains("dotnet-version: 8.0.x"), ".NET: instala el SDK")
	assert_true(dotnet.contains("- name: Build the C# project") and dotnet.contains("run: dotnet build ."), ".NET: compila el proyecto antes de correr")
	assert_true(dotnet.find("Build the C# project") > dotnet.find("Import the project") and dotnet.find("Build the C# project") < dotnet.find("Run the regressions"), ".NET: el build va entre importar y correr")
	assert_false(text.contains("dotnet"), "sin .NET no hay dotnet")
	_assert_yaml_shape(dotnet, "dotnet")


func test_write_does_not_overwrite_without_asking() -> void:
	var root := ProjectSettings.globalize_path(temp_dir("regressions_workflow"))
	DirAccess.remove_absolute(root.path_join(RegressionsWorkflow.PATH.trim_prefix("res://")))  # temp_dir no borra subcarpetas
	assert_false(RegressionsWorkflow.exists(root), "no existe al empezar")
	var first := RegressionsWorkflow.write(root, false, false, "4.7.2-stable")
	assert_true(first.ok, "se escribe (%s)" % first.error)
	assert_eq(first.path, ".github/workflows/godot-agent-regressions.yml", "en .github/workflows")
	assert_false(first.existed, "no existía")
	assert_true(RegressionsWorkflow.exists(root), "ahora existe")
	var written := FileAccess.get_file_as_string(root.path_join(first.path))
	assert_true(written.contains("Godot 4.7.2-stable"), "con la versión pedida")
	var again := RegressionsWorkflow.write(root, true, false, "4.7.2-stable")
	assert_false(again.ok, "sin overwrite no pisa")
	assert_true(again.existed and again.error.contains("already exists"), "y dice por qué (%s)" % again.error)
	assert_eq(FileAccess.get_file_as_string(root.path_join(first.path)), written, "el archivo quedó igual")
	var replaced := RegressionsWorkflow.write(root, true, true, "4.7.2-stable")
	assert_true(replaced.ok and replaced.existed, "con overwrite lo reemplaza")
	assert_true(FileAccess.get_file_as_string(root.path_join(first.path)).contains("xvfb-run"), "con el contenido nuevo")
	var custom := RegressionsWorkflow.write(root, false, true, "4.7.2-stable", false, false)
	assert_true(custom.ok and RegressionsWorkflow.WARN_CUSTOM_BUILD in custom.warnings, "un build no oficial avisa que la URL es una suposición (%s)" % [custom.warnings])
	assert_true(RegressionsWorkflow.WARNING_TEXTS.has(RegressionsWorkflow.WARN_CUSTOM_BUILD), "con texto para el agente")
	var mono := RegressionsWorkflow.write(root, false, true, "4.7.2-stable", true, true)
	assert_true(mono.ok and not RegressionsWorkflow.WARN_CUSTOM_BUILD in mono.warnings and FileAccess.get_file_as_string(root.path_join(mono.path)).contains("setup-dotnet"), "con .NET escribe el workflow .NET")


## El juego vive en una subcarpeta del repo: el yml va a la raíz (GitHub no lee otro .github/) con
## --path y las capturas relativos a la raíz; y una carpeta ignorada se avisa.
func test_project_in_a_subfolder_of_the_repo() -> void:
	var repo := ProjectSettings.globalize_path(temp_dir("regressions_workflow_repo"))
	OS.execute("rm", ["-rf", repo.path_join(".git"), repo.path_join(".github"), repo.path_join("game")])
	OS.execute("git", ["-c", "init.defaultBranch=main", "init", "-q", repo])
	DirAccess.make_dir_recursive_absolute(repo.path_join("game/addons/godot_agent"))
	var ignore := FileAccess.open(repo.path_join(".gitignore"), FileAccess.WRITE)
	ignore.store_string(".godot_agent/\n")
	ignore.close()
	var project := repo.path_join("game")
	var info := RegressionsWorkflow.repo_info(project)
	assert_eq(info.toplevel, repo, "la raíz del repo")
	assert_eq(info.project_dir, "game", "el proyecto relativo a la raíz")
	assert_eq(info.ignored, PackedStringArray([".godot_agent"]), "la carpeta ignorada")
	var written := RegressionsWorkflow.write(project, false, false, "4.7.2-stable")
	assert_true(written.ok, "se escribe (%s)" % written.error)
	assert_eq(written.root, repo, "en la raíz del repo")
	assert_true(FileAccess.file_exists(repo.path_join(".github/workflows/godot-agent-regressions.yml")), "el yml está en <repo>/.github/workflows")
	assert_false(FileAccess.file_exists(project.path_join(".github/workflows/godot-agent-regressions.yml")), "y no en el proyecto")
	var text := FileAccess.get_file_as_string(repo.path_join(written.path))
	assert_true(text.contains("--path \"game\" --import") and text.contains("--path \"game\" --script"), "Godot corre con --path game")
	assert_true(text.contains("            game/.godot_agent/playtests/**/*.png"), "las capturas relativas a la raíz")
	assert_eq(written.warnings, PackedStringArray([RegressionsWorkflow.WARN_IGNORED_REGRESSIONS]), "avisa que .godot_agent está ignorado")
	assert_true(RegressionsWorkflow.exists(project), "exists() mira la raíz del repo")
	# En la raíz del repo: sin subcarpeta, --path . y sin avisos de carpetas.
	OS.execute("rm", ["-f", repo.path_join(".gitignore"), repo.path_join(".github/workflows/godot-agent-regressions.yml")])
	var at_root := RegressionsWorkflow.write(repo, false, false, "4.7.2-stable")
	assert_true(at_root.ok and str(at_root.project_dir).is_empty() and at_root.warnings.is_empty(), "en la raíz: sin subcarpeta ni avisos (%s)" % [at_root])
	assert_true(FileAccess.get_file_as_string(repo.path_join(at_root.path)).contains("--path . --import"), "--path .")


func test_without_git_it_warns() -> void:
	var project := ProjectSettings.globalize_path(temp_dir("regressions_workflow_nogit"))
	var info := RegressionsWorkflow.repo_info("/")  # fuera de cualquier repo
	assert_eq(info.toplevel, "", "sin repo, sin raíz")
	assert_eq(RegressionsWorkflow.WARNING_TEXTS.size(), 4, "cada aviso tiene texto para el agente")
	# El temp vive dentro de user://, que puede estar en un repo o no: solo el texto del aviso se prueba acá.
	assert_true(RegressionsWorkflow.WARNING_TEXTS[RegressionsWorkflow.WARN_NO_GIT].contains("root of the repository"), "el aviso dice dónde va")
	assert_true(DirAccess.dir_exists_absolute(project), "carpeta temporal")


func test_tool_is_registered_for_the_agent() -> void:
	var tools := RunTools.new()
	var names := tools.tools().map(func(tool: RefCounted) -> String: return tool.name)
	assert_true("write_regressions_workflow" in names, "la tool existe (%s)" % [names])
	for tool: RefCounted in tools.tools():
		if tool.name == "write_regressions_workflow":
			assert_eq(tool.group, "edit_files", "pide permiso como una edición de archivos")
			assert_true(tool.input_schema.properties.has("render") and not tool.input_schema.properties.has("overwrite"), "con render y sin overwrite: la tool nunca pisa")
			assert_true(tool.description.contains("Never replaces an existing file"), "y lo dice")


## Sin un parser YAML a mano: cada línea con contenido tiene sangría par y las claves del workflow
## están en el orden que GitHub espera.
func _assert_yaml_shape(text: String, label: String) -> void:
	var lines := text.split("\n")
	for i in lines.size():
		var line := lines[i]
		if line.strip_edges().is_empty() or line.begins_with("#"):
			continue
		var indent := line.length() - line.lstrip(" ").length()
		assert_eq(indent % 2, 0, "%s: sangría par en la línea %d «%s»" % [label, i + 1, line])
		assert_false(line.contains("\t"), "%s: sin tabs en la línea %d" % [label, i + 1])
	var order: PackedStringArray = ["name: ", "on:", "  push:", "jobs:", "  regressions:", "    runs-on: ubuntu-latest", "    steps:", "      - uses: actions/checkout@v4", "      - name: Install Godot", "      - name: Import the project", "      - name: Run the regressions", "      - name: Upload the report and the captures"]
	var last := -1
	for key: String in order:
		var at := -1
		for i in lines.size():
			if lines[i].begins_with(key):
				at = i
				break
		assert_true(at > last, "%s: «%s» está y viene después de lo anterior (%d)" % [label, key, at])
		last = at
