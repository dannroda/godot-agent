extends "res://tests/unit/test_case.gd"
## m11-41: mutantes de GDScript para medir las regresiones.

const Mutator := preload("res://addons/godot_agent/playtest/mutation/gdscript_mutator.gd")
const MutationTesting := preload("res://addons/godot_agent/playtest/mutation/mutation_testing.gd")
const SaveGuard := preload("res://addons/godot_agent/playtest/mutation/save_guard.gd")

const SOURCE := "extends Node2D\n# x < 3 en un comentario\nconst SPEED := 5.0\nvar limit := 3\n\n\nfunc tick(x: int) -> bool:\n\tvar label := \"a < b and true\"\n\tif x < limit and ready:\n\t\tposition.x += 2 * x\n\t\tqueue_free()  # nada\n\treturn x == 0\n\n\nfunc other() -> void:\n\tpass\n"


func _changes(path: String = "res://a.gd") -> Array[String]:
	var lines := SOURCE.split("\n")
	var result: Array[String] = []
	for mutant: Dictionary in Mutator.mutants(SOURCE, path):
		result.append("%d %s %s" % [mutant.line, mutant.op, Mutator.describe(lines[int(mutant.line) - 1], mutant)])
	return result


func test_operators() -> void:
	var changes := _changes()
	for expected: String in [
			"3 number const SPEED := 5.0 → const SPEED := 0.0",
			"9 relational if x < limit and ready: → if x <= limit and ready:",
			"9 logical if x < limit and ready: → if x < limit or ready:",
			"9 negate_condition if x < limit and ready: → if not (x < limit and ready):",
			"10 arithmetic position.x += 2 * x → position.x -= 2 * x",
			"10 arithmetic position.x += 2 * x → position.x += 2 / x",
			"10 number position.x += 2 * x → position.x += 0 * x",
			"10 delete_statement position.x += 2 * x → pass",
			"12 relational return x == 0 → return x != 0",
			"12 number return x == 0 → return x == 1"]:
		assert_true(expected in changes, "%s · %s" % [expected, changes])


func test_leaves_alone() -> void:
	var changes := _changes()
	for change: String in changes:
		assert_false(change.begins_with("2 "), "el comentario no se muta: " + change)
		assert_false(change.begins_with("4 "), "una var fuera de funciones no se muta: " + change)
		assert_false(change.begins_with("8 "), "el string no se muta (ni se borra la declaración): " + change)
		assert_false(change.contains("-> bool") and not change.begins_with("9") and not change.begins_with("10") and not change.begins_with("12"), "la firma no se muta: " + change)
	assert_false(changes.any(func(change: String) -> bool: return change.begins_with("11 delete_statement")), "una línea con comentario al final no se borra (pass dejaría el comentario colgando)")
	assert_false(changes.any(func(change: String) -> bool: return change.begins_with("16")), "pass no se muta")


func test_apply() -> void:
	var mutants := Mutator.mutants(SOURCE, "res://a.gd")
	var negate: Dictionary = mutants.filter(func(m: Dictionary) -> bool: return m.op == Mutator.OP_NEGATE)[0]
	var mutated := Mutator.apply(SOURCE, negate)
	assert_true(mutated.contains("\tif not (x < limit and ready):\n"), "aplica en su lugar")
	assert_eq(mutated.split("\n").size(), SOURCE.split("\n").size(), "no cambia el largo del archivo")
	var script := GDScript.new()
	script.source_code = mutated
	assert_eq(script.reload(), OK, "compila")
	var stale := negate.duplicate()
	stale.col = int(stale.col) + 1
	assert_eq(Mutator.apply(SOURCE, stale), "", "si la línea ya no dice lo mismo, no aplica")


func test_sample_is_spread_and_deterministic() -> void:
	var all: Array[Dictionary] = []
	all.append_array(Mutator.mutants(SOURCE, "res://a.gd"))
	all.append_array(Mutator.mutants(SOURCE, "res://b.gd"))
	var first := Mutator.sample(all, 6)
	assert_eq(first.size(), 6, "seis")
	assert_eq(first, Mutator.sample(all, 6), "la misma muestra cada vez")
	assert_eq(first.filter(func(m: Dictionary) -> bool: return m.path == "res://a.gd").size(), 3, "repartida entre scripts")
	var lines_a: Array = first.filter(func(m: Dictionary) -> bool: return m.path == "res://a.gd").map(func(m: Dictionary) -> int: return m.line)
	assert_true(lines_a.min() < lines_a.max(), "y a lo largo del archivo: %s" % [lines_a])
	assert_eq(Mutator.sample(all, 1000).size(), all.size(), "pedir más que los que hay da todos")


