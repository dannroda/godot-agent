extends "test_case.gd"
## Benchmark del completado local (M8a, spec §16.2 y §12): proyecto generado de 200 scripts y 60
## escenas; mide el build del índice (en el hilo del test) y la latencia por consulta del proveedor
## local con una mezcla de reglas y recuperación. Criterio: p95 < 10 ms por consulta.

const ProjectContext := preload("res://addons/godot_agent/completion/project_context.gd")
const LocalProvider := preload("res://addons/godot_agent/completion/local/local_provider.gd")
const CompletionRequest := preload("res://addons/godot_agent/completion/completion_request.gd")

const SCRIPTS := 200
const SCENES := 60
const QUERIES := 1500
const P95_LIMIT_MS := 10.0
const SEED := 8128

const NODE_TYPES: PackedStringArray = ["Sprite2D", "CollisionShape2D", "Area2D", "Timer", "AnimationPlayer", "Label", "AudioStreamPlayer2D", "Marker2D", "RayCast2D", "GPUParticles2D"]
const BASES: PackedStringArray = ["CharacterBody2D", "Node2D", "Area2D", "Control", "Node", "RigidBody2D"]
const WORDS: PackedStringArray = ["health", "speed", "target", "damage", "score", "ammo", "cooldown", "enemy", "player", "shield", "jump", "coins", "level", "timer", "spawn", "wave", "boss", "item", "slot", "mana"]

var _rng := RandomNumberGenerator.new()


func test_p95_under_10ms() -> void:
	_rng.seed = SEED
	var root := temp_dir("completion_bench")
	var scripts := _generate(root)
	var context := ProjectContext.new()
	context.root = root
	var started := Time.get_ticks_usec()
	context.build_now()
	var build_ms := (Time.get_ticks_usec() - started) / 1000.0
	assert_eq(context.index.scripts.size(), SCRIPTS, "indexó los scripts generados")
	var provider := LocalProvider.new(context)

	var requests := _requests(scripts)
	# Calentamiento: cachés de ClassDB y regex compiladas no cuentan.
	for i in 50:
		provider.complete(requests[i])
	var samples: Array[float] = []
	var shown := 0
	for request: CompletionRequest in requests:
		var t0 := Time.get_ticks_usec()
		var result := provider.complete(request)
		samples.append((Time.get_ticks_usec() - t0) / 1000.0)
		if result:
			shown += 1
	samples.sort()
	var p50 := samples[samples.size() / 2]
	var p95 := samples[int(samples.size() * 0.95)]
	var worst := samples[samples.size() - 1]
	print("completion_bench: %d scripts, %d escenas, %d líneas únicas; build %.0f ms; %d consultas: p50 %.2f ms, p95 %.2f ms, máx %.2f ms; con sugerencia %d (%s)" % [
		context.index.scripts.size(), context.index.scenes.size(), context.lines().size(), build_ms,
		samples.size(), p50, p95, worst, shown, Engine.get_version_info().string])
	assert_true(p95 < P95_LIMIT_MS, "p95 %.2f ms < %.0f ms" % [p95, P95_LIMIT_MS])
	assert_true(shown > QUERIES / 10, "sugiere en una parte de las consultas (%d)" % shown)
	assert_true(build_ms < 5000.0, "el build entra en unos segundos (%.0f ms)" % build_ms)

	# Build incremental: un archivo cambiado reutiliza el resto.
	var file := FileAccess.open(scripts[0].path, FileAccess.WRITE)
	file.store_string(str(scripts[0].text) + "\nfunc added() -> void:\n\tpass\n")
	file.close()
	started = Time.get_ticks_usec()
	context.build_now()
	print("completion_bench: rebuild con un archivo cambiado %.0f ms" % ((Time.get_ticks_usec() - started) / 1000.0))
	assert_true("added" in context.index.scripts[scripts[0].path].funcs, "reindexó el archivo cambiado")


