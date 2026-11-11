extends "test_case.gd"
## godot.project_map (m11-26): índice de solo estructura, grafo de dependencias de Godot, ranking
## hacia un foco y texto con presupuesto.

const ProjectIndex := preload("res://addons/godot_agent/completion/project_index.gd")
const ProjectMap := preload("res://addons/godot_agent/mcp/project_map.gd")
const MapTools := preload("res://addons/godot_agent/mcp/tools/map_tools.gd")
const ToolRegistry := preload("res://addons/godot_agent/mcp/tool_registry.gd")
const McpTool := preload("res://addons/godot_agent/mcp/mcp_tool.gd")
const AgentLog := preload("res://addons/godot_agent/core/agent_log.gd")
const UntrustedText := preload("res://addons/godot_agent/mcp/untrusted_text.gd")

const FIXTURE := "res://tests/map_fixture"


func _map() -> ProjectMap:
	var index: ProjectIndex = ProjectIndex.build({"root": FIXTURE, "structure_only": true})
	return ProjectMap.create(index, FIXTURE, ProjectMap.read_autoloads(FIXTURE))


func test_structure_index() -> void:
	var index: ProjectIndex = ProjectIndex.build({"root": FIXTURE, "structure_only": true})
	var player: Dictionary = index.scripts[FIXTURE + "/player.gd"]
	var decls: Array = player.decls
	var texts: Array = decls.map(func(decl: Array) -> String: return decl[1])
	assert_eq(texts, ["class_name Player", "signal died", "@export var speed := 200.0", "func hurt(amount: int) -> void"], "declaraciones públicas, sin _ready · %s" % [texts])
	assert_eq(decls[3][0], 12, "con su línea")
	assert_eq(player.refs, PackedStringArray(["bullet.tscn"]), "preload literal")
	assert_true("GameState" in player.idents and "Player" in player.idents, "identificadores con mayúscula")
	var enemy_texts: Array = (index.scripts[FIXTURE + "/enemy.gd"].decls as Array).map(func(decl: Array) -> String: return decl[1])
	assert_eq(enemy_texts, ["enum Mode", "func chase(target: Player) -> void", "static func spawn_count() -> int"], "enum y static")
	assert_eq(index.resource_deps[FIXTURE + "/stats.tres"].deps, PackedStringArray(["res://stats.gd"]), "los .tres con sus ext_resource")
	assert_true("res://player.tscn" in index.scenes[FIXTURE + "/main.tscn"].deps, "las escenas con sus ext_resource")
	var completion: ProjectIndex = ProjectIndex.build({"root": FIXTURE})
	assert_false(completion.scripts[FIXTURE + "/player.gd"].has("decls") or completion.structure_only, "el índice del completado no cambia")
	assert_true(completion.resource_deps.is_empty(), "ni lee los .tres")


func test_graph() -> void:
	var map := _map()
	assert_eq(map.autoloads, {"GameState": "res://game_state.gd"}, "autoloads de project.godot")
	assert_eq(map.class_paths.get("Player"), "res://player.gd", "class_name")
	var expect := {
		"res://main.tscn": ["res://main.gd", "res://player.tscn"],
		"res://main.gd": ["res://player.gd", "res://game_state.gd"],
		"res://player.gd": ["res://bullet.tscn", "res://game_state.gd"],
		"res://enemy.gd": ["res://player.gd"],
		"res://stats.tres": ["res://stats.gd"],
		"res://bullet.tscn": ["res://bullet.gd"],
	}
	for from: String in expect:
		for to: String in expect[from]:
			assert_true((map.edges.get(from, {}) as Dictionary).has(to), "%s → %s · %s" % [from, to, map.edges.get(from, {})])
	assert_false(map.edges.has("res://unrelated.gd"), "un script suelto no usa nada")
	assert_true((map.edges["res://enemy.gd"] as Dictionary).has("res://player.gd"), "el grupo players también lo une (o el class_name)")


func test_focus_and_rank() -> void:
	var map := _map()
	var resolved: Dictionary = map.resolve_focus(PackedStringArray(["Player", "GameState", "bullet.tscn", "nope", "res://main.tscn"]))
	assert_eq(resolved.paths, PackedStringArray(["res://player.gd", "res://game_state.gd", "res://bullet.tscn", "res://main.tscn"]), "class_name, autoload, archivo y ruta")
	assert_eq(resolved.unknown, PackedStringArray(["nope"]), "lo que no está")
	assert_eq(map.resolve_focus(PackedStringArray(["player"])).paths, PackedStringArray(["res://player.gd", "res://player.tscn"]) if map.resolve_focus(PackedStringArray(["player"])).paths[0] == "res://player.gd" else PackedStringArray(["res://player.tscn", "res://player.gd"]), "un nombre sin extensión trae los dos")
	var scores := map.rank(PackedStringArray(["res://bullet.gd"]))
	assert_true(scores["res://bullet.tscn"] > scores["res://unrelated.gd"] and scores["res://player.gd"] > scores["res://unrelated.gd"], "los vecinos del foco antes que lo suelto · %s" % scores)
	assert_true(scores["res://bullet.tscn"] > scores["res://main.tscn"], "el vecino directo antes que el de dos saltos")


