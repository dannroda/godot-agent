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


func test_tool_is_registered_for_the_agent() -> void:
	var tools := RunTools.new()
	var names := tools.tools().map(func(tool: RefCounted) -> String: return tool.name)
	assert_true("write_regressions_workflow" in names, "la tool existe (%s)" % [names])
	for tool: RefCounted in tools.tools():
		if tool.name == "write_regressions_workflow":
			assert_eq(tool.group, "edit_files", "pide permiso como una edición de archivos")
			assert_true(tool.input_schema.properties.has("overwrite") and tool.input_schema.properties.has("render"), "con overwrite y render")


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
