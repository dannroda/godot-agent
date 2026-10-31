extends "test_case.gd"
## Completado (M8a, M8b): LineIndex, LineRetrieval (línea siguiente, bloques, adaptación), historial,
## Ranker, post-procesado, caché y proveedor local.

const ProjectContext := preload("res://addons/godot_agent/completion/project_context.gd")
const LineIndex := preload("res://addons/godot_agent/completion/local/line_index.gd")
const TypedHistory := preload("res://addons/godot_agent/completion/local/typed_history.gd")
const Ranker := preload("res://addons/godot_agent/completion/local/ranker.gd")
const LocalProvider := preload("res://addons/godot_agent/completion/local/local_provider.gd")
const PostProcessor := preload("res://addons/godot_agent/completion/post_processor.gd")
const CompletionRequest := preload("res://addons/godot_agent/completion/completion_request.gd")
const CompletionResult := preload("res://addons/godot_agent/completion/completion_result.gd")
const SuggestionCache := preload("res://addons/godot_agent/completion/suggestion_cache.gd")
const RulesTest := preload("test_completion_rules.gd")

const FIXTURE := "res://tests/completion_fixture"
const NOW := 1_800_000_000.0
## El mismo bloque en varios scripts (línea siguiente, bloques y adaptación).
const READY_BLOCK := "extends Control\n\nfunc _ready() -> void:\n\thealth.changed.connect(_on_health_changed)\n\tvisible = false\n\tif debug:\n\t\tprint(\"ready\")\n\nfunc _on_health_changed(value: int) -> void:\n\t$Bar.value = value\n\t$Label.text = str(value)\n"


## `now` 1.0: antes que cualquier mtime, los archivos cuentan como recién editados.
func _provider(now: float = 1.0) -> LocalProvider:
	var context := ProjectContext.new()
	context.root = FIXTURE
	context.settings_file = FIXTURE + "/project_settings.cfg"
	context.fixed_now = now
	context.build_now()
	return LocalProvider.new(context)


func _complete(provider: LocalProvider, path: String, line: String) -> String:
	var result := provider.complete(RulesTest.request_at(path, line))
	return result.text if result else "<nada>"


func test_line_index() -> void:
	assert_eq(LineIndex.normalize("\t\tvar  x\t:=   1"), "var x := 1", "sin indentación y con espacios colapsados")
	assert_eq(LineIndex.normalize("\tprint(\"a  b\",   'c  \\' d')"), "print(\"a  b\", 'c  \\' d')", "adentro de los strings no colapsa")
	var sequence := LineIndex.lines_of("var a := 1\n\tpass\n\t# nota\n\n\tvar b := 2", 4)
	assert_eq(sequence.lines, PackedStringArray(["var a := 1", "pass", "", ""]), "sin comentarios; la vacía y la del caret cortan")
	assert_eq(sequence.indents, PackedInt32Array([0, 1, -1, -1]), "sangría por línea")
	var index: LineIndex = LineIndex.build({
		"res://a/one.gd": _seq(["health.changed.connect(_on_health_changed)", "health.changed.emit(value)", "var speed := 10"]),
		"res://a/two.gd": _seq(["health.changed.connect(_on_health_changed)"]),
		"res://b/three.gd": _seq(["health.changed.connect(_on_health_changed)", "var speed := 12"]),
	}, {"res://a/one.gd": NOW, "res://a/two.gd": NOW, "res://b/three.gd": NOW - 70 * 86400.0}, NOW)
	assert_eq(index.size(), 4, "líneas únicas")
	var found := index.query("health.changed.c", "res://a/one.gd", 100)
	assert_eq(found.size(), 1, "solo las que empiezan igual")
	assert_eq(found[0].rest, "onnect(_on_health_changed)", "devuelve el resto")
	# mismo archivo 3 + misma carpeta 2 + otra carpeta 1 × recencia vieja (~0.5)
	assert_true(absf(float(found[0].raw) - (3.0 + 2.0 + 0.5)) < 0.01, "cercanía × recencia (%.3f)" % found[0].raw)
	assert_true(absf(float(found[0].evidence) - 6.0) < 0.01, "la evidencia no baja con la edad (%.3f)" % found[0].evidence)
	assert_eq(index.query("health.changed.", "res://c/x.gd", 100).size(), 2, "rango con dos líneas")
	assert_true(index.query("health.changed.", "res://c/x.gd", 1).is_empty(), "más de max_scan: ambiguo, nada")
	assert_true(index.query("var speed := 10", "res://a/one.gd", 100).is_empty(), "la línea completa no se sugiere a sí misma")