func test_render_and_budget() -> void:
	var map := _map()
	var text := map.render(PackedStringArray(["res://player.gd"]), 2000, "res://player.gd")
	var lines := text.split("\n")
	assert_true(lines[0].begins_with("Project map: 7 scripts, 3 scenes, 1 resources. Ranked toward res://player.gd."), lines[0])
	assert_eq(lines[1], "Autoloads: GameState (res://game_state.gd)", "autoloads")
	assert_eq(lines[3], "res://player.gd · script · class_name Player · extends CharacterBody2D", "el foco primero")
	assert_true(text.contains("  5: signal died\n  7: @export var speed := 200.0\n  12: func hurt(amount: int) -> void\n  on: res://player.tscn (.)"), "declaraciones con línea y dónde se usa · " + text)
	assert_true(text.contains("res://main.tscn · scene · root Main: Node2D script main.gd\n  Player: CharacterBody2D instance player.tscn\n  %HUD: Control groups hud\n  signal Player.died → Main._on_player_died"), "árbol y conexiones · " + text)
	assert_false(text.contains("_ready"), "sin privadas")
	assert_false(text.contains("more files"), "entra todo")
	var small := map.render(PackedStringArray(["res://player.gd"]), 0, "x")
	assert_true(small.length() <= ProjectMap.MIN_TOKENS * ProjectMap.CHARS_PER_TOKEN + 80 and small.contains("more files. Raise max_tokens"), "el presupuesto corta y lo dice · " + small)
	var whole := map.render(PackedStringArray(), 2000, "the whole project")
	assert_true(whole.contains("Ranked toward the whole project.") and whole.contains("res://unrelated.gd"), "sin foco, todo")


func test_tool() -> void:
	var registry := ToolRegistry.new()
	registry.agent_log = AgentLog.new()
	var map_tools := MapTools.new()
	map_tools.root = FIXTURE
	map_tools.editor_focus = func() -> PackedStringArray: return PackedStringArray(["res://main.tscn"])
	registry.register_provider(map_tools)
	var listed: Dictionary = registry.list()[0]
	assert_true(str(listed.description).ends_with(UntrustedText.NOTE), "la descripción explica el sobre")
	assert_eq(listed.annotations.readOnlyHint, true, "de solo lectura")
	var result: Dictionary = await registry.call_tool("project_map", {"focus": ["Player", "ghost"], "max_tokens": 600})
	var text: String = result.content[0].text
	assert_false(result.isError, text)
	assert_true(text.begins_with("<untrusted nonce=\"") and text.contains("Not found in the project: ghost.\nProject map:") and text.contains("Ranked toward res://player.gd."), "en un sobre, con lo que no encontró · " + text.left(300))
	var opened: String = (await registry.call_tool("project_map", {})).content[0].text
	assert_true(opened.contains("Ranked toward what is open in the editor: res://main.tscn."), "sin focus, lo abierto · " + opened.left(300))
	assert_true(map_tools._index != null and map_tools._index.structure_only, "guarda el índice para la próxima")


# --- fix-a (revisión de sm/next2) --------------------------------------------------------------

const PLUGINS := "res://tests/map_fixture_plugins"


func _plugins_map() -> ProjectMap:
	var index: ProjectIndex = ProjectIndex.build({"root": PLUGINS, "structure_only": true})
	return ProjectMap.create(index, PLUGINS, ProjectMap.read_autoloads(PLUGINS))


## #7: el índice del mapa no arma líneas ni tokens (lo caro), pero sí los grupos.
func test_structure_only_skips_lines_and_tokens() -> void:
	var index: ProjectIndex = ProjectIndex.build({"root": FIXTURE, "structure_only": true})
	var enemy: Dictionary = index.scripts[FIXTURE + "/enemy.gd"]
	assert_true((enemy.lines as Dictionary).is_empty() and (enemy.tokens as PackedStringArray).is_empty(), "sin líneas ni tokens")
	assert_eq(enemy.groups, PackedStringArray(["players"]), "con sus grupos")
	var completion: ProjectIndex = ProjectIndex.build({"root": FIXTURE})
	assert_false((completion.scripts[FIXTURE + "/enemy.gd"].tokens as PackedStringArray).is_empty(), "el completado sí")


## #6 y #24: autoloads guardados como uid:// (script por su .uid, escena por su encabezado) y uno en
## minúscula usado como `tracker.count`.
func test_uid_and_lowercase_autoloads() -> void:
	var map := _plugins_map()
	assert_eq(map.autoloads, {"State": "res://state.gd", "tracker": "res://tracker.gd", "Menu": "res://menu.tscn"}, "uid:// resuelto")
	var hero: Dictionary = map.edges.get("res://hero.gd", {})
	assert_true(hero.has("res://state.gd") and hero.has("res://tracker.gd"), "aristas a los dos autoloads · %s" % hero)
	assert_eq(map.resolve_focus(PackedStringArray(["State"])).paths, PackedStringArray(["res://state.gd"]), "foco por nombre de un autoload uid://")


