extends "test_case.gd"
## Recetas (m11-30): la carpeta, la lectura y validación, la expansión del prompt, el formulario y la
## corrida en el controller (checks de la receta, reintentos, aprobación por máquina, aviso final).

const ProjectDirs := preload("res://addons/godot_agent/core/project_dirs.gd")
const Recipes := preload("res://addons/godot_agent/core/recipes.gd")
const TurnChecks := preload("res://addons/godot_agent/core/turn_checks.gd")
const HarnessSettings := preload("res://addons/godot_agent/core/harness_settings.gd")
const AgentLog := preload("res://addons/godot_agent/core/agent_log.gd")
const SessionController := preload("res://addons/godot_agent/session/session_controller.gd")
const SessionModel := preload("res://addons/godot_agent/session/session_model.gd")
const ChatEntry := preload("res://addons/godot_agent/session/chat_entry.gd")
const HarnessPrompts := preload("res://addons/godot_agent/session/harness_prompts.gd")
const RecipeForm := preload("res://addons/godot_agent/ui/dock/recipe_form.gd")
const AgentDock := preload("res://addons/godot_agent/ui/dock/agent_dock.gd")
const RecipeTemplates := preload("res://addons/godot_agent/core/recipe_templates.gd")
const RecipesTab := preload("res://addons/godot_agent/ui/extensions/recipes_tab.gd")
const PlanApproval := preload("res://addons/godot_agent/session/plan_approval.gd")

const ENEMY := {
	"version": 1, "title": "Add enemy", "description": "An enemy from a base scene", "mode": "build",
	"prompt": "Add an enemy based on {{base}} that {{ behavior }}. Speed {{speed}}, flying: {{flying}}, attached to {{node}}.",
	"parameters": [
		{"key": "base", "type": "scene", "label": "Base scene"},
		{"key": "behavior", "type": "multiline"},
		{"key": "speed", "type": "number", "default": 120},
		{"key": "flying", "type": "bool", "required": false},
		{"key": "node", "type": "node", "required": false},
	],
	"checks": [{"kind": "command", "name": "Lint", "command": "{godot} --headless --script res://lint.gd"}],
	"max_retries": 3,
}


func _dir(name: String) -> String:
	var dir := ProjectSettings.globalize_path("user://").path_join("recipes_%s_%d" % [name, Time.get_ticks_usec()])
	DirAccess.make_dir_recursive_absolute(dir)
	return dir


