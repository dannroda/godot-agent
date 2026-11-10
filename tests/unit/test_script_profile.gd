extends "test_case.gd"
## m13-27: godot.profile_run. Parte pura (frames del profiler → funciones calientes, tipado leído del
## script) y las negativas de la tool que no necesitan el editor.

const ScriptProfile := preload("res://addons/godot_agent/playtest/script_profile.gd")
const ProfileTools := preload("res://addons/godot_agent/mcp/tools/profile_tools.gd")
const RunTools := preload("res://addons/godot_agent/mcp/tools/run_tools.gd")
const FIXTURE := "res://tests/fixtures/profile_fixture.gd"


## Un frame serializado como ServersProfilerFrame: `functions` = [[id, calls, self, total], …].
static func _frame(number: int, frame_time: float, script_time: float, functions: Array, servers: Array = []) -> Array:
	var data: Array = [number, frame_time, frame_time, 0.0, 0.016, script_time, servers.size()]
	for server: Array in servers:
		data.append(server[0])
		data.append(2)
		data.append("draw")
		data.append(server[1])
	data.append(functions.size() * 5)
	for function: Array in functions:
		data.append_array([function[0], function[1], function[2], function[3], 0.0])
	return data


func test_parse_frame() -> void:
	var frame := ScriptProfile.parse_frame(_frame(10, 0.002, 0.0005, [[0, 2000, 0.0001, 0.0001], [1, 1, 0.00008, 0.0004]], [["RenderingServer", 0.0003]]))
	assert_eq(frame.frame_time, 0.002, "frame_time")
	assert_eq(frame.script_time, 0.0005, "script_time")
	assert_eq(frame.functions[0], {"calls": 2000, "self": 0.0001, "total": 0.0001, "internal": 0.0}, "función con el bloque de servers salteado")
	assert_eq(frame.functions[1].total, 0.0004, "self antes que total, como en serialize()")
	assert_eq(ScriptProfile.parse_frame([1, 2, 3]), {}, "corto")
	assert_eq(ScriptProfile.parse_frame([1, 0.1, 0.1, 0, 0, 0, 0, 10, 0, 1]), {}, "dice más funciones de las que trae")


func test_first_frame_and_impossible_frames_are_discarded() -> void:
	var profile := ScriptProfile.new()
	profile.add_signature(["res://a.gd::3::_step", 0])
	# El primer frame tras el toggle: llamadas en curso medidas desde 0 (lo que pasa en 4.7/4.8).
	profile.add_frame(_frame(1, 0.002, 0.86, [[0, 1331, 0.86, 0.86]]))
	profile.add_frame(_frame(2, 0.002, 0.0001, [[0, 2000, 0.0001, 0.0001]]))
	# Uno donde una función dura más que el frame: también basura.
	profile.add_frame(_frame(3, 0.002, 0.5, [[0, 2000, 0.5, 0.5]]))
	profile.add_frame(_frame(4, 0.004, 0.0003, [[0, 2000, 0.0003, 0.0003]]))
	assert_eq([profile.frames, profile.discarded], [2, 2], "quedan los dos frames buenos")
	var rows := profile.top(5)
	assert_eq(rows.size(), 1, "una función")
	assert_eq(rows[0].calls, 2000.0, "llamadas por frame, sin el parcial del primero")
	assert_true(absf(rows[0].self_ms - 0.2) < 1e-9, "self promedio: (0.1 + 0.3) / 2 ms")
	assert_true(absf(profile.average_frame_ms() - 3.0) < 1e-9, "frame promedio")



## Revisión de m13-27: una función recursiva tiene un total mayor que el frame (cada nivel cuenta lo
## anidado) y no por eso el frame es basura; el descarte mira el tiempo propio.
func test_recursive_function_keeps_its_frames() -> void:
	var profile := ScriptProfile.new()
	profile.add_signature(["res://a.gd::3::flood", 0])
	profile.add_frame([])
	profile.add_frame(_frame(2, 0.016, 0.004, [[0, 8, 0.004, 0.032]]))
	assert_eq([profile.frames, profile.discarded], [1, 1], "el frame con la recursiva cuenta")


