extends "test_case.gd"
## Sabotajes de escena para la medición de mutación (m11-62).

const SceneSabotage := preload("res://addons/godot_agent/playtest/mutation/scene_sabotage.gd")
const MutationTesting := preload("res://addons/godot_agent/playtest/mutation/mutation_testing.gd")

const SCENE := "res://tests/fixtures/sabotage/door.tscn"
const REGRESSION := "res://tests/fixtures/regressions/sabotage/door.json"


func _changes(list: Array[Dictionary]) -> PackedStringArray:
	var changes: PackedStringArray = []
	for sabotage: Dictionary in list:
		changes.append(sabotage.change)
	changes.sort()
	return changes


func test_sabotages_of_a_scene() -> void:
	var all := SceneSabotage.sabotages(SCENE)
	assert_eq(_changes(all), PackedStringArray([
		"Panel hidden", "Timer.timeout → root._on_timer_timeout disconnected", "Zone hidden", "Zone/Shape disabled",
		"root hidden", "root.speed = 0.0"]), "todas, leídas del .tscn sin instanciar")
	for sabotage: Dictionary in all:
		assert_eq(sabotage.kind, SceneSabotage.KIND, "tipo")
		assert_eq(sabotage.path, SCENE, "la escena es el «archivo» del mutante")
		assert_true(JSON.parse_string(JSON.stringify(sabotage)) is Dictionary, "se manda como JSON al proceso")
	var code: String = JSON.parse_string(FileAccess.get_file_as_string(REGRESSION)).code
	assert_eq(_changes(SceneSabotage.sabotages(SCENE, code)), PackedStringArray([
		"Panel hidden", "Timer.timeout → root._on_timer_timeout disconnected", "root hidden", "root.speed = 0.0"]),
		"con el código de la regresión: los nodos que nombra, la raíz y lo que llega a la raíz")


func test_apply_in_memory() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var by_change := {}
	for sabotage: Dictionary in SceneSabotage.sabotages(SCENE):
		by_change[sabotage.change] = sabotage
	var door: Node2D = (load(SCENE) as PackedScene).instantiate()
	tree.root.add_child(door)
	assert_eq(SceneSabotage.apply(door, by_change["root.speed = 0.0"]), "", "propiedad")
	assert_eq(door.speed, 0.0, "speed a 0")
	assert_eq(SceneSabotage.apply(door, by_change["Panel hidden"]), "", "ocultar")
	assert_false((door.get_node("Panel") as CanvasItem).visible, "Panel oculto")
	var timer := door.get_node("Timer") as Timer
	assert_eq(SceneSabotage.apply(door, by_change["Timer.timeout → root._on_timer_timeout disconnected"]), "", "señal")
	assert_false(timer.timeout.is_connected(door._on_timer_timeout), "desconectada")
	assert_true(SceneSabotage.apply(door, by_change["Timer.timeout → root._on_timer_timeout disconnected"]).contains("not connected"),
		"dos veces: ya no está conectada, el mutante no vale")
	assert_eq(SceneSabotage.apply(door, by_change["Zone/Shape disabled"]), "", "deshabilitar")
	await tree.process_frame
	assert_true((door.get_node("Zone/Shape") as CollisionShape2D).disabled, "deshabilitada (diferido)")
	var gone := (by_change["Panel hidden"] as Dictionary).duplicate()
	gone.node = "Missing"
	assert_true(SceneSabotage.apply(door, gone).contains("not in the scene"), "un nodo que ya no está")
	door.free()
	assert_eq(FileAccess.get_file_as_string(SCENE).contains("speed = 150.0"), true, "el .tscn no cambió")


func test_plan_includes_scene_sabotages() -> void:
	var entry: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(REGRESSION))
	entry.file = REGRESSION
	var entries: Array[Dictionary] = [entry]
	var plan := MutationTesting.plan(entries, 100)
	var scene := plan.filter(func(mutant: Dictionary) -> bool: return mutant.get("kind") == SceneSabotage.KIND)
	assert_eq(scene.size(), 4, "los sabotajes de la escena entran al plan")
	assert_true(plan.size() > scene.size(), "junto con los mutantes del script")
	assert_eq(Array(scene[0].regressions), [REGRESSION], "con sus regresiones")
	assert_eq(MutationTesting.where(scene[0]), SCENE, "sin «:0»")
	assert_eq(MutationTesting.where({"path": "res://a.gd", "line": 3}), "res://a.gd:3", "los de código con línea")