static func _seq(lines: Array) -> Dictionary:
	var indents := PackedInt32Array()
	indents.resize(lines.size())
	return {"lines": PackedStringArray(lines), "indents": indents}



func _block_index() -> LineIndex:
	var files := {}
	for path: String in ["res://ui/a.gd", "res://ui/b.gd", "res://other/c.gd"]:
		files[path] = LineIndex.lines_of(READY_BLOCK)
	files["res://other/d.gd"] = LineIndex.lines_of("func _ready() -> void:\n\thealth.changed.connect(_on_health_changed)\n\tset_process(false)\n")
	return LineIndex.build(files, {}, NOW)


func test_next_line_and_blocks() -> void:
	var index := _block_index()
	var next := index.next_lines("func _ready() -> void:", "res://ui/x.gd", 100)
	assert_eq(next.size(), 1, "una sola continuación")
	assert_eq(next[0].text, "health.changed.connect(_on_health_changed)", "la línea que sigue en el corpus")
	assert_eq(next[0].delta, 1, "con un nivel más de sangría")
	var block := index.extend(next[0].positions, 7, 2)
	assert_eq(block.size(), 0, "las apariciones no coinciden en la siguiente: no extiende")
	var handler := index.next_lines("func _on_health_changed(value: int) -> void:", "res://ui/x.gd", 100)
	block = index.extend(handler[0].positions, 7, 2)
	assert_eq(block.size(), 1, "extiende mientras todas coinciden, hasta la línea vacía")
	assert_eq(block[0].text, "$Label.text = str(value)", "la siguiente del bloque")
	assert_eq(block[0].delta, 0, "misma sangría")
	assert_eq(index.extend(handler[0].positions, 7, 4).size(), 0, "sin apoyo suficiente no extiende")
	var visible_line := index.query("visible = f", "res://ui/x.gd", 100)
	var after_visible := index.extend(visible_line[0].positions, 7, 2)
	assert_eq(after_visible.size(), 2, "sigue con un bloque más adentro")
	assert_eq(after_visible[1].delta, 1, "sangría relativa a la primera")
	assert_eq(index.extend(visible_line[0].positions, 1, 2).size(), 1, "respeta el máximo")


func test_identifier_adaptation() -> void:
	assert_eq(LineIndex.substitute("health.changed.connect(_on_health_changed) # HealthBar MAX_HEALTH healthy", "health", "mana"),
		"mana.changed.connect(_on_mana_changed) # ManaBar MAX_MANA healthy", "snake_case, PascalCase y MAYÚSCULAS; no adentro de otra palabra")
	var index := _block_index()
	var adapted := index.adapt("mana.chan", "res://ui/x.gd", 100)
	assert_eq(adapted.size(), 1, "una línea difiere en un identificador")
	assert_eq(adapted[0].rest, "ged.connect(_on_mana_changed)", "la misma sustitución en el resto")
	assert_true(index.adapt("health.chan", "res://ui/x.gd", 100).is_empty(), "el mismo identificador no es adaptación")
	assert_true(index.adapt("mana", "res://ui/x.gd", 100).is_empty(), "el identificador a medio escribir no cuenta")
	assert_true(index.adapt("var x", "res://ui/x.gd", 100).is_empty(), "sin texto después del identificador: nada")