## Revisión de m13-27: después de una pausa del debugger (continue_on_error), el frame que la
## contiene no se cuenta: la llamada en curso se lleva el tiempo de la pausa.
func test_frame_after_a_debugger_pause_is_skipped() -> void:
	var profile := ScriptProfile.new()
	profile.add_frame([])
	profile.add_frame(_frame(2, 0.002, 0.0001, [[0, 10, 0.0001, 0.0001]]))
	profile.skip_next_frame()
	profile.add_frame(_frame(3, 0.4, 0.38, [[0, 10, 0.38, 0.38]]))
	profile.add_frame(_frame(4, 0.002, 0.0001, [[0, 10, 0.0001, 0.0001]]))
	assert_eq([profile.frames, profile.discarded], [2, 2], "el de la pausa se descarta aunque frame_time también sea largo")


## Revisión de m13-27: datos mal formados no cuelgan el editor (un conteo negativo dejaba el índice quieto).
func test_malformed_frames() -> void:
	assert_eq(ScriptProfile.parse_frame([1, 0.1, 0.1, 0, 0, 0, 1000000000, "s", -2, 0]), {}, "muchos servers y un conteo negativo")
	assert_eq(ScriptProfile.parse_frame([1, 0.1, 0.1, 0, 0, 0, -1, 0]), {}, "servers negativos")
	assert_eq(ScriptProfile.parse_frame([1, 0.1, 0.1, 0, 0, 0, 1, "s", -2, 5, 0]), {}, "pares negativos")

func test_top_orders_by_self_time() -> void:
	var profile := ScriptProfile.new()
	profile.add_signature(["res://a.gd::10::_hot", 1])
	profile.add_signature(["res://a.gd::20::_step", 0])
	profile.add_signature(["res://b.gd::5::_process", 2])
	profile.add_frame([])  # el descartado
	for i in 3:
		profile.add_frame(_frame(i, 0.003, 0.001, [[0, 2000, 0.0006, 0.0006], [1, 1, 0.0003, 0.0009], [2, 1, 0.0001, 0.001]]))
	var rows := profile.top(2)
	assert_eq(rows.map(func(row: Dictionary) -> String: return row.name), ["_step", "_hot"], "por tiempo propio, recortado a `count`")
	assert_eq([rows[1].path, rows[1].line], ["res://a.gd", 10], "ruta y línea de la firma")
	assert_true(absf(rows[0].share - 0.6) < 1e-6, "parte del tiempo de script")
	assert_true(absf(rows[1].total_ms - 0.9) < 1e-6, "total con lo que llama")


func test_split_signature() -> void:
	assert_eq(ScriptProfile.split_signature("res://a/b.gd::12::_process"), {"path": "res://a/b.gd", "line": 12, "name": "_process"}, "script en archivo")
	assert_eq(ScriptProfile.split_signature("res://s.tscn::GDScript_abc::7::run"), {"path": "res://s.tscn::GDScript_abc", "line": 7, "name": "run"}, "script built-in: la ruta lleva el sub-recurso")
	assert_eq(ScriptProfile.split_signature("raro"), {"path": "raro", "line": 0, "name": ""}, "sin forma")


