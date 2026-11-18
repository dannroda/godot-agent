extends "test_case.gd"
## El juego del playtest termina si muere el editor (m2-07 de pruebas-windows): editor_watch escucha
## y el watchdog del juego mira la conexión.

const EditorWatch := preload("res://addons/godot_agent/playtest/editor_watch.gd")
const EditorWatchdog := preload("res://addons/godot_agent/playtest/runtime/editor_watchdog.gd")


## Se conecta, sigue vivo mientras el editor escucha y, cuando el editor se va, avisa una sola vez.
func test_game_ends_when_the_editor_goes() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var previous_env: Variant = OS.get_environment(EditorWatchdog.ENV) if OS.has_environment(EditorWatchdog.ENV) else null
	var watch := EditorWatch.new()
	assert_true(watch.start(), "el editor escucha")
	assert_eq(OS.get_environment(EditorWatchdog.ENV), str(watch.port()), "y deja el puerto en el entorno")
	await tree.process_frame  # la raíz entra al árbol recién en el primer frame
	var host := Node.new()
	tree.root.add_child(host)
	var gone: Array[int] = [0]
	var watchdog := EditorWatchdog.new()
	watchdog.on_editor_gone = func() -> void: gone[0] += 1
	assert_true(watchdog.start(host), "el juego se conecta con el puerto del entorno")
	assert_true(not (watchdog.get(&"_timer") as Timer).is_stopped(), "y el Timer corre")
	assert_eq(host.get_child_count(), 0, "el Timer es interno: no aparece en el árbol del juego")
	await _frames(tree, 40)  # el editor acepta cada POLL_MS
	assert_true(watchdog.check(), "con el editor vivo sigue vigilando")
	assert_true(watchdog.get(&"_connected"), "y la conexión quedó abierta")
	watch.stop()
	assert_true(not OS.has_environment(EditorWatchdog.ENV), "al parar, el editor saca la variable")
	var deadline := Time.get_ticks_msec() + 3000
	while watchdog.check() and Time.get_ticks_msec() < deadline:
		await tree.process_frame
	assert_eq(gone[0], 1, "sin editor, el juego se termina (una vez)")
	assert_true(not watchdog.check(), "y deja de vigilar")
	assert_eq(gone[0], 1, "no vuelve a avisar")
	host.free()
	if previous_env != null:
		OS.set_environment(EditorWatchdog.ENV, str(previous_env))


## Sin puerto (un juego lanzado a mano, o sin editor que escuche) no hace nada.
func test_nothing_without_an_editor() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var host := Node.new()
	tree.root.add_child(host)
	var gone: Array[int] = [0]
	var watchdog := EditorWatchdog.new()
	watchdog.on_editor_gone = func() -> void: gone[0] += 1
	assert_true(not watchdog.start(host, 0), "sin puerto no arranca")
	# Un puerto donde nadie escucha: la conexión falla y no se toma como que el editor murió.
	var free_port := TCPServer.new()
	free_port.listen(0, "127.0.0.1")
	var port := free_port.get_local_port()
	free_port.stop()
	if watchdog.start(host, port):
		# En Windows un connect rechazado en 127.0.0.1 tarda ~2 s (reintenta el SYN).
		var deadline := Time.get_ticks_msec() + 8000
		while watchdog.check() and Time.get_ticks_msec() < deadline:
			await tree.process_frame
	assert_eq(gone[0], 0, "una conexión que nunca abrió no termina el juego")
	assert_true(not watchdog.check(), "y deja de vigilar")
	host.free()


func _frames(tree: SceneTree, count: int) -> void:
	for i in count:
		await tree.process_frame
