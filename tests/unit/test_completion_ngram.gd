extends "test_case.gd"
## Completado (M8b): lexer GDScript y modelo n-gram (entrenamiento, actualización por archivo y
## generación).

const GdLexer := preload("res://addons/godot_agent/completion/local/gd_lexer.gd")
const NGramModel := preload("res://addons/godot_agent/completion/local/ngram_model.gd")
const ProjectContext := preload("res://addons/godot_agent/completion/project_context.gd")
const LocalProvider := preload("res://addons/godot_agent/completion/local/local_provider.gd")
const CompletionRequest := preload("res://addons/godot_agent/completion/completion_request.gd")

const PLAYER := """extends CharacterBody2D

const SPEED := 200.0 # pixels


func _physics_process(delta: float) -> void:
	var direction := Input.get_axis("move_left", "move_right")
	velocity.x = move_toward(velocity.x, direction * SPEED, delta)
	move_and_slide()
"""


func test_lexer() -> void:
	assert_eq(GdLexer.tokenize_line("\tvar x := foo(1.5, \"a b\") # nota"), PackedStringArray(["var", " x", " :=", " foo", "(", "1.5", ",", " \"a b\"", ")"]), "tokens con su espacio; sin comentario")
	assert_eq(GdLexer.tokenize_line("func f() -> void:"), PackedStringArray(["func", " f", "(", ")", " ->", " void", ":"]), "operadores de dos caracteres")
	assert_eq(GdLexer.tokenize_line("x **= 0x1F + &\"name\" + ^\"path\""), PackedStringArray(["x", " **=", " 0x1F", " +", " &\"name\"", " +", " ^\"path\""]), "hex, StringName y NodePath")
	assert_eq(GdLexer.tokenize_line("print(\"sin cerr"), PackedStringArray(["print", "(", "\"sin cerr"]), "string a medio escribir: un token")
	assert_eq(GdLexer.tokenize_line("var s := \"\"\"uno\"\"\" + x"), PackedStringArray(["var", " s", " :=", " \"\"\"uno\"\"\"", " +", " x"]), "triple comilla en una línea")
	var tokens := GdLexer.tokenize(PLAYER)
	assert_eq(tokens.slice(0, 3), PackedStringArray(["extends", " CharacterBody2D", GdLexer.NEWLINE]), "primera línea")
	var colon := tokens.find(" void") + 1
	assert_eq(tokens[colon], ":", "los dos puntos del func")
	assert_eq(tokens[colon + 1], GdLexer.NEWLINE, "fin de la línea del func")
	assert_eq(tokens[colon + 2], GdLexer.INDENT, "indent al entrar al cuerpo")
	assert_false(tokens.has("# pixels"), "sin comentarios")
	var nested := GdLexer.tokenize("if a:\n\tif b:\n\t\tx()\ny()\n")
	assert_eq(nested.count(GdLexer.DEDENT), 2, "dos dedent al volver dos niveles")
	assert_eq(GdLexer.tokenize("a()\n\"\"\"\ndoc\n\"\"\"\nb()\n"), PackedStringArray(["a", "(", ")", GdLexer.NEWLINE, "\"\"\"", GdLexer.NEWLINE, "b", "(", ")", GdLexer.NEWLINE]), "el interior de un string multilínea no cuenta")
	assert_eq(GdLexer.tokenize("a()\nskip()\nb()\n", 1).count("skip"), 0, "la línea del caret no cuenta")
	assert_eq(GdLexer.tokenize("if a:\n  if b:\n    x()\ny()\n").count(GdLexer.DEDENT), 2, "dos espacios por nivel: mismos dedent")
	assert_eq(GdLexer.spaces_unit(PackedStringArray(["func f():", "  if a:", "    pass", "  # c"])), 2, "unidad del archivo")
	assert_eq(GdLexer.spaces_unit(PackedStringArray(["func f():", "\tpass"])), GdLexer.SPACES_PER_LEVEL, "con tabs, la de siempre")
	var spaced := NGramModel.context_for(PackedStringArray(["func f():", "  pass"]), "  ", 2)
	assert_eq(spaced.context, PackedStringArray(["func", " f", "(", ")", ":", GdLexer.NEWLINE, GdLexer.INDENT, "pass", GdLexer.NEWLINE]), "contexto con el indent entre líneas de arriba, como al entrenar")
	assert_true(GdLexer.is_open_token(" veloc"), "identificador abierto")
	assert_true(GdLexer.is_open_token("\"jum"), "string sin cerrar")
	assert_false(GdLexer.is_open_token("\"jump\""), "string cerrado")
	assert_false(GdLexer.is_open_token("("), "operador")


func _model(copies: int) -> NGramModel:
	var files := {}
	for i in copies:
		files["res://p%d.gd" % i] = GdLexer.tokenize(PLAYER)
	return NGramModel.build(files)


func _generate(model: NGramModel, previous: Array, prefix: String) -> String:
	var input := NGramModel.context_for(PackedStringArray(previous), prefix)
	var generated := model.generate(input.context, input.partial, input.after_space)
	return str(generated.get("text", "<nada>"))