func test_scripts_of_scene() -> void:
	assert_eq(MutationTesting.scripts_of("res://tests/fixtures/playtest_game/playtest_game.tscn"),
		PackedStringArray(["res://tests/fixtures/playtest_game/player.gd", "res://tests/fixtures/playtest_game/playtest_game.gd"]), "los scripts de la escena y de lo que instancia")
	var plan := MutationTesting.plan([{"scene": "res://tests/fixtures/playtest_game/playtest_game.tscn", "file": "res://r/jump.json"}] as Array[Dictionary], 4)
	assert_eq(plan.size(), 4, "cuatro mutantes")
	assert_eq(plan[0].regressions, PackedStringArray(["res://r/jump.json"]), "cada uno con sus regresiones")
	assert_true(str(plan[0].change).contains("→"), "con el cambio legible")


func test_score() -> void:
	var mutants := [
		{"status": "killed", "killed_by": ["a.json"], "regressions": PackedStringArray(["a.json", "b.json"])},
		{"status": "killed", "killed_by": ["a.json"], "regressions": PackedStringArray(["a.json", "b.json"])},
		{"status": "timeout", "regressions": PackedStringArray(["a.json"])},
		{"status": "survived", "regressions": PackedStringArray(["a.json", "b.json"])},
		{"status": "invalid", "regressions": PackedStringArray(["a.json"])},
	]
	var score := MutationTesting.score(mutants)
	assert_eq([score.detected, score.measured, score.percent, score.invalid], [3, 4, 75, 1], "timeout cuenta como detectado; no válido no cuenta")
	assert_eq(score.by_regression, {"a.json": 2, "b.json": 0}, "b no atrapó ninguno")


func test_save_guard_writes_nothing() -> void:
	var guard := SaveGuard.new()
	Engine.set_meta(&"godot_agent_save_guard_test", true)
	ResourceSaver.add_resource_format_saver(guard, true)
	var path := "user://test_save_guard.tres"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	var error := ResourceSaver.save(Resource.new(), path)
	ResourceSaver.remove_resource_format_saver(guard)
	Engine.remove_meta(&"godot_agent_save_guard_test")
	assert_eq(error, OK, "se queda con el guardado (con un error, ResourceSaver probaría el saver siguiente)")
	assert_false(FileAccess.file_exists(path), "y no escribe nada")
	assert_eq(guard.attempts, PackedStringArray([path]), "lo anota")


func test_notice() -> void:
	var result := MutationTesting.score([
		{"status": "killed", "killed_by": ["res://r/jump.json"], "regressions": PackedStringArray(["res://r/jump.json", "res://r/start.json"])},
		{"status": "survived", "path": "res://p.gd", "line": 7, "change": "a < b → a <= b", "regressions": PackedStringArray(["res://r/jump.json", "res://r/start.json"])},
		{"status": "invalid", "regressions": PackedStringArray(["res://r/jump.json"])},
	])
	result.mutants = [{"status": "survived", "path": "res://p.gd", "line": 7, "change": "a < b → a <= b"}]
	var notice := MutationTesting.notice(result, {"res://r/jump.json": "The player jumps"}, func(text: String) -> String: return text)
	assert_eq(notice.title, "Regressions: mutation score 1/2 (50 %)", "el puntaje")
	assert_true(str(notice.text).contains("1 did not compile (not counted)"), "los no válidos aparte")
	assert_eq(notice.sections[0].text, "p.gd:7 · a < b → a <= b", "los no detectados")
	assert_true(str(notice.sections[1].text).contains("«The player jumps»: caught 1") and str(notice.sections[1].text).contains("«start.json»: detects nothing"), "por regresión: %s" % notice.sections[1].text)
	assert_eq(notice.survivors, [{"path": "res://p.gd", "line": 7}], "con su botón para abrir")
	assert_true(notice.level_warning, "bajo 80 % o con una que no detecta nada es advertencia")