## Proyecto chico con el mismo bloque en tres scripts y el buffer actual en otro.
func _block_provider(indent: String = "\t") -> LocalProvider:
	var root := temp_dir("completion_blocks" if indent == "\t" else "completion_blocks_%d" % indent.length())
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(root.path_join("ui")))
	for name: String in ["a", "b", "c"]:
		var file := FileAccess.open(root.path_join("ui/%s.gd" % name), FileAccess.WRITE)
		file.store_string(READY_BLOCK.replace("\t", indent))
		file.close()
	var context := ProjectContext.new()
	context.root = root
	context.build_now()
	return LocalProvider.new(context)


## Pedido sobre `ui/new.gd` con `text` (el caret en `|`).
func _request(provider: LocalProvider, text: String) -> CompletionRequest:
	var lines := text.split("\n")
	var line := 0
	while not lines[line].contains("|"):
		line += 1
	return CompletionRequest.make(provider.context.root.path_join("ui/new.gd"), text.replace("|", ""), line, lines[line].find("|"))


func test_provider_next_line_blocks_and_adaptation() -> void:
	var provider := _block_provider()
	var result := provider.complete(_request(provider, "extends Control\n\nfunc _on_health_changed(value: int) -> void:\n\t|"))
	assert_eq(result.text if result else "<nada>", "$Bar.value = value\n\t$Label.text = str(value)", "línea siguiente extendida a un bloque")
	provider.max_lines = 1
	result = provider.complete(_request(provider, "extends Control\n\nfunc _on_health_changed(value: int) -> void:\n\t|"))
	assert_eq(result.text if result else "<nada>", "$Bar.value = value", "multilínea apagado: una línea")
	provider.max_lines = 8
	var spaces := _request(provider, "extends Control\n\nfunc _on_health_changed(value: int) -> void:\n    |")
	spaces.indent_spaces = true
	result = provider.complete(spaces)
	assert_eq(result.text if result else "<nada>", "$Bar.value = value\n    $Label.text = str(value)", "con la indentación del editor")
	result = provider.complete(_request(provider, "extends Control\n\nfunc _ready() -> void:\n|"))
	assert_eq(result.text if result else "<nada>", "\thealth.changed.connect(_on_health_changed)\n\tvisible = false\n\tif debug:\n\t\tprint(\"ready\")", "agrega la sangría que falta y sigue con el bloque")
	result = provider.complete(_request(provider, "extends Control\n\nfunc _ready() -> void:\n\tmana.chan|"))
	assert_eq(result.text if result else "<nada>", "ged.connect(_on_mana_changed)", "adapta un identificador")
	result = provider.complete(_request(provider, "extends Control\n\nfunc _ready() -> void:\n\thealth.changed.connect(_on_health_changed)\n\t|\n\tvisible = false"))
	assert_eq(result, null, "no sugiere la línea que ya está debajo")
	# Proyecto con dos espacios por nivel (y el editor igual): bloques y sangrías en esa unidad.
	var two := _block_provider("  ")
	var request := _request(two, "extends Control\n\nfunc _ready() -> void:\n  |")
	request.indent_spaces = true
	request.indent_size = 2
	result = two.complete(request)
	assert_eq(result.text if result else "<nada>", "health.changed.connect(_on_health_changed)\n  visible = false\n  if debug:\n    print(\"ready\")", "dos espacios por nivel")
	request = _request(two, "extends Control\n\nfunc _ready() -> void:\n|")
	request.indent_spaces = true
	request.indent_size = 2
	result = two.complete(request)
	assert_eq((result.text if result else "<nada>").get_slice("\n", 0), "  health.changed.connect(_on_health_changed)", "agrega un nivel de dos espacios")


## Adaptar es para cuando nada empieza así: una línea ya completa o un prefijo ambiguo no se
## reemplazan con la de un pariente (revisión de M8b).
func test_adaptation_only_without_prefix() -> void:
	var root := temp_dir("completion_adapt")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(root.path_join("ui")))
	var sources := {"a": "func f(damage: int) -> void:\n\thealth -= damage\n", "b": "func g(damage: int) -> void:\n\tarmor -= damage * 0.5\n"}
	for name: String in sources:
		var file := FileAccess.open(root.path_join("ui/%s.gd" % name), FileAccess.WRITE)
		file.store_string(sources[name])
		file.close()
	var context := ProjectContext.new()
	context.root = root
	context.build_now()
	var provider := LocalProvider.new(context)
	var result := provider.complete(_request(provider, "func h(damage: int) -> void:\n\thealth -= damage|"))
	assert_eq(result.text if result else "<nada>", "<nada>", "la línea ya está completa: no adapta la del pariente")
	result = provider.complete(_request(provider, "func h(damage: int) -> void:\n\tshield -= dam|"))
	assert_eq(result.text if result else "<nada>", "<nada>", "dos parientes distintos: ambiguo")
	assert_true(context.lines().has_prefix("health -= d") and not context.lines().has_prefix("mana -="), "has_prefix")