func _write(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()


func _exit_script(dir: String, code: int) -> String:
	var path := dir.path_join("exit_%d.gd" % code)
	_write(path, "extends SceneTree\n\nfunc _init() -> void:\n\tprint(\"check says %d\")\n\tquit(%d)\n" % [code, code])
	return path


func test_project_dirs() -> void:
	assert_eq(ProjectDirs.normalize("agent_recipes"), "res://agent_recipes")
	assert_eq(ProjectDirs.normalize("  res://game/recipes/ "), "res://game/recipes", "sin / final ni espacios")
	assert_eq(ProjectDirs.normalize("/recipes"), "res://recipes", "sin / adelante")
	assert_eq(ProjectDirs.normalize("a/./b"), "res://a/b", "simplificada")
	for bad: String in ["", "res://", "/", ".godot_agent/recipes", "../outside", "a/../../b", "addons/godot_agent/recipes"]:
		assert_eq(ProjectDirs.normalize(bad), "", "no sirve: «%s»" % bad)
	assert_eq(ProjectDirs.resolve(".hidden", Recipes.DEFAULT_DIR), Recipes.DEFAULT_DIR, "si no sirve, la de siempre")
	assert_eq(Recipes.resolve_dir("my_recipes"), "res://my_recipes")


func test_parse_valid() -> void:
	var parsed := Recipes.parse(JSON.stringify(ENEMY), "res://agent_recipes/add_enemy.json")
	assert_eq(parsed.errors, PackedStringArray(), "sin errores")
	var recipe: Dictionary = parsed.recipe
	assert_eq([recipe.slug, recipe.title, recipe.mode, recipe.max_retries], ["add_enemy", "Add enemy", "build", 3])
	assert_eq(recipe.parameters.size(), 5)
	assert_eq(recipe.parameters[1].label, "Behavior", "sin label, la clave")
	assert_true(recipe.parameters[0].required, "obligatorio por defecto")
	assert_eq(recipe.checks[0].name, "Lint")
	assert_eq(Recipes.placeholders(recipe.prompt), PackedStringArray(["base", "behavior", "speed", "flying", "node"]))
	var spec := Recipes.run_spec(recipe)
	assert_eq([spec.title, spec.max_retries, spec.checks.size()], ["Add enemy", 3, 1], "lo que lleva la corrida")


func test_parse_errors() -> void:
	assert_true(Recipes.parse("{", "x.json").errors[0].begins_with("Not valid JSON"), "JSON roto")
	assert_eq(Recipes.parse("[]").errors, PackedStringArray(["The recipe must be a JSON object."]))
	var broken := {
		"version": 1, "title": "", "prompt": "Use {{missing}} and {{a}}", "mode": "fly", "max_retries": 9, "extra": true,
		"parameters": [{"key": "a", "type": "choice"}, {"key": "a"}, {"key": "bad key"}, {"key": "b", "type": "color"}, {"key": "c", "type": "scene", "default": "res://x.gd"}],
		"checks": [{"kind": "command", "command": "make && run"}, {"kind": "playtest"}, {"kind": "lint"}, {"kind": "playtest", "goal": "win", "minutes": 99}],
	}
	var errors := "\n".join(Recipes.from_data(broken).errors)
	for expected: String in ["Unknown field «extra»", "«title» is missing", "«mode» must be one of", "«max_retries» must be between 0 and 5",
			"{{missing}}, which isn't a parameter", "a choice needs «options»", "«a» appears twice", "«key» must be a name",
			"unknown type «color»", "the default must be a tscn, scn file", "runs without a shell", "a playtest needs a «goal»", "unknown kind «lint»", "«minutes» must be between 0 and 30"]:
		assert_true(errors.contains(expected), "dice «%s»: %s" % [expected, errors])
	assert_true(Recipes.from_data({"version": 2, "title": "t", "prompt": "p"}).errors[0].contains("newer version"), "una versión más nueva")


func test_values_and_expand() -> void:
	var recipe: Dictionary = Recipes.from_data(ENEMY).recipe
	var missing := Recipes.values_errors(recipe, {"behavior": ""})
	assert_eq(missing.size(), 2, "faltan la escena y el comportamiento: %s" % [missing])
	assert_true(Recipes.values_errors(recipe, {"base": "res://enemy.gd", "behavior": "x"})[0].contains("tscn"), "la extensión del tipo")
	assert_true(Recipes.values_errors(recipe, {"base": "res://../x.tscn", "behavior": "x"})[0].contains("res:// path"), "nada fuera del proyecto")
	assert_true(Recipes.values_errors(recipe, {"base": "res://e.tscn", "behavior": "x", "speed": "fast"})[0].contains("number"), "un número")
	var values := {"base": "res://enemies/base.tscn", "behavior": "patrols and jumps", "speed": 150.0, "flying": true, "node": "Level/Enemies"}
	assert_eq(Recipes.values_errors(recipe, values), PackedStringArray())
	assert_eq(Recipes.expand(recipe, values), "Add an enemy based on @res://enemies/base.tscn that patrols and jumps. Speed 150, flying: yes, attached to @Level/Enemies.",
		"rutas y nodos como menciones, sí/no, números sin .0")
	assert_eq(Recipes.expand(recipe, {"base": "res://b.tscn", "behavior": "b"}), "Add an enemy based on @res://b.tscn that b. Speed 120, flying: no, attached to .",
		"sin valor, el default; un opcional vacío queda vacío")


func test_load_dir_and_find() -> void:
	var dir := _dir("load")
	_write(dir.path_join("zeta.json"), JSON.stringify({"title": "Another", "prompt": "p"}))
	_write(dir.path_join("add_enemy.json"), JSON.stringify(ENEMY))
	_write(dir.path_join("broken.json"), "{ nope")
	_write(dir.path_join("notes.txt"), "not a recipe")
	var loaded := Recipes.load_dir(dir)
	assert_eq(loaded.map(func(item: Dictionary) -> String: return str(item.recipe.slug)), ["add_enemy", "zeta", "broken"], "por título; la rota (sin título) por nombre")
	assert_false((loaded[2].errors as PackedStringArray).is_empty(), "la rota con su error")
	assert_eq(Recipes.find(loaded, "ADD_ENEMY").recipe.title, "Add enemy", "por archivo")
	assert_eq(Recipes.find(loaded, "another").recipe.slug, "zeta", "o por título")
	assert_true(Recipes.find(loaded, "nope").is_empty())
	assert_eq(Recipes.load_dir(dir.path_join("missing")).size(), 0, "sin carpeta, sin recetas")
	assert_true(AgentDock.is_recipe_command("/recipe add_enemy") and AgentDock.is_recipe_command(" /recipe "), "/recipe")
	assert_false(AgentDock.is_recipe_command("/recipes"), "otro comando no")


func test_form() -> void:
	var recipe: Dictionary = Recipes.from_data(ENEMY).recipe
	var form := RecipeForm.new()
	form.node_options = func() -> PackedStringArray: return PackedStringArray(["Level", "Level/Enemies"])
	form.open_recipe(recipe)
	var used: Array = []
	form.used.connect(func(r: Dictionary, values: Dictionary) -> void: used.append(values))
	assert_eq(form.values().speed, 120.0, "el default")
	form.call(&"_on_confirmed")
	assert_true(used.is_empty(), "sin lo obligatorio no sale")
	form.set_value("base", "res://enemies/base.tscn")
	form.set_value("behavior", "patrols")
	form.set_value("flying", true)
	form.set_value("node", "Level/Enemies")
	form.call(&"_on_confirmed")
	assert_eq(used.size(), 1, "con todo, «Usar»")
	assert_eq(used[0], {"base": "res://enemies/base.tscn", "behavior": "patrols", "speed": 120.0, "flying": true, "node": "Level/Enemies"})
	form.free()
	assert_true(RecipeForm.project_input_actions().has("ui_accept"), "las acciones del Input Map")


func _controller(dir: String, sent: Array, settings: HarnessSettings) -> SessionController:
	var controller := SessionController.new()
	controller.setup(SessionModel.new(), AgentLog.new(), dir)
	controller.model.session_id = "s"
	controller.model.set_state(SessionModel.SessionState.READY)
	controller.model.set_harness_mode(SessionModel.HarnessMode.BUILD)
	controller.client.setup(func(line: String) -> bool:
		sent.append(JSON.parse_string(line))
		return true, controller.agent_log)
	controller.turn_checks_provider = func() -> Dictionary: return {"checks": [], "godot": OS.get_executable_path(), "project": dir}
	controller.is_command_approved = settings.is_command_approved
	controller.approve_command = settings.approve_command
	return controller


func _prompts(sent: Array) -> Array:
	return sent.filter(func(message: Variant) -> bool: return message is Dictionary and message.get("method") == "session/prompt")


func _notices(controller: SessionController) -> Array:
	return controller.model.entries().filter(func(entry: ChatEntry) -> bool: return entry.kind == ChatEntry.EntryKind.NOTICE).map(func(entry: ChatEntry) -> String: return entry.text)


## Termina el session/prompt en vuelo como si el agente hubiera cerrado el turno.
func _end_turn(controller: SessionController) -> void:
	controller.client.fail_all_pending("end of turn")
	await _frames()
	controller.model.set_state(SessionModel.SessionState.READY)


func test_controller_run() -> void:
	var dir := _dir("run")
	var settings := HarnessSettings.new()
	var failing := "{godot} --headless --script \"%s\"" % _exit_script(dir, 1)
	var passing := "{godot} --headless --script \"%s\"" % _exit_script(dir, 0)
	settings.approve_command(TurnChecks.approval_key(dir, failing))
	settings.approve_command(TurnChecks.approval_key(dir, passing))
	var sent: Array = []
	var controller := _controller(dir, sent, settings)
	var spec := {"title": "Add enemy", "slug": "add_enemy", "max_retries": 2, "checks": [TurnChecks.make(TurnChecks.KIND_COMMAND, "Lint", failing)]}
	controller.arm_recipe_run("Add an enemy", spec)
	controller.send_prompt("Add an enemy")
	await _frames()
	assert_eq(controller.recipe_run().get("title"), "Add enemy", "el texto armado arranca la corrida")
	await _end_turn(controller)
	var started := int(Time.get_unix_time_from_system()) - 5
	# El turno no cambió archivos: los checks de la receta corren igual.
	await controller.call(&"_run_turn_checks", started)
	var notices := _notices(controller)
	assert_true(notices.any(func(text: String) -> bool: return text.contains("recipe «Add enemy»") and text.contains("✗ Lint")), "el aviso: %s" % [notices])
	var prompts := _prompts(sent)
	assert_eq(prompts.size(), 2, "la falla vuelve al agente")
	assert_eq(controller.prompt_label(str(prompts[-1].params.prompt[-1].text)), "", "ya salió")
	assert_true(controller.model.entries().any(func(entry: ChatEntry) -> bool: return entry.kind == ChatEntry.EntryKind.USER and entry.harness_label == HarnessPrompts.RECIPE_CHECK), "con la etiqueta de la receta")
	await _end_turn(controller)
	await controller.call(&"_run_turn_checks", started)
	assert_eq(_prompts(sent).size(), 3, "segundo reintento")
	await _end_turn(controller)
	await controller.call(&"_run_turn_checks", started)
	assert_eq(_prompts(sent).size(), 3, "con el tope de la receta, no manda más")
	assert_true(_notices(controller)[-1].contains("still fail after 3 attempts"), _notices(controller)[-1])
	assert_true(controller.recipe_run().is_empty(), "la corrida terminó")

	# Pasa al segundo intento.
	spec.checks = [TurnChecks.make(TurnChecks.KIND_COMMAND, "Lint", failing)]
	controller.arm_recipe_run("Again", spec)
	controller.send_prompt("Again")
	await _end_turn(controller)
	await controller.call(&"_run_turn_checks", started)
	controller.get(&"_recipe_run").checks = [TurnChecks.make(TurnChecks.KIND_COMMAND, "Lint", passing)]
	await _end_turn(controller)
	await controller.call(&"_run_turn_checks", started)
	assert_true(_notices(controller)[-1].contains("checks passed (attempt 2)"), _notices(controller)[-1])
	assert_true(controller.recipe_run().is_empty())

	# Otro mensaje del usuario termina la corrida; un comando sin aprobar no corre.
	var clone := "{godot} --headless --script \"%s\" --cloned" % _exit_script(dir, 0)
	controller.arm_recipe_run("Third", {"title": "Cloned", "slug": "c", "max_retries": 2, "checks": [TurnChecks.make(TurnChecks.KIND_COMMAND, "Unknown", clone)]})
	controller.send_prompt("Third")
	await _end_turn(controller)
	var before := _prompts(sent).size()
	await controller.call(&"_run_turn_checks", started)
	notices = _notices(controller)
	assert_true(notices[-2].contains("⊘ Unknown"), "sin aprobar no corre: %s" % [notices])
	assert_true(notices[-1].contains("aren't approved on this machine"), notices[-1])
	assert_eq(_prompts(sent).size(), before, "y no manda nada")
	controller.arm_recipe_run("Fourth", spec)
	controller.send_prompt("Fourth")
	await _end_turn(controller)
	controller.send_prompt("Something else")
	await _frames()
	assert_true(controller.recipe_run().is_empty(), "otro mensaje del usuario la termina")
	controller.client.fail_all_pending("end of test")
	await _frames()


func test_controller_playtest() -> void:
	var dir := _dir("playtest")
	var settings := HarnessSettings.new()
	var passing := "{godot} --headless --script \"%s\"" % _exit_script(dir, 0)
	settings.approve_command(TurnChecks.approval_key(dir, passing))
	var sent: Array = []
	var controller := _controller(dir, sent, settings)
	var recipe: Dictionary = Recipes.from_data({"version": 1, "title": "Options", "prompt": "Add options", "max_retries": 2, "checks": [
		{"kind": "command", "name": "Lint", "command": passing}, {"kind": "playtest", "goal": "change the volume", "minutes": 3}]}).recipe
	var spec := Recipes.run_spec(recipe)
	assert_eq((spec.checks as Array).size(), 1, "el playtest no va con los checks")
	assert_eq(spec.playtests, [{"name": "Playtest", "goal": "change the volume", "minutes": 3}])
	controller.arm_recipe_run("Add options", spec)
	controller.send_prompt("Add options")
	await _end_turn(controller)
	var started := int(Time.get_unix_time_from_system()) - 5
	await controller.call(&"_run_turn_checks", started)
	await _frames()
	var prompt := str(_prompts(sent)[-1].params.prompt[-1].text)
	assert_true(prompt.begins_with("Playtest: change the volume") and prompt.contains("Time limit: 3 minutes"), "con los checks en verde, juega: %s" % prompt.left(80))
	assert_eq(controller.model.harness_mode, SessionModel.HarnessMode.REVIEW, "en Revisar")
	assert_true(controller.model.entries().any(func(e: ChatEntry) -> bool: return e.harness_label == HarnessPrompts.RECIPE_PLAYTEST), "como prompt del harness")
	assert_false(controller.recipe_run().is_empty(), "el prompt del playtest no corta la corrida")
	# Falla: lo que vio vuelve como corrección, en el modo de la receta.
	await _end_turn(controller)
	controller.get(&"_recipe_run").playtest_verdict = {"verdict": "fail", "summary": "The volume slider does nothing", "repro": ["open options", "drag the slider"]}
	controller.call(&"_after_recipe_playtest")
	await _frames()
	assert_eq(controller.model.harness_mode, SessionModel.HarnessMode.BUILD, "vuelve a Construir")
	prompt = str(_prompts(sent)[-1].params.prompt[-1].text)
	assert_true(prompt.contains("A playtest of what you built failed") and prompt.contains("The volume slider does nothing") and prompt.contains("- drag the slider"), prompt)
	assert_true(_notices(controller)[-1].contains("the playtest failed"), _notices(controller)[-1])
	# El arreglo: los checks pasan, juega de nuevo y pasa.
	await _end_turn(controller)
	await controller.call(&"_run_turn_checks", started)
	await _end_turn(controller)
	controller.get(&"_recipe_run").playtest_verdict = {"verdict": "pass"}
	controller.call(&"_after_recipe_playtest")
	assert_true(_notices(controller)[-1].contains("checks passed (attempt 2)"), _notices(controller)[-1])
	assert_true(controller.recipe_run().is_empty())
	assert_eq(controller.model.harness_mode, SessionModel.HarnessMode.BUILD)
	# Sin poder probar, termina con un aviso.
	controller.arm_recipe_run("Again", spec)
	controller.send_prompt("Again")
	await _end_turn(controller)
	await controller.call(&"_run_turn_checks", started)
	await _end_turn(controller)
	controller.get(&"_recipe_run").playtest_verdict = {"verdict": "blocked"}
	var before := _prompts(sent).size()
	controller.call(&"_after_recipe_playtest")
	assert_true(_notices(controller)[-1].contains("couldn't check the result"), _notices(controller)[-1])
	assert_eq(_prompts(sent).size(), before, "no manda nada")
	assert_true(controller.recipe_run().is_empty())
	controller.client.fail_all_pending("end of test")
	await _frames()


func test_controller_plan_first() -> void:
	var dir := _dir("plan")
	var sent: Array = []
	var controller := _controller(dir, sent, HarnessSettings.new())
	var spec := {"title": "Options", "slug": "options", "max_retries": 2, "checks": [TurnChecks.make(TurnChecks.KIND_REGRESSIONS, "Regressions", "")], "playtests": [], "plan": true}
	controller.arm_recipe_after_plan(spec)
	controller.request_plan("Add options")
	await _frames()
	assert_eq(controller.model.harness_mode, SessionModel.HarnessMode.ASK, "planifica en Preguntar")
	assert_true(controller.recipe_run().is_empty(), "la corrida no arranca con el plan")
	await _end_turn(controller)
	var request := PlanApproval.block_request("1. Add the screen")
	controller.model.add_permission(request)
	controller.approve_plan(request)
	await _frames()
	assert_eq(controller.recipe_run().get("title"), "Options", "arranca con «Aprobar y construir»")
	assert_eq(controller.model.harness_mode, SessionModel.HarnessMode.BUILD)
	assert_eq(int(controller.recipe_run().attempts), 0)
	await _end_turn(controller)
	# Otro mensaje antes de aprobar el plan la descarta.
	controller.arm_recipe_after_plan(spec)
	controller.send_prompt("Never mind")
	await _frames()
	assert_true((controller.get(&"_recipe_after_plan") as Dictionary).is_empty(), "otro mensaje del usuario la descarta")
	controller.client.fail_all_pending("end of test")
	await _frames()
	DirAccess.remove_absolute(dir.path_join(".godot_agent"))


func test_templates_and_tab() -> void:
	for template: Dictionary in RecipeTemplates.all():
		var parsed := Recipes.parse(RecipeTemplates.text(template.id), "x.json")
		assert_eq(parsed.errors, PackedStringArray(), "la plantilla «%s» sirve" % template.id)
	assert_true(Recipes.run_spec(Recipes.parse(RecipeTemplates.text("options")).recipe).plan, "la pantalla de opciones planifica primero")
	var dir := _dir("tab")
	var tab := RecipesTab.new()
	tab.dir_provider = func() -> String: return dir.path_join("recipes")
	var uses: Array = []
	tab.use_requested.connect(func(slug: String) -> void: uses.append(slug))
	(Engine.get_main_loop() as SceneTree).root.add_child(tab)
	tab.refresh()
	assert_eq(tab.recipe_count(), 0, "carpeta vacía (todavía no existe)")
	var path := tab.create_from_template("enemy")
	assert_eq(path.get_file(), "new_enemy.json", "la plantilla se guarda con su título")
	assert_eq(tab.recipe_count(), 1)
	assert_eq(tab.create_from_template("enemy").get_file(), "new_enemy_2.json", "sin pisar la otra")
	assert_true(tab.problems_text().contains("valid"), tab.problems_text())
	# Valida mientras se escribe; con cambios, «Use» espera.
	tab.editor().text = tab.editor().text.replace("\"title\": \"New enemy\"", "\"title\": \"\"")
	assert_true(tab.is_dirty())
	tab.validate()
	assert_true(tab.problems_text().contains("«title» is missing"), tab.problems_text())
	assert_eq(tab.save(), OK)
	assert_false(tab.is_dirty())
	assert_true(Recipes.load_file(path.get_base_dir().path_join("new_enemy_2.json")).errors.size() > 0, "se guarda aunque tenga errores")
	tab.editor().text = RecipeTemplates.text("csharp")
	tab.save()
	for button: Button in tab.find_children("*", "Button", true, false):
		if button.text == "Use in the dock":
			assert_false(button.disabled, "válida y guardada: «Use» anda")
			button.pressed.emit()
	assert_eq(uses, ["new_enemy_2"], "«Use» pide abrirla en el dock")
	tab.queue_free()
	for file: String in DirAccess.get_files_at(dir.path_join("recipes")):
		DirAccess.remove_absolute(dir.path_join("recipes").path_join(file))
	DirAccess.remove_absolute(dir.path_join("recipes"))


func _frames(n: int = 2) -> void:
	for i: int in n:
		await Engine.get_main_loop().process_frame
