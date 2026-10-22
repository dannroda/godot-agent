extends "test_case.gd"
## Completado (M8c): formato de cada endpoint LLM, contexto del proyecto con presupuesto y el
## proveedor contra un server HTTP falso (respuesta, cancelación, errores).

const LlmProfile := preload("res://addons/godot_agent/completion/llm/llm_profile.gd")
const LlmClient := preload("res://addons/godot_agent/completion/llm/llm_client.gd")
const LlmContext := preload("res://addons/godot_agent/completion/llm/llm_context.gd")
const LlmProvider := preload("res://addons/godot_agent/completion/llm/llm_provider.gd")
const ProjectContext := preload("res://addons/godot_agent/completion/project_context.gd")
const CompletionRequest := preload("res://addons/godot_agent/completion/completion_request.gd")
const CompletionResult := preload("res://addons/godot_agent/completion/completion_result.gd")
const FakeLlmServer := preload("res://tests/fake_llm_server.gd")

const FIXTURE := "res://tests/completion_fixture"
const PLAYER := FIXTURE + "/actors/player.gd"
const KEY_ENV := "GODOT_AGENT_TEST_LLM_KEY"


func _profile(kind: String, url: String = "http://127.0.0.1:1") -> LlmProfile:
	var profile: LlmProfile = LlmProfile.make(kind)
	profile.url = url
	profile.api_key_env = KEY_ENV
	return profile


func test_profiles() -> void:
	var profile: LlmProfile = LlmProfile.from_dict({"kind": "codestral", "id": "c", "stops": ["\n\n", ""], "temperature": 9, "max_tokens": 1})
	assert_eq(profile.url, "https://api.mistral.ai", "url por defecto del tipo")
	assert_eq(profile.stops, PackedStringArray(["\n\n"]), "stops sin vacíos")
	assert_eq([profile.temperature, profile.max_tokens], [2.0, 8], "valores acotados")
	assert_true(profile.is_remote(), "codestral es remoto")
	assert_false(LlmProfile.make("ollama").is_remote(), "ollama en 127.0.0.1 es local")
	assert_false(_profile("openai", "http://localhost:1234/").is_remote(), "localhost es local")
	assert_false(_profile("openai", "http://[::1]:1234/v1").is_remote(), "[::1] con puerto es local")
	assert_true(_profile("openai", "http://192.168.1.20:1234").is_remote(), "otra máquina de la red es remota")
	assert_true(LlmProfile.make("gemini").is_experimental(), "gemini es experimental")
	var hand_edited: LlmProfile = LlmProfile.from_dict({"kind": "ollama", "id": "o", "temperature": null, "max_tokens": [1]})
	assert_true(hand_edited != null and hand_edited.max_tokens == LlmProfile.make("ollama").max_tokens, "números de otro tipo: el default, sin romper")
	assert_true(LlmProfile.make("codestral").needs_key() and not LlmProfile.make("llamacpp").needs_key(), "qué tipos necesitan key")
	assert_eq(LlmProfile.from_dict(profile.to_dict()).to_dict(), profile.to_dict(), "ida y vuelta")
	assert_false(profile.to_dict().has("api_key"), "la key nunca se guarda")
	var raw: LlmProfile = LlmProfile.make("openai")
	raw.fim_template = LlmProfile.QWEN_FIM
	assert_true(raw.all_stops().has("<|endoftext|>"), "la plantilla de Qwen suma sus stops")