func test_typed_in_source() -> void:
	var source := "\n".join([
		"extends Node",  # 1
		"func a(x: int, y := 2.0) -> float:",  # 2
		"\treturn x + y",
		"func b(x, y):",  # 4
		"\tpass",
		"func c(x: int, y) -> void:",  # 6
		"\tpass",
		"func d():",  # 8
		"\tpass",
		"func e(",  # 10
		"\t\tx: Vector2 = Vector2(1, 2),",
		"\t\ty: Array[int] = [],",
		") -> Dictionary:",
		"\treturn {}",
		"func f(x) -> int: return g(x)",  # 15
		"static func s() -> void:",  # 16
		"\tpass",
		"func g(opts = {\"a\": 1}, s = \"x:y\"):",  # 18
		"\tpass",
		"func h(a: String = \")\", b := \"(,\") -> void:",  # 20
		"\tpass",
	])
	# La firma del profiler trae la primera línea del cuerpo: se busca el func hacia atrás.
	assert_eq(ScriptProfile.typed_in_source(source, 3, "a"), {"typed": "yes", "line": 2}, "parámetros con tipo, := y retorno; la línea del func")
	assert_eq(ScriptProfile.typed_in_source(source, 5, "b").typed, "no", "nada tipado")
	assert_eq(ScriptProfile.typed_in_source(source, 7, "c").typed, "partial", "un parámetro sin tipo")
	assert_eq(ScriptProfile.typed_in_source(source, 9, "d").typed, "no", "sin parámetros ni retorno")
	assert_eq(ScriptProfile.typed_in_source(source, 14, "e"), {"typed": "yes", "line": 10}, "cabecera en varias líneas con defaults que llevan comas")
	assert_eq(ScriptProfile.typed_in_source(source, 15, "f").typed, "partial", "una línea con una llamada en el cuerpo: la firma es la misma línea")
	assert_eq(ScriptProfile.typed_in_source(source, 17, "s"), {"typed": "yes", "line": 16}, "static")
	assert_eq(ScriptProfile.typed_in_source(source, 5, "a"), {"typed": "", "line": 0}, "no sigue buscando más allá de otra función")
	assert_eq(ScriptProfile.typed_in_source(source, 99, "a"), {"typed": "", "line": 0}, "fuera del archivo")
	# Revisión de m13-27: un `:` dentro del default no es un tipo, y los strings no cortan la cabecera.
	assert_eq(ScriptProfile.typed_in_source(source, 19, "g").typed, "no", "defaults con `:` adentro, sin tipos")
	assert_eq(ScriptProfile.typed_in_source(source, 21, "h"), {"typed": "yes", "line": 20}, "paréntesis y comas dentro de strings")


func test_typed_in_file() -> void:
	# Las firmas reales que mandó el juego en el profile-test: ::28::_hot y ::33::_step.
	assert_eq(ScriptProfile.typed_in_file(FIXTURE, 28, "_hot"), {"typed": "yes", "line": 27}, "la escena del profile-test")
	assert_eq(ScriptProfile.typed_in_file(FIXTURE, 33, "_step"), {"typed": "yes", "line": 32}, "_step")
	assert_eq(ScriptProfile.typed_in_file("res://s.tscn::GDScript_abc", 7, "run").typed, "", "built-in: no se lee")
	assert_eq(ScriptProfile.typed_in_file("res://no_existe.gd", 1, "f").typed, "", "archivo que no está")


func test_report() -> void:
	var empty := ScriptProfile.new()
	empty.add_frame([])
	assert_true(empty.report(5).begins_with("No usable profiler frames arrived (1 discarded)"), "sin frames útiles lo dice")
	var profile := ScriptProfile.new()
	profile.add_signature([FIXTURE + "::33::_step", 0])
	profile.add_frame([])
	profile.add_frame(_frame(2, 0.002, 0.0002, [[0, 2000, 0.0001, 0.0001]]))
	var text := profile.report(5)
	assert_true(text.contains("1 frames (1 discarded"), "frames y descartados")
	assert_true(text.contains("%s:32 _step — 2000.0 calls, self 0.100 ms" % FIXTURE), "ruta:línea del func, llamadas y tiempos")
	assert_true(text.contains("typed: yes"), "tipada, leída del script")
	assert_true(text.ends_with(ScriptProfile.OVERHEAD_NOTE), "y la nota del overhead")


func test_tool_refuses_while_busy() -> void:
	# Sin editor no hay EditorDebuggerPlugin: alcanza con RunTools sin setup.
	var run_tools := RunTools.new()
	var tools := ProfileTools.new()
	tools.setup(run_tools, null)
	var listed: Array = tools.tools()
	assert_eq(listed.size(), 1, "una tool")
	assert_eq([listed[0].name, listed[0].group], ["profile_run", "run"], "profile_run, del grupo de ejecutar")
	var properties: Dictionary = listed[0].input_schema.properties
	assert_true(properties.has("inputs") and properties.has("scene") and properties.has("top"), "los args de run_scene más los propios")
	run_tools._busy = true
	run_tools._busy_since_ms = Time.get_ticks_msec()
	var result: Dictionary = await tools._profile_run({})
	assert_true(result.isError and str(result.content[0].text).begins_with("A run_scene is in progress (game: no game launched"), "no choca con un run_scene en curso y dice el estado del juego")
	assert_false(tools._profiling, "no quedó perfilando")
	tools._profiling = true
	result = await tools._profile_run({})
	assert_true(result.isError and str(result.content[0].text).contains("already in progress"), "uno a la vez")
	tools._profiling = false
	tools.shutdown()
