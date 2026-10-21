extends "test_case.gd"
## Completado (M8a): LineIndex, LineRetrieval, historial, Ranker, post-procesado y proveedor local.

const ProjectContext := preload("res://addons/godot_agent/completion/project_context.gd")
const LineIndex := preload("res://addons/godot_agent/completion/local/line_index.gd")
const TypedHistory := preload("res://addons/godot_agent/completion/local/typed_history.gd")
const Ranker := preload("res://addons/godot_agent/completion/local/ranker.gd")
const LocalProvider := preload("res://addons/godot_agent/completion/local/local_provider.gd")
const PostProcessor := preload("res://addons/godot_agent/completion/post_processor.gd")
const RulesTest := preload("test_completion_rules.gd")

const FIXTURE := "res://tests/completion_fixture"
const NOW := 1_800_000_000.0


func _provider() -> LocalProvider:
	var context := ProjectContext.new()
	context.root = FIXTURE
	context.settings_file = FIXTURE + "/project_settings.cfg"
	context.build_now()
	return LocalProvider.new(context)


func _complete(provider: LocalProvider, path: String, line: String) -> String:
	var result := provider.complete(RulesTest.request_at(path, line))
	return result.text if result else "<nada>"


func test_line_index() -> void:
	assert_eq(LineIndex.normalize("\t\tvar  x\t:=   1"), "var x := 1", "sin indentación y con espacios colapsados")
	assert_eq(LineIndex.normalize("\tprint(\"a  b\",   'c  \\' d')"), "print(\"a  b\", 'c  \\' d')", "adentro de los strings no colapsa")
	assert_eq(LineIndex.lines_of("var a := 1\n\tpass\nx\n\tvar b := 2", 3), PackedStringArray(["var a := 1", "pass"]), "salta cortas y la del caret")
	var index: LineIndex = LineIndex.build({
		"res://a/one.gd": PackedStringArray(["health.changed.connect(_on_health_changed)", "health.changed.emit(value)", "var speed := 10"]),
		"res://a/two.gd": PackedStringArray(["health.changed.connect(_on_health_changed)"]),
		"res://b/three.gd": PackedStringArray(["health.changed.connect(_on_health_changed)", "var speed := 12"]),
	}, {"res://a/one.gd": NOW, "res://a/two.gd": NOW, "res://b/three.gd": NOW - 70 * 86400.0}, NOW)
	assert_eq(index.size(), 4, "líneas únicas")
	var found := index.query("health.changed.c", "res://a/one.gd", 100)
	assert_eq(found.size(), 1, "solo las que empiezan igual")
	assert_eq(found[0].rest, "onnect(_on_health_changed)", "devuelve el resto")
	# mismo archivo 3 + misma carpeta 2 + otra carpeta 1 × recencia vieja (~0.5)
	assert_true(absf(float(found[0].raw) - (3.0 + 2.0 + 0.5)) < 0.01, "cercanía × recencia (%.3f)" % found[0].raw)
	assert_eq(index.query("health.changed.", "res://c/x.gd", 100).size(), 2, "rango con dos líneas")
	assert_true(index.query("health.changed.", "res://c/x.gd", 1).is_empty(), "más de max_scan: ambiguo, nada")
	assert_true(index.query("var speed := 10", "res://a/one.gd", 100).is_empty(), "la línea completa no se sugiere a sí misma")


func test_retrieval_suggests_repeated_line() -> void:
	var provider := _provider()
	var turret := FIXTURE + "/actors/turret.gd"
	var hud := FIXTURE + "/ui/hud.gd"
	var player := FIXTURE + "/actors/player.gd"
	assert_eq(_complete(provider, turret, "\thealth.ch|"), "anged.connect(_on_health_changed)", "línea repetida en el proyecto")
	assert_eq(_complete(provider, hud, "\tvar direction := Input.ge|"), "t_axis(\"move_left\", \"move_right\")", "dos apariciones en otra carpeta alcanzan")
	assert_eq(_complete(provider, hud, "\tvelocity = velocity.mo|"), "<nada>", "una sola aparición lejana no alcanza")
	assert_eq(_complete(provider, player, "\tvelocity = velocity.mo|"), "ve_toward(Vector2.ZERO, FRICTION * delta)", "en el mismo archivo sí")
	assert_eq(_complete(provider, hud, "\tva|"), "<nada>", "menos de 3 caracteres: nada")
	var with_suffix := RulesTest.request_at(hud, "\tvar direction := Input.get_axis(|")
	with_suffix.line_suffix = ")"
	var result := provider.complete(with_suffix)
	assert_eq(result.text if result else "", "\"move_left\", \"move_right\"", "quita el ) que ya está a la derecha")
	var repeated := RulesTest.request_at(turret, "\thealth.ch|")
	repeated.next_line = "\thealth.changed.connect(_on_health_changed)"
	assert_eq(provider.complete(repeated), null, "no repite la línea siguiente")