func test_build_requests() -> void:
	OS.set_environment(KEY_ENV, "sk-test")
	var built := LlmClient.build(_profile("ollama"), "func f():\n\tpri", "\n", "# ctx\n")
	var body: Dictionary = JSON.parse_string(built.body)
	assert_eq(built.url, "http://127.0.0.1:1/api/generate", "ollama: endpoint")
	assert_eq([body.prompt, body.suffix, body.stream, body.model], ["# ctx\nfunc f():\n\tpri", "\n", false, "qwen2.5-coder:1.5b-base"], "ollama: FIM nativo con prompt y suffix")
	assert_eq(int(body.options.num_predict), 96, "ollama: num_predict")
	var templated: LlmProfile = _profile("ollama")
	templated.fim_template = LlmProfile.QWEN_FIM
	body = JSON.parse_string(LlmClient.build(templated, "a", "b").body)
	assert_eq([body.prompt, body.get("raw"), body.has("suffix")], ["<|fim_prefix|>a<|fim_suffix|>b<|fim_middle|>", true, false], "ollama: plantilla en crudo")
	built = LlmClient.build(_profile("llamacpp"), "pre", "suf", "# ctx\n")
	body = JSON.parse_string(built.body)
	assert_eq(built.url, "http://127.0.0.1:1/infill", "llama.cpp: endpoint")
	assert_eq([body.input_prefix, body.input_suffix, body.input_extra[0].text], ["pre", "suf", "# ctx\n"], "llama.cpp: contexto en input_extra, no en el prefix")
	built = LlmClient.build(_profile("codestral", "https://api.mistral.ai/"), "pre", "suf")
	body = JSON.parse_string(built.body)
	assert_eq(built.url, "https://api.mistral.ai/v1/fim/completions", "codestral: endpoint")
	assert_eq([body.model, body.prompt, body.suffix], ["codestral-latest", "pre", "suf"], "codestral: prompt y suffix")
	assert_true(built.headers.has("Authorization: Bearer sk-test"), "codestral: key del entorno")
	var openai: LlmProfile = _profile("openai")
	body = JSON.parse_string(LlmClient.build(openai, "pre", "suf").body)
	assert_eq([body.prompt, body.has("suffix"), (body.stop as Array).size()], ["<|fim_prefix|>pre<|fim_suffix|>suf<|fim_middle|>", false, 4], "openai: plantilla de Qwen por defecto, sin suffix, hasta 4 stops")
	openai.fim_template = ""
	body = JSON.parse_string(LlmClient.build(openai, "pre", "suf").body)
	assert_eq([body.prompt, body.suffix], ["pre", "suf"], "openai sin plantilla: suffix")
	built = LlmClient.build(_profile("gemini", "https://generativelanguage.googleapis.com"), "pre", "suf")
	body = JSON.parse_string(built.body)
	assert_eq(built.url, "https://generativelanguage.googleapis.com/v1beta/models/gemini-3.5-flash-lite:generateContent", "gemini: endpoint")
	assert_eq(body.contents[0].parts[0].text, "pre<CURSOR>suf", "gemini: marcador del cursor")
	assert_true(built.headers.has("x-goog-api-key: sk-test"), "gemini: key en header, no en la URL")
	OS.unset_environment(KEY_ENV)
	assert_eq(Array(LlmClient.build(_profile("codestral"), "a", "b").headers).filter(func(h: String) -> bool: return h.begins_with("Authorization")), [], "sin variable, sin header")


func test_parse_responses() -> void:
	assert_eq(LlmClient.parse("ollama", 200, "{\"response\": \"nt()\", \"done\": true}"), {"text": "nt()"}, "ollama")
	assert_eq(LlmClient.parse("llamacpp", 200, "{\"content\": \"x\"}"), {"text": "x"}, "llama.cpp")
	assert_eq(LlmClient.parse("codestral", 200, "{\"choices\": [{\"message\": {\"content\": \"y\"}}]}"), {"text": "y"}, "codestral")
	assert_eq(LlmClient.parse("openai", 200, "{\"choices\": [{\"text\": \"z\"}]}"), {"text": "z"}, "openai")
	assert_eq(LlmClient.parse("gemini", 200, "{\"candidates\": [{\"content\": {\"parts\": [{\"text\": \"```gdscript\\nprint(1)\\n```\"}]}}]}"), {"text": "print(1)"}, "gemini sin fences")
	assert_eq(LlmClient.parse("gemini", 200, "{\"promptFeedback\": {\"blockReason\": \"OTHER\"}}"), {"text": ""}, "gemini bloqueado: sin sugerencia")
	assert_eq(LlmClient.parse("ollama", 404, "{\"error\": \"model 'x' not found\"}"), {"error": "HTTP 404: model 'x' not found"}, "error de ollama")
	assert_eq(LlmClient.parse("gemini", 400, "{\"error\": {\"message\": \"API key not valid\"}}"), {"error": "HTTP 400: API key not valid"}, "error de gemini")
	assert_true(LlmClient.parse("openai", 200, "<html>").has("error"), "no JSON")
	var echoed := LlmClient.parse("openai", 422, "{\"detail\": [{\"msg\": \"Field required\", \"input\": {\"prompt\": \"func secreto()\"}}]}")
	assert_eq(echoed, {"error": "HTTP 422: Field required"}, "un 422 de FastAPI: el msg, sin el prompt que repite")
	assert_eq(LlmClient.parse("openai", 500, "func secreto(): eco del prompt"), {"error": "HTTP 500"}, "un body desconocido no va al error")