## Una línea larguísima (un literal de datos) no se normaliza ni se tokeniza entera en cada tecla
## (revisión de M8b: 20 000 caracteres costaban ~18 ms).
func test_long_lines_stay_cheap() -> void:
	var provider := _provider()
	var data := "const LEVEL := [" + ", ".join(PackedStringArray(range(4000).map(func(i: int) -> String: return str(i)))) + "]"
	var long_prefix := "\tvar level := " + data.substr(16)
	var text := "extends Node\n%s\n%s\n%s\n\tvar x := 1" % [data, data, data]
	var requests: Array[CompletionRequest] = [
		CompletionRequest.make("res://long.gd", text + "\n" + long_prefix, 5, long_prefix.length()),
		CompletionRequest.make("res://long.gd", text + "\n\tvel", 5, 4),
	]
	requests[1].previous_lines = PackedStringArray([data, data, data])
	for request: CompletionRequest in requests:
		var started := Time.get_ticks_usec()
		provider.complete(request)
		var ms := (Time.get_ticks_usec() - started) / 1000.0
		assert_true(ms < 5.0, "%.1f ms con líneas de %d caracteres" % [ms, data.length()])


func test_retrieval_suggests_repeated_line() -> void:
	var provider := _provider()
	var turret := FIXTURE + "/actors/turret.gd"
	var hud := FIXTURE + "/ui/hud.gd"
	var player := FIXTURE + "/actors/player.gd"
	assert_eq(_complete(provider, turret, "\thealth.ch|"), "anged.connect(_on_health_changed)", "línea repetida en el proyecto")
	assert_eq(_complete(provider, hud, "\tvar direction := Input.ge|"), "t_axis(\"move_left\", \"move_right\")", "dos apariciones en otra carpeta alcanzan")
	assert_eq(_complete(provider, hud, "\tvelocity = velocity.mo|"), "ve_toward(Vector2.ZERO, FRICTION * delta)", "una sola aparición en otra carpeta alcanza (D27)")
	assert_eq(_complete(provider, player, "\tvelocity = velocity.mo|"), "ve_toward(Vector2.ZERO, FRICTION * delta)", "en el mismo archivo también")
	# Con todos los archivos de hace años también: la recencia no apaga una sola aparición (m16-07).
	var aged := _provider(Time.get_unix_time_from_system() + 3 * 365 * 86400.0)
	assert_eq(_complete(aged, hud, "\tvelocity = velocity.mo|"), "ve_toward(Vector2.ZERO, FRICTION * delta)", "una sola aparición en un proyecto viejo alcanza")
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


## Post-procesado de una sugerencia para `prefix|suffix`, con `following` debajo.
static func _pp(text: String, prefix: String, suffix: String = "", following: Array = [], max_lines: int = 1, spaces: bool = false, stops: PackedStringArray = []) -> String:
	var request: CompletionRequest = CompletionRequest.from_lines("res://x.gd", "", 0, prefix.length(), prefix + suffix, PackedStringArray(), PackedStringArray(following))
	request.indent_spaces = spaces
	request.indent_size = 4
	return PostProcessor.process(text, request, max_lines, stops)


