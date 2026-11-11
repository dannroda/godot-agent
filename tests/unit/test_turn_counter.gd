extends "test_case.gd"
## El contador vivo de cambios del turno (m11-34): cuenta desde el snapshot del principio del turno,
## a lo sumo cada THROTTLE_S, se borra al terminar y abre los cambios para ver (sin tocar).

const TurnCounter := preload("res://addons/godot_agent/ui/turn_counter.gd")
const TurnSnapshots := preload("res://addons/godot_agent/session/turn_snapshots.gd")
const SessionModel := preload("res://addons/godot_agent/session/session_model.gd")
const AddonUpdater := preload("res://addons/godot_agent/core/addon_updater.gd")


class FakeDock:
	var summaries: Array = []
	func set_turn_changes(summary: Dictionary) -> void:
		summaries.append(summary)


func test_counts_the_turn() -> void:
	if OS.execute("git", ["--version"]) != 0:
		return
	var root := ProjectSettings.globalize_path("user://unit_tests/turn_counter")
	AddonUpdater._remove_tree(root)
	DirAccess.make_dir_recursive_absolute(root)
	_write(root.path_join("a.gd"), "1\n")
	for args: Array in [["init", "-q"], ["-c", "user.name=t", "-c", "user.email=t@t", "add", "-A"], ["-c", "user.name=t", "-c", "user.email=t@t", "commit", "-qm", "base"]]:
		OS.execute("git", PackedStringArray(["-C", root]) + PackedStringArray(args))
	var snapshots := TurnSnapshots.new(root)
	await snapshots.setup()
	var dock := FakeDock.new()
	var opened: Array = []
	var clock := [100000]
	var counter := TurnCounter.new()
	counter.snapshots_of = func(_s: String) -> TurnSnapshots: return snapshots
	counter.dock_of = func(_s: String) -> Object: return dock
	counter.open_dialog = func(data: Dictionary) -> void: opened.append(data)
	counter.now_ms = func() -> int: return clock[0]

	# Un turno de Preguntar: sin snapshot desde que empezó, no cuenta nada.
	await snapshots.take("s1")  # de un turno anterior
	OS.delay_msec(5)
	counter.on_state("s1", SessionModel.SessionState.PROMPTING)
	_write(root.path_join("a.gd"), "2\n")
	await counter.refresh("s1")
	assert_eq(dock.summaries, [], "sin snapshot del turno, nada")
	counter.on_state("s1", SessionModel.SessionState.READY)
	dock.summaries.clear()

	# Un turno de Construir: el controller toma el snapshot al empezar.
	counter.on_state("s1", SessionModel.SessionState.PROMPTING)
	OS.delay_msec(5)
	var start := await snapshots.take("s1")
	_write(root.path_join("a.gd"), "3\n4\n")
	_write(root.path_join("b.gd"), "new\n")
	await counter.refresh("s1")
	assert_eq(dock.summaries.size(), 1)
	var summary: Dictionary = dock.summaries[-1]
	assert_eq([summary.files.size(), summary.added, summary.removed, summary.start], [2, 3, 1, start], "2 archivos · +3 −1 desde el principio del turno")

	# A lo sumo cada THROTTLE_S.
	counter.note_activity("s1")
	counter._process(0.0)
	assert_eq(dock.summaries.size(), 1, "recién calculado: espera")
	clock[0] += int(TurnCounter.THROTTLE_S * 1000.0) + 1
	counter._process(0.0)
	await _until(func() -> bool: return dock.summaries.size() == 2)
	assert_eq(dock.summaries.size(), 2, "pasado el intervalo, recalcula")

	# Ver los cambios hasta ahora: solo para ver, y los trozos salen del árbol de peek.
	counter.open("s1")
	assert_eq(opened.size(), 1)
	assert_true(opened[0].live and opened[0].start == start and not str(opened[0].end).is_empty(), "abre en modo de solo ver")
	assert_eq((await snapshots.hunks(opened[0].start, opened[0].end, "a.gd")).size(), 1, "los trozos hasta ahora")

	# Al terminar el turno se borra.
	counter.on_state("s1", SessionModel.SessionState.READY)
	assert_eq(dock.summaries[-1], {}, "se oculta")
	counter.note_activity("s1")
	assert_false(counter.get(&"_pending").has("s1"), "fuera de un turno no se recalcula")
	counter.free()


func _tick() -> void:
	await (Engine.get_main_loop() as SceneTree).process_frame


func _until(condition: Callable) -> void:
	for i in 300:
		if condition.call():
			return
		await _tick()


func _write(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()