func test_generation() -> void:
	var model := _model(3)
	# Después de `velocity.x` el corpus sigue igual de veces con ` =` y con `,`: ante el empate, para.
	assert_eq(_generate(model, [], "\tvelocity.x = move_t"), "oward(velocity.x", "completa el identificador y sigue hasta la duda")
	assert_eq(_generate(model, [], "\tvelocity.x = "), "move_toward(velocity.x", "después de un espacio, sin repetirlo")
	assert_eq(_generate(model, [], "\tvelocity.x = move_toward(velocity.x, "), "direction * SPEED, delta)", "con contexto que desempata, hasta el fin de línea")
	assert_eq(_generate(model, ["\tvar direction := Input.get_axis(\"move_left\", \"move_right\")"], "\tvelocity"), ".x", "con la línea de arriba como contexto, hasta el empate")
	assert_eq(_generate(model, ["func _physics_process(delta: float) -> void:"], "\t"), "var direction := Input.get_axis(\"move_left\", \"move_right\")", "línea siguiente (indent después del func)")
	assert_eq(_generate(model, [], "\tvar direction := Input.get_axis(\"move_l"), "eft\", \"move_right\")", "completa un string")
	assert_eq(_generate(_model(1), [], "\tvelocity.x = move_t"), "<nada>", "un solo ejemplo: contexto sin soporte")
	assert_eq(_generate(model, [], "\tzzz_unknown."), "<nada>", "contexto desconocido: nada")
	var generated := model.generate(NGramModel.context_for(PackedStringArray(), "\tmove_and_sl").context, "move_and_sl")
	assert_true(bool(generated.complete), "llegó al fin de línea")
	assert_true(float(generated.score) > 0.9, "confianza alta en lo que siempre se repite (%.2f)" % generated.score)


func test_incremental_update() -> void:
	var files := {}
	for i in 10:
		files["res://p%d.gd" % i] = GdLexer.tokenize(PLAYER)
	var model := NGramModel.build(files)
	var words_before: int = model.words.size()
	var updated_files := files.duplicate()
	updated_files["res://p0.gd"] = GdLexer.tokenize(PLAYER.replace("move_and_slide()", "move_and_collide(velocity)"))
	updated_files.erase("res://p1.gd")
	var incremental := NGramModel.build(updated_files, model)
	var full := NGramModel.build(updated_files)
	assert_eq(incremental.token_count, full.token_count, "mismos tokens")
	var same := true
	for key: int in full.counts:
		var expected: Dictionary = full.counts[key]
		var translated := {}
		for id: int in expected:
			translated[full.words[id]] = expected[id]
		var actual := {}
		var key_words := []
		# La clave usa ids, que dependen del orden de entrenamiento: se compara por texto.
		var found := false
		for other_key: int in incremental.counts:
			if _key_text(incremental, other_key) == _key_text(full, key):
				found = true
				for id: int in incremental.counts[other_key]:
					actual[incremental.words[id]] = incremental.counts[other_key][id]
				break
		if not found or actual != translated:
			same = false
			break
	assert_true(same, "actualizar por archivo da lo mismo que reentrenar")
	assert_eq(incremental.counts.size(), full.counts.size(), "mismos contextos")
	assert_true(model.counts.size() > 0 and NGramModel.build(files, model) == model, "sin cambios devuelve el mismo modelo")
	# El modelo anterior no se tocó (el hilo principal lo puede estar leyendo).
	assert_eq(model.token_count, NGramModel.build(files).token_count, "el anterior queda intacto")
	assert_eq(model.words.size(), words_before, "el vocabulario del anterior no crece (el worker no escribe en lo publicado)")
	assert_true(incremental.words.size() > words_before, "el nuevo tiene los tokens nuevos")
	assert_eq(_generate(model, [], "\tmove_and_s"), "lide()", "el anterior sigue generando lo suyo")


static func _key_text(model: NGramModel, key: int) -> String:
	var length := key >> 60
	var parts := PackedStringArray()
	for k in length:
		parts.append(model.words[(key >> (20 * k)) & 0xFFFFF])
	return "|".join(parts)


func test_provider_uses_ngram() -> void:
	var root := temp_dir("completion_ngram")
	for i in 3:
		var file := FileAccess.open(root.path_join("p%d.gd" % i), FileAccess.WRITE)
		# Cada archivo con su velocidad: la línea entera no se repite, la estructura sí.
		file.store_string(PLAYER.replace("direction * SPEED", "direction * SPEED * %d" % (i + 2)))
		file.close()
	var context := ProjectContext.new()
	context.root = root
	context.build_now()
	assert_true(context.ngram().token_count > 0, "el índice entrena el n-gram")
	var provider := LocalProvider.new(context)
	var request: CompletionRequest = CompletionRequest.make(root.path_join("new.gd"), "extends Node\n\nfunc f(delta: float) -> void:\n\tspeed.x = move_toward(speed.x, 0, delta)\n\tmove_and_sl", 4, 13)
	var result := provider.complete(request)
	assert_eq(result.text if result else "<nada>", "ide()", "sugiere desde el n-gram")
	provider.sources[LocalProvider.SOURCE_NGRAM] = false
	provider.sources[LocalProvider.SOURCE_RETRIEVAL] = false
	assert_eq(provider.complete(request), null, "con la fuente apagada, nada")
