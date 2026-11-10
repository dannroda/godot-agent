extends "test_case.gd"
## m11-43: los monitores de Performance que la probe muestrea en el juego y los nodos huérfanos.

const Monitors := preload("res://addons/godot_agent/playtest/runtime/monitors.gd")


func test_stats() -> void:
	var values := PackedFloat64Array()
	for i in 100:
		values.append(float(i + 1))
	var got := Monitors.stats(values)
	assert_eq([got.min, got.max, got.p95], [1.0, 100.0, 95.0], "mínimo, máximo y p95")
	assert_true(is_equal_approx(got.avg, 50.5), "promedio")
	assert_eq(Monitors.stats(PackedFloat64Array([7.0])).p95, 7.0, "con una muestra")
	assert_eq(Monitors.stats(PackedFloat64Array()).max, 0.0, "sin muestras, ceros")


func test_report_over_frames() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var monitors := Monitors.new()
	assert_true(monitors.report().begins_with("No frames were sampled"), "sin muestras lo dice")
	monitors.start()
	var leaked: Array[Node] = []
	for i in 5:
		await tree.process_frame
		var node := Node.new()  # nodos que nunca entran al árbol: crecen los huérfanos
		node.name = "LeakedBullet"
		leaked.append(node)
		monitors.tick()
	assert_eq(monitors.frames(), 5, "una muestra por frame")
	var text := monitors.report()
	assert_true(text.begins_with("Sampled 5 frames over "), "cuántos frames (%s)" % text.get_slice("\n", 0))
	assert_true(text.contains("Frame time: avg ") and text.contains(" p95 ") and text.contains("fps on average"), "tiempo de frame")
	assert_true(text.contains("Slowest frame of each second, as the engine measures it: process up to ") and text.contains("physics up to "), "tiempos de proceso y física, solo el máximo")
	# Otros tests liberan nodos en estos mismos frames: se mira el formato, no cuánto creció.
	assert_true(RegEx.create_from_string("orphan nodes \\d+ → \\d+").search(text) != null, "huérfanos al principio y al final (%s)" % text)
	assert_true(text.contains("static memory ") and text.contains(" MB"), "memoria en MB")
	assert_true(text.contains("- LeakedBullet (Node) ×5"), "lista los huérfanos agrupados (%s)" % text)
	assert_false(monitors.report(false).contains("Orphan nodes now"), "sin la lista si no se pide")
	for node: Node in leaked:
		node.free()


func test_orphan_text_names_class_and_script() -> void:
	var script := load("res://tests/fixtures/profile_fixture.gd") as Script
	var node := Node2D.new()
	node.name = "Lost"
	node.set_script(script)
	var text := Monitors.orphan_text()
	assert_true(text.contains("- Lost (Node2D, res://tests/fixtures/profile_fixture.gd)"), "clase y script (%s)" % text)
	node.free()
	assert_false(Monitors.orphan_text().contains("Lost (Node2D"), "liberado, ya no está")


func test_change_format() -> void:
	assert_eq(Monitors._change("nodes", 4, 9, false), "nodes 4 → 9 (+5)", "lo que creció")
	assert_eq(Monitors._change("nodes", 9, 9, false), "nodes 9 → 9", "sin cambio, sin paréntesis")
	assert_eq(Monitors._change("orphan nodes", 3, 1, false), "orphan nodes 3 → 1 (-2)", "lo que bajó")
	assert_eq(Monitors._change("static memory", 50.0 * Monitors.MB, 51.5 * Monitors.MB, true), "static memory 50.0 → 51.5 MB (+1.5)", "memoria en MB")