func test_split_and_context() -> void:
	var request: CompletionRequest = CompletionRequest.make("res://a.gd", "uno\ndos\ntres x\ncuatro\ncinco", 2, 5)
	var parts := LlmProvider.split(request, 100, 100)
	assert_eq([parts.prefix, parts.suffix], ["uno\ndos\ntres ", "x\ncuatro\ncinco"], "prefix y suffix completos")
	parts = LlmProvider.split(request, 9, 9)
	assert_eq([parts.prefix, parts.suffix], ["tres ", "x\ncuatro\n"], "recortados a líneas enteras")
	var at_end: CompletionRequest = CompletionRequest.make("res://a.gd", "abc\n" + "x".repeat(50), 0, 3)
	assert_eq(LlmProvider.split(at_end, 100, 10).suffix, "\n", "caret al final de la línea: sin media línea siguiente")
	var context := ProjectContext.new()
	context.root = FIXTURE
	context.settings_file = FIXTURE + "/project_settings.cfg"
	context.build_now()
	var text := FileAccess.get_file_as_string(PLAYER) + "\nvar e: FixtureEnemy\n"
	var full := LlmContext.render(context, PLAYER, text, 2000)
	assert_true(full.contains("#   $Sprite2D: Sprite2D") or full.contains("#   $Sprite2D"), "nodos del script")
	assert_true(full.contains("# Base class:\n#   CharacterBody2D"), "clase base")
	assert_true(full.contains("FixtureEnemy extends"), "clases del proyecto que nombra")
	assert_true(full.contains("Events (res://tests/completion_fixture/events.gd)"), "autoloads")
	assert_true(full.contains("#   jump") and not full.contains("ui_cancel"), "acciones propias, sin las ui_*")
	var small := LlmContext.render(context, PLAYER, text, 10)
	assert_true(small.length() <= 40 and small.begins_with("# Nodes"), "presupuesto chico: solo lo primero (%d)" % small.length())
	assert_eq(LlmContext.render(context, PLAYER, text, 0), "", "presupuesto 0: nada")


func test_provider_with_fake_server() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	await tree.process_frame
	OS.set_environment(KEY_ENV, "sk-test")
	var server: FakeLlmServer = FakeLlmServer.new()
	tree.root.add_child(server)
	assert_eq(server.start(), OK, "server falso escuchando")
	server.routes["/api/generate"] = {"body": {"response": "nt(\"hola\")\n\nfunc other() -> void:", "done": true}}
	var provider: LlmProvider = LlmProvider.new(tree.root, _profile("ollama", server.url()))
	provider.context_budget = 0
	var request: CompletionRequest = CompletionRequest.make("res://a.gd", "func f() -> void:\n\tpri\n", 1, 4)
	var result: CompletionResult = await provider.complete(request)
	assert_eq(result.text if result else "<nada>", "nt(\"hola\")", "texto del modelo recortado al bloque")
	assert_eq(result.source if result else "", "llm", "fuente llm")
	assert_eq(provider.last_error, "", "sin error")
	assert_eq(server.requests.size(), 1, "un pedido")
	var body: Dictionary = server.requests[0].body
	assert_eq([body.prompt, body.suffix], ["func f() -> void:\n\tpri", "\n"], "prefix y suffix del buffer")
	assert_eq(provider.last_output_chars, 33, "tamaño de salida para el log")

	# Cancelación: un pedido lento se corta y no devuelve nada; el siguiente funciona.
	server.routes["/api/generate"] = {"body": {"response": "lento"}, "delay_ms": 3000}
	var started := Time.get_ticks_msec()
	var slow := [null, false]
	var waiter := func() -> void:
		slow[0] = await provider.complete(request)
		slow[1] = true
	waiter.call()
	await tree.create_timer(0.2).timeout
	assert_true(provider.is_busy(), "en vuelo")
	provider.cancel()
	await tree.process_frame
	assert_true(slow[1] and slow[0] == null, "cancelado: null")
	assert_true(Time.get_ticks_msec() - started < 1500, "sin esperar al server")
	server.routes["/api/generate"] = {"body": {"response": "nt(1)"}}
	result = await provider.complete(request)
	assert_eq(result.text if result else "<nada>", "nt(1)", "después de cancelar, el HTTPRequest se reutiliza")

	# Errores: el status y el mensaje del server, o la conexión.
	server.routes["/api/generate"] = {"status": 404, "body": {"error": "model 'x' not found"}}
	assert_eq(await provider.complete(request), null, "error: sin sugerencia")
	assert_eq(provider.last_error, "HTTP 404: model 'x' not found", "error del server")
	provider.profile = _profile("ollama", "http://127.0.0.1:1")
	assert_eq(await provider.complete(request), null, "sin server: sin sugerencia")
	assert_eq(provider.last_error, "could not connect", "error de conexión")
	var keyed := _profile("codestral", server.url())
	keyed.api_key_env = "GODOT_AGENT_TEST_UNSET_KEY_VAR"
	provider.profile = keyed
	var sent := server.requests.size()
	assert_eq(await provider.complete(request), null, "sin la key: sin sugerencia")
	assert_true(provider.last_error.contains("GODOT_AGENT_TEST_UNSET_KEY_VAR") and server.requests.size() == sent, "sin la key no se manda nada")
	keyed.api_key_env = ""
	assert_eq(await provider.complete(request), null, "codestral sin variable: sin sugerencia")
	assert_eq(server.requests.size(), sent, "y sin pedido")
	assert_eq((provider.get(&"_http") as HTTPRequest).max_redirects, 0, "no sigue redirecciones (reenviarían código y key)")
	provider.release()
	server.queue_free()
	OS.unset_environment(KEY_ENV)
	await tree.process_frame