func test_post_processor() -> void:
	assert_eq(PostProcessor.strip_suffix_overlap("jump\")", "\")"), "jump", "quita el cierre del autocierre")
	assert_eq(PostProcessor.strip_suffix_overlap("bar)", ")  "), "bar", "ignora espacios del suffix")
	assert_eq(PostProcessor.strip_suffix_overlap("x", ")"), "x", "sin solapamiento")
	assert_eq(_pp("bar()", "foo(", ")"), "bar()", "no quita un ) que hace falta para balancear")
	assert_eq(_pp("ok\nsegunda", "", ""), "ok", "una sola línea con max_lines 1")
	assert_eq(_pp("   ", "x", ""), "", "solo espacios: descarta")
	assert_eq(_pp("a))", "f(", ""), "", "cierres de más: descarta")
	assert_eq(_pp("\"sin cerrar", "print(", ")"), "", "string sin cerrar: descarta")
	assert_eq(_pp("ar := {", "var b", ""), "ar := {", "abrir un bloque está bien")
	assert_eq(_pp(".x", ")", ""), ".x", "los cierres del prefix (de líneas de arriba) se toleran")
	assert_true(PostProcessor.balanced("f(\"(\", [1, {2: 3}])  # )"), "ignora strings y comentarios")
	assert_false(PostProcessor.balanced("f(]"), "cierres cruzados")


## Salidas defectuosas reales de modelos FIM y de la recuperación (spec §16.6, §16.9).
func test_post_processor_defective_outputs() -> void:
	assert_eq(_pp("health -= amount<|fim_suffix|>\n\nfunc heal", "\t", "", [], 8), "health -= amount", "token FIM residual (Qwen)")
	assert_eq(_pp("queue_free()<|endoftext|>", "\t", "", [], 8), "queue_free()", "fin de texto")
	assert_eq(_pp("emit_signal(\"died\")<EOT>garbage", "\t", "", [], 8), "emit_signal(\"died\")", "EOT de CodeLlama")
	assert_eq(_pp("x = 1\n\ty = 2\n\nfunc other():", "\t", "", [], 8, false, ["\nfunc "]), "x = 1\n\ty = 2", "stop del perfil")
	assert_eq(_pp("velocity = Vector2.ZERO\n\tmove_and_slide()\nfunc other() -> void:", "\t", "", [], 8), "velocity = Vector2.ZERO\n\tmove_and_slide()", "corta cuando el bloque termina (menos sangría)")
	assert_eq(_pp("a()\n\n\tb()", "\t", "", [], 8), "a()", "una línea vacía termina el bloque")
	assert_eq(_pp("a()\n\tb()\n\tc()\n\td()", "\t", "", [], 3), "a()\n\tb()\n\tc()", "máximo de líneas")
	assert_eq(_pp("\n    if hurt:\n        play_hit()", "func take_damage(amount: int) -> void:", "", [], 8), "\n\tif hurt:\n\t\tplay_hit()", "espacios del modelo a tabs del editor")
	assert_eq(_pp("\n\tif hurt:\n\t\tplay_hit()", "func take_damage(amount: int) -> void:", "", [], 8, true), "\n    if hurt:\n        play_hit()", "tabs a espacios del editor")
	assert_eq(_pp("x = 1\n\treturn value", "\t", "", ["\treturn value"], 8), "x = 1", "corta donde empieza lo que ya está escrito abajo")
	assert_eq(_pp("jump\")\n\tfoo()", "\tif Input.is_action_pressed(\"", "\")", [], 8), "jump", "con cierres a la derecha: una línea, sin repetirlos")
	assert_eq(_pp("foo(\n\tbar))", "\t", "", [], 8), "", "un bloque con cierres de más se descarta")
	assert_eq(_pp("spawn(\n\t\tenemy,\n\t\tposition", "\t", "", [], 8), "spawn(\n\t\tenemy,\n\t\tposition", "un bloque que deja abierta una llamada está bien")
	assert_eq(_pp("pass", "\t", "", ["\tpass"], 8), "", "repite la línea siguiente: descarta")