## #5: los plugins de res://addons/ quedan afuera (y el encabezado lo dice) salvo con foco ahí.
func test_addons_left_out() -> void:
	var map := _plugins_map()
	var whole := map.render(PackedStringArray(), 2000, "the whole project")
	assert_true(whole.begins_with("Project map: 3 scripts, 1 scenes, 0 resources.") and whole.contains("2 files in res://addons/ (plugins) are left out"), "cuenta solo el juego · " + whole.left(300))
	assert_false(whole.contains("fancy_button.gd") or whole.contains("plugin.gd"), "sin archivos de plugins · " + whole)
	var job := {"root": PLUGINS, "previous": null, "focus": PackedStringArray(["FancyButton"]), "from_editor": false, "cancel": [false], "autoloads": ProjectMap.read_autoloads(PLUGINS), "max_tokens": 2000, "result": {}}
	MapTools._work(job)
	var focused: String = job.result.text
	assert_true(focused.contains("Project map: 5 scripts") and focused.contains("res://addons/fancy/fancy_button.gd · script · class_name FancyButton") and not focused.contains("left out"), "con foco en un plugin, entran · " + focused.left(400))


## #24: max_tokens acota también el encabezado y los autoloads; un foco sin relaciones se dice.
func test_header_within_budget() -> void:
	var map := _map()
	for i in 60:
		map.autoloads["SomeManagerNumber%d" % i] = "res://autoload/some_manager_number_%d.gd" % i
	var text := map.render(PackedStringArray(["res://player.gd"]), 0, "res://player.gd")
	var budget := ProjectMap.MIN_TOKENS * ProjectMap.CHARS_PER_TOKEN
	assert_true(text.length() <= budget + 80, "dentro del presupuesto: %d de %d" % [text.length(), budget])
	assert_true(text.contains(" more") and text.contains("res://player.gd · script"), "los autoloads se cortan y queda lugar para archivos · " + text)
	var loose := _map().render(PackedStringArray(["res://icon.png"]), 2000, "res://icon.png")
	assert_true(loose.contains("Ranked toward the whole project (res://icon.png is not linked to the files in the map)."), "foco fuera del grafo · " + loose.left(200))


## #24: una llamada que llega durante un build arma la suya sobre ese índice (sin releer).
func test_concurrent_calls_reuse_the_build() -> void:
	var map_tools := MapTools.new()
	map_tools.root = FIXTURE
	var first: Array = []
	var run_first := func() -> void:
		await map_tools._project_map({})
		first.append(map_tools._index)
	run_first.call()
	var second: Dictionary = await map_tools._project_map({"focus": ["Player"]})
	assert_false(second.get("isError", false), str(second))
	assert_eq(first.size(), 1, "la primera terminó antes")
	var path := FIXTURE + "/player.gd"
	assert_true(is_same(map_tools._index.scripts[path], first[0].scripts[path]), "la segunda reusó lo que leyó la primera")


## #1: wait() corta el build en curso y lo espera; la llamada contesta que se interrumpió y no arma más.
func test_wait_cancels_the_worker() -> void:
	var map_tools := MapTools.new()
	map_tools.root = FIXTURE
	var answers: Array = []
	var call_map := func() -> void: answers.append(await map_tools._project_map({}))
	call_map.call()
	map_tools.wait()
	assert_eq(map_tools._task, -1, "esperó la tarea")
	await (Engine.get_main_loop() as SceneTree).process_frame
	await (Engine.get_main_loop() as SceneTree).process_frame
	assert_eq(answers.size(), 1, "la llamada volvió")
	assert_true(answers[0].get("isError", false) and McpTool.error(MapTools.CANCELLED).content[0].text == answers[0].content[0].text, "interrumpida · %s" % [answers[0]])
	var later: Dictionary = await map_tools._project_map({})
	assert_true(later.get("isError", false), "después de wait() no arma más")
	var cut: ProjectIndex = ProjectIndex.build({"root": FIXTURE, "structure_only": true, "cancel": [true]})
	assert_true(cut.scripts.is_empty(), "el build cortado no lee archivos")
	var plugin := FileAccess.get_file_as_string("res://addons/godot_agent/agent_plugin.gd")
	var exit_tree := plugin.substr(plugin.find("func _exit_tree"), 6000)
	assert_true(exit_tree.contains("_map_tools.wait()"), "el plugin lo espera al deshabilitarse")


## Revisión de next2 #24: el foco del editor con un script integrado es su escena, no
## «res://x.tscn::GDScript_ab» (que no es un archivo y no rankeaba nada).
func test_builtin_script_focus_is_its_scene() -> void:
	assert_eq(MapTools.focus_of_script("res://levels/x.tscn::GDScript_ab12"), "res://levels/x.tscn", "integrado → su escena")
	assert_eq(MapTools.focus_of_script("res://player.gd"), "res://player.gd", "un archivo queda igual")
	assert_eq(MapTools.focus_of_script(""), "", "sin ruta, sin foco")
	assert_eq(MapTools.focus_of_script("/tmp/outside.gd"), "", "afuera de res:// no")