## Escribe SCRIPTS scripts y SCENES escenas; devuelve [{path, text}].
func _generate(root: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for i in SCRIPTS:
		var folder := root.path_join("feature_%d" % (i % 20))
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
		var path := folder.path_join("script_%d.gd" % i)
		var text := _script_text(i)
		var file := FileAccess.open(path, FileAccess.WRITE)
		file.store_string(text)
		file.close()
		out.append({"path": path, "text": text})
	for i in SCENES:
		var script: Dictionary = out[i]
		var scene := "[gd_scene format=3]\n\n[ext_resource type=\"Script\" path=\"%s\" id=\"1\"]\n\n[node name=\"Root\" type=\"%s\"]\nscript = ExtResource(\"1\")\n" % [script.path, BASES[i % BASES.size()]]
		for n in 12 + i % 15:
			var parent := "." if n < 4 else "Child%d" % (n % 4)
			scene += "\n[node name=\"Child%d\" type=\"%s\" parent=\"%s\"]\n" % [n, NODE_TYPES[n % NODE_TYPES.size()], parent]
			if n % 7 == 3:
				scene += "unique_name_in_owner = true\n"
		scene += "\n[connection signal=\"timeout\" from=\"Child3\" to=\".\" method=\"_on_child_3_timeout\"]\n"
		var file := FileAccess.open(str(script.path).get_basename() + ".tscn", FileAccess.WRITE)
		file.store_string(scene)
		file.close()
	return out


func _word() -> String:
	return WORDS[_rng.randi() % WORDS.size()]


func _script_text(i: int) -> String:
	var lines := PackedStringArray()
	lines.append("class_name Bench%d" % i if i % 3 == 0 else "")
	lines.append("extends %s" % BASES[i % BASES.size()])
	lines.append("")
	for s in 3:
		lines.append("signal %s_changed(value: int)" % _word())
	lines.append("")
	for v in 12:
		var word := _word()
		lines.append("@export var %s_%d: float = %d.0" % [word, v, _rng.randi_range(1, 50)])
	lines.append("@onready var child_0: Sprite2D = $Child0")
	lines.append("")
	lines.append("func _ready() -> void:")
	lines.append("\tadd_to_group(\"%ss\")" % _word())
	lines.append("\t$Child3.timeout.connect(_on_child_3_timeout)")
	lines.append("\thealth_changed.connect(_on_health_changed)")
	for f in 8:
		var word := _word()
		lines.append("")
		lines.append("func update_%s_%d(delta: float) -> void:" % [word, f])
		lines.append("\tvar direction := Input.get_axis(\"move_left\", \"move_right\")")
		lines.append("\tvelocity = velocity.move_toward(Vector2.ZERO, friction * delta)")
		lines.append("\tif %s_%d > 0.0:" % [word, f])
		lines.append("\t\t%s_%d -= delta * %d" % [word, f, _rng.randi_range(1, 9)])
		lines.append("\t\temit_signal(\"%s_changed\", %d)" % [_word(), f])
		lines.append("\tprint(\"%s\", %s_%d)" % [word, word, f])
		for extra in 6:
			lines.append("\tvar %s_%d_%d := %s * %d.%d" % [_word(), i, extra, _word(), _rng.randi_range(1, 99), extra])
	lines.append("")
	lines.append("func _on_health_changed(value: int) -> void:")
	lines.append("\tscore += value")
	return "\n".join(lines) + "\n"


## Mezcla de consultas: líneas del corpus cortadas al azar (recuperación) y disparadores de reglas.
func _requests(scripts: Array[Dictionary]) -> Array[CompletionRequest]:
	var out: Array[CompletionRequest] = []
	var triggers: PackedStringArray = ["@onready var ", "func _", "func _on_", "\t$Chi", "\t%Chi", "\tif Input.is_action_pressed(\"", "extends Ch", "\tadd_to_group(\"", "\t$Child3.timeout.connect(", "\tvar s := preload(\"res://"]
	for q in QUERIES:
		var script: Dictionary = scripts[_rng.randi() % scripts.size()]
		var lines := str(script.text).split("\n")
		var typed: String
		if q % 4 == 0:
			typed = triggers[(q / 4) % triggers.size()]
		else:
			var source := lines[_rng.randi() % lines.size()]
			while source.strip_edges().length() < 6:
				source = lines[_rng.randi() % lines.size()]
			var indent := source.length() - source.strip_edges(true, false).length()
			typed = source.left(_rng.randi_range(indent + 3, source.length() - 1))
		var text := "\n".join(lines.slice(0, lines.size() - 1)) + "\n" + typed
		out.append(CompletionRequest.make(str(script.path), text, lines.size() - 1, typed.length()))
	return out