func test_history() -> void:
	var history := TypedHistory.new()
	history.record("\tvar mana := 10")
	history.record("var max_mana := 20")
	history.record("x")
	assert_eq(history.size(), 2, "ignora líneas cortas")
	history.record("var mana := 15")
	var found := history.query("var ma")
	assert_eq(found[0].text, "na := 15", "la más reciente primero")
	assert_eq(found[1].text, "x_mana := 20", "después las anteriores")
	assert_true(float(found[0].score) > float(found[1].score), "más peso por recencia")
	history.record("var mana := 10")
	assert_eq(history.query("var mana")[0].text, " := 10", "repetir una línea la vuelve la más reciente")
	for i in TypedHistory.CAPACITY + 10:
		history.record("line_%d = %d" % [i, i])
	assert_eq(history.size(), TypedHistory.CAPACITY, "acotado")

	var provider := _provider()
	var hud := FIXTURE + "/ui/hud.gd"
	provider.history.record("\tvar stamina_regen := 4.5")
	assert_eq(_complete(provider, hud, "\tvar stamina_r|"), "egen := 4.5", "el historial de la sesión sugiere")


func test_ranker() -> void:
	var pick := func(candidates: Array) -> String:
		var typed: Array[Dictionary] = []
		typed.assign(candidates)
		var chosen := Ranker.pick(typed, 0.5, 0.12)
		return str(chosen.get("text", "<nada>"))
	assert_eq(pick.call([{"text": "a", "score": 0.4, "source": "retrieval"}]), "<nada>", "debajo del umbral")
	assert_eq(pick.call([{"text": "a", "score": 0.7, "source": "retrieval"}, {"text": "b", "score": 0.65, "source": "retrieval"}]), "<nada>", "sin margen sobre el rival: nada")
	assert_eq(pick.call([{"text": "a", "score": 0.8, "source": "retrieval"}, {"text": "b", "score": 0.6, "source": "retrieval"}]), "a", "con margen")
	assert_eq(pick.call([{"text": "foo", "score": 0.7, "source": "retrieval"}, {"text": "foo(bar)", "score": 0.66, "source": "retrieval"}]), "foo(bar)", "compatibles empatados: el más largo")
	assert_eq(pick.call([{"text": "foo", "score": 0.9, "source": "retrieval"}, {"text": "foo(bar)", "score": 0.5, "source": "retrieval"}]), "foo", "compatibles sin empate: el mejor")
	assert_eq(pick.call([{"text": "x", "score": 0.4, "source": "retrieval"}, {"text": "x", "score": 0.4, "source": "history"}]), "x", "duplicados se suman (1-(0.6·0.6) = 0.64)")
	assert_eq(pick.call([{"text": "r", "score": 0.95, "source": "rule", "rule": "virtual"}, {"text": "h", "score": 0.99, "source": "history"}]), "r", "una regla que aplica gana")
	var merged := Ranker.merge([{"text": "x", "score": 0.4, "source": "retrieval"}, {"text": "x", "score": 0.5, "source": "history"}] as Array[Dictionary])
	assert_eq(merged[0].source, "history", "la fuente del duplicado es la de mayor puntaje")


func test_post_processor() -> void:
	assert_eq(PostProcessor.strip_suffix_overlap("jump\")", "\")"), "jump", "quita el cierre del autocierre")
	assert_eq(PostProcessor.strip_suffix_overlap("bar)", ")  "), "bar", "ignora espacios del suffix")
	assert_eq(PostProcessor.strip_suffix_overlap("x", ")"), "x", "sin solapamiento")
	assert_eq(PostProcessor.process("bar()", "foo(", ")"), "bar()", "no quita un ) que hace falta para balancear")
	assert_eq(PostProcessor.process("ok\nsegunda", "", ""), "ok", "una sola línea")
	assert_eq(PostProcessor.process("   ", "x", ""), "", "solo espacios: descarta")
	assert_eq(PostProcessor.process("a))", "f(", ""), "", "cierres de más: descarta")
	assert_eq(PostProcessor.process("\"sin cerrar", "print(", ")"), "", "string sin cerrar: descarta")
	assert_eq(PostProcessor.process("ar := {", "var b", ""), "ar := {", "abrir un bloque está bien")
	assert_eq(PostProcessor.process(".x", ")", ""), ".x", "los cierres del prefix (de líneas de arriba) se toleran")
	assert_true(PostProcessor.balanced("f(\"(\", [1, {2: 3}])  # )"), "ignora strings y comentarios")
	assert_false(PostProcessor.balanced("f(]"), "cierres cruzados")


func test_rules_win_over_retrieval() -> void:
	var provider := _provider()
	var player := FIXTURE + "/actors/player.gd"
	assert_eq(_complete(provider, player, "func _|"), "process(delta: float) -> void:", "func _ -> virtual")
	var request := RulesTest.request_at(player, "\tif Input.is_action_pressed(\"j|")
	request.line_suffix = "\")"
	var result := provider.complete(request)
	assert_eq(result.text if result else "", "ump", "la regla deja lo que falta antes del autocierre")
	assert_eq(result.source if result else "", "rule", "fuente rule")
	provider.sources[LocalProvider.SOURCE_RULES] = false
	assert_eq(_complete(provider, player, "func _|"), "<nada>", "fuente de reglas apagada")