func test_suggestion_cache() -> void:
	var cache := SuggestionCache.new()
	cache.capacity = 2
	var request: CompletionRequest = CompletionRequest.make("res://x.gd", "var a\nvar b", 1, 5)
	var key := SuggestionCache.key_for(request)
	assert_false(cache.lookup(key).found, "vacía: miss")
	cache.store(key, CompletionResult.make("x", 0.9, "retrieval"))
	var hit := cache.lookup(key)
	assert_true(hit.found and (hit.result as CompletionResult).text == "x", "hit")
	cache.store("nada", null)
	assert_true(cache.lookup("nada").found and cache.lookup("nada").result == null, "guarda que no hubo sugerencia")
	cache.store("otra", null)
	assert_false(cache.lookup(key).found, "LRU: la menos usada sale")
	assert_eq(cache.size(), 2, "acotada")
	assert_eq(cache.hits, 3, "cuenta hits")
	assert_eq(cache.misses, 2, "cuenta misses")
	var changed: CompletionRequest = CompletionRequest.make("res://x.gd", "var a\nvar bb", 1, 5)
	assert_true(SuggestionCache.key_for(changed) != key, "otro texto, otra clave")
	# Lo que cambia fuera del texto (input map, escena abierta, historial) cambia la generación del
	# proveedor, que entra en la clave (revisión de M8b).
	var provider := _provider()
	var before := provider.cache_generation()
	provider.context.settings_changed()
	assert_true(provider.cache_generation() != before, "ProjectSettings cambia la generación")
	before = provider.cache_generation()
	provider.history.record("\tvar mana := 10")
	assert_true(provider.cache_generation() != before, "el historial también")
	assert_true(SuggestionCache.key_for(request, 1) != SuggestionCache.key_for(request, 2), "la generación entra en la clave")


## m14-08: un .cs se completa con las líneas de los .cs del proyecto, nunca con GDScript.
func test_csharp_uses_its_own_lines() -> void:
	var root := temp_dir("completion_csharp")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(root.path_join("scripts")))
	var csharp := "using Godot;\n\npublic partial class Enemy%s : CharacterBody2D\n{\n\t// Sigue al jugador.\n\tpublic override void _PhysicsProcess(double delta)\n\t{\n\t\tVelocity = Velocity.MoveToward(Vector2.Zero, Friction * (float)delta);\n\t\tMoveAndSlide();\n\t}\n}\n"
	for name: String in ["a", "b", "c"]:
		var file := FileAccess.open(root.path_join("scripts/%s.cs" % name), FileAccess.WRITE)
		file.store_string(csharp % name.to_upper())
		file.close()
		var gd := FileAccess.open(root.path_join("scripts/%s.gd" % name), FileAccess.WRITE)
		gd.store_string("extends Node\n\nfunc _physics_process(delta: float) -> void:\n\tvelocity = velocity.move_toward(Vector2.ZERO, friction * delta)\n")
		gd.close()
	var context := ProjectContext.new()
	context.root = root
	context.build_now()
	assert_true(context.lines_for("x.cs").has_prefix("Velocity = Velocity"), "las líneas de C#, en su índice")
	assert_false(context.lines_for("x.cs").has_prefix("velocity = velocity"), "sin GDScript en el de C#")
	assert_false(context.lines_for("x.gd").has_prefix("Velocity = Velocity"), "sin C# en el de GDScript")
	assert_false(context.lines_for("x.cs").has_prefix("// Sigue"), "sin los comentarios //")
	var provider := LocalProvider.new(context)
	var request := CompletionRequest.make(root.path_join("scripts/new.cs"), "using Godot;\n\npublic partial class New : CharacterBody2D\n{\n\tpublic override void _PhysicsProcess(double delta)\n\t{\n\t\tVelocity = Velo\n", 6, 17)
	var result := provider.complete(request)
	var text: String = result.text if result else "<nada>"
	assert_true(text.begins_with("city.MoveToward(Vector2.Zero, Friction * (float)delta);") and text.contains("MoveAndSlide();"), "completa con la línea de C# y la que la sigue · " + text)
	var gd_request := CompletionRequest.make(root.path_join("scripts/new.gd"), "extends Node\n\nfunc _physics_process(delta: float) -> void:\n\tvelocity = velo\n", 3, 16)
	var gd_result := provider.complete(gd_request)
	assert_true(gd_result == null or not gd_result.text.contains("MoveToward"), "un .gd no recibe C#")
